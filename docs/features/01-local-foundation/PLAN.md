# PLAN 01 — Fundação local

**Estado:** T01 a T06 concluídas em 24/10/2026 (fuso `-03:00`). Fundação Local concluída, com FL-01 a FL-09 verificados. Suíte final: 35 testes aprovados; execução, inspeções e dois ciclos de parada/recuperação aprovados. API deixada parada, sem remoção de rede ou dados.

Referência de comportamento e aceite: [SPEC.md](SPEC.md). Alterações de contrato ou segurança devem ser revisadas na SPEC, não escondidas como ajustes deste plano.

## 1. Forma de execução

- Executar uma tarefa por vez, validando seu resultado antes de avançar.
- Não implementar identidade, monitoramento ou automação junto com esta entrega.
- Usar PowerShell no host e registrar comandos reproduzíveis a partir da raiz do projeto.
- Manter tarefas e critérios pendentes quando ferramentas ou validações estiverem indisponíveis.
- T01 a T06 têm resultados registrados nas evidências. Diferenciar os registros históricos de cada rodada do estado final da entrega.

## 2. Estrutura prevista

```text
compose.yaml
.gitignore
.dockerignore
apps/api/
  package.json
  package-lock.json
  tsconfig.json
  Dockerfile
  src/
    server.ts
    main.ts
  test/
    server.test.ts
  scripts/
    probe.mjs
docs/evidence/01-local-foundation.md
```

O contexto de build proposto é a raiz, para que o `.dockerignore` tenha efeito. O Dockerfile fica em `apps/api/`. Separar criação do servidor de inicialização facilita testes sem processos órfãos. O script de probe deve falhar com código não zero se a resposta, o status ou o timeout não atenderem ao contrato.

## 3. Tarefas

### T01 — Conferir ambiente e decisões

- [x] Revisar SPEC e registrar eventuais dúvidas antes de implementar.
- [x] Executar `docker version`, `docker compose version` e `docker info --format '{{.OSType}}'`.
- [x] Registrar versões e confirmar daemon Linux acessível.
- [x] Conferir documentação oficial e fixar versões da imagem Node, TypeScript e tipos; documentar a escolha.
- [x] Definir health check e timeout do probe com limite finito.
- [x] Definir prazo de encerramento da aplicação e período de parada maior no Compose.
- [x] Definir rotação de logs com limites explícitos.

**Validação:** pré-requisitos atendidos e escolhas registradas. Se Docker estiver ausente ou inacessível, registrar bloqueio; não instalar, reiniciar ou reconfigurar o sistema sem autorização.

**Resultado:** Docker Engine `28.5.1`, Docker Desktop `4.48.0`, Compose `v2.40.2-desktop.1` e daemon `linux/amd64` acessíveis. Revisão sem alterações do contrato ou de escopo. Consultas de metadados e manifesto confirmaram as versões escolhidas, sem download das camadas ou execução da imagem. Ver [evidências de T01](../../evidence/01-local-foundation.md).

#### Parâmetros definidos para T02/T03

| Parâmetro | Valor | Motivo |
| --- | --- | --- |
| Timeout do probe HTTP | `2000 ms` | Limitar a operação completa, incluindo leitura do corpo; não apenas conexão |
| Health check: destino | `http://127.0.0.1:3000/health` | Validar o processo dentro do próprio container |
| Health check: interval | `10s` | Verificação frequente, suficiente para o laboratório |
| Health check: timeout | `3s` | Maior que o timeout HTTP do probe; execução real ainda precisa ser medida |
| Health check: retries | `3` | Evitar marcar falha por uma única tentativa |
| Health check: start_period | `5s` | Tolerar a inicialização inicial sem prometer prontidão imediata |
| Espera de validação por saúde | Até `60s` após início do serviço | Falhar a validação com diagnóstico se a saúde não chegar |
| Encerramento da aplicação | Limite de `5s` após sinal | Fechar conexões e impedir espera indefinida |
| Compose: stop_grace_period | `10s` | Dar margem antes da interrupção forçada pelo Docker |
| Política de reinício | `restart: "no"` | Preservar a falha manual da API |
| Logs por container | Driver `json-file`, `max-size: "10m"`, `max-file: "3"` | Rotação local explícita, sem alterar o daemon global |

