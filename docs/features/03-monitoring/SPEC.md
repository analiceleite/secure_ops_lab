# SPEC 03 — Monitoramento com Zabbix

**Estado:** concluída em 26/10/2026, após implementação iniciada em 25/10. M-D01–M-D06 aprovadas e MO-01–MO-10 verificados; resultados, origens e limites no [PLAN](PLAN.md) e nas [evidências](../../evidence/03-monitoring.md). n8n permanece na entrega 04, ainda não iniciada e sem IA.

Referências: [README](../../../README.md), [arquitetura](../../architecture.md), [roadmap](../../roadmap.md), [Fundação Local](../01-local-foundation/SPEC.md), [Identidade e acesso](../02-identity-access/SPEC.md) e [PLAN](PLAN.md).

## 1. Objetivo, estado real e substituição do rascunho

Demonstrar no Zabbix dois resultados distintos:

1. **Disponibilidade:** detectar queda e recuperação da API pela rede Docker.
2. **Segurança de acesso:** sinalizar pelo menos cinco eventos de falha de autenticação em cinco minutos no client da aplicação, usando eventos do Keycloak.

Fundação e identidade concluídas; API somente em `service`, sem porta/mounts. Keycloak 26.8.1/OAuth2 Proxy mantêm MFA, credenciais e grupo exato. Zabbix integrado à disponibilidade e ao coletor: dois ciclos reais de autenticação, falhas de fonte/coletor, negativos HTTP/nodata e persistência dos quatro componentes verificados; dashboard privado de quatro widgets e retenções configuradas. Regressão/manual final aprovados; origens/limites na matriz das evidências. Kuma nunca foi instalado e n8n não implementado.

Esta SPEC **substitui integralmente** o rascunho Kuma: porta 3001, banco embutido, volume `kuma-data`, heartbeats e payloads `heartbeat/monitor/msg` deixam de orientar a implementação. README, arquitetura e roadmap foram alinhados em T02; referências históricas ao Kuma não são uma alternativa a implementar. A substituição não removeu serviço/volume existente, pois não havia Kuma instalado; entregas 01/02 continuam concluídas.

A verificação interna de `/health` não atravessa gateway nem usa credenciais de usuário; não cria bypass público. Eventos de login do Keycloak não medem todas as requisições à API nem as negações de autorização do gateway.

## 2. Escopo e fronteiras

Incluído:

- Zabbix server, frontend e PostgreSQL locais, com persistência independente da API.
- Um host lógico `secureops-api`, cenário web interno e problemas/recuperações nativos do Zabbix.
- Um coletor mínimo de eventos, com leitura restrita no Keycloak e saída agregada autenticada para o Zabbix.
- Um alerta agregado de `LOGIN_ERROR` do client `secureops-gateway`, no realm `secureops-lab`.
- Um alerta técnico de ausência/falha da coleta, para não confundir falta de observação com ausência de erros.
- Dashboard pequeno: disponibilidade, contagem recente, estado da coleta e problemas ativos.
- Testes reais controlados, persistência, regressão, runbook e evidências sanitizadas.

Fora do escopo: n8n, IA, SMTP/e-mail, webhook/receptor de captura, armazenamento externo de incidentes, filas, autorrecuperação, bloqueio automático de contas, alteração de permissões por alertas, Docker socket, agente no host, SIEM/WAF, atribuição de ataques e login sintético com senha/TOTP armazenados. Não criar endpoint de falha ou administrativo na API.

Não ampliar agora para monitorar recursos do host, todos os serviços ou todas as categorias de eventos. O problema de coleta é uma salvaguarda do cenário escolhido, não monitoramento completo do Keycloak.

## 3. Decisões técnicas aprovadas

Escopo funcional, limiar e M-D01–M-D06 aprovados explicitamente pela autora em 25/10/2026, em resposta à apresentação dos riscos de HTTP local, redes, leitura de eventos do realm e retenção. Mudanças nesses limites exigem nova revisão.

