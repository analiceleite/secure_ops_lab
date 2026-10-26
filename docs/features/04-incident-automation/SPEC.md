# SPEC 04 — Incidentes e relatórios com IA

**Estado:** em implementação inicial desde 26/10/2026. Após aprovar o fluxo, a autora solicitou **“use a versao e modelo de IA que vc recomendar e inicie a implementação”**, autorizando seleção técnica e início gradual dentro deste escopo. IA local é requisito; escolhas e exceções locais já propostas ficam documentadas abaixo, com validação obrigatória antes de uso funcional. Gate de integração Zabbix e critérios de aceite ainda pendentes. Execução no [PLAN](PLAN.md).

Referências: [arquitetura](../../architecture.md), [roadmap](../../roadmap.md), [SPEC 03](../03-monitoring/SPEC.md) e [evidências 03](../../evidence/03-monitoring.md).

**Revisão do receptor aprovada:** após autorizar a revisão documental motivada pela persistência do segredo fictício no n8n, a autora respondeu **“aprovado! pode implementar”**, aprovando o receptor mínimo e autorizando implementação gradual. Fluxo revisado: Zabbix → receptor TypeScript → PostgreSQL → n8n para IA/HTML/SMTP. Substitui explicitamente o receptor n8n da baseline anterior. Instalação funcional ainda depende dos gates de HTTP/banco/macros/allowlist reais; aprovação não equivale a aceite técnico concluído. Preservar infraestrutura/credenciais/volumes e distinguir o candidato n8n reprovado do novo receptor.

## 1. Objetivo e ponto de partida verificado

Transformar problemas e recuperações do Zabbix em incidentes locais consultáveis, persistentes e idempotentes e **gerar relatórios HTML com análise de IA**, enviados por SMTP local. A autora deve demonstrar abertura, repetição sem duplicação, encerramento correlacionado, duração observada, sobrevivência a reinícios e relatório com IA real. Não executar correção automática.

Inspeção inicial dos arquivos existentes, antes da autorização executável (estado histórico; incremento atual nas evidências/PLAN):

- Zabbix 7.0.32 LTS, frontend e PostgreSQL 17.11, com dados em `zabbix-db-data`.
- API sem porta no host, somente em `service`; server em `service` + `monitoring`; coletor em `identity` + `monitoring`.
- Nenhum serviço n8n, workflow, media type, action ou armazenamento de incidentes implementado no repositório.
- Triggers Single, sem fechamento manual, com tags `service=secureops-api` e `category=availability|authentication|collection`.
- Há **duas triggers collection**: ausência de resultados HTTP e qualidade/ausência da coleta de autenticação. Categoria não identifica uma condição de modo único.
- Eventos reais anteriores (por exemplo 137→138 e 109→112) são evidência de problema/recuperação do monitor, **não payloads capturados do webhook** nem eventos a reenviar automaticamente.
- O token administrativo temporário foi revogado. A automação proposta não precisa de token da API Zabbix em runtime. Administração futura exige acesso temporário novo, nunca reativar o divulgado.

### Condições propostas para a integração

| Chave lógica local | Trigger existente | Categoria |
| --- | --- | --- |
| `api-http` | SecureOps API: falha na verificacao HTTP interna | availability |
| `api-http-nodata` | SecureOps API: verificacao HTTP sem dados recentes | collection |
| `auth-threshold` | SecureOps: falhas repetidas de autenticacao | authentication |
| `auth-collection` | SecureOps: coleta de autenticacao invalida ou ausente | collection |

Resolver IDs reais na configuração inicial e manter um mapeamento local explícito entre instância, host, trigger, condição, serviço e categoria. Não reutilizar IDs históricos de outro ambiente ou confiar apenas no nome/tags enviados. Mudança de trigger exige revisão do mapeamento.

## 2. Escopo proposto

Incluído no desenho revisado: receptor TypeScript mínimo independente, n8n Community self-hosted para relatórios, media type Webhook customizado no Zabbix, action restrita às quatro condições acima, operações de problema e recuperação, autenticação por header, validação estrita, transação PostgreSQL, consulta read-only, replay controlado e testes de falha/persistência. Também geração obrigatória de análise com IA local, template HTML seguro e envio SMTP para caixa local de laboratório. Sem community nodes ou serviços comerciais. Envio externo solicitado posteriormente pela autora ainda precisa de revisão própria de SMTP/privacidade antes de configuração; Mailpit permanece a caixa do laboratório e nenhum endereço pessoal será embutido nos artefatos versionados.

Fora do escopo: entrega a Gmail/Outlook ou caixas externas, SMTP relay público, IA em nuvem/API paga, agente com ferramentas, treinamento/fine-tuning, previsão estatística validada, mensageria, ticketing externo, reconhecimento/fechamento manual no Zabbix, update operations, correlação causal entre triggers, polling/reconciliação automática pela API Zabbix, Redis/queue mode, HA, bloqueio de usuários, reinício de containers, socket Docker, comandos no host e nova interface CRUD. A entrega 05 fará a demonstração integrada, sem substituir os testes específicos desta entrega.

Incidente significa **registro operacional do problema observado**, não ataque confirmado. Encerrar autenticação significa que o monitor observou contagem válida abaixo do limiar, não que houve contenção de ameaça.

## 3. Fluxo aprovado, baseline técnica e gates

A aprovação inicial do fluxo não autorizava instalação. Depois, a autora delegou a escolha de versão/modelo e pediu início da implementação. A-D01–A-D10 são a baseline técnica adotada para esse início, sem mudança dos limites gratuitos/locais e sem supor aceite já validado. Novas exceções, aumento de recursos, troca para cloud ou ampliação de comportamento exigem revisão explícita.

### Seleção inicial e exceções antes da subida

