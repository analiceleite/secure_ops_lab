# PostgreSQL + receptor reais, mas somente dados/segredos/recursos efemeros exclusivos.
[CmdletBinding()]
param([switch]$Build)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if($Build){
    & docker build --pull=false --target test -t secureops-incident-receiver-test:0.1.0 (Join-Path $root 'apps/incident-receiver')
    if($LASTEXITCODE -ne 0){throw 'Build de testes falhou.'}
    & docker run --rm --pull never --network none --read-only --cap-drop ALL --security-opt no-new-privileges:true --memory 128m --cpus 1 secureops-incident-receiver-test:0.1.0
    if($LASTEXITCODE -ne 0){throw 'Testes unitarios falharam.'}
    & docker build --pull=false --target runtime -t secureops-incident-receiver:0.1.0 (Join-Path $root 'apps/incident-receiver')
    if($LASTEXITCODE -ne 0){throw 'Build de runtime falhou.'}
}
$id=[guid]::NewGuid().ToString('N');$network="secureops-receiver-test-$id"
$pg="$network-db";$receiver="$network-http"
$directory=Join-Path (Join-Path $env:LOCALAPPDATA 'Temp/opencode') $network
$created=@();$networkCreated=$false
function New-FixtureSecret {return [guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N')}
$bootstrap=New-FixtureSecret;$meta=New-FixtureSecret;$ingest=New-FixtureSecret;$header=New-FixtureSecret;$marker='fixture-sensitive-'+$id
$existing=@(& docker ps -a --filter 'label=com.docker.compose.project=secure_ops_lab' --format '{{.ID}}')
if($LASTEXITCODE -ne 0){throw 'Falha ao identificar servicos existentes.'}
$baseline=@(& docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.State.Running}}' @existing)
if($LASTEXITCODE -ne 0){throw 'Falha ao registrar estado minimo.'}
$image='postgres:17.11-bookworm@sha256:858bb5e98eed02eb8cafbcdc007f9a65d1b613972028944a8ec2133ccaf80d27'
function Create-Receiver {
    $null=& docker create --name $receiver --pull never --network $network --network-alias fixture-receiver --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --cpus 1 --mount "type=bind,src=$root/infra/automation,dst=/checks,readonly" --mount "type=bind,src=$directory/webhook-key,dst=/run/secrets/automation-webhook-key,readonly" --mount "type=bind,src=$directory/ingest-password,dst=/run/secrets/automation-incident-ingest,readonly" -e INCIDENT_DB_HOST=fixture-db secureops-incident-receiver:0.1.0
    if($LASTEXITCODE -ne 0){throw 'Receptor efemero nao criado.'}
    $script:created+=$receiver
    $null=& docker start $receiver
    if($LASTEXITCODE -ne 0){throw 'Receptor efemero nao iniciou.'}
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(20)
    do{
        $null=& docker exec $receiver node probe.mjs
        if($LASTEXITCODE -eq 0){break}
        if([DateTimeOffset]::UtcNow -gt $deadline){throw 'Receptor sem liveness.'};Start-Sleep -Milliseconds 300
    }while($true)
    $script:receiverDiff=@(& docker diff $receiver)
    if($LASTEXITCODE -ne 0){throw 'Snapshot dos placeholders de mounts falhou.'}
}
function Check-ReceiverLogs {
    $old=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$logs=(& docker logs $receiver 2>&1) -join "`n";$exit=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
    if($exit -ne 0){throw 'Inspecao de logs falhou.'}
    foreach($value in @($header,$ingest,$bootstrap,$marker)){if($logs.Contains($value)){throw 'Segredo/marcador ficticio em logs; valor omitido.'}}
    foreach($line in ($logs -split "`n"|Where-Object {$_})){
        $record=$line|ConvertFrom-Json
        $names=(@($record.PSObject.Properties.Name)|Sort-Object) -join ','
        if($names -ne 'duration_ms,result,status'){throw 'Log do receptor nao categorico.'}
    }
    $currentDiff=@(& docker diff $receiver)
    if($LASTEXITCODE -ne 0 -or (Compare-Object $script:receiverDiff $currentDiff)){throw 'Escrita inesperada no filesystem do receptor.'}
}
try{
    $null=New-Item -ItemType Directory -Path $directory
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User;$acl=[Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
    Set-Acl -LiteralPath $directory -AclObject $acl
    foreach($file in @(@('webhook-key',$header),@('ingest-password',$ingest),@('pg.env',"POSTGRES_PASSWORD=$bootstrap`nFIXTURE_META_PASSWORD=$meta`nFIXTURE_INGEST_PASSWORD=$ingest`nPOSTGRES_INITDB_ARGS=--auth-local=peer --auth-host=scram-sha-256"))){
        [IO.File]::WriteAllText((Join-Path $directory $file[0]),$file[1]+"`n",[Text.UTF8Encoding]::new($false))
    }
    $null=& docker network create --internal --label "secureops.fixture=$id" $network
    if($LASTEXITCODE -ne 0){throw 'Rede efemera nao criada.'};$networkCreated=$true
    $null=& docker create --name $pg --pull never --network $network --network-alias fixture-db --user 999:999 --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 256m --cpus 2 --tmpfs '/var/lib/postgresql/data:uid=999,gid=999,mode=0700,size=256m' --tmpfs '/var/run/postgresql:uid=999,gid=999,mode=0770,size=8m' --tmpfs '/tmp:uid=999,gid=999,mode=1770,size=16m' --mount "type=bind,src=$root/infra/automation,dst=/checks,readonly" --env-file (Join-Path $directory 'pg.env') $image postgres -c log_statement=none -c log_min_error_statement=panic
    if($LASTEXITCODE -ne 0){throw 'PostgreSQL efemero nao criado.'};$created+=$pg
    $null=& docker start $pg
    if($LASTEXITCODE -ne 0){throw 'PostgreSQL efemero nao iniciou.'}
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(40)
    do{
        $null=& docker exec $pg sh -c 'test $(cat /proc/1/comm) = postgres && pg_isready -U postgres -d postgres' 2>$null
        if($LASTEXITCODE -eq 0){break}
        if([DateTimeOffset]::UtcNow -gt $deadline){throw 'PostgreSQL efemero sem prontidao.'};Start-Sleep -Milliseconds 300
    }while($true)
    foreach($step in @(@('postgres','/checks/tests/setup-webhook.sql'),@('incidents','/checks/migrations/001-incidents.sql'))){
        $null=& docker exec $pg psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d $step[0] -f $step[1]
        if($LASTEXITCODE -ne 0){throw 'Preparacao SQL da fixture falhou.'}
    }
    Create-Receiver
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((@{bootstrap=$bootstrap;header=$header;marker=$marker}|ConvertTo-Json -Compress)))
    & docker exec -e "FIXTURE_CONFIG=$encoded" $receiver node /checks/tests/receiver-client.mjs main
    if($LASTEXITCODE -ne 0){throw 'Gate HTTP/PostgreSQL do receptor falhou.'}
    Check-ReceiverLogs
    # Recriar SOMENTE o receptor proprio; banco permanece ativo com os dados da fixture.
    $null=& docker rm -f $receiver
    if($LASTEXITCODE -ne 0){throw 'Receptor proprio nao removido para ensaio de recriacao.'}
    $created=@($created|Where-Object {$_ -ne $receiver})
    Create-Receiver
    & docker exec -e "FIXTURE_CONFIG=$encoded" $receiver node /checks/tests/receiver-client.mjs resume
    if($LASTEXITCODE -ne 0){throw 'Recriacao/deduplicacao falhou.'}
    $null=& docker stop -t 10 $pg
    if($LASTEXITCODE -ne 0){throw 'Parada do banco da fixture falhou.'}
    & docker exec -e "FIXTURE_CONFIG=$encoded" $receiver node /checks/tests/receiver-client.mjs offline
    if($LASTEXITCODE -ne 0){throw 'Banco offline produziu falso sucesso.'}
    Check-ReceiverLogs
    $c=((& docker inspect $receiver)|ConvertFrom-Json)[0]
    if($LASTEXITCODE -ne 0 -or -not $c.HostConfig.ReadonlyRootfs -or $c.Config.User -ne '1000:1000' -or $c.HostConfig.Memory -ne 134217728 -or @($c.HostConfig.PortBindings.PSObject.Properties).Count -or (@($c.Mounts)|Where-Object {$_.Type -eq 'volume'})){throw 'Restricao inesperada no receptor da fixture.'}
    & docker exec $receiver sh -c 'cat /sys/fs/cgroup/memory.peak; cat /sys/fs/cgroup/memory.events'
    if($LASTEXITCODE -ne 0){throw 'Leitura de recursos falhou.'}
    Write-Output 'Gate receptor: HTTP/SQL, recriacao, banco offline, logs categoricos e rootfs sem escrita aprovados. N8n nao participa da ingestao.'
}finally{
    $current=@(& docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.State.Running}}' @existing)
    if($LASTEXITCODE -eq 0 -and -not (Compare-Object $baseline $current)){Write-Output "Servicos existentes preservados: $($existing.Count)."}else{Write-Warning 'Verificar estado dos servicos existentes.'}
    [array]::Reverse($created)
    foreach($name in $created){$null=& docker rm -f $name;if($LASTEXITCODE -ne 0){Write-Warning "Fixture propria pendente:$name"}}
    if($networkCreated){$null=& docker network rm $network;if($LASTEXITCODE -ne 0){Write-Warning "Rede propria pendente:$network"}}
    foreach($file in @('webhook-key','ingest-password','pg.env')){if(Test-Path -LiteralPath (Join-Path $directory $file)){Remove-Item -LiteralPath (Join-Path $directory $file)}}
    if(Test-Path -LiteralPath $directory){Remove-Item -LiteralPath $directory}
}
