import {readFileSync} from 'node:fs';
import {createReceiver} from './server.ts';
import {createDatabase} from './database.ts';

try{
  const key=readFileSync('/run/secrets/automation-webhook-key','utf8').trim();
  const password=readFileSync('/run/secrets/automation-incident-ingest','utf8').trim();
  const host=process.env.INCIDENT_DB_HOST ?? 'automation-db';
  if(!/^[a-f0-9]{64}$/.test(password)||!/^[a-z0-9][a-z0-9.-]{0,62}$/.test(host))throw new Error('invalid_configuration');
  const database=createDatabase(host,password);
  const server=createReceiver({key,ingest:database.ingest,log:entry=>console.log(JSON.stringify(entry))});
  server.on('error',()=>{console.error('receiver_listener_failed');process.exitCode=1;void database.close();});
  server.listen(3000,'0.0.0.0');
  const stop=()=>{
    const timeout=setTimeout(()=>process.exit(1),10000);timeout.unref();
    server.close(()=>{void database.close().then(()=>{clearTimeout(timeout);process.exit(0);});});
  };
  process.once('SIGTERM',stop);process.once('SIGINT',stop);
}catch{console.error('receiver_configuration_invalid');process.exitCode=1;}
