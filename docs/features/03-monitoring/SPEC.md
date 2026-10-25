# SPEC 03 — Monitoramento com Zabbix

**Estado:** em implementação, iniciada em 25/10/2026. A autora aprovou explicitamente M-D01–M-D06 e a sequência de implementação após a revisão documental. Disponibilidade primeiro, coleta de segurança depois; n8n fica para a entrega 04, sem IA. Aprovação não comprova viabilidade ou critérios de aceite; resultados reais no [PLAN](PLAN.md).

Referências: [README](../../../README.md), [arquitetura](../../architecture.md), [roadmap](../../roadmap.md), [Fundação Local](../01-local-foundation/SPEC.md), [Identidade e acesso](../02-identity-access/SPEC.md) e [PLAN](PLAN.md).

## 1. Objetivo, estado real e substituição do rascunho

Demonstrar no Zabbix dois resultados distintos:

1. **Disponibilidade:** detectar queda e recuperação da API pela rede Docker.
2. **Segurança de acesso:** sinalizar pelo menos cinco eventos de falha de autenticação em cinco minutos no client da aplicação, usando eventos do Keycloak.

Fundação e identidade estão concluídas. `compose.yaml` mantém API somente em `service` interna, sem publicação de porta ou mounts. `compose.identity.yaml` implementa Keycloak 26.8.1 e OAuth2 Proxy. O gateway exige MFA e grupo exato; logs de requisição e autenticação estão desabilitados. Não existe Kuma, Zabbix, coletor ou n8n implementado.

Esta SPEC **substitui integralmente** o rascunho Kuma: porta 3001, banco embutido, volume `kuma-data`, heartbeats e payloads `heartbeat/monitor/msg` deixam de orientar a implementação. Referências a Kuma no README, arquitetura e roadmap são o desenho anterior, não uma alternativa a implementar. Alinhar esses documentos na preparação da implementação, sem alterar o estado concluído da entrega 02. Não interpretar a substituição como remoção de serviço ou volume existente: não há Kuma instalado.

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
| M-D01 | Zabbix 7.0 LTS, patch candidato 7.0.32; PostgreSQL 17.11; frontend Nginx | Família documentada, imagens separadas oficiais e banco compatível. Custa mais memória e configuração que Kuma. Sem TimescaleDB, proxy, agent, Java gateway ou web service. |
| M-D02 | Frontend em `http://localhost:8081`, publicação exclusiva `127.0.0.1:8081:8080`; comunicação local sem TLS | Exceção local: painel HTTP, sessão, protocolo PostgreSQL e tokens internos não têm confidencialidade TLS. Somente contas fictícias, host/daemon confiáveis e segredos exclusivos. Conferir cookies, logout e bloqueio sem sessão antes do aceite; não relaxar validações para fazer HTTP funcionar. |
| M-D03 | Redes separadas conforme seção 4; PostgreSQL em volume nomeado próprio | API fica intacta. Frontend ganha rota de saída na bridge `operations`; coletor participa de `identity`, que já não é interna. Não alegar egress bloqueado ou isolamento absoluto do host. Nenhum banco/coletor/Zabbix server publicado no host. |
| M-D04 | Coleta via Admin REST, client técnico confidencial com service account e somente `realm-management/view-events` | Reutiliza interface documentada, sem socket Docker, plugin Java nem leitura de logs brutos. A permissão permite ler eventos do realm, **não só do client da aplicação**; o filtro no coletor não é fronteira de autorização do Keycloak. Exposição desse privilégio precisa de aprovação explícita. |
| M-D05 | Habilitar persistência de `LOGIN_ERROR` no realm, retenção de 24 h; coletor entrega somente agregado de cinco minutos | Eventos brutos permanecem no volume sensível do Keycloak e podem conter identificadores/IP/detalhes. Preservar tipos/configuração anteriores e não apagar histórico. Se a configuração existente tiver retenção/tipos conflitantes, apresentar a diferença antes de alterar. |
| M-D06 | Cenário web a cada 20 s, timeout 5 s e uma tentativa; coleta de segurança a cada 30 s; limiar agregado ≥5 eventos/300 s | Demonstração curta. Primeiro erro da checagem web pode abrir problema; um `LOGIN_ERROR` isolado não abre o alerta de segurança. Limite não é padrão universal nem prova de ataque. |

