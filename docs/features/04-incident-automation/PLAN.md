# PLAN 04 — Incidentes e relatórios com IA

**Estado:** em implementação inicial desde 26/10/2026, após a autora delegar escolha de versão/modelo e solicitar início. Infraestrutura com n8n 2.44.7, Ollama 0.40.11/Qwen2.5 1.5B Q4_K_M, PostgreSQL separado e Mailpit 1.32.0 ativa; owner criado pela autora. Inferência e SMTP isolados testados; **sem workflows ou integração Zabbix ainda**. Resultados/limites nas [evidências 04](../../evidence/04-incident-automation.md).

## 1. Gates e cuidados iniciais

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

**Gate de autorização resolvido:** solicitação posterior autorizou início gradual e escolha técnica. Gate de infraestrutura dividido do contrato real: não criar action/media type/workflow produtivo enquanto o receptor/transação não estiver validado.

### T02 — Fechar viabilidade da versão e contrato real

- [x] Selecionado n8n 2.44.7 stable oficial, licença SUL compatível com uso pessoal local e manifestos Linux/digests conferidos; versão real confirmada. Tabela/digests na SPEC, migrações no PostgreSQL 17.11 separado executadas. Sem scanner/auditoria universal de vulnerabilidades.
- [ ] Verificar listener, owner login, Header Auth, respostas após commit, parser/raw body, limite de payload, timeouts/query parameters, secrets por arquivo, diretórios/usuários/volumes e desabilitação de telemetria/IA cloud/recursos externos, preservando inferência local de relatório.
- [ ] Fixar versões/digests Ollama/Mailpit e modelo/quantização/licença; confirmar configuração sem cloud/relay, saída estruturada e limites reais, SMTP/UI auth, armazenamento persistente e portas candidatas. Conferir viabilidade CPU/memória com todo o lab antes de carregar o modelo.
- [ ] Decidir se nodes nativos bastam sem Code/task runner adicional; incompatibilidade exige revisão, não dependência silenciosa.
- [ ] Conferir macros e parâmetros do Zabbix 7.0.32, destinatário/permissões, action restrita, problem/recovery e comportamento de retry/timeout.
- [ ] Com autorização e credencial de teste exclusiva, capturar mensagens reais sanitizadas em receptor n8n protegido ou fixture temporária autenticada na rede Compose, sem porta pública e sem alterar API. Começar por host/trigger fictícios próprios; validar depois contexto real da action autorizada.
- [ ] Registrar amostras mínimas resolvidas, vínculo problem↔recovery e campos ausentes, sem headers/segredos/dados brutos. Resolver IDs da allowlist local por leitura, sem fixar IDs de outra instalação.
- [ ] Conferir recursos/portas livres, imagem/usuário/bootstrap, limites e exceções HTTP/cookies/SMTP/rede da inferência. Se um gate falhar, atualizar SPEC e pedir decisão antes de workaround; não retirar IA do aceite nem mudar para API externa silenciosamente.

**Validação:** IA-01; resultado documental estático não comprova esse gate. Desabilitar ações de teste ao terminar e limpar somente recursos efêmeros criados pela invocação; não excluir eventos reais/volumes existentes.

### T03 — Infraestrutura mínima após aprovação/gate

- [x] Overlay/profile automation, redes internas e operations implementados; comparação estática preserva integralmente os sete serviços anteriores e runtime preservou seus IDs/start times. Server Zabbix ainda sem events/action, sem interrupção.
- [x] Somente volumes/segredos novos, inicializador recusa pasta existente, ACL restrita/Git/build excluídos e mounts read-only; chave estável não exibida.
- [x] automation-db com bancos n8n/incidents e papéis separados sem superuser/create; nenhuma escrita/grant no banco Zabbix. TCP com senha, acesso cruzado e senha errada negados; sem porta no host.
- [ ] Concluir sessão/logout/cookie/relogin do editor com a autora. Owner criado e editor aberto foram confirmados pela autora; workflow ainda não publicado, endpoints de dados sem sessão negados 401 e ownerConfigured=true após recriação do n8n.
- [ ] Verificar Compose resolvido, bindings reais, redes, não root, caps, filesystem, mounts, segredo por arquivo, logs/telemetria e consumo com sete serviços existentes mais os novos.
- [x] Ollama/Mailpit em redes próprias, sem porta de inferência/SMTP no host; UI da caixa autenticada em 127.0.0.1:8025. Modelo pré-carregado por loader administrativo efêmero, removido sem apagar volume; todos os blobs/manifestos verificados. SMTP autenticado e mensagem fictícia vista na API da caixa; não e relatório real.

