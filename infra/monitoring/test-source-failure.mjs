import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {localApi,waitFor} from './zabbix-api.mjs';
const phase=process.argv[2],component=process.argv[3],since=Number(process.argv[4]??0);
assert.ok(['before','down','recovery'].includes(phase));assert.ok(['keycloak','identity-event-collector'].includes(component));
const path=`/state/outage-${component}.json`;
const api=localApi();const ids=JSON.parse(readFileSync('/state/security-zabbix-created.json','utf8'));
async function state(){
  const items=await api('item.get',{itemids:ids.itemids,output:['itemid','lastvalue','lastclock','state']});
  const triggers=await api('trigger.get',{triggerids:ids.triggerids,output:['triggerid','value','state']});
  return {count:items.find(i=>i.itemid===ids.itemids[1]),quality:items.find(i=>i.itemid===ids.itemids[2]),auth:triggers.find(t=>t.triggerid===ids.triggerids[0]),technical:triggers.find(t=>t.triggerid===ids.triggerids[1])};
}
async function checkApiHealthy(){
  const items=await api('item.get',{hostids:[ids.hostid],webitems:true,filter:{key_:['web.test.fail[api-health]']},output:['lastclock','lastvalue']});
  assert.equal(items.length,1);assert.equal(items[0].lastvalue,'0');assert.ok(Number(items[0].lastclock)>Date.now()/1000-60);
}
try{
  if(phase==='before'){
    const s=await state();assert.ok(Number(s.count.lastvalue)>=5);assert.equal(s.quality.lastvalue,'1');assert.equal(s.auth.value,'1');assert.equal(s.technical.value,'0');
    const problems=await api('event.get',{objectids:[ids.triggerids[0]],value:1,output:['eventid','clock','r_eventid'],sortfield:['clock','eventid'],sortorder:'DESC',limit:1});assert.equal(problems.length,1);assert.equal(problems[0].r_eventid,'0');
    writeFileSync(path,JSON.stringify({component,count:Number(s.count.lastvalue),qualityClock:Number(s.quality.lastclock),authEvent:problems[0].eventid}),{flag:'wx'});
    console.log(JSON.stringify({phase,component,result:'pass',authEvent:problems[0].eventid,count:Number(s.count.lastvalue)}));
  }else if(phase==='down'){
    const baseline=JSON.parse(readFileSync(path,'utf8'));assert.ok(since>0);
    if(component==='keycloak'){
      // Novo caminho de login nao alcanca o provedor; nao toca sessao existente.
      let unreachable=false;try{await fetch('http://keycloak.localhost:8080/realms/secureops-lab/.well-known/openid-configuration',{redirect:'error',signal:AbortSignal.timeout(3000)});}catch{unreachable=true;}assert.equal(unreachable,true);
    }
    const s=await waitFor(state,s=>s.technical.value==='1'&&(component!=='keycloak'||(s.quality.lastvalue==='0'&&Number(s.quality.lastclock)>=since)),130,'real_outage_technical');
    assert.equal(s.auth.value,'1');assert.equal(Number(s.count.lastvalue),baseline.count);assert.ok(Number(s.count.lastclock)<=since+1);
    const [problem]=await api('event.get',{eventids:[baseline.authEvent],output:['r_eventid']});assert.equal(problem.r_eventid,'0');
    const [technical]=await api('event.get',{objectids:[ids.triggerids[1]],value:1,time_from:since-1,output:['eventid','clock'],sortfield:['clock','eventid'],sortorder:'DESC',limit:1});assert.ok(technical);
    const latency=Number(technical.clock)-since;assert.ok(latency>=-1&&latency<=120);
    await checkApiHealthy();
    const result={...baseline,stoppedAt:since,technicalEvent:technical.eventid,technicalClock:Number(technical.clock),detectionSeconds:latency,authStillOpen:true,noZero:true,apiHealthy:true};
    if(component==='identity-event-collector'){const gap=Number(technical.clock)-Number(s.quality.lastclock);assert.ok(gap>=90&&gap<=120);result.nodataSeconds=gap;}
    writeFileSync(path,JSON.stringify(result));console.log(JSON.stringify({phase,result:'pass',...result}));
  }else{
    const baseline=JSON.parse(readFileSync(path,'utf8'));assert.ok(since>0);
    const s=await waitFor(state,s=>s.quality.lastvalue==='1'&&Number(s.quality.lastclock)>=since&&s.technical.value==='0',120,'real_outage_recovery');
    const [problem]=await api('event.get',{eventids:[baseline.technicalEvent],output:['r_eventid']});assert.notEqual(problem.r_eventid,'0');
    await checkApiHealthy();
    const result={...baseline,restoredAt:since,recoveryEvent:problem.r_eventid,newValidQualityClock:Number(s.quality.lastclock),countAfterRecovery:Number(s.count.lastvalue),authProblemAfterRecovery:s.auth.value==='1'};
    writeFileSync(path,JSON.stringify(result));console.log(JSON.stringify({phase,result:'pass',...result}));
  }
}catch(error){console.error(error instanceof Error&&/^(timeout_[a-z0-9_]+|zabbix_[a-z._0-9-]+)$/.test(error.message)?error.message:'real_outage_check_failed_values_omitted');process.exitCode=1;}
