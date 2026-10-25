import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createServer } from 'node:net';
import type { AddressInfo } from 'node:net';
import { createInterface } from 'node:readline';
import { test, type TestContext } from 'node:test';

interface LogEntry {
  timestamp: string;
  event: string;
  port?: number;
  signal?: string;
  code?: string;
}

function launch(t: TestContext, port = 0, entrypoint = false, stalledResponse = false) {
  const moduleUrl = new URL('../src/main.js', import.meta.url).href;
  const child = entrypoint
    ? spawn(process.execPath, [new URL('../src/main.js', import.meta.url).pathname], {
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    : spawn(process.execPath, ['--input-type=module', '-e',
      `import { startApplication } from ${JSON.stringify(moduleUrl)}; ` +
      `const server = startApplication({host:'127.0.0.1',port:${port}});` +
      (stalledResponse
        ? `server.removeAllListeners('request'); ` +
          `server.on('request', (_req, res) => { res.writeHead(200); res.write('partial'); });`
        : '')], {
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  const stdout: LogEntry[] = [];
  const stderr: LogEntry[] = [];
  const out = createInterface({ input: child.stdout });
  const err = createInterface({ input: child.stderr });
  const ready = once(out, 'line').then(([line]) => JSON.parse(line as string) as LogEntry);
  out.on('line', (line) => stdout.push(JSON.parse(line) as LogEntry));
  err.on('line', (line) => stderr.push(JSON.parse(line) as LogEntry));
  const closed = once(child, 'close');
  // Não deixar uma rejeição sem observador se o processo falhar antes da prontidão.
  void ready.catch(() => {});
  void closed.catch(() => {});
  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
    await closed;
    out.close();
    err.close();
  });
  return { child, stdout, stderr, ready, closed };
}

function assertSanitizedLogs(entries: LogEntry[]) {
  for (const entry of entries) {
    assert.equal(new Date(entry.timestamp).toISOString(), entry.timestamp);
    assert.ok(['startup_completed', 'startup_failed', 'shutdown_started',
      'shutdown_completed', 'shutdown_timeout', 'shutdown_failed'].includes(entry.event));
    for (const key of Object.keys(entry)) {
      assert.ok(['timestamp', 'event', 'port', 'signal', 'code'].includes(key));
    }
  }
}

for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  test(`${signal} encerra com código zero e logs UTC sanitizados`, async (t) => {
    const app = launch(t);
    const startup = await app.ready;
    assert.equal(startup.event, 'startup_completed');
    assert.ok(startup.port! > 0);
    const response = await fetch(`http://127.0.0.1:${startup.port}/health`, {
      signal: AbortSignal.timeout(2000),
      headers: { Authorization: 'Bearer ficticio-nao-registrar' },
    });
    assert.deepEqual(await response.json(), { status: 'ok' });

    const started = performance.now();
    app.child.kill(signal);
    const [code, exitSignal] = await app.closed;
    assert.equal(code, 0);
    assert.equal(exitSignal, null);
    assert.ok(performance.now() - started < 5000);
    assert.deepEqual(app.stdout.map((entry) => entry.event), [
      'startup_completed', 'shutdown_started', 'shutdown_completed',
    ]);
    assert.equal(app.stdout[1]?.signal, signal);
    assert.deepEqual(app.stderr, []);
    assertSanitizedLogs(app.stdout);
  });
}

test('porta ocupada no container provoca EADDRINUSE e saída não zero', async (t) => {
  const blocker = createServer();
  t.after(async () => {
    await new Promise<void>((resolve, reject) => {
      blocker.close((error) => error ? reject(error) : resolve());
    });
  });
  blocker.listen(0, '127.0.0.1');
  await once(blocker, 'listening');
  const app = launch(t, (blocker.address() as AddressInfo).port);
  const [code, signal] = await app.closed;
  assert.equal(code, 1);
  assert.equal(signal, null);
  assert.deepEqual(app.stdout, []);
  assert.equal(app.stderr.length, 1);
  assert.equal(app.stderr[0]?.event, 'startup_failed');
  assert.equal(app.stderr[0]?.code, 'EADDRINUSE');
  assertSanitizedLogs(app.stderr);
});

test('entrypoint usa porta 3000 e atende HTTP antes da parada', async (t) => {
  // Porta fixa apenas no container de teste, nunca publicada no host.
  const app = launch(t, 0, true);
  const startup = await app.ready;
  assert.equal(startup.port, 3000);
  const response = await fetch('http://127.0.0.1:3000/', {
    signal: AbortSignal.timeout(2000),
  });
  assert.equal(response.status, 200);
  await response.arrayBuffer();
  app.child.kill('SIGTERM');
  assert.deepEqual(await app.closed, [0, null]);
});

test('conexão ativa é interrompida no prazo de 5s de encerramento', async (t) => {
  // Somente o subprocesso de teste troca o handler por uma resposta que não termina.
  // Não adicionamos rota de simulação ou opção de falha ao entrypoint real.
  const app = launch(t, 0, false, true);
  const startup = await app.ready;
  const response = await fetch(`http://127.0.0.1:${startup.port}/`, {
    signal: AbortSignal.timeout(9000),
  });
  const body = response.text().then(() => 'completed', () => 'interrupted');
  const started = performance.now();
  app.child.kill('SIGTERM');
  const [code, signal] = await app.closed;
  const elapsed = performance.now() - started;
  assert.equal(code, 1);
  assert.equal(signal, null);
  assert.ok(elapsed >= 4900 && elapsed < 8000, `encerramento levou ${elapsed} ms`);
  assert.equal(await body, 'interrupted');
  assert.deepEqual(app.stderr.map((entry) => entry.event), ['shutdown_timeout']);
  assertSanitizedLogs([...app.stdout, ...app.stderr]);
});