| Componente | Seleção | Justificativa / gate |
| --- | --- | --- |
| n8n | 2.44.7, digest `sha256:942bc274709f27f99f7c6024a785d8e8f75ac06838cabcba448abb8d9127ec7b` | Release estável oficial de 26/10, não beta; binário confirmou versão. Configuração conferida no código dessa tag; runtime e cadastro owner ainda serão validados |
| Ollama | 0.40.11, digest `sha256:dea72d1e22270fe095b68fdf756d2b489d615643c5a2eaebbc5f569181e322d8` | Release oficial de 24/10; configuração permite desabilitar cloud e limitar contexto/concorrência; imagem derivada só prepara diretório de volume para UID 1000 |
| Modelo | `qwen2.5:1.5b-instruct-q4_K_M`, Q4_K_M, 1,54B parâmetros | Português, licença Apache 2.0 e pesos de 986048512 bytes. Selecionado por caber melhor no laboratório; não significa análise preditiva validada. Fixar SHA-256 do manifesto/artefatos antes de carregar; medir RAM/latência real |
| Mailpit | 1.32.0, digest `sha256:0790692be935ea4420d085694f7985b1f692ca6a8771ab0e0bd8ba75ac180498` | Release de 22/10 com correções de segurança; imagem derivada só prepara volume para UID 1000. Opções confirmadas pelo help real e fonte oficial |
| PostgreSQL da automação | 17.11, digest já fixado no overlay do monitoramento | Novo container/volume independente; sem atualizar ou compartilhar o banco Zabbix |
| Receptor | Node 24.22.1-bookworm-slim, digest `sha256:55fb5f5a527ea2c5c4a95f963e48ef90aa38c7b346054fdc8ee9957a2b55d205`; TypeScript apagável nativo; `pg` 8.21.0, licença MIT | Mesmo runtime da API/coletor, sem framework/compilador novo. Versão/engines/licença do driver conferidos no registro npm; dependências transitivas fixadas em package-lock, instalação com scripts desabilitados. Não é auditoria universal de vulnerabilidades |

A-D04/A-D10 são aplicadas somente no recorte já apresentado: HTTP local, cookie n8n sem Secure/SameSite Strict e SMTP autenticado sem TLS, somente dados fictícios/loopback/redes locais. Não há validação TLS desabilitada, confidencialidade de transporte ou isolamento absoluto do host. Validar binds/negações reais antes de publicar workflow. Ollama fica sem porta no host, em rede interna sem autenticação própria, somente com n8n como cliente permanente; host/Docker são confiáveis. Downloads de imagens/modelo são instalação administrativa, não integração externa de runtime.

Gate dividido: infraestrutura/usuários/volumes/configuração podem ser exercitados isoladamente; captura de macros/action e processamento funcional só avançam depois do gate próprio. **Estado atual:** rede interna `events`, schema/allowlist, service user/group e action/media restritos foram preparados. Um evento real confirmou expansão de macros e ingestão problem/recovery; action/media e os dois workflows foram pausados porque o runtime n8n ficou pendente antes dos nodes, impedindo o relatório.

| ID | Recomendação | Custo, alternativa e limite |
| --- | --- | --- |
| A-D01 | Integrar as quatro triggers, com incidentes independentes por condição/ciclo | Preserva disponibilidade, autenticação e visibilidade da coleta. Alternativa menor: só disponibilidade, exigindo recorte explícito da SPEC. Não fundir dois problemas collection em um incidente. |
| A-D02 — revisão aprovada | `incident-receiver` TypeScript mínimo: autenticação/limites → rotina PostgreSQL → ACK; n8n só executa relatórios a partir de jobs/snapshots sanitizados | Corrige persistência de headers sem relaxar a proibição. Cinco serviços de automação. Driver pg fixado, sem framework HTTP, fila, proxy adicional ou API administrativa. A autorização posterior substitui explicitamente a proibição inicial de receptor customizado; validações continuam obrigatórias. |
| A-D03 — revisão aprovada | `events` interna: Zabbix server→incident-receiver; `automation` interna: receptor/n8n→banco. n8n só automation/inference/mail/operations | Receptor sem porta no host, sem operations/service/identity/monitoring. Editor continua 127.0.0.1:5678 sem workflow de ingestão. Neste incremento, remover events somente do n8n e iniciar receptor; Zabbix permanece fora de events até o gate real. operations permite saída; não alegar egress bloqueado. |
| A-D04 — revisão do ponto de validação | Receptor valida header exclusivo antes de ler/processar corpo; HTTP somente events, sem listener de ingestão no host. Cookie HTTP do editor permanece exceção já documentada | Mesmo limite local de transporte, sem TLS ou prova criptográfica de origem. Segredo de webhook existente, ainda sem uso funcional, será montado somente no receptor; não rotacionar nem enviar ao n8n. Replay continua no banco. Host/Docker confiáveis. |
| A-D05 | Persistência transacional, recuperação antecipada guardada sem abrir incidente e conflito entre ciclos devolvido para retry | Evita “última mensagem vence”, reabertura e fechamento do ciclo errado. Recuperação que nunca recebe problema permanece pendente e consultável. Não inventar evento faltante ou prometer convergência ilimitada. |
| A-D06 — revisão do destinatário | Retries finitos no media type: proposta de 5 tentativas totais, intervalo 30s, timeout HTTP 15s para o receptor; positivo só após commit | Confirmar campos/ranges no patch 7.0.32 e medir tempo efetivo. Receptor/banco offline podem esgotar tentativas; n8n offline não impede registro de incidentes/jobs e apenas atrasa relatórios. Replay manual preserva envelope/IDs; sem promessa de entrega garantida. |
| A-D07 — revisão explícita de minimização | Conservar incidentes/chaves até limpeza autorizada; receptor nunca grava headers/corpo bruto em logs, arquivos ou metadados. n8n recebe somente snapshots/saídas sanitizados e mantém flags none/false para minimizar retenção, sem prometer ausência de gravação inicial | Dados técnicos sanitizados de relatório podem existir transitoriamente no metadata n8n e ficar sujeitos a pruning 7d/1000 e ao ciclo real de hard-delete; nunca incluir headers/evento bruto/segredos. Credenciais nativas criptografadas e chave estável continuam separadas dos payloads. Não usar metadata como banco de incidentes/jobs; testar erros, crash e execuções manuais. Exceção técnica de retenção de dados sanitizados apresentada para revisão, não aplicada silenciosamente. |
| A-D08 | IA local via Ollama, com modelo pequeno quantizado, licença gratuita compatível e identidade/digest fixados no gate | IA é requisito confirmado; Ollama/modelo ainda são propostas técnicas. Somente agregados sanitizados, sem cloud/tools/RAG externo. Gate mede memória/CPU/latência sem derrubar o laboratório; se não couber, registrar bloqueio e revisar modelo/recursos com a autora, não substituir silenciosamente IA por texto fixo. |
| A-D09 | Um relatório de encerramento por incidente, gerado assincronamente com IA e histórico agregado de 7d; fallback factual explicitamente sem IA somente em falha | Entrega análise e sugestões preventivas, não previsão garantida. Job/outbox persistidos na transação do encerramento; IA/SMTP nunca atrasam o ACK Zabbix. Proposta não envia e-mail de cada polling nem relatório de abertura; outra frequência exige decisão da autora. Fallback não satisfaz sozinho o aceite de IA. |
| A-D10 | SMTP capturado localmente por Mailpit, sem relay/forward externo; UI candidata em `127.0.0.1:8025`, SMTP somente na rede Docker | E-mail HTML real via SMTP, visualizado na caixa local do navegador; **não chega à caixa pessoal externa**. Remetente/destinatário fictícios fixos, UI protegida e autenticação SMTP exclusiva conforme gate. Exceção SMTP local sem TLS requer aprovação, não usar Ignore SSL Issues. Entrega SMTP ambígua não autoriza prometer exactly-once. |