Qualquer alternativa que mude redes, privilégios, dados armazenados, transporte ou comportamento volta à revisão. Não reutilizar administrador/bootstrap ou client secret do gateway para coletar eventos. Não desabilitar MFA, autorização, TLS validation ou proteção contra brute force. Caso proteções existentes impeçam produzir o cenário, discutir outro procedimento de teste, não enfraquecê-las.

## 4. Composição e persistência propostas

Overlay futuro: `compose.monitoring.yaml`. Disponibilidade deve funcionar com base + monitoramento sem iniciar identidade; coletor fica em profile explícito, usado com base + identidade + monitoramento. Profiles do Compose selecionam serviços, **não habilitam/desabilitam itens ou triggers no banco do Zabbix**: documentar também como habilitar o cenário de segurança no modo completo e deixá-lo desabilitado no modo somente disponibilidade, sem excluir seu histórico. Confirmar semântica dos profiles na configuração resolvida; não criar dependência que inicie Keycloak para executar só health checks.

| Serviço proposto | Redes | Responsabilidade |
| --- | --- | --- |
| `zabbix-db` | `monitoring` interna | Banco exclusivo do Zabbix, volume `zabbix-db-data`; sem porta no host |
| `zabbix-server` | `monitoring`, `service` | Cenário web, itens HTTP, triggers e eventos; sem publicação de 10051 |
| `zabbix-web` | `monitoring`, `operations` bridge não interna | Frontend autenticado, única publicação nova em loopback |
| `identity-event-collector` | `monitoring`, `identity` | Ler eventos do Keycloak; endpoint agregado interno autenticado, sem porta no host ou acesso ao volume Keycloak |

API continua somente em `service`. Keycloak/gateway mantêm redes, portas e credenciais existentes. O coletor não participa de `service`; server/frontend não participam de `identity`. `operations` resolve publicação do frontend sem pressupor que rede exclusivamente interna publique corretamente neste Docker. Testar os bindings reais.

### Versões candidatas consultadas, não executadas

Consultas HTTP de metadados oficiais em 25/10/2026 confirmaram tags e manifesto `linux/amd64`. Digests abaixo são do índice retornado pelo Docker Hub, não resultado de pull ou teste de compatibilidade:

| Imagem candidata | Digest do índice consultado |
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
- Histórico de itens de sete dias e retenção de eventos do Zabbix de sete dias aprovados, ainda a configurar em T03, verificando limites e housekeeping suportados. Distinguir política configurada de expurgo efetivamente observado; não esperar sete dias nem apagar dados para simular aceite.
- Logs rotacionados: 10 MiB × 3 por serviço, sem debug/trace que exponha HTTP. Medir consumo com todos os serviços do cenário; não reutilizar limite de 512 MiB do Kuma como dimensionamento do conjunto.
- Limites iniciais definidos após inspeção do daemon (7,61 GiB, 12 CPUs): PostgreSQL 512 MiB, server 512 MiB, frontend 384 MiB; coletor terá limite definido em T06 antes da subida. São tetos iniciais, não dimensionamento comprovado. Espera inicial finita de 180 s e parada graciosa de 30 s. Se insuficiente, registrar causa e revisar, não esperar indefinidamente.

## 5. Disponibilidade da API

Usar **web scenario** executado pelo Zabbix server, pois falha de conexão precisa resultar em falha observável do cenário. Um item HTTP que fica unsupported não deve ser tratado automaticamente como zero/serviço saudável.

