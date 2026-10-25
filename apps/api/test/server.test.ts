import assert from 'node:assert/strict';
import { once } from 'node:events';
import { request } from 'node:http';
import type { AddressInfo } from 'node:net';
import { test, type TestContext } from 'node:test';
import { createApplicationServer } from '../src/server.js';

async function startServer(t: TestContext) {
  const server = createApplicationServer();
  t.after(async () => {
    server.closeAllConnections();
    if (server.listening) {
      await new Promise<void>((resolve, reject) => {
        server.close((error) => error ? reject(error) : resolve());
      });
    }
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const { port } = server.address() as AddressInfo;

  return (path: string, method = 'GET') => new Promise<{
    status: number | undefined;
    headers: Record<string, string | string[] | undefined>;
    body: string;
  }>((resolve, reject) => {
    const req = request({
      hostname: '127.0.0.1', port, path, method, agent: false,
      signal: AbortSignal.timeout(2000),
      headers: { Authorization: 'Bearer ficticio-nao-registrar' },
    }, (response) => {
      response.setEncoding('utf8');
      let body = '';
      response.on('data', (chunk: string) => { body += chunk; });
      response.once('error', reject);
      response.once('end', () => resolve({
        status: response.statusCode, headers: response.headers, body,
      }));
    });
    req.once('error', reject);
    req.end();
  });
}

for (const [path, expected] of [
  ['/health', { status: 'ok' }],
  ['/health?probe=1', { status: 'ok' }],
  ['/', { service: 'secureops-api', message: 'Serviço fictício do laboratório' }],
  ['/?probe=1', { service: 'secureops-api', message: 'Serviço fictício do laboratório' }],
] as const) {
  test(`GET ${path} retorna somente o JSON esperado`, async (t) => {
    const send = await startServer(t);
    const response = await send(path);
    assert.equal(response.status, 200);
    assert.equal(response.headers['content-type'], 'application/json');
    assert.equal(response.headers['allow'], undefined);
    assert.deepEqual(JSON.parse(response.body), expected);
  });
}

for (const path of ['/nao-existe', '/health/', '/admin', '/shutdown', '/__proto__']) {
  test(`GET ${path} retorna 404 sem refletir dados da requisição`, async (t) => {
    const send = await startServer(t);
    const response = await send(path);
    assert.equal(response.status, 404);
    assert.equal(response.headers['content-type'], 'application/json');
    assert.deepEqual(JSON.parse(response.body), { error: 'not_found' });
  });
}

for (const path of ['/', '/health']) {
  for (const method of ['POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS', 'HEAD']) {
    test(`${method} ${path} retorna 405 e Allow: GET`, async (t) => {
      const send = await startServer(t);
      const response = await send(path, method);
      assert.equal(response.status, 405);
      assert.equal(response.headers['content-type'], 'application/json');
      assert.equal(response.headers['allow'], 'GET');
      // HTTP HEAD preserva status/headers, mas nunca transporta corpo.
      if (method === 'HEAD') assert.equal(response.body, '');
      else assert.deepEqual(JSON.parse(response.body), { error: 'method_not_allowed' });
    });
  }
}

test('caminho inexistente tem precedência sobre método não suportado', async (t) => {
  const send = await startServer(t);
  const response = await send('/nao-existe', 'POST');
  assert.equal(response.status, 404);
  assert.deepEqual(JSON.parse(response.body), { error: 'not_found' });
});
