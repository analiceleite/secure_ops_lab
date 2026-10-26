import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import { localApi, sleep, waitFor } from './zabbix-api.mjs';
import { masterItem, dependentItems, securityTriggers, KEYS } from './security-config.mjs';
const name=process.argv[2];
assert.match(name,/^secureops-negative-[a-f0-9]{32}$/);
const target=`http://${name}:3000`;
const api=localApi();
const key=readFileSync('/secrets/test-target-key','utf8').trim();assert.match(key,/^[a-f0-9]{64}$/);
let hostid;
const evidence=[];
function pass(check,data={}) { const row={check,result:'pass',...data};evidence.push(row);console.log(JSON.stringify(row)); }
try {
  const group=await api('hostgroup.get',{filter:{name:['SecureOps Lab']},output:['groupid']});assert.equal(group.length,1);
  assert.equal((await api('host.get',{filter:{host:[name]},output:['hostid']})).length,0);
  hostid=(await api('host.create',{host:name,groups:[{groupid:group[0].groupid}],macros:[{macro:'{$SECUREOPS_METRICS_KEY}',type:1,value:key}]})).hostids[0];
  // Mesmos parametros HTTP da disponibilidade; destinos exclusivamente ficticios.
  await api('httptest.create',['500','redirect'].map((path)=>({hostid,name:path,delay:'20s',retries:1,
    steps:[{name:'health',no:1,url:`${target}/${path}`,timeout:'5s',required: '',status_codes:'200',follow_redirects:0}]})));
  const web=await api('item.get',{hostids:[hostid],webitems:true,output:['itemid','key_','lastclock','lastvalue']});
  const failures=web.filter(i=>/^web.test.fail\[(500|redirect)\]$/.test(i.key_));assert.equal(failures.length,2);
  const codes=web.filter(i=>/^web.test.rspcode\[(500|redirect),health\]$/.test(i.key_));assert.equal(codes.length,2);
  await waitFor(()=>api('item.get',{itemids:[...failures,...codes].map(i=>i.itemid),webitems:true,output:['key_','lastvalue','lastclock']}),rows=>rows.length===4&&rows.every(i=>Number(i.lastclock)>0)&&rows.filter(i=>i.key_.startsWith('web.test.fail')).every(i=>i.lastvalue==='1'),120,'web_negatives');
  const actual=await api('item.get',{itemids:codes.map(i=>i.itemid),webitems:true,output:['key_','lastvalue']});
  assert.equal(actual.find(i=>i.key_.includes('[500,')).lastvalue,'500');
  assert.equal(actual.find(i=>i.key_.includes('[redirect,')).lastvalue,'302');
  pass('http_500_redirect_not_healthy',{statusCodes:actual.map(i=>Number(i.lastvalue)),failedSteps:1,mainApiNotChanged:true});

  const master=(await api('item.create',masterItem(hostid,`${target}/metrics`))).itemids[0];
  const dependent=(await api('item.create',dependentItems(hostid,master))).itemids;
  const triggers=(await api('trigger.create',securityTriggers(name))).triggerids;
  const items=()=>api('item.get',{itemids:[master,...dependent],output:['itemid','key_','lastclock','lastvalue','state']});
  const states=()=>api('trigger.get',{triggerids:triggers,output:['triggerid','value','state']});
  const quality=rows=>rows.find(i=>i.key_===KEYS.quality);
  const count=rows=>rows.find(i=>i.key_===KEYS.count);
  await waitFor(items,rows=>Number(quality(rows).lastclock)>0&&quality(rows).lastvalue==='0',150,'initial_failure');
  assert.equal(Number(count(await items()).lastclock),0);
  await waitFor(states,rows=>rows.find(t=>t.triggerid===triggers[1]).value==='1',90,'initial_technical_problem');
  pass('initial_failure_is_unknown_not_zero',{countHasNoSample:true,technicalProblem:true});

  async function mode(value){const r=await fetch(target+'/control',{method:'POST',headers:{'X-SecureOps-Metrics-Key':key},body:value,signal:AbortSignal.timeout(5000)});assert.equal(r.status,204);return Math.floor(Date.now()/1000);}
  const valid5=await mode('valid5');
  await waitFor(items,rows=>count(rows).lastvalue==='5'&&Number(count(rows).lastclock)>=valid5&&quality(rows).lastvalue==='1',100,'five');
  await waitFor(states,rows=>rows.find(t=>t.triggerid===triggers[0]).value==='1'&&rows.find(t=>t.triggerid===triggers[1]).value==='0',60,'auth_open');
  const since=valid5;
  const problems=()=>api('event.get',{objectids:[triggers[0]],source:0,object:0,value:1,time_from:since,output:['eventid','clock','r_eventid']});
  const [original]=await problems();assert.ok(original);
  pass('fixture_threshold_opens',{problemEvent:original.eventid});
  for(const value of ['provider_auth','events_disabled','event_limit','failure']) {
    const changed=await mode(value);
    await waitFor(items,rows=>quality(rows).lastvalue==='0'&&Number(quality(rows).lastclock)>=changed,100,`quality_${value}`);
    const rows=await items();assert.equal(count(rows).lastvalue,'5');assert.ok(Number(count(rows).lastclock)<changed);
    const events=await problems();assert.equal(events.length,1);assert.equal(events[0].r_eventid,'0');
    const ts=await states();assert.equal(ts.find(t=>t.triggerid===triggers[0]).value,'1');assert.equal(ts.find(t=>t.triggerid===triggers[1]).value,'1');
    pass(`failure_preserves_security_${value}`,{problemEvent:original.eventid,noZero:true,noRecovery:true});
  }
  // Corpo HTTP invalido/negado e amostra obsoleta nao geram qualidade nova.
  for(const value of ['http403','http500','invalidjson','stale']) {
    const changed=await mode(value);
    await waitFor(items,rows=>rows.find(i=>i.itemid===master).state==='1',100,`unsupported_${value}`);
    const events=await problems();assert.equal(events.length,1);assert.equal(events[0].r_eventid,'0');
    assert.equal(count(await items()).lastvalue,'5');
    pass(`invalid_master_preserves_security_${value}`,{problemEvent:original.eventid,noRecovery:true});
    // Reestabelecer coleta completa antes do proximo teste, sem recuperar autenticacao.
    const healthy=await mode('valid5');
    await waitFor(items,rows=>quality(rows).lastvalue==='1'&&Number(quality(rows).lastclock)>=healthy&&rows.find(i=>i.itemid===master).state==='0',100,'reset_fixture_valid');
  }
  // Perda de resultados novos com ultimo estado de qualidade valida.
  const lastGood=Number(quality(await items()).lastclock);
  await mode('http500');
  const technical=await waitFor(states,rows=>rows.find(t=>t.triggerid===triggers[1]).value==='1',130,'nodata_quality');
  const qualityEvents=await api('event.get',{objectids:[triggers[1]],value:1,time_from:lastGood,output:['eventid','clock'],sortfield:['clock','eventid'],sortorder:'DESC',limit:1});
  assert.ok(qualityEvents.length===1);
  const delay=Number(qualityEvents[0].clock)-lastGood;assert.ok(delay>=90&&delay<=120);
  assert.equal((await problems())[0].r_eventid,'0');
  pass('quality_nodata_timing',{lastGoodClock:lastGood,problemClock:Number(qualityEvents[0].clock),detectionSeconds:delay,authStillOpen:true});

  const recovery=await mode('valid0');
  await waitFor(items,rows=>count(rows).lastvalue==='0'&&Number(count(rows).lastclock)>=recovery&&quality(rows).lastvalue==='1',100,'valid_recovery');
  await waitFor(states,rows=>rows.every(t=>t.value==='0'),60,'both_recovered');
  const finalEvents=await problems();assert.equal(finalEvents.length,1);assert.notEqual(finalEvents[0].r_eventid,'0');
  pass('only_complete_valid_zero_recovers',{problemEvent:original.eventid,recoveryEvent:finalEvents[0].r_eventid,scope:'fixture_not_real_logins'});
} catch(error) {
  console.error(error instanceof Error&&/^(timeout_[a-z0-9_]+|zabbix_[a-z._0-9-]+)$/.test(error.message)?error.message:'negative_test_failed_values_omitted');process.exitCode=1;
} finally {
  if(hostid){
    try {await api('host.delete',[hostid]);console.log(JSON.stringify({cleanup:'only_invocation_owned_test_host',result:'pass'}));}
    catch{console.error('test_host_cleanup_failed_preserve_and_diagnose');process.exitCode=1;}
  }
}
