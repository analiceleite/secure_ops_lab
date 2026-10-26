# Evidências 03 — Monitoramento com Zabbix

**Estado:** concluída em 26/10/2026, MO-01–MO-10 aprovados. Matriz final na seção 16 e revisão/sanitização na seção 17; seções anteriores preservam pendências/resultados históricos de cada coleta, não o estado atual. n8n/automação permanecem não implementados.

## 1. Ambiente e preparação

- Docker Engine 28.5.1, Compose 2.40.2-desktop.1, Linux x86_64, 12 CPUs, 8.171.757.568 bytes de memória do daemon (aproximadamente 7,61 GiB).
- Porta 8081 sem listener na inspeção anterior à subida. API, Keycloak e gateway já estavam ativos; API healthy e publicações de identidade em 127.0.0.1.
- Três imagens por tag+digest da SPEC baixadas com sucesso. Entry points e bibliotecas de configuração foram lidos nas próprias imagens, com rede none e restrições. Server/frontend têm usuário 1997; PostgreSQL permite execução explícita como 999:999 com volume novo já pertencente a postgres. Nenhum container foi executado como root.
- Conferidos suporte a POSTGRES_PASSWORD_FILE, configuração mascarada de DBPassword com DEBUG_MODE=false, pg_isready e curl/ping do frontend. PostgreSQL suporta peer no socket e SCRAM TCP. Server não tem health check declarado na imagem.
- Criados dois segredos exclusivos em `.local/monitoring/` com ACL restrita ao usuário atual. Segundo acionamento do inicializador recusado; comparação de hashes em memória confirmou que os arquivos permaneceram iguais, sem exibir hashes/valores. Pasta ignorada e fora do build da API.

## 2. Inspeção somente leitura da identidade

Um container Node efêmero na rede identity leu bootstrap local por mount read-only, obteve token administrativo em memória e consultou somente realm/configuração de eventos. Nenhum token ou resposta bruta foi exportado. Essa credencial é de diagnóstico administrativo separado, **não a credencial do futuro coletor**.

Resultado selecionado: `eventsEnabled=false`, `LOGIN_ERROR` entre tipos retornados, listener `jboss-logging`, admin events desabilitados, `sslRequired=external` e **`bruteForceProtected=false` preexistente**. Não havia retenção explícita retornada. Nenhuma dessas opções foi alterada; não declarar proteção brute force habilitada. O futuro armazenamento deve ser configurado explicitamente e documentar a diferença entre tipos efetivos padrão retornados e o recorte desejado, antes de habilitar eventos.

Não foram consultadas credenciais OTP/senhas, criados clients, alterados grupos ou produzidos logins falsos para gerar eventos. Client técnico/view-events e testes reais da coleta permanecem pendentes.

## 3. Implementação e subida reais — 11:20–11:24, -03:00

- Overlay `compose.monitoring.yaml`: PostgreSQL, Zabbix server e frontend; redes monitoring interna e operations bridge não interna. Server também em service; API intacta.
- PostgreSQL iniciou como UID/GID 999. Script de primeiro volume criou role `zabbix` e banco próprio. Verificação real de rolsuper/rolcreatedb/rolcreaterole/rolreplication retornou **false em todos**. Server/frontend não recebem o segredo de bootstrap.
- Script de inicialização só é executado em banco vazio. Credenciais não foram exibidas. Configurações de autenticação efetivas consultadas em pg_hba_file_rules: somente **peer nos sockets locais e scram-sha-256 nas regras host**; sem trust. Conexão TCP como zabbix sem senha foi rejeitada com “no password supplied”.
- Schema importado pela imagem Zabbix com role dedicada, `mandatory=07000000`, `optional=07000030`. Log selecionado confirmou server 7.0.32 revision `0d6fa36`, versão de banco e processo principal iniciado em 11:21:09 (-03:00).
- Frontend healthy, `/ping` 200 e `apiinfo.version` retornando 7.0.32. `up --wait` não substitui confirmação de inicialização do server; as verificações de schema/log/API são complementares.
- Comparação de IDs/start times antes/depois confirmou que **API, Keycloak e gateway existentes não foram recriados nem reiniciados**. Nenhuma porta da API publicada e nenhum volume/segredo de identidade removido ou alterado.

## 4. Validações executadas e limites

- `Test-MonitoringInfrastructure.ps1`: **23 checks estáticos aprovados**, envolvendo base, base+monitoramento e composição com identidade. API comparada à configuração base, redes e segredos/publicações conferidos.
- `Test-MonitoringInfrastructure.ps1 -Runtime`: **42 checks totais aprovados**, somando inspeções de containers/restrições/redes/publicações/usuários/mounts, role, schema e ping. Não são 42 testes de monitoramento funcional.
- Restrições reais: usuários não root esperados, cap_drop ALL, NoNewPrivs, sem privileged/socket. Banco só em monitoring; server em monitoring+service; frontend em monitoring+operations; API só em service e sem mounts.
- Binding novo observado: somente **127.0.0.1:8081 → 8080** do frontend. Banco/server sem publicação. Tentativa em `[::1]:8081` falhou. Não comprova isolamento absoluto do host nem bloqueio de egress.
- Dashboard sem sessão retornou HTTP **200**, título Warning e mensagem de não autenticado, não painel administrativo. Não exigir 401/403 para concluir essa negativa. Inspeção read-only de memberships confirmou guest no grupo **Disabled**, users_status=1; também está em Guests/Internal. Não houve alteração de usuário via SQL.
- **Troca da senha Admin, novo login/logout e cookies autenticados continuam pendentes da autora.** Não houve sessão autenticada de navegador coletada pelo agente. Não houve alteração de senha do painel pelo agente.
- Host padrão `Zabbix server` já veio habilitado e registrou falha de agente local; nenhum agente foi instalado. Deve ser desabilitado pela UI ao configurar o host do lab. Isso é ruído da configuração de fábrica, não incidente da API.
- Logs dos três novos serviços examinados em memória: nenhuma correspondência aos dois segredos novos conhecidos ou padrão selecionado de JWT. Conteúdo bruto não exportado; varredura limitada, sem garantia universal.
- Snapshot de memória: banco **163,3 MiB / 512 MiB**, server **49,87 MiB / 512 MiB**, frontend **24,03 MiB / 384 MiB**. Não representa pico, teste de carga ou dimensionamento mínimo.

### Erros de execução corrigidos

Primeiras inspeções shell falharam por quoting/CRLF ao atravessar PowerShell para sh. Repetidas por leitura direta dos arquivos com `--entrypoint cat` e validação `bash -n`, sem executar configurações do ambiente. Primeiro check estático confundiu `@($null).Count` com uma porta existente; corrigida a verificação de propriedade ausente e repetido o conjunto completo. Esses erros não motivaram permissões extras, rede pública ou remoção de dados.

## 5. Regressão antecipada após novas redes

