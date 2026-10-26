# Evidências 04 — Incidentes e relatórios com IA (parcial)

**Estado:** implementação inicial em 26/10/2026. Infraestrutura executada, inferência real sobre fixture e SMTP local testados. **Nenhum workflow, action/media type Zabbix, transação de incidentes ou relatório integrado implementado ainda.** Este registro não conclui IA-01–IA-14. Contrato e limites na [SPEC](../features/04-incident-automation/SPEC.md); tarefas no [PLAN](../features/04-incident-automation/PLAN.md).

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

`compose.automation.yaml` adiciona quatro serviços opt-in no profile automation. `events`, `automation`, `inference` e `mail` são internas; n8n/Mailpit usam também a operations existente para interfaces em loopback. Não há dependência que inicie API/Keycloak para subir automação. Server Zabbix **ainda não conectado a events** e nenhuma action criada.

- n8n: **127.0.0.1:5678**, não root 1000, rootfs read-only, 512 MiB, volume próprio, tmpfs de /tmp e /home/node/.cache.
- automation-db: não root 999, 256 MiB, somente automation, sem porta no host, volume próprio. Bancos n8n/incidents e papéis n8n_meta/incident_owner/incident_ingest/incident_report/incident_reader; runtime sem superuser/create role/create database/replication. Somente n8n migrou suas tabelas; incidents ainda não tem modelo/transações de negócio.
- Ollama: não root 1000, read-only, 2 GiB/4 CPUs, somente inference, sem porta no host, um modelo/uma consulta paralela, contexto 2048, cloud/history/debug de bodies desabilitados. API sem autenticação própria: fronteira é rede local restrita e host/Docker confiáveis, não isolamento absoluto.
- Mailpit: não root 1000, read-only, 128 MiB, SMTP só Docker e UI/API em **127.0.0.1:8025**, autenticações SMTP/UI distintas por arquivo, volume SQLite próprio, sem pruning automático/relay/forward configurados. Destinatário permitido somente operadora@lab.invalid; não chega à caixa pessoal externa.

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