O prazo de 2 segundos cobre a requisição do probe, não o tempo que o Docker leva para criar o container auxiliar. Os valores acima são escolhas para implementação; sua eficácia será testada em T04/T05. O probe de rede usa `http://api:3000/health`, distinto do loopback usado pelo health check.

Versões da API e justificativa ficam na SPEC para evitar definições duplicadas. A revisão de documentação confirmou `internal`, `healthcheck`, `stop_grace_period`, `logging` e profiles; o help local confirmou `run --build`, `--rm` e `--no-deps`. A aceitação do futuro YAML pelo Compose permanece uma validação de T03.

### T02 — Criar API e testes do contrato

- [x] Criar pacote npm, lockfile, configuração TypeScript e scripts de build/teste.
- [x] Implementar o contrato HTTP sem framework, banco ou segredos.
- [x] Separar criação do servidor e entrypoint do processo.
- [x] Adicionar testes automatizados de `200`, JSON, headers, `404`, `405` e query string.
- [x] Testar em porta efêmera dentro do processo de teste e fechar todos os servidores ao terminar.
- [x] Implementar logs mínimos, encerramento com prazo e saída não zero em falha de inicialização.
- [x] Testar falha de inicialização por conflito de bind apenas dentro de um ambiente de teste isolado, sem disputar portas do host.

**Validação:** compilação e testes aprovados pelo caminho em container criado em T03. Não marcar T02 concluída só porque o código foi escrito.

**Resultado intermediário:** implementação e compilação verificadas em container temporário da imagem Node definida na SPEC, sem portas publicadas, como usuário `node` e com `--network none` durante os testes. Foram aprovados 27 testes, incluindo `SIGTERM`, `SIGINT`, conflito de bind e conexão ativa interrompida após o limite de 5 segundos. O encerramento forçado é provocado apenas pelo fixture do teste, não por uma rota da API.

**Adaptação de execução em T02:** foi usado `docker run --rm` com bind mount restrito a `apps/api`. Essa validação intermediária não substituía Compose. **Fechamento em T03:** os 27 testes originais passaram novamente pelo serviço `api-test`, junto com 8 novos testes do probe. T02 concluída pelo caminho originalmente previsto.

O `.gitignore` foi antecipado apenas para excluir dependências, artefatos e arquivos de ambiente já nesta tarefa. O `.dockerignore` permanece em T03.

### T03 — Construir imagem e Compose

- [x] Criar Dockerfile multi-stage com caminho de testes e runtime mínimo, usando versões verificadas.
- [x] Usar instalação pelo lockfile e usuário não root na execução final.
- [x] Criar `.gitignore` e `.dockerignore` coerentes com o contexto de build.
- [x] Criar serviço `api` sem `ports`, volumes, socket Docker ou privilégios extras.
- [x] Criar rede `service` com `internal: true` e manter a API somente nela.
- [x] Configurar health check e rotação de logs, sem reinício automático.
- [x] Criar serviço auxiliar `probe` no profile `tools`, sem processo permanente e sem portas publicadas.
- [x] Criar caminho sob demanda para executar testes via Compose, por exemplo serviço `api-test` no profile `tools`, usando o estágio de testes.
- [x] Validar sintaxe com `docker compose config --quiet`.
- [x] Executar a suíte em container e conferir seu exit code.

**Comandos executados:**

```powershell
docker compose config --quiet
docker compose --profile tools run --build --rm api-test
docker compose build api
```

**Validação:** FL-02 e FL-03 aprovados; configuração resolvida sem publicação de portas. Confirmar opções dos comandos na versão local do Compose antes de usá-los.

**Resultado:** comandos com saída zero; 35 testes aprovados (27 da API/ciclo de vida e 8 do probe). Configuração resolvida conferida sem portas, volumes ou modos proibidos; testes sem rede. Build de runtime aprovado. A tentativa inicial de `build api probe` apresentou conflito de exportação da mesma tag: corrigido ao atribuir build de runtime somente a `api`; `probe` reutiliza a imagem com `pull_policy: never`. Repetir `build api probe` após a correção também passou, construindo apenas `api`.

