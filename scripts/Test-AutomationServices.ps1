[CmdletBinding()]
param([ValidateSet('interfaces','model','smtp','report')][string]$Phase='interfaces',[int]$IncidentId=0)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if($Phase -eq 'report' -and $IncidentId -lt 1){throw 'Use -Phase report -IncidentId com o ID real do incidente.'}
$json=& docker compose -f (Join-Path $root 'compose.yaml') -f (Join-Path $root 'compose.identity.yaml') -f (Join-Path $root 'compose.monitoring.yaml') -f (Join-Path $root 'compose.automation.yaml') --profile automation config --format json
if($LASTEXITCODE -ne 0){throw 'Compose invalido.'}
$c=$json|ConvertFrom-Json
$networks=if($Phase -eq 'model'){@('--network',$c.networks.inference.name)}else{@('--network',$c.networks.automation.name,'--network',$c.networks.mail.name)}
$secrets=if($Phase -eq 'model'){@()}else{@('--mount',"type=bind,src=$root/.local/automation/mailpit-ui-auth,dst=/secrets/mailpit-ui-auth,readonly",'--mount',"type=bind,src=$root/.local/automation/mailpit-smtp-auth,dst=/secrets/mailpit-smtp-auth,readonly")}
& docker run --rm --pull never @networks --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 128m --mount "type=bind,src=$root/infra/automation,dst=/checks,readonly" @secrets secureops-api:0.1.0 node /checks/check-services.mjs $Phase $IncidentId
if($LASTEXITCODE -ne 0){throw "Smoke de infraestrutura falhou:$Phase. Nao comprova entrega integrada; preservar dados e diagnosticar."}
