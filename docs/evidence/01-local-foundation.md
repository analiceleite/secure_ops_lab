# Evidências — Fundação local

## Estado e escopo

**Coletas:** T01 em 24/10/2026, aproximadamente 22h56; T02 aproximadamente 23h01–23h05, fuso `-03:00`.

**T03:** 24/10/2026, até aproximadamente 23h08 (`-03:00`).

**T04 a T06:** 24/10/2026, aproximadamente 23h11–23h18 (`-03:00`); timestamps de logs em UTC correspondem a 25/10/2026, 02h11–02h18.

T01 cobriu revisão e preparação. T02 criou código e testes da API. T03 criou imagens e Compose e revalidou a suíte. T04/T05 validaram execução, inspeções, parada e recuperação. T06 repetiu o procedimento e fechou a documentação. As seções 1–3, 5 e 6 preservam o histórico das respectivas rodadas; as seções 7–9 registram a validação final. A API foi deixada parada; container, rede e imagens preservados.

Referências: [SPEC](../features/01-local-foundation/SPEC.md) e [PLAN](../features/01-local-foundation/PLAN.md).

## 1. Ambiente observado

Comandos executados na raiz do projeto em PowerShell:

```powershell
docker version
docker compose version
docker info --format '{{.OSType}}'
docker info --format 'CPUs={{.NCPU}} MemoryBytes={{.MemTotal}} LoggingDriver={{.LoggingDriver}}'
docker compose run --help
```

Todos terminaram com sucesso. Resultados relevantes, sem dados de identificação do host:

| Campo | Resultado |
| --- | --- |
| Docker CLI | `28.5.1`, cliente `windows/amd64` |
| Contexto | `desktop-linux` |
| Docker Desktop | `4.48.0` |
| Docker Engine | `28.5.1`, servidor `linux/amd64` |
| Docker Compose | `v2.40.2-desktop.1` |
| Tipo de daemon | `linux` |
| CPUs reportadas pelo daemon | `12` |
| Memória total reportada pelo daemon | `8171761664` bytes, aproximadamente `7,61 GiB` |
| Driver de logs padrão | `json-file` |
| Opções no help local de `compose run` | `--build`, `--rm` e `--no-deps` disponíveis |

A memória é capacidade total reportada ao daemon, não memória livre, consumo do projeto ou requisito mínimo. Espaço disponível e consumo de build/runtime ainda não foram medidos. Não houve instalação, alteração de configuração, reinício ou inspeção de workloads alheios.

## 2. Versões e disponibilidade

Fontes consultadas com sucesso por HTTPS:

- [Índice oficial de releases Node.js](https://nodejs.org/dist/index.json): Node `v24.22.1`, LTS `Krypton`, release de segurança de `20/10/2026`.
- [Variantes mantidas da imagem oficial Node](https://github.com/nodejs/docker-node/blob/main/versions.json): linha 24 com variante `bookworm-slim` e arquitetura `amd64`.
- [Pacote TypeScript 5.9.3 no npm](https://registry.npmjs.org/typescript/5.9.3): versão existente, requisito Node `>=14.17`, sem dependências próprias declaradas.
- [Pacote @types/node 24.19.2 no npm](https://registry.npmjs.org/@types/node/24.19.2): versão existente da linha Node 24; dependências transitivas serão fixadas pelo lockfile.

Também foi consultada a versão mais recente do TypeScript no registro (`7.0.2`). A escolha de `5.9.3` é deliberadamente conservadora para este escopo, não uma alegação de versão mais recente. A instalação e compilação conjuntas ainda não foram executadas.

Comando de inspeção remota, sem download das camadas da imagem:

```powershell
docker manifest inspect node:24.22.1-bookworm-slim
```

Resultado: sucesso, com índice OCI contendo manifesto `linux/amd64`:

```text
sha256:2dd9a4f758e173b65fee15388f7706af6fb01ef50cf7a2c0538711d67a6981ae
```

Esse é o digest do manifesto da plataforma, não o digest do índice multiarch. A consulta comprova a disponibilidade nominal da imagem para a plataforma local, não sua execução. Não houve pull, build ou execução de container. O digest efetivamente usado no build deverá ser conferido na etapa de implementação.

## 3. Revisão e parâmetros operacionais

Não foram identificados bloqueios de escopo ou necessidade de alterar o contrato HTTP. A API permanece sem portas publicadas, sem segredos e sem acesso pelo navegador do host nesta entrega.

Timeouts, health check, encerramento e rotação foram definidos na seção T01 do PLAN. São decisões de implementação, não resultados de testes de comportamento.

Referências de configuração consultadas:

- [Serviços Compose](https://docs.docker.com/reference/compose-file/services/): `healthcheck`, `stop_grace_period`, `logging` e profiles.
- [Redes Compose](https://docs.docker.com/reference/compose-file/networks/): `internal: true` e escopo de nomes.
- [Driver json-file](https://docs.docker.com/engine/logging/drivers/json-file/): `max-size` e `max-file`.

As referências online não substituem `docker compose config --quiet` no YAML real nem testes de runtime na versão instalada.

## 4. Matriz de resultados

| Critério | Estado | Evidência/pendência |
| --- | --- | --- |
| FL-01 | Validado na inspeção inicial | Docker, Compose e daemon Linux acessíveis |
| FL-02 | Validado em T03/T06 | Instalação pelo lockfile, build das imagens e suíte via Compose aprovados |
| FL-03 | Validado via Compose em T03/T06 | 35 testes aprovados, incluindo 27 de contrato/ciclo de vida e 8 do probe |
| FL-04 | Validado em T04/T06 | Health check saudável e probe separado por DNS `api` com sucesso |
| FL-05 | Validado em T04/T06 | Configuração resolvida sem portas; bindings e portas observadas vazios, PublishAllPorts=false |
| FL-06 | Validado em T04/T06 | PID 1 UID/GID 1000, capabilities efetivas zero, NoNewPrivs=1; sem mounts ou modos proibidos |
| FL-07 | Validado em T05/T06 | Dois ciclos positivos/negativos, API parada sem reinício automático e recuperação com probe aprovado |
| FL-08 | Validado em T02/T05/T06 | Logs sanitizados, parada normal <1s; testes de sinais, timeout de encerramento e falha de bind aprovados |
| FL-09 | Validado em T06 | README/runbook repetidos pelo agente, evidências revisadas; reprodução manual da autora não observada |

**Conclusão atual:** T01 a T06 concluídas; Fundação Local concluída. Próxima entrega: especificar Identidade e acesso, quando solicitada. Isso não conclui o laboratório completo nem comprova autenticação, MFA, monitoramento ou incidentes.

## 5. Implementação e testes de T02

### Arquivos e comportamento

- `apps/api/package.json`, lockfile e `tsconfig.json`: pacote privado, versões diretas exatas, sem dependências de produção e compilação estrita.
- `src/server.ts`: fábrica de servidor sem efeitos de inicialização; respostas da SPEC e nenhuma rota administrativa.
- `src/main.ts`: entrypoint em `0.0.0.0:3000`, logs JSON UTC sanitizados, sinais e encerramento com limite de 5 segundos.
- `test/server.test.ts`: sucesso, query strings, recursos inexistentes e métodos não suportados.
- `test/lifecycle.test.ts`: subprocessos para sinais, falha de bind, entrypoint e encerramento forçado de conexão ativa.
- `.gitignore`: exclusão de dependências, artefatos e arquivos de ambiente, antecipada para não incluir arquivos gerados nesta tarefa.

Os testes usam portas efêmeras no loopback do container, exceto o teste do entrypoint real, que usa a porta interna 3000. O conflito de bind ocorre exclusivamente dentro do container de testes, nunca no host. A resposta que não termina é instalada somente pelo subprocesso de teste; a API real não possui mecanismo de simulação acessível por HTTP.

### Comandos executados

Na raiz do repositório, o caminho do mount usado foi a pasta `apps/api`. Forma reproduzível sem caminho pessoal fixo:

```powershell
$apiPath = (Resolve-Path ./apps/api).Path
docker run --rm --user node --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$apiPath,target=/app" --workdir /app --env npm_config_cache=/tmp/npm-cache node:24.22.1-bookworm-slim npm install --package-lock-only --ignore-scripts --no-audit --no-fund
docker run --rm --user node --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$apiPath,target=/app" --workdir /app --env npm_config_cache=/tmp/npm-cache node:24.22.1-bookworm-slim npm ci --ignore-scripts --no-audit --no-fund
docker run --rm --network none --user node --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$apiPath,target=/app" --workdir /app node:24.22.1-bookworm-slim npm test
```

Resultado da instalação: sucesso, 3 pacotes de desenvolvimento, incluindo `undici-types` `7.24.6` transitivo fixado no lockfile. Scripts de instalação desativados. Não foi executada auditoria de vulnerabilidades; nenhum resultado de segurança de dependências é inferido daí.

A instalação exigiu saída para registro npm e download da imagem. Os testes foram executados com `--network none`, sem `-p`, usuário `node`, capabilities removidas e sem socket Docker. O código da API estava acessível apenas pelo mount estreito, não pela raiz do projeto.

Digest da imagem base baixada, conferido com `docker image inspect`:

```text
node@sha256:55fb5f5a527ea2c5c4a95f963e48ef90aa38c7b346054fdc8ee9957a2b55d205
```

Este é o digest do índice usado no pull. Ainda não existe digest de imagem própria da aplicação.

### Resultado da suíte

Uma primeira execução passou em 26 testes. Após adicionar teste do limite de encerramento com conexão ativa, a execução final passou em 27 testes:

```text
build: tsc -p tsconfig.json — sucesso
tests 27
pass 27
fail 0
cancelled 0
skipped 0
todo 0
duration_ms 6062.467422
```

O teste de encerramento com conexão ativa levou aproximadamente 5,14 segundos, incluindo inicialização do subprocesso. A asserção mede o tempo a partir do sinal e exige entre 4,9 e 8 segundos, tolerando escalonamento sem confundir o limite de aplicação com garantia de tempo real. O prazo de 5 segundos permanece fixo no código.

Os testes também comprovaram saída zero no encerramento normal, saída 1 em `EADDRINUSE`, timestamps UTC e allowlist de campos dos logs. `HEAD` recebe `405` com `Allow: GET`, mas sem corpo por semântica HTTP.

### Limites desta validação

- Não valida DNS entre containers, rede `internal`, health check do Docker ou bindings do futuro serviço Compose.
- Não valida usuário, mounts, dependências ou rotação de logs da imagem final, que ainda será construída.
- Sinais foram enviados ao processo filho no container de teste; a parada do container da aplicação será exercitada em T05.
- Os arquivos gerados `node_modules` e `dist` ficaram restritos à pasta da API; os containers temporários terminaram com remoção automática.
- Na rodada T02, a revalidação via Compose estava pendente; foi realizada em T03, abaixo.

## 6. Build e Compose (T03)

### Implementação

- `apps/api/Dockerfile`: estágios `build`, `test` e `runtime`, base Node da SPEC; instalação por `npm ci --ignore-scripts --no-audit --no-fund`. Build e testes como `node`. Runtime copia somente `dist/src`, `package.json` e `scripts/probe.mjs`, sem copiar `node_modules`, testes ou compilador. Ferramentas já presentes na imagem base, como npm, não foram removidas; não se trata de imagem distroless.
- `.dockerignore`: contexto na raiz com lista permitida dos arquivos necessários da API; documentos, dependências locais, `dist`, arquivos de ambiente e logs não são enviados como conteúdo de build. Primeiro contexto observado: aproximadamente `19,16 kB`; transferências posteriores aproveitaram cache.
- `compose.yaml`: API somente na rede `service` interna; sem portas, volumes ou mounts. Capabilities removidas e `no-new-privileges` configurado; sem reinício automático. Saúde, prazo de parada e logs conforme T01.
- `probe` no profile `tools`: usa a imagem local da API, sem build próprio, sem dependência que inicie a API automaticamente; `pull_policy: never` evita tentar obter essa imagem de um registro remoto.
- `api-test` no profile `tools`: estágio `test` em imagem separada, `network_mode: none`, sem mounts. O script npm passou a incluir os testes `.mjs` do probe; não houve nova dependência.
- Probe: destino padrão `http://api:3000/health`; argumento explícito de loopback usado no health check. Exige status `200`, `Content-Type: application/json` e somente `{"status":"ok"}`; não segue redirects. Timeout de 2000 ms abrange leitura do corpo. Saída sanitizada `probe_succeeded`/`probe_failed`, código 0/1.

### Comandos e resultados reais

```powershell
docker compose config --quiet
docker compose --profile tools config --format json
docker compose --profile tools run --build --rm api-test
docker compose build api probe
```

`config --quiet` e a suíte passaram inicialmente. O primeiro `build api probe` falhou na exportação concorrente da mesma tag: `image ... already exists`. A configuração inicial atribuía build idêntico aos dois serviços. Correção: somente `api` constrói o runtime; `probe` reutiliza a imagem. Nenhuma imagem, dado ou volume foi apagado para contornar o erro.

Após a correção, o mesmo comando `build api probe` terminou com código 0 e construiu apenas `api`. O comando recomendado no README passou a ser `docker compose build api`, pois descreve diretamente esse comportamento. A suíte foi executada novamente via Compose com sucesso, não apenas reutilizada como resultado em cache:

```text
tests 35
pass 35
fail 0
cancelled 0
skipped 0
todo 0
duration_ms 6069.334462
```

Exit code do comando de testes: `0`. Os 27 testes de T02 passaram novamente; 8 novos testes verificaram saúde válida, status incorreto, tipo de conteúdo incorreto, JSON inválido, corpo divergente, campos extras, redirect e corpo que não termina. O teste do corpo incompleto levou aproximadamente `2077 ms`, incluindo subprocesso, com falha sanitizada esperada.

A configuração resolvida foi conferida também por asserções PowerShell, não apenas pelo YAML escrito:

```powershell
$config = docker compose --profile tools config --format json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Falha ao resolver Compose' }
foreach ($entry in $config.services.PSObject.Properties) {
  $service = $entry.Value
  if ($service.ports -or $service.volumes -or $service.privileged -or $service.network_mode -eq 'host') {
    throw "Configuracao proibida: $($entry.Name)"
  }
}
if (-not $config.networks.service.internal) { throw 'Rede service nao interna' }
if ($config.services.'api-test'.network_mode -ne 'none') { throw 'Testes com rede' }
docker compose config --quiet
```

Resultado: código 0; `api`, `probe` e `api-test` sem portas, volumes ou modos proibidos; `service` interna e testes sem rede. A configuração resolvida conecta apenas `api` e `probe` à rede de serviço. Isso é validação de configuração, não inspeção de bindings ou conectividade observada do serviço.

### Imagens e estado final

Metadados consultados com `docker image inspect`, selecionando tags, ID, tamanho, usuário e comando. IDs locais finais:

| Imagem | ID local | Tamanho reportado | Usuário configurado |
| --- | --- | --- | --- |
| `secureops-api:0.1.0` | `sha256:9c9cfc17dde8f333bd941348f809185bd5e695bf5a598374cea900eb85bdb902` | `81056044` bytes | `node` |
| `secureops-api-test:0.1.0` | `sha256:7209c4eeac9676e32f9ebc8657bb814a313c821eb58ab474e7a80d122be944ad` | `91890428` bytes | `node` |

Base efetivamente resolvida no build:

```text
node:24.22.1-bookworm-slim@sha256:55fb5f5a527ea2c5c4a95f963e48ef90aa38c7b346054fdc8ee9957a2b55d205
```

Os IDs locais identificam esta rodada, não uma publicação em registro; não houve push. Os tamanhos reportados não representam consumo máximo de disco/cache ou memória. Consumo de runtime ainda não foi medido. A instalação não executou auditoria de vulnerabilidades.

Ao final, `docker compose --profile tools ps --all` mostrou tabela vazia: nenhum container do projeto permaneceu criado ou executando. As imagens e o cache de build foram preservados; não houve limpeza ampla. A API não foi iniciada como serviço, nem houve publicação de porta em qualquer momento.

### Pendências preservadas

- T04: iniciar API, aguardar saúde, consultar DNS `api` de outro container e inspecionar bindings, redes, mounts, usuário efetivo e privilégios.
- T05: parar e recuperar o container real, verificar falha do probe com API parada e logs de encerramento.
- T06: repetir procedimento operacional completo e revisar evidências antes de concluir a entrega.
- O timeout e os caminhos negativos do probe foram testados com fixtures locais no container de testes; isso não comprova o ciclo de indisponibilidade real nem o health check do Docker.

Referência adicional consultada: [Dockerfile](https://docs.docker.com/reference/dockerfile/) para multi-stage, `COPY --from`, `USER` e `CMD` em formato exec. O help local confirmou as opções de `compose run` utilizadas.

## 7. Execução, rede e privilégios (T04)

### Ambiente e comandos

Reconfirmados Docker CLI/Engine `28.5.1`, daemon `linux/amd64` e Compose `v2.40.2-desktop.1`. Não havia containers do projeto antes do início. Nenhuma alteração de configuração do sistema foi necessária.

```powershell
docker compose up -d --wait --wait-timeout 60 api
docker compose --profile tools run --rm --no-deps probe
docker compose ps
```

Todos com saída 0. API chegou a `healthy` em **6694 ms**, incluindo criação da rede/container e início do processo; o prazo de espera era 60 s. O probe separado retornou `{"event":"probe_succeeded"}`, comprovando acesso HTTP pelo DNS `api` na rede do serviço, além do loopback do health check.

### Inspeção observada

Usados `docker inspect` do ID obtido por `docker compose ps -q api`, `docker network inspect` da rede efetivamente conectada e configuração resolvida de todos os serviços. Campos selecionados e asserções PowerShell conferiram:

| Campo | Resultado |
| --- | --- |
| `HostConfig.PortBindings` | `{}` |
| `NetworkSettings.Ports` | `{}` |
| `PublishAllPorts` | `false` |
| Mounts | `[]` |
| `Privileged` | `false` |
| Usuário configurado | `node` |
| `CapDrop` | `["ALL"]` |
| `SecurityOpt` | `["no-new-privileges:true"]` |
| Redes da API | Somente `secure_ops_lab_service`, bridge, `Internal=true` |
| Reinício | `no` |
| Prazo Docker de parada | `10` segundos |
| Logs | `json-file`, `max-size=10m`, `max-file=3` |

A configuração resolvida confirmou ausência de portas publicadas também em `probe` e `api-test`. Não houve rede host, mounts de socket ou volumes. Não se usou um erro de `localhost:3000` como substituto dessa inspeção; nenhum serviço alheio do host foi testado ou interrompido.

Script enviado por stdin ao Node dentro do container leu campos selecionados de `/proc/1/status` e conferiu os caminhos da aplicação:

```text
execUid=1000 execGid=1000
PID 1: Uid=1000/1000/1000/1000 Gid=1000/1000/1000/1000
CapEff=0000000000000000
NoNewPrivs=1
/app/node_modules, /app/test, /app/src, /app/dist/test: ausentes
```

A primeira tentativa com `node -e` falhou por remoção de aspas na passagem de argumentos do PowerShell (`SyntaxError`). O comando foi corrigido usando here-string por stdin, sem alterar imagem, segurança ou aplicação. A forma corrigida está no [runbook](../runbooks/local-foundation.md#2-exposição-redes-e-privilégios) e foi repetida com sucesso em T06.

Saúde observada: checks com exit code 0, saída exclusivamente `{"event":"probe_succeeded"}` e durações de aproximadamente `244,6` a `268,5 ms`, abaixo do limite de 3 s. Log da aplicação continha apenas inicialização JSON UTC, sem dados de requisição.

Snapshot `docker stats --no-stream`: CPU `0,00%`, memória `18,68 MiB / 7,611 GiB`, 7 PIDs. Na repetição: `19,16 MiB`, CPU `17,57%` e 7 PIDs. São amostras pontuais, podendo incluir atividade de health check; não representam pico, benchmark nem requisito mínimo. Rotação foi validada pela configuração efetiva do container, não por forçar o preenchimento dos arquivos de log.

## 8. Indisponibilidade e recuperação (T05)

1. `docker compose stop api`: saída 0, **718 ms** medidos no comando completo. Estado `exited`, exit code 0, `RestartCount=0`.
2. `docker compose --profile tools run --rm --no-deps probe`: `probe_failed`, saída **1**, **1472 ms** totais incluindo criação/remoção do auxiliar. Não iniciou a API.
3. Após o probe e mais **12 s** de observação, a API continuava parada, com `RestartCount=0` e política `no`.
4. `docker compose start api`: saída 0. Consulta periódica da saúde, limitada a 60 s, chegou a `healthy` em **5286 ms** de espera.
5. Probe repetido: `probe_succeeded`, saída 0.

`compose start --help` confirmou que a versão local não fornece espera por saúde nesse comando; por isso foi usada consulta explícita. Forma da espera executada após `start`, sem modificar o container:

```powershell
$apiId = docker compose ps -q api
$timer = [System.Diagnostics.Stopwatch]::StartNew()
do {
  $health = docker inspect --format '{{.State.Health.Status}}' $apiId
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar saude' }
  if ($health -eq 'healthy') { break }
  if ($timer.Elapsed.TotalSeconds -ge 60) { throw 'Saude nao atingida em 60s' }
  Start-Sleep -Seconds 1
} while ($true)
```

Trecho sanitizado da primeira rodada, timestamps UTC:

```json
{"timestamp":"2026-10-25T02:11:03.821Z","event":"startup_completed","port":3000}
{"timestamp":"2026-10-25T02:12:10.127Z","event":"shutdown_started","signal":"SIGTERM"}
{"timestamp":"2026-10-25T02:12:10.127Z","event":"shutdown_completed"}
{"timestamp":"2026-10-25T02:12:40.810Z","event":"startup_completed","port":3000}
```

O encerramento foi normal, sem SIGKILL. O limite de 5 s para conexões ativas e a falha de inicialização por conflito de bind são comprovados pelos testes automatizados, não por esse caso de parada sem carga. O tempo de 2 s do probe vale para HTTP completo; não é garantia sobre a duração de `compose run`. O teste com API parada falhou antes desse limite; o teste de corpo incompleto da suíte comprova o abort após aproximadamente 2 s.

## 9. Repetição e fechamento (T06)

README atualizado e runbook operacional criado; depois foram repetidos os comandos documentados de config, testes, build, início com espera, probe, inspeções, logs, parada, probe negativo e recuperação. Os comandos foram conferidos por exit code; o único código 1 esperado nessa sequência é do probe enquanto a API está parada.

Suíte final real:

```text
tests 35
pass 35
fail 0
cancelled 0
skipped 0
todo 0
duration_ms 5865.097699
```

Build repetido com cache, sem reinstalação fria nem alegação de reprodução em outra máquina. O container de testes voltou a compilar e executar a suíte de fato. Na repetição, o build gerou nova identificação local de imagem, e Compose recriou somente a API. Isso não envolveu volume ou dados persistentes. No ciclo seguinte, sem novo build, a recuperação com `up -d --wait --wait-timeout 60 api` reutilizou o mesmo container; foi feita comparação dos IDs antes e depois.

Segundo ciclo: parada medida em **757 ms**, probe negativo com código 1, recuperação saudável e probe com código 0. Uma parada final deixou a API em **`exited`/0, `RestartCount=0`**. `compose --profile tools ps --all` mostrou somente a API parada, sem auxiliares permanentes.

Logs finais sanitizados:

```json
{"timestamp":"2026-10-25T02:14:17.624Z","event":"startup_completed","port":3000}
{"timestamp":"2026-10-25T02:14:58.005Z","event":"shutdown_started","signal":"SIGTERM"}
{"timestamp":"2026-10-25T02:14:58.006Z","event":"shutdown_completed"}
{"timestamp":"2026-10-25T02:15:01.742Z","event":"startup_completed","port":3000}
{"timestamp":"2026-10-25T02:15:10.299Z","event":"shutdown_started","signal":"SIGTERM"}
{"timestamp":"2026-10-25T02:15:10.300Z","event":"shutdown_completed"}
```

Identificações locais finais após rebuild:

```text
secureops-api:0.1.0      sha256:fdc37c8c75fc64b81c53bcd86faa06d0e90bebcb38fc1890f3a3d79b5e772d63
secureops-api-test:0.1.0 sha256:0e0c59d8cddb31b747c15ccb864b1a3a30b1b9bcb7232641ef3f557bfb19fe3c
```

Base Node resolvida permaneceu no digest registrado em T03. IDs locais/atestados podem mudar com rebuild; não houve publicação em registro.

### Revisão e limites finais

- Revisados 21 arquivos autorais e evidências, excluindo `node_modules`/`dist`; nenhum arquivo `.env` autoral encontrado. Busca por formatos de chaves privadas, tokens GitHub, access keys AWS e JWTs não encontrou correspondências. Essa busca é limitada, não um detector infalível de segredos; fixtures usam apenas valores fictícios.
- Verificação final às 23h18 (`-03:00`): 25 destinos de links locais existentes, sem validação automática de âncoras; `docker compose config --quiet` aprovado e API ainda parada.
- As 6 linhas de logs finais passaram por verificação de evento, timestamp UTC e allowlist de campos; health check contém apenas evento sanitizado. Sem dumps de variáveis de ambiente nas evidências.
- Sem novas dependências, portas, mounts ou alteração de código de runtime/Compose nesta rodada. Somente documentação e execução dos testes previstos. Nenhum volume ou dado alheio removido; imagens, rede e container parado preservados. Não executados prune, `down -v` ou limpeza ampla.
- Procedimento repetido pelo agente no ambiente local, não pela autora nem em uma máquina limpa. Explicação para reprodução/entrevista está no runbook.
- HTTP interno não é cifrado; host e Docker fazem parte da base de confiança. Rede interna e ausência de bindings não comprovam firewall completo ou isolamento absoluto. Não se testou egress contra sistemas externos.
- Autenticação, MFA, gateway, monitoramento independente, persistência/deduplicação de incidentes e navegador não fazem parte desta entrega e não foram testados.
- Auditoria de vulnerabilidades, pico de consumo de build e mínimo de disco/memória não foram medidos. Nenhum desses resultados é inferido de testes bem-sucedidos.

**Fechamento:** FL-01 a FL-09 atendidos no escopo da SPEC 01. Fundação Local concluída; demais entregas permanecem não iniciadas.
