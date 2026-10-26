[CmdletBinding()]
param([ValidateSet('status','clean','fresh','one','threshold','recovery','positive-before','positive-after')][string] $Phase='status',[ValidateSet('1','2')][string] $Cycle='1',[long] $Since=0)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$json=& docker compose -f (Join-Path $root 'compose.yaml') -f (Join-Path $root 'compose.identity.yaml') -f (Join-Path $root 'compose.monitoring.yaml') config --format json
if($LASTEXITCODE -ne 0){throw 'Compose invalido.'}
$config=$json|ConvertFrom-Json
& docker run --rm --pull never --network $config.networks.monitoring.name --network $config.networks.identity.name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 256m --mount "type=bind,source=$root/infra/monitoring,target=/checks,readonly" --mount "type=bind,source=$root/apps/identity-event-collector/collector.ts,target=/collector/collector.ts,readonly" --mount "type=bind,source=$root/.local/monitoring/validation-state,target=/state" --mount "type=bind,source=$root/.local/monitoring/zabbix-api-token,target=/secrets/zabbix-api-token,readonly" --mount "type=bind,source=$root/.local/monitoring/collector-client-secret,target=/secrets/collector-client-secret,readonly" --mount "type=bind,source=$root/.local/monitoring/collector-realm-id,target=/secrets/collector-realm-id,readonly" secureops-api:0.1.0 node /checks/observe-security.mjs $Phase $Cycle $Since
if($LASTEXITCODE -ne 0){throw 'Observacao de seguranca falhou; nao alterar eventos/credenciais para repetir.'}