| Campo | Contrato proposto |
| --- | --- |
| Host / cenário / etapa | `secureops-api` / `api-health` / `health` |
| Método / destino | GET `http://api:3000/health` |
| Intervalo / timeout / tentativas | 20 s / 5 s / 1 |
| Código exigido / redirects | Somente 200 / não seguir |
| Autenticação / headers sensíveis | Nenhum |
| Conteúdo | Resposta HTTP 200; probe existente valida separadamente Content-Type e JSON exato |

Trigger de disponibilidade usa o item de falha do cenário (`web.test.fail`), com expressão validada na versão: valor diferente de zero abre problema; execução válida com zero recupera. Modo de geração de problemas **Single**, sem fechamentos manuais para substituir recuperação real. Incluir detecção de ausência de resultados para que último sucesso antigo não seja exibido como saúde atual; `nodata` de 90 s é candidato a validar.

Antes do ensaio, esperar duas execuções saudáveis após criação/configuração do cenário. Executar dois ciclos de parada **somente** da API e retomada preservando dados. Meta local: problema e recuperação em até **60 s** da parada confirmada/saúde confirmada, respectivamente. Registrar comando, mudança efetiva, amostra e evento; não atribuir ao monitor a duração exata da falha. Monitor e banco permanecem ativos.

Testar alvo auxiliar isolado com 500 e redirect para demonstrar que não aparece saudável; não modificar a API nem deixar o cenário principal apontando para o auxiliar.

## 6. Segurança: falhas repetidas de autenticação

### Fonte e interpretação

- Realm fixo `secureops-lab`, client fixo `secureops-gateway`, tipo exato `LOGIN_ERROR`.
- Contagem **agregada do client**, não por usuário ou IP. Conta eventos, não pessoas nem necessariamente submissões únicas no navegador. Comprovar a relação entre submissão e evento no cenário real antes de apresentar o teste como cinco tentativas.
- Falhas de senha/OTP que gerarem esse evento podem contribuir. Observar tipos/erros reais; não prometer cobertura de toda falha de MFA a partir do nome do evento.
- Login bem-sucedido não zera a janela; 403 de visitante após autenticar é autorização negada no gateway e não deve ser reclassificado como `LOGIN_ERROR`.
- Console de conta, administração e outros clients ficam fora do filtro. É uma regra educacional de triagem, não detecção completa de brute force, comprometimento ou ataques distribuídos.

### Coletor proposto: leitura sob demanda, sem varrer logs

O Zabbix consulta o coletor via item HTTP agent a cada 30 s. Endpoint interno de métricas, GET, destino fixo e autenticação por segredo compartilhado em header, distinto do secret do Keycloak. Requisições sem segredo válido recebem 401/403 e não disparam consulta ao provedor. Não aceitar URL, realm, client ou janela arbitrários do chamador. Essa é uma interface de métricas do coletor, não um novo endpoint da API monitorada.

Para cada amostra:

1. Obter token por client credentials com client técnico exclusivo. Não usar credencial de usuário, gateway ou administrador. Validar por ensaio que leitura é permitida e alteração de eventos/realm/usuários é negada.
2. Ler `GET /admin/realms/secureops-lab/events/config`, verificando armazenamento habilitado, `LOGIN_ERROR` incluído e retenção compatível. Configuração desabilitada/incompatível é falha de coleta, não contagem zero.
3. Fixar instante `t` em epoch milliseconds e consultar `GET /admin/realms/secureops-lab/events` com `client=secureops-gateway`, `type=LOGIN_ERROR`, `dateFrom=t-300000` e `dateTo=t`. A API 26.8.1 documenta filtros de tempo em milissegundos, `first`, `max` e `direction`.
4. Validar formato, timestamps e escopo também localmente. A janela é inclusiva `[t-300000,t]`. Contar registros únicos por ID estável; ausência de ID/duplicação inconsistente não permite alegar contagem exata. Confirmar representação real antes de fechar esse contrato.
5. Fazer consulta limitada que permita comprovar janela completa: proposta de `max=1001`, aceitando no máximo 1000 eventos. Resposta que atinge o limite, truncamento, limite efetivo diferente no servidor ou inconsistência tornam a amostra inválida; não publicar parcial como total. Se necessário outro mecanismo de paginação, revisá-lo antes de implementar, com teto de páginas/tempo e teste de duplicação/fronteiras.
6. Responder somente versão do contrato, realm/client fictícios fixos, tamanho da janela, instante da amostra, `collection_ok` e, **apenas no sucesso completo**, `login_errors_5m`. Sem IDs de usuário/evento, e-mail, IP, detalhes de erro, URL de callback, tokens, cookies ou payload bruto.

