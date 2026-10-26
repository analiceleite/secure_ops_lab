import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const dir=new URL('./',import.meta.url);
const load=name=>JSON.parse(readFileSync(new URL(name,dir),'utf8'));
const allowed=new Set(['n8n-nodes-base.scheduleTrigger','n8n-nodes-base.postgres','n8n-nodes-base.if',
  'n8n-nodes-base.set','n8n-nodes-base.httpRequest','n8n-nodes-base.emailSend']);

test('prompt não contém newline literal ou delimitador prematuro da expressão n8n',()=>{
  const w=load('incident-reports.json');
  const value=w.nodes.find(n=>n.id==='prompt').parameters.assignments.assignments.find(a=>a.name==='ollamaRequest').value;
  assert.ok(value.startsWith('={{ ') && value.endsWith(' }}'));
  const source=value.slice(3,-2);
  assert.ok(!source.includes('\n'), 'newline literal em string JavaScript');
  assert.ok(!source.includes('}}'), 'fechamento de objeto confundido com delimitador n8n');
  const request=new Function('$json',`return (${source})`)({claim:{snapshot:{duration_seconds:40}}});
  assert.equal(request.model,'qwen2.5:1.5b-instruct-q4_K_M');
  assert.deepEqual(request.format.required,['summary','hypotheses','recommendations']);
  assert.ok(request.prompt.includes('"duration_seconds":40'));
});

for(const [file,required] of [
  ['incident-reports.json',['scheduleTrigger','postgres','if','set','httpRequest']],
  ['incident-mail-delivery.json',['scheduleTrigger','postgres','if','emailSend']]
]) test(`${file}: workflow inativo, nodes permitidos e conexões fechadas`,()=>{
  const w=load(file);assert.equal(w.active,false);
  assert.ok(w.nodes.length>=required.length);
  assert.ok(w.nodes.every(n=>allowed.has(n.type)), 'node fora da allowlist n8n');
  assert.ok(required.every(t=>w.nodes.some(n=>n.type.endsWith('.'+t))));
  assert.ok(w.nodes.every(n=>!n.credentials), 'workflow não deve exigir credencial exportada');
  assert.ok(w.nodes.every(n=>!JSON.stringify(n).match(/"(?:password|webhook_key|smtp_password)"\s*:/i)));
  assert.ok(!JSON.stringify(w).match(/\b[a-f0-9]{64}\b/i), 'valor de segredo literal no export');
  const names=new Set(w.nodes.map(n=>n.name));
  for(const [from,outputs] of Object.entries(w.connections)){
    assert.ok(names.has(from));
    for(const output of outputs.main)for(const edge of output)assert.ok(names.has(edge.node));
  }
});

test('geração usa inferência local e SQL restrito por lease; não acessa webhook de eventos',()=>{
  const w=load('incident-reports.json');
  assert.ok(w.nodes.some(n=>n.parameters?.url==='http://ollama:11434/api/generate'));
  const http=w.nodes.find(n=>n.id==='ollama');
  assert.equal(http.parameters.contentType,'json');
  assert.equal(http.parameters.specifyBody,'json');
  assert.equal(http.parameters.jsonBody,'={{ $json.ollamaRequest }}');
  assert.ok(w.nodes.some(n=>n.parameters?.query?.includes('incident.claim_report_job')));
  assert.ok(w.nodes.some(n=>n.parameters?.query?.includes('incident.save_report')));
  assert.ok(w.nodes.every(n=>!JSON.stringify(n).includes('incident.ingest')));
  assert.ok(w.nodes.every(n=>!JSON.stringify(n).includes('localhost')));
});

test('envio tem origem/destino fictícios fixos e só registra SMTP aceito após node',()=>{
  const w=load('incident-mail-delivery.json');
  const mail=w.nodes.find(n=>n.type==='n8n-nodes-base.emailSend');
  assert.equal(mail.parameters.fromEmail,'secureops@lab.invalid');
  assert.equal(mail.parameters.toEmail,'operadora@lab.invalid');
  assert.equal(mail.parameters.options.ccEmail,undefined);
  assert.equal(mail.parameters.options.bccEmail,undefined);
  assert.ok(w.nodes.find(n=>n.name==='Reservar mensagem pendente').parameters.query.includes('claim_report_outbox'));
  assert.ok(w.nodes.find(n=>n.name==='Registrar aceite SMTP').parameters.query.includes("'accepted'"));
  assert.equal(w.connections['Enviar apenas ao Mailpit local'].main[0][0].node,'Registrar aceite SMTP');
});
