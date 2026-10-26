# PLAN 03 — Monitoramento com Zabbix

**Estado:** concluída em 26/10/2026, após implementação iniciada em 25/10. MO-01–MO-10 verificados: disponibilidade, segurança, falhas, persistência, regressão e confirmação manual, com documentação/sanitização revisadas. Sem IA ou n8n. Fonte do comportamento/aceite: [SPEC](SPEC.md); resultados e limites nas [evidências](../../evidence/03-monitoring.md).

## 1. Gates e estado inicial

- Fundação e identidade concluídas. API sem publicação/mounts e somente em `service` interna. Keycloak 26.8.1/gateway existentes devem ser preservados, incluindo credenciais, TOTP, grupos, sessões e volume.
- Working tree estava limpa no início da revisão, após commit `5cacda4`. Rascunho Kuma substituído documentalmente, não migrado em runtime: nenhum Kuma foi instalado.
- A solicitação inicial autorizou somente revisão documental. Depois de apresentar M-D01–M-D06 e seus riscos, a autora respondeu “aprovado!”, autorizando implementação gradual. Preservar os limites e registrar cada validação; configuração manual e testes interativos ainda dependem da autora.
- Aprovar novas exceções locais e privilégios antes de aplicar. Não herdar automaticamente D01–D04 da identidade como autorização para frontend, banco ou coletor.
- Trabalhar uma tarefa por vez, registrar resultado e impedimentos; não criar n8n, IA, SMTP, webhook ou banco adicional de incidentes.

## 2. Artefatos da entrega

```text
compose.monitoring.yaml                  # server/frontend/banco; coletor no profile monitoring-security
apps/identity-event-collector/            # TypeScript simples; runtime e integracao Zabbix validados
infra/monitoring/10-create-zabbix-db.sh    # implementado: bootstrap sem superusuario permanente
infra/monitoring/availability-host.json  # importado: host/cenario/triggers de disponibilidade
scripts/Test-MonitoringAvailabilityConfig.ps1 # 8 checks de contrato + 7 schema/gramatica isolados
scripts/Test-MonitoringAvailability.ps1   # leitura real; -RunFailureCycles executa dois ciclos so da API
scripts/Test-MonitoringPersistence.ps1    # leitura real; flag explicita reinicia/recria apenas monitoramento
scripts/Initialize-Monitoring.ps1        # implementado: segredos novos, recusa sobrescrita
scripts/Test-MonitoringInfrastructure.ps1 # implementado: configuracao e inspecao real
infra/monitoring/security-config.mjs      # payloads API, macro referenciada, sem valor secreto
scripts/Configure-MonitoringSecurity.ps1  # API oficial; leitura por padrao, aplica so com -Apply
scripts/Set-MonitoringSecurityMode.ps1    # availability/full, preservando historico
scripts/Test-MonitoringCollector.ps1      # 39 testes + TypeScript + 14 contratos/API + 2 alvo ficticio
scripts/Test-MonitoringNegatives.ps1      # alvo/host ficticios exclusivos, cleanup proprio
scripts/Test-MonitoringNoData.ps1         # pausa limitada do web poller, CONT/finally/watchdog
scripts/Observe-MonitoringSecurity.ps1   # agregado/horarios reais, sem payload de identidade
scripts/Test-MonitoringSourceFailure.ps1 # falha real isolada de fonte ou coletor
scripts/Test-MonitoringCollectorPersistence.ps1 # janela real nao vazia reconstruida
scripts/Test-MonitoringFinal.ps1          # selecao publica de itens/triggers/dashboard/eventos
scripts/Test-MonitoringTokenRevoked.ps1  # negativa do token temporario, sem alterar usuarios
.local/monitoring/                       # criado, ignorado, jamais versionado
docs/runbooks/monitoring.md              # instalacao, retomada, testes e limites
docs/evidence/03-monitoring.md            # resultados reais e matriz final
```

