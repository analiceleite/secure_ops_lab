# Cria APENAS segredos novos. Nunca sobrescreve/rotaciona credenciais existentes.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$directory=Join-Path $root '.local/automation'
if(Test-Path -LiteralPath $directory){throw '.local/automation ja existe; preserve os arquivos. Nao e um reset.'}
function New-Secret {
    $bytes=New-Object byte[] 32
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
    return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
}
function Write-New([string]$Name,[string]$Value){
    $stream=[IO.File]::Open((Join-Path $directory $Name),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes($Value);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
}
$null=New-Item -ItemType Directory -Path $directory
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$acl=[Security.AccessControl.DirectorySecurity]::new()
$acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
Set-Acl -LiteralPath $directory -AclObject $acl
foreach($name in @('postgres-bootstrap-password','n8n-db-password','incident-ingest-password','incident-report-password','incident-reader-password','n8n-encryption-key','webhook-key')){Write-New $name (New-Secret)}
$ui=New-Secret;$smtp=New-Secret
Write-New 'mailpit-ui-auth' "operadora:$ui"
Write-New 'mailpit-smtp-auth' "secureops:$smtp"
$null=New-Item -ItemType Directory -Path (Join-Path $directory 'validation-state')
Write-Output 'Segredos exclusivos criados em .local/automation, com ACL restrita; nenhum valor exibido. Identidade/monitoramento preservados.'
