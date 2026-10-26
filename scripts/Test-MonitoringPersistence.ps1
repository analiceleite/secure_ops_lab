# Somente leitura por padrao. A flag reinicia/recria APENAS monitoramento,
# incluindo coletor com -IncludeCollector; preserva volume e servicos centrais.
[CmdletBinding()]
param([switch] $RunRestartAndRecreate,[switch] $IncludeCollector)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$compose = @('compose', '-f', (Join-Path $root 'compose.yaml'), '-f', (Join-Path $root 'compose.identity.yaml'), '-f', (Join-Path $root 'compose.monitoring.yaml'))
if ($IncludeCollector) { $compose += @('--profile','monitoring-security') }
$monitoringServices=@('zabbix-db','zabbix-server','zabbix-web')
if ($IncludeCollector) { $monitoringServices += 'identity-event-collector' }

function Read-Json([string] $Sql) {
    $result = & docker @compose exec -T zabbix-db psql --no-psqlrc --set=ON_ERROR_STOP=1 -U postgres -d zabbix -Atc $Sql
    if ($LASTEXITCODE -ne 0 -or -not $result) { throw 'Leitura de evidencia PostgreSQL falhou.' }
    return ($result | ConvertFrom-Json)
}

function Read-Container([string] $Name) {
    $id = & docker @compose ps -a -q $Name
    if ($LASTEXITCODE -ne 0 -or -not $id) { throw "Container ausente: $Name" }
    $json = & docker inspect $id
    if ($LASTEXITCODE -ne 0) { throw "Inspecao falhou: $Name" }
    return ($json | ConvertFrom-Json)[0]
}

function Get-SnapshotHash($Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 40 -Compress))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToBase64String($sha.ComputeHash($bytes)) } finally { $sha.Dispose() }
}

