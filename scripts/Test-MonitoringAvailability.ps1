# Diagnostico real somente leitura por padrao. -RunFailureCycles para dois ciclos
# explicitamente destrutivos apenas da disponibilidade da API (sem apagar dados).
[CmdletBinding()]
param([switch] $RunFailureCycles)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$compose = @('compose', '-f', (Join-Path $root 'compose.yaml'), '-f', (Join-Path $root 'compose.identity.yaml'), '-f', (Join-Path $root 'compose.monitoring.yaml'), '--profile', 'monitoring-security')
$failureName = 'SecureOps API: falha na verificacao HTTP interna'
$collectionName = 'SecureOps API: verificacao HTTP sem dados recentes'

function Read-ZabbixJson([string] $Sql) {
    # Nao configura o Zabbix por SQL; usa somente SELECT para observar evidencia.
    $result = & docker @compose exec -T zabbix-db psql --no-psqlrc --set=ON_ERROR_STOP=1 -U postgres -d zabbix -Atc $Sql
    if ($LASTEXITCODE -ne 0 -or -not $result) { throw 'Leitura de evidencia Zabbix falhou.' }
    return ($result | ConvertFrom-Json)
}

function Read-Container([string] $Name) {
    $id = & docker @compose ps -a -q $Name
    if ($LASTEXITCODE -ne 0 -or -not $id) { throw "Container ausente: $Name" }
    $json = & docker inspect $id
    if ($LASTEXITCODE -ne 0) { throw "Inspecao falhou: $Name" }
    return ($json | ConvertFrom-Json)[0]
}

function Read-State([long] $Since) {
    return Read-ZabbixJson @"
SELECT json_build_object(
 'now',extract(epoch from clock_timestamp())::bigint,
 'latest',(SELECT json_build_object('clock',v.clock,'value',v.value) FROM history_uint v JOIN items i ON i.itemid=v.itemid JOIN hosts h ON h.hostid=i.hostid WHERE h.host='secureops-api' AND i.key_='web.test.fail[api-health]' ORDER BY v.clock DESC,v.ns DESC LIMIT 1),
 'response',(SELECT json_build_object('clock',v.clock,'value',v.value) FROM history_uint v JOIN items i ON i.itemid=v.itemid JOIN hosts h ON h.hostid=i.hostid WHERE h.host='secureops-api' AND i.key_='web.test.rspcode[api-health,health]' ORDER BY v.clock DESC,v.ns DESC LIMIT 1),
 'failed_samples',(SELECT count(*) FROM history_uint v JOIN items i ON i.itemid=v.itemid JOIN hosts h ON h.hostid=i.hostid WHERE h.host='secureops-api' AND i.key_='web.test.fail[api-health]' AND v.clock >= $Since AND v.value<>0),
 'open_problems',(SELECT count(*) FROM problem p WHERE p.source=0 AND p.object=0 AND p.r_eventid IS NULL AND p.objectid IN (SELECT t.triggerid FROM triggers t JOIN functions f ON f.triggerid=t.triggerid JOIN items i ON i.itemid=f.itemid JOIN hosts h ON h.hostid=i.hostid WHERE h.host='secureops-api' AND t.description='$failureName')),
 'problem_events',(SELECT count(*) FROM events e WHERE e.source=0 AND e.object=0 AND e.value=1 AND e.clock >= $Since AND e.objectid IN (SELECT t.triggerid FROM triggers t JOIN functions f ON f.triggerid=t.triggerid JOIN items i ON i.itemid=f.itemid JOIN hosts h ON h.hostid=i.hostid WHERE h.host='secureops-api' AND t.description='$failureName')),
 'last_problem',(SELECT json_build_object('eventid',e.eventid::text,'clock',e.clock,'recovery_eventid',r.r_eventid::text,'recovery_clock',ok.clock) FROM events e LEFT JOIN event_recovery r ON r.eventid=e.eventid LEFT JOIN events ok ON ok.eventid=r.r_eventid WHERE e.source=0 AND e.object=0 AND e.value=1 AND e.objectid IN (SELECT t.triggerid FROM triggers t JOIN functions f ON f.triggerid=t.triggerid JOIN items i ON i.itemid=f.itemid JOIN hosts h ON h.hostid=i.hostid WHERE h.host='secureops-api' AND t.description='$failureName') ORDER BY e.clock DESC,e.ns DESC LIMIT 1),
 'collection_problem',(SELECT t.value FROM triggers t JOIN functions f ON f.triggerid=t.triggerid JOIN items i ON i.itemid=f.itemid JOIN hosts h ON h.hostid=i.hostid WHERE h.host='secureops-api' AND t.description='$collectionName' LIMIT 1)
)
"@
}

