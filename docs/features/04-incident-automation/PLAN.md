# PLAN 04 — Incidentes e relatórios com IA

**Estado:** validação integrada em 26/10/2026. Migrações 001–003/allowlist ativas; relatórios #4/#5 persistidos e recebidos no Mailpit. Prompt v1 rejeitado semanticamente; v2 identificado e entregue, mas revisão humana ainda pendente. Action/media types e workflows retomados. Diagnóstico confirmou expressão e transporte JSON inválidos, não travamento do Schedule Trigger. Registros failed anteriores preservados. Critérios completos e lacunas na [matriz de aceite](../../evidence/04-acceptance-matrix.md); não marcar entrega concluída. Token temporário deve ser revogado pela autora ao fim dos ensaios.

**Revisão aprovada para implementação:** após a revisão documental motivada pelo gate n8n reprovado, autora respondeu **“aprovado! pode implementar”**. Receptor TypeScript mínimo e n8n dedicado a relatórios sanitizados autorizados, incluindo decisões revisadas A-D02/A-D03/A-D04/A-D06/A-D07. Testar isoladamente antes de promover; macro/allowlist/action e integração real ainda pendentes. Não aplicar a migração ao banco ativo antecipadamente.

## 1. Gates e cuidados iniciais

**Orientação final para esta rodada:** autora solicitou fluxo mínimo funcional para validação de conceitos e entrevista, sem prolongar testes. Demo funcional entregue e integração retomada; endurecimento/aceite integral ficam explicitamente pendentes na matriz, sem marcar IA-01–IA-14 como aprovados. Prompt2 também alucinou causa no ensaio #7; preservar evidência e declarar limitação. [Roteiro curto](../../runbooks/interview-demo.md).

**Incremento autorizado para fechamento:** diagnóstico com progresso temporário autorizado pela autora; expressão do prompt e transporte JSON corrigidos. Incidente 4 gerou relatório v1/SMTP/Mailpit, mas revisão semântica rejeitou afirmação causal sem evidência. Próximo incremento: prompt v2 identificado, preservando v1 e todos os jobs anteriores; migração 003 permite revisão 2 sem reduzir validações. Restauradas flags warn/progress=false. Não concluir a entrega sem matriz IA-01–IA-14 verificada. A execução paralela de testes com reinícios invalidou as asserções finais de preservação de duas suítes; repetir sem reiniciar serviços simultaneamente.

- Entregas 01–03 concluídas; preservar credenciais, TOTP, grupos, volumes, API sem porta e configuração do monitoramento.
- Ao iniciar esta especificação, `README.md` e `docs/topology.html` já tinham alterações solicitadas pela autora; preservadas, sem revertê-las ou fazer commit automático.
- Fonte do comportamento é a SPEC; não duplicar parâmetros/decisões nesta lista. Aprovação do desenho não comprova que macros, versão n8n e opções de segurança funcionam.
- Nenhum token administrativo revogado pode ser reutilizado. Se necessário no futuro, novo token temporário via prompt local seguro; nunca enviar valores ao chat e revogar ao finalizar.
- Não marcar tarefa de runtime como concluída por análise estática ou documentação online. Instalação inicial/importação, execução de workflow, commit SQL e consulta persistente são provas diferentes.

## 2. Etapas propostas e validação

### T01 — Revisão e aprovação da SPEC

