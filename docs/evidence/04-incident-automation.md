# Evidências 04 — Incidentes e relatórios com IA (parcial)

**Estado atual — 26/10/2026:** relatórios reais #4 e #5 recebidos no Mailpit, HTML persistido e SMTP accepted. Schema 1/2/3 e allowlist ativos; action/media types e workflows retomados. Prompt v1 rejeitado semanticamente por afirmação causal; prompt v2 entregue com hipótese genérica não confirmada, aguardando revisão humana. Preservados jobs anteriores failed. Diagnóstico corrigiu a leitura indevida de metadata `running` como travamento do Schedule Trigger. Entrega não concluída: [matriz de aceite/pendências](04-acceptance-matrix.md). Contrato na [SPEC](../features/04-incident-automation/SPEC.md); tarefas no [PLAN](../features/04-incident-automation/PLAN.md).

## Integração real e revisão para fechamento

**Decisão posterior da autora:** priorizar fluxo mínimo funcional e encerrar testes extensos para entrevista no dia seguinte. Demo funcional entregue, sem declarar todos os critérios aprovados. Action/media types e ambos workflows foram retomados; n8n healthy. [Roteiro](../runbooks/interview-demo.md). Prompt v2 também produziu afirmação causal indevida no ensaio #7; o endurecimento do prompt não foi uma solução semântica confiável. IA continua componente demonstrativo sujeito a revisão humana, não diagnóstico. A pausa transitória de segurança foi revertida após a orientação explícita da autora para retomar a demo local.

- Falha real Ollama: job #6 terminou `failed`, duas tentativas, `lease_expired`, sem outbox; incidente fechado e Ollama restaurado. Não reenfileirado.
- Falha real SMTP: incidente #7 (175/176, 40 s), job ready em uma tentativa, outbox 3 virou `delivery_unknown` com uma tentativa e erro `previous_send_lease_expired`. Após Mailpit retomar, permaneceu unknown/1, sem reenvio automático. Isso demonstra comportamento conservador, não implementação de retry pré-aceite ou prova de crash após aceite real.
- Varredura limitada: 143 arquivos versionados/não ignorados e logs n8n recentes sem correspondência para 11 valores conhecidos de segredos locais. Não é auditoria universal nem prova de ausência de qualquer segredo. `git diff --check` sem erros de whitespace (avisos LF/CRLF).

- O diagnóstico temporário autorizado usou `N8N_LOG_LEVEL=debug` e progresso=true. Logs mostraram que ciclos sem job concluíam. Execuções com none/false podem ficar com status inicial `running` e `deletedAt` preenchido; ignorar `deletedAt` e assumir que a pilha persistida é a pilha atual produziu diagnóstico incorreto. Nenhum registro antigo foi apagado manualmente.
- Erros reais: newline literal em string JavaScript do prompt; fechamentos de objeto `}}` confundidos com delimitador da expressão pelo avaliador n8n; HTTP Request raw retornando stream em vez de JSON. Corrigidos expressão (testada também na VM nativa da versão instalada) e `contentType=json/specifyBody=json/jsonBody`. Nenhuma validação SQL foi desativada; `invalid_model_output` rejeitou análise ausente durante o diagnóstico.
- Incidentes #2 (155/156, 40 s) e #3 (157/158, 40 s) foram fechados, mas jobs esgotaram leases durante ensaios com versões ainda incorretas. Foram preservados junto ao job #1, sem replay/requeue.
- Incidente #4 (159/160, 41 s): job ready em uma tentativa, outbox 1 accepted em uma tentativa, mensagem Mailpit `3VPKTwv6cUOmuSwGqepHus`, assunto `SecureOps | Relatório #4 v1`. HTML 2096 bytes. A IA afirmou causa de rede sem evidência; relatório preservado e **rejeitado na revisão técnica**, não considerado conteúdo aprovado.
- Prompt v2 usa system instructions, temperatura 0, seed 42, limites de schema e saída, sem aumentar recursos do modelo. Migração 003 mantém v1, permite revisão 2 e preserva schema/lease/template; fixture confirmou v2 válido, versão desconhecida negada, dados inválidos negados e XSS escapado. Nada foi reescrito nos relatórios anteriores.
- Incidente #5 (161/162, 40 s) aconteceu com n8n parado. Banco registrou closed/job pending/0 tentativas. Restart automation-db/receptor e retomada n8n preservaram credenciais/estado; job passou ready/prompt2 na primeira tentativa, outbox 2 accepted na primeira tentativa. Mensagem `0bsklv58gj88NlgtJC9ase`, assunto `SecureOps | Relatório #5 v1`. A IA separou uma hipótese genérica, não causa confirmada; revisão humana continua obrigatória.
- Depois do restart, replay concorrente real do evento 161: 20 respostas duplicate, contadores mantidos em 10 deliveries/5 incidentes/5 jobs/2 outbox. Nenhum relatório duplicado.
- `Test-AutomationServices -Phase report -IncidentId 4/5` comprovou uma mensagem por assunto, destinatário fictício fixo, HTML/texto, separação fatos/hipóteses/avisos e ausência de elementos ativos/remotos nos corpos. É inspeção por API autenticada, não renderização em navegador. Mensagem #4 persistiu após restart Mailpit/Ollama/n8n; #5 foi entregue após restart do banco/receptor/n8n.
- Flags temporárias restauradas: warn/progress=false, verificadas no container recriado. Dois testes iniciados em paralelo com reinícios falharam na asserção de preservação de containers; **não foram contados como aprovados**. Repetição serial posterior passou.
- Regressões: SQL 86+15+12 checks, 20 duplicatas/corrida/rollback/reaplicação negada; receptor 139+7+4 checks; infraestrutura 82; interfaces/isolações de banco; API 35; coletor 39+16/config TypeScript; gateway isolado positivo/negativos; discovery; monitor final com quatro widgets/coleta; modelo 6 testes de integridade; workflow/webhook 9. Resultados de fixtures não substituem gates reais indicados na matriz.
- Falha real de coleta: parada somente de identity-event-collector abriu trigger 25232, incidente #6; retomada fechou em 50 s, enquanto triggers de disponibilidade/autenticação ficaram normais. Ollama deliberadamente offline nesse ensaio para observar esgotamento do job; resultado final registrado ao concluir o ensaio.

