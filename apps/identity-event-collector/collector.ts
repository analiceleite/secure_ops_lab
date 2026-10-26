import { timingSafeEqual } from 'node:crypto';
import { createServer, type IncomingMessage } from 'node:http';

export const REALM = 'secureops-lab';
export const CLIENT = 'secureops-gateway';
export const SERVICE_CLIENT = 'secureops-event-reader';
export const WINDOW_MS = 300_000;
export const MAX_EVENTS = 1000;
export const MAX_BYTES = 2 * 1024 * 1024;
type Json = Record<string, unknown>;
class CollectionError extends Error {}
const fail = (code: string): never => { throw new CollectionError(code); };
const record = (value: unknown): value is Json => typeof value === 'object' && value !== null && !Array.isArray(value);

// Streaming com teto efetivo, inclusive sem Content-Length. Nunca propagar corpo/URL/headers em erros.
export async function limitedJson(response: Response, limit = MAX_BYTES): Promise<unknown> {
  if (!response.body) return fail('schema');
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); return fail('response_limit'); }
      chunks.push(value);
    }
    try { return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown; }
    catch { return fail('schema'); }
  } finally { reader.releaseLock(); }
}

export function validateConfig(value: unknown): void {
  if (!record(value) || value.eventsEnabled !== true || !Array.isArray(value.enabledEventTypes)
    || value.enabledEventTypes.length !== 1 || value.enabledEventTypes[0] !== 'LOGIN_ERROR' || value.eventsExpiration !== 86400) fail('events_config');
}

export function countWindow(value: unknown, at: number, realmId = REALM): number {
  if (!Array.isArray(value)) return fail('schema');
  // max=1001 comprova truncamento para a janela aceita <=1000. Nao publicar parcial.
  if (value.length > MAX_EVENTS) return fail('event_limit');
  const ids = new Map<string, string>();
  for (const event of value) {
    if (!record(event) || typeof event.id !== 'string' || event.id.length === 0 || event.id.length > 256
      || !Number.isSafeInteger(event.time) || (event.time as number) < at - WINDOW_MS || (event.time as number) > at
      || event.realmId !== realmId || event.clientId !== CLIENT || event.type !== 'LOGIN_ERROR') return fail('event_scope');
    // Duplicacao de ID deve representar exatamente o mesmo evento, nao mascarar divergencia.
    const canonical = JSON.stringify(Object.entries(event).sort(([a], [b]) => a.localeCompare(b)));
    if (ids.has(event.id) && ids.get(event.id) !== canonical) return fail('event_duplicate');
    ids.set(event.id, canonical);
  }
  return ids.size;
}

export function createCollector(options: {
  clientSecret: string; realmId: string; baseUrl?: string; fetcher?: typeof fetch; now?: () => number; timeoutMs?: number;
}) {
  const base = options.baseUrl ?? 'http://keycloak.localhost:8080';
  const request = options.fetcher ?? fetch;
  const now = options.now ?? Date.now;
  let token: { value: string; until: number } | undefined;
  let busy = false;

  async function collect() {
    const at = now();
    const common = { contract_version: 1, realm: REALM, client: CLIENT, window_seconds: 300, sampled_at: at };
    if (busy) return { ...common, collection_ok: 0, error: 'busy' };
    busy = true;
    const signal = AbortSignal.timeout(options.timeoutMs ?? 10_000);
    async function get(path: string): Promise<unknown> {
      const response = await request(base + path, { signal, redirect: 'error', headers: { Authorization: `Bearer ${token!.value}` } });
      if (response.status === 401) { token = undefined; return fail('provider_auth'); }
      if (response.status === 403) return fail('provider_permission');
      if (response.status !== 200) return fail('provider_status');
      return limitedJson(response);
    }
    try {
      if (!token || token.until <= now()) {
        const response = await request(`${base}/realms/${REALM}/protocol/openid-connect/token`, {
          method: 'POST', signal, redirect: 'error', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ grant_type: 'client_credentials', client_id: SERVICE_CLIENT, client_secret: options.clientSecret })
        });
        if (response.status !== 200) return fail('provider_auth');
        const data = await limitedJson(response);
        if (!record(data) || typeof data.access_token !== 'string' || data.access_token.length < 1
          || data.token_type !== 'Bearer' || typeof data.expires_in !== 'number' || !Number.isFinite(data.expires_in)
          || data.expires_in <= 10 || data.expires_in > 86400) return fail('token_schema');
        token = { value: data.access_token, until: now() + (data.expires_in - 10) * 1000 };
      }
      validateConfig(await get(`/admin/realms/${REALM}/events/config`));
      const query = new URLSearchParams({ client: CLIENT, type: 'LOGIN_ERROR', dateFrom: String(at - WINDOW_MS),
        dateTo: String(at), first: '0', max: '1001', direction: 'asc' });
      const count = countWindow(await get(`/admin/realms/${REALM}/events?${query}`), at, options.realmId);
      return { ...common, collection_ok: 1, login_errors_5m: count };
    } catch (error) {
      const code = signal.aborted ? 'timeout' : error instanceof CollectionError ? error.message : 'transport';
      return { ...common, collection_ok: 0, error: code };
    } finally { busy = false; }
  }
  return { collect };
}

export function createMetricsServer(collector: ReturnType<typeof createCollector>, secret: string) {
  if (secret.length < 32 || secret.length > 256) throw new Error('invalid_metrics_secret');
  const expected = Buffer.from(secret);
  function authorized(req: IncomingMessage): boolean {
    const header = req.headers['x-secureops-metrics-key'];
    if (typeof header !== 'string') return false;
    const actual = Buffer.from(header);
    return expected.length === actual.length && timingSafeEqual(expected, actual);
  }
  const server = createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', 'application/json');
    if (!authorized(req)) { res.writeHead(401).end('{"error":"unauthorized"}'); return; }
    if (req.method !== 'GET' || req.url !== '/metrics') { res.writeHead(404).end('{"error":"not_found"}'); return; }
    res.writeHead(200).end(JSON.stringify(await collector.collect()));
  });
  server.requestTimeout = 15_000;
  server.headersTimeout = 5_000;
  server.maxHeadersCount = 32;
  return server;
}