Alternativas não são autorizações para ampliar escopo silenciosamente. Baseline adotada após a solicitação de escolha técnica/início; gates de contrato, segurança e comportamento continuam obrigatórios antes da integração funcional.

## 4. Arquitetura proposta e segurança

```text
Zabbix server -- events / POST autenticado --> incident-receiver (proposto)
                                                       |
                                              automation interna
                                                       |
                                                 automation-db
                                                  /          \
                                        metadados n8n      incidentes/jobs

Navegador local -- 127.0.0.1:5678 / login próprio --> editor n8n

Após commit do encerramento, sem depender do n8n para registrar o evento:
job persistido --> n8n --> Ollama local --> análise validada --> template HTML
                   |                                           |
                   +---- relatório/outbox no PostgreSQL --------+
                                                               |
                                                    Mailpit / SMTP local
                                                               |
                                            caixa local em 127.0.0.1:8025
```

- Overlay `compose.automation.yaml` implementado no incremento inicial, opt-in via profile automation, sem iniciar API/identidade por dependência. Ausência de n8n não impede coleta/triggers existentes; integração de notificações ainda não foi criada.
- PostgreSQL 17.11 executado **em container/volume novos**, com banco n8n e incidents separados; n8n migrou somente seu banco. Nenhuma atualização do banco Zabbix.
- Versões/digests selecionados na seção 3; `infra/automation/model-lock.json` fixa manifesto original `65ec06548149b04c096a120e4a6da9d4017ea809c91734ea5631e89f96ddc57b` e pesos Q4_K_M. Gate inicial verificou licença, imagens Linux, configuração e inferência sintética real; não equivale a auditoria de vulnerabilidades, segurança funcional do workflow ou qualidade preditiva. Não usar latest/trial ou confiar em alias mutável.
- Executar não root, sem privileged/socket/capabilities extras, com no-new-privileges, mounts de segredo read-only e volumes nomeados novos. Validar diretórios graváveis e suporte a rootfs read-only; não habilitar exceção de privilégio para fazer funcionar.
- Tetos candidatos: n8n 512 MiB, automation-db 256 MiB, Mailpit 128 MiB e inferência CPU-only até 2 GiB para modelo pequeno quantizado; logs 10 MiB × 3. Não são dimensionamento comprovado, tamanho de download não equivale a RAM e os 7,61 GiB observados anteriormente no Docker não comprovam memória livre atual. Medir com todos os serviços, sem GPU/privileged como requisito. Se insuficiente, apresentar revisão antes de baixar modelo maior/aumentar limites; não retirar IA do aceite silenciosamente.
- Receptor implementado em `apps/incident-receiver/`: usa somente events/automation, sem volumes de negócio, porta no host ou privilégio Docker. Node/TypeScript reutilizam a versão base; `pg` 8.21.0 é dependência operacional nova. Sem alteração em apps/api/framework. Runtime: 128 MiB/1 CPU, rootfs read-only, UID 1000, caps ALL removidas/no-new-privileges, logs limitados. Recriação controlada do n8n removeu events e preservou metadata mínima; detalhes/resultado em PLAN/evidências. Recepção funcional ainda depende da migração/allowlist e contrato Zabbix.
- Rede proposta `inference` interna: somente n8n e Ollama, sem publicar 11434. API Ollama não deve ser considerada autenticada por padrão; isolamento local/rede e host confiável são limites explícitos a aprovar. Desabilitar recursos cloud e não permitir ao evento escolher modelo/endpoint. Modelo pré-carregado por etapa administrativa controlada, sem download ou fallback remoto durante geração.
- Rede proposta `mail` interna: somente n8n e Mailpit, SMTP 1025 sem publicação no host. Mailpit também em operations para UI protegida em loopback 8025; sem relay, forwarding, remote images ou auto-link checking. SMTP local sem TLS é exceção proposta separada, com credenciais fictícias exclusivas; não desativar validação de certificado como workaround.
- Segredos novos em `.local/automation/`, fora do Git/build: header, chave estável de criptografia n8n, senhas exclusivas. Nunca usar senha de operadora, TOTP, client secret do gateway/coletor, credenciais Zabbix ou bootstrap como runtime.
- Volume de dados do PostgreSQL e volume necessário do usuário n8n preservados; chave de criptografia estável fora do export. Metadados do workflow, credenciais criptografadas e conta do editor precisam sobreviver à recriação. Volume não é backup; chave não cifra o tráfego nem todos os dados do banco.
- Papel dos metadados n8n pode migrar **somente seu banco**. Papel incident_ingest passa a ser exclusivo do receptor, nunca owner/superuser: apenas EXECUTE da rotina, sem DML/DDL/views de tabela bruta. n8n usa incident_report restrito a snapshots/rotinas de job/outbox; leitor exclusivo SELECT nas views. DDL/bootstrap só em administração efêmera. Testar negação a bancos/tabelas do monitor e a DDL indevido.
- Preferir uma rotina SQL transacional chamada com parâmetros, com owner separado, permissões mínimas, nomes qualificados e search_path seguro se SECURITY DEFINER for indispensável. Não montar queries concatenando campos do evento nem espalhar BEGIN/COMMIT entre nodes/conexões diferentes.
- Editor com conta local própria e senha exclusiva antes de publicar workflow de relatório; negar acesso sem sessão. Não presumir SSO gratuito nem reutilizar o Keycloak. Receptor tem autenticação própria independente; não publicar Webhook de ingestão n8n ou endpoints administrativos de simulação.
- Desabilitar diagnósticos/telemetria, templates externos, notificações de versão e recursos cloud de IA conforme opções comprovadas na versão; **preservar apenas a inferência local aprovada para relatórios**. Nenhum envio de logs externo. Não instalar community nodes, executar comandos ou baixar código no workflow. Preferir HTTP Request nativo para inferência com destino fixo e Send Email nativo, sem AI Agent/tools. Se a validação/template exigir Code node/task runner, revisar e justificar antes de acrescentar serviço; não autorizar execução de conteúdo do modelo.
- Nenhum header/body bruto de entrada nos logs/execuções/exports. Receptor valida o segredo antes do processamento e só envia ao PostgreSQL o texto necessário à validação/ledger canônico; não encaminha requisição HTTP ao n8n. N8n não recebe o segredo, nem mesmo para removê-lo depois. Fixtures usam chaves fictícias novas, nunca o segredo do lab. IA/SMTP continuam exclusivamente nos workflows de relatórios sanitizados; validar a persistência técnica real conforme A-D07 revisada.

