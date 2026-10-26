# Interrompe somente componente explicitamente selecionado, com alerta real aberto.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('keycloak','identity-event-collector')][string] $Component,[switch] $RunFailure)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$compose=@('compose','-f',(Join-Path $root 'compose.yaml'),'-f',(Join-Path $root 'compose.identity.yaml'),'-f',(Join-Path $root 'compose.monitoring.yaml'),'--profile','monitoring-security')
$json=& docker @compose config --format json
if($LASTEXITCODE -ne 0){throw 'Compose invalido.'}
$config=$json|ConvertFrom-Json
function Check-Phase([string] $Phase,[long] $Since=0){
    & docker run --rm --pull never --network $config.networks.monitoring.name --network $config.networks.identity.name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=bind,source=$root/infra/monitoring,target=/checks,readonly" --mount "type=bind,source=$root/.local/monitoring/validation-state,target=/state" --mount "type=bind,source=$root/.local/monitoring/zabbix-api-token,target=/secrets/zabbix-api-token,readonly" secureops-api:0.1.0 node /checks/test-source-failure.mjs $Phase $Component $Since
    if($LASTEXITCODE -ne 0){throw "Fase nao aprovada: $Phase; restaurar componente e diagnosticar."}
}
if(-not $RunFailure){& (Join-Path $PSScriptRoot 'Observe-MonitoringSecurity.ps1');return}
$others=@{}
foreach($name in @('api','keycloak','oauth2-proxy','zabbix-db','zabbix-server','zabbix-web','identity-event-collector')|Where-Object {$_ -ne $Component}){
    $id=& docker @compose ps -q $name
    if($LASTEXITCODE -ne 0 -or -not $id){throw "Servico deve estar ativo: $name"}
    $json=& docker inspect $id
    if($LASTEXITCODE -ne 0){throw 'Inspecao falhou.'}
    $c=($json|ConvertFrom-Json)[0];$others[$name]=@{Id=$c.Id;StartedAt=$c.State.StartedAt}
}
Check-Phase 'before'
$intervened=$false
try{
    $intervened=$true
    & docker @compose stop $Component
    if($LASTEXITCODE -ne 0){throw 'Parada nao confirmada.'}
    $stopped=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Check-Phase 'down' $stopped
}finally{
    if($intervened){
        & docker @compose up -d --no-deps --no-recreate --pull never --wait --wait-timeout 180 $Component
        if($LASTEXITCODE -ne 0){throw 'Retomada falhou; preservar volume e diagnosticar.'}
        if($Component -eq 'keycloak'){
            & docker run --rm --pull never --network $config.networks.identity.name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=bind,source=$root/infra/monitoring,target=/checks,readonly" secureops-api:0.1.0 node /checks/wait-keycloak.mjs
            if($LASTEXITCODE -ne 0){throw 'Discovery nao retomou.'}
            & docker @compose --profile tools run --rm --no-deps identity-check
            if($LASTEXITCODE -ne 0){throw 'Discovery/JWKS/negativa nao confirmados.'}
        }
    }
}
$restored=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Check-Phase 'recovery' $restored
foreach($name in $others.Keys){
    $id=& docker @compose ps -q $name
    $json=& docker inspect $id
    if($LASTEXITCODE -ne 0){throw 'Inspecao final falhou.'}
    $c=($json|ConvertFrom-Json)[0]
    if(-not $c.State.Running -or $c.Id -ne $others[$name].Id -or $c.State.StartedAt -ne $others[$name].StartedAt){throw "Outro servico foi alterado: $name"}
}
Write-Output "Falha/retomada aprovada: $Component; demais seis servicos preservados."