- API: **35 aprovados**, zero falhas, **5799.136844 ms**; execução por Compose completo com build de teste/cache e container sem rede.
- Configuração de identidade: **10 aprovados**, zero falhas, **227.398807 ms**; imagem local, sem rede, mount read-only.
- Proxy OIDC real isolado: **12 verificações aprovadas**, incluindo audience/issuer/assinatura/nonce/state/grupos/cookie; rede temporária interna, sem publicação, gateway principal inalterado.
- Probe API aprovado. Discovery interno 200, issuer exato, JWKS 200 e token sem secret rejeitado 401.
- Revisão de arquivos: 73 links Markdown locais com destinos existentes (âncoras não verificadas), sintaxe PowerShell e LF do script Linux aprovados; `git diff --check` aprovado. Varredura de 45 arquivos versionados/versionáveis sem correspondências aos segredos locais conhecidos ou padrões selecionados de chave privada/JWT; `.local` fora da seleção. Limites de varredura preservados, sem garantia universal.

Isso não substitui regressão final após implementar coletor/triggers nem confirma novo login de navegador no ambiente principal. Entrega 02 permanece concluída, com dados preservados.

## 6. Estado do aceite

| Critério | Estado nesta coleta |
| --- | --- |
| MO-01 | Parcial: decisões/imagens/recursos/infra conferidos; expressões reais e contrato/permissões do coletor ainda pendentes |
| MO-02 | Parcial: exposição/restrições/guest verificadas; troca de senha Admin e testes autenticados de painel pendentes |
| MO-03/MO-04 | Pendentes: ainda não há cenário web/trigger configurado nem ciclo de parada da API |
| MO-05/MO-06/MO-07 | Pendentes: client/coletor/triggers de segurança não implementados |
| MO-08 | Pendente: primeiro volume/schema funcionando não comprova preservação após reinício/recriação |
| MO-09 | Parcial: containers/configuração preservados e discovery/probe; regressão manual pós-monitoramento ainda pendente |
| MO-10 | Parcial: regressão antecipada aprovada e runbook parcial; fechamento final depende dos demais critérios |

**Estado deixado:** seis serviços ativos (API, Keycloak, gateway e três novos componentes Zabbix). Sem cenário web, coletor, n8n, IA ou e-mail. Volumes/segredos preservados, sem commit/push. Próximo passo é a autora trocar a senha inicial do painel e confirmar novo login/logout, antes de configurar o monitor.

## 7. Checkpoint, senha e preparação da configuração de disponibilidade

Registros acima representam a coleta inicial, não apagam as atualizações abaixo.

- Por solicitação da autora, criado commit **0427f9e**, `feat: iniciar monitoramento Zabbix com infraestrutura local restrita`; sem push, árvore limpa imediatamente depois. Novos arquivos desta etapa ainda não commitados.
- Autora inicialmente informou que manteria a senha padrão; foi sinalizada a divergência com MO-02 e solicitada aprovação de exceção. Em seguida informou **“troquei de senha com sucesso!”**. Registrado como troca bem-sucedida relatada, sem coleta de credenciais. **Nenhuma exceção para senha padrão foi aplicada.** Logout, novo login e atributos autenticados não foram observados pelo agente nem explicitamente confirmados nessa mensagem.
- Preparado `infra/monitoring/availability-host.json`, formato nativo JSON de importação Zabbix 7.0: grupo SecureOps Lab, host secureops-api, cenário api-health GET interno/20 s/5 s/uma tentativa/somente 200/sem redirects. Duas triggers Single e sem fechamento manual: falha HTTP por last(web.test.fail) diferente de zero e ausência de amostras por nodata(90s), com tags estáveis.
- Consultados somente por leitura o schema de importação das classes da imagem fixada, leitores JSON e parser de expressões, além da documentação 7.0 de web monitoring/items. Formato usa `status_codes` na etapa, não o nome inventado `required_codes`; etapas do export não recebem `no` da API httptest.
- Primeira execução do harness: oito testes estáticos passaram, mas validação PHP não iniciou porque **a imagem não inclui PHP CLI**. Não foi instalado pacote nem alterado o container real; ajustado harness para o PHP-FPM 8.5 efetivamente presente na imagem fixada.
- Reexecução completa: **oito testes Node aprovados**, zero falhas, **176.918801 ms**. Controles sobre escopo, HTTP, limites, ausência de credenciais, tags e separação entre falha/ausência de dados.
- **Sete verificações com classes originais Zabbix aprovadas**: aceitação do schema completo, gramática de duas expressões, rejeição de versão não suportada, campo de etapa desconhecido, enum de redirect inválido e host sem nome técnico obrigatório.
- PHP-FPM e cliente FastCGI executados em containers não root, rootfs read-only, cap_drop ALL/NoNewPrivs e memória 128 MiB; rede de teste internal exclusiva por GUID, sem portas no host, banco, secrets ou redes reais. Node estático sem rede; mounts somente de código público read-only. Cleanup limitado aos recursos próprios da chamada.
- Repetição final em aproximadamente 11:42 (-03:00): oito testes Node aprovados (178.24276 ms) e sete verificações originais aprovadas novamente. Consulta final não encontrou containers/redes `secureops-import-*` remanescentes. Revisão documental: 74 links locais com destino existente, sintaxe PowerShell e `git diff --check` aprovados; 51 arquivos versionados/versionáveis sem correspondências aos segredos conhecidos e padrões selecionados de chave privada/JWT. Âncoras e ausência universal de segredos não garantidas.

**Limite e próximo passo:** aprovação offline de schema/gramática não prova que referências a itens web serão vinculadas ou que checks/triggers executam. Nenhum host, cenário ou trigger foi aplicado ao banco real pelo agente; não foi usado acesso SQL para configurar o Zabbix nem credencial/token do painel. Autora deve importar pela UI conforme runbook, conferir duas execuções saudáveis e então iniciar o ensaio controlado T04. MO-02 segue parcial por sessões/cookies, MO-03/MO-04 pendentes de runtime, e coleta de segurança não implementada.

## 8. Importação confirmada e ciclos reais de disponibilidade — 25/10/2026

### Configuração aplicada pela autora, inspecionada pelo agente

Autora informou **“deu certo!”** após instrução de importação e conferência do cenário. Agente consultou somente SELECTs do banco próprio Zabbix para comprovar configuração, amostras e eventos. Não usou SQL para criar/alterar host, cenário, triggers ou contas; não recebeu senha/token do painel.

Confirmado em runtime:

- Host `secureops-api` e cenário `api-health` habilitados, monitorados pelo server; intervalo 20s, uma tentativa, sem autenticação HTTP.
- Etapa `health`, destino exato `http://api:3000/health`, timeout 5s, somente 200, follow_redirects=0.
- Duas triggers habilitadas, Single/type=0, manual_close=0 e recovery_mode=0. Vinculação real ao item web.test.fail, funções last e nodata com janela 90s; expressões armazenadas por referência interna `{36116}<>0` e `{36117}=1`.
- Duas execuções saudáveis recentes separadas por 20s, web.test.fail=0 e código de resposta 200. Estado inicial de ambas triggers normal.

Primeira consulta diagnóstica usou incorretamente a coluna `httptest.attempts`; falhou sem modificar dados. Inspecionado information_schema e corrigido para `httptest.retries`, que corresponde ao campo de tentativas exposto/importado. Não inventar identidade entre nomes do export, API e schema SQL. Script reproduzível usa a coluna efetivamente conferida.

### Script e segurança do ensaio