Escolher nomes definitivos na implementação. Preferir Node simples e testes nativos, reaproveitando imagem local, sem framework novo. Export de configuração não inclui credenciais nem substitui procedimentos/evidências. Não exportar banco, realm ou histórico bruto de autenticação.

## 3. Tarefas e validação

### T01 — Aprovar desenho e confirmar viabilidade

- [x] M-D01–M-D06 aprovadas explicitamente após apresentação dos riscos e limites.
- [x] Participacao manual confirmada: painel/sessao, aprovacoes de provisionamento, dois ciclos de falha e regressao com senha+TOTP existentes. Segredos compartilhados involuntariamente nao copiados ao repositorio; logout/revogacao registrados separadamente.
- [x] Engine 28.5.1/Compose 2.40.2, Linux amd64, 12 CPUs/7,61 GiB; nenhum listener 8081 encontrado; API/Keycloak/gateway preservados. Tetos iniciais: banco/server 512 MiB cada e frontend 384 MiB, espera 180 s; medir na subida.
- [x] Tres imagens fixadas baixadas; entrypoints, bibliotecas pgsql/php/config e usuarios conferidos na propria imagem. Frontend contem curl/ping, banco pg_isready; server nao traz health check. Variaveis _FILE suportadas, DBPassword mascarado com DEBUG_MODE=false; caminhos de dados confirmados.
- [x] PostgreSQL inicializado como UID/GID 999; Zabbix como 1997:1995, sem capacidades e NoNewPrivs. Role zabbix criada sem superuser/createdb/createrole/replication; bootstrap exclusivo do banco. Validacao runtime na evidencia, nao apenas desenho.
- [x] Inspecao inicial administrativa separada: eventos desabilitados, LOGIN_ERROR na lista padrao, listener jboss-logging, admin events off, sslRequired=external e bruteForceProtected=false preexistente. Fonte habilitada depois em T05, com aprovacao especifica; credenciais/MFA/grupos preservados, sem alegar protecao brute force implementada.
- [x] Filtros/ID/time/max conferidos no codigo 26.8.1 e em duas janelas reais nao vazias; max=1 contrastado com max=1001 em janela de cinco eventos. JpaEventQuery/PaginationUtils passam limite informado diretamente a JPA. Teto 1001/bytes/fronteiras em fixture; nao alegar teste de carga com 1001 eventos reais.
- [x] Expressoes/contrato fechados e executados pelo Zabbix 7.0.32: ausencia de dados e falhas nao zeram contagem nem recuperam autenticacao sem consulta completa.

**Gate executado por etapas:** infraestrutura aprovada antes da subida; permissao/contrato antes dos ensaios de seguranca. Expressoes, imagens, recursos e fonte conferidos conforme evidencias. Administracao efemera separada; nenhum bootstrap no coletor, leitura direta de banco Keycloak, plugin ou socket.

### T02 — Alinhar documentação e compor infraestrutura mínima

- [x] README/arquitetura/roadmap/topologia alinhados ao estado implementado; entregas 01/02 preservadas e n8n fora da entrega.
- [x] Overlay com server/frontend/PostgreSQL e redes aprovadas executado; somente painel novo em 127.0.0.1:8081. Coletor acrescentado em T06 sem portas.
- [x] Redes estaticas/runtime verificadas; API identica a base. Fronteiras do coletor conferidas em teste proprio, sem acesso a service.
- [x] Volume nomeado e role dedicada funcionando; dois segredos exclusivos em pasta com ACL restrita. Reexecucao do inicializador recusada com hashes preservados; mounts de segredo read-only e pasta fora do build/Git.
- [x] Coletor em profile monitoring-security, com redes monitoring+identity, sem dependencia que inicie Keycloak; configuracao resolvida e runtime conferidos, API intacta.
- [x] Modos availability/full testados com tres itens e duas triggers, preservando historico e cenario API; retorno exigiu duas novas amostras validas. Token temporario teve validade corrigida pela autora e foi revogado no fechamento, com negativa real confirmada.
- [x] Base, base+monitoramento e composicao completa resolvidas sem imprimir secrets; somente tres componentes novos iniciados com --no-deps/--pull never e espera 180 s. Containers/start times dos tres servicos existentes preservados.
- [x] 23 verificacoes estaticas e 42 no modo -Runtime aprovadas; negativos de senha TCP e IPv6 loopback, API/provedor preservados. Snapshots: banco 163,3 MiB, server 49,87 MiB, frontend 24,03 MiB; nao representam pico ou dimensionamento.