## Incremento de preparação para teste integrado — 26/10/2026

- Criados `incident-media-types.yaml` com media types problem/recovery inativos e script JS que mapeia explicitamente os triggers 25229–25232. O payload é serializado, contém apenas campos do contrato e a chave é referenciada por macro secreta local; destino fixo `http://incident-receiver:3000/v1/events`. Quatro testes unitários passaram (mapeamento, correlação, negativos e respostas HTTP). Isso **não valida expansão de macros pelo Zabbix** nem entrega em runtime.
- Compose do Zabbix agora declara a rede interna `events` no serviço server; validação estática confirmou nenhuma porta publicada e configuração geral preservada. O container Zabbix não foi recriado/conectado nesta etapa.
- Adicionado `Install-IncidentSchema.ps1`, que exige confirmação explícita de macros e recusa schema preexistente. **Não executado.** O banco ativo continua sem schema/allowlist.
- Workflows de geração (Postgres claim → Ollama → validação/persistência SQL) e entrega Mailpit (claim → SMTP → marcar aceite) permanecem inativos, sem credenciais. 4 testes estáticos passaram; são validações de arquivos/contrato, não teste n8n importado, inferência com incidente, SMTP real nem visualização no Mailpit. Falha ou expiração no envio fica ambígua e não é reenviada automaticamente; reconciliação manual ainda pendente.
- `Test-AutomationIncidents.ps1`: 86 checks SQL + 15 checks de relatório/outbox; concorrência 1 applied/19 duplicate, corrida 1 applied/1 conflict, rollback de lock timeout; fixture efêmera, 12 containers existentes preservados. `Test-AutomationInfrastructure.ps1`: 56 checks estáticos. Sem mudança no banco ativo.

## Staging inicial autorizado — 26/10/2026

- A autora autorizou prosseguir com instalação e validação ponta a ponta. `Install-IncidentSchema.ps1 -EndToEndTestAuthorized` aplicou as migrações 001/002 e inseriu os trigger IDs confirmados 25229–25232 na allowlist `secureops-lab-zabbix`. Consulta read-only retornou versions `1,2`, quatro condições, zero deliveries. Nenhum evento foi fabricado; action continua ausente.
- Recriado somente `zabbix-server` pelo overlay Compose para ingressar em `secure_ops_lab_events`. Container está `running`; `getent` resolve `incident-receiver`; HTTP GET `/health` dentro do container retornou `{"result":"alive"}`. Sem publicação de porta.
- Recriado somente `n8n` para aplicar `EXECUTIONS_TIMEOUT=180`; readiness saudável e `Test-AutomationServices.ps1 -Phase interfaces` passou (receiver 200/401, n8n readiness, APIs Mailpit protegidas). Query read-only n8n localizou `SecureOps - entrega local de relatórios v1 (candidato)` com `active=false`; não localizou o workflow de geração. Dados do banco persistiram. O owner pode precisar reabrir sua sessão no editor.
- Media types aparecem no DB Zabbix como IDs 72/73 com status desabilitado; sem action instalada. A macro secreta foi criada pela autora; valor não consultado/exibido. Expansão real de macros ainda não validada.
- `EXECUTIONS_TIMEOUT=180` ativo. Não houve chamadas ao modelo, envio SMTP via workflow, evento Zabbix→receptor ou relatório real.
- Após a autora informar que criou dois workflows separados e que os nodes funcionam, consulta read-only completa a `workflow_entity` confirmou `SecureOps - Incident Report|false` e `SecureOps - Mail Delivery|false`. Ambos permanecem inativos/não publicados.
- Para preparar a action, consulta ao banco mostrou zero actions com nome SecureOps. `Test-MonitoringTokenRevoked.ps1` confirmou a rejeição do token anterior. A autora salvou um novo token pelo procedimento local; `Configure-MonitoringSecurity.ps1` (somente leitura) recebeu `zabbix_auth_not_authorized` em chamada autenticada. Nenhuma configuração administrativa foi alterada. Verificar na UI que o token está habilitado, não expirado, associado ao usuário Admin esperado e autorizado para a API; não revelar o valor. A criação da action aguarda nova consulta read-only bem-sucedida.

## Ensaio real Zabbix e pausa do runtime — 26/10/2026

### Diagnóstico autorizado após republicação