Criado `scripts/Test-MonitoringAvailability.ps1`. Por padrão só lê configuração/amostras e recusa cenário incompatível, triggers divergentes, ausência de duas amostras saudáveis, API não healthy ou relógios incoerentes. `-RunFailureCycles` executa explicitamente dois ciclos somente da API, com espera finita, sem excluir dados. Um finally tenta retomar somente a API em caso de falha, sem prometer êxito se host/Docker estiver indisponível.

Verificações consideram um evento de problema por ciclo, três amostras falhas (primeira + duas adicionais), recuperação vinculada ao mesmo evento, código 200 após retorno e preservação dos IDs/start times de Keycloak/gateway/banco/server/frontend. Comparação confirmou API retomada no mesmo container, sem recriação.

### Tempos observados — referências locais -03:00

| Medição | Ciclo 1 | Ciclo 2 |
| --- | --- | --- |
| Início do comando stop | 12:04:21.707 | 12:05:28.895 |
| Parada confirmada, referência em segundos | 12:04:23 | 12:05:30 |
| Evento de problema | 12:04:22, ID 31 | 12:05:42, ID 33 |
| Detecção em relação à confirmação | Já detectado antes da confirmação; diferença -1s | 12s depois |
| Início da retomada | 12:05:08.120 | 12:06:28.849 |
| Healthy confirmado após up --wait | 12:05:14 | 12:06:35 |
| Evento de recuperação | 12:05:22, ID 32 | 12:06:42, ID 34 |
| Recuperação após healthy confirmado | 8s | 7s |
| Duração observada problema → recuperação | 60s | 60s |
| Amostras falhas / eventos de problema | 3 / 1 | 3 / 1 |

Ambos os ciclos dentro das metas locais de 60s. No primeiro, o monitor detectou a falha entre início do comando e confirmação da parada; **não existe latência física negativa**. Eventos e referências de confirmação têm resolução de segundos; o valor -1s exprime a escolha da referência, não cronometragem subsegundo ou garantia de disponibilidade instantânea. Duração observada de 60s não é duração exata da falha. Nenhum evento foi encerrado manualmente para fazer o teste passar.

Durante cada parada, três amostras falhas mantiveram **um só problema aberto**. Trigger de ausência de resultados permaneceu normal, corretamente distinguindo API indisponível de perda da coleta. Isso não testa ainda a ativação de nodata nem deduplicação da futura automação n8n.

### Estado após ensaios e pendências

- API healthy, probe aprovado em ambas retomadas. **42 checks de infraestrutura novamente aprovados**, discovery/JWKS aprovados e token sem secret rejeitado com 401. Demais cinco serviços não foram reiniciados nem recriados; volumes/segredos preservados.
- Inspeção final, sem flag de falha, voltou a encontrar duas amostras saudáveis recentes e response code 200. Nenhum novo ciclo provocado por essa inspeção.
- Revisão final: sintaxe PowerShell e `git diff --check` aprovados; 74 links locais com destinos existentes, 52 arquivos versionados/versionáveis sem correspondências aos segredos conhecidos ou padrões selecionados de chave privada/JWT. Âncoras e ausência universal de segredos não garantidas; senha nova do painel não foi recebida nem inspecionada.
- Retenção **ainda não aplicada**: eventos de trigger 365d; override global de history/trends desligado; itens web com history=30d/trends=90d. Valores globais não efetivos eram history=31d/trends=365d. Runbook orienta aplicar history/eventos de trigger 7d pela UI, sem limpeza manual.
- Host padrão `Zabbix server` **ainda habilitado**, embora sem agente; pedir desabilitação somente de sua configuração pela UI, não do container. Não modificar SQL para retirar esse ruído.
- Cookies autenticados/logout/relogin, dashboard, 500/redirect/ativação de nodata e persistência por reinício/recriação continuam pendentes. Password change continua relato da autora, não inspeção do segredo. Coletor/client técnico/eventos Keycloak ainda não provisionados.

**Matriz atual:** MO-04 aprovado com evidência real acima; MO-03 parcial (saúde e ciclos comprovados, negativos restantes); MO-02 parcial (sessão/cookies); MO-01/MO-05–MO-10 continuam parciais/pendentes conforme seus requisitos. Entrega 03 **não concluída**. Sem novo commit/push automático depois do checkpoint 0427f9e.

## 9. Retenção configurada e host de fábrica desabilitado — 25/10/2026, 12:20 -03:00

Autora respondeu **“feito!”** ao procedimento de housekeeping e desabilitação do host padrão. Consultas somente leitura confirmaram:

| Campo real | Resultado |
| --- | --- |
| hk_events_mode | 1 — housekeeping habilitado |
| hk_events_trigger | 7d |
| hk_history_mode | 1 — housekeeping habilitado |
| hk_history_global | 1 — override habilitado |
| hk_history | 7d |
| hk_trends_global | 0 — override de trends não habilitado |
| hk_trends | 365d, valor global não efetivo; permanecem períodos dos itens |
| Host Zabbix server, status | 1 — desabilitado na configuração, sem parar o container |
| Host secureops-api, status | 0 — habilitado |

Isso comprova **política de expurgo configurada**, não remoção observada de dados antigos, backup ou retenção imutável. Nenhuma limpeza manual ou execução forçada de housekeeper. Defaults de histórico dos itens web podem continuar 30d porque o override global de 7d prevalece; tendências agregadas não são esse histórico bruto.

Executado novamente `Test-MonitoringAvailability.ps1` sem flag de falha: duas amostras recentes saudáveis, separadas por 20 s, web.test.fail=0 e HTTP200. Nenhum serviço foi parado ou configuração alterada pelo agente nessa conferência.

Próxima etapa manual preparada no runbook: dashboard privado SecureOps Lab, widgets Web monitoring e Problems filtrados para o host. Documentação 7.0 consultada para campos e comportamento; **dashboard ainda não declarado criado**. Contagem e qualidade da coleta de segurança não têm fonte implementada e não devem aparecer como dados estáticos fictícios no painel. Entrega continua parcial, sem novo commit/push.

## 10. Dashboard e persistência da disponibilidade — 25/10/2026

### Dashboard confirmado

Autora respondeu **“feito!”** ao procedimento de criação/visualização. Inspeção somente leitura em aproximadamente 14:05 (-03:00) confirmou dashboard SecureOps Lab com private=1, zero shares de usuários/grupos e dois widgets:

- Web, “Disponibilidade da API”, groupids apontando para SecureOps Lab e hostids para secureops-api.
- Problems, “Problemas ativos da API”, hostids para secureops-api e show=3. Constantes da própria imagem confirmaram PRIVATE_SHARING=1 e TRIGGERS_OPTION_IN_PROBLEM=3; não inferir significado só pelo número.
- Tags reais conferidas: host service=secureops-api; triggers com service=secureops-api e category=availability/collection, conforme função.

Relato visual é da autora; agente não utilizou sessão autenticada do navegador. Não existem ainda widgets/fonte de contagem de falhas de autenticação ou qualidade do coletor.

### Reinício e recriação dos três componentes novos

Criado Test-MonitoringPersistence.ps1, somente leitura por padrão, com flag explícita para intervenção. Sintaxe PowerShell, help do restart e baseline foram conferidos antes da execução. Teste real concluído aproximadamente 14:11–14:13 (-03:00):

