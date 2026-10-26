// Administracao separada e efemera. Nunca executar dentro do coletor.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

const base = 'http://keycloak.localhost:8080';
const realm = '/admin/realms/secureops-lab';
const apply = process.argv.includes('--apply-login-error-only');
const verify = process.argv.includes('--verify-permissions');
assert.ok(!(apply&&verify));
const output = '/provision';
const digest = x => createHash('sha256').update(JSON.stringify(x)).digest('hex');
let admin;
async function call(path, method = 'GET', body, token = admin) {
  const r = await fetch(base + path, { method, redirect: 'error', signal: AbortSignal.timeout(10000),
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  if (!r.ok) throw new Error(`admin_request_failed_${r.status}`);
  return r.status === 204 || r.status === 201 ? null : r.json();
}
async function getToken(client, secret, password) {
  const body = new URLSearchParams(password ? { grant_type: 'password', client_id: 'admin-cli', username: client, password } : { grant_type: 'client_credentials', client_id: client, client_secret: secret });
  const r = await fetch(`${base}/realms/${password ? 'master' : 'secureops-lab'}/protocol/openid-connect/token`, {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000), body });
  if (r.status !== 200) throw new Error(`token_failed_${r.status}`);
  const j = await r.json(); assert.equal(typeof j.access_token, 'string'); return j.access_token;
}
async function identitySnapshot() {
  const r = await call(realm);
  const clients = await call(realm + '/clients?clientId=secureops-gateway');
  assert.equal(clients.length, 1);
  const users = await call(realm + '/users?max=100');
  assert.ok(users.length < 100);
  const selected = [];
  for (const u of users.filter(u => !u.username.startsWith('service-account-'))) {
    const groups = await call(`${realm}/users/${u.id}/groups`);
    const credentials = await call(`${realm}/users/${u.id}/credentials`);
    selected.push({ id: u.id, username: u.username, enabled: u.enabled, requiredActions: u.requiredActions,
      groups: groups.map(g => ({ id: g.id, path: g.path })), credentials: credentials.map(c => ({ id: c.id, type: c.type, createdDate: c.createdDate })) });
  }
  return { realmId: r.id, sslRequired: r.sslRequired, bruteForceProtected: r.bruteForceProtected,
    browserFlow: r.browserFlow, otpPolicyType: r.otpPolicyType, otpPolicyAlgorithm: r.otpPolicyAlgorithm,
    gateway: clients[0], users: selected };
}
try {
  const env = Object.fromEntries(readFileSync('/bootstrap/keycloak.env','utf8').split(/\r?\n/).filter(Boolean).map(l => { const p=l.indexOf('='); return [l.slice(0,p),l.slice(p+1)]; }));
  admin = await getToken(env.KC_BOOTSTRAP_ADMIN_USERNAME, null, env.KC_BOOTSTRAP_ADMIN_PASSWORD);
  const beforeConfig = await call(realm + '/events/config');
  const beforeIdentity = await identitySnapshot();
  const matches = await call(realm + '/clients?clientId=secureops-event-reader');
  console.log(JSON.stringify({ mode: apply ? 'apply' : verify ? 'verify-permissions' : 'read-only', eventsEnabled: beforeConfig.eventsEnabled,
    eventsExpiration: beforeConfig.eventsExpiration ?? null, enabledTypesCount: beforeConfig.enabledEventTypes?.length,
    includesLoginError: beforeConfig.enabledEventTypes?.includes('LOGIN_ERROR'), readerExists: matches.length === 1,
    realmIdIsName: beforeIdentity.realmId === 'secureops-lab', bruteForceProtected: beforeIdentity.bruteForceProtected }));
  if(verify){
    assert.equal(matches.length,1);
    const serviceToken=await getToken('secureops-event-reader',readFileSync(output+'/collector-client-secret','utf8').trim());
    assert.deepEqual(await call(realm+'/events/config','GET',undefined,serviceToken),beforeConfig);
    const r=await call(realm);assert.equal(r.enabled,true);
    const users=await call(realm+'/users?username=operadora&exact=true');assert.equal(users.length,1);assert.equal(users[0].enabled,true);
    const tests=[[realm+'/events/config',beforeConfig],[realm,{enabled:true}],[`${realm}/users/${users[0].id}`,{enabled:true}]];
    const denied=[];
    for(const [path,body] of tests){
      const response=await fetch(base+path,{method:'PUT',redirect:'error',signal:AbortSignal.timeout(10000),headers:{Authorization:`Bearer ${serviceToken}`,'Content-Type':'application/json'},body:JSON.stringify(body)});
      assert.equal(response.status,403);denied.push(response.status);
    }
    assert.deepEqual(await call(realm+'/events/config'),beforeConfig);
    assert.equal(digest(await identitySnapshot()),digest(beforeIdentity));
    console.log(JSON.stringify({result:'pass',eventsConfigWrite:denied[0],realmWrite:denied[1],userWrite:denied[2],selectedIdentityUnchanged:true,noEffectiveMutation:true}));
    process.exit(0);
  }
  if (!apply) process.exit(0);
  if (matches.length || existsSync(output + '/collector-realm-id')) throw new Error('reader_already_exists_no_overwrite');
  // Confere premissa aprovada: nao substituir configuracao alterada por terceiros.
  assert.equal(beforeConfig.eventsEnabled, false);
  assert.equal(beforeConfig.adminEventsEnabled, false);
  const secret = readFileSync(output + '/collector-client-secret','utf8').trim();
  assert.match(secret, /^[a-f0-9]{64}$/);
  // Apenas configuracao de eventos (sem dados brutos) para diagnosticar eventual falha parcial.
  writeFileSync(output + '/events-config-before.json', JSON.stringify(beforeConfig), { flag: 'wx', mode: 0o600 });
  await call(realm + '/clients', 'POST', { clientId: 'secureops-event-reader', name: 'SecureOps event reader', enabled: true,
    protocol: 'openid-connect', publicClient: false, bearerOnly: false, secret,
    standardFlowEnabled: false, implicitFlowEnabled: false, directAccessGrantsEnabled: false,
    serviceAccountsEnabled: true, fullScopeAllowed: false, defaultClientScopes: [], optionalClientScopes: [], redirectUris: [], webOrigins: [] });
  const [client] = await call(realm + '/clients?clientId=secureops-event-reader');
  const account = await call(`${realm}/clients/${client.id}/service-account-user`);
  const defaultRoles = await call(`${realm}/users/${account.id}/role-mappings/realm`);
  if (defaultRoles.length) await call(`${realm}/users/${account.id}/role-mappings/realm`, 'DELETE', defaultRoles);
  const [management] = await call(realm + '/clients?clientId=realm-management');
  const role = await call(`${realm}/clients/${management.id}/roles/view-events`);
  await call(`${realm}/users/${account.id}/role-mappings/clients/${management.id}`, 'POST', [role]);
  await call(`${realm}/clients/${client.id}/scope-mappings/clients/${management.id}`, 'POST', [role]);
  const desiredConfig = { ...beforeConfig, eventsEnabled: true, eventsExpiration: 86400, enabledEventTypes: ['LOGIN_ERROR'] };
  await call(realm + '/events/config', 'PUT', desiredConfig);
  const afterConfig = await call(realm + '/events/config');
  assert.deepEqual(afterConfig, desiredConfig);
  const afterIdentity = await identitySnapshot();
  assert.equal(digest(afterIdentity), digest(beforeIdentity));
  writeFileSync(output + '/collector-realm-id', beforeIdentity.realmId, { flag: 'wx', mode: 0o600 });
  const serviceToken = await getToken('secureops-event-reader', secret);
  assert.deepEqual(await call(realm + '/events/config','GET',undefined,serviceToken), desiredConfig);
  const at = Date.now();
  const events = await call(`${realm}/events?client=secureops-gateway&type=LOGIN_ERROR&dateFrom=${at-300000}&dateTo=${at}&first=0&max=1001&direction=asc`,'GET',undefined,serviceToken);
  assert.ok(Array.isArray(events) && events.length <= 1000);
  // PUT identico: caso inesperadamente autorizado, nao altera configuracao efetiva.
  const denied = await fetch(base + realm + '/events/config', { method: 'PUT', signal: AbortSignal.timeout(10000), redirect: 'error',
    headers: { Authorization: `Bearer ${serviceToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify(desiredConfig) });
  assert.equal(denied.status, 403);
  assert.deepEqual(await call(realm + '/events/config'), desiredConfig);
  const mappings = await call(`${realm}/users/${account.id}/role-mappings`);
  assert.deepEqual(mappings.realmMappings ?? [], []);
  assert.deepEqual(Object.values(mappings.clientMappings ?? {}).flatMap(m => m.mappings.map(r => r.name)), ['view-events']);
  writeFileSync(output + '/reader-provisioned.json', JSON.stringify({ clientId: client.clientId, clientUuid: client.id, accountId: account.id,
    role: 'view-events', identityUnchanged: true, writeDeniedStatus: denied.status }), { flag: 'wx', mode: 0o600 });
  console.log(JSON.stringify({ result: 'pass', onlyLoginErrorStored: true, retentionSeconds: 86400, identityUnchanged: true,
    serviceReadConfig: true, serviceReadFilteredEvents: true, writeDeniedStatus: denied.status, roles: ['view-events'], initialWindowCount: events.length,
    realmWideReadPrivilege: true }));
} catch { console.error('event_reader_provision_failed_preserve_state_and_diagnose'); process.exitCode = 1; }
