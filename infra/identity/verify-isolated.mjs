// Exercita o binário real do gateway com um emissor exclusivamente diagnóstico.
// Sem contas reais, sem portas no host; chaves de assinatura somente em memória.
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, randomUUID, sign, verify } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { setTimeout as delay } from 'node:timers/promises';

const issuer = 'http://oidc-verifier-issuer:8080/realms/test';
const gateway = 'http://oidc-verifier-gateway:4180';
if (process.argv.includes('--ready')) {
  let ready = false;
  for (let i = 0; i < 100; i++) {
    try { ready = (await fetch('http://127.0.0.1:8080/realms/test/.well-known/openid-configuration', { signal: AbortSignal.timeout(500) })).ok; } catch { /* startup */ }
    if (ready) break;
    await delay(100);
  }
  process.exit(ready ? 0 : 1);
}
const config = readFileSync('/checks/proxy.cfg', 'utf8');
const clientId = JSON.parse(/^client_id = (.+)$/m.exec(config)[1]);
const clientSecret = JSON.parse(/^client_secret = (.+)$/m.exec(config)[1]);
const mainKey = generateKeyPairSync('rsa', { modulusLength: 2048 });
const otherKey = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...mainKey.publicKey.export({ format: 'jwk' }), kid: 'isolated-key', alg: 'RS256', use: 'sig' };
const codes = new Map();
const accessTokens = new Map();
let scenario = 'positive';
let tokenCalls = 0;
let successfulTokenResponses = 0;
let upstreamCalls = 0;

function jwt(claims, key = mainKey.privateKey) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const input = `${encode({ alg: 'RS256', typ: 'JWT', kid: jwk.kid })}.${encode(claims)}`;
  return `${input}.${sign('RSA-SHA256', Buffer.from(input), key).toString('base64url')}`;
}

function identity(mode) {
  const result = { sub: 'fictitious-subject', email: 'operadora@lab.example', email_verified: true, preferred_username: 'operadora' };
  if (mode !== 'missing-groups') result.groups = mode === 'empty-groups' ? []
    : [mode === 'similar-group' ? '/secureops-operators-extra' : '/secureops-operators'];
  return result;
}