| ID | Proposta | Justificativa e limite |
| --- | --- | --- |
| M-D01 | Zabbix 7.0.32 LTS; PostgreSQL 17.11; frontend Nginx | Versões candidatas da revisão confirmadas na execução, com imagens oficiais separadas e banco compatível. Custa mais recursos que Kuma. Sem TimescaleDB, proxy, agent, Java gateway ou web service. |
| M-D02 | Frontend em `http://localhost:8081`, publicação exclusiva `127.0.0.1:8081:8080`; comunicação local sem TLS | Exceção local: painel HTTP, sessão, protocolo PostgreSQL e tokens internos não têm confidencialidade TLS. Somente contas fictícias, host/daemon confiáveis e segredos exclusivos. Conferir cookies, logout e bloqueio sem sessão antes do aceite; não relaxar validações para fazer HTTP funcionar. |
| M-D03 | Redes separadas conforme seção 4; PostgreSQL em volume nomeado próprio | API fica intacta. Frontend ganha rota de saída na bridge `operations`; coletor participa de `identity`, que já não é interna. Não alegar egress bloqueado ou isolamento absoluto do host. Nenhum banco/coletor/Zabbix server publicado no host. |
| M-D04 | Coleta via Admin REST, client técnico confidencial com service account e somente `realm-management/view-events` | Reutiliza interface documentada, sem socket Docker, plugin Java nem leitura de logs brutos. A permissão permite ler eventos do realm, **não só do client da aplicação**; o filtro no coletor não é fronteira de autorização do Keycloak. Exposição desse privilégio precisa de aprovação explícita. |
| M-D05 | Habilitar persistência somente de `LOGIN_ERROR`, retenção de 24 h; coletor entrega somente agregado de cinco minutos | Em 25/10 a autora aprovou explicitamente substituir a lista padrão ampla retornada com eventos desabilitados pelo recorte mínimo LOGIN_ERROR. Preservar listener/eventos administrativos e identidade; não apagar histórico. Eventos brutos ficam no volume sensível do Keycloak e podem conter identificadores/IP/detalhes. Novas divergências exigem revisão. |
| M-D06 | Cenário web a cada 20 s, timeout 5 s e uma tentativa; coleta de segurança a cada 30 s; limiar agregado ≥5 eventos/300 s | Demonstração curta. Primeiro erro da checagem web pode abrir problema; um `LOGIN_ERROR` isolado não abre o alerta de segurança. Limite não é padrão universal nem prova de ataque. |

Qualquer alternativa que mude redes, privilégios, dados armazenados, transporte ou comportamento volta à revisão. Não reutilizar administrador/bootstrap ou client secret do gateway para coletar eventos. Não desabilitar MFA, autorização, TLS validation ou proteção contra brute force. Caso proteções existentes impeçam produzir o cenário, discutir outro procedimento de teste, não enfraquecê-las.

## 4. Composição e persistência propostas

Overlay implementado: `compose.monitoring.yaml`. Base + monitoramento funciona sem iniciar identidade; coletor em profile `monitoring-security`, usado com base + identidade + monitoramento. Profiles **não habilitam/desabilitam itens/triggers no banco**. `Set-MonitoringSecurityMode.ps1` exercitado em availability/full preserva histórico/cenário; recusa ocultar problema ativo e exige duas qualidades válidas ao reativar. Exige acesso administrativo temporário, revogado ao terminar; runtime não depende desse token. Não iniciar Keycloak por dependência para executar só health checks.

| Serviço implementado | Redes | Responsabilidade |
| --- | --- | --- |
| `zabbix-db` | `monitoring` interna | Banco exclusivo do Zabbix, volume `zabbix-db-data`; sem porta no host |
| `zabbix-server` | `monitoring`, `service` | Cenário web, itens HTTP, triggers e eventos; sem publicação de 10051 |
| `zabbix-web` | `monitoring`, `operations` bridge não interna | Frontend autenticado, única publicação nova em loopback |
| `identity-event-collector` | `monitoring`, `identity` | Ler eventos do Keycloak; endpoint agregado interno autenticado, sem porta no host ou acesso ao volume Keycloak |

API continua somente em `service`. Keycloak/gateway mantêm redes, portas e credenciais existentes. O coletor não participa de `service`; server/frontend não participam de `identity`. `identity` é declarada também no overlay do monitoramento com os mesmos parâmetros aprovados, para resolver o profile sem iniciar Keycloak no modo disponibilidade. `operations` resolve publicação do frontend; bindings reais devem ser testados.

