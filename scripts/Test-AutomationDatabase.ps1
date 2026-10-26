[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$script=Get-Content -Raw -Encoding UTF8 (Join-Path $root 'infra/automation/check-database.sh')
# PowerShell 5.1 acrescenta CRLF ao stdin; normalizar antes de interpretar no Linux.
$script | & docker compose -f (Join-Path $root 'compose.yaml') -f (Join-Path $root 'compose.identity.yaml') -f (Join-Path $root 'compose.monitoring.yaml') -f (Join-Path $root 'compose.automation.yaml') --profile automation exec -T automation-db bash -c "tr -d '\r' | bash -s"
if($LASTEXITCODE -ne 0){throw 'Verificacao de isolamento do banco falhou; preservar estado e diagnosticar.'}