- [x] Ler README/arquitetura/roadmap e inspecionar Compose, export de disponibilidade e payloads/triggers de segurança existentes.
- [x] Conferir documentação oficial de Webhook Zabbix, Webhook/Postgres n8n, banco, chave e execução; registrar limites das fontes móveis/URLs ausentes.
- [x] Escrever contrato proposto, invariantes transacionais e critérios de aceite; revisar para A-D01–A-D10 e IA-01–IA-14 após a solicitação de IA/HTML/SMTP, sem inventar aprovação das escolhas técnicas/resultados.
- [x] Revisar conflitos e ambiguidades: duas triggers collection, recovery órfã, eventos invertidos, duplicação concorrente, ACK perdido, isolamento de bancos e exposição compartilhada editor/webhook.
- [x] Registrar IA como requisito obrigatório de relatório, não opcional/futuro; resolver proibição anterior em AGENTS.md e escopo documental compartilhado, sem autorizar IA externa ou ação corretiva.
- [x] Autora aprovar o fluxo funcional com IA local e relatório HTML enviado por SMTP local; resposta registrada: “aceito o fluxo proposto”. Não estender essa aprovação aos parâmetros técnicos ou à instalação.
- [x] Após aprovação do fluxo, autora solicitou “use a versao e modelo de IA que vc recomendar e inicie a implementação”. Baseline técnica A-D01–A-D10 adotada, com exceções locais previamente apresentadas e agora documentadas antes da subida; novos desvios ainda exigem revisão.
- [x] Após gate reprovado de persistência, autora autorizou **revisar a SPEC** para receptor mínimo dedicado. Desenho revisado redigido sem acrescentar serviço/driver/redes ao runtime.
- [x] Autora aprovou o desenho revisado e autorizou implementação: “aprovado! pode implementar”, após apresentação do receptor dedicado/n8n de relatórios. Gate técnico/aceites integrados continuam pendentes.

**Gate de autorização resolvido:** solicitação posterior autorizou início gradual e escolha técnica. Gate de infraestrutura dividido do contrato real: não criar action/media type/workflow produtivo enquanto o receptor/transação não estiver validado.

### T02 — Fechar viabilidade da versão e contrato real

- [x] Selecionado n8n 2.44.7 stable oficial, licença SUL compatível com uso pessoal local e manifestos Linux/digests conferidos; versão real confirmada. Tabela/digests na SPEC, migrações no PostgreSQL 17.11 separado executadas. Sem scanner/auditoria universal de vulnerabilidades.
- [x] Gate isolado do receptor: Node HTTP sem framework, `pg` 8.21.0 MIT fixado/lockado, autenticação antes do corpo, UTF-8/raw JSON/4 KiB, timeout/parametrização, logs categóricos e somente events/automation. 25 testes HTTP unitários e integração PostgreSQL real (139 checks principais, resume 7, offline 4); detalhes em evidências. Gate do editor/relatórios n8n permanece separado.
- [x] Fixar versões/digests Ollama/Mailpit e modelo/quantização/licença; confirmar configuração sem cloud/relay, saída estruturada e limites, SMTP/UI auth, armazenamento persistente e portas. Inferência real sintética testada; limites de carga e workflow ainda não comprovados.
- [ ] Verificar se nodes nativos bastam **para relatórios sanitizados** sem Code/task runner adicional. Para ingestão direta, o candidato nativo foi reprovado e motivou a revisão do receptor; não adicionar dependência silenciosa.

**Bloqueio identificado no gate isolado:** nodes nativos atenderam raw body/auth/transação, mas n8n 2.44.7 persistiu header/marcador fictícios em execution_data apesar das flags. Candidato não publicado; não usar pruning/Code para mascarar gravação inicial. A autora aprovou depois a revisão e a implementação do receptor dedicado. A execução isolada passou, mas macros/mapeamento real e instalação funcional no banco/Zabbix permanecem gates separados.
- [ ] Conferir macros e parâmetros do Zabbix 7.0.32, destinatário/permissões, action restrita, problem/recovery e comportamento de retry/timeout.
- [ ] Com autorização/credencial de teste exclusiva, capturar mensagens reais sanitizadas no receptor revisado ou fixture autenticada na rede Compose, sem porta no host/alterar API. Começar por host/trigger fictícios próprios; validar depois contexto real da action autorizada. Não usar o candidato n8n reprovado.
- [ ] Registrar amostras mínimas resolvidas, vínculo problem↔recovery e campos ausentes, sem headers/segredos/dados brutos. Resolver IDs da allowlist local por leitura, sem fixar IDs de outra instalação.
- [x] Conferir recursos/portas, imagem/usuário/bootstrap, limites e exceções HTTP/cookies/SMTP/rede da inferência. Incertezas restantes (carga/workflows/egress) são explicitadas; não retirar IA do aceite nem mudar para API externa silenciosamente.

