import { readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { localApi, waitFor } from './zabbix-api.mjs';
import { KEYS, NAMES, masterItem, dependentItems, securityTriggers } from './security-config.mjs';

try {
  const api = localApi();
  assert.equal(await api('apiinfo.version'), '7.0.32');
  const hosts = await api('host.get', { filter: { host: ['secureops-api'] }, output: ['hostid','host','status'] });
  assert.equal(hosts.length,1); const host = hosts[0]; assert.equal(host.status,'0');
  const existing = await api('item.get', { hostids: [host.hostid], filter: { key_: Object.values(KEYS) }, output: ['itemid','key_'] });
  if (!process.argv.includes('--apply')) {
    console.log(JSON.stringify({ mode: 'read-only', securityItems: existing.length, expectedItems: 3 })); process.exit(0);
  }
  assert.equal(existing.length,0, 'security_items_exist_no_overwrite');
  const macros = await api('usermacro.get', { hostids: [host.hostid], filter: { macro: '{$SECUREOPS_METRICS_KEY}' }, output: ['hostmacroid'] });
  assert.equal(macros.length,0,'macro_exists_no_overwrite');
  const secret = readFileSync('/secrets/collector-metrics-secret','utf8').trim(); assert.match(secret,/^[a-f0-9]{64}$/);
  await api('usermacro.create', { hostid: host.hostid, macro: '{$SECUREOPS_METRICS_KEY}', type: 1, value: secret,
    description: 'Segredo exclusivo do endpoint interno; nunca exportar valor.' });
  const master = await api('item.create', masterItem(host.hostid));
  const dependent = await api('item.create', dependentItems(host.hostid,master.itemids[0]));
  const triggers = await api('trigger.create',securityTriggers());
  writeFileSync('/state/security-zabbix-created.json', JSON.stringify({ hostid: host.hostid, itemids: [...master.itemids,...dependent.itemids], triggerids: triggers.triggerids }), { flag: 'wx' });
  const readItems = () => api('item.get',{ itemids: [dependent.itemids[1]], output: ['itemid','lastvalue','lastclock','state','error'] });
  await waitFor(readItems, rows => rows.length === 1 && rows[0].state === '0' && rows[0].lastvalue === '1' && Number(rows[0].lastclock) > Date.now()/1000-60,180,'first_valid_security_sample');
  const items = await api('item.get', { itemids: [...master.itemids,...dependent.itemids], output: ['itemid','key_','lastvalue','lastclock','state'] });
  assert.ok(items.every(i => i.state === '0'));
  const dashboard = await api('dashboard.get', { filter: { name: ['SecureOps Lab'] }, selectPages: 'extend', output: ['dashboardid','name','private'] });
  assert.equal(dashboard.length,1); assert.equal(dashboard[0].private,'1');
  const pages = dashboard[0].pages;
  assert.equal(pages.length,1); assert.equal(pages[0].widgets.length,2,'unexpected_dashboard_no_overwrite');
  const maxY = Math.max(...pages[0].widgets.map(w => Number(w.y) + Number(w.height)));
  const additions = dependent.itemids.map((itemid,i) => ({ type: 'item', name: i === 0 ? 'LOGIN_ERROR 5 min — ultimo valido; confira coleta' : 'Coleta: 1 valida / 0 falha — confira horario e problemas',
    x: i*36, y: maxY, width: 36, height: 5,
    fields: [{ type: 4, name: 'itemid.0', value: itemid }, { type: 0, name: 'decimal_places', value: 0 }] }));
  // Preserva widgets existentes e seus filtros; nao altera compartilhamentos.
  await api('dashboard.update', { dashboardid: dashboard[0].dashboardid, pages: pages.map(p => ({ dashboard_pageid: p.dashboard_pageid,
    name: p.name, display_period: p.display_period, widgets: [...p.widgets.map(w => ({ widgetid: w.widgetid, type: w.type, name: w.name,
      x: w.x,y: w.y,width: w.width,height: w.height,view_mode: w.view_mode, fields: w.fields })), ...additions] })) });
  const current = await api('trigger.get',{ triggerids: triggers.triggerids, output: ['description','value','state','type','manual_close'] });
  assert.equal(current.length,2); assert.ok(current.every(t => t.state === '0' && t.type === '0' && t.manual_close === '0'));
  console.log(JSON.stringify({ result:'pass', masterAndDependents:3, triggers:current.map(t => ({ name:t.description,value:t.value })), dashboardWidgets:4,
    noSecretExported:true, failureDoesNotWriteCount:true }));
} catch (error) {
  const message = error instanceof Error && /^zabbix_(api_[a-z.]+_-?\d+|http_\d+|auth_[a-z_]+)$/.test(error.message) ? error.message : 'security_configuration_failed_preserve_partial_state';
  console.error(message); process.exitCode=1;
}
