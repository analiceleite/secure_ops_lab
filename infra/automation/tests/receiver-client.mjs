// Cliente administrativo somente da fixture; não faz parte do receptor de runtime.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {request,createServer} from 'node:http';
import {once} from 'node:events';
const {Client}=createRequire('/receiver/package.json')('pg');
const config=JSON.parse(Buffer.from(process.env.FIXTURE_CONFIG,'base64').toString('utf8'));
const phase=process.argv[2]??'main';let checks=0,stage=phase;
const check=value=>{assert.ok(value);checks++;};
const now=String(Math.floor(Date.now()/1000)-120);
function event(id,pid=id,tid='1',extra={}){
 return JSON.stringify({contract_version:1,source:'zabbix',source_instance:'receiver-fixture',
  event_type:id===pid?'problem':'recovery',event_id:id,problem_event_id:pid,trigger_id:tid,
  host:'secureops-api',service:'secureops-api',condition:({'1':'api-http','2':'api-http-nodata','3':'auth-threshold','4':'auth-collection'})[tid]??'api-http',
  category:tid==='1'?'availability':tid==='3'?'authentication':'collection',occurred_at:now,...extra});
}
function post(body,headers={},fragmented=false){
 return new Promise((resolve,reject)=>{
  const req=request({host:'fixture-receiver',port:3000,path:'/v1/events',method:'POST',headers:{
   'Content-Type':'application/json','X-SecureOps-Webhook-Key':config.header,'X-Fixture-Sensitive':config.marker,...headers}},res=>{
   let text='';res.on('data',c=>text+=c);res.on('end',()=>{
    check(!text.includes(config.header)&&!text.includes(config.marker));
    resolve({status:res.statusCode,value:JSON.parse(text)});
   });
  });req.setTimeout(12000,()=>req.destroy(Error('timeout')));req.on('error',reject);
  if(fragmented){for(const byte of Buffer.from(body))req.write(Buffer.from([byte]));req.end();}else req.end(body);
 });
}
async function expect(body,status,result,headers={},fragmented=false){
 const r=await post(body,headers,fragmented);check(r.status===status);check(r.value.result===result);
}
const db=new Client({host:'fixture-db',database:'incidents',user:'postgres',password:config.bootstrap});
async function state(){
 const r=await db.query(`SELECT jsonb_build_object(
 'ledger',(SELECT jsonb_agg(to_jsonb(t) ORDER BY source_instance,event_id) FROM incident.deliveries t),
 'cycles',(SELECT jsonb_agg(to_jsonb(t) ORDER BY source_instance,problem_event_id) FROM incident.cycles t),
 'incidents',(SELECT jsonb_agg(to_jsonb(t) ORDER BY incident_id) FROM incident.incidents t),
 'jobs',(SELECT jsonb_agg(to_jsonb(t) ORDER BY incident_id,report_version) FROM incident.report_jobs t)) AS state`);
 return JSON.stringify(r.rows[0].state);
}
async function lostAck(body){
 // Proxy só do harness: derruba downstream APÓS receber a resposta upstream (commit).
 let confirmed;const committed=new Promise(r=>confirmed=r);
 const proxy=createServer((incoming,response)=>{
  const upstream=request({host:'fixture-receiver',port:3000,path:'/v1/events',method:'POST',headers:{'Content-Type':'application/json','X-SecureOps-Webhook-Key':config.header}},res=>{
   check(res.statusCode===200);res.resume();confirmed();response.destroy();
  });upstream.on('error',()=>response.destroy());incoming.pipe(upstream);
 });proxy.listen(0,'127.0.0.1');await once(proxy,'listening');
 try{
  await new Promise((resolve,reject)=>{
   const r=request({host:'127.0.0.1',port:proxy.address().port,path:'/',method:'POST'},()=>reject(Error('ack_not_lost')));
   r.on('error',resolve);r.end(body);
  });await committed;
 }finally{proxy.closeAllConnections();await new Promise(resolve=>proxy.close(resolve));}
}
try{
 if(phase==='offline'){
  const started=Date.now();await expect(event('990'),503,'unavailable');check(Date.now()-started<10000);
 }else{
  await db.connect();
  if(phase==='resume'){
   const envelope=(await db.query("SELECT envelope::text AS body FROM incident.deliveries WHERE event_id='700'")).rows[0].body;
   await expect(envelope,200,'duplicate');
   await expect(event('701','700','1',{occurred_at:String(Number(now)+120)}),200,'applied');
   check((await db.query("SELECT state FROM incident.incident_summary WHERE problem_event_id='700'")).rows[0].state==='closed');
  }else{
   await db.query(`INSERT INTO incident.allowed_conditions VALUES
    ('receiver-fixture','1','api-http','availability'),('receiver-fixture','2','api-http-nodata','collection'),
    ('receiver-fixture','3','auth-threshold','authentication'),('receiver-fixture','4','auth-collection','collection')`);
   stage='negative_contract';const initial=await state();
   await expect(event('100'),401,'unauthorized',{'X-SecureOps-Webhook-Key':''});
   await expect(event('100'),401,'unauthorized',{'X-SecureOps-Webhook-Key':'wrong'});
   for(const body of ['{','[]','null',event('{EVENT.ID}'),event('1'.repeat(21)),event('100','100','1',{extra:config.marker}),
    event('100','100','999'),event('100','100','1',{event_id:100}),event('100','100','1',{occurred_at:'1'}),
    event("1';DROP SCHEMA incident CASCADE;--"),event('100').replace('{','{"host":"secureops-api",'),
    event('100').replace('{','{"ho\\u0073t":"secureops-api",')])await expect(body,400,'invalid');
   await expect(event('100'),415,'invalid',{'Content-Type':'text/plain'});
   await expect(event('100'),415,'invalid',{'Content-Encoding':'gzip'});
   await expect(Buffer.from([0xff]),400,'invalid');
   await expect(' '.repeat(4097),413,'invalid');
   await expect(' '.repeat(4097),413,'invalid',{'Transfer-Encoding':'chunked'});
   check(initial===await state());
   stage='normal_cycle';
   await expect(event('100'),200,'applied',{},true);
   await expect(event('100').padEnd(4096,' '),200,'duplicate');
   const opened=await state();await expect(event('100','100','1',{occurred_at:String(Number(now)+1)}),409,'conflict');check(opened===await state());
   stage='commit_before_ack';
   await db.query('BEGIN');await db.query("SELECT * FROM incident.allowed_conditions WHERE trigger_id='1' FOR UPDATE");
   let settled=false;
   const waiting=post(event('101','100','1',{occurred_at:String(Number(now)+10)})).then(r=>{settled=true;return r;});
   await new Promise(resolve=>setTimeout(resolve,500));check(!settled);await db.query('COMMIT');
   check((await waiting).status===200);
   check((await db.query("SELECT duration_seconds FROM incident.incident_summary WHERE problem_event_id='100'")).rows[0].duration_seconds==='10');
   check((await db.query('SELECT count(*)::int AS n FROM incident.report_jobs')).rows[0].n===1);
   stage='concurrency';
   const results=await Promise.all(Array.from({length:20},()=>post(event('200'))));
   check(results.every(r=>r.status===200));check(results.filter(r=>r.value.result==='applied').length===1);check(results.filter(r=>r.value.result==='duplicate').length===19);
   stage='lock_timeout';const beforeTimeout=await state();
   await db.query('BEGIN');await db.query("SELECT * FROM incident.allowed_conditions WHERE trigger_id='1' FOR UPDATE");
   const started=Date.now();await expect(event('201','200'),503,'unavailable');check(Date.now()-started<10000);
   await db.query('ROLLBACK');check(beforeTimeout===await state());
   await expect(event('201','200','1',{occurred_at:String(Number(now)+10)}),200,'applied');
   stage='recovery_first';
   await expect(event('301','300','1',{occurred_at:String(Number(now)+10)}),200,'pending');
   check(!(await db.query("SELECT FROM incident.incident_summary WHERE problem_event_id='300'")).rowCount);
   await expect(event('300'),200,'applied');
   check((await db.query("SELECT out_of_order FROM incident.incident_summary WHERE problem_event_id='300'")).rows[0].out_of_order);
   stage='collection_independence';
   await expect(event('400','400','2'),200,'applied');await expect(event('500','500','4'),200,'applied');
   await expect(event('401','400','2'),200,'applied');
   check((await db.query("SELECT state FROM incident.incident_summary WHERE problem_event_id='500'")).rows[0].state==='open');
   stage='rollback_after_mutation';
   await db.query(`CREATE FUNCTION public.fixture_fail() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'fixture_failure'; END$$;
    CREATE TRIGGER fixture_fail AFTER INSERT ON incident.deliveries FOR EACH ROW EXECUTE FUNCTION public.fixture_fail()`);
   const beforeFailure=await state();await expect(event('600'),503,'unavailable');check(beforeFailure===await state());
   await db.query('DROP TRIGGER fixture_fail ON incident.deliveries; DROP FUNCTION public.fixture_fail()');
   stage='lost_ack_after_commit';
   await lostAck(event('600'));await expect(event('600'),200,'duplicate');
   check((await db.query("SELECT count(*)::int AS n FROM incident.incidents WHERE problem_event_id='600'")).rows[0].n===1);
   await expect(event('601','600'),200,'applied');await expect(event('700'),200,'applied');
   stage='no_raw_secret_persistence';
   const stored=await state();check(!stored.includes(config.marker)&&!stored.includes(config.header));
   // Rotina aceita somente envelope mínimo; nenhuma tabela de execução é criada pelo receptor.
   check((await db.query("SELECT count(*)::int AS n FROM pg_class WHERE relname IN ('execution_data','execution_entity')")).rows[0].n===0);
  }
 }
 console.log(JSON.stringify({check:'incident_receiver_integration',phase,result:'pass',checks,...(phase==='main'?{concurrentApplied:1,concurrentDuplicates:19,lostAckAfterCommit:true}:{} )}));
}catch(error){console.error(JSON.stringify({check:'incident_receiver_integration',phase,result:'fail',stage,checks,errorClass:error.name,values:'omitted'}));process.exitCode=1;}
finally{await db.end().catch(()=>{});}
