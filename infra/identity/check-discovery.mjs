import assert from 'node:assert/strict';
import { lookup } from 'node:dns/promises';

// Apenas metadados públicos e uma tentativa inválida sem segredo; não obtém tokens.
const issuer = 'http://keycloak.localhost:8080/realms/secureops-lab';
const addresses = await lookup('keycloak.localhost', { all: true });
assert.ok(addresses.length);
assert.ok(addresses.every(({ address }) => !address.startsWith('127.') && address !== '::1'));
const response = await fetch(`${issuer}/.well-known/openid-configuration`, { signal: AbortSignal.timeout(3000) });
assert.equal(response.status, 200);
const discovery = await response.json();
assert.equal(discovery.issuer, issuer);
for (const key of ['authorization_endpoint', 'token_endpoint', 'jwks_uri', 'userinfo_endpoint']) {
  assert.equal(new URL(discovery[key]).origin, 'http://keycloak.localhost:8080');
}
const jwks = await fetch(discovery.jwks_uri, { signal: AbortSignal.timeout(3000) });
assert.equal(jwks.status, 200);
assert.ok((await jwks.json()).keys.length);
const invalidLogin = await fetch(discovery.token_endpoint, {
  method: 'POST',
  body: new URLSearchParams({ grant_type: 'authorization_code', code: 'invalid', client_id: 'secureops-gateway' }),
  signal: AbortSignal.timeout(3000),
});
assert.equal(invalidLogin.status, 401);
assert.equal((await invalidLogin.json()).error, 'unauthorized_client');
console.log(JSON.stringify({
  check: 'identity_discovery', dns: addresses.map(({ address }) => address),
  discovery: 200, issuer: 'exact_match', jwks: 200, token_without_secret: 401,
}));
