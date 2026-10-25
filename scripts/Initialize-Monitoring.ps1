# Windows PowerShell 5.1+; cria somente os segredos novos de monitoramento.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$local = Join-Path $root '.local'
$directory = Join-Path $local 'monitoring'
if (Test-Path -LiteralPath $directory) {
    throw 'A pasta .local/monitoring ja existe. Preserve os segredos; este script nao faz reset/rotacao.'
}

function New-RandomSecret {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}

function Write-NewSecretFile([string] $Path, [string] $Content) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Content)
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
}

if (-not (Test-Path -LiteralPath $local)) { $null = New-Item -ItemType Directory -Path $local }
$null = New-Item -ItemType Directory -Path $directory
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
$acl = [Security.AccessControl.DirectorySecurity]::new()
$acl.SetOwner($sid)
$acl.SetAccessRuleProtection($true, $false)
$rule = [Security.AccessControl.FileSystemAccessRule]::new(
    $sid, [Security.AccessControl.FileSystemRights]::FullControl,
    [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
    [Security.AccessControl.PropagationFlags]::None,
    [Security.AccessControl.AccessControlType]::Allow
)
$acl.AddAccessRule($rule)
Set-Acl -LiteralPath $directory -AclObject $acl

Write-NewSecretFile (Join-Path $directory 'postgres-bootstrap-password') (New-RandomSecret)
Write-NewSecretFile (Join-Path $directory 'zabbix-db-password') (New-RandomSecret)
Write-Output 'Dois segredos criados em .local/monitoring com ACL restrita. Nenhum valor exibido.'
Write-Output 'Preserve a pasta junto do volume. Segredos de identidade existentes nao foram alterados.'
