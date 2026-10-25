import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const probePath = fileURLToPath(new URL('../scripts/probe.mjs', import.meta.url));

async function runProbe(t, handler) {
  const server = createServer(handler);
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const child = spawn(process.execPath, [probePath,
    `http://127.0.0.1:${server.address().port}/health`], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const closed = once(child, 'close');
  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
    await closed;
  });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const [code, signal] = await closed;
  assert.equal(signal, null);
  return { code, stdout, stderr };
}

for (const [name, status, contentType, body, expectedCode] of [
  ['saúde válida', 200, 'application/json', '{"status":"ok"}', 0],
  ['status inválido', 503, 'application/json', '{"status":"ok"}', 1],
  ['tipo inválido', 200, 'text/plain', '{"status":"ok"}', 1],
  ['JSON inválido', 200, 'application/json', 'invalid', 1],
  ['corpo divergente', 200, 'application/json', '{"status":"down"}', 1],
  ['campos extras', 200, 'application/json', '{"status":"ok","secret":"ficticio"}', 1],
  ['redirect', 302, 'application/json', '{"status":"ok"}', 1],
]) {
  test(`probe: ${name}`, async (t) => {
    const result = await runProbe(t, (_req, res) => {
      res.writeHead(status, { 'Content-Type': contentType, Location: '/health' });
      res.end(body);
    });
    assert.equal(result.code, expectedCode);
    assert.equal(result.stdout, expectedCode === 0 ? '{"event":"probe_succeeded"}\n' : '');
    assert.equal(result.stderr, expectedCode === 1 ? '{"event":"probe_failed"}\n' : '');
  });
}

test('probe: timeout abrange corpo que não termina', async (t) => {
  const started = performance.now();
  const result = await runProbe(t, (_req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.write('{"status":');
  });
  assert.equal(result.code, 1);
  assert.equal(result.stderr, '{"event":"probe_failed"}\n');
  const elapsed = performance.now() - started;
  assert.ok(elapsed >= 1900 && elapsed < 5000, `probe levou ${elapsed} ms`);
});