**Validação:** IA-01; resultado documental estático não comprova esse gate. Desabilitar ações de teste ao terminar e limpar somente recursos efêmeros criados pela invocação; não excluir eventos reais/volumes existentes.

### T03 — Infraestrutura mínima após aprovação/gate

- [x] Overlay/profile automation, redes internas e operations implementados; comparação estática preserva integralmente os sete serviços anteriores e runtime preservou seus IDs/start times. Server Zabbix ainda sem events/action, sem interrupção.
- [x] Somente volumes/segredos novos, inicializador recusa pasta existente, ACL restrita/Git/build excluídos e mounts read-only; chave estável não exibida.
- [x] automation-db com bancos n8n/incidents e papéis separados sem superuser/create; nenhuma escrita/grant no banco Zabbix. TCP com senha, acesso cruzado e senha errada negados; sem porta no host.
- [ ] Concluir sessão/logout/cookie/relogin do editor com a autora. Owner criado e editor aberto foram confirmados pela autora; workflow ainda não publicado, endpoints de dados sem sessão negados 401 e ownerConfigured=true após recriação do n8n.
- [x] Verificar Compose resolvido/runtime: 80 checks, bindings reais, redes, não root, caps, filesystem read-only, mounts/segredos por arquivo e limites; smoke de interfaces atualizado confirma receptor liveness 200 e negação sem chave 401. Não prova integração Zabbix/banco funcional.
- [x] Ollama/Mailpit em redes próprias, sem porta de inferência/SMTP no host; UI da caixa autenticada em 127.0.0.1:8025. Modelo pré-carregado por loader administrativo efêmero, removido sem apagar volume; todos os blobs/manifestos verificados. SMTP autenticado e mensagem fictícia vista na API da caixa; não e relatório real.
- [x] Após aceite da revisão: receptor restrito no profile automation, segredos webhook/ingest exclusivos e sem porta; n8n fora de events. Somente n8n foi recriado; metadata mínima owner/workflows/credentials preservada e dez serviços mantiveram ID/start time/running. Pico de memória observado do receptor 51,957,760 bytes na fixture, sem OOM; não é teste de carga.

**Incremento inicial de T02/T03:** 66 verificações de configuração/runtime, seis testes isolados de integridade, interfaces/negações, isolamento de bancos e inferência real sintética em 23740ms/150 tokens aprovados. Pico de memória cgroup observado do Ollama: 1160585216 bytes (sem OOM), não teste de carga. Flags de não salvamento/cloud/telemetria e allowlist conferidas; persistência de payloads e contrato de workflow ainda pendentes.

**Validação:** IA-02. Não declarar isolamento absoluto, egress bloqueado ou TLS onde não existe.

### T04 — Modelo transacional e consulta read-only