### Receptor mínimo proposto — contrato de operação a revisar

- Destino fixo candidato `http://incident-receiver:3000/v1/events`, somente rede Compose, POST; nenhuma porta publicada. GET /health interno pode expor só estado categórico para probe, sem dados/configurações. Não criar replay/admin/fault endpoint.
- Montar somente os segredos já provisionados para webhook e incident_ingest, read-only; validar formato na inicialização, falhar fechado e nunca imprimir valores. Comparar header com algoritmo constant-time após validar comprimento. Ausente/errado → 401, sem query de ingestão ou leitura/persistência do corpo. Limitar headers/tempo/conexões antes de processar, com opções reais da versão Node conferidas no gate.
- Aceitar application/json (charset UTF-8 opcional), não aceitar compressão/lotes. Ler bytes em memória até **4096**, inclusive corpo fragmentado/chunked; excesso → 413, UTF-8 inválido/schema inválido → 400, tipo/compressão indevidos → 415, método indevido → 405. Sem coerção de IDs/resserialização. A rotina SQL continua validando chaves duplicadas, campos, allowlist, relógio e transições; texto não validado jamais vira log/arquivo.
- Driver PostgreSQL com SQL fixo `SELECT incident.ingest($1)` e parâmetro de texto, conexão exclusiva de menor privilégio. Autocommit e resultado lido somente após confirmação do comando; positivos applied/duplicate/pending retornam 200, invalid 400, conflict 409. Erros/timeout retornam 503 categórico, nunca SQL/stack/headers/corpo; após commit com resposta perdida, retry deduplica. Pool, tempo de conexão e espera limitados; statement_timeout 5s do papel e lock_timeout 4s já previsto, requisição até 10s, emissor 15s, sujeitos a prova real de cancelamento/commit desconhecido e clocks.
- No filesystem apenas arquivos de aplicação/secrets read-only e tmpfs mínimo se necessário, nenhum payload persistido ou fila adicional. Logs limitados a resultado/categoria/duração, sem headers/corpos/query string/segredos. Falha da API, n8n, Ollama ou SMTP não derruba o receptor/banco. Parada do receptor/banco produz falha de entrega observável no Zabbix; parada do n8n mantém incidentes/jobs e adia só geração/envio.
- Validação antes da instalação: teste isolado do HTTP real com credenciais novas, fragmented/chunked/over-limit/UTF-8/JSON/duplicatas, 20 chamadas concorrentes, erros/rollback/perda de ACK, banco indisponível, timeout, restart sem volume próprio e varredura de logs/disco. Nenhum dado bruto/segredo pode aparecer no metadata n8n ou prompt/HTML. Aplicar migração/mapa só depois dos gates do novo receptor e das macros reais.

Esses pontos foram aprovados na autorização posterior para implementar. Resposta HTTP limpa não comprova ausência de logs/arquivo ou gravação inicial; exigir evidência negativa. Não conectar Zabbix ou aplicar migração/allowlist real antes dos gates específicos, nem tratar liveness do receptor como prova de prontidão funcional.

## 5. Contrato de entrada proposto, ainda não capturado

Zabbix não emite um JSON universal para esta automação: o **script do media type** montará uma mensagem mínima a partir de macros. O schema abaixo é contrato local proposto, não evidência de macros resolvidas. O gate deve capturar uma amostra sanitizada de problema e outra de recuperação da versão 7.0.32 antes de congelar payload/export.

### Envelope normalizado v1

| Campo | Regra |
| --- | --- |
| `contract_version` | Inteiro exato 1 |
| `source` | Literal `zabbix` |
| `source_instance` | Identificador local estável provisionado, não hostname arbitrário do chamador |
| `event_type` | `problem` ou `recovery` |
| `event_id` | ID decimal positivo como **string**, até 20 dígitos, sem coerção para Number |
| `problem_event_id` | ID original do problema, string; igual a event_id em problem |
| `trigger_id` | ID decimal string presente no mapeamento permitido |
| `host` | Literal `secureops-api` |
| `service` | Literal `secureops-api` |
| `condition` | Uma das quatro chaves da seção 1, consistente com trigger_id |
| `category` | Valor fixo do mapeamento, não entrada livre |
| `occurred_at` | Epoch seconds inteiro decimal como string, UTC; converter de modo validado para cálculo |

Somente esses campos. Não enviar mensagem/subject livre, URLs, tags completas, senha, token, usuário, IP, dados brutos do Keycloak ou dados de execução. Severidade/título de exibição podem ser derivados do mapeamento local, não usados como identidade.

- Método POST, Content-Type application/json, um objeto por requisição, sem arrays/lotes. No receptor revisado, limite de transporte e lógico propostos são ambos **4096 bytes**, inclusive streaming/chunked; provar rejeição antes da query e sem log de corpo. A diferença 1 MiB/4 KiB e os códigos 422/500 descritos no gate abaixo pertencem ao candidato n8n histórico reprovado, não ao contrato a implementar.
- Rejeitar campos ausentes/extras, null, tipos alternativos, macros não resolvidas, duplicação de chaves JSON se o parser não preservar sua rejeição, strings excessivas e instância/condição não permitidas. Gate deve verificar parser: se não permitir detectar chaves duplicadas, escolher validação de raw body ou revisar contrato antes de implementar.
- Eventos com horário mais de 60s no futuro são rejeitados. Eventos com idade superior a 7d são rejeitados sem alterar incidentes; aceitar atraso dentro de 7d para replay e inversão de entrega. Comparar ao horário de recebimento UTC; desvio de relógio que comprometa isso bloqueia testes. Não inserir evento velho como se fosse atual.
- Recuperação tem event_id diferente de problem_event_id; seu horário não pode preceder o problema quando ambos forem conhecidos. Não usar ordem de chegada nem magnitude de event_id para decidir qual estado vence.
- Endpoint revisado candidato é o path fixo `/v1/events` do receptor interno, não um workflow n8n. Não usar `/webhook-test/`, Listen for Test Event, URL do chamador ou redirects. Header `X-SecureOps-Webhook-Key` separado da URL/corpo; n8n não recebe esse header. Confirmar path/limites/códigos no gate do novo receptor antes do media type.