### Versões implementadas na infraestrutura

Consultas HTTP em 25/10/2026 confirmaram tags/manifesto `linux/amd64`; após aprovação, pull e inicialização reais foram executados com os índices abaixo. Compatibilidade de inicialização/schema conferida em T02, sem presumir aceite dos cenários de monitoramento:

| Imagem implementada | Digest do índice consultado |
| --- | --- |
| `zabbix/zabbix-server-pgsql:alpine-7.0.32` | `sha256:401dc90cff398aaf6a0fa72625f4b9b57407e61231f94e13e7f4e68aeff0c42c` |
| `zabbix/zabbix-web-nginx-pgsql:alpine-7.0.32` | `sha256:a54ce2e19aaf0a61609e4bbc7ec01c16bef504e6e1c51e3854120ac76d2dbaeb` |
| `postgres:17.11-bookworm` | `sha256:858bb5e98eed02eb8cafbcdc007f9a65d1b613972028944a8ec2133ccaf80d27` |

Zabbix 7.0 documenta PostgreSQL 17 a partir de 7.0.6. Revalidar patches, manifesto, variáveis, health checks, usuário e caminhos de dados antes de fixar tag+digest no Compose; não usar `latest` nem atualização silenciosa. Coletor deve reaproveitar Node/imagem local, sem framework ou biblioteca nova por conveniência.

Requisitos de implementação:

- Sem privileged, host network, socket Docker, capabilities extras ou execução root silenciosa. Verificar inicialização do volume PostgreSQL com usuário/permissões adequados; incompatibilidade bloqueia o gate, não autoriza exceção automática.
- Papel de banco dedicado ao Zabbix; não usar superusuário de bootstrap como credencial permanente de server/frontend. Confirmar privilégios necessários de criação/migração de schema na versão.
- Segredos exclusivos em `.local/monitoring/`, ignorados e fora do build/Git, com mounts read-only quando suportados. Nenhuma senha literal no Compose, comandos versionados, exports ou logs. Client técnico não aceita login interativo, password grant ou redirects de aplicação.
- Trocar senha administrativa padrão e desabilitar acesso guest antes da validação; autora mantém senhas no ambiente, sem enviá-las ao chat.
- Banco preserva configuração, histórico e eventos do Zabbix; não exportar seu conteúdo bruto. Volume não é backup. Coletor não persiste cópia dos eventos ou tokens; token de serviço, se cacheado, fica apenas em memória e é renovado de modo limitado.
- Histórico bruto de itens e eventos de trigger em sete dias, configurados pelo housekeeping suportado e conferidos em T03. Trends agregadas seguem default dos itens, sem override global. Distinguir política configurada de expurgo efetivamente observado; não esperar sete dias nem apagar dados para simular aceite.
- Logs rotacionados: 10 MiB × 3 por serviço, sem debug/trace que exponha HTTP. Medir consumo com todos os serviços do cenário; não reutilizar limite de 512 MiB do Kuma como dimensionamento do conjunto.
- Limites iniciais definidos após inspeção do daemon (7,61 GiB, 12 CPUs): PostgreSQL 512 MiB, server 512 MiB, frontend 384 MiB e coletor 128 MiB. São tetos iniciais, não dimensionamento comprovado. Espera inicial finita de 180 s e parada graciosa de 30 s. Se insuficiente, registrar causa e revisar, não esperar indefinidamente.

## 5. Disponibilidade da API

Usar **web scenario** executado pelo Zabbix server, pois falha de conexão precisa resultar em falha observável do cenário. Um item HTTP que fica unsupported não deve ser tratado automaticamente como zero/serviço saudável.

| Campo | Contrato implementado |
| --- | --- |
| Host / cenário / etapa | `secureops-api` / `api-health` / `health` |
| Método / destino | GET `http://api:3000/health` |
| Intervalo / timeout / tentativas | 20 s / 5 s / 1 |
| Código exigido / redirects | Somente 200 / não seguir |
| Autenticação / headers sensíveis | Nenhum |
| Conteúdo | Resposta HTTP 200; probe existente valida separadamente Content-Type e JSON exato |