A autora autorizou reprodução controlada com progresso temporariamente persistido e logs detalhados, exclusivamente de snapshots sanitizados de relatório. Nenhum header/corpo de ingestão passa pelo n8n; credenciais nativas continuam criptografadas. Restaurar `EXECUTIONS_DATA_SAVE_ON_PROGRESS=false` e log `warn` após a reprodução, sem apagar registros existentes. `runData` vazio com progresso desabilitado é apenas snapshot inicial e **não localiza** um travamento no Schedule Trigger; a conclusão anterior era indevida. O agendamento já havia chegado ao claim SQL. A expressão do prompt contém newline literal dentro de string JavaScript com aspas simples; o avaliador nativo da versão instalada reproduziu `invalid syntax` com fixture sintética (sem inferência/SQL de incidentes).

- Após a autora habilitar o token na UI, `Configure-MonitoringSecurity.ps1` somente leitura passou. Os quatro triggers estavam habilitados/clear; host `secureops-api` (ID 10684) está sozinho no host group `SecureOps Lab` (ID 22). Media types 72/73 eram Webhooks desabilitados. A macro existia, mas era do tipo texto; script de preparação comparou hash em memória contra `.local/automation/webhook-key`, não imprimiu o valor, converteu para tipo Secret e verificou o tipo.
- Preparada action 7 com condição host 10684 + trigger IDs 25229–25232, um único operation PROBLEM via media 72, recovery via media 73 e zero update operations. Criado user group ID 14 com frontend desabilitado e leitura somente no host group 22; user ID 3 (role User) tem só media types 72/73. Nenhuma senha aleatória foi exibida/salva. O escopo foi conferido antes da habilitação.
- Workflows confirmados no n8n: `SecureOps - Incident Report` (ID `aqhbDEZE5eGYegqp`) e `SecureOps - Mail Delivery` (ID `WnP9yQzfVSyBH8n7`); credenciais referenciadas: Postgres account e SMTP account. CLI `publish:workflow` publicado individualmente; n8n reiniciado saudável e interface smoke passou. O CLI emitiu aviso `McpRegistryNodeLoader` apesar de exit 0; verificação de DB confirmou ambos `active=true`.
- Um ciclo controlado consistiu em parar somente Compose service `api` e restaurá-lo. Zabbix trigger 25229 abriu; receiver ledger retornou `applied` para problem event 153 e recovery event 154. Incidente 1 fechou com duração de 80 s. Triggers 25230–25232 ficaram normais; container API voltou healthy. Isso comprova expansão real de macros e ingestão problem/recovery, não os demais triggers.
- O job de relatório teve duas tentativas, sem modelo/persistência de análise; terminou `failed`, `last_error=lease_expired`, sem outbox. Inspeção de metadados n8n (sem ler/exportar payloads) mostrou execuções de produção sem `runData` e `nodeExecutionStack` aguardando `Verificar jobs a cada 30s`; report e mail delivery acumularam execuções `running`. Ollama não carregou modelo durante o fluxo.
- Smoke isolado `Test-AutomationServices.ps1 -Phase model` passou: inferência sintética em 33.498 ms, modelo/digest esperados; chamada sintética pelo network namespace do n8n também respondeu 200/done em 14.674 ms. Isso não valida o workflow real. `Test-AutomationServices.ps1 -Phase interfaces` passou depois dos restarts; a primeira chamada durante startup falhou transitoriamente e a repetição passou.
- Para não acumular execuções nem novos jobs sem relatório, action 7 foi desabilitada antes de media types 72/73, ambos agora disabled. Os workflows foram despublicados individualmente e n8n reiniciado; DB confirma ambos `active=false`, health/readiness e interfaces passaram. Dados do incidente e do job failed foram preservados. Não apagar nem reenfileirar o job manualmente.
- A tabela n8n ainda mostra 27 execuções `running` por workflow, iniciadas durante o período publicado. Após o restart/despublish, observação de mais 35 s não encontrou novos starts; as antigas foram preservadas, sem DELETE/SQL corretivo. O estado permanece pendente para inspeção/encerramento pelo mecanismo suportado do n8n.
- A consulta authenticated API funcionou com o token temporário habilitado pela autora. Revogar esse token na UI depois que a investigação/alterações administrativas terminar; nenhum valor foi consultado ou incluído nas evidências.

## 1. Autorização e seleção

A autora primeiro pediu IA para gerar relatórios, depois aprovou o fluxo e, por fim, solicitou “use a versao e modelo de IA que vc recomendar e inicie a implementação”. Isso autorizou seleção técnica e início gradual dentro do desenho já apresentado, não testes externos, dados reais, cloud ou correção automática.

- n8n **2.44.7**, release stable oficial de 26/10 (2.45.4 estava prerelease); binário --version confirmou 2.44.7. Licença SUL consultada: uso pessoal/não comercial permitido, sem solicitar licença Enterprise ou trial.
- Ollama **0.40.11**, release oficial de 24/10, com cloud desabilitado por opção conferida no código da tag.
- Qwen2.5 **1.5B Instruct Q4_K_M**, português e licença Apache 2.0; pesos **986048512 bytes**. Não escolhido por promessa de previsão de falhas, mas por recursos limitados e saída estruturada.
- Mailpit **1.32.0**, release de 22/10 com correções de segurança de thumbnails/renderização; opções conferidas no help real e documentação.
- PostgreSQL **17.11** em container/volume **novos**, sem atualizar/reutilizar o banco do monitor.

