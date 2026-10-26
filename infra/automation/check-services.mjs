// Smoke da infraestrutura nova. Dados ficticios; nao comprova integracao Zabbix/n8n.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createConnection} from 'node:net';
import {createInterface} from 'node:readline';
import {randomUUID} from 'node:crypto';
const phase=process.argv[2];assert.ok(['interfaces','model','smtp','report'].includes(phase));
const lock=JSON.parse(readFileSync(new URL('./model-lock.json',import.meta.url),'utf8'));
const get=(url,options={})=>fetch(url,{redirect:'error',signal:AbortSignal.timeout(10000),...options});
const pass=(check,fields={})=>console.log(JSON.stringify({check,result:'pass',...fields}));
let stage='initial';
function credential(name){
 const value=readFileSync('/secrets/'+name,'utf8').trim();assert.match(value,/^[a-z]+:[a-f0-9]{64}$/);return value;
}
async function smtp(auth,recipient,send){
 const socket=createConnection({host:'mailpit',port:1025});socket.setTimeout(10000,()=>socket.destroy());
 const lines=createInterface({input:socket,crlfDelay:Infinity})[Symbol.asyncIterator]();
 socket.on('error',()=>{});
 async function response(){
  for(let i=0;i<100;i++){const line=await lines.next();assert.equal(line.done,false);assert.match(line.value,/^\d{3}[ -]/);if(line.value[3]===' ')return Number(line.value.slice(0,3));}
  throw new Error('smtp_response_limit');
 }
 async function command(line){socket.write(line+'\r\n');return response();}
 try{
  assert.equal(await response(),220);assert.equal(await command('EHLO secureops.lab.invalid'),250);
  if(auth){const [user,password]=auth.split(':');const status=await command('AUTH PLAIN '+Buffer.from('\0'+user+'\0'+password).toString('base64'));if(status!==235)return {auth:status};}
  const mail=await command('MAIL FROM:<secureops@lab.invalid>');if(mail!==250)return {mail};
  const rcpt=await command(`RCPT TO:<${recipient}>`);if(rcpt!==250)return {rcpt};
  if(!send)return {mail,rcpt};
  assert.equal(await command('DATA'),354);
  const id='secureops-infra-'+randomUUID();
  const body=`From: secureops@lab.invalid\r\nTo: operadora@lab.invalid\r\nSubject: ${id}\r\nMessage-ID: <${id}@lab.invalid>\r\nMIME-Version: 1.0\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<!doctype html><html lang="pt-BR"><body><h1>Teste SMTP local</h1><p>Alvo ficticio. Este smoke nao e relatorio de IA nem incidente real.</p></body></html>\r\n.`;
  assert.equal(await command(body),250);return {accepted:true,id};
 }finally{socket.destroy();}
}
try{
 if(phase==='interfaces'){
  assert.equal((await get('http://incident-receiver:3000/health')).status,200);
  assert.equal((await get('http://incident-receiver:3000/v1/events',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).status,401);
  assert.equal((await get('http://n8n:5678/healthz/readiness')).status,200);
  assert.equal((await get('http://n8n:5678/rest/workflows')).status,401);
  assert.equal((await get('http://mailpit:8025/api/v1/messages')).status,401);
  assert.equal((await get('http://mailpit:8025/api/v1/messages',{headers:{Authorization:'Basic '+Buffer.from('wrong:wrong').toString('base64')}})).status,401);
  assert.equal((await get('http://mailpit:8025/api/v1/messages',{headers:{Authorization:'Basic '+Buffer.from(credential('mailpit-ui-auth')).toString('base64')}})).status,200);
  pass('automation_interfaces',{receiverLiveness:200,unauthenticatedReceiver:401,n8nReadiness:200,unauthenticatedWorkflows:401,unauthenticatedMailbox:401,wrongMailboxPassword:401,authenticatedMailbox:200});
 }else if(phase==='report'){
  const incidentId=process.argv[3];assert.match(incidentId??'',/^[1-9][0-9]*$/);
  const headers={Authorization:'Basic '+Buffer.from(credential('mailpit-ui-auth')).toString('base64')};
  const response=await get('http://mailpit:8025/api/v1/messages',{headers});assert.equal(response.status,200);
  const box=await response.json();
  const matches=box.messages.filter(m=>m.Subject===`SecureOps | Relatório #${incidentId} v1`);
  assert.equal(matches.length,1,'mensagem ausente ou repetida');
  assert.deepEqual(matches[0].To.map(r=>r.Address),['operadora@lab.invalid']);
  const messageResponse=await get(`http://mailpit:8025/api/v1/message/${encodeURIComponent(matches[0].ID)}`,{headers});
  assert.equal(messageResponse.status,200);const message=await messageResponse.json();
  assert.equal(typeof message.HTML,'string');assert.ok(message.HTML.includes(`Relatório de incidente #${incidentId}`));
  for(const label of ['Fatos observados','Análise gerada por IA local','Hipóteses (não confirmadas)','Cobertura histórica pode ser incompleta'])assert.ok(message.HTML.includes(label));
  assert.ok(!/<(?:script|iframe|form|img|link|object|embed)\b|\bon[a-z]+\s*=|(?:src|href)\s*=\s*["']?https?:/i.test(message.HTML));
  assert.ok(message.Text.includes('Fatos observados:'));
  pass('real_incident_mailpit_report',{incidentId:Number(incidentId),messageId:matches[0].ID,subject:matches[0].Subject,unique:true,html:true,plainText:true,noActiveOrRemoteContent:true,noMessagesDeleted:true,semanticReview:'human_required'});
 }else if(phase==='model'){
  stage='model_metadata';
  const tags=await(await get('http://ollama:11434/api/tags')).json();const tag=tags.models.find(m=>m.name===lock.model);assert.ok(tag);
  assert.equal(tag.digest,lock.manifestSha256);
  const version=await(await get('http://ollama:11434/api/version')).json();assert.equal(version.version,'0.40.11');
  const schema={type:'object',additionalProperties:false,required:['resumo','hipoteses','recomendacoes_preventivas'],properties:{resumo:{type:'string'},hipoteses:{type:'array',items:{type:'string'}},recomendacoes_preventivas:{type:'array',items:{type:'string'}}}};
  const started=Date.now();
  stage='model_generation';
  const r=await get('http://ollama:11434/api/generate',{method:'POST',headers:{'Content-Type':'application/json'},signal:AbortSignal.timeout(120000),body:JSON.stringify({model:lock.model,stream:false,keep_alive:0,format:schema,options:{temperature:0,seed:42,num_ctx:lock.contextTokens,num_predict:lock.outputTokens,num_thread:4},system:'Escreva em portugues brasileiro. Analise somente os fatos ficticios fornecidos. Nao invente causa, ataque, risco percentual ou previsao. Declare historico insuficiente. Recomende investigacao humana, nunca executar comandos. Responda somente JSON com resumo, hipoteses e recomendacoes_preventivas. Seja breve: no maximo duas frases por campo e dois itens por lista.',prompt:'Cenario FICTICIO de viabilidade, nao incidente do laboratorio: API retornou HTTP diferente de 200 durante um intervalo observado de 60 segundos e depois respondeu 200. Um incidente registrado; nenhum dado de CPU, memoria ou logs e nenhum historico anterior. Produza uma analise com limitacoes e sugestoes preventivas, sem afirmar causa conhecida.'})});
  assert.equal(r.status,200);const result=await r.json();
  stage='model_completion';assert.equal(result.done,true);assert.equal(result.done_reason,'stop');
  stage='model_output_schema';
  assert.ok(Buffer.byteLength(result.response)<=8192);const value=JSON.parse(result.response);
  assert.deepEqual(Object.keys(value).sort(),schema.required.slice().sort());assert.equal(typeof value.resumo,'string');assert.ok(value.resumo.length>0&&value.resumo.length<=1500);
  for(const list of [value.hipoteses,value.recomendacoes_preventivas]){assert.ok(Array.isArray(list)&&list.length<=3);assert.ok(list.every(v=>typeof v==='string'&&v.length>0&&v.length<=1500&&!/[<>]/.test(v)));}
  pass('local_model_real_inference',{scope:'synthetic_fixture_not_real_incident',model:lock.model,manifestSha256:lock.manifestSha256,elapsedMs:Date.now()-started,outputTokens:result.eval_count,structuredOutput:true,analysis:value,semanticReviewPending:true});
 }else{
  const noAuth=await smtp(null,'operadora@lab.invalid',false);assert.equal(noAuth.mail,530);
  const wrong=await smtp('secureops:wrong','operadora@lab.invalid',false);assert.equal(wrong.auth,535);
  const auth=credential('mailpit-smtp-auth');const denied=await smtp(auth,'other@lab.invalid',false);assert.ok(denied.rcpt>=500);
  const accepted=await smtp(auth,'operadora@lab.invalid',true);assert.equal(accepted.accepted,true);
  const box=await(await get('http://mailpit:8025/api/v1/messages',{headers:{Authorization:'Basic '+Buffer.from(credential('mailpit-ui-auth')).toString('base64')}})).json();
  assert.ok(box.messages.some(m=>m.Subject===accepted.id));
  pass('local_smtp_auth_and_delivery',{scope:'fictitious_infrastructure_message_no_ai_report',unauthenticated:530,wrongAuth:535,otherRecipientDenied:true,smtpAccepted:true,visibleInMailbox:true,messageIdentifier:accepted.id,noMessagesDeleted:true});
 }
}catch{console.error(JSON.stringify({error:'automation_service_check_failed_values_omitted',phase,stage}));process.exitCode=1;}