Trigger de disponibilidade usa `web.test.fail`: diferente de zero abre problema, nova execução válida com zero recupera. Modo **Single**, sem fechamento manual. `nodata` de 90s validado em ensaio controlado: problema em 118s da última amostra, compatível com avaliação periódica; último sucesso antigo não comprova saúde atual.

Implementação em `infra/monitoring/availability-host.json`: um host/grupo fictícios, um cenário e duas triggers. Expressões `last(/secureops-api/web.test.fail[api-health])<>0` e `nodata(/secureops-api/web.test.fail[api-health],90s)=1`; Average/Warning, Single e sem fechamento manual. Schema/gramática, importação, vinculação, ciclos e negativos verificados separadamente. HTTP500/302 em alvo fictício falharam; ausência de amostras foi distinguida de queda da API. Sem dados recentes, condição desconhecida/problema técnico. Parada do próprio server interrompe avaliação; não há monitor externo de si mesmo nesta entrega.

Antes do ensaio, esperar duas execuções saudáveis após criação/configuração do cenário. Executar dois ciclos de parada **somente** da API e retomada preservando dados. Meta local: problema e recuperação em até **60 s** da parada confirmada/saúde confirmada, respectivamente. Registrar comando, mudança efetiva, amostra e evento; não atribuir ao monitor a duração exata da falha. Monitor e banco permanecem ativos.

Testar alvo auxiliar isolado com 500 e redirect para demonstrar que não aparece saudável; não modificar a API nem deixar o cenário principal apontando para o auxiliar.

## 6. Segurança: falhas repetidas de autenticação

### Fonte e interpretação

- Realm fixo `secureops-lab`, client fixo `secureops-gateway`, tipo exato `LOGIN_ERROR`.
- Contagem **agregada do client**, não por usuário ou IP. Conta eventos, não pessoas nem necessariamente submissões únicas no navegador. Comprovar a relação entre submissão e evento no cenário real antes de apresentar o teste como cinco tentativas.
- Falhas de senha/OTP que gerarem esse evento podem contribuir. Observar tipos/erros reais; não prometer cobertura de toda falha de MFA a partir do nome do evento.
- Login bem-sucedido não zera a janela; 403 de visitante após autenticar é autorização negada no gateway e não deve ser reclassificado como `LOGIN_ERROR`.
- Console de conta, administração e outros clients ficam fora do filtro. É uma regra educacional de triagem, não detecção completa de brute force, comprometimento ou ataques distribuídos.

### Coletor implementado: leitura sob demanda, sem varrer logs

Código TypeScript em `apps/identity-event-collector/`, com suporte nativo a tipos apagáveis do Node 24.22.1, sem npm/framework em runtime. Configuração exige somente LOGIN_ERROR/86400; `realmId` interno não é o nome do realm: ID conferido no provisionamento e fixo por arquivo, não parâmetro do chamador. Janelas reais vazias/não vazias e IDs/tempo/escopo validados. Payloads de `infra/monitoring/security-config.mjs` aplicados pela API oficial e exercitados no Zabbix real; saturação/bytes/fronteiras em fixtures, sem alegar carga real de 1001 eventos.

O Zabbix consulta o coletor via item HTTP agent a cada 30 s. Endpoint interno de métricas, GET, destino fixo e autenticação por segredo compartilhado em header, distinto do secret do Keycloak. Requisições sem segredo válido recebem 401/403 e não disparam consulta ao provedor. Não aceitar URL, realm, client ou janela arbitrários do chamador. Essa é uma interface de métricas do coletor, não um novo endpoint da API monitorada.

Para cada amostra:

