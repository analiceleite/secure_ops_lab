[CmdletBinding()]
param([switch] $Runtime, [switch] $ExpectFailure)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'apps/identity-event-collector'
if (-not $Runtime) {
    & docker run --rm --pull never --network none --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 256m --mount "type=bind,source=$source,target=/checks,readonly" secureops-api:0.1.0 node --test /checks/collector.test.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Testes isolados do coletor falharam.' }
    & docker run --rm --pull never --network none --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 256m --mount "type=bind,source=$source,target=/checks,readonly" secureops-api-test:0.1.0 /app/node_modules/.bin/tsc --noEmit --strict --target ES2023 --module NodeNext --allowImportingTsExtensions --typeRoots /app/node_modules/@types /checks/collector.ts /checks/main.ts
    if ($LASTEXITCODE -ne 0) { throw 'Checagem TypeScript falhou.' }
    & docker run --rm --pull never --network none --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=bind,source=$root/infra/monitoring,target=/checks,readonly" secureops-api:0.1.0 node --test /checks/security-config.test.mjs /checks/test-target.test.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Contrato de configuracao do Zabbix falhou.' }
    return
}
$json = & docker compose -f (Join-Path $root 'compose.yaml') -f (Join-Path $root 'compose.identity.yaml') -f (Join-Path $root 'compose.monitoring.yaml') --profile monitoring-security config --format json
if ($LASTEXITCODE -ne 0) { throw 'Compose invalido.' }
$config = $json | ConvertFrom-Json
$service = $config.services.'identity-event-collector'
if ($null -ne $service.ports -or $service.user -ne 'node' -or -not $service.read_only -or $service.cap_drop -notcontains 'ALL' -or $service.security_opt -notcontains 'no-new-privileges:true') { throw 'Restricoes do coletor divergentes.' }
$id = & docker compose -f (Join-Path $root 'compose.yaml') -f (Join-Path $root 'compose.identity.yaml') -f (Join-Path $root 'compose.monitoring.yaml') --profile monitoring-security ps -q identity-event-collector
if ($LASTEXITCODE -ne 0 -or -not $id) { throw 'Coletor nao esta ativo.' }
$json = & docker inspect $id
if ($LASTEXITCODE -ne 0) { throw 'Inspecao falhou.' }
$container = ($json | ConvertFrom-Json)[0]
$actualNetworks = @($container.NetworkSettings.Networks.PSObject.Properties.Name | Sort-Object)
$expectedNetworks = @($config.networks.monitoring.name,$config.networks.identity.name | Sort-Object)
if (-not $container.State.Running -or $container.Config.User -ne 'node' -or $container.HostConfig.Privileged -or -not $container.HostConfig.ReadonlyRootfs -or $container.HostConfig.CapDrop -notcontains 'ALL' -or $container.HostConfig.SecurityOpt -notcontains 'no-new-privileges:true' -or @($container.HostConfig.PortBindings.PSObject.Properties).Count -ne 0 -or @(Compare-Object $actualNetworks $expectedNetworks).Count -ne 0) { throw 'Fronteiras reais do coletor divergentes.' }
if ($container.HostConfig.Memory -ne 134217728 -or @($container.Mounts | Where-Object { $_.RW -or $_.Destination -notlike '/run/secrets/collector-*' }).Count -ne 0 -or $container.Mounts.Count -ne 3) { throw 'Mounts/memoria do coletor divergentes.' }
$extra = @()
if ($ExpectFailure) { $extra += '--expect-failure' }
& docker run --rm --pull never --network $config.networks.monitoring.name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=bind,source=$root/infra/monitoring,target=/checks,readonly" --mount "type=bind,source=$root/.local/monitoring/collector-metrics-secret,target=/secrets/collector-metrics-secret,readonly" secureops-api:0.1.0 node /checks/check-collector.mjs @extra
if ($LASTEXITCODE -ne 0) { throw 'Probe autenticado do coletor falhou.' }
Write-Output 'Restricoes reais verificadas: nao root, rootfs read-only, 128 MiB, sem portas/socket e apenas monitoring+identity.'
