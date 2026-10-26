/* Zabbix 7.0 webhook. O servidor expande os parâmetros por evento antes da execução.
 * Nunca registrar params/body/headers: contêm segredo e IDs operacionais.
 */
var conditions = {
  '25229': {condition: 'api-http', category: 'availability'},
  '25230': {condition: 'api-http-nodata', category: 'collection'},
  '25231': {condition: 'auth-threshold', category: 'authentication'},
  '25232': {condition: 'auth-collection', category: 'collection'}
};

function fail() { throw 'secureops_delivery_failed'; }
function sendEvent(p) {
  var eventId, problemId, occurredAt, mapping, event;
  if (!p || (p.event_type !== 'problem' && p.event_type !== 'recovery')) fail();
  if (!/^[a-f0-9]{64}$/.test(p.webhook_key || '')) fail();
  if (p.host !== 'secureops-api') fail();
  if (!/^[1-9][0-9]{0,19}$/.test(p.trigger_id || '')) fail();
  if (!/^[1-9][0-9]{0,19}$/.test(p.problem_event_id || '')) fail();
  if (!/^[1-9][0-9]{0,10}$/.test(p.occurred_at || '')) fail();
  mapping = conditions[p.trigger_id];
  if (!mapping) fail();
  if (p.event_type === 'problem') {
    eventId = p.event_id;
    problemId = p.problem_event_id;
    if (eventId !== problemId) fail();
  } else {
    eventId = p.event_id;
    problemId = p.problem_event_id;
    if (eventId === problemId) fail();
  }
  if (!/^[1-9][0-9]{0,19}$/.test(eventId || '')) fail();
  event = {
    contract_version: 1,
    source: 'zabbix',
    source_instance: 'secureops-lab-zabbix',
    event_type: p.event_type,
    event_id: eventId,
    problem_event_id: problemId,
    trigger_id: p.trigger_id,
    host: p.host,
    service: 'secureops-api',
    condition: mapping.condition,
    category: mapping.category,
    occurred_at: p.occurred_at
  };
  var request = new HttpRequest();
  request.addHeader('Content-Type: application/json');
  request.addHeader('X-SecureOps-Webhook-Key: ' + p.webhook_key);
  var response = request.post('http://incident-receiver:3000/v1/events', JSON.stringify(event));
  var status = request.getStatus();
  if (status !== 200) fail();
  var result;
  try { result = JSON.parse(response); } catch (e) { fail(); }
  if (!result || ['applied', 'duplicate', 'pending'].indexOf(result.result) === -1) fail();
  return 'OK';
}

return sendEvent(JSON.parse(value));
