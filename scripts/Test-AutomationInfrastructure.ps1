[CmdletBinding()]
param([switch]$Runtime)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$base=@('compose','-f',(Join-Path $root 'compose.yaml'),'-f',(Join-Path $root 'compose.identity.yaml'),'-f',(Join-Path $root 'compose.monitoring.yaml'),'-f',(Join-Path $root 'compose.automation.yaml'),'--profile','monitoring-security')
$full=$base+@('--profile','automation')
function Read-Config($Arguments){
    $json=& docker @Arguments config --format json
    if($LASTEXITCODE -ne 0){throw 'Compose invalido; nao imprimir configuracao completa.'}
    return $json|ConvertFrom-Json
}
$before=Read-Config $base;$config=Read-Config $full
$checks=0
function Check([string]$Name,[bool]$Ok){if(-not $Ok){throw "check_failed:$Name"};$script:checks++;Write-Output "pass:$Name"}
foreach($name in @('api','keycloak','oauth2-proxy','zabbix-db','zabbix-server','zabbix-web','identity-event-collector')){
    Check "${name}_configuration_preserved" (($before.services.$name|ConvertTo-Json -Depth 100 -Compress) -ceq ($config.services.$name|ConvertTo-Json -Depth 100 -Compress))
}
Check 'zabbix_server_events_network_no_port' ('events' -in $config.services.'zabbix-server'.networks.PSObject.Properties.Name -and -not $config.services.'zabbix-server'.ports)
foreach($name in @('automation','events','inference','mail')){Check "${name}_internal" ($config.networks.$name.internal -eq $true)}
$expected=@{ 'incident-receiver'=@('events','automation');'automation-db'=@('automation');n8n=@('automation','inference','mail','operations');ollama=@('inference');mailpit=@('mail','operations') }
foreach($name in $expected.Keys){
    $s=$config.services.$name
    Check "${name}_profile" ('automation' -in $s.profiles)
    Check "${name}_nonroot_caps" ($s.user -in @('1000:1000','999:999') -and 'ALL' -in $s.cap_drop -and 'no-new-privileges:true' -in $s.security_opt)
    Check "${name}_no_privileged_socket" (-not $s.privileged -and -not (@($s.volumes)|Where-Object { $_.source -match 'docker.sock|identity|monitoring' }))
    Check "${name}_networks" (-not (Compare-Object @($expected[$name]|Sort-Object) @($s.networks.PSObject.Properties.Name|Sort-Object)))
    if($name -in @('incident-receiver','automation-db','ollama')){Check "${name}_no_host_ports" (-not $s.ports)}
    else{
        $port=if($name -eq 'n8n'){5678}else{8025}
        Check "${name}_loopback" (@($s.ports).Count -eq 1 -and $s.ports[0].host_ip -eq '127.0.0.1' -and [int]$s.ports[0].published -eq $port)
        Check "${name}_rootfs_readonly" ($s.read_only -eq $true)
    }
    Check "${name}_memory_bound" ([long]$s.mem_limit -gt 0)
}
$e=$config.services.n8n.environment
Check 'n8n_secret_files_only' ($e.DB_POSTGRESDB_PASSWORD_FILE -eq '/run/secrets/automation-n8n-db' -and -not $e.DB_POSTGRESDB_PASSWORD -and $e.N8N_ENCRYPTION_KEY_FILE -eq '/run/secrets/automation-n8n-key' -and -not $e.N8N_ENCRYPTION_KEY)
Check 'n8n_execution_retention_minimized_not_no_initial_storage' ($e.EXECUTIONS_DATA_SAVE_ON_SUCCESS -eq 'none' -and $e.EXECUTIONS_DATA_SAVE_ON_ERROR -eq 'none' -and $e.EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS -eq 'false' -and $e.EXECUTIONS_DATA_SAVE_ON_PROGRESS -eq 'false')
Check 'n8n_execution_timeout_supports_local_ai' ($e.EXECUTIONS_TIMEOUT -eq '180' -and $e.EXECUTIONS_TIMEOUT_MAX -eq '300')
Check 'receiver_readonly_bounded' ($config.services.'incident-receiver'.read_only -eq $true -and $config.services.'incident-receiver'.cpus -eq 1 -and $config.services.'incident-receiver'.mem_limit -eq 134217728)
$receiverSecrets=@($config.services.'incident-receiver'.secrets|ForEach-Object {$_.source}|Sort-Object)
Check 'receiver_only_ingest_and_webhook_secrets' (-not (Compare-Object @('automation-incident-ingest','automation-webhook-key') $receiverSecrets))
Check 'n8n_no_ingest_or_webhook_secret' (-not(@($config.services.n8n.secrets)|Where-Object {$_.source -in @('automation-incident-ingest','automation-webhook-key')}))
Check 'n8n_cloud_telemetry_disabled' ($e.N8N_DIAGNOSTICS_ENABLED -eq 'false' -and $e.N8N_AI_GATEWAY_ENABLED -eq 'false' -and $e.N8N_TEMPLATES_ENABLED -eq 'false' -and $e.N8N_LICENSE_AUTO_RENEW_ENABLED -eq 'false')
Check 'n8n_community_packages_disabled' ($e.N8N_COMMUNITY_PACKAGES_ENABLED -eq 'false' -and $e.N8N_COMMUNITY_PACKAGES_PREVENT_LOADING -eq 'true' -and $e.N8N_UNVERIFIED_PACKAGES_ENABLED -eq 'false')
$nodes=$e.NODES_INCLUDE|ConvertFrom-Json
Check 'n8n_builtin_allowlist_no_code_or_tools' ($nodes.Count -eq 9 -and -not ($nodes|Where-Object {$_ -match 'code|executeCommand|file|agent|Tool'}))
Check 'ollama_local_bounded' ($config.services.ollama.environment.OLLAMA_NO_CLOUD -eq 'true' -and $config.services.ollama.environment.OLLAMA_NUM_PARALLEL -eq '1' -and $config.services.ollama.read_only -eq $true)
$m=$config.services.mailpit.environment
Check 'mailpit_real_auth_no_accept_any' ($m.MP_UI_AUTH_FILE -and $m.MP_SMTP_AUTH_FILE -and -not $m.MP_SMTP_AUTH_ACCEPT_ANY -and $m.MP_SMTP_RELAY_ALL -eq 'false' -and -not $m.MP_SMTP_RELAY_CONFIG -and -not $m.MP_SMTP_FORWARD_CONFIG)
Check 'mailpit_no_auto_delete' ($m.MP_MAX_MESSAGES -eq '0' -and -not $m.MP_MAX_AGE)
Check 'mailpit_only_fictitious_recipient' ('operadora@lab.invalid' -cmatch $m.MP_SMTP_ALLOWED_RECIPIENTS -and 'other@lab.invalid' -cnotmatch $m.MP_SMTP_ALLOWED_RECIPIENTS)
if($Runtime){
    foreach($name in $expected.Keys){
        $id=& docker @full ps -q $name
        if($LASTEXITCODE -ne 0 -or -not $id){throw "Container ausente:$name"}
        $json=& docker inspect $id
        if($LASTEXITCODE -ne 0){throw 'Inspecao falhou.'}
        $c=($json|ConvertFrom-Json)[0]
        Check "${name}_runtime_running" $c.State.Running
        Check "${name}_runtime_nonroot_caps" ($c.Config.User -in @('1000:1000','999:999') -and 'ALL' -in $c.HostConfig.CapDrop -and 'no-new-privileges:true' -in $c.HostConfig.SecurityOpt -and -not $c.HostConfig.Privileged)
        $networks=@($expected[$name]|ForEach-Object {$config.networks.$_.name}|Sort-Object)
        Check "${name}_runtime_networks" (-not(Compare-Object $networks @($c.NetworkSettings.Networks.PSObject.Properties.Name|Sort-Object)))
        $bindings=@($c.HostConfig.PortBindings.PSObject.Properties|ForEach-Object {$_.Value})
        if($name -in @('incident-receiver','automation-db','ollama')){Check "${name}_runtime_no_host_ports" ($bindings.Count -eq 0)}
        else{Check "${name}_runtime_loopback" ($bindings.Count -eq 1 -and $bindings[0].HostIp -eq '127.0.0.1')}
        Check "${name}_runtime_restrictions" ($c.HostConfig.Memory -eq $config.services.$name.mem_limit -and -not(@($c.Mounts)|Where-Object {$_.Source -match 'docker.sock'}) -and ($name -eq 'automation-db' -or $c.HostConfig.ReadonlyRootfs))
    }
}
Write-Output "Automation infrastructure checks=$checks; Runtime=$Runtime. Nao comprova workflow, IA, SMTP ou persistencia funcional."
