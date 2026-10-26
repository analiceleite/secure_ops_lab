# Entrada interativa local; nunca passar token como argumento ou enviar ao chat.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$path = Join-Path (Split-Path -Parent $PSScriptRoot) '.local/monitoring/zabbix-api-token'
if (Test-Path -LiteralPath $path) { throw 'Arquivo ja existe; nao sobrescrever.' }
if (-not (Get-Acl (Split-Path -Parent $path)).AreAccessRulesProtected) { throw 'Pasta deve ter ACL restrita.' }
$secure = Read-Host 'Cole SOMENTE aqui no terminal local o token temporario do Zabbix (entrada oculta)' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $text = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    if ($text -notmatch '^[a-fA-F0-9]{64}$') { throw 'Formato inesperado; nada salvo.' }
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $stream = [IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
} finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $text=$null; $secure.Dispose() }
Write-Output 'Token salvo apenas na pasta ignorada e restrita. Nao envie o valor ao chat. Revogue-o na UI ao terminar os testes.'