Limitar corpo de resposta aceito do Keycloak a 2 MiB, duração total de coleta a 10 s, uma consulta em andamento e sem retries ilimitados. Timeout do HTTP agent proposto de 15 s, sujeito a confirmação na imagem. Falhas usam códigos categóricos sanitizados; nunca refletir erro HTTP bruto. Resposta válida do coletor pode trazer `collection_ok=0`, sem contagem, para separar falha da fonte de indisponibilidade do coletor.

Client técnico terá somente `view-events`. Análise do código 26.8.1 confirmou esse requisito tanto em `/events` quanto em `/events/config`; atualização da configuração exige `manage-events`. Isso é evidência estática, não prova de permissões no realm real. A criação/configuração inicial exige ação administrativa separada e autorizada, sem dar essa permissão ao coletor. Não montar volume do Keycloak nem ler seu banco diretamente.

### Triggers, ausência de dados e recuperação

- Itens dependentes extraem contagem e qualidade da resposta. **Não somar contagens sucessivas de uma janela móvel**: os mesmos eventos aparecem em várias amostras por desenho.
- Abrir um problema de severidade proposta Warning quando uma amostra completa tem `login_errors_5m >= 5`; modo Single. Manter o mesmo problema enquanto o limiar continuar excedido.
- Recuperar somente com nova amostra completa de contagem `<5`. Redução pode ocorrer pela passagem do tempo, não significa ameaça contida ou usuário desbloqueado. Meta: recuperação em até 60 s após a janela efetivamente cair abaixo do limiar com coleta funcionando.
- Ausência de dados, 401/403 do provedor, configuração de eventos desabilitada, erro de schema, limite excedido ou timeout **não geram zero** e não recuperam alerta de segurança aberto. Manter último valor como histórico, claramente sem validade atual. A expressão não pode usar perda de frescor como condição que encerre o problema de segurança.
- Falha explícita `collection_ok=0` abre problema técnico; ausência de amostras por 90 s também deve abrir problema técnico. Recuperar só com nova consulta válida. Meta de detecção da indisponibilidade da coleta: até 120 s. Não afirmar recuperação da coleta com base apenas em endpoint HTTP responder.
- Início/reinício sem amostra válida é desconhecido, não saudável. Não executar exclusão de eventos para limpar a janela: aguardar seu esvaziamento natural. Relógios de Keycloak/coletor/Zabbix devem estar coerentes; registrar desvio e suspender a conclusão se comprometer o teste.

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
- [Keycloak 26.8.1 — campos da representação de evento](https://github.com/keycloak/keycloak/blob/26.8.1/core/src/main/java/org/keycloak/representations/idm/EventRepresentation.java).
- [Administração Keycloak 26.8.1 — armazenamento e expiração de eventos](https://www.keycloak.org/docs/26.8.1/server_admin/index.html).

Documentação online da família Zabbix pode evoluir; conferir cada opção no patch/imagem selecionado. Na revisão inicial não houve execução. Após aprovação, as três imagens fixadas foram baixadas e seus entrypoints/usuários inspecionados; resultados e estado parcial estão no PLAN e nas evidências. O formato agregado continua contrato proposto, não payload observado. Nenhum critério de segurança deve ser presumido a partir da infraestrutura de disponibilidade.