**Validação:** parte de MO-02. Se rede interna suprimir publicação, revisar desenho, nunca publicar em `0.0.0.0` como contorno.

### T03 — Proteger frontend e configurar disponibilidade

- [x] Autora confirmou troca da senha inicial. Guest no grupo Disabled, confirmado read-only; senha do painel não recebida. Um valor de cookie foi compartilhado involuntariamente na conversa; não foi decodificado nem copiado ao repositório. Logout posterior confirmado pela autora; não houve ensaio de replay.
- [x] Autora confirmou logout pelo painel, dashboard exigindo login e novo login com senha nova após recriação. Evidência manual relatada, não teste de navegador executado pelo agente.
- [x] Autora observou zbx_session: HttpOnly marcado, Secure desmarcado, SameSite vazio, Path=/ e Domain=localhost. Compatível com HTTP local aprovado; não equivale a SameSite=Lax explícito nem transporte cifrado.
- [x] Autora confirmou importacao; inspecao real validou host/cenario/etapa, intervalos/codigo/redirects e duas triggers habilitadas, Single, sem fechamento manual, com last e nodata(90s) vinculados ao item web.test.fail real. Testes offline anteriores continuam distintos dessa evidencia de runtime.
- [x] Autora aplicou housekeeping; leitura real em 25/10, 12:20 -03:00 confirmou eventos de trigger 7d, history override 7d e housekeeping habilitado em ambas categorias. Sem limpeza forcada; expurgo ainda nao observado. Host padrao Zabbix server desabilitado, secureops-api mantido habilitado.
- [x] Dashboard inicial privado web/problems conferido; depois ampliado para quatro widgets com contagem/qualidade reais, preservando filtros/shares. Autora confirmou quatro widgets apos recriacao; tags service/category conferidas.
- [x] Duas amostras saudaveis recentes observadas por SELECT; web.test.fail=0 e response code=200, com 20 s entre amostras. Probe aprovado apos as duas retomadas; nao atribuir ao cenario validacao do JSON exato.
- [x] Alvo temporario respondeu 500/302: cenario falhou, sem seguir redirect. Host/container exclusivos removidos. Ausencia real de amostras do principal por pausa limitada do http poller: nodata em 118s, HTTP failure normal, API probe saudavel; CONT/finally/watchdog e recuperacao observados.

**Validação:** MO-02/MO-03. Configuração exportada e dashboard visual não bastam para comprovar detecção.

### T04 — Executar ciclos reais da API

- [x] Dois ciclos executados em 25/10, 12:04–12:06 -03:00: somente API parada; DOWN registrado antes da confirmacao da parada no primeiro e 12 s depois da confirmacao no segundo, ambos dentro da meta. Referencias exatas e limites de resolucao nas evidencias.
- [x] Tres amostras falhas por ciclo (deteccao + duas adicionais), um problema ativo/um evento de problema por ciclo; trigger de ausencia de dados permaneceu normal. IDs/start times de Keycloak/gateway/banco/server/frontend preservados.
- [x] API retomada com up --no-deps/--pull never/--wait, probe aprovado; recuperacoes 8 s e 7 s apos confirmacao healthy, dentro da meta.
- [x] Eventos 31→32 e 33→34, duracao observada de 60 s cada; sem exclusao de historico, sem recriar API e sem remover volumes/segredos. Script inclui finally para retomar somente API em caso de falha do ensaio.

