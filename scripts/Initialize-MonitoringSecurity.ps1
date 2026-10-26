# Acrescenta somente dois segredos novos. Nao roda os inicializadores anteriores.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$directory = Join-Path (Split-Path -Parent $PSScriptRoot) '.local/monitoring'
if (-not (Test-Path -LiteralPath $directory)) { throw 'Inicialize primeiro a infraestrutura conforme runbook.' }
foreach ($name in @('collector-client-secret','collector-metrics-secret')) {
    if (Test-Path -LiteralPath (Join-Path $directory $name)) { throw 'Segredo do coletor ja existe; preservar, sem sobrescrever ou rotacionar.' }
}
$acl = Get-Acl -LiteralPath $directory
if (-not $acl.AreAccessRulesProtected) { throw 'ACL de monitoramento deve estar restrita antes da criacao.' }
foreach ($name in @('collector-client-secret','collector-metrics-secret')) {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $content = [Text.Encoding]::UTF8.GetBytes(([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant())
    $stream = [IO.File]::Open((Join-Path $directory $name),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($content,0,$content.Length) } finally { $stream.Dispose() }
}
Write-Output 'Dois segredos exclusivos criados; valores omitidos. Nenhum segredo anterior alterado.'
