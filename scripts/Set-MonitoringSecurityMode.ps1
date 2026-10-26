# Flags de itens/triggers apenas; nao inicia/para servicos nem apaga historico.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('availability','full')][string] $Mode)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$json=& docker compose -f (Join-Path $root 'compose.yaml') -f (Join-Path $root 'compose.monitoring.yaml') config --format json
if($LASTEXITCODE -ne 0){throw 'Compose invalido.'}
$config=$json|ConvertFrom-Json
& docker run --rm --pull never --network $config.networks.monitoring.name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=bind,source=$root/infra/monitoring,target=/checks,readonly" --mount "type=bind,source=$root/.local/monitoring/validation-state,target=/state,readonly" --mount "type=bind,source=$root/.local/monitoring/zabbix-api-token,target=/secrets/zabbix-api-token,readonly" secureops-api:0.1.0 node /checks/security-mode.mjs $Mode
if($LASTEXITCODE -ne 0){throw 'Mudanca de modo nao confirmada; preservar estado e diagnosticar.'}