- [x] Escrever migração 001 restrita ao banco incidents: ledger/ciclos/incidentes, identidade e índice parcial de único open; execução atômica e recusa de reaplicação testadas em cluster efêmero. Aplicada junto à migração 002 no banco ativo após autorização para staging; quatro IDs confirmados allowlisted, zero deliveries/eventos.
- [x] Rotina parametrizada incident.ingest(text), validação raw JSON/duplicatas/mapeamento/horários, lock na condição pré-provisionada antes do primeiro ciclo, permissões mínimas e rollback de fechamento+ledger+job verificados isoladamente. Gate de deadline/query/HTTP n8n ainda pendente.
- [x] Transições da SPEC testadas diretamente em PostgreSQL 17.11 efêmero: duas collection independentes, órfãs/inversões/ciclos antigos/novos e 20 chamadas realmente bloqueadas simultaneamente (1 applied/19 duplicate); dois ciclos concorrentes (1 applied/1 conflict) e timeout de lock sem escrita. Não substitui concorrência via receptor revisado.
- [x] Na fixture PostgreSQL, SET ROLE verificou EXECUTE permitido e SELECT/DML/DDL negados para ingest; leitor restrito a views e sem ingest/escrita; report sem alteração de incidentes; metadados n8n sem EXECUTE privilegiado. Repetir/confirmar ao provisionar o banco ativo.
- [x] Aplicar migrações 001/002 e allowlist real no banco ativo; conferidos schema versions 1/2, quatro condições e zero deliveries. Script recusa schema preexistente/reaplicação; action continua desabilitada até conferir macros no ciclo real.
- [x] Jobs persistentes, lease/compare-and-set, validação da análise, HTML escapado, outbox e rotinas de relatório implementados/testados em fixture. Ainda sem aplicação ativa nem integração n8n.
- [ ] Disponibilizar consulta read-only após migração no banco ativo; views exercitadas somente na fixture.

**Validação:** parte de IA-03/IA-05/IA-06; sucesso SQL isolado ainda não é integração n8n/Zabbix.

### T05 — Receptor revisado, media type e action

- [x] Implementar receptor HTTP TypeScript mínimo: header exclusivo/limites → UTF-8/raw JSON → chamada SQL parametrizada → resposta mínima após resolução do commit. Sem framework, shell, API administrativa ou persistência própria; falhas categóricas/503 sem falso 2xx/stack. Validado em build e runtime efêmeros.
- Histórico: candidato `infra/automation/workflows/incident-receiver.json`/`Test-AutomationWebhook.ps1` foi exercitado só em fixture; apesar de transições e concorrência aprovadas, **gate execution_storage falhou** ao persistir header/marcador no banco n8n. Nunca publicar esse candidato. A decisão posterior foi substituir por serviço dedicado autorizado.
- [x] Nos ensaios HTTP/SQL, header/corpo/marcador ausentes dos logs categóricos; filesystem do receptor sem escrita após baseline de mounts; n8n não recebeu segredo de ingestão e não participou da ingestão. Limite: crash/logs de todo runtime e futuras execuções de relatório sanitizado requerem gates próprios; flags do n8n não significam ausência de gravação inicial.
- [x] Versionar configuração/contrato e validar build repetível sem segredos/IDs reais. Não publicar URL de webhook n8n para ingestão; workflows futuros serão somente de relatórios.
- [x] Script Webhook e dois media types Zabbix problem/recovery importados/desabilitados: destino interno fixo, JSON serializado, segredo em macro, mapeamento dos quatro triggers e erros sanitizados. Quatro testes JS passam; expansão real das macros pendente.
- [x] Conectar Zabbix server à rede Compose `events`; DNS e HTTP `/health` do receptor confirmados, sem porta publicada. Container Zabbix server recriado e rodando.
- [x] Criar grupo/usuário de serviço sem login no frontend, leitura somente ao host group que contém apenas `secureops-api`; mídias Webhook 72/73 vinculadas ao usuário com destino local fictício.
- [x] Criar action IDs 25229–25232 + host 10684, problem 72 e recovery 73, sem update/comandos. Habilitada para um ciclo controlado e pausada após falha no processamento do relatório; macros problem/recovery validadas no evento real.
- [ ] Executar negativos de autenticação/contrato, macro não resolvida, horário/ID/trigger desconhecidos, injeção e corpo grande; comparar banco antes/depois sem exportar seu conteúdo bruto.

**Validação:** IA-03 e base de IA-04/IA-05. Workflow verde não comprova idempotência nem ACK correto.

### T06 — Concorrência, fora de ordem e falhas de entrega

