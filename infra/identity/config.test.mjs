import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const realm = JSON.parse(readFileSync(new URL('../keycloak/realm-template.json', import.meta.url), 'utf8'));
const client = realm.clients.find((item) => item.clientId === 'secureops-gateway');
// Apenas o subconjunto JSON de valores usado neste arquivo TOML; não é parser TOML genérico.
const config = {};
for (const line of readFileSync(new URL('../oauth2-proxy/oauth2-proxy.cfg', import.meta.url), 'utf8').split('\n')) {
  if (!line.trim() || line.trim().startsWith('#')) continue;
  const match = /^(\w+)\s*=\s*(.+)$/.exec(line);
  assert.ok(match, 'Linha de configuração fora do subconjunto esperado');
  assert.ok(!Object.hasOwn(config, match[1]), 'Opção duplicada');
  config[match[1]] = JSON.parse(match[2]);
}

test('template sem contas, credenciais OTP ou secret utilizável', () => {
  assert.equal(realm.users, undefined);
  assert.equal(client.secret, '${SECUREOPS_CLIENT_SECRET}');
  assert.equal(realm.registrationAllowed, false);
  assert.equal(realm.sslRequired, 'external');
});

test('client confidencial só aceita code flow e callback exato com PKCE', () => {
  assert.equal(client.publicClient, false);
  assert.equal(client.standardFlowEnabled, true);
  for (const option of ['implicitFlowEnabled', 'directAccessGrantsEnabled', 'serviceAccountsEnabled']) {
    assert.equal(client[option], false);
  }
  assert.deepEqual(client.redirectUris, ['http://app.localhost:4180/oauth2/callback']);
  assert.deepEqual(client.webOrigins, []);
  assert.equal(client.attributes['pkce.code.challenge.method'], 'S256');
  assert.equal(config.code_challenge_method, 'S256');
});

test('override dedicado exige senha e OTP, sem Cookie ou execução alternativa', () => {
  const flow = realm.authenticationFlows.find((item) => item.id === client.authenticationFlowBindingOverrides.browser);
  assert.ok(flow?.topLevel);
  assert.deepEqual(flow.authenticationExecutions.map((item) => [item.authenticator, item.requirement]), [
    ['auth-username-password-form', 'REQUIRED'], ['auth-otp-form', 'REQUIRED'],
  ]);
  assert.equal(realm.browserFlow, undefined, 'Não sobrescrever fluxo global administrativo');
  assert.equal(realm.otpPolicyDigits, 6);
  assert.equal(realm.otpPolicyPeriod, 30);
  assert.equal(realm.otpPolicyAlgorithm, 'HmacSHA1');
  assert.equal(realm.otpPolicyLookAheadWindow, 1);
});

test('mapper de grupo usa caminho completo e gateway exige grupo exato', () => {
  const mapper = realm.clientScopes.find((item) => item.name === 'groups').protocolMappers[0];
  assert.equal(mapper.config['full.path'], 'true');
  assert.equal(mapper.config['claim.name'], 'groups');
  assert.equal(mapper.config['id.token.claim'], 'true');
  assert.deepEqual(config.allowed_groups, ['/secureops-operators']);
  assert.deepEqual(config.email_domains, ['lab.example']);
  assert.equal(config.scope, 'openid profile email groups');
});

test('import cria os scopes nativos mesmo com groups customizado, sem redefini-los parcialmente', () => {
  assert.equal(realm.attributes.CreateDefaultClientScopes, 'true');
  assert.deepEqual(realm.clientScopes.map((item) => item.name), ['groups']);
});

test('gateway recebe basic/profile/email sem roles nem offline_access', () => {
  assert.deepEqual(client.defaultClientScopes, ['basic', 'profile', 'email']);
  assert.deepEqual(client.optionalClientScopes, ['groups']);
  assert.equal(client.fullScopeAllowed, false);
});

test('gateway valida issuer, audience e nonce, sem bypass de bearer/rotas', () => {
  for (const option of ['insecure_oidc_skip_nonce', 'insecure_oidc_skip_issuer_verification',
    'insecure_oidc_allow_unverified_email', 'ssl_insecure_skip_verify', 'skip_oidc_discovery',
    'skip_jwt_bearer_tokens', 'skip_auth_preflight', 'reverse_proxy']) {
    assert.equal(config[option], false, option);
  }
  for (const option of ['skip_auth_routes', 'skip_auth_regex', 'trusted_ips']) assert.equal(config[option], undefined);
  assert.deepEqual(config.oidc_audience_claims, ['aud']);
  assert.deepEqual(config.oidc_extra_audiences, []);
  assert.equal(config.client_id, client.clientId);
  assert.equal(config.oidc_issuer_url, 'http://keycloak.localhost:8080/realms/secureops-lab');
  assert.deepEqual(config.upstreams, ['http://api:3000/']);
});

test('cookie local host-only com HttpOnly, Lax e 5 min sem refresh', () => {
  assert.equal(config.cookie_secure, false, 'Exceção HTTP explicitamente aprovada');
  assert.equal(config.cookie_httponly, true);
  assert.equal(config.cookie_samesite, 'lax');
  assert.equal(config.cookie_csrf_samesite, 'lax');
  assert.deepEqual(config.cookie_domains, []);
  assert.equal(config.cookie_expire, '5m');
  assert.equal(config.cookie_refresh, '0s');
  assert.deepEqual(config.whitelist_domains, []);
});

test('tokens não encaminhados e logs de callback/debug desabilitados', () => {
  for (const option of ['pass_access_token', 'pass_authorization_header', 'pass_basic_auth',
    'pass_user_headers', 'set_authorization_header', 'set_xauthrequest', 'set_basic_auth',
    'request_logging', 'auth_logging', 'show_debug_on_error']) assert.equal(config[option], false, option);
  assert.equal(config.client_secret_file, '/run/secrets/client-secret');
  assert.equal(config.cookie_secret_file, '/run/secrets/cookie-secret');
  assert.equal(config.client_secret, undefined);
  assert.equal(config.cookie_secret, undefined);
});

test('tempos distintos de token e sessão do IdP explicitamente limitados', () => {
  assert.equal(realm.accessTokenLifespan, 300);
  assert.equal(realm.ssoSessionIdleTimeout, 600);
  assert.equal(realm.ssoSessionMaxLifespan, 900);
  assert.equal(realm.rememberMe, false);
});
