import { readFileSync } from 'node:fs';
import { createCollector, createMetricsServer } from './collector.ts';

try {
  const clientSecret = readFileSync('/run/secrets/collector-client-secret', 'utf8').trim();
  const metricsSecret = readFileSync('/run/secrets/collector-metrics-secret', 'utf8').trim();
  const realmId = readFileSync('/run/secrets/collector-realm-id', 'utf8').trim();
  if (!/^[a-f0-9]{64}$/.test(clientSecret) || !/^[a-f0-9]{64}$/.test(metricsSecret)) throw new Error();
  if (!/^[a-zA-Z0-9_-]{1,128}$/.test(realmId)) throw new Error();
  const server = createMetricsServer(createCollector({ clientSecret, realmId }), metricsSecret);
  server.on('error', () => { console.error('collector_server_failed'); process.exitCode = 1; });
  server.listen(3001, '0.0.0.0', () => console.log('collector_started'));
  for (const signal of ['SIGTERM', 'SIGINT'] as const) {
    process.on(signal, () => { server.close(); setTimeout(() => process.exit(0), 12_000).unref(); });
  }
} catch { console.error('collector_start_failed'); process.exitCode = 1; }