- [x] Repetição e 20 envios concorrentes via receptor HTTP + PostgreSQL efêmero: 1 applied/19 duplicate; replay, conflito, primeira condição sem ciclo, falha/rollback e banco offline verificados. 139 checks principais; nenhum banco ativo alterado.
- [ ] Testar recovery órfã/antecipada seguida de problem, retry de problem já fechado, recovery antiga com novo ciclo, ciclos invertidos e horários incompatíveis, conforme tabela da SPEC.
- [ ] Parar somente receptor e, separadamente, automation-db: monitor segue coletando; sem sucesso fabricado e retries/esgotamento observáveis. Em ensaio separado, n8n offline deve preservar registro de incidentes/jobs pelo receptor e atrasar somente relatórios.
- [x] Simular perda de ACK após commit por proxy efêmero do harness, sem endpoint de falha no serviço; replay idêntico retornou duplicate sem incidente duplicado.
- [ ] Retomar dependências no finally, com prazos finitos; ensaiar replay autorizado após esgotamento e mostrar limites quando evento original não está mais disponível.

**Validação:** IA-05–IA-07. Distinguir fixture HTTP/banco isolado de media type/Action log e workflow reais. Não confiar em “retry on fail” configurado como evidência de entrega observada.

### T07 — Ciclos reais integrados

- [ ] Combinar com a autora dois ciclos de parada **somente da API**; manter monitor, receptor, n8n e bancos ativos. Usar rede Compose para probes, nunca publicar porta da API.
- [x] Um ciclo real de disponibilidade: evento problem 153/recovery 154, trigger 25229, duas entregas `applied`, incidente 1 fechado e duração 80 s; API restaurada saudável. Não cobre dois ciclos nem outros triggers.
- [ ] Reutilizar o procedimento seguro da entrega 03 para um ciclo real de LOGIN_ERROR, sem alterar senha/TOTP/grupos ou proteção do realm; cinco eventos observados não significam cinco submissões exatas.
- [ ] Com autenticação aberta, falha de fonte/coletor autorizada: incidente técnico independente e autenticação preservada até nova contagem válida e recovery correto. Cobrir ambas as condições collection, com origem real/fixture explicitada.
- [ ] Autora confirmar operadora+TOTP permitida e visitante+TOTP 403 em intervalo limpo; verificar que autorização negada não gerou incidente de login.

**Validação:** IA-04/IA-09. Medir detecção, entrega, commit/resposta separadamente; tempo observado não é SLA.

### T08 — Persistência e importação reproduzível

- [ ] Snapshot mínimo selecionado de incidentes open/closed, ledger, pendências, workflow e metadados públicos; sem export de credenciais ou dump de bancos.
- [ ] Recriação do receptor stateless validada na fixture e no runtime; deduplicação persistiu no PostgreSQL efêmero. Ainda falta ensaio autorizado de reinício/recriação do automation-db/n8n preservando volumes e confirmação manual de login/credenciais.
- [ ] Repetir evento antigo e verificar duplicate; completar pendência e fechar open correspondente; novo ciclo cria novo incidente. Igualdade de snapshot sozinha não satisfaz esses comportamentos.
- [ ] Importar workflow sanitizado em ambiente isolado de teste ou procedimento de reinstalação previamente aprovado, com credenciais fictícias próprias; não sobrescrever workflow ativo/segredos para “provar importação”.

**Validação:** IA-08 e parte de IA-10; não afirmar backup/HA ou proteção de queda do host.

### T09 — Relatórios com IA e HTML seguro

