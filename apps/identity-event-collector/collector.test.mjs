import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createServer } from 'node:http';
import { createCollector, createMetricsServer, countWindow, validateConfig, limitedJson, MAX_BYTES } from './collector.ts';

const at = 1_800_000_000_000;
const event = (i, extra = {}) => ({ id: `lab-${i}`, time: at - i, realmId: 'secureops-lab', clientId: 'secureops-gateway', type: 'LOGIN_ERROR', ...extra });
const config = { eventsEnabled: true, enabledEventTypes: ['LOGIN_ERROR'], eventsExpiration: 86400 };
const json = (x, status = 200) => new Response(JSON.stringify(x), { status });
function fixture(overrides = {}) {
  const calls = [];
  const options = { now: () => at, clientSecret: 'fictitious-client-secret', realmId: 'secureops-lab', fetcher: async (url, init) => {
    calls.push({ url, init });
    if (url.includes('/token')) return overrides.token?.() ?? json({ access_token: 'FICTITIOUS-TOKEN', token_type: 'Bearer', expires_in: 30 });
    if (url.endsWith('/config')) return overrides.config?.() ?? json(config);
    return overrides.events?.() ?? json([]);
  }, ...overrides.options };
  return { ...createCollector(options), calls };
}

for (const count of [0, 1, 4, 5, 1000]) {
  test(`janela completa de ${count} eventos`, () => assert.equal(countWindow(Array.from({ length: count }, (_, i) => event(i)), at), count));
}
test('fronteiras inclusivas', () => assert.equal(countWindow([event(0), event(1, { time: at - 300000 })], at), 2));
test('realmId interno nao e confundido com nome logico do realm', () => {
  assert.equal(countWindow([event(1, { realmId: 'fictitious-realm-id' })],at,'fictitious-realm-id'),1);
  assert.throws(() => countWindow([event(1)],at,'fictitious-realm-id'));
});
for (const [name, change] of Object.entries({ passado: { time: at - 300001 }, futuro: { time: at + 1 }, client: { clientId: 'other' }, realm: { realmId: 'other' }, tipo: { type: 'LOGIN' }, id: { id: '' }, idAusente: { id: undefined }, timestamp: { time: '123' } })) {
  test(`rejeita ${name}`, () => assert.throws(() => countWindow([event(1, change)], at)));
}
test('deduplica somente identidade consistente', () => {
  assert.equal(countWindow([event(1), event(1)], at), 1);
  assert.throws(() => countWindow([event(1), event(1, { time: at })], at));
});
test('limite de eventos nunca retorna parcial', () => assert.throws(() => countWindow(Array.from({ length: 1001 }, (_, i) => event(i)), at)));
for (const [name, value] of Object.entries({ disabled: { ...config, eventsEnabled: false }, types: { ...config, enabledEventTypes: [] }, broadTypes: { ...config, enabledEventTypes: ['LOGIN_ERROR','LOGIN'] }, retention: { ...config, eventsExpiration: 0 }, schema: [] })) {
  test(`configuracao ${name} invalida`, () => assert.throws(() => validateConfig(value)));
}
test('teto de bytes e JSON invalido', async () => {
  await assert.rejects(limitedJson(new Response('x'.repeat(MAX_BYTES + 1))));
  await assert.rejects(limitedJson(new Response('{')));
});
test('consulta fixa, filtros, cache e polling sem soma', async () => {
  const f = fixture({ events: () => json([event(1)]) });
  assert.equal((await f.collect()).login_errors_5m, 1);
  assert.equal((await f.collect()).login_errors_5m, 1);
  assert.equal(f.calls.filter(c => c.url.includes('/token')).length, 1);
  const url = new URL(f.calls.find(c => c.url.includes('/events?')).url);
  assert.deepEqual(Object.fromEntries(url.searchParams), { client: 'secureops-gateway', type: 'LOGIN_ERROR', dateFrom: String(at - 300000), dateTo: String(at), first: '0', max: '1001', direction: 'asc' });
});
for (const [name, overrides] of Object.entries({
  token401: { token: () => json({ secret: 'SENSITIVE' }, 401) },
  tokenSchema: { token: () => json({ access_token: 'SENSITIVE' }) },
  forbidden: { events: () => json({ secret: 'SENSITIVE' }, 403) },
  expired: { events: () => json({ secret: 'SENSITIVE' }, 401) },
  status500: { events: () => json({ secret: 'SENSITIVE' }, 500) },
  invalidJson: { events: () => new Response('SENSITIVE') },
  invalidSchema: { events: () => json({ secret: 'SENSITIVE' }) },
  configDisabled: { config: () => json({ ...config, eventsEnabled: false }) },
  eventLimit: { events: () => json(Array.from({ length: 1001 }, (_, i) => event(i))) },
  bytes: { events: () => new Response('SENSITIVE'.repeat(MAX_BYTES)) },
  transport: { events: () => { throw new Error('SENSITIVE'); } }
})) {
  test(`falha sanitizada sem zero: ${name}`, async () => {
    const f = fixture(overrides);
    const sample = await f.collect();
    assert.equal(sample.collection_ok, 0);
    assert.ok(!('login_errors_5m' in sample));
    assert.ok(!JSON.stringify(sample).includes('SENSITIVE'));
  });
}
test('token expira, renova uma vez, 401 invalida cache sem retry em loop', async () => {
  let clock = at;
  const f = fixture({ options: { now: () => clock }, events: () => json([], 401) });
  await f.collect(); await f.collect();
  assert.equal(f.calls.filter(c => c.url.includes('/token')).length, 2);
  const good = fixture({ options: { now: () => clock } });
  await good.collect(); clock += 21000; await good.collect();
  assert.equal(good.calls.filter(c => c.url.includes('/token')).length, 2);
});
test('saida agregada nao contem IDs, IP, email ou detalhes', async () => {
  const sample = await fixture({ events: () => json([event(1, { ipAddress: 'SENSITIVE-IP', userId: 'SENSITIVE-USER', details: { email: 'SENSITIVE-EMAIL' } })]) }).collect();
  assert.deepEqual(sample, { contract_version: 1, realm: 'secureops-lab', client: 'secureops-gateway', window_seconds: 300, sampled_at: at, collection_ok: 1, login_errors_5m: 1 });
});
test('timeout real de transporte e concorrencia limitada', async t => {
  const upstream = createServer((_req, _res) => {});
  upstream.listen(0, '127.0.0.1'); await once(upstream, 'listening');
  t.after(() => { upstream.closeAllConnections(); upstream.close(); });
  const c = createCollector({ clientSecret: 'fictitious', realmId: 'secureops-lab', baseUrl: `http://127.0.0.1:${upstream.address().port}`, timeoutMs: 100 });
  const pending = c.collect();
  assert.equal((await c.collect()).error, 'busy');
  assert.equal((await pending).error, 'timeout');
});
test('endpoint autenticado nega antes de consultar, rejeita parametros/metodo e nao reflete segredos', async t => {
  let calls = 0;
  const secret = 'f'.repeat(64);
  const server = createMetricsServer({ collect: async () => { calls++; return { collection_ok: 1 }; } }, secret);
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  for (const headers of [{}, { 'X-SecureOps-Metrics-Key': 'wrong' }]) assert.equal((await fetch(base + '/metrics', { headers })).status, 401);
  assert.equal(calls, 0);
  const headers = { 'X-SecureOps-Metrics-Key': secret };
  assert.equal((await fetch(base + '/metrics?realm=other', { headers })).status, 404);
  assert.equal((await fetch(base + '/metrics', { method: 'POST', headers })).status, 404);
  assert.equal(calls, 0);
  const response = await fetch(base + '/metrics', { headers });
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await response.json(), { collection_ok: 1 });
  assert.equal(calls, 1);
});