**Incremento inicial de T02/T03:** 66 verificações de configuração/runtime, seis testes isolados de integridade, interfaces/negações, isolamento de bancos e inferência real sintética em 23740ms/150 tokens aprovados. Pico de memória cgroup observado do Ollama: 1160585216 bytes (sem OOM), não teste de carga. Flags de não salvamento/cloud/telemetria e allowlist conferidas; persistência de payloads e contrato de workflow ainda pendentes.

**Validação:** IA-02. Não declarar isolamento absoluto, egress bloqueado ou TLS onde não existe.

### T04 — Modelo transacional e consulta read-only

- [x] Escrever migração 001 restrita ao banco incidents: ledger/ciclos/incidentes, identidade e índice parcial de único open; execução atômica e recusa de reaplicação testadas em cluster efêmero. **Não aplicada ao banco ativo**; allowlist real ainda pendente.
- [x] Rotina parametrizada incident.ingest(text), validação raw JSON/duplicatas/mapeamento/horários, lock na condição pré-provisionada antes do primeiro ciclo, permissões mínimas e rollback de fechamento+ledger+job verificados isoladamente. Gate de deadline/query/HTTP n8n ainda pendente.
- [x] Transições da SPEC testadas diretamente em PostgreSQL 17.11 efêmero: duas collection independentes, órfãs/inversões/ciclos antigos/novos e 20 chamadas realmente bloqueadas simultaneamente (1 applied/19 duplicate); dois ciclos concorrentes (1 applied/1 conflict) e timeout de lock sem escrita. Não substitui concorrência via workflow.
- [ ] Conferir SELECT/EXECUTE necessários e negação de DDL/DML direto/acesso aos bancos alheios; validar owner/search_path se houver função privilegiada.
- [ ] Disponibilizar consulta no banco ativo; views incident_summary/pending_recoveries/delivery_summary/report_job_summary já criadas e exercitadas sob papel read-only **somente na fixture**, sem porta ou SQL arbitrário via webhook.
- [ ] Completar jobs: reserva única/snapshot sanitizado já criados no mesmo commit de encerramento e testados isoladamente; lease/compare-and-set, saída/HTML/outbox e rotinas do papel de relatório ainda pendentes. Papel report não pode executar ingest nem mudar incidentes. Não manter transação aberta durante IA/SMTP.

**Validação:** parte de IA-03/IA-05/IA-06; sucesso SQL isolado ainda não é integração n8n/Zabbix.

### T05 — Workflow, media type e action

- [ ] Workflow: Webhook POST com Header Auth → validação/mapeamento estritos → chamada transacional nativa parametrizada → resposta mínima após commit. Tratar erro do node/banco sem falso 2xx ou stack trace.
- [ ] Configurar não salvamento de payloads de execuções, inclusive erro/manual/progresso; inspecionar a persistência efetiva com marcadores fictícios de headers/corpos, não só as flags.
- [ ] Exportar workflow sem credenciais/IDs sensíveis, documentar importação e vínculo manual a credenciais novas. Publicar URL de produção, não URL de teste.
- [ ] Media type com destino fixo, serialização JSON, erro sanitizado, autenticação exclusiva e retries limitados conforme gate. Sem log de parâmetros/header e sem URL derivada do evento.
- [ ] Action habilitada somente para instância/host/triggers permitidos; envio inicial e recovery, sem update ou comandos. Evidenciar usuário/mídia/permissões e parâmetros reais antes do teste.
- [ ] Executar negativos de autenticação/contrato, macro não resolvida, horário/ID/trigger desconhecidos, injeção e corpo grande; comparar banco antes/depois sem exportar seu conteúdo bruto.

