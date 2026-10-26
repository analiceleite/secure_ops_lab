# Testes offline, sem DB, login, portas, segredos ou alteracoes no Zabbix real.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'infra/monitoring'
docker run --rm --pull never --network none --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=bind,source=$source,target=/checks,readonly" secureops-api:0.1.0 node --test /checks/availability-config.test.mjs
if ($LASTEXITCODE -ne 0) { throw 'Testes do contrato de disponibilidade falharam.' }

$name = 'secureops-import-' + [guid]::NewGuid().ToString('N')
$networkCreated = $false
$containerCreated = $false
try {
    $null = & docker network create --internal $name
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar rede de teste exclusiva.' }
    $networkCreated = $true
    $null = & docker run -d --name $name --pull never --network $name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=bind,source=$source,target=/checks,readonly" --entrypoint /usr/sbin/php-fpm85 zabbix/zabbix-web-nginx-pgsql:alpine-7.0.32@sha256:a54ce2e19aaf0a61609e4bbc7ec01c16bef504e6e1c51e3854120ac76d2dbaeb --nodaemonize --fpm-config /checks/php-validation.conf
    # Se run falhar depois de criar o container, o nome exclusivo ainda deve ser limpo.
    $runExit = $LASTEXITCODE
    $owned = & docker container inspect $name --format '{{.Name}}' 2>$null
    $containerCreated = $LASTEXITCODE -eq 0
    if ($runExit -ne 0) { throw 'Falha ao iniciar PHP-FPM de teste.' }
    docker run --rm --pull never --network $name --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=bind,source=$source,target=/checks,readonly" secureops-api:0.1.0 node /checks/validate-via-fastcgi.mjs $name
    if ($LASTEXITCODE -ne 0) { throw 'Schema ou gramatica nao validados pelo PHP-FPM da imagem fixada.' }
} finally {
    if ($containerCreated) {
        $null = & docker container rm -f $name
        if ($LASTEXITCODE -ne 0) { Write-Warning "Container de teste nao removido: $name" }
    }
    if ($networkCreated) {
        $null = & docker network rm $name
        if ($LASTEXITCODE -ne 0) { Write-Warning "Rede de teste nao removida: $name" }
    }
}
Write-Output 'Configuracao validada offline. Este teste nao comprova importacao real ou execucao HTTP; conferir evidencias de runtime separadamente.'