A inspeção de metadados da imagem indica `User=node`; isso não substitui a inspeção de usuário efetivo, bindings e redes em T04. O serviço API não foi iniciado nesta etapa. Detalhes e limitações nas [evidências](../../evidence/01-local-foundation.md#6-build-e-compose-t03).

### T04 — Validar execução, rede e privilégios

- [x] Iniciar somente a API e aguardar o health check dentro de um prazo documentado.
- [x] Executar o probe como outro container, pela rede de serviço, usando DNS `api`.
- [x] Conferir bindings com `docker inspect` e a configuração resolvida, não apenas a coluna de portas do `ps`.
- [x] Inspecionar usuário efetivo, redes e mounts; confirmar ausência de modos proibidos.
- [x] Validar que o health check não registra dados sensíveis.
- [x] Registrar os resultados para FL-04, FL-05 e FL-06.

```powershell
docker compose up -d --wait --wait-timeout 60 api
docker compose ps
docker compose --profile tools run --rm --no-deps probe
docker compose logs --no-color api
```

O probe deve ter URL e timeout documentados e pode usar `http://api:3000/health` como destino fixo nesta entrega. Para inspecionar o container, obter seu ID com `docker compose ps -q api`; registrar somente os campos necessários, evitando dumps de ambiente.

**Resultado:** saúde em 6694 ms incluindo criação/início; probe separado aprovado. Bindings e portas observadas vazios, nenhum mount, uma rede bridge interna. UID/GID efetivos 1000 em PID 1, capabilities efetivas zero e `NoNewPrivs=1`. Configuração de logs e prazo de parada conferidos no container; health check registrou apenas `probe_succeeded`. Snapshot inicial: 18,68 MiB. Uma tentativa de inspeção via `node -e` falhou por aspas do PowerShell; envio por stdin corrigiu o comando, sem alteração na aplicação. Reprodução em [runbook](../../runbooks/local-foundation.md).

### T05 — Simular indisponibilidade e recuperação

- [x] Parar somente a API, verificar prazo e log de encerramento.
- [x] Confirmar que ela não reinicia sozinha.
- [x] Rodar o probe e observar falha com código não zero dentro do timeout.
- [x] Iniciar novamente a API e aguardar saúde.
- [x] Repetir o probe e observar sucesso.
- [x] Registrar FL-07 e FL-08, incluindo o teste de falha de inicialização de T02.

```powershell
docker compose stop api
docker compose --profile tools run --rm --no-deps probe
docker compose start api
docker compose --profile tools run --rm --no-deps probe
```

**Atenção:** `--no-deps` evita iniciar a API automaticamente durante a verificação negativa. Após `start`, aguardar saúde antes do último probe. A falha esperada do probe é evidência do cenário, não motivo para publicar uma porta ou contornar a rede.

**Resultado:** parada com saída 0 em 718 ms; logs de `SIGTERM` e encerramento completo. Probe com saída 1 em 1472 ms totais incluindo criação/remoção do auxiliar. API continuou parada após o probe e observação adicional de 12 s, `RestartCount=0`. `start api` seguido de consulta limitada a 60 s atingiu saúde em 5286 ms de espera; probe voltou a retornar 0. O timeout de 2 s é da requisição, não do comando Compose. Falha de bind e limite de encerramento foram revalidados pela suíte em T06.

### T06 — Documentar e fechar a entrega

- [x] Criar evidências com ambiente, comandos, resultados e relação com FL-01 a FL-09.
- [x] Atualizar README com caminho real de build, teste, início, diagnóstico e parada.
- [x] Explicar por que a API ainda não abre no navegador do host e o que a próxima entrega acrescentará.
- [x] Documentar que HTTP interno não é cifrado e que acesso ao host/Docker está fora da fronteira de isolamento.
- [x] Repetir o procedimento documentado sem apagar volumes ou dados alheios.
- [x] Revisar arquivos e logs em busca de segredos e informações locais desnecessárias.
- [x] Atualizar roadmap apenas quando todos os critérios de saída estiverem comprovados.

**Validação:** FL-09 e revisão de todos os demais critérios. Se algum teste estiver pendente, manter a entrega em validação ou bloqueada, conforme o caso.

**Resultado:** procedimento do README e inspeções do runbook repetidos; 35 testes aprovados novamente (5865,097699 ms de suíte), build e segundo ciclo de parada/falha/recuperação aprovados. Durante a repetição do build, Compose recriou somente a API pela nova identificação da imagem; após isso a recuperação sem novo build reutilizou o mesmo container, verificado por ID. API deixada em `exited`/0; rede, imagens e container preservados. Nenhum serviço de próxima entrega foi implementado. A reprodução foi executada pelo agente; não foi presumida demonstração manual da autora.

## 4. Parada e recuperação das mudanças

- Para interromper a API: `docker compose stop api`.
- Para retomá-la: `docker compose start api` e aguardar saúde.
- Para reconstruir após ajuste de código: usar o build documentado e recriar somente o serviço afetado.
- `docker compose down` remove containers e redes do projeto, mas não deve ser executado automaticamente quando outros serviços já tiverem sido adicionados; confirmar o impacto primeiro.
- Não usar `down -v`, prune, remoções amplas ou apagar diretórios para resolver falhas.
- Caso uma mudança falhe, corrigir apenas os arquivos envolvidos ou propor reversão específica, preservando alterações da autora.

Não há volume previsto nesta entrega. Essa ausência não autoriza excluir volumes de outras etapas ou projetos.

## 5. Registro da execução

Preencher durante a implementação, com uma linha por tarefa ou rodada de validação:

| Tarefa/critério | Data | Comando ou procedimento | Resultado observado | Pendência/próxima ação |
| --- | --- | --- | --- | --- |
| T01 / FL-01 | 24/10/2026 | `docker version`, `docker compose version`, `docker info` com campos selecionados | Cliente e daemon acessíveis; Linux confirmado | Nenhum bloqueio de ambiente identificado nesta inspeção |
| T01 / versões | 24/10/2026 | Índice Node, metadados npm, manifesto Docker e documentação oficial | Versões fixadas e tag com plataforma local disponível | Validar instalação, build e execução em T02/T03 |
| T01 / limites | 24/10/2026 | Revisão técnica e parâmetros registrados neste plano | Preparação concluída, sem mudança de contrato | Próxima tarefa: T02, quando solicitada |
| T02 / dependências | 24/10/2026 | `npm install --package-lock-only` e `npm ci` em container temporário | Lockfile gerado e 3 pacotes de desenvolvimento instalados | Nenhuma dependência de produção |
| T02 / testes | 24/10/2026 | `npm test` em container sem rede externa ou portas publicadas | 27 testes aprovados, 0 falhas; compilação TypeScript aprovada | Revalidar via Compose na T03; detalhes nas evidências |
| T03 / FL-02 e FL-03 | 24/10/2026 | Configuração resolvida, build e `compose run --build --rm api-test` | 35 testes aprovados, 0 falhas, exit code 0; imagens construídas | T02 e T03 concluídas; próxima tarefa T04 |
| T04 / FL-04 a FL-06 | 24/10/2026 | Início com espera, probe, configuração resolvida e inspeção seletiva | Saúde, DNS interno, ausência de bindings/mounts e usuário efetivo comprovados | Concluída |
| T05 / FL-07 e FL-08 | 24/10/2026 | Parada, probe negativo, observação e recuperação | Sem reinício automático; probe 1 durante parada e 0 após saúde | Concluída |
| T06 / FL-09 | 24/10/2026 | Repetição do README/runbook, suíte e revisão de arquivos/logs | 35 testes aprovados; segundo ciclo aprovado; API parada | Fundação concluída; próxima entrega requer SPEC/PLAN próprios |

## 6. Checklist final

- [x] FL-01 a FL-09 comprovados com evidências reais.
- [x] Nenhuma porta da API publicada, inclusive nos serviços auxiliares.
- [x] Nenhum serviço de etapas futuras implementado por antecipação.
- [x] Documentação distingue implementação, testes executados e limitações.
- [x] Procedimento e explicação fornecidos para a autora repetir a validação interna, a falha e a recuperação; repetição pelo agente aprovada. Execução manual pela autora não observada.