**Validação:** IA-03 e base de IA-04/IA-05. Workflow verde não comprova idempotência nem ACK correto.

### T06 — Concorrência, fora de ordem e falhas de entrega

- [ ] Repetição sequencial e 20 envios concorrentes via workflow real; mesmo event_id com conteúdo conflitante; primeira condição ainda sem linha. Conferir contagens, constraints e estado persistido.
- [ ] Testar recovery órfã/antecipada seguida de problem, retry de problem já fechado, recovery antiga com novo ciclo, ciclos invertidos e horários incompatíveis, conforme tabela da SPEC.
- [ ] Parar somente n8n e, em ensaio separado, automation-db: monitor segue coletando; emissor não recebe sucesso fabricado e tentativas/esgotamento são observáveis.
- [ ] Simular perda de ACK **após** commit em fixture/harness protegido, sem endpoint de falha da API e sem corromper segredo/configuração real. Repetir envelope idêntico e comprovar duplicate.
- [ ] Retomar dependências no finally, com prazos finitos; ensaiar replay autorizado após esgotamento e mostrar limites quando evento original não está mais disponível.

**Validação:** IA-05–IA-07. Distinguir fixture HTTP/banco isolado de media type/Action log e workflow reais. Não confiar em “retry on fail” configurado como evidência de entrega observada.

### T07 — Ciclos reais integrados

- [ ] Combinar com a autora dois ciclos de parada **somente da API**; manter monitor, n8n e bancos ativos. Usar rede Compose para probes, nunca publicar porta da API.
- [ ] Em cada ciclo, observar problema Zabbix, entrega, commit e recuperação; consultar um incidente fechado por ciclo, IDs certos, UTC/duração e repetição sem duplicar. Confirmar outros serviços preservados.
- [ ] Reutilizar o procedimento seguro da entrega 03 para um ciclo real de LOGIN_ERROR, sem alterar senha/TOTP/grupos ou proteção do realm; cinco eventos observados não significam cinco submissões exatas.
- [ ] Com autenticação aberta, falha de fonte/coletor autorizada: incidente técnico independente e autenticação preservada até nova contagem válida e recovery correto. Cobrir ambas as condições collection, com origem real/fixture explicitada.
- [ ] Autora confirmar operadora+TOTP permitida e visitante+TOTP 403 em intervalo limpo; verificar que autorização negada não gerou incidente de login.

**Validação:** IA-04/IA-09. Medir detecção, entrega, commit/resposta separadamente; tempo observado não é SLA.

### T08 — Persistência e importação reproduzível

- [ ] Snapshot mínimo selecionado de incidentes open/closed, ledger, pendências, workflow e metadados públicos; sem export de credenciais ou dump de bancos.
- [ ] Reiniciar/recriar n8n e automation-db preservando novos volumes/chave; não tocar volumes da identidade/monitoramento. Confirmar login real e credenciais legíveis após recriação.
- [ ] Repetir evento antigo e verificar duplicate; completar pendência e fechar open correspondente; novo ciclo cria novo incidente. Igualdade de snapshot sozinha não satisfaz esses comportamentos.
- [ ] Importar workflow sanitizado em ambiente isolado de teste ou procedimento de reinstalação previamente aprovado, com credenciais fictícias próprias; não sobrescrever workflow ativo/segredos para “provar importação”.

**Validação:** IA-08 e parte de IA-10; não afirmar backup/HA ou proteção de queda do host.

### T09 — Relatórios com IA e HTML seguro

