import { readFileSync } from 'node:fs';
export function createApi({ token, url = 'http://zabbix-web:8080/api_jsonrpc.php', fetcher = fetch }) {
  let id = 0;
  return async (method, params = {}) => {
    const r = await fetcher(url, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(20000),
      headers: { 'Content-Type': 'application/json-rpc', ...(token && method !== 'apiinfo.version' && method !== 'user.login' ? { Authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify({ jsonrpc: '2.0', id: ++id, method, params }) });
    if (r.status !== 200) throw new Error(`zabbix_http_${r.status}`);
    const data = await r.json();
    // Nunca imprimir data.error.data: pode conter parametro com segredo.
    if (data.error) {
      const reason = new Map([['Not authorized.', 'not_authorized'], ['API token expired.', 'token_expired'],
        ['Session terminated, re-login, please.', 'session_terminated']]).get(data.error.data);
      if (reason) throw new Error(`zabbix_auth_${reason}`);
      throw new Error(`zabbix_api_${method}_${Number.isInteger(data.error.code)?data.error.code:-32500}`);
    }
    return data.result;
  };
}
export function localApi() {
  const token = readFileSync('/secrets/zabbix-api-token','utf8').trim();
  if (!/^[a-fA-F0-9]{64}$/.test(token)) throw new Error('invalid_local_api_token');
  return createApi({ token });
}
export const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
export async function waitFor(read, check, seconds, name) {
  const deadline = Date.now() + seconds * 1000;
  do {
    const state = await read();
    if (check(state)) return state;
    if (Date.now() > deadline) throw new Error(`timeout_${name}`);
    await sleep(2000);
  } while (true);
}