| Verificação | Restart | Recreate |
| --- | --- | --- |
| Containers banco/server/frontend | Mesmos IDs, novos start times | IDs diferentes |
| Volume nomeado PostgreSQL | Mesmo volume | Mesmo volume |
| Snapshot público selecionado | Preservado | Preservado |
| Duas amostras saudáveis novas após retomada | Aprovado | Aprovado |
| API/Keycloak/gateway | Sem parada/reinício | Sem parada/reinício |

Snapshot comparado em memória por hash incluiu host/cenário/etapa/triggers, dashboard/posições/filtros, retenção, metadados de grupos Admin/guest, quatro eventos de disponibilidade anteriores e duas amostras históricas. **Não incluiu senha, hash de senha, token ou cookie**, nem foi exportado como backup. Isso comprova preservação dos campos selecionados, não integridade universal, recuperação de desastre ou autenticação real de conta.

Após retomada, 42 checks de infraestrutura aprovados novamente, probe/discovery/JWKS aprovados e token sem secret negado 401. O script não alterou SQL de configuração; somente comandos Compose autorizados e SELECTs. Sem remoção de volumes, limpeza de dados ou rotação de segredos. Autenticação pós-recriação depende de confirmação da autora.

### Novos ciclos após recriação

Reexecutados dois ciclos reais apenas da API para comprovar execução das triggers após persistência, aproximadamente 14:15–14:18 (-03:00):

| Medição | Ciclo 1 | Ciclo 2 |
| --- | --- | --- |
| Início do stop | 14:15:54.977 | 14:17:07.727 |
| Parada confirmada, epoch | 1792948556 | 1792948628 |
| Evento de problema | 37, clock 1792948562 | 39, clock 1792948642 |
| Detecção após parada confirmada | 6s | 14s |
| Healthy confirmado, epoch | 1792948614 | 1792948693 |
| Evento de recuperação | 38, clock 1792948622 | 40, clock 1792948702 |
| Recuperação após healthy | 8s | 9s |
| Duração observada | 60s | 60s |
| Amostras falhas / problemas por ciclo | 3 / 1 | 3 / 1 |

Probe aprovado nas duas retomadas; API voltou healthy no mesmo container, outros cinco serviços preservados durante esses ciclos. As referências usam segundos, não tempo exato de falha. Nenhuma recuperação manual e nenhuma deduplicação n8n presumida.

### Lacuna de observação anterior — não é teste controlado

Ao revisar eventos intermediários, encontrados problema de nodata **35**, clock 1792942590 (12:36:30 -03:00), e recuperação **36**, clock 1792947534 (13:58:54), **anteriores** ao ensaio de persistência. Histórico revelou intervalo de **4972s** entre amostras clock 1792942562 e 1792947534. A causa não foi determinada; não atribuir a suspensão do computador, falha da API ou ação da autora sem confirmação.

O evento de problema aparece 28s após a última amostra persistida anterior à lacuna; esses registros sem controle de relógio/agendamento/cache do período **não comprovam o limite configurado de 90s**, nem substituem o teste negativo controlado pendente. Registrar a observação, não ajustar timestamps/expressão para fazer o critério passar. Durante os ciclos controlados da API a trigger técnica permaneceu normal, mas isso também não comprova sua ativação no tempo esperado.

### Cookies e estado final desta coleta

Consultado código da imagem, não cookies de usuário: ZBX_SESSION_NAME=zbx_session, CCookieHelper define HttpOnly e Secure conforme HTTPS, domínio vazio e nenhum SameSite explícito no helper. Mesmo com nome CEncryptedCookieSession, não afirmar confidencialidade de transporte; HTTP continua sem TLS. Sessão autenticada não foi lida/decodificada pelo agente. A autora deve retestar logout/login com senha nova após recriação e informar apenas atributos, sem valores de cookies.

MO-08 continua **parcial**: persistência/configuração selecionada e novos ciclos aprovados para disponibilidade, mas login real e futuro coletor ainda pendentes. MO-02/03 também parciais por cookies/sessão e negativos controlados restantes. Serviços retomados, dados preservados, nenhuma implementação de IA/n8n ou commit/push automático.

Conferência final aproximadamente 14:27 (-03:00): scripts de disponibilidade/persistência aprovados em modo somente leitura, API com duas amostras recentes saudáveis e HTTP200; seis serviços ativos. `git diff --check`, sintaxe PowerShell e 74 links locais com destinos existentes aprovados. Varredura de 53 arquivos versionados/versionáveis sem correspondências aos segredos locais conhecidos e padrões selecionados de chave privada/JWT; `.local` fora da seleção. Âncoras e ausência universal de segredos não garantidas.

## 11. Sessão e cookies confirmados pela autora — 25/10/2026

Após a recriação do monitoramento, a autora informou os atributos de `zbx_session` observados nas ferramentas do navegador:

| Atributo | Observação manual |
| --- | --- |
| HttpOnly | Marcado |
| Secure | Desmarcado |
| SameSite | Sem texto |
| Path | `/` |
| Domain | `localhost` |

Em seguida respondeu **“consegui!”** à confirmação de sair pelo botão do Zabbix, verificar que o dashboard exige login e entrar novamente com a senha nova. Resultado registrado como teste manual relatado pela autora, não observação autenticada ou teste automatizado do agente.

Os atributos são compatíveis com M-D02 e a análise da imagem: HTTP local sem Secure não oferece confidencialidade TLS; SameSite vazio não comprova emissão explícita de Lax, mesmo que o navegador aplique um padrão. Domain exibido não comprova, sozinho, emissão de atributo Domain no Set-Cookie.

Durante a orientação, um valor de cookie foi compartilhado involuntariamente na conversa. Não foi decodificado, reutilizado em requisições ou copiado aos arquivos do projeto. Foi orientado logout pelo painel; sua execução posterior foi confirmada. Isso não é ensaio de replay nem prova técnica independente de invalidação do valor anterior. Não preservar o valor em evidências, comandos ou capturas.

A pendência manual de sessão/cookies e login após persistência está resolvida por relato. MO-08 permanece parcial pelo coletor ainda inexistente; MO-03 pelos negativos controlados HTTP500/redirect/nodata. Esta atualização documental não reexecuta bindings, containers, regressão ou demais critérios e não conclui a entrega 03.

## 12. Provisionamento restrito e primeiro runtime do coletor — 25/10/2026

### Aprovação e configuração efetiva

Ao solicitar avanço para fechar a entrega, a autora foi consultada sobre o conflito entre a lista padrão ampla de tipos e o recorte mínimo. Escolheu explicitamente **“Só LOGIN_ERROR”**. Preflight administrativo somente leitura confirmou armazenamento desabilitado, 102 tipos retornados (incluindo LOGIN_ERROR), retenção ausente, client técnico inexistente e ID interno do realm diferente do nome lógico. `bruteForceProtected=false` já existente permaneceu inalterado; não foi desabilitado para testes nem apresentado como proteção implementada.

Criados dois segredos exclusivos do coletor por Initialize-MonitoringSecurity.ps1, sem sobrescrever os anteriores. O wrapper inicial de execução acusou falha por verificar um `$LASTEXITCODE` antigo após script sem comando nativo; os arquivos tinham sido criados corretamente. Não repetimos o inicializador nem substituímos segredos. Preflight separado e aplicação posterior passaram.

Provisionamento real por Admin REST, em container administrativo efêmero, sem token/credencial administrativa no runtime:

- Client `secureops-event-reader` confidencial, service account habilitada; sem standard/implicit/password grant, redirects ou web origins; fullScopeAllowed=false e sem client scopes padrão/opcionais.
- Retiradas roles padrão **somente da service account recém-criada**; atribuída somente `realm-management/view-events`, com scope correspondente. Leitura de role-mappings confirmou ausência de realm roles e somente esse papel de client.
- Eventos habilitados, tipos exatamente `[LOGIN_ERROR]` e retenção 86400 s. Listener/configuração de eventos administrativos preservados. Configuração anterior guardada apenas na pasta local ignorada; nenhum histórico excluído.
- Snapshot selecionado antes/depois de gateway e metadados de usuários/grupos/credenciais, browserFlow/política OTP/SSL/brute force comparado em memória: igual. Não exportados segredos do gateway, senhas, sementes OTP ou respostas brutas. Isso não substitui regressão de navegador/MFA.
- Com token do client técnico: GET events/config e consulta filtrada de janela vazia permitidos. PUT **idêntico à configuração atual**, escolhido para não produzir mudança efetiva mesmo se inesperadamente permitido, recebeu **403**; leitura administrativa depois confirmou configuração igual. Não foi feito DELETE de eventos ou teste de mutação de credenciais.
- `view-events` permite leitura do realm inteiro, não ACL por client. Os filtros do coletor não reduzem esse privilégio no Keycloak.

### Coletor implementado e validado

`apps/identity-event-collector/` usa TypeScript simples executado com suporte nativo a tipos apagáveis do Node 24.22.1 e checagem --strict separada. Sem framework/biblioteca nova. Imagem local `secureops-event-collector:0.1.0`, derivada do runtime local já versionado da API; build com contexto restrito apenas a collector.ts/main.ts.

No Compose: profile `monitoring-security`, usuário node, rootfs read-only, cap_drop ALL/NoNewPrivs, limite 128 MiB, sem privileged/socket/portas e apenas monitoring+identity. Três arquivos read-only: segredo técnico, segredo de métricas e ID interno do realm, que não é o nome lógico. API permanece sem porta/mount e somente em service. Sem dependência que inicie Keycloak no modo disponibilidade.

Validações executadas:

| Origem | Resultado | Limite |
| --- | --- | --- |
| Testes nativos isolados do coletor | **39 aprovados**, zero falhas; última execução 681,983778 ms | Fixtures e transporte loopback, não cinco logins reais |
| Checagem TypeScript --strict | Aprovada, exit 0 | Não equivale a runtime integrado |
| Contrato de configuração/preprocessamento Zabbix | **10 aprovados**, zero falhas; 345,347517 ms | JavaScript em VM Node e payloads locais; não aceitação/execução pelo Zabbix |
| Infraestrutura existente | **42 checks aprovados** novamente | Ainda não inclui itens/triggers de segurança |
| Probe do coletor real | Sem/errado segredo: **401**; segredo válido: HTTP200, collection_ok=1 e login_errors_5m=0 | Janela vazia; não valida IDs/timestamps de eventos reais não vazios |
| Inspeção runtime do coletor | Restrições, memória, mounts, redes e ausência de portas conferidos | Não comprova isolamento absoluto ou egress bloqueado |
| Recriação do coletor para revisão final | Nova imagem iniciada; probe válido com janela vazia | Não comprova reconstrução de janela não vazia ou persistência integrada |

Testes cobrem 0/1/4/5/1000 eventos, fronteiras inclusivas, timestamps fora da janela, outro realm/client/tipo, ID ausente, realmId interno distinto do nome, duplicação consistente/inconsistente, teto 1001, streaming >2 MiB, JSON/schema/configuração/retencão inválidos, HTTP401/403/500, token expirado/renovação sem retries ilimitados, timeout real, uma consulta concorrente, negativas de endpoint e marcadores fictícios sensíveis fora da saída. Falha retorna qualidade 0 **sem contagem**, não zero. Configuração é conferida em cada coleta, antes dos eventos.

Payloads preparados em security-config.mjs usam contagem dependente que descarta amostras inválidas, qualidade separada e duas triggers Single. A expressão de autenticação não contém perda de frescor como recuperação; o problema técnico considera qualidade 0 ou nodata(90s). Isso é **implementação preparada**, não trigger aplicada ou verificada na versão real. Macro secreta e extensão do dashboard ainda não criadas.

### Bloqueio e estado deixado

Foi solicitado token temporário do painel salvo apenas em arquivo local pelo prompt oculto. Um token foi enviado involuntariamente na conversa; **não foi usado, reproduzido em comandos ou copiado aos arquivos**. Orientada revogação e criação de substituto, salvo somente por Save-MonitoringApiToken.ps1. Autora solicitou ajuda no terminal. Ao final desta coleta, arquivo local ainda ausente; revogação/substituição não confirmadas. Não contornar esse bloqueio com cookie divulgado, senha padrão, bypass da autorização ou edição SQL.

Sete serviços ativos após subida/recriação apenas do novo coletor. Nenhum comando desta etapa reiniciou API, Keycloak, gateway, banco, server ou frontend existentes. Nenhum volume removido, credencial de usuário alterada, evento excluído ou push/commit criado. Tráfego somente contra serviços/fixtures próprios do laboratório.

**Aceite atual:** MO-05 parcial (leitura/escrita negada/endpoint sanitizado comprovados, eventos não vazios e integração pendentes); MO-06/MO-07 pendentes de ensaios integrados; MO-08 parcial (falta janela/persistência integrada); MO-03 ainda parcial pelos negativos HTTP500/redirect/nodata; MO-09/MO-10 aguardam regressão final e participação manual. Não há alerta de segurança ativo no Zabbix por este trabalho, pois itens/triggers não foram aplicados. Entrega 03 permanece **em implementação**, com integração temporariamente bloqueada até acesso local seguro.

Conferência final às 21:43 (-03:00): disponibilidade em modo somente leitura aprovada, duas amostras saudáveis recentes e HTTP200; sete serviços ativos, API/banco/frontend healthy. Sintaxe dos scripts PowerShell, 76 destinos de links locais e `git diff --check` aprovados. Varredura limitada de 69 arquivos versionados/versionáveis e log do coletor sem correspondências aos segredos selecionados conhecidos; arquivos também sem padrões selecionados de chave privada/JWT. `.local` fora da seleção, arquivo de token ainda ausente. Não garante ausência universal de segredos nem valida âncoras ou invalidação do token divulgado.

## 13. Retomada do laboratório e validade do token — 26/10/2026, 06:58–07:03 -03:00

Autora confirmou **“arquivo salvo e anterior revogado”**. Arquivo local disponível; revogação do anterior é relato da autora, não teste de replay. Nenhum valor foi exibido ou copiado aos arquivos versionáveis.

Docker Desktop estava parado (pipe do engine inexistente). Executado `docker desktop start`; containers existentes do laboratório estavam parados. Retomados somente os sete serviços do projeto com `up -d --no-recreate --no-deps --pull never --wait`, preservando containers e volumes; nenhum outro projeto iniciado. Primeiro comando tentou `start --wait`, não suportado e rejeitado sem iniciar serviços; help consultado e operação corrigida. Gateway tentou iniciar antes da prontidão do Keycloak e saiu; após discovery/JWKS e negativa sem secret 401 aprovados, retomou normalmente. Isso é retomada de ambiente parado, não teste controlado de indisponibilidade ou comprovação de nodata(90s).