- [ ] Implementar workflow assíncrono separado: buscar/adquirir job persistido → snapshot SQL limitado → inferência local com modelo/prompt fixos → validar JSON/referências → template HTML escapado → outbox. Sem agent/tools, SQL livre, shell ou instruções do modelo dirigindo destino/execução.
- [ ] Persistir snapshot, versão de modelo/prompt/template e análise validada. Separar fatos e hipóteses; não atribuir capacidade preditiva validada, causa raiz ou risco percentual sem base. Histórico insuficiente deve aparecer como limitação.
- [ ] Executar inferência **real** com snapshot de incidente e revisar conteúdo em português com a autora; fixture/determinismo não substituem evidência da IA. Registrar identidade do modelo e tempos/memória sem salvar segredos ou chain-of-thought.
- [ ] Testar prompt injection, XSS/HTML/URLs do modelo, dados ausentes, saída inválida/truncada/grande, referências inexistentes e números inventados; verificar que facts do template vêm do banco e texto do modelo é identificado como análise não verificada automaticamente.
- [ ] Testar Ollama offline/timeout, duas tentativas finitas, lease expirada/crash/concorrência e retomada sem job/outbox duplicados. Fallback factual claramente sem IA; não usar fallback como único caso de aceite.
- [ ] Validar HTML/texto no navegador e limites de tamanho; sem scripts, recursos remotos, URLs ou CSS controlados pelo modelo. Sem alterar o estado dos incidentes por resultado da IA.

**Validação:** IA-11/IA-12 e parte de IA-13/IA-14. Uma chamada HTTP ao modelo com status 200 não comprova conteúdo correto, relatório seguro ou recebimento SMTP.

### T10 — SMTP local, caixa e retomada do envio

- [ ] Configurar Send Email nativo com remetente/destinatário fixos fictícios, sem CC/BCC/relay externo. Usar HTML final persistido + alternativa texto, não regenerar análise a cada retry; não habilitar Ignore SSL Issues.
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
| `compose.automation.yaml` | Implementado: n8n, automation-db, Ollama/Mailpit, redes/volumes/secrets; ainda sem conexão do server Zabbix |
| `infra/automation/` | Bootstrap, imagens não root, integridade/smokes e migração 001 de incidentes testada em fixture; ainda sem aplicar ao banco ativo. Workflows/lease/outbox/prompt produtivo/HTML pendentes |
| `scripts/` | Provisionamento e testes de infraestrutura/modelo/banco, mais Test-AutomationIncidents isolado; testes ponta a ponta ainda futuros |
| `.local/automation/` | Criado e ignorado, ACL restrita, sem sobrescrever segredos existentes |
| `docs/runbooks/incident-automation.md` | Parcial: instalação e testes iniciais exercitados |
| `docs/evidence/04-incident-automation.md` | Evidências iniciais, sem afirmar IA-01–IA-14 concluídos |

Nomes definitivos, versões e formato de export dependem do gate; não criar arquivos vazios ou credenciais fictícias funcionais antecipadamente. Nenhum novo serviço de ingestão/API é proposto; se nodes nativos não satisfizerem contrato/segurança, revisar antes de ampliar infraestrutura.

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

## 5. Checklist de prontidão

- [x] Requisito de IA para gerar relatórios confirmado pela autora e incorporado à entrega, não transferido para etapa futura.
- [x] Fluxo funcional com IA local, HTML e SMTP local aprovado pela autora.
- [x] Baseline A-D01–A-D10 adotada sob autorização posterior para escolha técnica/início, sem ampliar escopo ou usar cloud.
- [ ] Gate de versão/licença/segurança/recursos encerrado, com opções verificadas no patch.
- [ ] Contrato problem/recovery observado e sanitizado; mapeamento/IDs reais resolvidos.
- [x] Autorização explícita posterior para início de implementação e escolha de versão/modelo.

**Próxima ação:** testar transporte/raw body/Header Auth/erros e persistência de execuções em workflow protegido; completar rotinas de jobs/outbox, conferir contrato real e provisionar IDs antes de aplicar a migração ao banco ativo. Action Zabbix exige acesso temporário novo quando necessário. Sessão manual e aceites integrados pendentes. Entrega **em implementação**, não concluída; novos desvios de comportamento/segurança/escopo voltam à autora.