Digests dos índices Linux fixados no Compose/Dockerfiles e listados na SPEC. Consultas de release/config/licença/manifesto foram leitura pública para instalação; nenhum log/dado do laboratório enviado nessas consultas. Não houve scanner/auditoria completa de vulnerabilidades.

Preflight: Docker 28.5.1, Linux x86_64, 12 CPUs e MemTotal 8171765760 bytes; listeners 5678/8025 não encontrados antes da subida. Sete serviços existentes ativos. Disco Docker indicou 947 GiB disponíveis no filesystem consultado; não é espaço reservado/garantido para o projeto.

## 2. Implementação inicial e limites de exposição

`compose.automation.yaml` adiciona cinco serviços opt-in no profile automation. `events`, `automation`, `inference` e `mail` são internas; receptor tem events/automation, n8n está fora de events e n8n/Mailpit usam operations para interfaces em loopback. Server Zabbix **ainda não conectado a events** e nenhuma action criada.

- n8n: **127.0.0.1:5678**, não root 1000, rootfs read-only, 512 MiB, volume próprio, tmpfs de /tmp e /home/node/.cache.
- automation-db: não root 999, 256 MiB, somente automation, sem porta no host, volume próprio. Bancos n8n/incidents e papéis n8n_meta/incident_owner/incident_ingest/incident_report/incident_reader; runtime sem superuser/create role/create database/replication. Somente n8n migrou suas tabelas; incidents ainda não tem modelo/transações de negócio.
- Ollama: não root 1000, read-only, 2 GiB/4 CPUs, somente inference, sem porta no host, um modelo/uma consulta paralela, contexto 2048, cloud/history/debug de bodies desabilitados. API sem autenticação própria: fronteira é rede local restrita e host/Docker confiáveis, não isolamento absoluto.
- Mailpit: não root 1000, read-only, 128 MiB, SMTP só Docker e UI/API em **127.0.0.1:8025**, autenticações SMTP/UI distintas por arquivo, volume SQLite próprio, sem pruning automático/relay/forward configurados. Destinatário permitido somente operadora@lab.invalid; não chega à caixa pessoal externa.
- Receptor: Node 24.22.1 fixado por digest, TypeScript apagável nativo, `pg` 8.21.0 MIT com dependências lockadas; não root 1000, rootfs read-only, 128 MiB/1 CPU, sem porta host/volume. Recebe somente segredos webhook e incident_ingest. Liveness não depende da migração/allowlist, portanto não representa prontidão para ingestão funcional.

Imagens derivadas de Ollama/Mailpit só preparam diretórios de volume com dono 1000 durante build; nenhum init de runtime root/privileged/capability extra. Segredos novos em `.local/automation/`, ACL restrita, mounts somente leitura, fora do Git/build; inicializador recusa pasta existente, sem trocar credenciais anteriores.

Exceções locais documentadas antes da subida: HTTP sem TLS, cookie n8n sem Secure/SameSite Strict e SMTP autenticado sem TLS. Não foi desabilitada validação de certificado para contornar erro. Nenhuma confidencialidade de transporte/egress bloqueado foi presumida.

## 3. Falhas encontradas e correções

- Primeira tentativa de versão Mailpit usou --version, que não existe: help real orientou subcomando version. Esse subcomando tentou consultar release mesmo com flag de version-check desligada, mas **network none impediu a conexão**. Não se repetiu com rede externa; versão compilada e release foram conferidas separadamente. A flag de runtime continua configurada; não é prova de ausência universal de chamadas em todos os subcomandos.
- Primeiro startup n8n fez migrações mas falhou ao criar /home/node/.cache com rootfs read-only. Acrescentado tmpfs limitado com UID/GID correto; mesmo banco/volume preservados e recriação somente do n8n, sem relaxar rootfs ou privilégios. Prontidão posterior 200.
- Um teste de allowlist inicialmente contou array JSON como um objeto no PowerShell 5.1. Corrigida enumeração, sem alterar nodes permitidos ou runtime.
- Download do modelo por loader efêmero não root, sem portas/secrets de runtime, com rede de saída apenas para instalação. Loader removido no finally; volume preservado. Runtime fica em inference interna, sem download automático.
- Verificador inicial detectou estrutura local diferente do manifesto do registro: Ollama 0.40 adiciona layer com referência ao manifesto original. Inspeção pública confirmou isso; verificador agora ancora no SHA original fixado, verifica wrapper exatamente e hasheia **todos** os blobs/config/template/licença/pesos. Não substituiu hash por alias ou aceitou pesos desconhecidos.
- API tags expõe digest original sem prefixo sha256; teste de metadata foi corrigido para essa representação real. Tentativas que falharam antes dessa correção não são inferências aprovadas.
- Envio do script bash pelo stdin PowerShell acrescentou CR ao final, produzindo saída de checks seguida de exit não zero. Wrapper passou a normalizar CR antes da interpretação; reexecução exit 0. `.gitattributes` estendido aos scripts Linux de automação.
- O primeiro volume de modelo foi criado administrativamente sem labels Compose. Compose avisou sobre origem externa; dados foram preservados, não removidos para eliminar aviso. Instalador agora inclui labels na criação de volumes futuros; não altera labels/dados de volumes existentes.

## 4. Testes executados