**Incremento isolado do parser:** `incident.ingest(text)` na migração 001 valida o texto original com o tipo PostgreSQL `json` (preserva chaves duplicadas) antes de converter para `jsonb` canônico. O limite lógico é 4096 bytes, inclusive espaços, e chaves escapadas duplicadas também são rejeitadas. Isso foi testado em cluster efêmero, não via webhook. Leitura do código da tag n8n 2.44.7 confirmou opção Webhook `rawBody` com cópia base64 em binary.data e limite de transporte configurado em MiB; caminho candidato é parâmetro nativo Postgres com decodificação UTF-8, **sem reserializar `$json.body`**. Integração real, autenticação, malformed JSON e respostas anteriores ao workflow ainda precisam de gate; o limite de transporte atual é 1 MiB, distinto do limite lógico de 4 KiB. Não declarar contrato real capturado ou necessidade de Code node resolvida apenas por essa leitura.

**Gate n8n executado posteriormente, com bloqueio de segurança:** candidato de seis nodes nativos testado em instância n8n 2.44.7/PostgreSQL efêmeros. Raw body íntegro foi acessado por `$input.item.binary.data.data` (`$binary` omite data), enviado como parâmetro e validado pela rotina SQL. Header Auth, rejeição de duplicatas de chave, transação, 20 chamadas concorrentes, ACK após liberar lock e resposta 503 em timeout funcionaram na fixture. JSON malformado retornou 422 antes do workflow; corpo acima do teto de transporte 1 MiB retornou **500**, não 413, sem alteração do ledger. **Porém execution_data reteve header/marcador fictícios com flags globais e settings do workflow em none/false.** O código da tag confirma persistência inicial e soft-delete até pruning posterior. Logo o desenho direto Webhook→n8n **não passou o requisito de não persistir headers/bodies**, e o candidato não pode ser publicado. Nenhuma configuração de produção ou política de retenção foi relaxada. Proposta pendente de aprovação: receptor mínimo dedicado autentica/valida/persiste/confirma, n8n consome somente snapshots sanitizados para relatórios; altera A-D02 e fluxo de entrada e precisa revisão explícita antes de implementar. IA continua no escopo, sem Code node, serviço adicional ou proxy já instalado. Evidências detalhadas no registro 04.

### Mapeamento de macros a verificar, não payload aprovado

Conferir na matriz de macros/contextos e no patch as candidatas `{EVENT.ID}`, `{EVENT.RECOVERY.ID}`, `{TRIGGER.ID}`, `{HOST.HOST}`, `{EVENT.TIMESTAMP}` e `{EVENT.RECOVERY.TIMESTAMP}`. Operação de recuperação precisa preservar **ID do problema original** e usar **ID/horário da recuperação**, não apenas a trigger ou status atual. Tipo da operação deve vir de parâmetros distintos de problem/recovery comprovados no gate. Construir JSON por serialização, não substituição textual de mensagem pronta.

Se o contexto não resolver algum campo de forma inequívoca, parar e revisar o contrato; não buscar payload do Kuma, extrair IDs de texto livre ou adicionar token administrativo permanente para contornar. Usuário destinatário local e mídia devem ter apenas as permissões de leitura necessárias ao host; condições da action, usuário/mídia habilitados, recovery operations e ausência de update/escaladas repetitivas precisam de evidência.

## 6. Persistência e máquina de estados

### Identidades e invariantes

- Identidade da condição: `(source_instance, trigger_id)`. Serviço/categoria sozinhos não são únicos.
- Identidade do ciclo/incidente: `(source_instance, problem_event_id)`, imutável. A mesma chave nunca troca de trigger/condição.
- Identidade da entrega lógica: `(source_instance, event_id)`, com envelope canônico permitido persistido para comparar conteúdo, sem guardar headers. Mesmo ID com campos diferentes resulta em conflito, não update.
- No máximo um incidente aberto por condição; condições diferentes podem ter incidentes simultâneos. Novo ciclo depois de encerrado cria outro incidente.
- Consistência garantida por constraints, bloqueio transacional por condição e processamento atômico no banco, não por `SELECT` seguido de `INSERT` em nodes separados, concorrência=1, static data ou histórico de execução.

### Dados mínimos consultáveis

1. **Entregas aceitas:** chave do evento, campos normalizados, recebido_em UTC e resultado lógico. Chave única impede efeitos repetidos.
2. **Ciclos/correlações:** problema original, condição, evento/horário de recuperação antecipada quando houver; registro pode existir sem incidente.
3. **Incidentes:** ID local estável, instância, serviço, condição/categoria, trigger, problema, abertura observada, estado open/closed, recuperação e encerramento observados, duração em segundos, horários de recebimento e indicador de chegada fora de ordem.

Rejeitados sem autenticação/schema não devem escrever no ledger de incidentes. Diagnóstico de falhas é categórico e sem corpo/header. O estado autoritativo fica no banco de incidentes, não no retorno verde do n8n.

### Transições requeridas

| Entrada/estado | Efeito atômico |
| --- | --- |
| Problema novo, sem recuperação e sem outro ciclo aberto na condição | Inserir entrega, correlação e um incidente open |
| Mesmo evento e mesmo conteúdo, inclusive após restart | Retornar duplicate, sem nova linha de incidente/transição |
| Mesmo event_id com conteúdo diferente, ou problema com outra trigger | Conflict; rollback, sem sobrescrever o registro original |
| Recuperação de incidente open correspondente | Registrar entrega e fechar **somente** o problema indicado; duração = recovery.occurred_at − problem.occurred_at |
| Recuperação duplicada | Não recalcular encerramento ou duração; duplicate |
| Recuperação sem problema conhecido | Persistir entrega/correlação pendente; **não criar incidente**, não fechar outra condição/ciclo |
| Problema chega depois de recuperação pendente correspondente | Completar correlação e criar um único incidente já closed, com horários originais e marcador fora de ordem; nunca ficar open transitoriamente |
| Problema já fechado reenviado | Nunca reabrir, mesmo com horário de recebimento mais recente |
| Problema de outro ciclo chega com um ciclo ainda open na mesma condição | Conflict recuperável; rollback da nova entrega, para permitir retry após recuperação do ciclo anterior. Não fechar o antigo por inferência |
| Recuperação antiga chega enquanto ciclo novo está aberto | Atua somente no problema original; ciclo novo permanece open |
| Recuperação diferente para um ciclo já recuperado ou horário inconsistente | Conflict/invalid; sem mudar recuperação original, sem duração negativa |

