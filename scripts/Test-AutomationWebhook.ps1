# Gate n8n/PostgreSQL efemero. Nenhum segredo/volume/workflow ativo e montado ou alterado.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$id=[guid]::NewGuid().ToString('N')
$network="secureops-webhook-test-$id";$pg="$network-db";$n8n="$network-n8n"
$directory=Join-Path (Join-Path $env:LOCALAPPDATA 'Temp/opencode') $network
$created=@();$networkCreated=$false
function New-FixtureSecret {return [guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N')}
function Write-FixtureFile([string]$Name,[string[]]$Lines){
    [IO.File]::WriteAllText((Join-Path $directory $Name),($Lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
}
$bootstrap=New-FixtureSecret;$meta=New-FixtureSecret;$ingest=New-FixtureSecret
$header=New-FixtureSecret;$marker='fixture-sensitive-'+$id
$existing=@(& docker ps -a --filter 'label=com.docker.compose.project=secure_ops_lab' --format '{{.ID}}')
if($LASTEXITCODE -ne 0){throw 'Falha ao identificar servicos existentes.'}
$baseline=@(& docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.State.Running}}' @existing)
if($LASTEXITCODE -ne 0){throw 'Falha ao inspecionar estado minimo dos servicos existentes.'}
$json=& docker compose -f (Join-Path $root 'compose.yaml') -f (Join-Path $root 'compose.identity.yaml') -f (Join-Path $root 'compose.monitoring.yaml') -f (Join-Path $root 'compose.automation.yaml') --profile automation config --format json
if($LASTEXITCODE -ne 0){throw 'Compose invalido.'}
$config=$json|ConvertFrom-Json
try{
    $null=New-Item -ItemType Directory -Path $directory
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl=[Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
    Set-Acl -LiteralPath $directory -AclObject $acl
    Write-FixtureFile 'pg.env' @("POSTGRES_PASSWORD=$bootstrap","FIXTURE_META_PASSWORD=$meta","FIXTURE_INGEST_PASSWORD=$ingest",'POSTGRES_INITDB_ARGS=--auth-local=peer --auth-host=scram-sha-256')
    $environment=@{}
    foreach($p in $config.services.n8n.environment.PSObject.Properties){if(-not $p.Name.EndsWith('_FILE')){$environment[$p.Name]=[string]$p.Value}}
    $environment.DB_POSTGRESDB_HOST='fixture-db';$environment.DB_POSTGRESDB_PASSWORD=$meta
    $environment.N8N_ENCRYPTION_KEY=New-FixtureSecret
    $environment.N8N_HOST='fixture-n8n';$environment.N8N_EDITOR_BASE_URL='http://fixture-n8n:5678/'
    $environment.N8N_WEBHOOK_URL='http://fixture-n8n:5678/'
    Write-FixtureFile 'n8n.env' @($environment.Keys|Sort-Object|ForEach-Object {"$_=$($environment[$_])"})
    $null=& docker network create --internal --label "secureops.fixture=$id" $network
    if($LASTEXITCODE -ne 0){throw 'Nao foi possivel criar rede efemera.'};$networkCreated=$true
    $null=& docker create --name $pg --pull never --network $network --network-alias fixture-db --user 999:999 --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 256m --cpus 2 --tmpfs '/var/lib/postgresql/data:uid=999,gid=999,mode=0700,size=256m' --tmpfs '/var/run/postgresql:uid=999,gid=999,mode=0770,size=8m' --tmpfs '/tmp:uid=999,gid=999,mode=1770,size=16m' --mount "type=bind,src=$root/infra/automation,dst=/checks,readonly" --env-file (Join-Path $directory 'pg.env') $config.services.'automation-db'.image postgres -c log_statement=none -c log_min_error_statement=panic
    if($LASTEXITCODE -ne 0){throw 'Fixture PostgreSQL nao criada.'};$created+=$pg
    $null=& docker start $pg
    if($LASTEXITCODE -ne 0){throw 'Fixture PostgreSQL nao iniciou.'}
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(40)
    do{
        $null=& docker exec $pg sh -c 'test $(cat /proc/1/comm) = postgres && pg_isready -U postgres -d postgres' 2>$null
        if($LASTEXITCODE -eq 0){break}
        if([DateTimeOffset]::UtcNow -gt $deadline){throw 'Fixture PostgreSQL sem prontidao.'};Start-Sleep -Milliseconds 300
    }while($true)
    foreach($step in @(@('postgres','/checks/tests/setup-webhook.sql'),@('incidents','/checks/migrations/001-incidents.sql'))){
        $null=& docker exec $pg psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d $step[0] -f $step[1]
        if($LASTEXITCODE -ne 0){throw 'Preparacao SQL da fixture falhou.'}
    }
    $null=& docker create --name $n8n --pull never --network $network --network-alias fixture-n8n --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 512m --cpus 2 --tmpfs '/home/node/.n8n:uid=1000,gid=1000,mode=0700,size=64m' --tmpfs '/home/node/.cache:uid=1000,gid=1000,mode=0700,size=64m' --tmpfs '/tmp:uid=1000,gid=1000,mode=1770,size=64m' --mount "type=bind,src=$root/infra/automation,dst=/checks,readonly" --env-file (Join-Path $directory 'n8n.env') $config.services.n8n.image
    if($LASTEXITCODE -ne 0){throw 'Fixture n8n nao criada.'};$created+=$n8n
    $null=& docker start $n8n
    if($LASTEXITCODE -ne 0){throw 'Fixture n8n nao iniciou.'}
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(180)
    do{
        $null=& docker exec $n8n node -e "fetch('http://127.0.0.1:5678/healthz/readiness').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
        if($LASTEXITCODE -eq 0){break}
        if([DateTimeOffset]::UtcNow -gt $deadline){throw 'Fixture n8n sem prontidao.'};Start-Sleep -Seconds 2
    }while($true)
    $clientConfig=@{bootstrap=$bootstrap;ingest=$ingest;header=$header;marker=$marker}|ConvertTo-Json -Compress
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($clientConfig))
    & docker exec -e "FIXTURE_CONFIG=$encoded" $n8n node /checks/tests/webhook-client.mjs
    if($LASTEXITCODE -ne 0){
        $old=$ErrorActionPreference
        try{$ErrorActionPreference='Continue';$diagnostic=(& docker logs --tail 30 $n8n 2>&1) -join "`n"}finally{$ErrorActionPreference=$old}
        foreach($value in @($bootstrap,$meta,$ingest,$header,$marker)){$diagnostic=$diagnostic.Replace($value,'[REDACTED]')}
        $diagnostic -split "`n"|Where-Object {$_ -match 'workflow|Workflow|webhook|Webhook|node type|Node type'}|Write-Output
        throw 'Gate do receptor isolado falhou; nao publicar workflow ativo.'
    }
    foreach($name in $created){
        $old=$ErrorActionPreference
        try{$ErrorActionPreference='Continue';$logs=(& docker logs $name 2>&1) -join "`n";$exit=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
        if($exit -ne 0){throw 'Nao foi possivel revisar logs da fixture.'}
        foreach($value in @($bootstrap,$meta,$ingest,$header,$marker)){
            if($logs.Contains($value)){throw 'Marcador/segredo ficticio em logs; valor omitido.'}
        }
        $c=((& docker inspect $name)|ConvertFrom-Json)[0]
        if($LASTEXITCODE -ne 0 -or @($c.HostConfig.PortBindings.PSObject.Properties).Count -or (@($c.Mounts)|Where-Object {$_.Type -eq 'volume'})){throw 'Exposicao/volume inesperado na fixture.'}
    }
    $current=@(& docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.State.Running}}' @existing)
    if($LASTEXITCODE -ne 0 -or (Compare-Object $baseline $current)){throw 'Servico existente alterado durante ensaio.'}
    Write-Output "Receptor isolado: rede interna propria, sem portas/volumes persistentes/segredos reais; $($existing.Count) servicos preservados; marcadores ausentes nos logs."
}finally{
    if($existing.Count){
        $current=@(& docker inspect --format '{{.Id}} {{.State.StartedAt}} {{.State.Running}}' @existing)
        if($LASTEXITCODE -eq 0 -and -not (Compare-Object $baseline $current)){
            Write-Output "Servicos existentes preservados (ID/start time/running): $($existing.Count)."
        }else{Write-Warning 'Estado minimo de servico existente divergiu durante ensaio.'}
    }
    [array]::Reverse($created)
    foreach($name in $created){$null=& docker rm -f $name;if($LASTEXITCODE -ne 0){Write-Warning "Fixture propria pendente:$name"}}
    if($networkCreated){$null=& docker network rm $network;if($LASTEXITCODE -ne 0){Write-Warning "Rede propria pendente:$network"}}
    foreach($file in @('pg.env','n8n.env')){if(Test-Path -LiteralPath (Join-Path $directory $file)){Remove-Item -LiteralPath (Join-Path $directory $file)}}
    if(Test-Path -LiteralPath $directory){Remove-Item -LiteralPath $directory} # Somente pasta exclusiva e vazia.
}
