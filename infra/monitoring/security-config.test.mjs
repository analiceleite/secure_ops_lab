import { test } from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { masterItem, dependentItems, securityTriggers, validateSample, extractCount } from './security-config.mjs';
import { createApi } from './zabbix-api.mjs';
const run = (source, value) => vm.runInNewContext(`(function(value){${source}})(input)`, { input: JSON.stringify(value) }, { timeout: 1000 });
const common = () => ({ contract_version: 1, realm: 'secureops-lab', client: 'secureops-gateway', window_seconds: 300, sampled_at: Date.now() });
test('amostra valida 0/1/4/5 nao soma', () => {
  for (const count of [0,1,4,5]) {
    const sample = { ...common(), collection_ok: 1, login_errors_5m: count };
    assert.equal(JSON.parse(run(validateSample, sample)).login_errors_5m, count);
    assert.equal(run(extractCount, sample), count);
  }
});
test('falha valida preserva qualidade mas descarta contagem, sem zero', () => {
  const sample = { ...common(), collection_ok: 0, error: 'provider_auth' };
  assert.equal(JSON.parse(run(validateSample, sample)).collection_ok, 0);
  assert.equal(run(extractCount, sample), null);
});
for (const [name, extra] of Object.entries({ stale: { sampled_at: 0 }, future: { sampled_at: Date.now()+100000 }, count: { login_errors_5m: -1 }, scope: { client: 'other' }, leak: { userId: 'SENSITIVE' }, version: { contract_version: 2 } })) {
  test(`preprocessamento rejeita ${name}`, () => assert.throws(() => run(validateSample, { ...common(), collection_ok: 1, login_errors_5m: 5, ...extra })));
}
test('contrato do master e dependentes', () => {
  const item = masterItem('1');
  assert.equal(item.delay, '30s'); assert.equal(item.timeout, '15s'); assert.equal(item.follow_redirects, 0);
  assert.equal(item.headers[0].value, '{$SECUREOPS_METRICS_KEY}');
  assert.equal(item.type, 19);
  const [count, quality] = dependentItems('1','2');
  assert.equal(count.type,18); assert.equal(count.master_itemid,'2'); assert.ok(count.preprocessing[0].params.includes('return null'));
  assert.equal(quality.preprocessing[0].params,'$.collection_ok');
});
test('trigger Single sem recuperacao por perda de frescor na contagem', () => {
  const [auth, quality] = securityTriggers();
  assert.equal(auth.expression,'last(/secureops-api/secureops.auth.errors5m)>=5');
  assert.ok(!auth.expression.includes('nodata')); assert.equal(auth.type,0); assert.equal(auth.manual_close,0);
  assert.equal(quality.recovery_mode,1); assert.ok(quality.recovery_expression.includes('=1 and nodata('));
});
test('API omite autorizacao em versao e nao inclui token no corpo',async()=>{
  const calls=[];
  const api=createApi({token:'FICTITIOUS-TOKEN',fetcher:async(url,init)=>{calls.push(init);return new Response(JSON.stringify({result:'7.0.32'}));}});
  await api('apiinfo.version');await api('host.get');
  assert.ok(!('Authorization' in calls[0].headers));assert.equal(calls[1].headers.Authorization,'Bearer FICTITIOUS-TOKEN');
  assert.ok(!calls[1].body.includes('FICTITIOUS-TOKEN'));
});
test('erro da API nao reflete parametros sensiveis',async()=>{
  const api=createApi({token:'FICTITIOUS',fetcher:async()=>new Response(JSON.stringify({error:{code:-32602,data:'SENSITIVE-PARAMETER'}}))});
  await assert.rejects(api('item.create'),{message:'zabbix_api_item.create_-32602'});
});
test('expiracao e negativa recebem apenas categorias fixas',async()=>{
  for(const [data,reason] of [['API token expired.','token_expired'],['Not authorized.','not_authorized'],['Session terminated, re-login, please.','session_terminated']]){
    const api=createApi({token:'FICTITIOUS',fetcher:async()=>new Response(JSON.stringify({error:{code:-32500,data}}))});
    await assert.rejects(api('host.get'),{message:`zabbix_auth_${reason}`});
  }
});
test('campos inesperados em erro nao vazam codigo ou prototipo',async()=>{
  const api=createApi({token:'FICTITIOUS',fetcher:async()=>new Response(JSON.stringify({error:{code:'SENSITIVE',data:'__proto__'}}))});
  await assert.rejects(api('host.get'),{message:'zabbix_api_host.get_-32500'});
});