| Verificação | Resultado e limite |
| --- | --- |
| Test-AutomationInfrastructure -Runtime | **66 checks aprovados** (46 estáticos + 20 runtime); configurações dos sete serviços anteriores iguais, redes, usuários/caps, limites e binds reais. Não comprova workflow/HTML |
| Test-AutomationModelIntegrity | **6 testes aprovados**, 246,832238 ms: manifesto original e wrapper válidos; rejeição de pesos corrompidos do mesmo tamanho, layer extra, manifesto original alterado e licença corrompida |
| Install-AutomationModel | Integridade de bytes local real aprovada; todos os blobs verificados. Reexecução detectou modelo íntegro sem download/sobrescrita |
| Interfaces | Readiness n8n 200; workflows sem sessão 401; API Mailpit sem/errada autenticação 401; com autenticação exclusiva 200 |
| Banco | TCP correto permitido, senha errada negada; acesso n8n_meta→incidents negado, metadados de grants sem acesso cruzado, papéis sem superprivilégios, ingest sem CREATE de schema. Nenhum DDL de teste/tabela de incidente criado |
| SMTP | Sem autenticação 530, senha errada 535, destinatário diferente negado; mensagem fictícia autenticada aceita e vista na API da caixa. Mensagem preservada, não apagada para repetir teste |
| Serviços anteriores | IDs/start times dos sete serviços iguais ao marcador inicial ignorado; nenhum parado/recriado por este incremento |
| Regressão runtime de monitoramento | Coletor com qualidade=1/contagem=0 e negativa 401; disponibilidade com duas amostras saudáveis recentes/HTTP200. Não foi reexecutada ainda toda a suíte 01–03 |
| Regressão pós-inclusão do receptor | `Test-AutomationInfrastructure.ps1 -Runtime`: **80 checks**. `Test-AutomationServices.ps1 -Phase interfaces`: liveness receptor 200, POST sem segredo 401, além de readiness/negações n8n e autenticação Mailpit. Confirma runtime/exposição, não integração com Zabbix ou prontidão SQL |

Hash público fixado do manifesto original: `65ec06548149b04c096a120e4a6da9d4017ea809c91734ea5631e89f96ddc57b`. Hash do wrapper local 0.40: `f2b0a490f661d58f20c4b98e5797ecf55e6e96293a88b71e96e7cc389f658f7e`. A API tags apresenta o original; wrapper e original não devem ser confundidos.

### Inferência real, mas cenário sintético

Test-AutomationServices -Phase model aprovado: **23740ms**, **150 tokens de saída**, JSON completo (done/stop) no schema proposto. Prompt descreveu exclusivamente uma API fictícia com intervalo observado de 60s, retorno a 200 e ausência de dados de recursos/logs/histórico. Não consultou eventos reais ou credenciais.

O modelo gerou resumo em português, hipóteses de falha e recomendações de investigação. Hipóteses genéricas não são causas comprovadas; revisão semântica pela autora ainda pendente. Nenhum HTML derivado dessa análise foi enviado: o smoke SMTP é **outra mensagem**, explicitamente sem análise de IA. Portanto IA-11 e fluxo ponta a ponta permanecem pendentes.

### Cadastro manual e recursos

Autora confirmou “Conta criada; editor abriu” ao cadastro local com conta fictícia/senha exclusiva e sem trial/serviço externo. Origem: relato manual, não navegador autenticado observado pelo agente. Depois da recriação apenas do n8n, consulta mínima retornou ownerConfigured=true e workflowCount=0. Não coletados senha/cookie/token; logout, atributos autenticados e relogin ainda não retestados manualmente.

Snapshot aproximado às 12:30 (-03:00): n8n 416/512 MiB, banco da automação 64,31/256 MiB, Mailpit 9,848/128 MiB e Ollama descarregado 17,74 MiB/2 GiB. memory.peak do cgroup: Ollama **1160585216 bytes**, n8n recriado **480194560 bytes**; memory.events sem oom/oom_kill nos dois. Não é teste de carga; n8n tem margem reduzida no teto atual e precisa nova medição com workflows antes de concluir viabilidade operacional.

## 5. Pendências e próximo incremento

Contrato real de macros/action, parser e rejeições de payload; transação/constraints de incidentes, jobs/outbox e consultas; workflows n8n; template HTML seguro, falhas/retries e envio de relatório de IA real; persistência/concorrência fora de ordem; sessão do editor, revisão humana da análise, regressão completa e matriz IA-01–IA-14.

Sem token administrativo Zabbix reutilizado, sem alterações em senha/TOTP/grupos e sem exclusão de volumes ou dados. Infraestrutura iniciada **não significa entrega concluída**. Sem commit/push automático.

## 6. Revisão local do incremento — 12:39 (-03:00)

Sintaxe de seis scripts PowerShell, dois Bash e três módulos JS aprovada; 99 destinos de links Markdown locais existentes e git diff --check aprovado (âncoras/URLs externas não verificadas por essa checagem). Inicializador recusou pasta existente sem reset. Nova comparação dos sete serviços originais confirmou IDs/start times e running preservados.

Varredura em memória de **108 arquivos versionados/versionáveis** e **691 linhas de logs dos quatro serviços novos** sem correspondência aos segredos locais selecionados de automação/monitoramento/client do gateway. Padrões selecionados de chaves privadas/JWT também verificados nos arquivos; `.local` excluída do Git. Nenhum log bruto exportado. Varredura limitada: não é garantia universal de ausência de dados sensíveis, teste de egress ou auditoria de dependências.