function Assert-OtherServices($Baseline) {
    foreach ($name in $Baseline.Keys) {
        $current = Read-Container $name
        if (-not $current.State.Running -or $current.Id -ne $Baseline[$name].Id -or $current.State.StartedAt -ne $Baseline[$name].StartedAt) {
            throw "Outro servico parou/reiniciou durante o ensaio: $name"
        }
    }
}

function Restore-Api {
    & docker @compose up -d --no-deps --pull never --wait --wait-timeout 60 api
    if ($LASTEXITCODE -ne 0) { throw 'Retomada da API falhou; preservar dados e diagnosticar.' }
}

$config = Read-ZabbixJson @"
SELECT json_build_object('host',h.host,'host_status',h.status,'scenario',t.name,'delay',t.delay,'attempts',t.retries,'scenario_status',t.status,'authentication',t.authentication,'step',s.name,'url',s.url,'timeout',s.timeout,'status_codes',s.status_codes,'follow_redirects',s.follow_redirects)
FROM hosts h JOIN httptest t ON t.hostid=h.hostid JOIN httpstep s ON s.httptestid=t.httptestid
WHERE h.host='secureops-api' AND t.name='api-health'
"@
if ($config.host -ne 'secureops-api' -or $config.host_status -ne 0 -or $config.delay -ne '20s' -or $config.attempts -ne 1 -or $config.scenario_status -ne 0 -or $config.authentication -ne 0 -or $config.step -ne 'health' -or $config.url -ne 'http://api:3000/health' -or $config.timeout -ne '5s' -or $config.status_codes -ne '200' -or $config.follow_redirects -ne 0) {
    throw 'Configuracao real do cenario diverge do contrato; nao parar a API.'
}
$triggers = Read-ZabbixJson @"
SELECT json_agg(json_build_object('name',t.description,'status',t.status,'type',t.type,'manual_close',t.manual_close,'recovery_mode',t.recovery_mode,'expression',t.expression,'matches_contract',
 CASE WHEN t.description='$failureName' THEN f.name='last' AND f.parameter='$' AND t.expression=concat('{',f.functionid,'}<>0')
 ELSE t.description='$collectionName' AND f.name='nodata' AND f.parameter='$,90s' AND t.expression=concat('{',f.functionid,'}=1') END))
FROM triggers t JOIN functions f ON f.triggerid=t.triggerid JOIN items i ON i.itemid=f.itemid JOIN hosts h ON h.hostid=i.hostid
WHERE h.host='secureops-api' AND i.key_='web.test.fail[api-health]'
"@
if (@($triggers).Count -ne 2 -or @($triggers | Where-Object { $_.status -ne 0 -or $_.type -ne 0 -or $_.manual_close -ne 0 -or $_.recovery_mode -ne 0 -or $_.matches_contract -ne $true }).Count) {
    throw 'Triggers reais divergentes; nao parar a API.'
}
if (@($triggers | Where-Object name -eq $failureName).Count -ne 1 -or @($triggers | Where-Object name -eq $collectionName).Count -ne 1) {
    throw 'Triggers esperadas ausentes/duplicadas; nao parar a API.'
}
$healthy = Read-ZabbixJson @"
SELECT coalesce(json_agg(json_build_object('clock',s.clock,'value',s.value)),'[]'::json)
FROM (SELECT v.clock,v.value FROM history_uint v JOIN items i ON i.itemid=v.itemid JOIN hosts h ON h.hostid=i.hostid WHERE h.host='secureops-api' AND i.key_='web.test.fail[api-health]' ORDER BY v.clock DESC,v.ns DESC LIMIT 2) s
"@
$state = Read-State 0
if (@($healthy).Count -ne 2 -or @($healthy | Where-Object value -ne 0).Count -or $state.latest.value -ne 0 -or $state.response.value -ne 200 -or $state.open_problems -ne 0 -or $state.collection_problem -ne 0 -or $state.now - $state.latest.clock -gt 60) {
    throw 'Duas amostras saudaveis recentes e triggers normais ainda nao comprovadas; nao parar a API.'
}
$hostClock = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if ([math]::Abs($hostClock - $state.now) -gt 3) { throw 'Relogios do host/banco divergentes; nao medir latencia.' }
$api = Read-Container 'api'
if (-not $api.State.Running -or $api.State.Health.Status -ne 'healthy') { throw 'API deve iniciar o ensaio executando e healthy.' }
Write-Output (@{ check='availability_import_and_recent_samples';result='pass';samples=$healthy;response=$state.response } | ConvertTo-Json -Depth 5 -Compress)
if (-not $RunFailureCycles) {
    Write-Output 'Inspecao somente leitura aprovada; nenhum servico foi parado.'
    return
}

