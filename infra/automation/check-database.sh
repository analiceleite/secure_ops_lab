#!/usr/bin/env bash
# Somente verificacoes; nenhum DDL/mutacao ou segredo na saida.
set -Eeuo pipefail
result="$(psql --no-psqlrc --set=ON_ERROR_STOP=1 -U postgres -d postgres -Atc "
 SELECT bool_and(NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication)
 FROM pg_roles WHERE rolname IN ('n8n_meta','incident_ingest','incident_report','incident_reader','incident_owner');")"
[[ "$result" == t ]] || { echo 'database_runtime_privileges_failed' >&2; exit 1; }
result="$(psql --no-psqlrc --set=ON_ERROR_STOP=1 -U postgres -d postgres -Atc "
 SELECT NOT has_database_privilege('n8n_meta','incidents','CONNECT')
 AND NOT has_database_privilege('incident_ingest','n8n','CONNECT')
 AND NOT has_database_privilege('incident_report','n8n','CONNECT')
 AND NOT has_database_privilege('incident_reader','n8n','CONNECT')
 AND NOT has_database_privilege('n8n_meta','postgres','CONNECT');")"
[[ "$result" == t ]] || { echo 'database_isolation_failed' >&2; exit 1; }
export PGPASSWORD="$(cat /run/secrets/automation-n8n-db)"
psql --no-psqlrc --set=ON_ERROR_STOP=1 -h automation-db -U n8n_meta -d n8n -Atc 'SELECT 1' >/dev/null
if psql --no-psqlrc --set=ON_ERROR_STOP=1 -h automation-db -U n8n_meta -d incidents -Atc 'SELECT 1' >/dev/null 2>&1; then
    echo 'metadata_role_reached_incidents' >&2; exit 1
fi
export PGPASSWORD="$(cat /run/secrets/automation-incident-ingest)"
psql --no-psqlrc --set=ON_ERROR_STOP=1 -h automation-db -U incident_ingest -d incidents -Atc 'SELECT 1' >/dev/null
result="$(psql --no-psqlrc --set=ON_ERROR_STOP=1 -h automation-db -U incident_ingest -d incidents -Atc "SELECT NOT has_schema_privilege(current_user,'public','CREATE');")"
[[ "$result" == t ]] || { echo 'ingest_can_create_arbitrary_tables' >&2; exit 1; }
export PGPASSWORD=FICTITIOUS-WRONG-PASSWORD
if psql --no-psqlrc --set=ON_ERROR_STOP=1 -h automation-db -U incident_ingest -d incidents -Atc 'SELECT 1' >/dev/null 2>&1; then
    echo 'wrong_database_password_accepted' >&2; exit 1
fi
unset PGPASSWORD
echo '{"check":"automation_database_isolation","result":"pass","tcpPasswordRequired":true,"runtimeRolesNotSuperusers":true,"metadataAndBusinessSeparated":true,"noBusinessDdlGrant":true,"noDataChanged":true}'
