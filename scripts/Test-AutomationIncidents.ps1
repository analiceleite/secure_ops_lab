# Apenas cluster efemero: sem montar volumes/segredos do laboratorio e sem portas.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$image='postgres:17.11-bookworm@sha256:858bb5e98eed02eb8cafbcdc007f9a65d1b613972028944a8ec2133ccaf80d27'
$name='secureops-incident-test-'+[guid]::NewGuid().ToString('N')
$created=$false
$fixturePassword=[guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N')
$existing=@(& docker ps -a --filter 'label=com.docker.compose.project=secure_ops_lab' --format '{{.ID}}')
if($LASTEXITCODE -ne 0){throw 'Nao foi possivel identificar servicos existentes.'}
$baseline=if($existing.Count){@(& docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.State.Running}}' @existing)}else{@()}
if($LASTEXITCODE -ne 0){throw 'Nao foi possivel registrar estado minimo dos servicos.'}
try{
    $null=& docker create --name $name --pull never --network none --user 999:999 --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 256m --cpus 2 --shm-size 32m --tmpfs '/var/lib/postgresql/data:uid=999,gid=999,mode=0700,size=256m' --tmpfs '/var/run/postgresql:uid=999,gid=999,mode=0770,size=8m' --tmpfs '/tmp:uid=999,gid=999,mode=1770,size=16m' --mount "type=bind,src=$root/infra/automation,dst=/checks,readonly" -e "POSTGRES_PASSWORD=$fixturePassword" -e POSTGRES_HOST_AUTH_METHOD=reject -e 'POSTGRES_INITDB_ARGS=--auth-local=peer --auth-host=reject' $image postgres -c listen_addresses= -c max_connections=40 -c log_statement=none -c log_min_error_statement=panic
    if($LASTEXITCODE -ne 0){throw 'Nao foi possivel criar fixture isolada.'}
    $created=$true
    $null=& docker start $name
    if($LASTEXITCODE -ne 0){throw 'Fixture nao iniciou.'}
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(40)
    do{
        $running=& docker inspect $name --format '{{.State.Running}}'
        if($LASTEXITCODE -ne 0 -or $running -ne 'true'){throw 'Fixture encerrou antes de ficar pronta; nao alterar banco ativo.'}
        $null=& docker exec $name sh -c 'test $(cat /proc/1/comm) = postgres && pg_isready -U postgres -d postgres' 2>$null
        if($LASTEXITCODE -eq 0){break}
        if([DateTimeOffset]::UtcNow -gt $deadline){throw 'Fixture sem prontidao em 40s.'}
        Start-Sleep -Milliseconds 300
    }while($true)
    foreach($step in @(@('postgres','/checks/tests/setup.sql'),@('incidents','/checks/migrations/001-incidents.sql'),@('incidents','/checks/tests/incidents.sql'),@('incidents','/checks/migrations/002-report-processing.sql'),@('incidents','/checks/tests/reports.sql'),@('incidents','/checks/migrations/003-prompt-v2.sql'),@('incidents','/checks/tests/prompt-v2.sql'))){
        $priorPreference=$ErrorActionPreference
        try{$ErrorActionPreference='Continue';$output=& docker exec $name psql -X -qAt -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -U postgres -d $step[0] -f $step[1] 2>&1;$sqlExit=$LASTEXITCODE}finally{$ErrorActionPreference=$priorPreference}
        if($sqlExit -ne 0){throw "SQL isolado falhou:$($step[1]); valores omitidos. $($output | Select-Object -Last 12)"}
        $output|Where-Object {"$_" -match '^\{'}|Write-Output
    }
    & docker exec $name bash /checks/tests/concurrency.sh
    if($LASTEXITCODE -ne 0){throw 'Teste de concorrencia isolada falhou.'}
    # Uma migração já aplicada deve falhar/rollback, nunca sobrescrever estado.
    $before=& docker exec $name psql -X -qAt -U postgres -d incidents -c 'SELECT count(*) FROM incident.deliveries'
    $old=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        $null=& docker exec $name psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d incidents -f /checks/migrations/001-incidents.sql 2>&1
        $reapply=$LASTEXITCODE
    }finally{$ErrorActionPreference=$old}
    if($reapply -eq 0){throw 'Migracao reaplicada indevidamente.'}
    $after=& docker exec $name psql -X -qAt -U postgres -d incidents -c 'SELECT count(*) FROM incident.deliveries'
    if($LASTEXITCODE -ne 0 -or $before -ne $after){throw 'Reaplicacao alterou ledger.'}
    Write-Output 'Migration reapply refused; ledger preserved.'
    $json=& docker inspect $name
    if($LASTEXITCODE -ne 0){throw 'Inspecao da fixture falhou.'}
    $c=($json|ConvertFrom-Json)[0]
    if($c.HostConfig.NetworkMode -ne 'none' -or @($c.HostConfig.PortBindings.PSObject.Properties).Count -gt 0 -or $c.Config.User -ne '999:999' -or (@($c.Mounts)|Where-Object {$_.Type -eq 'volume'})){throw 'Fixture nao isolada.'}
    if($existing.Count){
        $current=@(& docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.State.Running}}' @existing)
        if($LASTEXITCODE -ne 0 -or (Compare-Object $baseline $current)){throw 'Estado de servico existente alterado durante ensaio.'}
    }
    Write-Output "Servicos existentes preservados (ID/start time/running): $($existing.Count)."
    Write-Output 'Fixture SQL: network=none, sem portas/volumes persistentes/segredos do laboratorio, UID 999, rootfs read-only; banco ativo nao alterado.'
}finally{
    if($created){
        $null=& docker rm -f $name
        if($LASTEXITCODE -ne 0){Write-Warning "Fixture propria pendente:$name"}
    }
}
