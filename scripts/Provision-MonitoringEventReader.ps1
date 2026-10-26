# Administracao separada e efemera; nunca faz parte do runtime do coletor.
[CmdletBinding()]
param([switch] $ApplyLoginErrorOnly,[switch] $VerifyPermissions)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if($ApplyLoginErrorOnly -and $VerifyPermissions){throw 'Escolha somente um modo explicito.'}
$json = & docker compose -f (Join-Path $root 'compose.yaml') -f (Join-Path $root 'compose.identity.yaml') -f (Join-Path $root 'compose.monitoring.yaml') config --format json
if ($LASTEXITCODE -ne 0) { throw 'Compose invalido.' }
$config = $json | ConvertFrom-Json
$extra = @(); $suffix = ',readonly'
if ($ApplyLoginErrorOnly) { $extra += '--apply-login-error-only'; $suffix = '' }
if ($VerifyPermissions) { $extra += '--verify-permissions' }
& docker run --rm --pull never --network $config.networks.identity.name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 256m --mount "type=bind,source=$root/infra/monitoring,target=/checks,readonly" --mount "type=bind,source=$root/.local/identity/keycloak.env,target=/bootstrap/keycloak.env,readonly" --mount "type=bind,source=$root/.local/monitoring,target=/provision$suffix" secureops-api:0.1.0 node /checks/provision-event-reader.mjs @extra
if ($LASTEXITCODE -ne 0) { throw 'Provisionamento/inspecao falhou; preservar estado e diagnosticar, sem repetir aplicacao.' }