- [x] Workflows `SecureOps - Incident Report` e `SecureOps - Mail Delivery` confirmados, publicados individualmente e n8n reiniciado; execuções ficaram `running` antes de processar os nodes, job real esgotou duas tentativas e falhou por lease expirada. Ambos despublicados para evitar acumular execuções. Autora confirmou nodes funcionando no editor; runtime integrado não passou.
- [ ] Persistir snapshot, versão de modelo/prompt/template e análise validada. Separar fatos e hipóteses; não atribuir capacidade preditiva validada, causa raiz ou risco percentual sem base. Histórico insuficiente deve aparecer como limitação.
- [ ] Executar inferência **real** com snapshot de incidente e revisar conteúdo em português com a autora; fixture/determinismo não substituem evidência da IA. Registrar identidade do modelo e tempos/memória sem salvar segredos ou chain-of-thought.
- [ ] Testar prompt injection, XSS/HTML/URLs do modelo, dados ausentes, saída inválida/truncada/grande, referências inexistentes e números inventados; verificar que facts do template vêm do banco e texto do modelo é identificado como análise não verificada automaticamente.
- [ ] Testar Ollama offline/timeout, duas tentativas finitas, lease expirada/crash/concorrência e retomada sem job/outbox duplicados. Fallback factual claramente sem IA; não usar fallback como único caso de aceite.
- [ ] Validar HTML/texto no navegador e limites de tamanho; sem scripts, recursos remotos, URLs ou CSS controlados pelo modelo. Sem alterar o estado dos incidentes por resultado da IA.

**Validação:** IA-11/IA-12 e parte de IA-13/IA-14. Uma chamada HTTP ao modelo com status 200 não comprova conteúdo correto, relatório seguro ou recebimento SMTP.

### T10 — SMTP local, caixa e retomada do envio

- [x] Workflow Mail Delivery confirmado com SMTP account vinculada; foi publicado durante o ensaio e depois despublicado junto ao workflow de geração, pois execuções não avançaram do Schedule Trigger. Readiness/interface n8n passaram após restart. Nenhum envio de relatório ocorreu pelo workflow.
- [ ] Enviar relatório com **análise de IA real** e confirmar via SMTP e na caixa Mailpit; autora visualizar HTML pela UI protegida, com identificador rastreável e aviso de hipótese/prevenção. Não afirmar entrega em caixa pessoal externa.
- [ ] Testar SMTP offline/erro antes de aceitação, retries limitados, concorrência e crash após possível aceitação: delivery_unknown sem reenvio cego, inspeção local pelo identificador, reconciliação/reenvio explícito. Não prometer exactly-once por usar Message-ID/assunto repetido.
- [ ] Reiniciar/recriar n8n, inferência e Mailpit com volumes mantidos: relatório/outbox, identidade do modelo e mensagem local preservados. Job em sending após crash não volta automaticamente a pending; demonstrar comportamento.
- [ ] Comparar coleta/triggers e acesso/MFA com inferência ativa; verificar recursos/bindings reais e ausência de envio externo. Evidenciar diferença entre geração real, fallback, aceitação SMTP e leitura da caixa.

**Validação:** IA-11/IA-13/IA-14. Caixa local de testes não é serviço de e-mail externo nem garantia de entrega fora do host.

### T11 — Regressão, evidências e fechamento

- [ ] Reexecutar suites API/identidade/coletor/configuração e verificações de infraestrutura da entrega 03 disponíveis, mais novas suites de contrato/estado/transação/integração. Registrar contagens reais, não prever resultados.
- [ ] Verificar API sem portas/mounts, grupos/MFA/credenciais preservados, quatro widgets e coleta/triggers não alterados; separação de runtime n8n e monitoramento.
- [ ] Runbook de instalação/configuração, consulta read-only, parada/retomada, retries/replay, pendências/conflitos, chave estável e limites de retenção. Documentar passos manuais de owner/credenciais e revogação de acesso temporário.
- [ ] Evidências sanitizadas: payload mínimo problem/recovery, Action log sem segredo, consultas/IDs/horários/duração e negativos. Revisar logs, exports, execuções, Git e links; distinguir análise estática/runtime/navegador/fixture.
- [ ] Somente com IA-01–IA-14 aprovados, incluindo IA real e recebimento HTML no SMTP local, concluir entrega e atualizar roadmap/README/arquitetura/topologia. Sem commit/push automático.

