import { pathToFileURL } from 'node:url';
import { createApplicationServer } from './server.js';

interface ApplicationOptions {
  host?: string;
  port?: number;
}

function log(event: string, fields: Record<string, string | number> = {}, error = false): void {
  const line = JSON.stringify({ timestamp: new Date().toISOString(), event, ...fields });
  if (error) {
    console.error(line);
  } else {
    console.log(line);
  }
}

/** Opções explícitas permitem testar com loopback e porta efêmera, sem ler .env. */
export function startApplication({ host = '0.0.0.0', port = 3000 }: ApplicationOptions = {}) {
  const server = createApplicationServer();
  let shuttingDown = false;

  const removeSignalHandlers = () => {
    process.off('SIGTERM', onSigterm);
    process.off('SIGINT', onSigint);
  };

  const shutdown = (signal: 'SIGTERM' | 'SIGINT') => {
    if (shuttingDown) return;
    shuttingDown = true;
    log('shutdown_started', { signal });

    const deadline = setTimeout(() => {
      log('shutdown_timeout', {}, true);
      process.exitCode = 1;
      // Inclui conexões HTTP ainda ativas; não há suporte a upgrades nesta API.
      server.closeAllConnections();
    }, 5000);

    server.close((error) => {
      clearTimeout(deadline);
      removeSignalHandlers();
      if (error) {
        log('shutdown_failed', {}, true);
        process.exitCode = 1;
        return;
      }
      log('shutdown_completed');
    });
  };

  const onSigterm = () => shutdown('SIGTERM');
  const onSigint = () => shutdown('SIGINT');

  server.once('error', (error: NodeJS.ErrnoException) => {
    removeSignalHandlers();
    // Não registrar error.message/stack: podem conter endereços e dados locais.
    const code = ['EADDRINUSE', 'EACCES'].includes(error.code ?? '')
      ? error.code!
      : 'STARTUP_ERROR';
    log('startup_failed', { code }, true);
    process.exitCode = 1;
  });

  process.on('SIGTERM', onSigterm);
  process.on('SIGINT', onSigint);

  server.listen(port, host, () => {
    const address = server.address();
    log('startup_completed', {
      port: typeof address === 'object' && address !== null ? address.port : port,
    });
  });

  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  startApplication();
}
