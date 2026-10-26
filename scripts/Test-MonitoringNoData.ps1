# Interrompe TEMPORARIAMENTE apenas o processo http poller, nao o avaliador de triggers.
# CONT em finally e watchdog de 180s; sem capacidades extras, root ou alteracao da API.
[CmdletBinding()]
param([switch] $RunNoData)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$compose=@('compose','-f',(Join-Path $root 'compose.yaml'),'-f',(Join-Path $root 'compose.identity.yaml'),'-f',(Join-Path $root 'compose.monitoring.yaml'))
if(-not $RunNoData){& (Join-Path $PSScriptRoot 'Test-MonitoringAvailability.ps1');return}
$json=& docker @compose config --format json
if($LASTEXITCODE -ne 0){throw 'Compose invalido.'}
$config=$json|ConvertFrom-Json
function Check-Phase([string] $Phase){
    & docker run --rm --pull never --network $config.networks.monitoring.name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=bind,source=$root/infra/monitoring,target=/checks,readonly" --mount "type=bind,source=$root/.local/monitoring/validation-state,target=/state" --mount "type=bind,source=$root/.local/monitoring/zabbix-api-token,target=/secrets/zabbix-api-token,readonly" secureops-api:0.1.0 node /checks/test-availability-nodata.mjs $Phase
    if($LASTEXITCODE -ne 0){throw "Fase de nodata falhou: $Phase"}
}
$processes=& docker @compose exec -T zabbix-server ps -o pid,args
if($LASTEXITCODE -ne 0){throw 'Nao foi possivel identificar poller.'}
$pollers=@($processes|Where-Object {$_ -match '^\s*(\d+)\s+/usr/sbin/zabbix_server: http poller #\d+ '}|ForEach-Object {if($_ -match '^\s*(\d+)') {[int]$Matches[1]}})
if($pollers.Count -ne 1){throw 'Esperado exatamente um http poller; nao enviar sinais.'}
$pollerId=$pollers[0]
Check-Phase 'baseline'
$intervened=$false
try{
    $intervened=$true
    # PID conferido e convertido a inteiro; watchdog independente do processo PowerShell.
    & docker @compose exec -T zabbix-server sh -c '(sleep 180; kill -CONT "$1") >/dev/null 2>&1 & kill -STOP "$1"' _ $pollerId
    if($LASTEXITCODE -ne 0){throw 'Pausa nao confirmada.'}
    & docker @compose --profile tools run --rm --no-deps probe
    if($LASTEXITCODE -ne 0){throw 'API nao estava saudavel durante pausa da coleta.'}
    Check-Phase 'down'
}finally{
    if($intervened){
        & docker @compose exec -T zabbix-server kill -CONT $pollerId
        if($LASTEXITCODE -ne 0){throw 'CONT falhou; watchdog deve retomar em ate 180s. Diagnosticar sem remover dados.'}
    }
}
Check-Phase 'recovery'
& (Join-Path $PSScriptRoot 'Test-MonitoringAvailability.ps1')
