// Payloads da API Zabbix 7.0; nenhum segredo real pertence a este arquivo.
export const KEYS = { raw: 'secureops.auth.raw', count: 'secureops.auth.errors5m', quality: 'secureops.auth.collection' };
export const NAMES = { auth: 'SecureOps: falhas repetidas de autenticacao', collection: 'SecureOps: coleta de autenticacao invalida ou ausente' };
export const validateSample = `var d = JSON.parse(value);
var now = new Date().getTime();
if (d.contract_version !== 1 || d.realm !== 'secureops-lab' || d.client !== 'secureops-gateway' || d.window_seconds !== 300
 || typeof d.sampled_at !== 'number' || Math.floor(d.sampled_at) !== d.sampled_at || d.sampled_at < now - 15000 || d.sampled_at > now + 3000
 || (d.collection_ok !== 0 && d.collection_ok !== 1)) { throw 'invalid_collection_sample'; }
var allowed = ['contract_version','realm','client','window_seconds','sampled_at','collection_ok'];
if (d.collection_ok === 1) {
 if (typeof d.login_errors_5m !== 'number' || Math.floor(d.login_errors_5m) !== d.login_errors_5m || d.login_errors_5m < 0 || d.login_errors_5m > 1000) { throw 'invalid_collection_count'; }
 allowed.push('login_errors_5m');
} else {
 if (typeof d.error !== 'string' || !/^[a-z_]{1,32}$/.test(d.error)) { throw 'invalid_collection_error'; }
 allowed.push('error');
}
var fields = Object.keys(d);
if (fields.length !== allowed.length) { throw 'invalid_collection_fields'; }
for (var i=0;i<fields.length;i++) { if (allowed.indexOf(fields[i]) === -1) { throw 'invalid_collection_fields'; } }
return JSON.stringify(d);`;
export const extractCount = "var d = JSON.parse(value); if (d.collection_ok !== 1) { return null; } return d.login_errors_5m;";

export function masterItem(hostid, url = 'http://identity-event-collector:3001/metrics') {
  return { hostid, name: 'Autenticacao: amostra agregada (verificar qualidade)', key_: KEYS.raw, type: 19, value_type: 4,
    delay: '30s', history: '7d', trends: '0', timeout: '15s', url, request_method: 0, retrieve_mode: 0,
    follow_redirects: 0, status_codes: '200', headers: [{ name: 'X-SecureOps-Metrics-Key', value: '{$SECUREOPS_METRICS_KEY}' }],
    preprocessing: [{ type: 21, params: validateSample, error_handler: 0 }],
    tags: [{ tag: 'service', value: 'secureops-api' }, { tag: 'category', value: 'collection' }] };
}
export function dependentItems(hostid, master_itemid) {
  return [
    { hostid, master_itemid, name: 'Autenticacao: LOGIN_ERROR em 5 min (ultimo valor valido; conferir coleta)', key_: KEYS.count,
      type: 18, value_type: 3, delay: '0', history: '7d', trends: '90d',
      preprocessing: [{ type: 21, params: extractCount, error_handler: 0 }],
      tags: [{ tag: 'service', value: 'secureops-api' }, { tag: 'category', value: 'authentication' }] },
    { hostid, master_itemid, name: 'Autenticacao: qualidade da coleta (1=valida; 0=falha; conferir horario)', key_: KEYS.quality,
      type: 18, value_type: 3, delay: '0', history: '7d', trends: '90d',
      preprocessing: [{ type: 12, params: '$.collection_ok', error_handler: 0 }],
      tags: [{ tag: 'service', value: 'secureops-api' }, { tag: 'category', value: 'collection' }] }
  ];
}
export function securityTriggers(host = 'secureops-api') {
  return [
    { description: NAMES.auth, expression: `last(/${host}/${KEYS.count})>=5`, priority: 2, type: 0, manual_close: 0,
      comments: 'Triagem educacional: agregado do client, nao prova ataque. Recupera somente com contagem valida <5; perda da coleta nao zera a janela.',
      tags: [{ tag: 'service', value: 'secureops-api' }, { tag: 'category', value: 'authentication' }] },
    { description: NAMES.collection, expression: `last(/${host}/${KEYS.quality})=0 or nodata(/${host}/${KEYS.quality},90s)=1`,
      recovery_mode: 1, recovery_expression: `last(/${host}/${KEYS.quality})=1 and nodata(/${host}/${KEYS.quality},90s)=0`,
      priority: 2, type: 0, manual_close: 0,
      comments: 'Falha explicita ou ausencia de qualidade recente. Ultima contagem pode estar obsoleta. Recupera com nova coleta valida.',
      tags: [{ tag: 'service', value: 'secureops-api' }, { tag: 'category', value: 'collection' }] }
  ];
}
