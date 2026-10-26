# Aplica migrações aditivas ao banco ativo sob autorização explícita para o ensaio ponta a ponta.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][switch]$EndToEndTestAuthorized)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$db='secure_ops_lab-automation-db-1'
if(-not $EndToEndTestAuthorized){throw 'Gate bloqueado: use -EndToEndTestAuthorized somente com autorização explícita para instalar o schema do ensaio.'}
$running=& docker inspect $db --format '{{.State.Running}}'
if($LASTEXITCODE -ne 0 -or $running -ne 'true'){throw 'automation-db não está em execução; nenhum dado alterado.'}
$state=& docker exec $db psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d incidents -c "SELECT current_database()||'|'||coalesce(to_regclass('incident.schema_version')::text,'absent')"
if($LASTEXITCODE -ne 0 -or $state -ne 'incidents|absent'){throw 'Estado do schema inesperado; não reaplicar nem sobrescrever.'}

function Invoke-Migration([string]$path){
    $containerPath='/tmp/secureops-migration-'+[guid]::NewGuid().ToString('N')+'.sql'
    $copied=$false
    try{
        & docker cp $path "${db}:$containerPath" | Out-Null
        if($LASTEXITCODE -ne 0){throw 'Não foi possível preparar o arquivo SQL; banco não alterado.'}
        $copied=$true
        $old=$ErrorActionPreference
        try{$ErrorActionPreference='Continue';$output=& docker exec $db psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d incidents -f $containerPath 2>&1;$code=$LASTEXITCODE}
        finally{$ErrorActionPreference=$old}
        if($code -ne 0){throw "Migração falhou; valores omitidos. $($output|Select-Object -Last 5)"}
    }finally{
        if($copied){$null=& docker exec --user 0 $db rm -f -- $containerPath;if($LASTEXITCODE -ne 0){Write-Warning 'Arquivo temporário SQL próprio permaneceu no container; nenhum dado/volume foi removido.'}}
    }
}

Invoke-Migration (Join-Path $root 'infra/automation/migrations/001-incidents.sql')
$provision="INSERT INTO incident.allowed_conditions(source_instance,trigger_id,condition,category) VALUES ('secureops-lab-zabbix','25229','api-http','availability'),('secureops-lab-zabbix','25230','api-http-nodata','collection'),('secureops-lab-zabbix','25231','auth-threshold','authentication'),('secureops-lab-zabbix','25232','auth-collection','collection');"
$null=& docker exec $db psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d incidents -c $provision
if($LASTEXITCODE -ne 0){throw 'Allowlist não foi provisionada; não execute novamente sem inspecionar estado.'}
Invoke-Migration (Join-Path $root 'infra/automation/migrations/002-report-processing.sql')
Invoke-Migration (Join-Path $root 'infra/automation/migrations/003-prompt-v2.sql')
$check=& docker exec $db psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d incidents -c "SELECT (SELECT string_agg(version::text,',' ORDER BY version) FROM incident.schema_version)||'|'||(SELECT count(*) FROM incident.allowed_conditions WHERE source_instance='secureops-lab-zabbix')"
if($LASTEXITCODE -ne 0 -or $check -ne '1,2,3|4'){throw 'Verificação pós-migração falhou; preservar o banco e diagnosticar sem rollback destrutivo.'}
Write-Output 'Schema 1/2/3 e quatro condições allowlisted instalados. Nenhum evento de produção foi fabricado.'
