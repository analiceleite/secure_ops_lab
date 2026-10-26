import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
try {
  const secret = readFileSync('/secrets/collector-metrics-secret','utf8').trim();
  const url = 'http://identity-event-collector:3001/metrics';
  for (const headers of [{}, { 'X-SecureOps-Metrics-Key': 'invalid-fictitious-key' }]) {
    const r = await fetch(url, { headers, redirect: 'error', signal: AbortSignal.timeout(15000) });
    assert.equal(r.status, 401);
  }
  const r = await fetch(url, { headers: { 'X-SecureOps-Metrics-Key': secret }, redirect: 'error', signal: AbortSignal.timeout(15000) });
  assert.equal(r.status, 200);
  const sample = await r.json();
  assert.equal(sample.contract_version, 1);
  assert.equal(sample.realm, 'secureops-lab');
  assert.equal(sample.client, 'secureops-gateway');
  assert.equal(sample.window_seconds, 300);
  assert.ok(Math.abs(Date.now() - sample.sampled_at) < 15000);
  if (process.argv.includes('--expect-failure')) {
    assert.equal(sample.collection_ok, 0);
    assert.ok(!('login_errors_5m' in sample));
  } else {
    assert.equal(sample.collection_ok, 1);
    assert.ok(Number.isSafeInteger(sample.login_errors_5m) && sample.login_errors_5m >= 0 && sample.login_errors_5m <= 1000);
  }
  assert.deepEqual(Object.keys(sample).sort(), ['contract_version','realm','client','window_seconds','sampled_at','collection_ok',sample.collection_ok ? 'login_errors_5m':'error'].sort());
  assert.ok(!JSON.stringify(sample).includes(secret));
  console.log(JSON.stringify({ check: 'collector_runtime', unauthorizedStatus: 401, result: 'pass', sample }));
} catch { console.error('collector_check_failed_values_omitted'); process.exitCode = 1; }
