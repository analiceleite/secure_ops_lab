// O timeout inclui conexão, headers e leitura completa do corpo.
try {
  const response = await fetch(process.argv[2] ?? 'http://api:3000/health', {
    signal: AbortSignal.timeout(2000),
    redirect: 'error',
  });
  if (response.status !== 200 || response.headers.get('content-type') !== 'application/json') {
    throw new Error('unexpected_response');
  }
  const body = await response.json();
  if (body === null || typeof body !== 'object' || Array.isArray(body)
    || Object.keys(body).length !== 1 || body.status !== 'ok') {
    throw new Error('unexpected_body');
  }
  console.log(JSON.stringify({ event: 'probe_succeeded' }));
} catch {
  // Não refletir destino, resposta ou detalhes internos em logs de saúde.
  console.error(JSON.stringify({ event: 'probe_failed' }));
  process.exitCode = 1;
}
