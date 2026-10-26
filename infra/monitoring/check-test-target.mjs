// Valida apenas o alvo ficticio em container, sem token ou API Zabbix.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const name=process.argv[2];assert.match(name,/^secureops-negative-[a-f0-9]{32}$/);
try{
 const key=readFileSync('/secrets/test-target-key','utf8').trim(),base=`http://${name}:3000`;
 assert.equal((await fetch(base+'/control',{method:'POST',body:'valid5',signal:AbortSignal.timeout(5000)})).status,401);
 assert.equal((await fetch(base+'/metrics',{signal:AbortSignal.timeout(5000)})).status,401);
 const headers={'X-SecureOps-Metrics-Key':key};
 const initial=await(await fetch(base+'/metrics',{headers,signal:AbortSignal.timeout(5000)})).json();assert.equal(initial.collection_ok,0);
 assert.equal((await fetch(base+'/control',{method:'POST',headers,body:'valid5',signal:AbortSignal.timeout(5000)})).status,204);
 const sample=await(await fetch(base+'/metrics',{headers,signal:AbortSignal.timeout(5000)})).json();assert.equal(sample.login_errors_5m,5);assert.ok(!JSON.stringify(sample).includes(key));
 assert.equal((await fetch(base+'/500',{signal:AbortSignal.timeout(5000)})).status,500);
 assert.equal((await fetch(base+'/redirect',{redirect:'manual',signal:AbortSignal.timeout(5000)})).status,302);
 console.log(JSON.stringify({check:'ephemeral_target_auth_runtime',result:'pass',unauthenticatedControl:401,unauthenticatedMetrics:401,authenticatedControl:204,secretNotReturned:true,scope:'fixture_only_no_zabbix_api'}));
}catch{console.error('ephemeral_target_check_failed_values_omitted');process.exitCode=1;}
