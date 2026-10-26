// Harness administrativo efêmero, NÃO um Code node/workflow de runtime.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync} from 'node:fs';
import {randomBytes,randomUUID} from 'node:crypto';
const require=createRequire('/usr/local/lib/node_modules/n8n/package.json');
const {Client}=require('pg'); // Dependência já presente na imagem n8n fixada.
const config=JSON.parse(Buffer.from(process.env.FIXTURE_CONFIG,'base64').toString('utf8'));
const password=()=>randomBytes(32).toString('hex');
const key=config.header,marker=config.marker;
const origin='http://fixture-n8n:5678', endpoint=origin+'/webhook/secureops-incidents-v1';
let cookie='',stage='setup',checks=0,lastHttpStatus=null;
const db=new Client({host:'fixture-db',database:'incidents',user:'postgres',password:config.bootstrap});
const meta=new Client({host:'fixture-db',database:'n8n',user:'postgres',password:config.bootstrap});
function check(value){assert.ok(value);checks++;}
async function http(url,options={}){
  const r=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(15000),...options});
  const text=await r.text();lastHttpStatus=r.status;return {status:r.status,text,headers:r.headers};
}
async function rest(path,data){
  const r=await http(origin+'/rest'+path,{method:'POST',headers:{'Content-Type':'application/json',Origin:origin,'browser-id':'fixture-browser',...(cookie?{Cookie:cookie}:{})},body:JSON.stringify(data)});
  assert.ok(r.status>=200&&r.status<300,'fixture_rest_'+r.status);
  const cookies=r.headers.getSetCookie();if(cookies.length)cookie=cookies.map(c=>c.split(';')[0]).join('; ');
  return JSON.parse(r.text).data;
}
const clock=String(Math.floor(Date.now()/1000)-60);
function event(eid,pid=eid,extra={}){return JSON.stringify({contract_version:1,source:'zabbix',source_instance:'webhook-fixture',event_type:eid===pid?'problem':'recovery',event_id:eid,problem_event_id:pid,trigger_id:'1',host:'secureops-api',service:'secureops-api',condition:'api-http',category:'availability',occurred_at:clock,...extra});}
async function post(body,auth=key,type='application/json'){
  const r=await http(endpoint,{method:'POST',headers:{'Content-Type':type,'X-Fixture-Sensitive':marker,...(auth?{'X-SecureOps-Webhook-Key':auth}:{})},body});
  check(!r.text.includes(marker)&&!r.text.includes(key));return r;
}
async function expect(body,status,result){const r=await post(body);check(r.status===status);check(JSON.parse(r.text).result===result);}
async function state(){return JSON.stringify((await db.query("SELECT (SELECT count(*) FROM incident.deliveries) AS deliveries,(SELECT count(*) FROM incident.incidents) AS incidents,(SELECT count(*) FROM incident.report_jobs) AS jobs")).rows[0]);}
try{
  await db.connect();await meta.connect();
  await db.query("INSERT INTO incident.allowed_conditions VALUES ('webhook-fixture','1','api-http','availability')");
  check((await http(origin+'/rest/workflows')).status===401);
  stage='fixture_owner';
  await rest('/owner/setup',{email:'fixture@lab.invalid',firstName:'Fixture',lastName:'Local',password:'Aa1!'+password().slice(0,32)});
  stage='fixture_credentials';
  const header=await rest('/credentials',{name:'Fixture header',type:'httpHeaderAuth',data:{name:'X-SecureOps-Webhook-Key',value:key}});
  const postgres=await rest('/credentials',{name:'Fixture ingest',type:'postgres',data:{host:'fixture-db',database:'incidents',user:'incident_ingest',password:config.ingest,port:5432,ssl:'disable',allowUnauthorizedCerts:false,maxConnections:4}});
  const workflow=JSON.parse(readFileSync('/checks/workflows/incident-receiver.json','utf8'));
  workflow.nodes.find(n=>n.id==='receiver').credentials={httpHeaderAuth:{id:header.id,name:header.name}};
  workflow.nodes.find(n=>n.id==='persist').credentials={postgres:{id:postgres.id,name:postgres.name}};
  stage='fixture_workflow_create';
  const created=await rest('/workflows',workflow);
  stage='fixture_workflow_activate';
  await rest('/workflows/'+created.id+'/activate',{versionId:created.versionId});
  let hooks;
  for(let attempt=0;attempt<20;attempt++){
    hooks=await meta.query('SELECT "webhookPath", method FROM webhook_entity');
    if(hooks.rows.length)break;
    await new Promise(resolve=>setTimeout(resolve,250));
  }
  check(hooks.rows.length===1&&hooks.rows[0].webhookPath==='secureops-incidents-v1');
  stage='authentication';
  const initial=await state();
  check([401,403].includes((await post(event('100'),null)).status));
  check([401,403].includes((await post(event('100'),'wrong')).status));
  check(initial===await state());
  stage='contract';
  await expect(event('100'),200,'applied');
  await expect(event('100'),200,'duplicate');
  await expect(event('100','100',{occurred_at:String(Number(clock)+1)}),409,'conflict');
  const beforeInvalid=await state();
  for(const body of [event('{EVENT.ID}'),event('200','200',{extra:marker}),event('200','200',{trigger_id:'999'}),event('200','200',{event_id:200}),event('200','200',{occurred_at:'1'}),event("1'; DROP SCHEMA incident CASCADE;--"),event('200').replace('{','{"host":"secureops-api",'),event('200').padEnd(4097,' ')])await expect(body,400,'invalid');
  check(beforeInvalid===await state());
  const wrongType=await post(event('200'),key,'text/plain');check(wrongType.status===400);
  stage='malformed_json';
  const malformed=await post('INVALID_'+marker);check(malformed.status>=400&&malformed.status<500);
  stage='transport_limit';
  const large=await post(' '.repeat(1048577));check(large.status===500);
  check(beforeInvalid===await state());
  stage='close_and_job';
  await expect(event('101','100',{occurred_at:String(Number(clock)+10)}),200,'applied');
  check((await db.query("SELECT count(*)::int AS count FROM incident.report_jobs")).rows[0].count===1);
  stage='concurrency';
  const concurrent=await Promise.all(Array.from({length:20},()=>post(event('200'))));
  const results=concurrent.map(r=>{check(r.status===200);return JSON.parse(r.text).result;});
  check(results.filter(r=>r==='applied').length===1);check(results.filter(r=>r==='duplicate').length===19);
  stage='commit_before_ack';
  await db.query('BEGIN');await db.query("SELECT * FROM incident.allowed_conditions FOR UPDATE");
  let settled=false;
  const held=post(event('201','200',{occurred_at:String(Number(clock)+20)})).then(r=>{settled=true;return r;});
  await new Promise(resolve=>setTimeout(resolve,700));check(!settled);
  await db.query('COMMIT');const accepted=await held;check(accepted.status===200);
  check((await db.query("SELECT state FROM incident.incident_summary WHERE problem_event_id='200'")).rows[0].state==='closed');
  stage='persistence_failure';
  const beforeFailure=await state();
  await db.query('BEGIN');await db.query("SELECT * FROM incident.allowed_conditions FOR UPDATE");
  const failed=await post(event('300'));check(failed.status===503);check(failed.text==='{"result":"unavailable"}');
  await db.query('ROLLBACK');check(beforeFailure===await state());
  await expect(event('300'),200,'applied');
  stage='execution_storage';
  await new Promise(resolve=>setTimeout(resolve,500));
  const stored=await meta.query('SELECT count(*)::int AS count FROM execution_data');
  const flags=await meta.query("SELECT count(*)::int AS count, coalesce(bool_or(to_jsonb(e)::text LIKE $1),false) AS has_marker, coalesce(bool_or(to_jsonb(e)::text LIKE $2),false) AS has_key FROM execution_data e",['%'+marker+'%','%'+key+'%']);
  console.log(JSON.stringify({check:'fixture_execution_storage',rows:stored.rows[0].count,hasMarker:flags.rows[0].has_marker,hasHeaderKey:flags.rows[0].has_key,malformedJsonStatus:malformed.status,overTransportLimitStatus:large.status,concurrentApplied:results.filter(r=>r==='applied').length,concurrentDuplicates:results.filter(r=>r==='duplicate').length}));
  check(!flags.rows[0].has_marker&&!flags.rows[0].has_key);
  // Falhas pré-workflow e do banco também não podem persistir o marcador no metadata.
  const sensitive=await meta.query("SELECT count(*)::int AS count FROM execution_entity e WHERE to_jsonb(e)::text LIKE $1",['%'+marker+'%']);
  check(sensitive.rows[0].count===0);
  console.log(JSON.stringify({check:'n8n_receiver_isolated',result:'pass',checks,malformedJsonStatus:malformed.status,overTransportLimitStatus:large.status,concurrentApplied:1,concurrentDuplicates:19,executionDataRows:stored.rows[0].count,liveServices:'preservation_checked_by_host_harness'}));
}catch(error){
  console.error(JSON.stringify({check:'n8n_receiver_isolated',result:'fail',stage,lastHttpStatus,checks,errorClass:error.name,messageCategory: /^fixture_rest_\d+$/.test(error.message)?error.message:'values_omitted'}));process.exitCode=1;
}finally{await db.end().catch(()=>{});await meta.end().catch(()=>{});}