O bloqueio precisa cobrir também **condição ainda sem linha**, para evitar a corrida de dois primeiros eventos. A futura implementação deve demonstrar isso com chamadas concorrentes ao banco e ao workflow. Constraint unique parcial de aberto por condição é proteção adicional; não substitui a transação que inclui ledger/correlação/estado.

**Implementação e estado ativo:** migração 001 cria schema/ledger/ciclos/incidentes/views e job/snapshot único; migração 002 adiciona leases, validação/armazenamento de relatório HTML escapado e outbox com expiração ambígua sem reenvio cego. Ambas passaram harness PostgreSQL efêmero (86 checks base + 15 relatório/outbox, concorrência e rollback) e foram aplicadas ao banco `incidents` ativo após autorização da autora para staging do teste ponta a ponta. Schema versions 1/2, quatro condições allowlisted e zero deliveries foram confirmados por consulta read-only. `scripts/Install-IncidentSchema.ps1` recusa schema preexistente/reaplicação. Macro/action ainda não foram verificadas em execução real.

### Fora de ordem e limites operacionais

Não haverá reconciliador automático nesta proposta. Recuperação antecipada permanece pendente até o problema chegar; um problema nunca entregue não é inventado. Novos ciclos bloqueados por anterior ainda aberto podem exigir replay após esgotar retries. Consulta deve mostrar pendências, abertos e conflitos diagnosticados, sem prometer completude apenas porque não há execução falhando.

### Consulta e duração

Consulta local reproduzível por SQL read-only nas views, via Compose; sem publicar PostgreSQL no host ou criar API administrativa. Exibir IDs, serviço, condição, estado, timestamps UTC, duração e pendências; mascarar credenciais no comando/output. Não criar painel customizado só para o aceite.

Duração é **intervalo observado entre eventos do Zabbix**, não tempo exato da indisponibilidade nem tempo de processamento do workflow. Horários de recebimento são separados e podem inverter. Para incidente aberto, duração final é null; para recuperação sem problema não há duração calculada.

## 7. Confirmação, retries e falhas

- Nunca responder “aceito” imediatamente ao receber. Resposta positiva requer commit da entrega/transição ou verificação persistente de duplicata. Recuperação antecipada pode receber positivo **após** persistir pendência, com resultado distinto de closed.
- Proposta revisada: 200 applied/duplicate/pending, 400 contrato/JSON inválido, 401 sem autenticação, 409 conflito, 413 excesso real de 4096 bytes, 415 tipo/compressão indevidos e 503 falha temporária/timeout. Confirmar no receptor real. Códigos 422/500 do candidato n8n são evidência histórica, não contrato a imitar no receptor.
- Resposta mínima e categórica, sem ecoar evento/header, SQL, stack trace ou credenciais. Media type só considera sucesso o código e resultado positivo previstos; timeout, resposta inválida e demais status lançam erro sanitizado.
- Proposta: query/transação 5s, requisição do receptor até 10s e media type 15s; conferir conexão/pool/cancelamento/erro no driver fixado. Workflows de relatório ficam fora desse prazo. Lock timeout não pode virar sucesso, e retry não pode pular evento não confirmado.
- Falha antes/durante commit: rollback ou resultado desconhecido para emissor, nunca sucesso fabricado. Falha **após commit e antes do ACK**: retry do mesmo envelope retorna duplicate, com exatamente um incidente.
- Emissor mantém IDs/horários originais em retry. Retries finitos do Zabbix precisam de teste real com endpoint/DB indisponíveis; não confundir uma configuração de 5 tentativas com 5 entregas observadas.
- Esgotamento: verificar falha no Action log do Zabbix e correlacionar com consulta read-only. Após retomar dependências, replay manual autorizado do envelope mínimo original via rede Compose e header local; não aumentar IDs, editar banco ou inventar recuperação para “limpar”.
- Limite de recuperação operacional proposta: replay até 7d do evento, conforme contrato. Sem evento retido/consultável ou fonte suficiente para reconstrução segura, registrar lacuna; não prometer reparo universal após retenção/queda do host.

## 8. Relatórios HTML com IA — requisito desta entrega

### Disparo e independência do núcleo

Proposta: **um relatório final por incidente encerrado**, não um por amostra/alerta repetido. Relatório de abertura ou resumo periódico ainda não foi definido como requisito; a frequência A-D09 aguarda revisão. Na mesma transação que cria/fecha o incidente, criar um job único `(incident_id, report_version)`; recuperação antecipada só gera job quando o problema chegar e o incidente fechado existir.

O receptor confirma após esse commit, sem esperar n8n, IA ou SMTP. Workflow separado agenda processamento de jobs persistidos (candidato: a cada 30s). Não é Redis/queue mode nem reconciliador do Zabbix: o banco guarda trabalho de relatório pendente. Falha de n8n/IA/SMTP nunca reabre/fecha incidente ou muda trigger.

Adquirir job com lease/token de tentativa persistidos e compare-and-set; somente dono vigente pode gravar resultado/outbox. Lease expirada permite retomar após crash, sem manter transação SQL aberta durante inferência ou SMTP. Duplicata/retry do evento não cria outro job ou e-mail lógico. Papéis de relatório só leem views sanitizadas e chamam rotinas restritas de job/outbox, sem editar estado de incidentes ou bancos alheios.

### Dados e papel da IA