function respond(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, issuer);
    if (url.pathname === '/realms/test/.well-known/openid-configuration') {
      return respond(res, 200, { issuer, authorization_endpoint: `${issuer}/auth`, token_endpoint: `${issuer}/token`,
        jwks_uri: `${issuer}/jwks`, userinfo_endpoint: `${issuer}/userinfo`, response_types_supported: ['code'],
        subject_types_supported: ['public'], id_token_signing_alg_values_supported: ['RS256'],
        token_endpoint_auth_methods_supported: ['client_secret_basic', 'client_secret_post'], code_challenge_methods_supported: ['S256'] });
    }
    if (url.pathname === '/realms/test/jwks') return respond(res, 200, { keys: [jwk] });
    if (url.pathname === '/realms/test/auth') {
      assert.equal(url.searchParams.get('client_id'), clientId, 'Client inesperado no emissor de teste');
      assert.equal(url.searchParams.get('redirect_uri'), `${gateway}/oauth2/callback`, 'Callback inesperado');
      assert.equal(url.searchParams.get('code_challenge_method'), 'S256', 'PKCE ausente');
      assert.ok(url.searchParams.get('nonce'), 'Nonce ausente');
      const code = randomUUID();
      codes.set(code, { nonce: url.searchParams.get('nonce'), challenge: url.searchParams.get('code_challenge'), mode: scenario });
      const callback = new URL(`${gateway}/oauth2/callback`);
      callback.searchParams.set('state', url.searchParams.get('state'));
      callback.searchParams.set('code', code);
      res.writeHead(302, { Location: callback.href });
      return res.end();
    }
    if (url.pathname === '/realms/test/token') {
      tokenCalls++;
      let body = '';
      for await (const chunk of req) { body += chunk; assert.ok(body.length < 16384, 'Corpo excedeu limite'); }
      const data = new URLSearchParams(body);
      const basic = req.headers.authorization?.startsWith('Basic ')
        ? Buffer.from(req.headers.authorization.slice(6), 'base64').toString().split(':') : [];
      assert.equal(data.get('client_secret') ?? basic[1], clientSecret, 'Client secret de teste divergente');
      assert.equal(data.get('client_id') ?? basic[0], clientId, 'Client ID divergente');
      assert.equal(data.get('grant_type'), 'authorization_code', 'Grant inesperado');
      const exchange = codes.get(data.get('code'));
      assert.ok(exchange, 'Codigo inexistente');
      codes.delete(data.get('code'));
      assert.equal(createHash('sha256').update(data.get('code_verifier') ?? '').digest('base64url'), exchange.challenge, 'PKCE invalido');
      const now = Math.floor(Date.now() / 1000);
      const common = { ...identity(exchange.mode), iss: issuer, aud: clientId, iat: now, exp: now + 300 };
      const claims = { ...common, nonce: exchange.nonce };
      if (exchange.mode === 'wrong-audience') claims.aud = 'other-client';
      if (exchange.mode === 'wrong-issuer') claims.iss = `${issuer}-other`;
      if (exchange.mode === 'wrong-nonce') claims.nonce = 'deliberately-incompatible-nonce';
      if (exchange.mode === 'expired-token') claims.exp = now - 120;
      const access = jwt(common);
      accessTokens.set(access, identity(exchange.mode));
      const idToken = jwt(claims, exchange.mode === 'wrong-signature' ? otherKey.privateKey : mainKey.privateKey);
      const parts = idToken.split('.');
      assert.equal(verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), mainKey.publicKey, Buffer.from(parts[2], 'base64url')),
        exchange.mode !== 'wrong-signature', 'Precondicao de assinatura do token de teste falhou');
      successfulTokenResponses++;
      return respond(res, 200, { access_token: access, id_token: idToken,
        token_type: 'Bearer', expires_in: 300 });
    }
    if (url.pathname === '/realms/test/userinfo') {
      const info = accessTokens.get(req.headers.authorization?.replace(/^Bearer /, ''));
      return respond(res, info ? 200 : 401, info ?? { error: 'unauthorized' });
    }
    if (url.pathname === '/' || url.pathname === '/health') {
      upstreamCalls++;
      assert.equal(req.headers.authorization, undefined, 'Token encaminhado ao upstream');
      return respond(res, 200, { isolatedUpstream: true });
    }
    return respond(res, 404, { error: 'not_found' });
  } catch {
    // Não imprimir requests, cookies, códigos, tokens ou material de assinatura.
    return respond(res, 400, { error: 'isolated_provider_rejected_request' });
  }
});

async function request(url, cookie) {
  return fetch(url, { redirect: 'manual', headers: cookie ? { Cookie: cookie } : {}, signal: AbortSignal.timeout(5000) });
}

function cookies(response) {
  return response.headers.getSetCookie().map((value) => value.split(';')[0]).join('; ');
}

async function login(mode, alterState = false) {
  scenario = mode;
  const start = await request(`${gateway}/oauth2/start`);
  assert.equal(start.status, 302, 'Inicio OIDC sem redirect');
  const csrf = cookies(start);
  assert.ok(csrf.includes('_csrf='), 'Cookie CSRF ausente');
  const auth = await request(start.headers.get('location'));
  assert.equal(auth.status, 302, 'Emissor de teste nao retornou codigo');
  const callback = new URL(auth.headers.get('location'));
  if (alterState) callback.searchParams.set('state', 'invalid-state');
  return request(callback, csrf);
}

function result(name, details = {}) {
  console.log(JSON.stringify({ test: name, result: 'pass', ...details }));
}