O preflight `Configure-MonitoringSecurity.ps1` é somente leitura e falhou no primeiro `host.get`: API retornou token expirado. Acrescentada classificação de mensagens fixas de autenticação em zabbix-api.mjs, sem imprimir detalhes arbitrários de erro que possam conter parâmetros sensíveis. Nova execução confirmou `zabbix_auth_token_expired`. Não executado `-Apply`; macro, itens, triggers e widgets de segurança continuam sem aplicação.

Orientada edição da expiração do **token novo** pela UI, sem gerar outro valor, mantendo anterior revogado. Autora solicitou ajuda; validade ainda não ajustada/confirmada nesta coleta. Não modificamos arquivo local, senha, SQL ou política de autorização para contornar expiração.

Verificações às 07:03: coletor real com coleção válida/janela vazia e acesso sem/errado segredo 401; API com duas amostras saudáveis recentes e código 200; 42 checks de infraestrutura aprovados novamente; `git diff --check` aprovado. Sete serviços retomados, dados preservados. Entrega continua em implementação; integração bloqueada pela validade do token, não pela ausência do arquivo. Nenhum commit/push.

## 14. Integração e negativos no Zabbix real — 26/10/2026

Autora confirmou atualização da expiração. Preflight da API aprovado, com zero itens de segurança anteriores. Aplicação pelo endpoint oficial criou macro secreta exclusiva (sem exportar valor), master HTTP agent + dois dependentes e duas triggers Single; primeira amostra válida, triggers normais e dashboard privado ampliado de dois para quatro widgets, preservando os anteriores. Payloads de security-config.mjs foram aceitos pelo Zabbix 7.0.32 e executaram de verdade.

Modos availability/full exercitados por Set-MonitoringSecurityMode.ps1: três itens e duas triggers desabilitados/habilitados, cenário api-health inalterado, nenhum histórico excluído. Retorno ao modo full exigiu duas amostras novas de qualidade válida. O script recusa ocultar problema ativo ao desabilitar. Profile do Compose não altera esses estados no banco.

### Alvo fictício temporário

Test-MonitoringNegatives.ps1 criou somente container e host lógico exclusivos por GUID. Alvo sem porta, volume ou segredo real, apenas em service interna; controlador efêmero acessou service+monitoring para usar a API Zabbix. Nenhuma alteração no host/cenário principal ou na API. Primeiro ensaio falhou por usar `attempts` na API: a classe CHttpTest da imagem confirmou **retries** para API/SQL, enquanto o export usa **attempts**. Corrigido, sem relaxar validações; host e container próprios da tentativa foram removidos.

Reexecução aprovada:

- Cenários com 20s/5s/uma tentativa/somente 200/sem redirects observaram HTTP500 e HTTP302; ambos web.test.fail=1, nunca saudáveis.
- Inicialização com falha: qualidade 0/problema técnico; contagem sem amostra (lastclock=0), não contagem zero fabricada.
- Agregado fictício 5 abriu problema **50**. Falhas categóricas de credencial, eventos desabilitados, limite e permissão conservaram contagem histórica 5 e o mesmo problema, sem recuperação.
- HTTP403/500, JSON inválido e amostra obsoleta tornaram o master unsupported; não escreveram zero nem recuperaram autenticação.
- Após última qualidade válida clock **1793010097**, perda de resultados abriu problema técnico em **1793010214**: **117s**, com autenticação ainda aberta.
- Somente nova amostra completa fictícia com zero recuperou autenticação, evento **104**. Fixture comprova pipeline/triggers reais, não cinco logins ou recuperação natural do Keycloak.
- Host de teste e container removidos no finally, apenas recursos próprios. Não removidos volumes/histórico do laboratório.

### Ausência de amostras do cenário principal — ensaio controlado

Test-MonitoringNoData.ps1 identificou exatamente um processo `http poller` do Zabbix server, pelo PID interno, e o pausou com STOP como o mesmo usuário não root. Não pausou o server/avaliador nem o HTTP agent poller de segurança. CONT em finally e watchdog independente de 180s; sem capabilities extras ou mudança da API. API probe permaneceu aprovado durante a pausa.

- Última amostra saudável: **1793010242**, sem nova amostra enquanto pausado.
- Problema nodata **107**, clock **1793010360**: **118s** desde a última amostra, compatível com janela de 90s + avaliação periódica, sem alegar disparo exato em 90s.
- Trigger de falha HTTP permaneceu normal; ausência de coleta não foi confundida com queda da API.
- CONT retomou coleta; amostra saudável **1793010366**, recuperação **108**. Este ensaio controlado substitui a pendência de timing, não reinterpreta a lacuna histórica não controlada da seção 10.

## 15. Dois ciclos reais de autenticação e falhas da coleta — 26/10/2026

### Origem e separação dos resultados

Autora confirmou operadora com senha+TOTP permitida e visitante com senha+TOTP negada 403 após retomada. Na inspeção subsequente havia dois LOGIN_ERROR na janela; não foi determinada a causa nem atribuída a sucesso/403. Eles expiraram naturalmente antes de iniciar o ensaio controlado. Ainda é necessário comparar um intervalo limpo durante novos logins bem-sucedidos para comprovar ausência de incremento; relato de resultado final de login não informa todas as submissões anteriores.

Observador separado leu eventos com client técnico, validou IDs/realmId interno/client/tipo/tempo e expôs somente contagens, horários e categorias de erro permitidas, nunca payload bruto/IDs de usuário/IP. Consulta max=1 retornou um evento em janela não vazia, enquanto max=1001 retornou cinco. Não foram gerados 1001 eventos reais: teto/bytes/fronteiras são testes de fixture. Fonte 26.8.1 reconferida: JpaEventQuery armazena maxResults recebido e PaginationUtils passa max não negativo diretamente a setMaxResults, sem teto intermediário de 1000; filtros de tempo são inclusivos. Essa é análise estática combinada com observação da janela real, não teste de carga.

### Resultados dos ciclos

| Medição | Ciclo 1 | Ciclo 2 |
| --- | --- | --- |
| Erro isolado | 1 evento, sem alerta | 1 evento, sem alerta |
| Primeiro evento, epoch ms | 1793010464867 | 1793011026255 |
| Quinto evento, epoch ms | 1793010501289 | 1793011077036 |
| Problema / clock (s) | 109 / 1793010502 | 113 / 1793011102 |
| Detecção em relação ao quinto evento | 711ms | 24964ms |
| Repetição | 3 amostras ≥5, 1 problema | 3 amostras ≥5, 1 problema |
| Janela cai abaixo de 5, epoch ms inclusivo | 1793010764868 | 1793011326256 |
| Recuperação / clock (s) | 112 / 1793010772 | 124 / 1793011372 |
| Recuperação após janela <5 | 7132ms | 45744ms |

Tempos calculados com eventos Zabbix em segundos e Keycloak em ms; resolução não é precisão subsegundo. Todas as metas de 60s observadas. Nenhum evento excluído nem recuperação manual. No ciclo 1 a autora relatou uma tentativa errada + quatro adicionais; no ciclo 2 relatou divergência na quantidade adicional, sem especificá-la. A fonte registrou cinco eventos `invalid_user_credentials`; portanto **não afirmar cinco submissões exatas no segundo ciclo**, apenas cinco eventos reais, origem/scope validados. Sem conclusão de ataque confirmado.

