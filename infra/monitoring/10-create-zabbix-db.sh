#!/usr/bin/env bash
# Executado uma unica vez pelo entrypoint oficial em volume PostgreSQL novo.
# Sem root do SO; o papel bootstrap postgres nao e compartilhado com o Zabbix.
set -Eeuo pipefail

ZABBIX_DB_PASSWORD="$(cat /run/secrets/monitoring-zabbix-db)"
if [[ ! "$ZABBIX_DB_PASSWORD" =~ ^[a-f0-9]{64}$ ]]; then
    echo 'Invalid monitoring database secret; value omitted.' >&2
    exit 1
fi
export ZABBIX_DB_PASSWORD

psql --no-psqlrc --set=ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<'SQL'
\getenv zabbix_password ZABBIX_DB_PASSWORD
CREATE ROLE zabbix LOGIN PASSWORD :'zabbix_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE DATABASE zabbix OWNER zabbix;
REVOKE ALL ON DATABASE zabbix FROM PUBLIC;
\connect zabbix
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO zabbix;
SQL

unset ZABBIX_DB_PASSWORD
