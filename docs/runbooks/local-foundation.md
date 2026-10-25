# Runbook — Fundação Local

Escopo: somente a API fictícia da entrega 01. Executar PowerShell na raiz do projeto, com Docker Linux e Compose V2. Não exige Node no host, `.env`, contas ou segredos. Build/testes e ciclo de parada estão no [README](../../README.md#execução).

## 1. Saúde e diagnóstico

```powershell
docker compose up -d --wait --wait-timeout 60 api
docker compose ps
docker compose --profile tools run --rm --no-deps probe
docker compose logs --no-color api
```

Esperado: API `healthy`, probe com código 0 e evento `probe_succeeded`; logs JSON UTC com inicialização. Se falhar, interrompa a sequência e confira logs/estado. Não publique a porta da API para depurar e não altere serviços alheios. O probe exige status e corpo corretos; o health check usa loopback, enquanto o probe separado usa DNS `api` na rede interna.

## 2. Exposição, redes e privilégios

Com a API executando:

```powershell
$apiId = docker compose ps -q api
if (-not $apiId) { throw 'API nao esta em execucao' }
docker inspect --format 'Bindings={{json .HostConfig.PortBindings}} Ports={{json .NetworkSettings.Ports}} PublishAll={{.HostConfig.PublishAllPorts}}' $apiId
docker inspect --format 'User={{.Config.User}} Privileged={{.HostConfig.Privileged}} Mounts={{json .Mounts}} CapDrop={{json .HostConfig.CapDrop}} SecurityOpt={{json .HostConfig.SecurityOpt}}' $apiId
$network = docker inspect --format '{{range $name, $value := .NetworkSettings.Networks}}{{$name}}{{end}}' $apiId
docker network inspect --format 'Driver={{.Driver}} Internal={{.Internal}}' $network
docker inspect --format 'Restart={{.HostConfig.RestartPolicy.Name}} StopTimeout={{.Config.StopTimeout}} Logging={{json .HostConfig.LogConfig}}' $apiId
docker compose --profile tools config --format json
```

Esperado: bindings/ports vazios (`{}` ou `null`), `PublishAll=false`, usuário `node`, sem mounts, `Privileged=false`, `CapDrop=["ALL"]`, `no-new-privileges:true`. A API deve estar em **uma única rede**, a rede de serviço do projeto, bridge e `Internal=true`. A configuração resolvida também deve estar sem `ports` em todos os serviços. `Restart=no`, prazo de parada 10 segundos e logs `json-file` com `10m`/`3`.

O comando de rede acima presume a topologia atual com uma rede; se a topologia for alterada, inspecione cada rede explicitamente. Não use dumps completos de ambiente/configuração como evidência de futuras etapas com segredos; selecione e sanitize os campos.

Para conferir o processo real, enviar o script por stdin evita problemas de aspas do PowerShell com `node -e`:

```powershell
@'
import { readFileSync, existsSync } from 'node:fs';
const status = readFileSync('/proc/1/status', 'utf8').split('\n')
  .filter(line => /^(Name|Uid|Gid|CapEff|NoNewPrivs):/.test(line));
console.log(JSON.stringify({ execUid: process.getuid(), execGid: process.getgid(),
  pid1: status, appNodeModules: existsSync('/app/node_modules'),
  appTests: existsSync('/app/test'), appSources: existsSync('/app/src'),
  compiledTests: existsSync('/app/dist/test') }));
'@ | docker compose exec -T api node --input-type=module
```

Esperado: UID/GID 1000 no processo inspecionado e em PID 1, capabilities efetivas zero, `NoNewPrivs=1`, caminhos de desenvolvimento ausentes. Isso complementa `USER node` do Dockerfile, que sozinho é apenas configuração.

## 3. Saúde, recursos e logs sanitizados

```powershell
docker inspect --format '{{json .State.Health}}' $apiId
docker stats --no-stream --format 'CPU={{.CPUPerc}} Memory={{.MemUsage}} PIDs={{.PIDs}}' $apiId
docker compose logs --no-color --no-log-prefix api
```

Esperado: saúde `healthy`, checks com código 0 e somente `{"event":"probe_succeeded"}`. Logs da API: eventos de inicialização/encerramento, timestamp UTC, porta ou sinal quando pertinente; nenhum header, corpo, token ou stack trace. Um snapshot de recursos não é benchmark nem dimensionamento mínimo. A rotação foi conferida como configuração do daemon para o container, não por gerar 30 MB de logs.

## 4. Parada e recuperação

Use o ciclo do README. Durante a parada, confira:

```powershell
$apiId = docker compose ps --all -q api
docker inspect --format 'Status={{.State.Status}} ExitCode={{.State.ExitCode}} RestartCount={{.RestartCount}}' $apiId
```

Esperado após parada normal: `exited`, código 0, nenhum reinício automático e logs `shutdown_started` (`SIGTERM`) → `shutdown_completed`. O probe deve falhar sem iniciar a API. Retomar com `up --wait` deve restaurar saúde e sucesso do probe. Não confundir erro esperado desse cenário com uma falha na instalação.

Para apenas encerrar o laboratório: `docker compose stop api`. Não usar prune, `down -v`, remoção de volumes ou exclusão ampla. Diagnosticar/corrigir apenas os arquivos e serviços envolvidos, preservando dados da autora.

## 5. O que explicar em entrevista

- “Health check local prova que o processo responde; o probe separado prova DNS e acesso pela rede de serviço.”
- “Inspecionei configuração resolvida e bindings do container, não apenas a coluna PORTS.”
- “Parar a API provoca falha do probe; a recuperação manual restaura a resposta. Ainda não há monitor ou automação de incidentes.”
- “A API não tem autenticação nesta entrega. HTTP interno não é cifrado; host e Docker são confiáveis. Não é isolamento absoluto nem ZTNA completo.”

Evidências e resultados: [Fundação Local](../evidence/01-local-foundation.md). A reprodução pela autora não foi observada; o procedimento foi repetido pelo agente no ambiente local.
