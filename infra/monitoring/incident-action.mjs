// Configuracao aditiva da entrega de incidentes. Nunca imprime macro/segredo/media payload.
import { randomBytes } from 'node:crypto';
import { createHash, timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { localApi } from './zabbix-api.mjs';

const mode = process.argv[2];
assert.ok(['inspect', 'prepare', 'enable', 'disable'].includes(mode));
const api = localApi();
const hostName = 'secureops-api';
const hostGroupName = 'SecureOps Lab';
const serviceGroupName = 'SecureOps incident delivery';
const serviceUserName = 'secureops-incident';
const actionName = 'SecureOps incident delivery — approved triggers';
const specs = [
  { id: '25229', media: '72', name: 'SecureOps incident problem (inactive candidate)' },
  { id: '25230', media: '72', name: 'SecureOps incident problem (inactive candidate)' },
  { id: '25231', media: '72', name: 'SecureOps incident problem (inactive candidate)' },
  { id: '25232', media: '72', name: 'SecureOps incident problem (inactive candidate)' }
];
const ids = [...new Set(specs.map(x => x.id))];
const mediatypeIds = ['72', '73'];

async function inspect() {
  assert.equal(await api('apiinfo.version'), '7.0.32', 'version');
  const hosts = await api('host.get', { filter: { host: [hostName] }, output: ['hostid', 'host', 'status'], selectGroups: ['groupid', 'name'] });
  assert.equal(hosts.length, 1, 'host_count');
  const host = hosts[0];
  assert.equal(host.status, '0', 'host_enabled');
  const hostGroup = host.groups.find(g => g.name === hostGroupName);
  assert.ok(hostGroup, 'expected_host_group_missing');
  const triggers = await api('trigger.get', { triggerids: ids, output: ['triggerid', 'description', 'status', 'value'], selectHosts: ['hostid', 'host'] });
  assert.equal(triggers.length, 4, 'trigger_count');
  assert.ok(triggers.every(t => t.status === '0' && t.hosts.some(h => h.hostid === host.hostid && h.host === hostName)));
  const media = await api('mediatype.get', { mediatypeids: mediatypeIds, output: ['mediatypeid', 'name', 'type', 'status'] });
  assert.equal(media.length, 2, 'media_count');
  assert.ok(media.every(m => m.type === '4'), 'media_webhook_type');
  assert.equal(media.find(m => m.mediatypeid === '72').name, 'SecureOps incident problem (inactive candidate)', 'problem_media_name');
  assert.equal(media.find(m => m.mediatypeid === '73').name, 'SecureOps incident recovery (inactive candidate)', 'recovery_media_name');
  const macros = await api('usermacro.get', { hostids: [host.hostid], filter: { macro: ['{$SECUREOPS_INCIDENT_WEBHOOK_KEY}'] }, output: ['hostmacroid', 'macro', 'type'] });
  assert.equal(macros.length, 1, 'secret_macro_exists');
  const [groups, users, actions] = await Promise.all([
    api('usergroup.get', { filter: { name: [serviceGroupName] }, output: ['usrgrpid', 'name', 'gui_access', 'users_status'], selectHostGroupRights: 'extend' }),
    api('user.get', { filter: { username: [serviceUserName] }, output: ['userid', 'username', 'roleid'], selectUsrgrps: 'extend', selectMedias: 'extend' }),
    api('action.get', { filter: { name: [actionName] }, output: ['actionid', 'name', 'status', 'eventsource'], selectFilter: 'extend', selectOperations: 'extend', selectRecoveryOperations: 'extend', selectUpdateOperations: 'extend' })
  ]);
  return { host, hostGroup, triggers, media, groups, users, actions };
}

async function secureWebhookMacro(hostId) {
  const localKey = readFileSync('/secrets/incident-webhook-key', 'utf8').trim();
  assert.match(localKey, /^[a-f0-9]{64}$/, 'local_webhook_key_format');
  const [macro] = await api('usermacro.get', { hostids: [hostId], filter: { macro: ['{$SECUREOPS_INCIDENT_WEBHOOK_KEY}'] },
    output: ['hostmacroid', 'hostid', 'macro', 'type', 'value'] });
  assert.ok(macro, 'webhook_macro_missing');
  if (macro.type === '1') return;
  assert.equal(macro.type, '0', 'unexpected_webhook_macro_type');
  const expected = createHash('sha256').update(localKey).digest();
  const actual = createHash('sha256').update(String(macro.value ?? '')).digest();
  assert.ok(timingSafeEqual(expected, actual), 'webhook_macro_does_not_match_local_receiver_key');
  await api('usermacro.update', { hostmacroid: macro.hostmacroid, type: 1, value: localKey });
  const [verified] = await api('usermacro.get', { hostmacroids: [macro.hostmacroid], output: ['hostmacroid', 'type'] });
  assert.equal(verified?.type, '1', 'webhook_macro_secret_conversion_failed');
}

function assertPrepared(s) {
  assert.equal(s.groups.length, 1, 'service_group_missing_or_ambiguous');
  const group = s.groups[0];
  assert.equal(group.gui_access, '3');
  assert.equal(group.users_status, '0');
  assert.deepEqual(group.hostgroup_rights.map(r => ({ id: r.id, permission: r.permission })), [{ id: s.hostGroup.groupid, permission: '2' }]);
  assert.equal(s.users.length, 1, 'service_user_missing_or_ambiguous');
  const user = s.users[0];
  assert.equal(user.roleid, '1');
  assert.ok(user.usrgrps.some(g => g.usrgrpid === group.usrgrpid));
  assert.deepEqual(user.medias.map(m => m.mediatypeid).sort(), mediatypeIds);
  assert.ok(user.medias.every(m => m.active === '0' && m.sendto === 'secureops-local'));
  assert.equal(s.actions.length, 1, 'incident_action_missing_or_ambiguous');
  const action = s.actions[0];
  assert.equal(action.eventsource, '0');
  const conditions = action.filter.conditions;
  assert.ok(conditions.some(c => c.conditiontype === '1' && c.operator === '0' && c.value === s.host.hostid));
  assert.deepEqual(conditions.filter(c => c.conditiontype === '2').map(c => c.value).sort(), ids);
  assert.equal(action.operations.length, 1);
  assert.equal(action.operations[0].operationtype, '0');
  assert.equal(action.operations[0].opmessage.mediatypeid, '72');
  assert.ok(action.operations[0].opmessage_usr.some(u => u.userid === user.userid));
  assert.equal(action.recovery_operations.length, 1);
  assert.equal(action.recovery_operations[0].operationtype, '0');
  assert.equal(action.recovery_operations[0].opmessage.mediatypeid, '73');
  assert.ok(action.recovery_operations[0].opmessage_usr.some(u => u.userid === user.userid));
  assert.equal(action.update_operations.length, 0);
  return { group, user, action };
}

try {
  const state = await inspect();
  if (mode === 'inspect') {
    console.log(JSON.stringify({ result: 'pass', hostId: state.host.hostid, hostGroupId: state.hostGroup.groupid,
      triggers: state.triggers.map(t => ({ id: t.triggerid, value: t.value })), mediaTypes: state.media.map(m => ({ id: m.mediatypeid, enabled: m.status === '0' })),
      webhookMacroPresent: true, webhookMacroSecret: (await api('usermacro.get', { hostids: [state.host.hostid], filter: { macro: ['{$SECUREOPS_INCIDENT_WEBHOOK_KEY}'] }, output: ['type'] }))[0]?.type === '1',
      existingServiceObjects: { groups: state.groups.length, users: state.users.length, actions: state.actions.length } }));
    process.exit(0);
  }
  if (mode === 'prepare') {
    assert.ok(state.media.every(m => m.status === '1'), 'media_must_remain_disabled_before_prepare');
    await secureWebhookMacro(state.host.hostid);
    const macroCheck = await api('usermacro.get', { hostids: [state.host.hostid], filter: { macro: ['{$SECUREOPS_INCIDENT_WEBHOOK_KEY}'] }, output: ['type'] });
    assert.equal(macroCheck.length, 1);
    assert.equal(macroCheck[0].type, '1', 'webhook_macro_must_be_secret');
    assert.equal(state.groups.length, 0, 'service_group_exists_preserve_and_inspect');
    assert.equal(state.users.length, 0, 'service_user_exists_preserve_and_inspect');
    assert.equal(state.actions.length, 0, 'incident_action_exists_preserve_and_inspect');
    const [groupResult] = await api('usergroup.create', [{ name: serviceGroupName, gui_access: 3,
      hostgroup_rights: [{ id: state.hostGroup.groupid, permission: 2 }] }]).then(r => r.usrgrpids);
    const password = randomBytes(48).toString('base64url');
    const userResult = await api('user.create', [{ username: serviceUserName, name: 'SecureOps', surname: 'Incident receiver',
      passwd: password, roleid: '1', usrgrps: [{ usrgrpid: groupResult }], medias: mediatypeIds.map(mediatypeid => ({
        mediatypeid, sendto: 'secureops-local', active: 0, severity: 63, period: '1-7,00:00-24:00'
      })) }]);
    password.fill?.(0);
    const userId = userResult.userids[0];
    const conditions = [{ conditiontype: 1, operator: 0, value: state.host.hostid }, ...ids.map(value => ({ conditiontype: 2, operator: 0, value }))];
    const actionResult = await api('action.create', [{ name: actionName, eventsource: 0, status: 1, esc_period: '1h',
      filter: { evaltype: 0, conditions },
      operations: [{ operationtype: 0, esc_step_from: 1, esc_step_to: 1, opmessage_usr: [{ userid: userId }],
        opmessage: { default_msg: 1, mediatypeid: '72' } }],
      recovery_operations: [{ operationtype: 0, opmessage_usr: [{ userid: userId }],
        opmessage: { default_msg: 1, mediatypeid: '73' } }] }]);
    const verified = await inspect();
    const objects = assertPrepared(verified);
    assert.equal(objects.action.status, '1');
    console.log(JSON.stringify({ result: 'prepared_disabled', serviceGroupId: groupResult, serviceUserId: userId,
      actionId: actionResult.actionids[0], actionDisabled: true, mediaTypesStillDisabled: true,
      webhookMacroSecret: true, uiLoginDisabled: true, hostAccess: 'read_only', updateOperations: 0 }));
    process.exit(0);
  }
  if (mode === 'disable') {
    const prepared = assertPrepared(state);
    if (prepared.action.status === '0') await api('action.update', { actionid: prepared.action.actionid, status: 1 });
    await api('mediatype.update', mediatypeIds.map(mediatypeid => ({ mediatypeid, status: 1 })));
    const final = await inspect();
    const disabled = assertPrepared(final);
    assert.equal(disabled.action.status, '1');
    assert.ok(final.media.every(m => m.status === '1'));
    console.log(JSON.stringify({ result: 'paused', actionDisabled: true, mediaTypesDisabled: true,
      serviceObjectsPreserved: true, triggerIds: ids }));
    process.exit(0);
  }
  const prepared = assertPrepared(state);
  assert.ok(['0', '1'].includes(prepared.action.status), 'invalid_action_status');
  assert.ok(state.triggers.every(t => t.value === '0'), 'trigger_problem_active_stop_before_enable');
  if (prepared.action.status === '1') {
    assert.ok(state.media.every(m => m.status === '1'), 'unexpected_partial_media_activation');
    await api('mediatype.update', mediatypeIds.map(mediatypeid => ({ mediatypeid, status: 0 })));
    await api('action.update', { actionid: prepared.action.actionid, status: 0 });
  }
  const final = await inspect();
  const enabled = assertPrepared(final);
  assert.equal(enabled.action.status, '0');
  assert.ok(final.media.every(m => m.status === '0'));
  console.log(JSON.stringify({ result: 'enabled', actionId: enabled.action.actionid, triggerIds: ids,
    mediaTypeIds: mediatypeIds, actionEnabled: true, problemAndRecoveryOnly: true,
    updateOperations: 0, triggersWereClearBeforeEnable: true }));
} catch (error) {
  const message = error instanceof Error && /^zabbix_(api_[a-z.]+_-?\d+|http_\d+|auth_[a-z_]+)$/.test(error.message)
    ? error.message : 'incident_action_configuration_failed_preserve_state_and_inspect';
  console.error(message === 'incident_action_configuration_failed_preserve_state_and_inspect' && error instanceof Error
    ? `${message}:${error.name}:${error.message.slice(0,160)}` : message);
  process.exitCode = 1;
}