async function run() {
  const deadline = Date.now() + 60000;
  let ready = false;
  while (Date.now() < deadline) {
    try { ready = (await request(`${gateway}/ready`)).status === 200; } catch { /* startup finito */ }
    if (ready) break;
    await delay(250);
  }
  assert.ok(ready, 'Gateway isolado nao pronto em 60s');

  const positive = await login('positive');
  assert.equal(positive.status, 302, 'Controle positivo nao criou sessao');
  const setCookies = positive.headers.getSetCookie().filter(value => /^secureops_session(?:_\d+)?=/.test(value));
  assert.ok(setCookies.length > 0, 'Cookie de sessao ausente no controle positivo');
  for (const value of setCookies) {
    assert.match(value, /;\s*HttpOnly/i, 'HttpOnly ausente');
    assert.match(value, /;\s*SameSite=Lax/i, 'SameSite divergente');
    assert.doesNotMatch(value, /;\s*Domain=/i, 'Cookie nao host-only');
    assert.doesNotMatch(value, /;\s*Secure(?:;|$)/i, 'Transporte de teste divergiu da excecao HTTP');
  }
  const validCookie = setCookies.map(value => value.split(';')[0]).join('; ');
  const upstream = await request(`${gateway}/`, validCookie);
  assert.equal(upstream.status, 200, 'Controle positivo nao acessou upstream');
  assert.equal((await upstream.json()).isolatedUpstream, true, 'Upstream inesperado');
  result('positive-signed-token-and-exact-group', { status: 200, tokenNotForwarded: true });
  result('session-cookie-attributes', { httpOnly: true, sameSite: 'Lax', hostOnly: true, secure: false, cookieParts: setCookies.length });

  for (const mode of ['wrong-audience', 'wrong-issuer', 'wrong-signature', 'wrong-nonce', 'expired-token', 'missing-groups', 'empty-groups', 'similar-group']) {
    const beforeUpstream = upstreamCalls;
    const beforeTokens = tokenCalls;
    const beforeSuccessfulTokens = successfulTokenResponses;
    const response = await login(mode);
    assert.ok(response.status >= 400, `${mode}: callback nao negado`);
    assert.ok(tokenCalls > beforeTokens, `${mode}: nao chegou a troca de codigo`);
    assert.equal(successfulTokenResponses, beforeSuccessfulTokens + 1, `${mode}: emissor nao forneceu exatamente uma resposta de tokens valida`);
    assert.ok(!response.headers.getSetCookie().some(value => /^secureops_session(?:_\d+)?=/.test(value)), `${mode}: emitiu sessao`);
    assert.equal(upstreamCalls, beforeUpstream, `${mode}: atingiu upstream`);
    result(mode, { callbackStatus: response.status, tokenResponseIssued: true, signaturePreconditionChecked: true, noSessionIssued: true });
  }
  const before = tokenCalls;
  const invalidState = await login('positive', true);
  assert.ok(invalidState.status >= 400, 'State invalido nao negado');
  assert.equal(tokenCalls, before, 'State invalido chegou ao token endpoint');
  result('invalid-state-with-csrf-cookie', { callbackStatus: invalidState.status, tokenExchangeNotReached: true });

  const tampered = validCookie.replace(/^(secureops_session(?:_\d+)?=)(.)/, (_, prefix, char) => prefix + (char === 'A' ? 'B' : 'A'));
  assert.notEqual(tampered, validCookie, 'Adulteracao nao aplicada');
  const beforeUpstream = upstreamCalls;
  const rejected = await request(`${gateway}/`, tampered);
  assert.ok([302, 401, 403].includes(rejected.status), 'Cookie adulterado nao negado');
  assert.equal(upstreamCalls, beforeUpstream, 'Cookie adulterado atingiu upstream');
  assert.equal((await request(`${gateway}/`, validCookie)).status, 200, 'Controle positivo apos adulteracao falhou');
  result('tampered-real-issued-cookie', { status: rejected.status, originalCookieStillValid: true });
  result('suite-complete', { isolation: 'temporary-internal-docker-network', mainGatewayUnchanged: true });
}

server.listen(8080, '0.0.0.0', () => {
  run().then(() => { server.closeAllConnections(); server.close(); })
    .catch(error => {
      console.error(JSON.stringify({ result: 'fail', reason: error.message }));
      server.closeAllConnections(); server.close(); process.exitCode = 1;
    });
});
