[CmdletBinding()]
param([switch] $RunRestartAndRecreate)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(-not $RunRestartAndRecreate){& (Join-Path $PSScriptRoot 'Observe-MonitoringSecurity.ps1');return}
$compose=@('compose','-f',(Join-Path $root 'compose.yaml'),'-f',(Join-Path $root 'compose.identity.yaml'),'-f',(Join-Path $root 'compose.monitoring.yaml'),'--profile','monitoring-security')
function Read-Container([string]$Name){
    $id=& docker @compose ps -q $Name
    if($LASTEXITCODE -ne 0 -or -not $id){throw "Container ausente: $Name"}
    $json=& docker inspect $id
    if($LASTEXITCODE -ne 0){throw 'Inspecao falhou.'}
    return ($json|ConvertFrom-Json)[0]
}
$status=& (Join-Path $PSScriptRoot 'Observe-MonitoringSecurity.ps1')|ConvertFrom-Json
if($status.sourceCount -ne 5 -or $status.zabbixCount -ne 5 -or -not $status.authProblem -or $status.technicalProblem){throw 'Exigida janela real de cinco eventos com coleta valida e alerta aberto.'}
$first=($status.eventTimes|Measure-Object -Minimum).Minimum
if($first+300000-[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -lt 120000){throw 'Janela remanescente curta; nao modificar eventos, repetir somente em ciclo oportuno.'}
$baseline=Read-Container 'identity-event-collector'
$others=@{}
foreach($name in @('api','keycloak','oauth2-proxy','zabbix-db','zabbix-server','zabbix-web')){$others[$name]=Read-Container $name}
$hashes=@{}
foreach($name in @('collector-client-secret','collector-metrics-secret','collector-realm-id')){$hashes[$name]=(Get-FileHash -LiteralPath (Join-Path $root ".local/monitoring/$name") -Algorithm SHA256).Hash}
try{
    foreach($phase in @('restart','recreate')){
        if($phase -eq 'restart'){
            & docker @compose restart --no-deps identity-event-collector
        }else{
            & docker @compose up -d --force-recreate --no-deps --pull never identity-event-collector
        }
        if($LASTEXITCODE -ne 0){throw 'Retomada do coletor falhou.'}
        $since=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $now=& (Join-Path $PSScriptRoot 'Observe-MonitoringSecurity.ps1') -Phase fresh -Since $since|ConvertFrom-Json
        if($now.sourceCount -ne 5 -or $now.zabbixCount -ne 5 -or -not $now.authProblem -or $now.technicalProblem){throw 'Reconstrucao da janela divergiu; investigar sem editar eventos.'}
        $actual=Read-Container 'identity-event-collector'
        if(($phase -eq 'restart') -ne ($actual.Id -eq $baseline.Id)){throw 'Identidade do container divergente da fase.'}
        if($actual.State.StartedAt -eq $baseline.State.StartedAt){throw 'Reinicio nao observado.'}
        foreach($name in $others.Keys){$c=Read-Container $name;if($c.Id -ne $others[$name].Id -or $c.State.StartedAt -ne $others[$name].State.StartedAt){throw "Outro servico mudou: $name"}}
        foreach($name in $hashes.Keys){if((Get-FileHash -LiteralPath (Join-Path $root ".local/monitoring/$name") -Algorithm SHA256).Hash -ne $hashes[$name]){throw 'Arquivo de segredo/configuracao mudou; valor omitido.'}}
        Write-Output (@{phase=$phase;result='pass';sourceCount=5;newZabbixCount=5;quality=1;authStillOpen=$true;otherSixServicesUnchanged=$true;secretsPreserved=$true;noCollectorVolume=$true}|ConvertTo-Json -Compress)
    }
}finally{
    & docker @compose up -d --no-deps --pull never identity-event-collector
    if($LASTEXITCODE -ne 0){throw 'Coletor nao retomou; preservar dados e diagnosticar.'}
}
