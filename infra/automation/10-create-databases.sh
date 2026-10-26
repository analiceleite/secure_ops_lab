#!/usr/bin/env bash
# Somente no volume NOVO da automacao; sem leitura/escrita no banco Zabbix.
set -Eeuo pipefail
for name in n8n-db incident-ingest incident-report incident-reader; do
    value="$(cat "/run/secrets/automation-$name")"
    [[ "$value" =~ ^[a-f0-9]{64}$ ]] || { echo 'Invalid automation secret; value omitted.' >&2; exit 1; }
    case "$name" in
        n8n-db) export N8N_DB_SECRET="$value";;
        incident-ingest) export INGEST_SECRET="$value";;
        incident-report) export REPORT_SECRET="$value";;
        incident-reader) export READER_SECRET="$value";;
    esac
done
unset value
psql --no-psqlrc --set=ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL'
SET log_min_error_statement = 'panic';
SET log_statement = 'none';
\getenv meta_password N8N_DB_SECRET
\getenv ingest_password INGEST_SECRET
\getenv report_password REPORT_SECRET
\getenv reader_password READER_SECRET
CREATE ROLE n8n_meta LOGIN PASSWORD :'meta_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE ROLE incident_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE ROLE incident_ingest LOGIN PASSWORD :'ingest_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE ROLE incident_report LOGIN PASSWORD :'report_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE ROLE incident_reader LOGIN PASSWORD :'reader_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
REVOKE ALL ON DATABASE postgres FROM PUBLIC;
REVOKE ALL ON DATABASE template1 FROM PUBLIC;
CREATE DATABASE n8n OWNER n8n_meta;
REVOKE ALL ON DATABASE n8n FROM PUBLIC;
GRANT CONNECT ON DATABASE n8n TO n8n_meta;
\connect n8n
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO n8n_meta;
CREATE DATABASE incidents OWNER incident_owner;
REVOKE ALL ON DATABASE incidents FROM PUBLIC;
GRANT CONNECT ON DATABASE incidents TO incident_ingest, incident_report, incident_reader;
\connect incidents
REVOKE ALL ON SCHEMA public FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE incident_owner REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
-- Nenhum grant de tabela/DML aqui: migrações/rotinas ainda sao outra etapa.
SQL
unset N8N_DB_SECRET INGEST_SECRET REPORT_SECRET READER_SECRET
