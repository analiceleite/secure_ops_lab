#!/usr/bin/env bash
set -Eeuo pipefail
# Chamadas separadas/autocommit; barreira libera as 20 conexões juntas.
sql() { psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d incidents "$@"; }
epoch="$(sql -c 'SELECT extract(epoch FROM now())::bigint - 60')"
event() {
  printf '{"contract_version":1,"source":"zabbix","source_instance":"%s","event_type":"problem","event_id":"%s","problem_event_id":"%s","trigger_id":"1","host":"secureops-api","service":"secureops-api","condition":"api-http","category":"availability","occurred_at":"%s"}' "$1" "$2" "$2" "$epoch"
}
# Bloquear linha da condição permite observar 20 chamadas realmente em voo.
sql -c "BEGIN; SELECT * FROM incident.allowed_conditions WHERE source_instance='concurrency' FOR UPDATE; SELECT pg_sleep(3); COMMIT" >/tmp/blocker &
blocker=$!
sleep 0.3
body="$(event concurrency 900)"
pids=()
for i in $(seq 1 20); do
  sql -c "SET ROLE incident_ingest; SELECT incident.ingest('$body')" >"/tmp/concurrent-$i" 2>/dev/null &
  pids+=("$!")
done
sleep 1
waiting="$(sql -c "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock' AND query LIKE '%incident.ingest(%'")"
[[ "$waiting" == 20 ]] || { echo 'concurrency_barrier_failed' >&2; exit 1; }
wait "$blocker"
for pid in "${pids[@]}"; do wait "$pid"; done
[[ "$(grep -l '"applied"' /tmp/concurrent-* | wc -l)" == 1 ]]
[[ "$(grep -l '"duplicate"' /tmp/concurrent-* | wc -l)" == 19 ]]
[[ "$(sql -c "SELECT count(*) FROM incident.deliveries WHERE source_instance='concurrency'")" == 1 ]]
[[ "$(sql -c "SELECT count(*) FROM incident.incidents WHERE source_instance='concurrency'")" == 1 ]]
echo '{"check":"incident_concurrent_duplicate","result":"pass","simultaneousBlockedCalls":20,"applied":1,"duplicate":19,"incidents":1}'

# Dois primeiros ciclos diferentes disputam condição ainda sem ciclos.
sql -c "BEGIN; SELECT * FROM incident.allowed_conditions WHERE source_instance='first-race' FOR UPDATE; SELECT pg_sleep(3); COMMIT" >/tmp/race-blocker &
blocker=$!
sleep 0.3
pids=()
for i in 910 920; do
  body="$(event first-race "$i")"
  sql -c "SET ROLE incident_ingest; SELECT incident.ingest('$body')" >"/tmp/race-$i" 2>/dev/null &
  pids+=("$!")
done
sleep 1
waiting="$(sql -c "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock' AND query LIKE '%incident.ingest(%'")"
[[ "$waiting" == 2 ]] || { echo 'first_race_barrier_failed' >&2; exit 1; }
wait "$blocker"
for pid in "${pids[@]}"; do wait "$pid"; done
[[ "$(grep -l '"applied"' /tmp/race-* | wc -l)" == 1 ]]
[[ "$(grep -l '"conflict"' /tmp/race-* | wc -l)" == 1 ]]
[[ "$(sql -c "SELECT count(*) FROM incident.deliveries WHERE source_instance='first-race'")" == 1 ]]
[[ "$(sql -c "SELECT count(*) FROM incident.incidents WHERE source_instance='first-race'")" == 1 ]]
echo '{"check":"incident_first_cycle_race","result":"pass","simultaneousBlockedCalls":2,"applied":1,"conflict":1,"ledgerRows":1,"incidents":1}'

# Lock timeout não retorna resultado positivo nem deixa ledger/ciclo/job.
sql -c "BEGIN; SELECT * FROM incident.allowed_conditions WHERE source_instance='lock-timeout' FOR UPDATE; SELECT pg_sleep(6); COMMIT" >/tmp/timeout-blocker &
blocker=$!
sleep 0.3
body="$(event lock-timeout 930)"
if sql -v VERBOSITY=verbose -c "SET statement_timeout='5s'; SET ROLE incident_ingest; SELECT incident.ingest('$body')" >/tmp/timeout-result 2>/tmp/timeout-error; then
  echo 'lock_timeout_false_success' >&2; exit 1
fi
grep -q '55P03' /tmp/timeout-error
wait "$blocker"
[[ "$(sql -c "SELECT count(*) FROM incident.deliveries WHERE source_instance='lock-timeout'")" == 0 ]]
[[ "$(sql -c "SELECT count(*) FROM incident.cycles WHERE source_instance='lock-timeout'")" == 0 ]]
echo '{"check":"incident_lock_timeout_rollback","result":"pass","sqlstate":"55P03","ledgerRows":0,"cycles":0,"positiveResult":false}'