# IDs/clocks abaixo sao lidos de eventos ficticios, convertidos a inteiros antes
# de interpolar SQL. Nenhuma senha, hash de senha ou sessao entra no snapshot.
$eventIds = @(Read-Json @"
SELECT coalesce(json_agg(s.eventid::text ORDER BY s.eventid),'[]'::json) FROM (
 SELECT e.eventid FROM events e WHERE e.source=0 AND e.object=0 AND e.objectid IN (
 SELECT t.triggerid FROM triggers t JOIN functions f ON f.triggerid=t.triggerid JOIN items i ON i.itemid=f.itemid JOIN hosts h ON h.hostid=i.hostid
 WHERE h.host='secureops-api' AND t.description='SecureOps API: falha na verificacao HTTP interna') ORDER BY e.eventid DESC LIMIT 4
) s
"@ | ForEach-Object { [long]$_ })
$sampleClocks = @(Read-Json @"
SELECT coalesce(json_agg(s.clock ORDER BY s.clock),'[]'::json) FROM (
 SELECT v.clock FROM history_uint v JOIN items i ON i.itemid=v.itemid JOIN hosts h ON h.hostid=i.hostid
 WHERE h.host='secureops-api' AND i.key_='web.test.fail[api-health]' AND v.value=0 ORDER BY v.clock DESC,v.ns DESC LIMIT 2
) s
"@ | ForEach-Object { [long]$_ })
if ($eventIds.Count -ne 4 -or $sampleClocks.Count -ne 2) { throw 'Exigidos dois ciclos anteriores e duas amostras saudaveis antes de testar persistencia.' }
$eventList = $eventIds -join ','
$clockList = $sampleClocks -join ','
$securityEvents='0'; $securityClocks='0'
if ($IncludeCollector) {
    $securityEvents=@(Read-Json @"
SELECT coalesce(json_agg(s.eventid::text ORDER BY s.eventid),'[]'::json) FROM (
 SELECT e.eventid FROM events e WHERE e.source=0 AND e.object=0 AND e.objectid IN (
 SELECT t.triggerid FROM triggers t JOIN functions f ON f.triggerid=t.triggerid JOIN items i ON i.itemid=f.itemid JOIN hosts h ON h.hostid=i.hostid
 WHERE h.host='secureops-api' AND t.description='SecureOps: falhas repetidas de autenticacao') ORDER BY e.eventid DESC LIMIT 4
) s
"@ | ForEach-Object { [long]$_ })
    $securityClocks=@(Read-Json @"
SELECT coalesce(json_agg(s.clock ORDER BY s.clock),'[]'::json) FROM (
 SELECT v.clock FROM history_uint v JOIN items i ON i.itemid=v.itemid JOIN hosts h ON h.hostid=i.hostid
 WHERE h.host='secureops-api' AND i.key_='secureops.auth.errors5m' ORDER BY v.clock DESC,v.ns DESC LIMIT 2
) s
"@ | ForEach-Object { [long]$_ })
    if($securityEvents.Count -ne 4 -or $securityClocks.Count -ne 2){throw 'Exigidos dois ciclos reais anteriores de seguranca e duas amostras validas.'}
    $securityEvents=$securityEvents -join ','; $securityClocks=$securityClocks -join ','
}

function Read-Snapshot {
    return Read-Json @"
SELECT json_build_object(
 'hosts',(SELECT json_agg(json_build_object('id',hostid::text,'name',host,'status',status) ORDER BY hostid) FROM hosts WHERE host IN ('secureops-api','Zabbix server') AND flags=0),
 'scenarios',(SELECT json_agg(json_build_object('id',t.httptestid::text,'name',t.name,'delay',t.delay,'attempts',t.retries,'status',t.status,'auth',t.authentication,'step',s.name,'url',s.url,'timeout',s.timeout,'codes',s.status_codes,'redirects',s.follow_redirects) ORDER BY t.httptestid,s.httpstepid) FROM httptest t JOIN hosts h ON h.hostid=t.hostid JOIN httpstep s ON s.httptestid=t.httptestid WHERE h.host='secureops-api'),
 'triggers',(SELECT json_agg(json_build_object('id',t.triggerid::text,'name',t.description,'expression',t.expression,'type',t.type,'status',t.status,'manual_close',t.manual_close,'recovery_mode',t.recovery_mode) ORDER BY t.triggerid) FROM triggers t WHERE t.triggerid IN (SELECT f.triggerid FROM functions f JOIN items i ON i.itemid=f.itemid JOIN hosts h ON h.hostid=i.hostid WHERE h.host='secureops-api')),
 'dashboard',(SELECT json_agg(json_build_object('id',dashboardid::text,'name',name,'private',private) ORDER BY dashboardid) FROM dashboard WHERE name='SecureOps Lab'),
 'widgets',(SELECT json_agg(json_build_object('id',w.widgetid::text,'type',w.type,'name',w.name,'x',w.x,'y',w.y,'width',w.width,'height',w.height) ORDER BY w.widgetid) FROM dashboard d JOIN dashboard_page p ON p.dashboardid=d.dashboardid JOIN widget w ON w.dashboard_pageid=p.dashboard_pageid WHERE d.name='SecureOps Lab'),
 'widget_filters',(SELECT json_agg(json_build_object('widget',w.widgetid::text,'name',f.name,'type',f.type,'int',f.value_int,'host',f.value_hostid::text,'group',f.value_groupid::text,'item',f.value_itemid::text) ORDER BY w.widgetid,f.name) FROM dashboard d JOIN dashboard_page p ON p.dashboardid=d.dashboardid JOIN widget w ON w.dashboard_pageid=p.dashboard_pageid JOIN widget_field f ON f.widgetid=w.widgetid WHERE d.name='SecureOps Lab' AND (f.name LIKE 'hostids.%' OR f.name LIKE 'groupids.%' OR f.name LIKE 'itemid.%' OR f.name='show')),
 'security_items',(SELECT json_agg(json_build_object('id',i.itemid::text,'key',i.key_,'type',i.type,'status',i.status,'delay',i.delay,'history',i.history,'trends',i.trends,'master',i.master_itemid::text,'url',i.url,'timeout',i.timeout) ORDER BY i.itemid) FROM items i JOIN hosts h ON h.hostid=i.hostid WHERE h.host='secureops-api' AND i.key_ LIKE 'secureops.auth.%'),
 'security_events',(SELECT json_agg(json_build_object('id',e.eventid::text,'clock',e.clock,'value',e.value,'recovery',r.r_eventid::text) ORDER BY e.eventid) FROM events e LEFT JOIN event_recovery r ON r.eventid=e.eventid WHERE e.eventid IN ($securityEvents)),
 'security_history',(SELECT json_agg(json_build_object('clock',v.clock,'ns',v.ns,'value',v.value) ORDER BY v.clock,v.ns) FROM history_uint v JOIN items i ON i.itemid=v.itemid JOIN hosts h ON h.hostid=i.hostid WHERE h.host='secureops-api' AND i.key_='secureops.auth.errors5m' AND v.clock IN ($securityClocks)),
 'retention',(SELECT json_build_object('events_mode',hk_events_mode,'events',hk_events_trigger,'history_mode',hk_history_mode,'history_global',hk_history_global,'history',hk_history,'trends_global',hk_trends_global,'trends',hk_trends) FROM config),
 'accounts',(SELECT json_agg(json_build_object('name',u.username,'group',g.name,'users_status',g.users_status,'gui_access',g.gui_access) ORDER BY u.username,g.name) FROM users u JOIN users_groups ug ON ug.userid=u.userid JOIN usrgrp g ON g.usrgrpid=ug.usrgrpid WHERE u.username IN ('Admin','guest')),
 'events',(SELECT json_agg(json_build_object('id',e.eventid::text,'clock',e.clock,'value',e.value,'recovery',r.r_eventid::text) ORDER BY e.eventid) FROM events e LEFT JOIN event_recovery r ON r.eventid=e.eventid WHERE e.eventid IN ($eventList)),
 'history',(SELECT json_agg(json_build_object('item',i.key_,'clock',v.clock,'ns',v.ns,'value',v.value) ORDER BY v.clock,v.ns) FROM history_uint v JOIN items i ON i.itemid=v.itemid JOIN hosts h ON h.hostid=i.hostid WHERE h.host='secureops-api' AND i.key_='web.test.fail[api-health]' AND v.clock IN ($clockList))
)
"@
}

$baseline = Read-Snapshot
if (@($baseline.dashboard).Count -ne 1 -or $baseline.dashboard[0].private -ne 1 -or @($baseline.widgets).Count -notin @(2,4)) { throw 'Dashboard privado esperado ainda nao comprovado.' }
if ($IncludeCollector -and (@($baseline.widgets).Count -ne 4 -or @($baseline.security_items).Count -ne 3 -or @($baseline.security_events).Count -ne 4 -or @($baseline.security_history).Count -ne 2)) { throw 'Baseline integrado de seguranca incompleto.' }
if ($baseline.retention.events -ne '7d' -or $baseline.retention.history -ne '7d' -or $baseline.retention.history_global -ne 1 -or $baseline.retention.events_mode -ne 1 -or $baseline.retention.history_mode -ne 1) { throw 'Politica de retencao aprovada ainda nao aplicada.' }
if (@($baseline.events).Count -ne 4 -or @($baseline.history).Count -ne 2) { throw 'Baseline de eventos/historico incompleto.' }
$baselineHash = Get-SnapshotHash $baseline
$baselineContainers = @{}
foreach ($name in (@('api','keycloak','oauth2-proxy')+$monitoringServices)) {
    $container = Read-Container $name
    if (-not $container.State.Running) { throw "Servico deve estar ativo antes do ensaio: $name" }
    $baselineContainers[$name] = $container
}
foreach ($name in @('api','zabbix-db','zabbix-web')) {
    if ($baselineContainers[$name].State.Health.Status -ne 'healthy') { throw "Servico deve estar healthy antes do ensaio: $name" }
}
$volume = @($baselineContainers['zabbix-db'].Mounts | Where-Object { $_.Destination -eq '/var/lib/postgresql/data' -and $_.Type -eq 'volume' })
if ($volume.Count -ne 1) { throw 'Volume nomeado esperado nao encontrado.' }
$volumeName = $volume[0].Name
Write-Output "Baseline publico conferido: dashboard privado, politica 7d, eventos e amostras historicas. IncludeCollector=$IncludeCollector; nenhuma credencial lida."
if (-not $RunRestartAndRecreate) {
    Write-Output 'Somente leitura; nenhum servico parado, reiniciado ou recriado.'
    return
}

function Start-Monitoring {
    & docker @compose up -d --no-deps --pull never --wait --wait-timeout 180 zabbix-db
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL nao retomou; preservar volume e diagnosticar.' }
    & docker @compose up -d --no-deps --pull never --wait --wait-timeout 180 zabbix-server zabbix-web
    if ($LASTEXITCODE -ne 0) { throw 'Zabbix nao retomou; preservar dados e diagnosticar.' }
    if($IncludeCollector){
        & docker @compose up -d --no-deps --pull never identity-event-collector
        if($LASTEXITCODE -ne 0){throw 'Coletor nao retomou.'}
    }
}

function Wait-NewSecuritySamples([long] $Since) {
    if(-not $IncludeCollector){return}
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(120)
    do {
        $data=Read-Json @"
SELECT json_build_object('count',count(*),'all_ok',bool_and(s.value=1)) FROM (
 SELECT v.value FROM history_uint v JOIN items i ON i.itemid=v.itemid JOIN hosts h ON h.hostid=i.hostid
 WHERE h.host='secureops-api' AND i.key_='secureops.auth.collection' AND v.clock >= $Since ORDER BY v.clock DESC,v.ns DESC LIMIT 2
) s
"@
        if($data.count -eq 2 -and $data.all_ok){return}
        if([DateTimeOffset]::UtcNow -gt $deadline){throw 'Duas coletas validas novas nao chegaram em 120s.'}
        Start-Sleep -Seconds 3
    }while($true)
}

function Wait-NewSamples([long] $Since) {
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(120)
    do {
        $data = Read-Json @"
SELECT json_build_object('count',count(*),'all_ok',bool_and(s.value=0)) FROM (
 SELECT v.value FROM history_uint v JOIN items i ON i.itemid=v.itemid JOIN hosts h ON h.hostid=i.hostid
 WHERE h.host='secureops-api' AND i.key_='web.test.fail[api-health]' AND v.clock >= $Since ORDER BY v.clock DESC,v.ns DESC LIMIT 2
) s
"@
        if ($data.count -eq 2 -and $data.all_ok) { return }
        if ([DateTimeOffset]::UtcNow -gt $deadline) { throw 'Duas novas amostras saudaveis nao chegaram em 120s apos retomada.' }
        Start-Sleep -Seconds 3
    } while ($true)
}

function Assert-Preservation([string] $Phase, [bool] $Recreated) {
    $current = Read-Snapshot
    if ((Get-SnapshotHash $current) -ne $baselineHash) { throw 'Snapshot publico mudou; investigar sem sobrescrever configuracao ou restaurar dados por cima.' }
    foreach ($name in @('api','keycloak','oauth2-proxy')) {
        $actual = Read-Container $name
        $old = $baselineContainers[$name]
        if (-not $actual.State.Running -or $actual.Id -ne $old.Id -or $actual.State.StartedAt -ne $old.State.StartedAt) { throw "Servico externo ao ensaio foi alterado: $name" }
    }
    foreach ($name in $monitoringServices) {
        $actual = Read-Container $name
        $old = $baselineContainers[$name]
        if (-not $actual.State.Running) { throw "Servico nao retomou: $name" }
        if ($Recreated -eq ($actual.Id -eq $old.Id)) { throw "Identidade do container nao corresponde a fase: $name" }
        if (-not $Recreated -and $actual.State.StartedAt -eq $old.State.StartedAt) { throw "Reinicio nao observado: $name" }
    }
    $currentDb = Read-Container 'zabbix-db'
    $mount = @($currentDb.Mounts | Where-Object { $_.Destination -eq '/var/lib/postgresql/data' -and $_.Type -eq 'volume' })
    if ($mount.Count -ne 1 -or $mount[0].Name -ne $volumeName) { throw 'Volume do banco nao foi preservado.' }
    Write-Output (@{phase=$Phase;result='pass';publicConfigurationAndPriorEventsPreserved=$true;volumePreserved=$true;apiAndIdentityNotRestarted=$true;newHealthySamples=2;collectorIncluded=[bool]$IncludeCollector;newValidSecuritySamples= $(if($IncludeCollector){2}else{0})} | ConvertTo-Json -Compress)
}

$intervened = $false
try {
    foreach ($phase in @('restart','recreate')) {
        $intervened = $true
        & docker @compose stop zabbix-web zabbix-server
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao parar somente frontend/server do monitoramento.' }
        if ($phase -eq 'restart') {
            if($IncludeCollector){& docker @compose restart --no-deps identity-event-collector; if($LASTEXITCODE -ne 0){throw 'Restart do coletor falhou.'}}
            & docker @compose restart --no-deps zabbix-db
            if ($LASTEXITCODE -ne 0) { throw 'Falha no restart do banco; preservar volume.' }
        } else {
            & docker @compose up -d --force-recreate --no-deps --pull never --wait --wait-timeout 180 zabbix-db
            if ($LASTEXITCODE -ne 0) { throw 'Falha ao recriar banco; preservar volume.' }
            & docker @compose up -d --force-recreate --no-deps --pull never --wait --wait-timeout 180 zabbix-server zabbix-web
            if ($LASTEXITCODE -ne 0) { throw 'Falha ao recriar frontend/server; preservar dados.' }
            if($IncludeCollector){& docker @compose up -d --force-recreate --no-deps --pull never identity-event-collector; if($LASTEXITCODE -ne 0){throw 'Recreate do coletor falhou.'}}
        }
        Start-Monitoring
        $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        Wait-NewSamples $since
        Wait-NewSecuritySamples $since
        Assert-Preservation $phase ($phase -eq 'recreate')
        & (Join-Path $PSScriptRoot 'Test-MonitoringAvailability.ps1')
    }
} finally {
    if ($intervened) { Start-Monitoring }
}
Write-Output 'Reinicio e recriacao aprovados, sem remover volumes/dados. Login real apos este ensaio ainda depende da autora.'
