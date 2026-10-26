[CmdletBinding()]
param([ValidateSet('inspect','prepare','enable','disable')][string]$Mode='inspect')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$local=Join-Path $root '.local/monitoring'
$automation=Join-Path $root '.local/automation'
$tokenPath=Join-Path $local 'zabbix-api-token'
if(-not (Test-Path -LiteralPath $tokenPath)){throw 'Token Zabbix temporario ausente; nao passe o token como argumento.'}
$compose=@('-f',(Join-Path $root 'compose.yaml'),'-f',(Join-Path $root 'compose.identity.yaml'),'-f',(Join-Path $root 'compose.monitoring.yaml'),'-f',(Join-Path $root 'compose.automation.yaml'),'--profile','monitoring-security','--profile','automation','config','--format','json')
$json=& docker compose @compose
if($LASTEXITCODE -ne 0){throw 'Compose invalido.'}
$config=$json|ConvertFrom-Json
& docker run --rm --pull never --network $config.networks.monitoring.name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 256m --mount "type=bind,source=$(Join-Path $root 'infra/monitoring'),target=/checks,readonly" --mount "type=bind,source=$tokenPath,target=/secrets/zabbix-api-token,readonly" --mount "type=bind,source=$(Join-Path $automation 'webhook-key'),target=/secrets/incident-webhook-key,readonly" secureops-api:0.1.0 node /checks/incident-action.mjs $Mode
if($LASTEXITCODE -ne 0){throw 'Configuracao de action falhou; preserve objetos parciais e diagnostique antes de repetir.'}
