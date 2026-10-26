import pg from 'pg';
import type {Ingest} from './server.ts';

export function createDatabase(host: string,password: string) {
  const pool=new pg.Pool({host,port:5432,database:'incidents',user:'incident_ingest',password,
    ssl:false,max:4,connectionTimeoutMillis:3000,idleTimeoutMillis:10000,
    statement_timeout:5000,query_timeout:5500,application_name:'secureops-incident-receiver'});
  // Erro de conexão idle não deve derrubar processo nem imprimir mensagem do driver.
  pool.on('error',()=>{});
  const ingest: Ingest=async(body,signal)=>{
    const client=await pool.connect();let discard=false;
    const abort=()=>{discard=true;client.release(true);};
    if(signal.aborted){client.release(true);throw new Error('unavailable');}
    signal.addEventListener('abort',abort,{once:true});
    try{
      // pg só resolve o comando após ReadyForQuery/autocommit; não ACK em CommandComplete parcial.
      const result=await client.query({text:'SELECT incident.ingest($1) AS outcome',values:[body]});
      if(signal.aborted)throw new Error('unavailable');
      return result.rows[0]?.outcome?.result ?? 'unavailable';
    }catch{discard=true;throw new Error('unavailable');}
    finally{
      signal.removeEventListener('abort',abort);
      // Abort já devolveu/destruiu o client; nunca devolver conexão com query ainda em andamento.
      if(!signal.aborted)client.release(discard);
    }
  };
  return {ingest,close:()=>pool.end()};
}