## 3. Artefatos e estado

| Caminho candidato | Finalidade |
| --- | --- |
| `compose.automation.yaml`, `compose.monitoring.yaml` | Receptor + conexão Zabbix pela rede interna `events`, sem porta publicada; alteração ainda não promovida ao runtime Zabbix |
| `infra/monitoring/incident-media-types.yaml`, `incident-webhook.js` | Media types problem/recovery importados/desabilitados; macros reais ainda precisam validação |
| `infra/automation/migrations/`, `workflows/` | Migrações 001/002 aplicadas ao banco ativo; workflows Incident Report/Mail Delivery presentes e inativos |
| `scripts/` | `Install-IncidentSchema.ps1` protegido pelo gate de macros; testes de infraestrutura, SQL, receptor e integração JS |
| `.local/automation/` | Criado e ignorado, ACL restrita, sem sobrescrever segredos existentes |
| `docs/runbooks/incident-automation.md` | Parcial: instalação e testes iniciais exercitados |
| `docs/evidence/04-incident-automation.md` | Evidências iniciais, sem afirmar IA-01–IA-14 concluídos |

Receptor customizado foi autorizado após revisão da SPEC. O runtime está implementado e ativo, mas não é receptor funcional de eventos até aplicar migração/allowlist e integrar action Zabbix, após contrato real de macros e mapeamento aprovado.

## 4. Registro desta revisão

