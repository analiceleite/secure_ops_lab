// Cliente minimo de teste: fala FastCGI apenas com o PHP-FPM efemero do harness.
import assert from 'node:assert/strict';
import net from 'node:net';
import { setTimeout as pause } from 'node:timers/promises';

const host = process.argv[2];
assert.match(host, /^secureops-import-[a-f0-9]{32}$/);

function record(type, data = Buffer.alloc(0)) {
  assert.ok(data.length <= 65535);
  const header = Buffer.from([1, type, 0, 1, 0, 0, 0, 0]);
  header.writeUInt16BE(data.length, 4);
  return Buffer.concat([header, data]);
}

const params = Object.entries({
  SCRIPT_FILENAME: '/checks/validate-availability-import.php',
  SCRIPT_NAME: '/validate-availability-import.php',
  REQUEST_METHOD: 'GET',
  REQUEST_URI: '/validate-availability-import.php',
  SERVER_PROTOCOL: 'HTTP/1.1',
  GATEWAY_INTERFACE: 'CGI/1.1',
  SERVER_NAME: 'validation.local',
  SERVER_PORT: '9000',
  REMOTE_ADDR: '127.0.0.1'
}).map(([key, value]) => {
  assert.ok(Buffer.byteLength(key) < 128 && Buffer.byteLength(value) < 128);
  return Buffer.concat([Buffer.from([Buffer.byteLength(key), Buffer.byteLength(value)]), Buffer.from(key), Buffer.from(value)]);
});
const request = Buffer.concat([
  record(1, Buffer.from([0, 1, 0, 0, 0, 0, 0, 0])),
  record(4, Buffer.concat(params)), record(4), record(5)
]);

function invoke() {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host, port: 9000 });
    const chunks = [];
    let bytes = 0;
    socket.setTimeout(5000, () => socket.destroy(new Error('fastcgi_timeout')));
    socket.on('connect', () => socket.write(request));
    socket.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > 256 * 1024) socket.destroy(new Error('fastcgi_body_limit'));
      else chunks.push(chunk);
    });
    socket.on('error', reject);
    socket.on('end', () => resolve(Buffer.concat(chunks)));
  });
}

let response;
for (let attempt = 0; attempt < 20; attempt++) {
  try { response = await invoke(); break; }
  catch (error) {
    if (!['ECONNREFUSED', 'EAI_AGAIN', 'ENOTFOUND'].includes(error.code) || attempt === 19) throw error;
    await pause(250);
  }
}

let stdout = '';
let stderr = '';
let ended = false;
for (let offset = 0; offset < response.length;) {
  assert.ok(offset + 8 <= response.length, 'fastcgi_header_truncated');
  assert.equal(response[offset], 1);
  assert.equal(response.readUInt16BE(offset + 2), 1);
  const type = response[offset + 1];
  const size = response.readUInt16BE(offset + 4);
  const padding = response[offset + 6];
  assert.ok(offset + 8 + size + padding <= response.length, 'fastcgi_record_truncated');
  const content = response.subarray(offset + 8, offset + 8 + size);
  if (type === 6) stdout += content.toString('utf8');
  if (type === 7) stderr += content.toString('utf8');
  if (type === 3) {
    assert.equal(content.readUInt32BE(0), 0, 'php_application_failed');
    assert.equal(content[4], 0, 'fastcgi_protocol_failed');
    ended = true;
  }
  offset += 8 + size + padding;
}
assert.ok(ended, 'fastcgi_end_missing');
assert.equal(stderr, '', `php_diagnostic: ${stderr}`);
const separator = stdout.indexOf('\r\n\r\n');
assert.ok(separator >= 0, 'php_response_headers_missing');
assert.equal(/Status: [45]/i.test(stdout.slice(0, separator)), false);
const lines = stdout.slice(separator + 4).trim().split(/\r?\n/).map(line => JSON.parse(line));
assert.deepEqual(lines.at(-1), { checks: 7, result: 'pass', scope: 'offline_schema_and_grammar_only' });
for (const line of lines) console.log(JSON.stringify(line));