### Fonte indisponível com autenticação aberta

Test-MonitoringSourceFailure.ps1 -Component keycloak -RunFailure parou somente Keycloak e retomou o mesmo container/volume:

- Parada confirmada **1793010583**; problema técnico **110**, clock **1793010592**: **9s**.
- Agregado ficou 5, problema 109 continuou aberto, nenhum zero. API com amostra saudável recente; novo caminho ao provedor indisponível, sem alegar revogação imediata de sessões gateway existentes.
- Retomada/discovery pronta **1793010612**; nova qualidade válida **1793010623**, recuperação técnica **111**; autenticação permaneceu aberta com cinco eventos válidos.
- Discovery/JWKS/negativa sem secret 401 aprovados; IDs/start times dos outros seis serviços preservados.

### Reconstrução e parada do coletor

Com problema 113 aberto e cinco eventos na fonte, Test-MonitoringCollectorPersistence.ps1 reiniciou e recriou somente o coletor. Cada fase exigiu **nova** amostra Zabbix, com fonte=5, agregado=5 e qualidade=1; problema de autenticação permaneceu aberto. Restart preservou ID/alterou start time; recreate alterou ID. Arquivos de segredo/configuração comparados por hash em memória, sem exibir hashes/valores; demais seis serviços intocados, nenhum volume do coletor. Isso comprova reconstrução da janela não vazia a partir do Keycloak, não zero de inicialização ou soma duplicada.

Depois, parada apenas do coletor:

- Última qualidade válida **1793011252**; parada confirmada **1793011266**.
- Problema técnico **119** em **1793011352**: **86s** após parada, **100s** após última qualidade; autenticação 113 ainda aberta, contagem histórica 5, API saudável.
- Retomada confirmada **1793011355**; consulta completa válida **1793011372**, qualidade=1, contagem=4. Recuperações legítimas **124** (autenticação) e **126** (técnica); a janela já havia caído abaixo de cinco durante a pausa. Não houve recuperação enquanto sem coleta.
- Outros seis serviços preservados. Janela depois esvaziou sem excluir eventos, e o observador confirmou fonte/Zabbix zero com qualidade válida.

### Privilégios negativos complementares

Provision-MonitoringEventReader.ps1 -VerifyPermissions fez PUTs com valores **iguais aos atuais**, escolhidos para não alterar estado efetivo mesmo se inesperadamente autorizados: configuração de eventos, realm enabled=true e operadora enabled=true. Os três receberam **403** usando token técnico. Snapshot selecionado de identidade/configuração antes/depois igual. Nenhum DELETE ou mutação de senha/OTP/grupo; bootstrap usado apenas na administração efêmera, nunca no coletor.

Nesse checkpoint a persistência integrada e confirmação final ainda eram pendentes; os resultados efetivos constam na seção 16 abaixo.

## 16. Persistência integrada, regressão e matriz final — 26/10/2026

### Reinício/recriação completos do monitoramento

Test-MonitoringPersistence.ps1 -RunRestartAndRecreate -IncludeCollector aprovado nas duas fases: banco/server/frontend/coletor com mesmos IDs e novos start times no restart, novos IDs no recreate; mesmo volume PostgreSQL e snapshot público selecionado iguais. Snapshot incluiu cenário/triggers, três itens de segurança, quatro widgets/filtros/referências de item, retenção, metadados de contas/grupos, quatro eventos anteriores e duas amostras históricas de disponibilidade, mais quatro eventos/duas amostras históricas de autenticação. Sem senha/hash de senha/macro secreta ou sessão no snapshot.

Cada fase exigiu duas amostras de disponibilidade saudáveis e duas qualidades novas válidas; API, Keycloak e gateway não reiniciados durante esse ensaio. Reconstrução de janela não vazia do coletor foi provada separadamente na seção 15. Named volume não foi apagado, nenhum dado restaurado por cima e nenhum backup/HA presumido.

### API após recriação

Test-MonitoringAvailability.ps1 -RunFailureCycles repetido com os **outros seis serviços preservados**, incluindo coletor:

| Medição | Ciclo 1 | Ciclo 2 |
| --- | --- | --- |
| Stop iniciado (-03:00) | 07:47:13.695 | 07:48:27.726 |
| Parada confirmada (epoch s) | 1793011635 | 1793011709 |
| Problema / clock | 137 / 1793011642 | 139 / 1793011722 |
| Detecção após parada | 7s | 13s |
| Healthy confirmado (epoch s) | 1793011694 | 1793011774 |
| Recuperação / clock | 138 / 1793011702 | 140 / 1793011782 |
| Recuperação após healthy | 8s | 8s |
| Amostras falhas / problemas / duração observada | 3 / 1 / 60s | 3 / 1 / 60s |

Probe aprovado nas duas retomadas; nenhuma parada/recriação dos outros seis serviços, recuperação manual ou exclusão de histórico. API voltou healthy.

### Conferência real e navegador

Test-MonitoringFinal.ps1 aprovado antes da revogação: Zabbix 7.0.32, três itens habilitados/suportados/recentes, contagem 0 e qualidade 1; header referencia apenas macro e macro é secret/type=1; preprocessamento real igual ao código versionável; duas triggers de segurança Single, sem manual close, habilitadas e normais; dashboard privado, sem shares, quatro widgets e referências de itens corretas; eventos **109/112/113/124** preservados.

Autora confirmou **“Todos os três checks OK”** ao procedimento final: sair do Zabbix, dashboard exigir login, entrar com senha exclusiva e visualizar quatro widgets; operadora em janela anônima nova com senha+TOTP permitida; visitante em nova janela anônima com senha+TOTP negada 403, sem novas tentativas erradas. Não houve inspeção de sessão autenticada pelo agente, recadastro OTP ou alteração de grupos.

Comparação independente do intervalo **1793011865116–1793012125443 ms**: **zero LOGIN_ERROR** do client da aplicação. O observador consultou desde o início registrado, não apenas desde uma última amostra favorável. Isso resolve a ambiguidade dos dois eventos prévios da seção 15, sem atribuí-los retroativamente a sucesso/403.

### Regressão final executada depois da persistência

| Suite/verificação | Resultado |
| --- | --- |
| API | 35 aprovados, 6220,085614 ms |
| Identidade estática | 10 aprovados, 251,337916 ms |
| Proxy OIDC real isolado | 12 verificações aprovadas, rede interna temporária, gateway principal inalterado |
| Coletor | 39 aprovados, 986,961482 ms |
| TypeScript strict do coletor | Exit 0 |
| Contrato/preprocessamento/cliente API sanitizado | 14 aprovados, 279,705473 ms |
| Contrato do import de disponibilidade | 8 aprovados, 196,060915 ms |
| Schema/gramática originais PHP-FPM | 7 verificações aprovadas |
| Infraestrutura | 42 checks aprovados novamente |
| Coletor runtime | Restrições verificadas, negativas 401 e coleta autenticada válida/zero |
| Discovery/JWKS/token sem secret e probe API | Aprovados |
| Persistência em modo somente leitura | Baseline integrado aprovado |

