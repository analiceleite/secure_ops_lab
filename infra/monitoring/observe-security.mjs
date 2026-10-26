// Somente leitura. Token tecnico/admin apenas em memoria; imprime agregado/horarios.
import { readFileSync,writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { countWindow,limitedJson,validateConfig } from '/collector/collector.ts';
import { localApi,waitFor,sleep } from './zabbix-api.mjs';
const phase=process.argv[2]??'status';
const cycle=process.argv[3]??'1';
assert.ok(['status','clean','fresh','one','threshold','recovery','positive-before','positive-after'].includes(phase));assert.ok(['1','2'].includes(cycle));
const path=`/state/security-cycle-${cycle}.json`;
const api=localApi();
const ids=JSON.parse(readFileSync('/state/security-zabbix-created.json','utf8'));
const realmId=readFileSync('/secrets/collector-realm-id','utf8').trim();
const secret=readFileSync('/secrets/collector-client-secret','utf8').trim();
let token,until=0;
async function window(from) {
  if(Date.now()>=until){
    const r=await fetch('http://keycloak.localhost:8080/realms/secureops-lab/protocol/openid-connect/token',{
      method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),body:new URLSearchParams({grant_type:'client_credentials',client_id:'secureops-event-reader',client_secret:secret})});
    assert.equal(r.status,200);const j=await limitedJson(r);assert.equal(typeof j.access_token,'string');token=j.access_token;until=Date.now()+(j.expires_in-10)*1000;
  }
  async function get(suffix){const r=await fetch('http://keycloak.localhost:8080/admin/realms/secureops-lab/events'+suffix,{headers:{Authorization:`Bearer ${token}`},redirect:'error',signal:AbortSignal.timeout(10000)});assert.equal(r.status,200);return limitedJson(r);}
  validateConfig(await get('/config'));
  const at=Date.now();const query=new URLSearchParams({client:'secureops-gateway',type:'LOGIN_ERROR',dateFrom:String(from??at-300000),dateTo:String(at),first:'0',max:'1001',direction:'asc'});
  const events=await get('?'+query);const count=countWindow(events,at,realmId);
  // Verificacao real de max/offset em janela pequena, sem alegar teste de 1001 eventos.
  if(count>0){const one=await get('?'+new URLSearchParams({...Object.fromEntries(query),max:'1'}));assert.equal(one.length,1);}
  const times=[...new Set(events.map(e=>e.id))].map(id=>events.find(e=>e.id===id).time).sort((a,b)=>a-b);
  const allowedErrors=new Set(['invalid_user_credentials','user_not_found','invalid_code','expired_code','cookie_not_found','invalid_redirect_uri','invalid_client_credentials','not_allowed']);
  const errorKinds={};
  for(const event of events){const kind=allowedErrors.has(event.error)?event.error:'other';errorKinds[kind]=(errorKinds[kind]??0)+1;}
  return {at,count,times,errorKinds};
}
async function monitor(){
  const items=await api('item.get',{itemids:ids.itemids,output:['itemid','lastvalue','lastclock','state']});
  const triggers=await api('trigger.get',{triggerids:ids.triggerids,output:['triggerid','value','state']});
  return {count:items.find(i=>i.itemid===ids.itemids[1]),quality:items.find(i=>i.itemid===ids.itemids[2]),
    auth:triggers.find(t=>t.triggerid===ids.triggerids[0]),technical:triggers.find(t=>t.triggerid===ids.triggerids[1])};
}
try {
  if(phase==='positive-before'){
    const w=await window();const m=await monitor();assert.equal(w.count,0);assert.equal(m.quality.lastvalue,'1');assert.equal(m.auth.value,'0');assert.equal(m.technical.value,'0');
    writeFileSync('/state/positive-logins.json',JSON.stringify({startedAt:w.at,baselineCount:0}),{flag:'wx'});
    console.log(JSON.stringify({phase,result:'pass',sourceCount:0,startedAt:w.at}));
  }else if(phase==='positive-after'){
    const before=JSON.parse(readFileSync('/state/positive-logins.json','utf8'));assert.ok(Date.now()-before.startedAt<=900000);
    // Intervalo diagnostico desde o inicio, para nao perder erros caso a autora demore >5 min.
    // Se houver evento mais antigo que 5 min, a validacao estrita falha; nunca o ignora.
    const w=await window(before.startedAt);assert.equal(w.count,0);
    const m=await waitFor(monitor,s=>s.count.lastvalue==='0'&&s.quality.lastvalue==='1'&&s.auth.value==='0'&&s.technical.value==='0',60,'positive_login_quality');
    writeFileSync('/state/positive-logins.json',JSON.stringify({...before,checkedAt:w.at,loginErrorsSinceStart:0}));
    console.log(JSON.stringify({phase,result:'pass',loginErrorsSinceStart:0,startedAt:before.startedAt,checkedAt:w.at,manualLoginResultsSeparate:true}));
  }else if(phase==='status'||phase==='clean'||phase==='fresh'){
    let w,m;
    if(phase==='clean'){
      const result=await waitFor(async()=>({w:await window(),m:await monitor()}),r=>r.w.count===0&&r.m.count.lastvalue==='0'&&r.m.quality.lastvalue==='1'&&Number(r.m.quality.lastclock)>Date.now()/1000-60&&r.m.auth.value==='0'&&r.m.technical.value==='0',370,'clean_window');
      w=result.w;m=result.m;
    }else if(phase==='fresh'){
      const since=Number(process.argv[4]);assert.ok(since>0);
      const result=await waitFor(async()=>({w:await window(),m:await monitor()}),r=>r.m.quality.lastvalue==='1'&&Number(r.m.quality.lastclock)>=since&&Number(r.m.count.lastclock)>=since&&Number(r.m.count.lastvalue)===r.w.count,100,'fresh_matching_window');
      w=result.w;m=result.m;
    }else{w=await window();m=await monitor();}
    console.log(JSON.stringify({phase,sourceCount:w.count,sourceSampledAt:w.at,eventTimes:w.times,errorKinds:w.errorKinds,
      zabbixCount:Number(m.count.lastvalue),countClock:Number(m.count.lastclock),quality:Number(m.quality.lastvalue),qualityClock:Number(m.quality.lastclock),authProblem:m.auth.value==='1',technicalProblem:m.technical.value==='1'}));
  } else if(phase==='one') {
    const w=await window();assert.equal(w.count,1);
    const m=await waitFor(monitor,s=>s.count.lastvalue==='1'&&Number(s.count.lastclock)*1000>=w.times[0]-1000&&s.quality.lastvalue==='1',60,'one_login_error');
    assert.equal(m.auth.value,'0');assert.equal(m.technical.value,'0');
    writeFileSync(path,JSON.stringify({cycle:Number(cycle),firstEventAt:w.times[0],isolatedErrorNoAlert:true}),{flag:'wx'});
    console.log(JSON.stringify({phase,result:'pass',cycle:Number(cycle),sourceCount:1,firstEventAt:w.times[0],authProblem:false,technicalProblem:false}));
  } else if(phase==='threshold') {
    const previous=JSON.parse(readFileSync(path,'utf8'));const w=await window();assert.equal(w.count,5);assert.ok(w.times.includes(previous.firstEventAt));
    const fifth=w.times[4];const m=await waitFor(monitor,s=>Number(s.count.lastvalue)>=5&&s.quality.lastvalue==='1'&&s.auth.value==='1',60,'threshold');
    const events=await api('event.get',{objectids:[ids.triggerids[0]],value:1,time_from:Math.floor(fifth/1000)-1,output:['eventid','clock','r_eventid'],sortfield:['clock','eventid'],sortorder:'DESC'});
    assert.equal(events.length,1);const problem=events[0];assert.equal(problem.r_eventid,'0');
    const latency=Number(problem.clock)*1000-fifth;assert.ok(latency>=-1000&&latency<=60000);
    // Tres amostras: deteccao + duas adicionais, mantendo o mesmo problema.
    await waitFor(()=>api('history.get',{history:3,itemids:[ids.itemids[1]],time_from:Number(m.count.lastclock),output:['clock','value'],sortfield:['clock','ns'],sortorder:'ASC'}),samples=>samples.filter(s=>Number(s.value)>=5).length>=3,75,'three_threshold_samples');
    const again=await api('event.get',{eventids:[problem.eventid],output:['eventid','r_eventid']});assert.equal(again[0].r_eventid,'0');
    const countProblems=await api('event.get',{objectids:[ids.triggerids[0]],value:1,time_from:Math.floor(fifth/1000)-1,output:['eventid']});assert.equal(countProblems.length,1);
    const result={...previous,fifthEventAt:fifth,problemEvent:problem.eventid,problemClock:Number(problem.clock),detectionMilliseconds:latency,threeSamplesOneProblem:true,latestEventAt:w.times[4]};
    writeFileSync(path,JSON.stringify(result));console.log(JSON.stringify({phase,result:'pass',...result}));
  } else {
    const previous=JSON.parse(readFileSync(path,'utf8'));assert.ok(previous.fifthEventAt&&previous.problemEvent);
    const dropsBelowAt=previous.firstEventAt+300001;
    const remaining=Math.max(0,previous.latestEventAt+300001-Date.now());
    await waitFor(monitor,s=>Number(s.count.lastclock)*1000>dropsBelowAt&&Number(s.count.lastvalue)<5&&s.quality.lastvalue==='1'&&s.auth.value==='0'&&s.technical.value==='0',Math.ceil(remaining/1000)+90,'natural_recovery');
    const [problem]=await api('event.get',{eventids:[previous.problemEvent],output:['eventid','r_eventid']});assert.notEqual(problem.r_eventid,'0');
    const [recovery]=await api('event.get',{eventids:[problem.r_eventid],output:['eventid','clock']});
    const delay=Number(recovery.clock)*1000-dropsBelowAt;assert.ok(delay>=-1000&&delay<=60000);
    const w=await window();
    const result={...previous,recoveryEvent:problem.r_eventid,recoveryClock:Number(recovery.clock),windowDropsBelowAt:dropsBelowAt,recoveryMilliseconds:delay,sourceCountAtEnd:w.count,noEventsDeleted:true};
    writeFileSync(path,JSON.stringify(result));console.log(JSON.stringify({phase,result:'pass',...result}));
  }
} catch(error){console.error(error instanceof Error&&/^(timeout_[a-z0-9_]+|zabbix_[a-z._0-9-]+)$/.test(error.message)?error.message:'security_observation_failed_values_omitted');process.exitCode=1;}