## 7. Incremento seguinte — núcleo SQL isolado, 26/10/2026

Após a autora solicitar continuidade da implementação, criada `infra/automation/migrations/001-incidents.sql`: allowlist administrativa, ledger canônico, correlações/ciclos, identidade local de incidentes, índice parcial de aberto único, views read-only e rotina parametrizada `incident.ingest(text)`. Fechamento cria reserva única de job com snapshot sanitizado no mesmo commit; **lease, processamento, HTML e outbox ainda não implementados**.

**Migração não aplicada ao automation-db ativo**, sem provisionar IDs reais, alterar Zabbix ou publicar workflow. A validação usa PostgreSQL 17.11 efêmero, network none, TCP listener desabilitado, sem portas/volumes persistentes/mounts de segredos do lab, UID 999, caps removidas, no-new-privileges e rootfs read-only. Dados/socket/tmp em tmpfs; bootstrap aleatório descartável usado somente pela fixture. Cada execução remove somente seu container exclusivo no finally, sem exclusão de volumes ou dados existentes.

Execução final de `./scripts/Test-AutomationIncidents.ps1`, exit 0:

| Ensaio real de banco, com eventos fictícios | Resultado |
| --- | --- |
| Contrato, transições, estado e privilégios | **86 verificações SQL aprovadas** |
| Vinte entregas idênticas concorrentes | 20 conexões observadas simultaneamente bloqueadas; **1 applied, 19 duplicate, 1 entrega/1 incidente** |
| Dois primeiros ciclos da mesma condição | 2 chamadas observadas simultaneamente bloqueadas; **1 applied, 1 conflict**, somente 1 entrega/1 incidente |
| Timeout de lock | SQLSTATE **55P03**, sem resultado positivo, sem ledger/ciclo parcial; limite interno 4s e statement timeout 5s do cliente de teste |
| Reaplicação da migração | Recusada, com rollback/ledger preservado; sem DROP/overwrite |
| Preservação | **11 serviços existentes** com ID/start time/running iguais antes/depois |

Os negativos cobrem JSON inválido/array/null, campos ausentes/extras/duplicados (inclusive chave escapada), tipos, macros, ID decimal acima do limite/zero/leading zero, ID de 20 dígitos sem arredondamento, instância/trigger/condição/categoria/host/serviço/tipo incorretos, tempo futuro/velho/malformado, injeção SQL e Unicode nulo. Corpo JSON válido com espaços até **4096 bytes** é aceito como duplicata canônica; com 4097 bytes é rejeitado. Para rejeições/duplicatas, o teste compara **todo o conteúdo** de allowlist/ledger/ciclos/incidentes/jobs antes/depois, não só contagens.

Transições testadas: abertura/fechamento/duração, repetição após fechamento sem reabertura, conflito de conteúdo/trigger, novo ciclo bloqueado e retry após fechar o anterior, recovery órfã/duplicada/conflitante, problema atrasado já closed e out_of_order, duração negativa negada, conclusão de ciclo antigo preservando o novo aberto, duas collection e autenticação independentes. Snapshot do job não muda com eventos posteriores. Falha forçada **depois** do fechamento e da criação do job reverte ledger/ciclo/job integralmente; índice parcial também rejeita diretamente segundo open.

Testes com SET ROLE verificaram ingest EXECUTE permitido e SELECT/DML/DDL de tabelas negados; leitor acessa views mas não chama ingest/escreve; relatório não pode mudar incidentes/chamar ingest; metadados n8n não têm EXECUTE da função privilegiada. Isso não substitui o teste de credenciais/query parameters de um workflow real.

Regressões reexecutadas: **66 checks de infraestrutura**, isolamento do banco ativo, interfaces/readiness/negações, coletor runtime (qualidade 1, contagem 0, negativa 401) e disponibilidade com amostras saudáveis HTTP200 aprovados. Não reexecutada toda a suíte 01–03 nem navegador autenticado. Sintaxe do novo PowerShell/Bash e whitespace aprovados.

### Parser n8n: análise estática, não teste integrado

