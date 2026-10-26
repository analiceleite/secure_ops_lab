# Pela API oficial; somente leitura por padrao. Payload ainda depende de validacao
# real no Zabbix. Em falha parcial, nao repetir -Apply sem diagnosticar o estado.
[CmdletBinding()]
param([switch] $Apply)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$local = Join-Path $root '.local/monitoring'
if (-not (Test-Path -LiteralPath (Join-Path $local 'zabbix-api-token'))) { throw 'Salve um NOVO token pelo Save-MonitoringApiToken.ps1; nunca envie ao chat.' }
$state = Join-Path $local 'validation-state'
if (-not (Test-Path -LiteralPath $state)) { $null = New-Item -ItemType Directory -Path $state }
$configJson = & docker compose -f (Join-Path $root 'compose.yaml') -f (Join-Path $root 'compose.identity.yaml') -f (Join-Path $root 'compose.monitoring.yaml') --profile monitoring-security config --format json
if ($LASTEXITCODE -ne 0) { throw 'Compose invalido.' }
$config = $configJson | ConvertFrom-Json
$extra = @()
if ($Apply) { $extra += '--apply' }
& docker run --rm --pull never --network $config.networks.monitoring.name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 256m --mount "type=bind,source=$root/infra/monitoring,target=/checks,readonly" --mount "type=bind,source=$local/zabbix-api-token,target=/secrets/zabbix-api-token,readonly" --mount "type=bind,source=$local/collector-metrics-secret,target=/secrets/collector-metrics-secret,readonly" --mount "type=bind,source=$state,target=/state" secureops-api:0.1.0 node /checks/configure-security.mjs @extra
if ($LASTEXITCODE -ne 0) { throw 'Configuracao/inspecao de seguranca falhou; preservar recursos parciais, sem reimportar ou sobrescrever.' }