**Validação:** MO-04. Nunca usar `down`, endpoint de falha ou publicação temporária da API para o teste.

### T05 — Provisionar leitura de eventos sem mudar identidade dos usuários

- [x] Autora aprovou explicitamente somente LOGIN_ERROR por 24h em vez dos 102 tipos padrao retornados com armazenamento desabilitado. Configuracao anterior guardada apenas localmente, listener/admin events preservados; nenhuma exclusao de historico.
- [x] Client secureops-event-reader criado confidencial, sem fluxo interativo/password grant/redirects, fullScopeAllowed=false e apenas view-events em roles/scope. Defaults removidos somente da NOVA service account.
- [x] Snapshot selecionado preservou gateway/metadados de usuarios/credenciais/grupos e politicas de realm/MFA; regressao manual final confirmou credenciais/TOTP existentes. Sem reset ou reinicializacao de volume.
- [x] Leitura real de config/eventos permitida; PUTs com valores atuais de eventos/realm/operadora negados 403 e estado selecionado igual antes/depois. Sem DELETE de eventos ou mutacao de credenciais.
- [x] Privilegio view-events e do realm inteiro, nao ACL por client. Filtro implementado no coletor, limite documentado.
- [x] Dois segredos exclusivos em arquivos ignorados/restritos. Provisionamento administrativo efemero por script, sem credencial admin no runtime. Runbook com comandos e recusa de sobrescrita.

**Validação:** parte de MO-05/MO-09. Se `view-events` não bastar, investigar a causa antes de pedir privilégio adicional.

### T06 — Implementar e testar o coletor mínimo

- [x] GET interno autenticado implementado; destino/realm/client/janela fixos, sem portas. Segredo invalido negado antes de consulta, confirmado em fixture; runtime sem/errado segredo 401.
- [x] Token somente em memoria com expiracao/renovacao limitada; config validada antes de contar, erro nao vira zero. Sucesso real para config e janela vazia.
- [x] Validacao local de janela/ID/escopo, max=1001 (aceita <=1000), 2 MiB em streaming, prazo total 10s e uma coleta concorrente; casos limites aprovados em testes isolados.
- [x] Dois ciclos reais com IDs/tempo/realmId interno/client/tipo validados e max=1 contrastado com janela completa de cinco. Limite JPA conferido no codigo; saturacao/2 MiB demonstradas em fixture, nao em carga real.
- [x] Saida apenas agregada; falha omite contagem. Sem persistencia de eventos/token ou dump HTTP no runtime; tres arquivos read-only de configuracao/segredos.
- [x] Testes nativos de token/renovacao, erros HTTP/transporte/schema, timeout real loopback, configuracao/retencao, janela/limites, duplicacoes e polling aprovados. TypeScript --strict aprovado.
- [x] Negativas de endpoint/parametros/metodo antes da consulta aprovadas em fixture; runtime autenticado validou contrato e frescor.
- [x] Marcadores ficticios nao aparecem na saida; runtime nao registra requisicoes/corpos. Revisao/varredura final registradas em T09/evidencias com limites, sem garantia universal.

**Validação:** MO-05 e parte de MO-07. Fixture demonstra contrato/casos extremos, não login real nem privilégio efetivo no realm.

### T07 — Integrar itens e testar cenário real de segurança