Leitura do código oficial **da tag 2.44.7** confirmou opção rawBody do Webhook, cópia base64 em binary.data e parser com teto de transporte em MiB. Caminho candidato: raw body original → parâmetro Postgres → decodificação UTF-8 → ingest(text). Reconstituir a partir de `$json.body` perderia a prova de chaves duplicadas e não foi adotado. A função SQL usa json antes de jsonb para detectar essas duplicatas. Fontes: [Webhook.node.ts](https://github.com/n8n-io/n8n/blob/n8n%402.44.7/packages/nodes-base/nodes/Webhook/Webhook.node.ts) e [body-parser.ts](https://github.com/n8n-io/n8n/blob/n8n%402.44.7/packages/cli/src/middlewares/body-parser.ts).

**Pendente:** provar raw body/Header Auth/malformed JSON/tamanhos/HTTP/ACK/deadlines no runtime n8n, verificar execuções sem headers/bodies persistidos, capturar macros reais e provisionar mapeamento. Não habilitado Code node, community package, proxy ou serviço novo. Transporte atual 1 MiB e limite lógico SQL 4 KiB são distintos; não afirmar rejeição HTTP 413 em 4 KiB.

### Ajustes do harness e limites

Primeira inicialização da fixture falhou porque a imagem exige senha bootstrap mesmo com host rejeitado; adicionada senha efêmera aleatória exclusiva, sem usar segredo do lab ou mudar autenticação do banco ativo. Outra tentativa falhou no quoting PowerShell 5.1 do probe; corrigido sem relaxar privilégios. Containers próprios dessas tentativas foram removidos no finally. Suítes posteriores passaram; essas falhas não são resultados de integração n8n/Zabbix.

IA-01–IA-14 continuam sem aceite completo: dados deste ensaio são fictícios e descartados com a fixture; não há incidente real persistido ou relatório integrado. Próxima etapa: gate do receptor n8n e jobs/outbox, antes de instalação/mapeamento/action no ambiente ativo. Sem commit/push automático.

## 8. Gate do receptor n8n — bloqueio real de segurança

Continuidade autorizada pela autora, com pedido de implementação objetiva. Criados candidato de seis nodes nativos (`workflows/incident-receiver.json`) e harness `Test-AutomationWebhook.ps1`/`tests/webhook-client.mjs`/`setup-webhook.sql`. Só fixtures n8n 2.44.7 e PostgreSQL 17.11, numa rede interna nova exclusiva, sem portas, volumes persistentes ou segredo/usuário/workflow do ambiente ativo. Senhas/header/key/bootstrap são aleatórios e exclusivos do ensaio; arquivos env temporários com ACL restrita removidos ao finalizar junto com containers/rede próprios. Nenhum Code node, community node, biblioteca nova, recurso cloud ou token administrativo Zabbix.

**Último resultado funcional: 105 verificações aprovadas antes do gate final; suíte reprovada em `execution_storage`. Não contar como IA-02/IA-03/T05 concluídos.**

Resultados anteriores à reprovação:

- Owner fictício criado por REST só no n8n de teste; editor/workflows sem sessão 401. Credenciais Header Auth e papel incident_ingest da fixture vinculados ao candidato somente ali. Publicação testou `/webhook/secureops-incidents-v1`, não webhook-test.
- Header ausente/errado negados sem alterar contagens. Content-Type incorreto devolveu 400. Preservação raw comprovada: JSON com chave duplicada passou pelo parser n8n, mas foi recusado 400 pelo SQL; não foi reserializado do objeto parsed.
- `rawBody` oferece cópia base64; a variável curta `$binary` omite o campo data nesta versão. Acesso correto por `$input.item.binary.data.data`, enviado no Query Parameters nativo como array, com SQL fixo decode/convert_from/ingest. Não foi necessário Code node.
- Aplicação/duplicata 200, conteúdo conflitante 409, inválidos 400. Macros/IDs/tipos/tempo/trigger desconhecidos, extra com marcador, SQL injection e JSON válido acima de 4096 bytes não alteraram contagens. Envelope mínimo de problem/recovery gerou fechamento/job; só fixture, não macro Zabbix real.
- JSON malformado devolveu **422** antes do workflow; corpo maior que 1 MiB devolveu **500**, não 413. Respostas não refletiram header/marcador fictícios; contagens de entregas/incidentes/jobs preservadas nesses negativos. Não alterar proxy/transporte para esconder divergência; registrar código real e ausência de falso sucesso.
- 20 POSTs concorrentes: **1 applied e 19 duplicate**, respostas 200. Diferente do ensaio SQL anterior, este passa pelo workflow real, mas com fonte fictícia.
- Mantendo lock SQL, o HTTP não respondeu durante espera observada de 700 ms; após liberar lock, commit e closed foram consultados e houve 200. Timeout interno 4s com role statement_timeout 5s devolveu **503 `{result:unavailable}`**, sem mudar contagens; retry posterior aplicou. Não é perda de ACK/crash, indisponibilidade total de banco ou prova de retries do Zabbix.

### Bloqueio encontrado

Na consulta do banco metadata **da fixture**, `execution_data` tinha **36 linhas no total**. Busca de presença em todas as linhas detectou tanto o marcador exclusivo do header de teste quanto o valor fictício Header Auth. Não foram exibidos/exportados valores ou linhas brutas. Flags globais success/error/manual/progress e settings do workflow estavam em none/false; ainda assim os valores estavam persistidos após as execuções. O teste falhou nessa asserção, em vez de reduzir o requisito ou apagar dados para ficar verde.

Leitura do código da tag confirmou o mecanismo: criação inicial persiste dados de execução; `deleteInFlightExecution`, quando pruning está ativo, marca para exclusão posterior. Portanto flags none não comprovam ausência de gravação em disco. Desabilitar pruning para apagar após finalizar também não demonstraria ausência da gravação inicial. Remover header em Set/Code posterior não é solução validada para esse ponto.

Fontes da tag: [ExecutionPersistence](https://github.com/n8n-io/n8n/blob/n8n%402.44.7/packages/cli/src/executions/execution-persistence.ts), [hooks de execução](https://github.com/n8n-io/n8n/blob/n8n%402.44.7/packages/cli/src/execution-lifecycle/execution-lifecycle-hooks.ts), [toSaveSettings](https://github.com/n8n-io/n8n/blob/n8n%402.44.7/packages/cli/src/execution-lifecycle/to-save-settings.ts) e [WorkflowDataProxy](https://github.com/n8n-io/n8n/blob/n8n%402.44.7/packages/workflow/src/workflow-data-proxy.ts).

### Falhas intermediárias e próximo passo

Primeiro setup de owner fictício excedeu o limite de senha de 64 caracteres; gerador corrigido, sem mudar política. O registro do webhook é assíncrono: chamada logo após activate obteve 404; fixture passou a aguardar presença na tabela antes do ensaio. A tentativa inicial com `$binary` foi negada 400; corrigida após inspecionar a API de dados. Expectativa 413 foi substituída pela observação 500 no teto de transporte. Essas correções do harness não validam o gate final, que continua reprovado por persistência.

**Nenhuma migração/workflow/credencial instalada no ambiente ativo; nenhum segredo real exposto nessa falha.** Somente tokens/marcadores descartáveis da fixture existiram no banco efêmero, removido no finally. Não alterar arquitetura silenciosamente: recomendação pendente é receptor TypeScript mínimo dedicado para autenticação/validação/commit/ACK, deixando n8n com snapshots sanitizados de relatórios. Exige aprovação e revisão de A-D02/fluxo da SPEC; não foi implementado serviço adicional. IA local/SMTP e jobs/outbox continuam no escopo da entrega, sem ações corretivas. Sem commit/push automático.

Reexecução final reproduziu **36 linhas execution_data, hasMarker=true, hasHeaderKey=true, malformedJsonStatus=422, overTransportLimitStatus=500, 1 applied/19 duplicate**. Asserção de segurança falhou, como deve; harness confirmou **11 serviços preservados** por ID/start time/running no finally. Revisão estática aprovou sintaxe PowerShell/JS/JSON e 24 destinos locais nos dez arquivos então novos/alterados; varredura limitada sem correspondência a segredos locais selecionados. Nenhum container/rede/pasta temporária da fixture pendente. Não houve varredura integral de todos os logs da fixture aprovada pelo harness, pois o gate anterior interrompeu essa fase; diagnóstico final exibiu somente mensagens selecionadas/sanitizadas, sem payload exportado.

## 9. Revisão documental autorizada após o bloqueio

Questionada sobre revisar a arquitetura antes de acrescentar serviço, a autora escolheu **“Revisar SPEC (Recomendado)”**. Isso autoriza redigir/revisar o desenho, **não instalar o receptor agora**. SPEC/PLAN atualizados: receptor TypeScript mínimo com Node HTTP e um driver PostgreSQL fixado após gate, usando somente events/automation e sem porta no host; papel incident_ingest e segredo do webhook exclusivos dele. N8n proposto fora de events, só com papel incident_report e snapshots sanitizados para IA/HTML/SMTP; incidentes/jobs seguem sendo registrados quando n8n está offline.

A revisão explicita que flags none/false do n8n minimizam retenção, mas não impedem gravação inicial de dados sanitizados de relatório; headers/eventos brutos/segredos de entrada **não entram no n8n**. A autora aprovou depois a revisão e a implementação dedicada; os gates técnicos permanecem separados.

## 10. Receptor TypeScript aprovado e validado isoladamente

Após a autora aprovar explicitamente **“aprovado! pode implementar”**, implementados `apps/incident-receiver/` (servidor HTTP, driver PostgreSQL, Dockerfile e probe), e harness efêmero `scripts/Test-IncidentReceiver.ps1`. O n8n foi retirado de `events`; Zabbix permanece sem essa rede/action. Na promoção controlada, somente n8n foi recriado; owner/workflow/credential counts mínimos permaneceram iguais. Os outros dez serviços existentes mantiveram ID, StartedAt e estado running.

| Ensaio | Resultado |
| --- | --- |
| Testes HTTP unitários em container sem rede/rootfs read-only | 25 aprovados; autenticação antes do corpo, header repetido/errado, corpo/chunked >4 KiB, UTF-8, deadline, desconexão, persistência e respostas sanitizadas |
| PostgreSQL 17.11 + receptor efêmeros, fase main | **139 checks**; concorrência **1 applied/19 duplicate**, rollback, commit, conflito, órfã/fora de ordem, duas collection e perda de ACK após commit/replay sem duplicação |
| Recriação do receptor mantendo DB fixture | **7 checks**; replay duplicado, recovery aplicado e incidente fechado após recriar somente o receptor |
| Banco offline | **4 checks**; HTTP 503 `unavailable`, sem falso sucesso |
| Logs/filesystem/limites da fixture | Logs apenas `{status,result,duration_ms}`, sem header/marcador; diff do rootfs estável após baseline dos mounts; UID 1000, read-only, 128 MiB, 1 CPU, nenhuma porta/volume. Pico cgroup observado **51,957,760 bytes**, sem OOM |
| Runtime após promoção | **80 checks** de infraestrutura; smoke interfaces confirmou liveness 200 e POST não autenticado 401 |

Os testes usam somente eventos, segredos, rede e banco descartáveis. Não demonstram aceitação das macros pelo Zabbix nem que o banco ativo tem schema/allowlist: **migração 001 segue não aplicada, nenhum incidente persistido no banco ativo e nenhuma integração Zabbix**. `/health` é liveness somente. Ainda pendentes: captura sanitizada de macros problem/recovery, mapeamento dos trigger IDs, migração/allowlist após validação, media type/action e integração ponta a ponta; jobs/outbox/IA/HTML e relatório SMTP local. Gmail/SMTP externo requer revisão independente de privacidade/segurança. Sem commit/push automático.
