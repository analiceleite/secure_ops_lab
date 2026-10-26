import {test} from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {randomBytes} from 'node:crypto';
import {createTestTarget} from './test-target.mjs';
test('controle e metricas do alvo ficticio exigem chave efemera',async t=>{
 const key=randomBytes(32).toString('hex'),server=createTestTarget(key);
 server.listen(0,'127.0.0.1');await once(server,'listening');
 t.after(()=>{server.closeAllConnections();server.close();});
 const base=`http://127.0.0.1:${server.address().port}`;
 for(const headers of [{},{'X-SecureOps-Metrics-Key':'wrong'}]){
  assert.equal((await fetch(base+'/control',{method:'POST',body:'valid5',headers})).status,401);
  assert.equal((await fetch(base+'/metrics',{headers})).status,401);
 }
 const headers={'X-SecureOps-Metrics-Key':key};
 let sample=await (await fetch(base+'/metrics',{headers})).json();assert.equal(sample.collection_ok,0);assert.ok(!('login_errors_5m'in sample));
 assert.equal((await fetch(base+'/control',{method:'POST',headers,body:'valid5'})).status,204);
 sample=await (await fetch(base+'/metrics',{headers})).json();assert.equal(sample.login_errors_5m,5);assert.ok(!JSON.stringify(sample).includes(key));
 assert.equal((await fetch(base+'/control',{method:'POST',headers,body:'unsupported'})).status,400);
});
test('alvo ficticio mantem codigos 500 e redirect sem alterar API',async t=>{
 const server=createTestTarget(randomBytes(32).toString('hex'));
 server.listen(0,'127.0.0.1');await once(server,'listening');t.after(()=>{server.closeAllConnections();server.close();});
 const base=`http://127.0.0.1:${server.address().port}`;
 assert.equal((await fetch(base+'/500')).status,500);
 const response=await fetch(base+'/redirect',{redirect:'manual'});assert.equal(response.status,302);assert.equal(response.headers.get('location'),'/ok');
 assert.equal((await fetch(base+'/ok')).status,200);
});