$others = @{}
foreach ($name in @('keycloak','oauth2-proxy','zabbix-db','zabbix-server','zabbix-web','identity-event-collector')) {
    $container = Read-Container $name
    if (-not $container.State.Running) { throw "Servico necessario parado: $name" }
    $others[$name] = @{Id=$container.Id;StartedAt=$container.State.StartedAt}
}

$intervened = $false
try {
    foreach ($cycle in 1..2) {
        $stopCommandAt = [DateTimeOffset]::Now.ToString('o')
        $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $intervened = $true
        & docker @compose stop api
        if ($LASTEXITCODE -ne 0) { throw 'Falha na parada controlada da API.' }
        if ((Read-Container 'api').State.Running) { throw 'Parada da API nao confirmada.' }
        $stopped = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds(60)
        do {
            $state = Read-State $since
            if ($state.latest.value -ne 0 -and $state.open_problems -eq 1 -and $state.last_problem.clock -ge $since) { break }
            if ([DateTimeOffset]::UtcNow -gt $deadline) { throw 'Problema DOWN nao observado em ate 60s.' }
            Start-Sleep -Seconds 2
        } while ($true)
        $down = $state.last_problem
        if ($down.clock - $stopped -gt 60) { throw 'Latencia DOWN acima da meta.' }
        Write-Output (@{cycle=$cycle;phase='down';stopCommandAt=$stopCommandAt;stoppedEpoch=$stopped;problem=$down;detectionSeconds=($down.clock-$stopped);detectedBeforeStopConfirmation=($down.clock -lt $stopped)} | ConvertTo-Json -Depth 5 -Compress)

        # Tres falhas comprovam primeira deteccao + duas execucoes adicionais.
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds(70)
        do {
            $state = Read-State $since
            if ($state.problem_events -ne 1 -or $state.open_problems -ne 1 -or $state.collection_problem -ne 0) { throw 'Duplicacao, falsa recuperacao ou ausencia de coleta durante DOWN.' }
            if ($state.failed_samples -ge 3) { break }
            if ([DateTimeOffset]::UtcNow -gt $deadline) { throw 'Amostras adicionais DOWN nao observadas.' }
            Start-Sleep -Seconds 2
        } while ($true)
        Assert-OtherServices $others
        $failedSamples = $state.failed_samples
        $restartCommandAt = [DateTimeOffset]::Now.ToString('o')
        Restore-Api
        $healthyAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        & docker @compose --profile tools run --rm --no-deps probe
        if ($LASTEXITCODE -ne 0) { throw 'Probe falhou apos retomada da API.' }
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds(60)
        do {
            $state = Read-State $since
            if ($state.latest.value -eq 0 -and $state.response.value -eq 200 -and $state.open_problems -eq 0 -and $state.last_problem.eventid -eq $down.eventid -and $null -ne $state.last_problem.recovery_eventid) { break }
            if ([DateTimeOffset]::UtcNow -gt $deadline) { throw 'Recuperacao UP nao observada em ate 60s apos healthy.' }
            Start-Sleep -Seconds 2
        } while ($true)
        $latency = $state.last_problem.recovery_clock - $healthyAt
        if ($latency -gt 60 -or $state.problem_events -ne 1 -or $state.collection_problem -ne 0) { throw 'Recuperacao, contagem ou latencia divergente.' }
        Assert-OtherServices $others
        if ((Read-Container 'api').Id -ne $api.Id) { throw 'API foi recriada inesperadamente; revisar.' }
        Write-Output (@{cycle=$cycle;phase='recovered';restartCommandAt=$restartCommandAt;healthyConfirmedEpoch=$healthyAt;problem=$state.last_problem;recoverySecondsAfterHealthConfirmation=$latency;recoveredBeforeHealthConfirmation=($latency -lt 0);observedDurationSeconds=($state.last_problem.recovery_clock-$down.clock);failedSamples=$failedSamples;problemEvents=$state.problem_events;otherServicesPreserved=$true} | ConvertTo-Json -Depth 5 -Compress)
    }
} finally {
    # Mesmo se medicao/assertion falhar, retomar somente a API que o script parou.
    if ($intervened) {
        $current = Read-Container 'api'
        if (-not $current.State.Running -or $current.State.Health.Status -ne 'healthy') { Restore-Api }
    }
}
Write-Output 'Dois ciclos reais aprovados. API retomada; nenhum dado/volume removido.'
