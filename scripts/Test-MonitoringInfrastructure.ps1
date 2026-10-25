# Valida disponibilidade/infra; nao declara aceite do cenario de seguranca.
[CmdletBinding()]
param([switch] $Runtime)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$baseArgs = @('compose', '-f', (Join-Path $root 'compose.yaml'))
$monitoringArgs = $baseArgs + @('-f', (Join-Path $root 'compose.monitoring.yaml'))
$fullArgs = $baseArgs + @('-f', (Join-Path $root 'compose.identity.yaml'), '-f', (Join-Path $root 'compose.monitoring.yaml'))
$script:checks = 0

function Assert-Check([bool] $Condition, [string] $Name) {
    if (-not $Condition) { throw "monitoring_check_failed: $Name" }
    $script:checks++
    Write-Output "pass: $Name"
}

function Read-Compose([string[]] $Arguments) {
    $json = & docker @Arguments config --format json
    if ($LASTEXITCODE -ne 0) { throw 'Compose invalido; nao continuar.' }
    return ($json | ConvertFrom-Json)
}

function Assert-Networks($Service, [string[]] $Expected, [string] $Name) {
    $actual = @($Service.networks.PSObject.Properties.Name | Sort-Object)
    Assert-Check (@(Compare-Object $actual ($Expected | Sort-Object)).Count -eq 0) $Name
}

$base = Read-Compose $baseArgs
$monitoring = Read-Compose $monitoringArgs
$full = Read-Compose $fullArgs
$api = $base.services.api | ConvertTo-Json -Depth 30 -Compress
Assert-Check (($monitoring.services.api | ConvertTo-Json -Depth 30 -Compress) -eq $api) 'api_unchanged_monitoring'
Assert-Check (($full.services.api | ConvertTo-Json -Depth 30 -Compress) -eq $api) 'api_unchanged_full'
Assert-Check ($monitoring.networks.service.internal -and $monitoring.networks.monitoring.internal -and -not $monitoring.networks.operations.internal) 'network_boundaries'
Assert-Check ($null -eq $monitoring.services.keycloak -and $null -eq $monitoring.services.'oauth2-proxy') 'availability_without_identity'
Assert-Networks $monitoring.services.'zabbix-db' @('monitoring') 'db_networks'
Assert-Networks $monitoring.services.'zabbix-server' @('monitoring', 'service') 'server_networks'
Assert-Networks $monitoring.services.'zabbix-web' @('monitoring', 'operations') 'web_networks'

foreach ($name in @('zabbix-db', 'zabbix-server', 'zabbix-web')) {
    $service = $monitoring.services.$name
    Assert-Check ($service.image -match '@sha256:[a-f0-9]{64}$') "${name}_pinned"
    Assert-Check ($service.user -in @('999:999', '1997:1995') -and $service.cap_drop -contains 'ALL' -and $service.security_opt -contains 'no-new-privileges:true') "${name}_restrictions"
    Assert-Check (-not $service.privileged -and @($service.volumes | Where-Object { $_.source -match 'docker.sock' }).Count -eq 0) "${name}_no_privileged_or_socket"
    if ($name -eq 'zabbix-web') {
        Assert-Check (@($service.ports).Count -eq 1 -and $service.ports[0].host_ip -eq '127.0.0.1' -and $service.ports[0].published -eq '8081' -and $service.ports[0].target -eq 8080) 'web_loopback_only'
    } else {
        Assert-Check ($null -eq $service.ports -or @($service.ports).Count -eq 0) "${name}_no_host_ports"
    }
    Assert-Check ($null -eq $service.environment.POSTGRES_PASSWORD -and $service.environment.POSTGRES_PASSWORD_FILE.StartsWith('/run/secrets/')) "${name}_password_file_only"
}
Assert-Check (@($monitoring.services.'zabbix-server'.secrets).Count -eq 1 -and @($monitoring.services.'zabbix-web'.secrets).Count -eq 1) 'runtime_no_bootstrap_secret'

if ($Runtime) {
    foreach ($name in @('api', 'zabbix-db', 'zabbix-server', 'zabbix-web')) {
        $id = & docker @monitoringArgs ps -q $name
        if (-not $id) { throw "Container ausente: $name" }
        $inspection = & docker inspect $id
        if ($LASTEXITCODE -ne 0) { throw 'Inspecao Docker falhou.' }
        $container = ($inspection | ConvertFrom-Json)[0]
        Assert-Check ($container.State.Running -and -not $container.HostConfig.Privileged -and $container.HostConfig.CapDrop -contains 'ALL' -and $container.HostConfig.SecurityOpt -contains 'no-new-privileges:true') "${name}_runtime_restrictions"
        if ($name -eq 'zabbix-web') {
            $bindings = @($container.HostConfig.PortBindings.'8080/tcp')
            Assert-Check ($bindings.Count -eq 1 -and $bindings[0].HostIp -eq '127.0.0.1' -and $bindings[0].HostPort -eq '8081') 'web_runtime_loopback'
        } else {
            Assert-Check (@($container.HostConfig.PortBindings.PSObject.Properties).Count -eq 0) "${name}_runtime_no_host_ports"
        }
        $actual = @($container.NetworkSettings.Networks.PSObject.Properties.Name | Sort-Object)
        $logicalNetworks = if ($name -eq 'api') { @('service') } elseif ($name -eq 'zabbix-db') { @('monitoring') } elseif ($name -eq 'zabbix-server') { @('monitoring', 'service') } else { @('monitoring', 'operations') }
        $expected = @($logicalNetworks | ForEach-Object { $monitoring.networks.$_.name })
        Assert-Check (@(Compare-Object $actual ($expected | Sort-Object)).Count -eq 0) "${name}_runtime_networks"
        if ($name -eq 'api') {
            Assert-Check ($container.Config.User -eq 'node' -and $container.Mounts.Count -eq 0) 'api_runtime_user_mounts'
        } else {
            Assert-Check ($container.Config.User -eq $monitoring.services.$name.user -and @($container.Mounts | Where-Object { $_.Destination -like '/run/secrets/*' -and $_.RW }).Count -eq 0) "${name}_runtime_user_secrets"
        }
    }
    $role = & docker @monitoringArgs exec -T zabbix-db psql --no-psqlrc -U postgres -d postgres -Atc "SELECT rolsuper,rolcreatedb,rolcreaterole,rolreplication FROM pg_roles WHERE rolname='zabbix'"
    Assert-Check ($LASTEXITCODE -eq 0 -and $role -eq 'f|f|f|f') 'zabbix_database_role_not_superuser'
    $version = & docker @monitoringArgs exec -T zabbix-db psql --no-psqlrc -U postgres -d zabbix -Atc 'SELECT mandatory,optional FROM dbversion'
    Assert-Check ($LASTEXITCODE -eq 0 -and $version -match '^7000000\|700[0-9]+$') 'zabbix_schema_imported'
    $status = & curl.exe --silent --show-error --noproxy '*' --max-time 5 --output NUL --write-out '%{http_code}' http://127.0.0.1:8081/ping
    Assert-Check ($LASTEXITCODE -eq 0 -and $status -eq '200') 'web_ping_200_not_authentication_evidence'
}

Write-Output "monitoring_infrastructure_checks=$script:checks runtime=$Runtime"
