import {test} from 'node:test';
import assert from 'node:assert/strict';
import {request} from 'node:http';
import {createConnection} from 'node:net';
import {once} from 'node:events';
import {randomBytes} from 'node:crypto';
import {createReceiver} from '../server.ts';

const key=randomBytes(32).toString('hex');
async function fixture(t,ingest=async()=> 'applied',options={}){
  const logs=[];const server=createReceiver({key,ingest,log:e=>logs.push(e),...options});
  server.listen(0,'127.0.0.1');await once(server,'listening');
  t.after(()=>new Promise(resolve=>{server.closeAllConnections();server.close(resolve);}));
  const port=server.address().port;
  const post=(body='{}',headers={},path='/v1/events',method='POST')=>new Promise((resolve,reject)=>{
    const req=request({host:'127.0.0.1',port,path,method,headers:{'Content-Type':'application/json','X-SecureOps-Webhook-Key':key,...headers}},res=>{
      let text='';res.on('data',c=>text+=c);res.on('end',()=>resolve({status:res.statusCode,value:text?JSON.parse(text):null}));
    });req.on('error',reject);req.end(body);
  });
  return {server,port,post,logs};
}
test('configuração falha fechada',()=>{assert.throws(()=>createReceiver({key:'invalid',ingest:async()=> 'applied'}));});
test('health é liveness sem consultar banco',async t=>{
  const f=await fixture(t,async()=>{throw Error('must_not_call');});
  assert.deepEqual(await f.post('',{},'/health','GET'),{status:200,value:{result:'alive'}});
});
for(const [name,headers,status] of [
  ['header ausente',{'X-SecureOps-Webhook-Key':''},401],
  ['header errado',{'X-SecureOps-Webhook-Key':randomBytes(32).toString('hex')},401],
  ['header repetido',{'X-SecureOps-Webhook-Key':[key,key]},401],
  ['tipo incorreto',{'Content-Type':'text/plain'},415],
  ['compressão proibida',{'Content-Encoding':'gzip'},415],
  ['charset indevido',{'Content-Type':'application/json; charset=latin1'},415],
])test(name,async t=>{
  let calls=0;const f=await fixture(t,async()=>{calls++;return 'applied';});
  assert.equal((await f.post('{"sensitive":"not_saved"}',headers)).status,status);assert.equal(calls,0);
});
test('caminho/query/método não aceitos',async t=>{
  const f=await fixture(t);assert.equal((await f.post('{}',{},'/other')).status,404);
  assert.equal((await f.post('{}',{},'/v1/events?secret=never-log')).status,404);
  assert.equal((await f.post('{}',{},'/v1/events','PUT')).status,405);
  assert.ok(!JSON.stringify(f.logs).includes('never-log'));
});
test('autenticação recusa antes de aguardar corpo declarado',async t=>{
  const f=await fixture(t);const s=createConnection(f.port,'127.0.0.1');t.after(()=>s.destroy());
  await once(s,'connect');s.write('POST /v1/events HTTP/1.1\r\nHost: fixture\r\nContent-Length: 999999\r\n\r\n');
  const [response]=await once(s,'data');assert.match(response.toString(),/^HTTP\/1.1 401/);
});
test('texto original e chaves duplicadas chegam intactos ao SQL',async t=>{
  const raw=' {"host":"one","host":"two"} ';
  const f=await fixture(t,async body=>{assert.equal(body,raw);return 'invalid';});
  assert.deepEqual(await f.post(raw),{status:400,value:{result:'invalid'}});
});
for(const [result,status] of [['applied',200],['duplicate',200],['pending',200],['conflict',409],['invalid',400],['unexpected',503]])
test('resposta '+result,async t=>{
  const f=await fixture(t,async()=>result);const r=await f.post();assert.equal(r.status,status);
  if(status===503)assert.deepEqual(r.value,{result:'unavailable'});
});
test('4096 bytes aceitos; 4097 declarados/chunked recusados antes do SQL',async t=>{
  let calls=0;const f=await fixture(t,async body=>{calls++;assert.equal(Buffer.byteLength(body),4096);return 'invalid';});
  assert.equal((await f.post(' '.repeat(4096))).status,400);
  assert.equal((await f.post(' '.repeat(4097))).status,413);
  assert.equal((await f.post(' '.repeat(4097),{'Transfer-Encoding':'chunked'})).status,413);
  assert.equal(calls,1);
});
test('UTF-8 inválido não chega ao SQL',async t=>{
  let calls=0;const f=await fixture(t,async()=>{calls++;return 'applied';});
  assert.equal((await f.post(Buffer.from([0xc3,0x28]))).status,400);assert.equal(calls,0);
});
test('UTF-8 fragmentado é reunido antes de decodificar',async t=>{
  const f=await fixture(t,async body=>{assert.equal(body,'{"x":"ação"}');return 'invalid';});
  const bytes=Buffer.from('{"x":"ação"}');
  const result=await new Promise((resolve,reject)=>{
    const r=request({host:'127.0.0.1',port:f.port,path:'/v1/events',method:'POST',headers:{'Content-Type':'application/json; charset=utf-8','X-SecureOps-Webhook-Key':key}},res=>{res.resume();res.on('end',()=>resolve(res.statusCode));});
    r.on('error',reject);for(const byte of bytes)r.write(Buffer.from([byte]));r.end();
  });assert.equal(result,400);
});
test('não confirma enquanto persistência não resolver',async t=>{
  let commit;const f=await fixture(t,()=>new Promise(resolve=>{commit=resolve;}));
  let settled=false;const pending=f.post().then(r=>{settled=true;return r;});
  while(!commit)await new Promise(resolve=>setTimeout(resolve,5));
  assert.equal(settled,false);commit('applied');assert.equal((await pending).status,200);
});
test('erro do banco sanitizado; nunca loga stack, header ou corpo',async t=>{
  const secret='sensitive-'+key;const f=await fixture(t,async()=>{throw Error(secret);});
  assert.deepEqual(await f.post(secret),{status:503,value:{result:'unavailable'}});
  const output=JSON.stringify(f.logs);assert.ok(!output.includes(secret)&&!output.includes(key));
  assert.deepEqual(Object.keys(f.logs[0]).sort(),['duration_ms','result','status']);
});
test('deadline aborta operação e não aceita resultado tardio',async t=>{
  let aborted=false;const f=await fixture(t,(_body,signal)=>new Promise(resolve=>{
    signal.addEventListener('abort',()=>{aborted=true;resolve('applied');});
  }),{deadlineMs:50});
  assert.deepEqual(await f.post(),{status:503,value:{result:'unavailable'}});assert.equal(aborted,true);
  assert.equal(f.logs.length,1);
});
test('conexão abortada cancela operação pendente',async t=>{
  let entered,aborted;const seen=new Promise(r=>entered=r),cancelled=new Promise(r=>aborted=r);
  const f=await fixture(t,(_body,signal)=>new Promise(resolve=>{entered();signal.addEventListener('abort',()=>{aborted();resolve('applied');});}));
  const r=request({host:'127.0.0.1',port:f.port,path:'/v1/events',method:'POST',headers:{'Content-Type':'application/json','X-SecureOps-Webhook-Key':key}});
  r.on('error',()=>{});r.end('{}');await seen;r.destroy();await cancelled;
});
test('corpo incompleto tem limite de tempo',async t=>{
  const f=await fixture(t,async()=> 'applied',{bodyTimeoutMs:50});
  const s=createConnection(f.port,'127.0.0.1');t.after(()=>s.destroy());await once(s,'connect');
  s.write(`POST /v1/events HTTP/1.1\r\nHost: fixture\r\nContent-Type: application/json\r\nX-SecureOps-Webhook-Key: ${key}\r\nContent-Length: 100\r\n\r\n{`);
  const [r]=await once(s,'data');assert.match(r.toString(),/^HTTP\/1.1 400/);
});