- Snapshot mínimo: serviço/condição, categoria, horários/duração observados, dados de qualidade/lacunas **quando conhecidos** e agregados SQL dos incidentes da mesma condição nos sete dias anteriores ao encerramento. Incluir contagem, janela efetivamente coberta e limitações; não interpretar falta de registros como ausência comprovada de falhas.
- Números/recorrência/duração são calculados deterministicamente em SQL, nunca inventados pelo modelo. Congelar snapshot, versão do prompt e do modelo por relatório para não mudar fatos entre retries. Entrada candidata até 8 KiB, sem lista de logs/eventos brutos; não enviar headers, tokens, senhas, IPs, usuários, TOTP ou URLs de credenciais.
- O modelo deve gerar **análise textual em português**, hipóteses e recomendações preventivas justificadas pelos fatos fornecidos. Com histórico insuficiente, declarar isso. Não afirmar que prevê a próxima falha, atribuir causa raiz/ataque como certeza, emitir percentuais de risco não calibrados ou inventar métricas ausentes.
- Não há ferramentas, shell, navegador, consulta livre SQL, leitura de arquivos/segredos, escolha de destinatário ou ação corretiva pela IA. Entrada é dado não confiável, mesmo do laboratório: prompt injection não autoriza mudar instruções, rede ou workflow.
- Saída estruturada candidata: objeto com `resumo`, lista de `hipoteses` e lista de `recomendacoes_preventivas`, cada item com referências aos fatos/limitações do snapshot. Validar tipos, comprimentos, campos permitidos e referências existentes; isso **não comprova verdade semântica**. Texto de IA deve ser identificado como gerado, sujeito a erro e revisão humana.
- Candidatos: uma inferência concorrente, contexto 2048 tokens, saída até 512 tokens/8 KiB e timeout 120s por tentativa. Conferir tokenizador/opções/modelo/versão e memória no gate; corpo além do limite ou geração incompleta é falha, não texto truncado apresentado como análise válida.

### HTML e rastreabilidade

**A IA gera a análise; o workflow gera o HTML a partir de template fixo.** Não executar/renderizar HTML bruto retornado pelo modelo. Escapar todas as strings e não converter Markdown do modelo em HTML ativo. Sem scripts, event handlers, formulários, iframes, tracking pixels, imagens/fontes remotas, links ou CSS/URLs fornecidos pelo modelo. Validar em browser e na caixa SMTP com payloads fictícios de XSS.

Seções do relatório: fatos observados e linha do tempo; histórico/recorrência com cobertura; análise de IA; hipóteses e limitações; sugestões preventivas para avaliação humana. Indicar que encerramento de autenticação não comprova contenção. IDs/fatos, relatório/versionamento, modelo/artefato, prompt versionado e horário UTC permitem rastrear a análise; não guardar chain-of-thought.

Guardar no banco o snapshot sanitizado, resultado validado, versão do template, HTML final, estado/contadores/erros categóricos do job e outbox. Não usar execuções n8n como armazenamento. HTML persiste para consultar e reenviar a mesma versão, não regenerar texto em cada tentativa SMTP. Retenção proposta acompanha A-D07; Mailpit deve usar armazenamento persistente e política explícita sem apagar mensagens automaticamente para testar.

### Falhas e envio local

- Proposta: até duas tentativas de IA, separadas por 30s, com timeout finito. Se falhar/offline/schema inválido, persistir falha e gerar relatório factual de contingência marcado **“Análise de IA indisponível”**, sem texto fixo fingindo ser inferência. Após fallback já enviado, regenerar/enviar análise posterior exige ação explícita/versionamento; não gerar dois e-mails automaticamente.
- Contingência mantém operação útil, mas **a entrega só passa com geração real de IA validada e recebida por SMTP**. Teste só com fixture/modelo desligado não satisfaz o requisito confirmado pela autora.
- From/To fixos de laboratório, por exemplo `secureops@lab.invalid` → `operadora@lab.invalid`, sem CC/BCC externo, anexos/URLs ou destino vindo do modelo/evento. HTML no corpo e alternativa texto; assunto fixo com ID/versionamento validado, sem CRLF ou conteúdo livre da IA.
- Enviar a Mailpit pelo node SMTP. “Aceito pelo SMTP” e “visível na caixa local” são provas separadas; testar ambas. Caixa pessoal externa **não** recebe essas mensagens. UI deve exigir login e bind em loopback; não configurar relay para contornar essa limitação.
- Estados de envio: pending, sending, accepted, failed e delivery_unknown. Persistir identidade estável do relatório no assunto/corpo e Message-ID retornado quando suportado, sem presumir que o node permite definir headers arbitrários. Não depender de threading para deduplicar.
- Retry SMTP automático somente em falha comprovada antes de aceitação (até três tentativas, intervalo 30s). Timeout/crash após possível aceitação vira delivery_unknown, **sem reenvio cego**: operadora consulta Mailpit pelo identificador e reconcilia/reenvia de forma explícita. SMTP e SQL não têm commit atômico; não prometer entrega exactly-once ou deduplicação do servidor SMTP.
- Jobs de geração podem retomar por lease; job em sending encontrado após crash deve virar delivery_unknown, não pending automático. SMTP/IA indisponíveis não podem perder incidente, bloquear coleta nem produzir falso estado de envio.

## 9. Critérios de aceite propostos

| ID | Critério | Evidência exigida |
| --- | --- | --- |
| IA-01 | Decisões/viabilidade | A-D01–A-D10 aprovadas; versões/digests/licença/recursos/opções e modelo conferidos; payload real sanitizado de problem e recovery e IDs correlacionados |
| IA-02 | Exposição e segredos | Compose resolvido e bindings reais loopback; banco/receptor sem portas; API intacta; editor autenticado e receptor protegido; n8n sem events/headers de entrada; sem socket/root; logs/arquivos/metadata/prompt revisados conforme A-D07 |
| IA-03 | Contrato negativo | Sem/errado header, JSON/tipos/campos/IDs/condições/tempo inválidos, SQL injection, corpo grande e macros não resolvidas não alteram ledger/incidentes; erros sanitizados |
| IA-04 | Abertura/encerramento reais | Dois ciclos controlados apenas da API geram dois incidentes distintos, cada um com problema/recuperação certos, horários/duração não negativos e consulta read-only |
| IA-05 | Idempotência/concorrência | Repetições sequenciais e pelo menos 20 envios concorrentes do mesmo evento: uma entrega lógica/um incidente; conflitos de conteúdo não sobrescrevem; prova de transação/constraints e não só workflow verde |
| IA-06 | Correlação/fora de ordem | Recovery antes do problema, recovery órfã, problema antigo após fechar, dois ciclos invertidos, recovery antiga com ciclo novo e duas conditions collection independentes conforme seção 6 |
| IA-07 | Falha/ACK/retry | Banco/receptor indisponíveis: sem falso 2xx, retries reais finitos/esgotamento/replay; perda de ACK após commit sem duplicação. n8n indisponível em ensaio separado: incidentes/jobs continuam sendo registrados, relatórios aguardam retomada |
| IA-08 | Persistência | Reiniciar/recriar receptor stateless, n8n e automation-db preserva workflow/credenciais/chave, incidentes/pendências/deduplicação/jobs; repetir evento anterior e novo ciclo sem apagar volumes ou credenciais |
| IA-09 | Segurança e coleta integradas | Um ciclo real do limiar LOGIN_ERROR e falha controlada de coleta geram incidentes independentes; falha técnica não fecha autenticação, recuperação só com evento correto; 403 da visitante não vira incidente de login |
| IA-10 | Regressão e reprodução | Suites existentes das entregas 01–03 e novos testes; exposição da API/MFA/grupos preservados; runbook/exports/evidências sanitizados e instalação/importação repetível com origem manual/automática explícita |
| IA-11 | IA real e evidência | Inferência local real sobre snapshot de incidente, análise em português, modelo/prompt identificáveis e relatório recebido na caixa SMTP; fatos separados de hipóteses, sem alegar previsão validada. Fallback/fixture não substituem essa prova |
| IA-12 | HTML e dados seguros | Negativos de prompt injection/XSS/schema/tamanho/saída truncada; sem execução de texto do modelo ou recursos remotos, headers/destinatários fixos; nenhum segredo/log bruto no prompt/HTML/export; revisão humana de conteúdo identificada |
| IA-13 | Jobs, falhas e envio | Jobs/outbox únicos e persistentes, concorrência/lease/crash/restart, IA offline/timeout, SMTP offline e aceitação ambígua testados; fallback rotulado e delivery_unknown sem reenvio automático; sem falso sent/exactly-once |
| IA-14 | Recursos e isolamento | Inferência limitada com todos os serviços ativos sem comprometer monitoramento/MFA; Ollama e SMTP sem portas no host, UI Mailpit protegida em loopback, modelos pré-carregados/sem cloud/relay, persistência da caixa validada |

