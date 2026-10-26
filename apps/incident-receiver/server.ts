import {createServer, type IncomingMessage, type ServerResponse} from 'node:http';
import {timingSafeEqual} from 'node:crypto';

export type Ingest = (body: string, signal: AbortSignal) => Promise<string>;
type Options = {key: string; ingest: Ingest; log?: (entry: object) => void; deadlineMs?: number; bodyTimeoutMs?: number};
const statuses: Record<string, number> = {applied:200, duplicate:200, pending:200, invalid:400, conflict:409};
class InputError extends Error {
  status: number;
  constructor(status: number) {super('invalid'); this.status=status;}
}

function readBody(req: IncomingMessage, signal: AbortSignal, timeout: number): Promise<string> {
  return new Promise((resolve,reject)=>{
    let size=0; const chunks: Buffer[]=[];
    const timer=setTimeout(()=>finish(new InputError(400)),timeout);
    const abort=()=>finish(new InputError(503));
    const data=(chunk: Buffer)=>{
      size+=chunk.length;
      if(size>4096){finish(new InputError(413));return;}
      chunks.push(chunk);
    };
    const end=()=>{
      try{finish(undefined,new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));}
      catch{finish(new InputError(400));}
    };
    const failed=()=>finish(new InputError(400));
    function finish(error?: Error, body?: string) {
      clearTimeout(timer);req.pause();req.off('data',data);req.off('end',end);
      req.off('aborted',failed);req.off('error',failed);signal.removeEventListener('abort',abort);
      if(error)reject(error);else resolve(body ?? '');
    }
    req.on('data',data);req.once('end',end);req.once('aborted',failed);req.once('error',failed);
    signal.addEventListener('abort',abort,{once:true});
    if(signal.aborted)abort();
  });
}

export function createReceiver({key,ingest,log=()=>{},deadlineMs=10000,bodyTimeoutMs=5000}: Options) {
  if(!/^[a-f0-9]{64}$/.test(key))throw new Error('invalid_configuration');
  const expected=Buffer.from(key,'ascii'); let active=0;
  const server=createServer({maxHeaderSize:8192,headersTimeout:5000,requestTimeout:5000,
    connectionsCheckingInterval:1000,keepAliveTimeout:1000},(req,res)=>{void handle(req,res);});
  server.maxConnections=64;server.maxHeadersCount=32;server.maxRequestsPerSocket=50;
  server.on('clientError',(_error,socket)=>{
    // Nunca imprimir error.message/rawPacket, que podem conter entrada do chamador.
    if(socket.writable)socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
  });
  server.on('checkContinue',(req,res)=>{req.pause();res.writeHead(400,{'Connection':'close'});res.end();});

  async function handle(req: IncomingMessage,res: ServerResponse) {
    const started=performance.now();const controller=new AbortController();
    req.on('error',()=>controller.abort());res.on('error',()=>controller.abort());
    let finished=false, admitted=false;
    const reply=(status: number,result: string)=>{
      if(finished)return;finished=true;clearTimeout(deadline);
      req.pause();res.shouldKeepAlive=false;
      if(!res.destroyed){res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store','Connection':'close'});res.end(JSON.stringify({result}));}
      log({status,result,duration_ms:Math.round(performance.now()-started)});
    };
    const deadline=setTimeout(()=>{reply(503,'unavailable');controller.abort();},deadlineMs);
    const disconnected=()=>{if(!res.writableFinished){controller.abort();}};
    res.once('close',disconnected);
    try{
      if(req.url==='/health'&&req.method==='GET'){reply(200,'alive');return;}
      if(req.url!=='/v1/events'){reply(404,'invalid');return;}
      if(req.method!=='POST'){reply(405,'invalid');return;}
      const supplied=req.headersDistinct['x-secureops-webhook-key'];
      if(supplied?.length!==1||!/^[a-f0-9]{64}$/.test(supplied[0] ?? '')||
        !timingSafeEqual(expected,Buffer.from(supplied[0]!,'ascii'))){reply(401,'unauthorized');return;}
      const types=req.headersDistinct['content-type'];
      if(types?.length!==1||!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(types[0] ?? '')||
        req.headers['content-encoding']!==undefined){reply(415,'invalid');return;}
      if(req.headers['content-length']!==undefined && Number(req.headers['content-length'])>4096){reply(413,'invalid');return;}
      if(active>=32){reply(503,'unavailable');return;}
      active++;admitted=true;
      const body=await readBody(req,controller.signal,bodyTimeoutMs);
      if(controller.signal.aborted)throw new Error('aborted');
      // O texto original chega ao parser SQL; JSON.parse/serialização aqui perderiam duplicatas.
      const result=await ingest(body,controller.signal);
      if(controller.signal.aborted)throw new Error('aborted');
      const status=statuses[result];
      if(status===undefined){reply(503,'unavailable');return;}
      reply(status,result);
    }catch(error){
      if(error instanceof InputError)reply(error.status,error.status===503?'unavailable':'invalid');
      else reply(503,'unavailable');
    }finally{
      clearTimeout(deadline);res.off('close',disconnected);
      if(admitted)active--;
    }
  }
  return server;
}
