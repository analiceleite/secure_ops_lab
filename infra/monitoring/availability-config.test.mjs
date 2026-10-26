import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const text = readFileSync(new URL('./availability-host.json', import.meta.url), 'utf8');
const config = JSON.parse(text).zabbix_export;
const host = config.hosts[0];
const scenario = host.httptests[0];
const step = scenario.steps[0];

test('export 7.0 contem apenas um grupo e host ficticio, sem interfaces ou templates extras', () => {
  assert.equal(config.version, '7.0');
  assert.equal(config.host_groups.length, 1);
  assert.match(config.host_groups[0].uuid, /^[a-f0-9]{32}$/);
  assert.equal(config.hosts.length, 1);
  assert.equal(host.host, 'secureops-api');
  assert.equal(host.monitored_by, 'SERVER');
  assert.equal(host.status, 'ENABLED');
  assert.deepEqual(host.groups, [{ name: 'SecureOps Lab' }]);
  assert.equal(host.interfaces, undefined);
  assert.equal(host.templates, undefined);
});

test('cenario consulta somente API interna sem publicacao, credenciais ou parametros', () => {
  assert.equal(host.httptests.length, 1);
  assert.equal(scenario.name, 'api-health');
  assert.equal(scenario.authentication, 'NONE');
  assert.equal(scenario.steps.length, 1);
  assert.equal(step.name, 'health');
  assert.equal(step.url, 'http://api:3000/health');
  for (const forbidden of ['http_user', 'http_password', 'http_proxy', 'headers', 'variables']) {
    assert.equal(scenario[forbidden], undefined);
  }
  for (const forbidden of ['posts', 'query_fields', 'headers', 'variables']) {
    assert.equal(step[forbidden], undefined);
  }
});

test('checagem a cada 20s, timeout 5s, uma tentativa e somente HTTP 200 sem redirects', () => {
  assert.equal(scenario.delay, '20s');
  assert.equal(scenario.attempts, '1');
  assert.equal(scenario.status, 'ENABLED');
  assert.equal(step.timeout, '5s');
  assert.equal(step.status_codes, '200');
  assert.equal(step.follow_redirects, 'NO');
  assert.equal(step.retrieve_mode, 'BODY');
});

test('trigger de falha usa resultado nativo do cenario, nao captura excecao como zero', () => {
  assert.equal(config.triggers.length, 2);
  assert.equal(config.triggers[0].expression, 'last(/secureops-api/web.test.fail[api-health])<>0');
  assert.equal(config.triggers[0].recovery_mode, 'EXPRESSION');
  assert.equal(config.triggers[0].recovery_expression, undefined);
});

test('ausencia de dados tem trigger tecnica separada de 90s sem recuperar falha HTTP', () => {
  assert.equal(config.triggers[1].expression, 'nodata(/secureops-api/web.test.fail[api-health],90s)=1');
  assert.equal(config.triggers[1].recovery_mode, 'EXPRESSION');
  assert.equal(config.triggers[0].expression.includes('nodata'), false);
});

test('triggers Single, sem fechamento manual nem notificacoes ou comandos', () => {
  for (const trigger of config.triggers) {
    assert.equal(trigger.type, 'SINGLE');
    assert.equal(trigger.manual_close, 'NO');
    assert.equal(trigger.status, 'ENABLED');
    assert.equal(trigger.dependencies, undefined);
  }
  assert.deepEqual(Object.keys(config).sort(), ['host_groups', 'hosts', 'triggers', 'version']);
});

test('tags estaveis separam disponibilidade e problema de coleta', () => {
  assert.deepEqual(host.tags, [{ tag: 'service', value: 'secureops-api' }]);
  assert.deepEqual(scenario.tags, config.triggers[0].tags);
  assert.deepEqual(config.triggers[0].tags, [
    { tag: 'service', value: 'secureops-api' },
    { tag: 'category', value: 'availability' }
  ]);
  assert.deepEqual(config.triggers[1].tags, [
    { tag: 'service', value: 'secureops-api' },
    { tag: 'category', value: 'collection' }
  ]);
});

test('arquivo nao altera usuarios, identidade, housekeeping global ou integra a entrega 04', () => {
  assert.equal(config.users, undefined);
  assert.equal(config.media_types, undefined);
  assert.equal(config.macros, undefined);
  assert.equal(/n8n|keycloak|bearer|password|cookie|oauth2/i.test(text), false);
});
