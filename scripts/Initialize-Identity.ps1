# Windows PowerShell 5.1+; não sobrescreve arquivos nem rotaciona segredos existentes.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$local = Join-Path $root '.local'
$directory = Join-Path $local 'identity'
if (Test-Path -LiteralPath $directory) {
    throw 'A pasta .local/identity ja existe. Preserve os segredos; este script nao faz reset/rotacao.'
}

function New-RandomSecret {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($bytes)
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
# Restringir a pasta e os arquivos herdados ao usuário atual ANTES de gravar segredos.
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

$clientSecret = New-RandomSecret
$cookieBytes = [Convert]::FromBase64String((New-RandomSecret))
$bootstrapPassword = New-RandomSecret
Write-NewSecretFile (Join-Path $directory 'keycloak.env') (
    "KC_BOOTSTRAP_ADMIN_USERNAME=lab-bootstrap`nKC_BOOTSTRAP_ADMIN_PASSWORD=$bootstrapPassword`nSECUREOPS_CLIENT_SECRET=$clientSecret`n"
)
Write-NewSecretFile (Join-Path $directory 'client-secret') $clientSecret
# v7.15.5 lê cookie-secret-file como bytes, SEM decodificar base64.
# Criar 32 bytes aleatórios brutos; não abrir esse arquivo binário em editor.
$cookieStream = [IO.File]::Open((Join-Path $directory 'cookie-secret'), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $cookieStream.Write($cookieBytes, 0, $cookieBytes.Length) } finally { $cookieStream.Dispose() }
Write-Output 'Segredos criados em .local/identity com ACL restrita ao usuario atual. Nenhum valor exibido.'
Write-Output 'Preserve a pasta junto do volume. Para o primeiro login administrativo, consulte keycloak.env apenas no editor local.'
