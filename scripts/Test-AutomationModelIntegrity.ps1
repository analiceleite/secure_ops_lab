[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
& docker run --rm --pull never --network none --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --tmpfs '/tmp:uid=1000,gid=1000,mode=1770,size=16m' --mount "type=bind,src=$root/infra/automation,dst=/checks,readonly" secureops-api:0.1.0 node --test /checks/verify-model.test.mjs
if($LASTEXITCODE -ne 0){throw 'Testes isolados de integridade falharam.'}
