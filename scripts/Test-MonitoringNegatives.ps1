# Cenarios ficticios no Zabbix real; nunca altera host/cenario principal.
# Cria/remove somente container/host/chave proprios; sem volume persistente/porta no host.
[CmdletBinding()]
param([switch] $VerifyTargetOnly)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$argsCompose=@('compose','-f',(Join-Path $root 'compose.yaml'),'-f',(Join-Path $root 'compose.identity.yaml'),'-f',(Join-Path $root 'compose.monitoring.yaml'))
$json=& docker @argsCompose config --format json
if($LASTEXITCODE -ne 0){throw 'Compose invalido.'}
$config=$json|ConvertFrom-Json
$name='secureops-negative-'+[guid]::NewGuid().ToString('N')
$created=$false
$keyCreated=$false
$keyPath=Join-Path $root ".local/monitoring/validation-state/$name.key"
try {
    if(-not (Get-Acl (Join-Path $root '.local/monitoring')).AreAccessRulesProtected){throw 'Pasta local deve ter ACL restrita.'}
    $bytes=New-Object byte[] 32
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
    $key=[Text.Encoding]::UTF8.GetBytes(([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant())
    $stream=[IO.File]::Open($keyPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $keyCreated=$true
    try{$stream.Write($key,0,$key.Length)}finally{$stream.Dispose()}
    $null=& docker run -d --name $name --pull never --network $config.networks.service.name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=bind,source=$root/infra/monitoring/test-target.mjs,target=/checks/target.mjs,readonly" --mount "type=bind,source=$keyPath,target=/run/secrets/test-target-key,readonly" secureops-api:0.1.0 node /checks/target.mjs
    $runExit=$LASTEXITCODE
    $null=& docker container inspect $name --format '{{.Name}}' 2>$null
    $created=$LASTEXITCODE -eq 0
    if($runExit -ne 0){throw 'Alvo ficticio nao iniciou.'}
    if($VerifyTargetOnly){
        & docker run --rm --pull never --network $config.networks.service.name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=bind,source=$root/infra/monitoring,target=/checks,readonly" --mount "type=bind,source=$keyPath,target=/secrets/test-target-key,readonly" secureops-api:0.1.0 node /checks/check-test-target.mjs $name
    }else{
        & docker run --rm --pull never --network $config.networks.monitoring.name --network $config.networks.service.name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 256m --mount "type=bind,source=$root/infra/monitoring,target=/checks,readonly" --mount "type=bind,source=$root/.local/monitoring/zabbix-api-token,target=/secrets/zabbix-api-token,readonly" --mount "type=bind,source=$keyPath,target=/secrets/test-target-key,readonly" secureops-api:0.1.0 node /checks/test-negatives.mjs $name
    }
    if($LASTEXITCODE -ne 0){throw 'Negativos falharam; revisar resultado sanitizado e cleanup.'}
} finally {
    if($created){
        $null=& docker container rm -f $name
        if($LASTEXITCODE -ne 0){Write-Warning "Container exclusivo pendente: $name"}
    }
    if($keyCreated){[IO.File]::Delete($keyPath)}
}
if($VerifyTargetOnly){Write-Output 'Alvo autenticado validado; container e chave efemera proprios removidos. Nenhuma chamada ao Zabbix.'}