| Data | Trabalho executado | Resultado e limite |
| --- | --- | --- |
| 26/10/2026 | Leitura do estado documentado e implementação versionada de monitoramento | Quatro triggers e duas collection confirmadas estaticamente; sem consultar secrets/banco/API autenticada |
| 26/10/2026 | Consulta documental e redação/revisão de SPEC/PLAN | Contrato local e decisões propostos, riscos/gates identificados; nenhum runtime implementado/testado e nenhuma aprovação presumida |
| 26/10/2026 | Validação documental local | 47 destinos de links locais existentes nos cinco documentos revisados, blocos Markdown fechados, sete decisões/dez critérios presentes e git diff --check aprovado. URLs externas/âncoras não validadas por essa checagem; sem testes de containers/navegador nesta tarefa |
| 26/10/2026 | Revisão de escopo solicitada pela autora | IA gerando relatórios passou a requisito da entrega 04, com HTML/SMTP local. SPEC/PLAN ampliados para dez decisões e 14 critérios; proposta local Ollama/Mailpit, jobs/outbox, limites de previsão e falhas explícitos. Fontes oficiais de geração, SMTP e Mailpit consultadas; nenhum modelo baixado, relatório/e-mail real gerado ou implementação autorizada |
| 26/10/2026 | Validação da revisão com IA | 47 destinos locais existentes nos documentos revisados, blocos Markdown e dois SVGs bem-formados, dez decisões/14 critérios presentes e whitespace aprovado. Sem validar âncoras, inferência, recursos ou SMTP em runtime |
| 26/10/2026 | Aprovação funcional da autora | “aceito o fluxo proposto”: Zabbix → n8n → incidentes → IA local → HTML → SMTP local. Fluxo aprovado; versões/modelo/recursos/frequência/transporte e autorização executável continuam pendentes, sem presumir validação ou implementação |
| 26/10/2026, após solicitação executável | Início autorizado e seleção técnica | Autora delegou versão/modelo e pediu implementação. Versões/digests na SPEC; infraestrutura/segredos novos, owner manual, seis testes de integridade e 66 checks de infraestrutura, modelo sintético real e SMTP fictício aprovados. Sete serviços existentes preservados; nenhuma action/workflow/credencial administrativa Zabbix reutilizada |
| 26/10/2026, 12:39 -03:00 | Revisão do incremento | Sintaxe 6 PowerShell/2 Bash/3 JS, 99 destinos locais, whitespace e recusa de sobrescrita aprovados; varredura limitada de 108 arquivos e 691 linhas de logs novos sem correspondências selecionadas. Integração de incidentes/relatórios e IA-01–IA-14 permanecem pendentes |
| 26/10/2026, incremento SQL isolado | Núcleo transacional e parser raw | Migração 001 e harness Test-AutomationIncidents: **86 checks SQL**, concorrência de 20 duplicatas/2 primeiros ciclos, timeout de lock e recusa de reaplicação aprovados em PostgreSQL efêmero sem rede/volume persistente. Onze serviços preservados; regressões de infraestrutura/banco/interfaces/coletor/disponibilidade aprovadas. Banco ativo e Zabbix sem alteração. Leitura do rawBody da tag n8n é evidência estática, não gate de webhook concluído |
| 26/10/2026, gate de receptor | Candidato nativo e fixture n8n/PostgreSQL | 105 verificações passaram antes do gate final; header/auth/raw JSON/concorrência/commit/503 funcionaram. **Gate de segurança reprovado:** 36 linhas execution_data no total, com presença de header/marcador fictícios detectada apesar de none/false; limpeza posterior não equivale a não gravar. Recursos próprios removidos, sem instalar migração/workflow/credenciais no ambiente ativo. Revisão de arquitetura pendente de decisão da autora |
| 26/10/2026, após resultado do gate | Autorização de revisão documental | Autora escolheu “Revisar SPEC (Recomendado)”. SPEC/PLAN revisados para receptor mínimo dedicado, redes/papéis separados, códigos/limites e n8n somente para relatórios sanitizados. Nenhum serviço/driver adicionado ou configuração ativa alterada; revisão/aceite da implementação permanece pendente |
| 26/10/2026, após aprovação da revisão | Receptor dedicado isolado e promoção restrita | 25 testes HTTP unitários; PostgreSQL 17.11 efêmero: 139 checks principais, 7 resume, 4 offline; 1 applied/19 duplicates concorrentes, ACK perdido após commit sem duplicação, rollback, timeout e banco offline 503. Runtime rootfs read-only, UID 1000, 128 MiB/1 CPU, sem porta; memória fixture 51,957,760 bytes. Somente n8n recriado, metadata mínima preservada; dez serviços mantiveram IDs/start times. Nenhuma migração/allowlist/action instalada em Zabbix/banco ativo. |
| 26/10/2026, smoke pós-promoção | Infraestrutura/runtime e interfaces | 80 checks runtime e interfaces: liveness receptor 200, POST sem segredo 401; n8n readiness/negações e Mailpit auth aprovados. Confirma exposição/configuração, não ingestão funcional ou ligação Zabbix. |

## 5. Checklist de prontidão

- [x] Requisito de IA para gerar relatórios confirmado pela autora e incorporado à entrega, não transferido para etapa futura.
- [x] Fluxo funcional com IA local, HTML e SMTP local aprovado pela autora.
- [x] Baseline inicial A-D01–A-D10 adotada sob autorização anterior, sem cloud; revisão documental do receptor autorizada posteriormente.
- [x] Revisão de A-D02/A-D03/A-D04/A-D06/A-D07 aceita antes de implementar receptor dedicado, conforme autorização posterior explícita.
- [ ] Gate de versão/licença/segurança/recursos encerrado, com opções verificadas no patch.
- [ ] Contrato problem/recovery observado e sanitizado; mapeamento/IDs reais resolvidos.
- [x] Autorização explícita posterior para início de implementação e escolha de versão/modelo.

**Próxima ação:** completar os gates reais pendentes da matriz (especialmente autenticação integrada/403 e revisão humana de relatório, falhas/retries SMTP e injeção/renderização). Diagnóstico do agendamento encerrado; relatórios reais e persistência/replay já observados. Preservar jobs failed e relatórios rejeitados, não reenfileirar por SQL. Nenhum aceite manual presumido; entrega em validação, não concluída.