1. Obter token por client credentials com client técnico exclusivo. Não usar credencial de usuário, gateway ou administrador. Validar por ensaio que leitura é permitida e alteração de eventos/realm/usuários é negada.
2. Ler `GET /admin/realms/secureops-lab/events/config`, verificando armazenamento habilitado, somente `LOGIN_ERROR` e retenção 86400 segundos. Configuração desabilitada/incompatível é falha de coleta, não contagem zero.
3. Fixar instante `t` em epoch milliseconds e consultar `GET /admin/realms/secureops-lab/events` com `client=secureops-gateway`, `type=LOGIN_ERROR`, `dateFrom=t-300000` e `dateTo=t`. A API 26.8.1 documenta filtros de tempo em milissegundos, `first`, `max` e `direction`.
4. Validar formato, timestamps e escopo também localmente. A janela é inclusiva `[t-300000,t]`. Contar registros únicos por ID estável; ausência de ID/duplicação inconsistente não permite alegar contagem exata. Confirmar representação real antes de fechar esse contrato.
5. Consulta `max=1001`, aceitando até 1000 eventos. Atingir 1001, excesso de bytes, truncamento ou inconsistência invalida a amostra; não publicar parcial como total. Na versão fixada, JpaEventQuery/PaginationUtils passam max diretamente ao JPA, sem teto menor intermediário; max=1 contrastado com consulta de cinco eventos reais. Se isso mudar, revisar paginação/limites antes de implementar e não presumir completude.
6. Responder somente versão do contrato, realm/client fictícios fixos, tamanho da janela, instante da amostra, `collection_ok` e, **apenas no sucesso completo**, `login_errors_5m`. Sem IDs de usuário/evento, e-mail, IP, detalhes de erro, URL de callback, tokens, cookies ou payload bruto.

Limites implementados: streaming até 2 MiB, total de coleta 10s, uma consulta concorrente, sem retries ilimitados; HTTP agent 15s aceito pela imagem. Erros categóricos sanitizados, sem refletir corpo HTTP. `collection_ok=0` omite contagem; diferencia falha da fonte de indisponibilidade do coletor. Master valida contrato/frescor, dependente de contagem descarta amostra inválida, qualidade tem item separado.

Client técnico tem somente `view-events`, com leitura real de events/config e eventos permitida; três escritas sem mudança efetiva (configuração/realm/usuário) negadas 403, com estado selecionado preservado. Criação/configuração usam administração separada/efêmera autorizada, nunca credencial permanente do coletor. Não montar volume Keycloak nem ler seu banco diretamente.

### Triggers, ausência de dados e recuperação

- Itens dependentes extraem contagem e qualidade da resposta. **Não somar contagens sucessivas de uma janela móvel**: os mesmos eventos aparecem em várias amostras por desenho.
- Abrir um problema de severidade proposta Warning quando uma amostra completa tem `login_errors_5m >= 5`; modo Single. Manter o mesmo problema enquanto o limiar continuar excedido.
- Recuperar somente com nova amostra completa de contagem `<5`. Redução pode ocorrer pela passagem do tempo, não significa ameaça contida ou usuário desbloqueado. Meta: recuperação em até 60 s após a janela efetivamente cair abaixo do limiar com coleta funcionando.
- Ausência de dados, 401/403 do provedor, configuração de eventos desabilitada, erro de schema, limite excedido ou timeout **não geram zero** e não recuperam alerta de segurança aberto. Manter último valor como histórico, claramente sem validade atual. A expressão não pode usar perda de frescor como condição que encerre o problema de segurança.
- Falha explícita `collection_ok=0` abre problema técnico; ausência de amostras por 90 s também deve abrir problema técnico. Recuperar só com nova consulta válida. Meta de detecção da indisponibilidade da coleta: até 120 s. Não afirmar recuperação da coleta com base apenas em endpoint HTTP responder.
- Início/reinício sem amostra válida é desconhecido, não saudável. Não executar exclusão de eventos para limpar a janela: aguardar seu esvaziamento natural. Relógios de Keycloak/coletor/Zabbix devem estar coerentes; registrar desvio e suspender a conclusão se comprometer o teste.

Expressões implementadas no host secureops-api: `last(/secureops-api/secureops.auth.errors5m)>=5`; problema técnico `last(/secureops-api/secureops.auth.collection)=0 or nodata(/secureops-api/secureops.auth.collection,90s)=1`, com recuperação explícita por qualidade=1 e nodata=0. Nenhuma perda de frescor participa da recuperação de autenticação. Dois ciclos reais e pipeline fictício comprovaram esse comportamento, com distinção de evidência no PLAN.

