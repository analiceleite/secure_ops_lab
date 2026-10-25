[CmdletBinding()]
param([ValidateRange(1, 120)][int] $TimeoutSeconds = 120)

$ErrorActionPreference = 'Stop'
$issuer = 'http://keycloak.localhost:8080/realms/secureops-lab'
$watch = [Diagnostics.Stopwatch]::StartNew()
# O DNS Windows pode não resolver *.localhost; --resolve vale somente para este curl.
# Não altera hosts/DNS nem substitui o teste com URL canônica no navegador.
while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
    $body = & curl.exe --noproxy '*' --resolve 'keycloak.localhost:8080:127.0.0.1' --max-time 3 --silent --fail "$issuer/.well-known/openid-configuration"
    if ($LASTEXITCODE -eq 0) {
        $discovery = ($body -join "`n") | ConvertFrom-Json
        if ($discovery.issuer -ne $issuer) { throw 'Issuer inesperado no discovery' }
        foreach ($name in @('authorization_endpoint', 'token_endpoint', 'jwks_uri', 'userinfo_endpoint')) {
            $url = [Uri] $discovery.$name
            if ($url.GetLeftPart([UriPartial]::Authority) -ne 'http://keycloak.localhost:8080') {
                throw "Origem inesperada em $name"
            }
        }
        Write-Output "Discovery HTTP 200, issuer/endpoints exatos; espera $($watch.ElapsedMilliseconds) ms. Curl com --resolve, nao DNS do Windows."
        return
    }
    Start-Sleep -Seconds 1
}
throw "Discovery indisponivel dentro de ${TimeoutSeconds}s; verificar estado e logs locais sem exportar segredos."