Sem confundir soma de checks heterogêneos com quantidade única de testes funcionais. Fixtures não são login real e os relatos manuais são identificados separadamente.

### Revogação do acesso temporário e recursos

Autora confirmou revogação do token administrativo temporário e manutenção da revogação do anteriormente divulgado. Test-MonitoringTokenRevoked.ps1 confirmou **negação real** ao tentar somente leitura com o arquivo local antes aceito; não aceitou mera expiração como prova de revogação. Nenhuma operação administrativa adicional feita com esse token. Arquivo ignorado preservado, sem apagar/rotacionar segredos existentes.

Depois da revogação, coletor continuou com qualidade=1/contagem=0, pois usa exclusivamente sua service account/segredos próprios. Sete serviços ativos às 08:03 (-03:00); API/banco/frontend healthy. Snapshot de memória: API 21,04 MiB, Keycloak 619,6 MiB, gateway 7,688 MiB, banco 105 MiB, server 52,74 MiB, frontend 42,76 MiB e coletor 49,75/128 MiB. Não são pico, dimensionamento mínimo ou teste de carga. Nenhum container secureops-negative/secureops-import ou rede secureops-import remanescente na consulta. Sem commit/push automático.

### Matriz final de aceite — substitui estados históricos acima

| ID | Resultado | Evidência e limite |
| --- | --- | --- |
| MO-01 | Aprovado | Decisões aprovadas, imagens/patches/digests/limites/usuários/volume conferidos; API/expressões reais e fonte JPA 26.8.1 validadas com distinção de análise estática |
| MO-02 | Aprovado | 42 checks + restrições reais do coletor, bindings loopback, ausência de porta API/banco/server/coletor, guest desabilitado; senha/sessão/cookies e logout/relogin relatados pela autora; HTTP local sem confidencialidade |
| MO-03 | Aprovado | Saúde/probe, HTTP500/302 não saudáveis em alvo fictício, nodata principal em 118s e recuperação real após CONT |
| MO-04 | Aprovado | Ciclos iniciais e finais 137→138/139→140, limites locais atendidos, uma condição/um problema e outros serviços preservados |
| MO-05 | Aprovado | Leitura técnica real, três PUTs sem mudança efetiva negados 403, IDs/escopo/tempo reais, 401 nas métricas sem segredo e saída agregada; saturação/bytes em fixture, não teste de carga |
| MO-06 | Aprovado | Dois erros isolados sem alerta, cinco eventos nos dois ciclos 109→112/113→124, três amostras/um problema, recuperações por janela válida; quantidade exata de submissões do ciclo 2 não comprovada |
| MO-07 | Aprovado | Falhas reais da fonte/coletor com alerta aberto, 9s/86s, nenhum zero/recuperação indevida; credencial/config/schema/limites e início sem amostra em fixtures/pipeline real |
| MO-08 | Aprovado | Restart/recreate dos quatro componentes, mesmo volume/snapshot selecionado/eventos/histórico, novas amostras e novos ciclos; janela=5 reconstruída; login final relatado; política de retenção, não expurgo/backup comprovados |
| MO-09 | Aprovado | Snapshot selecionado da identidade preservado, MFA/operadora/403 manual e intervalo de sucesso sem LOGIN_ERROR; API saudável com Keycloak parado; sem nova cronometragem manual de sessão da entrega 02 |
| MO-10 | Aprovado | Regressão completa, runbook exercitado, origens distinguidas e documentação/links/sanitização revisados conforme seção 17; sem alegar instalação limpa em outra máquina |

Retenções e limites são parte do aceite, não funcionalidades futuras pendentes: eventos Keycloak 24h e histórico/eventos de trigger Zabbix 7d configurados; expurgo após esses períodos não observado. Sem garantia de eventos durante indisponibilidade do próprio Keycloak, observação contínua durante parada do server, isolamento absoluto do host, ataque confirmado ou deduplicação n8n. Entrega 04 não iniciada.

## 17. Revisão e sanitização do fechamento — 26/10/2026, a partir de 08:15 -03:00

- Na primeira conferência, às 08:15, sintaxe PowerShell aprovada e 17 módulos JavaScript passaram em node --check. TypeScript strict e suites funcionais aprovados na seção 16.
- 75 links Markdown locais com destinos existentes; âncoras e disponibilidade de URLs externas não validadas nessa revisão. `git diff --check` aprovado; avisos LF/CRLF não foram erros de whitespace.
- 86 arquivos versionados/versionáveis, incluindo novos arquivos ainda sem commit, sem correspondências aos segredos locais selecionados conhecidos (incluindo token revogado e representações selecionadas do cookie-secret), chaves privadas/JWT nos padrões selecionados. `.local` fora da seleção Git.
- Logs dos sete serviços consultados em memória, até 10000 linhas por serviço: 858 linhas capturadas, nenhuma correspondência aos mesmos segredos/padrões selecionados. Não exportados logs brutos, valores de cookie/token, capturas de credenciais, realm ou banco. Isso é varredura limitada, **não garantia universal** de ausência de segredos/dados sensíveis.
- README, arquitetura, roadmap, SPEC/PLAN, runbook e texto da topologia alinhados ao estado real. Sete serviços ativos, API saudável, qualidade válida e contagem limpa após os ensaios. Alterações mantidas sem commit/push automático.

Na revisão final foi identificado que o controle do alvo fictício temporário ainda não exigia chave. Protegidos controle **e** métricas com chave aleatória exclusiva por execução, sem reutilizar segredo do lab; arquivo ignorado/read-only montado e apagado apenas pelo cleanup da invocação que o criou. Nenhum endpoint da API real foi criado/alterado. Adicionados **dois testes isolados** de autenticação e HTTP, aprovados junto dos 14 de contrato/API: 16 no conjunto, 319,402535 ms; 39 testes do coletor e TypeScript reexecutados, aprovados (39 em 648,082870 ms).

Em aproximadamente 08:22, Test-MonitoringNegatives.ps1 -VerifyTargetOnly exerceu criação da chave/ACL, alvo e verificador em containers, controle/métricas sem chave 401, controle válido 204, agregado fictício 5 e códigos 500/302; chave não refletida. Container/chave próprios removidos. Não acessou API Zabbix nem reativou token administrativo. Pipeline Zabbix da seção 14 foi testado antes desse reforço do harness; não alegar uma nova execução integrada depois da revogação. Contrato de amostras e serviços reais não mudaram.

Conferência final repetida às **08:25 (-03:00)** após esse reforço: sintaxe PowerShell e **19 módulos JS**, **76 destinos de links locais**, **88 arquivos versionados/versionáveis** e **932 linhas de logs dos sete serviços** aprovados nas mesmas verificações limitadas, sem correspondências selecionadas de segredos. `.local` fora do Git, nenhum container/chave efêmeros do alvo remanescentes e whitespace aprovado. API com duas amostras recentes saudáveis/HTTP200; coletor com qualidade válida, contagem zero e negativas 401. Nenhum token administrativo reativado, commit ou push.

**Conclusão:** entrega 03 concluída no escopo aprovado, com evidências de execução e participação manual identificadas. Próximo trabalho é especificar/revisar a entrega 04; não há automação de incidentes implementada por esta conclusão.