## 7. Validação de segurança e preservação da identidade

Com participação da autora e somente contas fictícias existentes:

1. Confirmar janela limpa de eventos do client e coleta válida. Um erro isolado de credencial não deve gerar o problema de segurança.
2. Completar a sequência controlada até pelo menos cinco eventos na mesma janela, em login iniciado pela aplicação; registrar horários e apenas campos permitidos. Meta de abertura: até 60 s após o quinto evento persistido. Nunca solicitar senha, OTP, token ou cookie no chat.
3. Manter a condição por mais de uma amostra: deve existir um só problema ativo para a trigger, não um por polling.
4. Aguardar contagem cair abaixo de cinco sem excluir eventos; observar recuperação. Repetir um segundo ciclo para comprovar nova abertura após recuperação.
5. Demonstrar que login bem-sucedido e negação 403 da visitante não incrementam a regra; eventos de outro client não entram na contagem. Preferir testes de contrato isolados para casos difíceis e distinguir essa evidência da coleta real.
6. Exercitar falha da fonte e do coletor separadamente, inclusive com problema de segurança aberto: nenhum zero/falsa recuperação. Usar fixture isolada para token inválido, 403, schema/limites e permissão de escrita negada quando o teste no realm real exigiria operações arriscadas. Uma fixture não comprova as permissões reais: a negativa real deve usar operação sem mudança efetiva e verificação de estado antes/depois.
7. Confirmar operadora permitida com senha+TOTP, visitante autenticada negada, sessões conforme entrega 02, grupos/credenciais preservados. Não mudar proteção contra brute force para produzir alertas. Pausa do Keycloak não deve alterar o resultado do health check interno da API se esta continua saudável.

Reiniciar/recriar apenas componentes novos, mantendo volumes, deve preservar conta, cenário, itens, triggers, dashboard e eventos Zabbix. Coletor reconstrói janela consultando eventos persistidos, sem somar contagens antigas. Não exige backup/HA e não comprova eventos ocorridos/perdidos durante indisponibilidade do próprio Keycloak ou períodos maiores que a retenção.

## 8. Fronteira com a entrega 04

Zabbix é a fonte dos problemas/recuperações de monitoramento desta entrega. Registrar nomes lógicos, IDs de problema/recuperação quando disponíveis, timestamps, severidade e tags estáveis propostas `service=secureops-api` e `category=availability|authentication|collection`. Exportar somente configuração suportada e sanitizada, nunca banco/credenciais.

**Não configurar webhook ou instalar n8n agora.** A entrega 04 definirá o contrato real de integração, autenticação, retries, deduplicação persistente, eventos fora de ordem, responsabilidades de estado e notificação. Problema único no Zabbix não comprova deduplicação da futura automação nem entrega garantida. O antigo receptor de captura do Kuma é removido do plano, não substituído por implementação antecipada de incidentes.

## 9. Critérios de aceite

| ID | Critério | Evidência exigida |
| --- | --- | --- |
| MO-01 | Decisões e viabilidade | M-D01–M-D06 resolvidas, imagens/digests/opções, porta, permissões de volume, limites de memória e caminhos de prontidão conferidos |
| MO-02 | Exposição mínima e administração | Configuração resolvida + bindings reais; API intacta, somente painel novo em loopback, banco/coletor/server sem publicação; painel protegido, senha padrão substituída, guest desabilitado, sem socket/root não aprovado |
| MO-03 | Disponibilidade e limites HTTP | Duas execuções saudáveis e probe; 500/redirect em alvo isolado não saudáveis; ausência de resultados detectada |
| MO-04 | Queda/recuperação repetíveis | Dois ciclos reais só da API, problema/recuperação em até 60 s, monitor e banco ativos, horários e identidade dos eventos registrados |
| MO-05 | Coleta restrita e sanitizada | Client técnico de leitura real, escrita negada sem alterar dados, filtros/configuração/janela corretos, endpoint agregado autenticado e ausência de dados sensíveis na saída/logs |
| MO-06 | Regra de segurança | Erro isolado não abre; ≥5 eventos em 5 min abre em até 60 s, um problema por condição, recuperação por janela válida e segundo ciclo; tipos reais observados e sem atribuir ataque |
| MO-07 | Falhas não viram saúde | Fonte indisponível, coletor parado, credencial inválida, eventos desabilitados, schema/limite inválidos tratados; problema técnico até 120 s; nenhum zero/falsa recuperação do alerta aberto |
| MO-08 | Persistência e retenção | Reinício/recriação dos componentes novos sem apagar volumes preservam conta/configuração/eventos e novo ciclo funciona; retenções configuradas e limitações de expurgo/lacunas documentadas |
| MO-09 | Identidade preservada | Operadora com senha+OTP permitida, visitante autenticada 403, credenciais/grupos/sessões preservados; sucesso/403 não classificados como LOGIN_ERROR; indisponibilidade da fonte não implica queda da API |
| MO-10 | Regressão e reprodução | Suites existentes de 35 API, 10 estáticos e 12 verificações OIDC isoladas, discovery/probe, composições, runbook, sanitização e evidências consistentes; diferenciar fixture, inspeção e relato manual |