- [x] Master HTTP agent 30s/15s, macro secreta, dependentes e triggers Single aplicados pela API oficial. Preprocessamento descarta contagem invalida; configuracao real conferida.
- [x] Fixture integrada, antes dos ciclos manuais, comprovou ausencia de amostra inicial (lastclock=0), qualidade tecnica e preservacao do alerta aberto sob perda de frescor/schema/HTTP/fonte.
- [x] Janela limpa confirmada; erro isolado de cada ciclo gerou um evento, sem alerta; horarios/fonte comparados sem exclusao de eventos.
- [x] Cinco eventos reais abriram 109 e 113 em 0,711s/24,964s de referencia. Ciclo 2 com divergencia de quantidade relatada: nao afirmar cinco submissões exatas, somente cinco eventos observados.
- [x] Tres amostras >=5/um problema por ciclo; recuperacoes 112 e 124 somente com consulta valida <5, 7,132s/45,744s apos fronteira da janela. Eventos preservados.
- [x] Segundo ciclo abriu novo problema apos recuperacao; sucesso nao redefine janela. Novo intervalo limpo de logins corretos comparado separadamente.
- [x] Confirmacao manual final de operadora+TOTP permitida e visitante+TOTP 403. Intervalo epoch ms 1793011865116–1793012125443 sem LOGIN_ERROR; filtro de outro client/tipo/fronteiras tambem testado em fixture.

**Validação:** MO-06/MO-09. Regra é agregado de eventos do client, não reputação de IP/usuário nem confirmação de ataque.

### T08 — Falhas de coleta e persistência

- [x] Fonte e coletor parados separadamente com autenticacao aberta: nenhum zero/falsa recuperacao. Tecnicos detectados em 9s/86s; nodata do coletor em 100s desde ultima qualidade valida.
- [x] Keycloak retomado no mesmo container/volume, discovery/JWKS/negativa 401 aprovados. API saudavel durante parada; provedor inacessivel a novo login, sem alegar revogacao instantanea de sessao existente.
- [x] Credencial/config/schema/limite invalidos em testes isolados e pipeline Zabbix de fixture; sem estragar segredos/eventos reais.
- [x] Recuperacao tecnica somente apos consulta completa valida; retomada do coletor encontrou janela=4 e so entao recuperou autenticacao. Demais seis servicos preservados em cada parada isolada.
- [x] Validacao antecipada da disponibilidade: banco/server/frontend reiniciados e depois recriados com o mesmo volume. Snapshot publico selecionado (configuracao, dashboard, filtros, retencao, metadados de contas, quatro eventos e duas amostras antigas) preservado; duas amostras novas saudaveis em cada fase. API/identidade nao reiniciadas durante esse ensaio; dois ciclos adicionais da API aprovados apos a recriacao.
- [x] Login real com senha nova após recriação confirmado pela autora, além do logout e bloqueio sem sessão. Não inferido dos metadados do banco; nenhum hash de senha consultado.
- [x] Persistencia integrada banco/server/frontend/coletor: restart/recreate aprovados com snapshot publico, quatro widgets, eventos/historico selecionados e mesmo volume; duas novas amostras saudaveis e duas qualidades validas por fase. API/identidade preservadas nesse ensaio; login final confirmado pela autora.
- [x] Restart/recreate apenas do coletor em janela real=5 produziu novas amostras validas=5, sem duplicar/zerar; segredos preservados e outros seis servicos intocados.
- [x] Retencoes 24h/7d, lacunas controladas/nao controladas e limites de reconstrucao documentados; nenhum volume, evento real ou credencial removido.

**Validação:** MO-07/MO-08 e complemento de MO-09. Registrar datas/horários e restaurar todos os serviços/configurações alterados pelo ensaio.

### T09 — Regressão, reprodução e fechamento

- [x] Regressao final: 35 API + 10 estaticos + 12 OIDC, 39 coletor + TypeScript strict + 14 contrato/API, 8 contrato de disponibilidade + 7 schema/gramatica; discovery/probe aprovados. Revisao do controle ficticio acrescentou 2 testes de autenticacao/HTTP e probe em container sem API administrativa.
- [x] Configuracoes/bindings reais revalidados: 42 checks + restricoes reais do coletor; API sem portas/mounts e so service; profiles/modos independentes de disponibilidade conferidos.
- [x] Confirmacao manual final preservou operadora/visitante/MFA, sem recadastro OTP/grupos; sessao/logout do painel confirmados novamente. Limites de sessao da entrega 02 preservados, sem fingir nova cronometragem de cinco minutos.
- [x] Tags/IDs reais registrados, incluindo 109→112, 113→124 e ciclos API finais 137→138/139→140; sem webhook ou deduplicacao n8n presumida.
- [x] Runbook reproduzido no ambiente existente, com provisionamento/testes/retomada executados e autoria/relato distinguidos. Nova instalacao completa em outra maquina nao foi testada.
- [x] Matriz MO-01–MO-10 consolidada. Revisao final de sintaxe/links/arquivos/logs e protecao do alvo ficticio na secao 17 das evidencias; nenhuma captura com segredo ou export bruto. Varredura limitada, sem garantia universal/validacao de ancoras.
- [x] PLAN/roadmap/README/arquitetura/SPEC/runbook/topologia alinhados ao aceite real; token temporario revogado com negativa confirmada e coletor valido depois. Nenhum commit/push automatico.

