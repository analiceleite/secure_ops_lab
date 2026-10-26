import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {localApi,waitFor,sleep} from './zabbix-api.mjs';
const phase=process.argv[2];assert.ok(['baseline','down','recovery'].includes(phase));
const api=localApi(),path='/state/availability-nodata.json';
async function state(){
  const [host]=await api('host.get',{filter:{host:['secureops-api']},output:['hostid']});assert.ok(host);
  const [item]=await api('item.get',{hostids:[host.hostid],webitems:true,filter:{key_:['web.test.fail[api-health]']},output:['itemid','lastclock','lastvalue']});assert.ok(item);
  const triggers=await api('trigger.get',{hostids:[host.hostid],filter:{description:['SecureOps API: verificacao HTTP sem dados recentes','SecureOps API: falha na verificacao HTTP interna']},output:['triggerid','description','value','state']});assert.equal(triggers.length,2);
  return {item,technical:triggers.find(t=>t.description.includes('sem dados')),http:triggers.find(t=>t.description.includes('falha na'))};
}
try{
  if(phase==='baseline'){
    const s=await state();assert.equal(s.technical.value,'0');assert.equal(s.http.value,'0');assert.equal(s.item.lastvalue,'0');assert.ok(Number(s.item.lastclock)>Date.now()/1000-60);
    writeFileSync(path,JSON.stringify({itemid:s.item.itemid,triggerid:s.technical.triggerid,baselineClock:Number(s.item.lastclock)}),{flag:'wx'});
    console.log(JSON.stringify({phase,result:'pass',baselineClock:Number(s.item.lastclock)}));
  }else if(phase==='down'){
    const baseline=JSON.parse(readFileSync(path,'utf8'));await sleep(8000);const first=await state();const last=Number(first.item.lastclock);
    const s=await waitFor(state,s=>s.technical.value==='1',140,'availability_nodata');assert.equal(Number(s.item.lastclock),last);assert.equal(s.http.value,'0');
    const [problem]=await api('event.get',{objectids:[baseline.triggerid],value:1,time_from:last,output:['eventid','clock','r_eventid'],sortfield:['clock','eventid'],sortorder:'DESC',limit:1});assert.ok(problem);assert.equal(problem.r_eventid,'0');
    const gap=Number(problem.clock)-last;assert.ok(gap>=90&&gap<=120);
    const result={...baseline,lastSampleClock:last,problemEvent:problem.eventid,problemClock:Number(problem.clock),nodataSeconds:gap,noNewSamples:true,httpFailureRemainedNormal:true};
    writeFileSync(path,JSON.stringify(result));console.log(JSON.stringify({phase,result:'pass',...result}));
  }else{
    const baseline=JSON.parse(readFileSync(path,'utf8'));
    const s=await waitFor(state,s=>Number(s.item.lastclock)>baseline.lastSampleClock&&s.item.lastvalue==='0'&&s.technical.value==='0'&&s.http.value==='0',80,'availability_nodata_recovery');
    const [problem]=await api('event.get',{eventids:[baseline.problemEvent],output:['r_eventid']});assert.notEqual(problem.r_eventid,'0');
    const result={...baseline,recoveryEvent:problem.r_eventid,newHealthyClock:Number(s.item.lastclock)};
    writeFileSync(path,JSON.stringify(result));console.log(JSON.stringify({phase,result:'pass',...result}));
  }
}catch(error){console.error(error instanceof Error&&/^(timeout_[a-z0-9_]+|zabbix_[a-z._0-9-]+)$/.test(error.message)?error.message:'availability_nodata_failed_values_omitted');process.exitCode=1;}
