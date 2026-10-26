# Download administrativo explicito. Runtime de inferencia permanece em rede interna.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$compose=@('compose','-f',(Join-Path $root 'compose.yaml'),'-f',(Join-Path $root 'compose.identity.yaml'),'-f',(Join-Path $root 'compose.monitoring.yaml'),'-f',(Join-Path $root 'compose.automation.yaml'),'--profile','automation')
$json=& docker @compose config --format json
if($LASTEXITCODE -ne 0){throw 'Compose invalido.'}
$config=$json|ConvertFrom-Json
$volume=$config.volumes.'ollama-data'.name
$lock=Get-Content -Raw -Encoding UTF8 (Join-Path $root 'infra/automation/model-lock.json')|ConvertFrom-Json
$exists=@(& docker volume ls --filter "name=^$volume$" --format '{{.Name}}')
if($LASTEXITCODE -ne 0){throw 'Nao foi possivel inspecionar volume do modelo.'}
if($volume -notin $exists){
    $null=& docker volume create --label "com.docker.compose.project=$($config.name)" --label 'com.docker.compose.volume=ollama-data' $volume
    if($LASTEXITCODE -ne 0){throw 'Volume do modelo indisponivel.'}
}
function Verify-Model {
    & docker run --rm --pull never --network none --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=volume,src=$volume,dst=/model,readonly" --mount "type=bind,src=$root/infra/automation,dst=/checks,readonly" secureops-api:0.1.0 node /checks/verify-model.mjs
}
# Antes do primeiro mount pelo Ollama, volume vazio tem dono root, mas e legivel.
Verify-Model
$initial=$LASTEXITCODE
if($initial -eq 0){Write-Output 'Modelo fixado ja instalado e verificado; sem novo download.';return}
if($initial -ne 2){throw 'Modelo existente divergente; nao sobrescrever.'}
$runtime=& docker @compose ps -q ollama
if($LASTEXITCODE -ne 0){throw 'Inspecao de runtime falhou.'}
if($runtime){throw 'Pare somente Ollama antes do download administrativo; nao modificar modelo em uso.'}
$name='secureops-model-loader-'+[guid]::NewGuid().ToString('N')
$created=$false
try{
    # Sem volume anterior, copy-up do diretorio preparado na imagem da permissao ao UID 1000.
    $null=& docker run -d --name $name --pull never --network bridge --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 2g --cpus 4 --tmpfs '/tmp:uid=1000,gid=1000,mode=1770,size=128m' --mount "type=volume,src=$volume,dst=/home/ollama/.ollama" -e OLLAMA_HOST=0.0.0.0:11434 -e OLLAMA_NO_CLOUD=true -e OLLAMA_NOPRUNE=true -e OLLAMA_DEBUG_LOG_REQUESTS=false secureops-ollama:0.1.0 serve
    $runExit=$LASTEXITCODE
    $null=& docker inspect $name --format '{{.Name}}' 2>$null
    $created=$LASTEXITCODE -eq 0
    if($runExit -ne 0 -or -not $created){throw 'Loader nao iniciou.'}
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(30)
    do{
        $null=& docker exec $name ollama list 2>$null
        if($LASTEXITCODE -eq 0){break}
        if([DateTimeOffset]::UtcNow -gt $deadline){throw 'Loader sem prontidao em 30s.'}
        Start-Sleep -Seconds 1
    }while($true)
    $old=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$output=& docker exec $name ollama pull $lock.model 2>&1;$exit=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
    if($exit -ne 0){throw 'Download do modelo falhou; detalhes omitidos e volume preservado para diagnostico/resume.'}
}finally{
    if($created){$null=& docker rm -f $name;if($LASTEXITCODE -ne 0){Write-Warning "Loader proprio pendente: $name"}}
}
Verify-Model
if($LASTEXITCODE -ne 0){throw 'Modelo baixado nao corresponde ao lock; nao iniciar inferencia.'}
Write-Output 'Modelo fixado instalado e verificado; loader proprio removido. Nenhuma porta publicada, prompt ou log enviado para download.'
