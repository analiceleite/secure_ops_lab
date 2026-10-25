import { createServer, type ServerResponse } from 'node:http';

function sendJson(response: ServerResponse, status: number, body: object): void {
  response.writeHead(status, { 'Content-Type': 'application/json' });
  response.end(JSON.stringify(body));
}

/** Cria o servidor sem abrir porta nem instalar handlers no processo. */
export function createApplicationServer() {
  return createServer((request, response) => {
    // Não usamos o cabeçalho Host para interpretar ou registrar dados da requisição.
    const path = (request.url ?? '').split('?')[0];

    if (path !== '/' && path !== '/health') {
      sendJson(response, 404, { error: 'not_found' });
      return;
    }

    if (request.method !== 'GET') {
      response.setHeader('Allow', 'GET');
      sendJson(response, 405, { error: 'method_not_allowed' });
      return;
    }

    if (path === '/health') {
      sendJson(response, 200, { status: 'ok' });
      return;
    }

    sendJson(response, 200, {
      service: 'secureops-api',
      message: 'Serviço fictício do laboratório',
    });
  });
}