Só concluir com critérios executados com sucesso. Aprovação do escopo, leitura de docs, export de template ou containers iniciados não comprovam aceite. Decisão/interação/ferramenta indisponível deixa pendência/bloqueio explícito.

## 10. Fontes consultadas e limitações desta revisão

Consultas somente leitura em 25/10/2026:

- [Zabbix 7.0 — containers, componentes e tags](https://www.zabbix.com/documentation/7.0/en/manual/installation/containers).
- [Requisitos e PostgreSQL suportado](https://www.zabbix.com/documentation/7.0/en/manual/installation/requirements).
- [Web monitoring: cenário, tentativas, código e redirects](https://www.zabbix.com/documentation/7.0/en/manual/web_monitoring).
- [HTTP agent e comportamento unsupported](https://www.zabbix.com/documentation/7.0/en/manual/config/items/itemtypes/http).
- [Triggers](https://www.zabbix.com/documentation/7.0/en/manual/config/triggers/trigger) e [funções de histórico/nodata](https://www.zabbix.com/documentation/7.0/en/manual/appendix/functions/history).
- Metadados Docker Hub: [server 7.0.32](https://hub.docker.com/v2/repositories/zabbix/zabbix-server-pgsql/tags/alpine-7.0.32), [frontend 7.0.32](https://hub.docker.com/v2/repositories/zabbix/zabbix-web-nginx-pgsql/tags/alpine-7.0.32), [PostgreSQL 17.11](https://hub.docker.com/v2/repositories/library/postgres/tags/17.11-bookworm).
- [Keycloak Admin REST 26.8.1 — eventos/configuração e filtros](https://www.keycloak.org/docs-api/26.8.1/rest-api/index.html).
- [Keycloak 26.8.1 — implementação de autorização e consulta de eventos](https://github.com/keycloak/keycloak/blob/26.8.1/services/src/main/java/org/keycloak/services/resources/admin/RealmAdminResource.java).
- [Keycloak 26.8.1 — consulta JPA e limites de tempo](https://github.com/keycloak/keycloak/blob/26.8.1/model/jpa/src/main/java/org/keycloak/events/jpa/JpaEventQuery.java).
- [Keycloak 26.8.1 — limite passado diretamente ao JPA](https://github.com/keycloak/keycloak/blob/26.8.1/model/jpa/src/main/java/org/keycloak/models/jpa/PaginationUtils.java), reconferido em 26/10.
- [Keycloak 26.8.1 — campos da representação de evento](https://github.com/keycloak/keycloak/blob/26.8.1/core/src/main/java/org/keycloak/representations/idm/EventRepresentation.java).
- [Administração Keycloak 26.8.1 — armazenamento e expiração de eventos](https://www.keycloak.org/docs/26.8.1/server_admin/index.html).

Documentação online pode evoluir; opções conferidas no patch/imagem selecionado. Revisão inicial foi somente leitura; depois houve execução real de infraestrutura, disponibilidade e segurança. Formato agregado observado e validações executadas constam no PLAN/evidências, sem inferir segurança a partir de container iniciado. Preparação inicial e estado final são registros distintos.
