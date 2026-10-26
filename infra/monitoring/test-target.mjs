// Alvo FICTICIO efemero, sem portas/dados do lab; chave efemera propria.
// Nao faz parte da API nem do runtime do coletor.
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
export function createTestTarget(key) {
assert.match(key,/^[a-f0-9]{64}$/);
let mode = 'failure';
const modes = ['failure','valid0','valid5','http403','http500','invalidjson','stale','events_disabled','event_limit','provider_auth'];
const server=createServer(async (req,res) => {
  if (req.method === 'POST' && req.url === '/control') {
    if(req.headers['x-secureops-metrics-key']!==key){res.writeHead(401).end();return;}
    let body='';
    for await (const chunk of req) { body+=chunk; if(body.length>128){res.writeHead(413).end();return;} }
    if(!modes.includes(body)){res.writeHead(400).end();return;}
    mode=body; res.writeHead(204).end(); return;
  }
  if(req.method!=='GET'){res.writeHead(405).end();return;}
  if(req.url==='/500'){res.writeHead(500).end('fictitious');return;}
  if(req.url==='/redirect'){res.writeHead(302,{Location:'/ok'}).end();return;}
  if(req.url==='/ok'){res.writeHead(200).end('fictitious');return;}
  if(req.url!=='/metrics'){res.writeHead(404).end();return;}
  if(req.headers['x-secureops-metrics-key']!==key){res.writeHead(401).end();return;}
  if(mode==='http403'){res.writeHead(403).end();return;}
  if(mode==='http500'){res.writeHead(500).end();return;}
  if(mode==='invalidjson'){res.writeHead(200).end('not-json');return;}
  const sample={contract_version:1,realm:'secureops-lab',client:'secureops-gateway',window_seconds:300,sampled_at:Date.now()};
  if(mode==='stale'){sample.sampled_at=0;}
  if(['valid0','valid5','stale'].includes(mode)){sample.collection_ok=1;sample.login_errors_5m=mode==='valid0'?0:5;}
  else {sample.collection_ok=0;sample.error=mode==='failure'?'provider_permission':mode;}
  res.writeHead(200,{'Content-Type':'application/json'}).end(JSON.stringify(sample));
});
server.requestTimeout=15000;server.headersTimeout=5000;
return server;
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 createTestTarget(readFileSync('/run/secrets/test-target-key','utf8').trim()).listen(3000,'0.0.0.0');
}
