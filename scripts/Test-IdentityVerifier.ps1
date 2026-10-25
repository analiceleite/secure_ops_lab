[CmdletBinding()]
param()

# Containers e rede exclusivos desta invocação. Não acessa secrets/volume do lab.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
$network = "secureops-verifier-$suffix"
$issuerContainer = "secureops-verifier-issuer-$suffix"
$gatewayContainer = "secureops-verifier-gateway-$suffix"
$localDir = Join-Path $root ".local\identity-verifier\$suffix"
$configPath = Join-Path $localDir 'proxy.cfg'
$createdNetwork = $false
$createdIssuer = $false
$createdGateway = $false

function Docker-Checked([string[]] $DockerArgs) {
    $output = & docker @DockerArgs
    if ($LASTEXITCODE -ne 0) { throw 'Operacao Docker do verificador falhou; nao repetir sem inspecionar.' }
    return $output
}

try {
    New-Item -ItemType Directory -Path $localDir | Out-Null
    $cfg = Get-Content -Raw -LiteralPath (Join-Path $root 'infra\oauth2-proxy\oauth2-proxy.cfg')
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 32
    $random.GetBytes($bytes)
    $testClientSecret = [Convert]::ToBase64String($bytes)
    $random.GetBytes($bytes)
    # SecretBytes no tag v7.15.5 aceita base64url, não base64 padrão com + e /.
    $testCookieSecret = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $random.Dispose()
    $cfg = $cfg.Replace('http://keycloak.localhost:8080/realms/secureops-lab', 'http://oidc-verifier-issuer:8080/realms/test')
    $cfg = $cfg.Replace('http://app.localhost:4180/oauth2/callback', 'http://oidc-verifier-gateway:4180/oauth2/callback')
    $cfg = $cfg.Replace('http://api:3000/', 'http://oidc-verifier-issuer:8080/')
    $cfg = $cfg.Replace('client_secret_file = "/run/secrets/client-secret"', "client_secret = `"$testClientSecret`"")
    $cfg = $cfg.Replace('cookie_secret_file = "/run/secrets/cookie-secret"', "cookie_secret = `"$testCookieSecret`"")
    [IO.File]::WriteAllText($configPath, $cfg, (New-Object Text.UTF8Encoding $false))
    Docker-Checked @('network', 'create', '--internal', $network) | Out-Null
    $createdNetwork = $true
    Docker-Checked @('run', '-d', '--pull', 'never', '--name', $issuerContainer, '--network', $network,
        '--network-alias', 'oidc-verifier-issuer', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
        '--read-only', '--memory', '128m', '--mount', "type=bind,source=$configPath,target=/checks/proxy.cfg,readonly",
        '--mount', "type=bind,source=$(Join-Path $root 'infra\identity\verify-isolated.mjs'),target=/checks/verify-isolated.mjs,readonly",
        'secureops-api:0.1.0', 'node', '/checks/verify-isolated.mjs') | Out-Null
    $createdIssuer = $true
    # O processo gera RSA antes de escutar; não iniciar discovery do proxy antes disso.
    Docker-Checked @('exec', $issuerContainer, 'node', '/checks/verify-isolated.mjs', '--ready') | Out-Null
    Docker-Checked @('run', '-d', '--pull', 'never', '--name', $gatewayContainer, '--network', $network,
        '--network-alias', 'oidc-verifier-gateway', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
        '--read-only', '--memory', '128m', '--mount', "type=bind,source=$configPath,target=/checks/proxy.cfg,readonly",
        'quay.io/oauth2-proxy/oauth2-proxy:v7.15.5@sha256:8498b0d0ef0a7b29686414000a08aee467f02d0299c9ed1e006a8f33fc017916',
        '--config=/checks/proxy.cfg') | Out-Null
    $createdGateway = $true
    $exitCode = Docker-Checked @('wait', $issuerContainer)
    Docker-Checked @('logs', $issuerContainer)
    if ([int]$exitCode -ne 0) {
        $ErrorActionPreference = 'Continue'
        $gatewayLogs = @(& docker logs $gatewayContainer 2>&1)
        $ErrorActionPreference = 'Stop'
        foreach ($line in $gatewayLogs) {
            $safe = ([string]$line).Replace($testClientSecret, '[REDACTED]').Replace($testCookieSecret, '[REDACTED]')
            $safe = $safe -replace 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', '[TOKEN OMITIDO]'
            Write-Output $safe
        }
        throw 'Verificador isolado reprovou; nao comprova os criterios ate corrigir.'
    }
    Write-Output 'Verificador aprovado. Sem portas, volumes ou alteracoes no gateway principal. Segredos efemeros nao exibidos.'
}
finally {
    # Apenas os recursos criados por esta invocação; nunca remover volumes ou serviços do lab.
    if ($createdGateway) { & docker rm -f $gatewayContainer | Out-Null }
    if ($createdIssuer) { & docker rm -f $issuerContainer | Out-Null }
    if ($createdNetwork) { & docker network rm $network | Out-Null }
    if (Test-Path -LiteralPath $configPath) { Remove-Item -LiteralPath $configPath }
    if (Test-Path -LiteralPath $localDir) { Remove-Item -LiteralPath $localDir }
}