Meta local candidata para entrega normal: transição consultável até 15s após início da chamada do media type, sem retries e com dependências saudáveis. IA/HTML/SMTP são assíncronos e **não entram nesse prazo**; medir separadamente espera do job, inferência e envio com o modelo escolhido, sem inventar SLA antes do gate. Falhas/retries obedecem aos limites próprios, sem meta de entrega garantida.

## 10. Revisão documental realizada e gates pendentes

Revisão estática desta proposta identificou e resolveu no desenho: duas triggers collection; IDs como strings; ACK somente depois do commit; ledger durável em vez de execução n8n; recuperação antecipada sem incidente; proteção para condição ainda sem linha; conflito entre ciclos sem fechamento por inferência; listener do editor também expõe webhook no loopback; credenciais de editor e webhook são independentes.

**Checkpoint documental inicial, agora histórico:** a redação inicial não teve instalação/migração/download/runtime. Depois, infraestrutura/receptor e SQL de jobs/outbox foram implementados/testados em fixture; media types e workflows candidatos foram versionados. Integração ativa, expansão real de macros, migração/allowlist ativa, importação/execução de workflows e relatório de IA recebido continuam pendentes.

Revisão de escopo solicitada pela autora: IA passou de excluída a **requisito de geração dos relatórios nesta entrega**, com HTML/SMTP local. AGENTS.md ajustado nesse recorte; não foi autorizada IA externa ou execução corretiva. A implementação começou pela baseline A-D01–A-D10 e modelo pequeno recomendado; testes de inferência e mensagem SMTP são sintéticos, não relatório integrado real. Relatórios ficam fora da transação/ACK Zabbix; confirmação SMTP ambígua exige estado desconhecido, não promessa de envio único.

## 11. Fontes documentais consultadas

Consultadas em 26/10/2026, além dos arquivos locais da seção 1:

- [Zabbix 7.0 — media type Webhook](https://www.zabbix.com/documentation/7.0/en/manual/config/notifications/media/webhook): JavaScript, parâmetros, HTTP e timeout. Conferir o patch antes de usar payload/macros.
- [n8n — Webhook](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/): Header Auth, URLs de teste/produção e modos de resposta; “Immediately” não satisfaz o ACK exigido aqui.
- [n8n — Postgres node](https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.postgres/): query parameters e execução transacional; não prova atomicidade entre nodes separados.
- [n8n — banco de dados](https://docs.n8n.io/hosting/configuration/supported-databases-settings/): PostgreSQL e permissões de migração próprias, a conferir na versão fixada.
- [n8n — chave de criptografia](https://docs.n8n.io/hosting/configuration/configuration-examples/encryption-key/): chave estável para credenciais; não substitui volume/backup.
- [n8n — execuções](https://docs.n8n.io/hosting/configuration/environment-variables/executions/): opções de salvamento, pruning, timeouts e concorrência; documentação móvel, não configuração testada.
- [Ollama — Generate](https://docs.ollama.com/api/generate): geração local, saída JSON/schema e limites de contexto/saída; versão, modelo/licença, autenticação/rede e comportamento efetivo ainda precisam de gate. Exemplos da documentação não são modelos aprovados para o lab.
- [Mailpit — Docker](https://mailpit.axllent.org/docs/install/docker/): SMTP 1025, UI 8025, banco persistente e autenticação de UI. Não copiar exemplos com latest/portas em todas as interfaces ou SMTP accept-any; fixar versão e proteger configuração.
- [n8n — Send Email](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.sendemail/): SMTP, HTML/texto e limitações de headers/threading; não usar a opção de ignorar falhas de certificado ou instruções de IA como parâmetros SMTP.
- [n8n 2.44.7](https://github.com/n8n-io/n8n/releases/tag/n8n%402.44.7), [licença SUL](https://github.com/n8n-io/n8n/blob/n8n%402.44.7/LICENSE.md), [configuração da tag](https://github.com/n8n-io/n8n/tree/n8n%402.44.7/packages/%40n8n/config/src/configs).
- [Ollama 0.40.11](https://github.com/ollama/ollama/releases/tag/v0.40.11), [configuração da tag](https://github.com/ollama/ollama/blob/v0.40.11/envconfig/config.go) e [modelo Qwen2.5 selecionado](https://ollama.com/library/qwen2.5:1.5b-instruct-q4_K_M).
- [Mailpit 1.32.0](https://github.com/axllent/mailpit/releases/tag/v1.32.0) e [formatos de arquivo de senha](https://mailpit.axllent.org/docs/configuration/passwords/).

Uma tentativa de localizar template genérico em path presumido no repositório Zabbix retornou 404; não foi usado como contrato. A URL antiga de opt-out de telemetria do n8n também não existe; opções de isolamento/telemetria devem ser localizadas na documentação e imagem escolhidas no gate. Não presumir suporte a variável só por seu nome.