**Gate final:** MO-01–MO-10 aprovados. Entrega 04 permanece não implementada; problema único no Zabbix não comprova deduplicação ou entrega de futuras notificações.

## 4. Registro de execução

| Data | Atividade | Resultado real | Pendência |
| --- | --- | --- | --- |
| 25/10/2026 | Rascunho inicial | SPEC/PLAN descreviam Kuma; nenhum monitor implementado | Desenho substituído por esta revisão, não usar tarefas/opções antigas |
| 25/10/2026 | Aprovação funcional em conversa | Autora concordou com Zabbix, disponibilidade e cenário pequeno de LOGIN_ERROR; n8n depois, sem IA | Aprovar novas decisões técnicas M-D01–M-D06 antes da implementação |
| 25/10/2026 | Revisão documental solicitada | Arquivos Compose/config existentes inspecionados; docs Zabbix 7.0/Keycloak 26.8.1, código de autorização/filtros e metadados de três imagens consultados somente por HTTP; SPEC/PLAN reescritos | Sem pull, client, evento real ou teste de runtime; validar viabilidade e contrato antes de implementar |
| 25/10/2026 | Validação estática dos documentos | `git diff --check` aprovado; sete links locais com destinos existentes; MO-01–MO-10 presentes nos dois documentos e M-D01–M-D06 definidos na SPEC | Não valida links externos/âncoras, expressões executáveis, infraestrutura ou critérios de runtime |
| 25/10/2026 | Aprovacao e inicio T01/T02 | Autora aprovou M-D01–M-D06 e implementacao; imagens baixadas, scripts/overlay escritos, banco inicializado nao root e schema Zabbix importado com role nao superuser | Gate de disponibilidade separado da verificacao runtime da coleta; nenhum client/evento provisionado |
| 25/10/2026, 11:20–11:24 -03:00 | Infraestrutura real | Server 7.0.32 iniciou, schema 07000000/07000030; frontend ping 200/API 7.0.32. 23 estaticos/42 runtime aprovados. Guest pertence ao grupo Disabled; anonimo recebeu aviso de nao autenticado | Troca de senha Admin e validacao manual do painel pendentes; nenhum cenario web configurado |
| 25/10/2026 | Regressao antecipada apos novas redes | 35 API (5799.136844 ms), 10 estaticos identidade (227.398807 ms), 12 verificacoes OIDC isoladas aprovados; probe/discovery aprovados | Nao substitui regressao final T09 nem testes manuais; entrega permanece em implementacao |
| 25/10/2026 | Checkpoint solicitado | Commit 0427f9e criado, sem push; arvore limpa imediatamente apos commit | Novas alteracoes desta etapa nao sao commitadas automaticamente |
| 25/10/2026 | Troca da senha inicial | Autora relatou troca bem-sucedida; nenhuma excecao para manter senha padrao foi aplicada | Confirmar logout/relogin e cookies, sem coletar credenciais |
| 25/10/2026 | Preparacao de T03 | Host JSON importavel com cenario 20s/5s/1 tentativa, HTTP200 sem redirects e triggers Single falha/nodata; 8 testes Node e 7 verificacoes PHP-FPM originais aprovados, todos isolados do banco real | Autora importar pela UI; nao marcar host como configurado ate verificacao real |
| 25/10/2026 | Importacao real confirmada | Autora informou “deu certo!”; SELECTs confirmaram cenario e expressoes reais, duas amostras saudaveis e HTTP200. Test-MonitoringAvailability.ps1 inspeciona sem mutar por padrao | Cookies/logout, retencao/dashboard e negativos 500/redirect/ausencia de dados ainda pendentes |
| 25/10/2026, 12:04–12:06 -03:00 | T04 — dois ciclos reais | Problemas/recuperacoes 31→32 e 33→34, tres amostras falhas e um problema por ciclo, duracao observada 60 s cada; API healthy e demais servicos sem reinicio | T04 executada, mas entrega nao concluida; falta completar T03 e coleta de seguranca |
| 25/10/2026 | Verificacao pos-ciclos | 42 checks de infraestrutura novamente aprovados; discovery/JWKS e negativa sem secret aprovados, inspecao final somente leitura com duas amostras saudaveis | Host padrao Zabbix server ainda habilitado; housekeeping ainda nos defaults, autora deve aplicar politica aprovada pela UI |
| 25/10/2026, 12:20 -03:00 | Retencao e host padrao | Autora informou “feito!”; SELECT confirmou hk_events_mode=1, hk_events_trigger=7d, hk_history_mode=1, hk_history_global=1 e hk_history=7d; host padrao status=1 e API status=0 | Politica configurada nao comprova expurgo; trends sem override. Dashboard, cookies e negativos adicionais pendentes |
| 25/10/2026 | Inspecao apos ajustes da UI | Test-MonitoringAvailability.ps1 aprovado em modo somente leitura: duas amostras saudaveis recentes, fail=0 e HTTP200; nenhum servico parado | Prosseguir com dashboard sem criar widgets de seguranca ainda sem fonte |
| 25/10/2026, 14:05 -03:00 | Dashboard de disponibilidade | Autora confirmou criacao/visualizacao; inspecao real: Private=1, sem compartilhamentos, widgets web/problems filtrados para API, Show=3 (Problems ativos), tags service/category corretas | Cookies/logout/relogin e extensao com seguranca ainda pendentes |
| 25/10/2026, aproximadamente 14:11–14:13 -03:00 | Persistencia antecipada | Test-MonitoringPersistence.ps1 aprovado: restart preservou IDs e alterou start times; recreate alterou IDs dos tres novos containers, com volume/snapshot selecionado preservados. Duas amostras novas saudaveis por fase; API/Keycloak/gateway intocados durante teste | Autenticacao real apos retomada e persistencia do coletor ainda pendentes; nao conclui MO-08 inteiro |
| 25/10/2026, 14:15–14:18 -03:00 | Ciclos apos recriacao | Eventos 37→38 e 39→40; DOWN em 6s/14s, UP em 8s/9s apos healthy, tres amostras falhas e um problema por ciclo; API retomada | Nenhum dado/volume apagado; negativos adicionais e seguranca ainda pendentes |
| 25/10/2026 | Sessão do painel após recriação | Autora confirmou logout, bloqueio do dashboard e login com senha nova; informou somente atributos na verificação final: HttpOnly marcado, Secure desmarcado, SameSite vazio, Path=/, Domain=localhost | Cookie compartilhado antes dessa confirmação não foi decodificado/reproduzido; logout confirmado, sem teste de replay. Negativos HTTP/nodata e coletor ainda pendentes |
| 25/10/2026 | T05/T06 — inicio da coleta | Aprovado recorte minimo; armazenamento LOGIN_ERROR/86400 e client view-events provisionados. Snapshot selecionado de identidade preservado, leitura permitida e PUT identico negado 403. Coletor ativo, rede/mounts/restricoes reais conferidos e janela vazia valida | Integracao Zabbix e eventos reais de limiar ainda pendentes; nao conclui MO-05/06/07/08 |
| 25/10/2026 | Preparacao da integracao | Contrato de itens/triggers e preprocessamento com 10 testes locais aprovados, ainda nao aplicado a API Zabbix. Token foi compartilhado involuntariamente no chat; nao utilizado ou copiado aos arquivos/comandos | Autora precisa revogar token divulgado, gerar substituto e salva-lo no prompt oculto local. Solicitou ajuda no terminal; integracao bloqueada ate arquivo seguro disponivel |
| 26/10/2026, 06:58–07:03 -03:00 | Retomada e token local | Autora confirmou arquivo salvo e token anterior revogado. Docker Desktop estava parado; iniciado e sete containers existentes retomados sem recriacao/remoção de volumes. Discovery/JWKS e negativa 401 aprovados; coletor valido/401 sem segredo, disponibilidade e 42 checks aprovados | Preflight da API rejeitou token local expirado. Nenhuma configuracao Zabbix aplicada; autora pediu ajuda para editar validade pela UI. Nao usar token divulgado nem alterar autorizacao/SQL |
| 26/10/2026 | Integracao e negativos | Token com validade corrigida; tres itens/duas triggers/quatro widgets aplicados e conferidos. 500/302 falharam em alvo ficticio; falhas nao recuperaram autenticacao; nodata de qualidade 117s e principal 118s | Recursos ficticios exclusivos removidos; fonte/limiar reais verificados depois |
| 26/10/2026 | Dois ciclos reais e falhas | Eventos 109→112/113→124, cinco LOGIN_ERROR por ciclo e tres amostras/um problema. Keycloak/coletor parados separadamente: tecnicos em 9s/86s, sem zero/falsa recuperacao. Reconstrucao real=5 apos restart/recreate do coletor | Divergencia de numero de submissoes no ciclo 2 registrada, sem equiparar a cinco eventos |
| 26/10/2026, aproximadamente 07:44–07:49 -03:00 | Persistencia integrada e novos ciclos API | Quatro componentes restart/recreate com mesmo volume/snapshot selecionado; duas novas amostras saudaveis e qualidades validas por fase. API 137→138/139→140: DOWN 7s/13s, UP 8s/8s, demais seis servicos preservados | Limites de snapshots/retencao/lacunas documentados; nao e backup/HA |
| 26/10/2026 | Aceite manual e regressao final | Autora confirmou logout/login/quatro widgets, operadora+TOTP e visitante 403. Intervalo dos logins corretos sem LOGIN_ERROR. 35+10+12, 39+14+8+7, TypeScript, discovery/probe e infraestrutura aprovados | Origens fixture/runtime/relato distinguidas |
| 26/10/2026, a partir de 08:00 -03:00 | Fechamento | Token temporario revogado e chamada negada; coletor continuou valido. Documentacao/sanitizacao/sintaxe/links/whitespace revisados. Controle do alvo ficticio protegido por chave efemera e retestado sem token administrativo; sete servicos ativos e API saudavel | Entrega 04 nao iniciada; sem commit/push |

## 5. Checklist de conclusão — entrega concluída

- [x] M-D01–M-D06 resolvidas, viabilidade confirmada e implementação autorizada.
- [x] MO-01–MO-10 executados com sucesso, com origem/limites de cada evidência.
- [x] API intacta; painel autenticado em loopback; banco/coletor/server sem publicação/socket/privilégios não aprovados.
- [x] Dois ciclos de queda/recuperação e dois ciclos de segurança validados com tempos reais.
- [x] Coleta mínima, autenticada e restrita; falha/ausência de dados não viram saúde ou recuperação indevida.
- [x] Conta/configuração/histórico persistentes; identidade/MFA/grupos preservados.
- [x] Runbook reproduzido no laboratório, regressão aprovada e documentação compartilhada alinhada; sem alegar instalação nova em outra máquina.
- [x] Evidências sanitizadas, sem export bruto; nenhuma IA, n8n, SMTP ou automação futura implementada.
