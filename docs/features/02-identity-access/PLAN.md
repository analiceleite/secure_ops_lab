# PLAN 02 — Identidade e acesso

**Estado:** concluída em 25/10/2026. IA-01–IA-12 verificados por testes técnicos e confirmações manuais da autora, diferenciados na [matriz final de evidências](../../evidence/02-identity-access.md#19-confirmação-final-e-fechamento--25102026). D01–D04 e limites locais preservados. Registros de execução anteriores são históricos.

## 1. Execução e gates

- Uma tarefa por vez, com resultado registrado antes de avançar. A solicitação atual autoriza ajustar documentos e iniciar implementação; não autoriza ampliar escopo ou dispensar validações.
- A SPEC é a fonte de comportamento, URLs, política e aceite. Não esconder mudanças de segurança neste plano.
- Usar PowerShell e Docker Linux. Preferir os serviços e módulos já existentes; não pressupor shell/curl nas imagens de terceiros.
- Consultar docs e `--help` da versão exata antes de escrever flags, import JSON, testes ou health checks. Não copiar comandos com `latest`/senhas de exemplo.
- Não alterar hosts, firewall, confiança de certificados ou relógio do sistema sem autorização específica. Não usar serviços externos de teste de OIDC/QR/JWT.
- Se D01 não for aprovada, parar e revisar o desenho de HTTPS; não implementar as duas alternativas.
- Evidência exige resultado real. Registrar como pendentes os passos que dependam da autora, inclusive cadastro TOTP e navegador.

## 2. Estado inicial e arquivos previstos

Na inspeção inicial, Compose continha somente `api`, `probe`, `api-test`, rede `service` interna e API sem porta/volume. Fundação concluída com 35 testes; naquele momento não havia configuração de Keycloak/gateway. A estrutura abaixo descreve o acréscimo atual.

Estrutura implementada nesta etapa (API/Keycloak/gateway executando no fechamento):

```text
compose.yaml                         # preservar Fundação e seus comandos
compose.identity.yaml                # overlay: serviços, rede identity e volume
infra/identity/keycloak.env.example   # placeholders, nunca valores utilizáveis
infra/identity/{config.test,check-discovery}.mjs # testes estáticos e cliente interno
.gitignore / .dockerignore           # revisar exclusão de artefatos sensíveis
infra/keycloak/realm-template.json   # configuração sanitizada, sem credenciais
infra/oauth2-proxy/                  # configuração não secreta, formato confirmado
docs/runbooks/identity-access.md     # bootstrap, TOTP, testes, logout e recuperação
docs/evidence/02-identity-access.md   # criar ao executar, não fabricar evidência
scripts/Initialize-Identity.ps1       # geração local sem sobrescrita, ACL restrita
scripts/Test-IdentityDiscovery.ps1    # espera finita pelo discovery do host
scripts/Test-IdentityVerifier.ps1     # proxy real em rede interna temporária
infra/identity/verify-isolated.mjs    # emissor/upstream de fixture e cenários negativos
```

Se um template precisar de renderização com segredos, gerar apenas artefato local ignorado e montar somente o arquivo necessário em modo read-only. Não incluir `.env`, volume ou diretório com segredos no contexto de build. Não adicionar biblioteca de templates por conveniência.

## 3. Tarefas

### T01 — Revisar decisões e conferir viabilidade

- [x] Apresentar D01–D03 e registrar a decisão explícita da autora, inclusive limites e riscos do HTTP/cookie não seguro.
- [x] Confirmar navegador e autenticador disponíveis; cadastro manual combinado para T04, com nova interação da autora nessa etapa.
- [x] Reconfirmar Docker/Compose Linux e estado dos serviços, preservando dados existentes.
- [x] Verificar versões candidatas, imagens/manifests `linux/amd64`, digests e documentação do tag. Digests fixados no overlay.
- [x] Conferir opções do provider, nonce, cookie/session, logs, logout, hostname, fluxo OTP e persistência na versão exata. Runtime completo será validado nas etapas seguintes.
- [x] Verificar portas 4180/8080 livres; Chrome alcançou ambos os nomes em loopback. Windows DNS retornou NXDOMAIN; nenhum hosts/DNS alterado.
- [x] Fixar TOTP HmacSHA1, janela 1, 6 dígitos/30 s; Keycloak limitado a 1 GiB, espera 120 s e parada 30 s; gateway espera 60 s e parada 10 s. Medições reais parciais nas evidências.

**Validação/gate:** IA-01 preparado e decisões registradas; sem decisão de transporte não avançar a T02. Consultar metadados e documentação não comprova autenticação.

Comandos de preparação executados: `docker version`, `docker compose version`, `Get-NetTCPConnection` com filtro de portas e inspeção de manifesto das tags aprovadas. Resultados nas evidências; sem dumps integrais de ambiente.

### T02 — Preparar configuração local e segredos

- [x] Escrever exemplo não funcional e instrução de geração local; revisar ignores antes de gerar arquivos reais.
- [x] Gerar senha de bootstrap, client secret e chave de cookie compatíveis, sem exibir valores. Senhas das contas serão definidas pela autora na T04, conforme procedimento de criação manual.
- [x] Gateway lê arquivos read-only suportados pela versão; Keycloak usa ambiente para bootstrap/substituição do import, com visibilidade ao administrador Docker documentada. Pasta local com ACL restrita, ignorada no Git/build.
- [x] Criar template sem usuários/senhas/OTP/chaves, com realm/client/scopes/grupo e fluxo dedicado; bootstrap manual documentado.
- [x] Manter bootstrap separado e documentar passagem para conta administrativa permanente testada, sem remoção automática. Passagem efetiva depende da autora e permanece pendente.

**Validação:** placeholders não iniciam o sistema como se fossem credenciais reais; arquivos sensíveis não entram no Git/build. Não coletar `compose config` completo com segredos substituídos.

### T03 — Adicionar Keycloak e validar emissor

- [x] Acrescentar Keycloak, rede `identity` e volume aprovados. D04 autorizou bridge não interna após binding vazio com rede interna. Loopback, memória, UID não root, logs e ausência de socket/privilégios extras inspecionados.
- [x] Configurar hostname completo e alias interno, sem backchannel dinâmico ou URLs divergentes.
- [x] Iniciar Keycloak em HTTP/start-dev aprovado; espera finita pelo discovery do host, sem curl na imagem.
- [x] Importar realm; preservar volume/realm após reinício. Corrigir pontualmente scopes profile/email ausentes via cliente administrativo temporário, sem exclusão/reset. Template corrigido para instalações novas; não há script administrativo permanente.
- [x] Validar discovery do host, formulário OIDC no Chrome e cliente Node temporário interno: issuer/endpoints exatos, JWKS 200, token endpoint 401 sem secret. Cadastro/login continuam pendentes.
- [x] Conferir bindings efetivos, rede/mounts, UID/CapEff/NoNewPrivs; porta de gestão não publicada.

**Resultado:** T03 executada; DNS interno aponta para o container e o host alcança a porta loopback. IA-02/IA-03 ainda dependem do gateway real. Falha de publicação da proposta interna resolvida somente após aprovação explícita D04. Evidências registram limites, erros iniciais e correções.

### T04 — Provisionar contas, claims e MFA — executada

- [x] Client/scopes/mappers implementados e inspecionados; callback exato, fluxos extras desabilitados, fluxo real validado pelo gateway e audience negativa exercitada separadamente no harness.
- [x] Autora criou as duas contas fictícias; inspeção em 25/10 confirmou somente operadora no grupo permitido e presença de senha em ambas. E-mails fictícios marcados como verificados na correção autorizada, sem alterar credenciais/grupos/roles.
- [x] Fluxo dedicado vinculado e inspecionado no realm em uso com senha/OTP REQUIRED e sem Cookie; cadastro inicial e logins das duas contas confirmados manualmente pela autora.
- [x] Autora confirmou em 25/10 o acesso da operadora após correção e o cadastro/acesso da visitante na interface de conta. Confirmação manual relatada em conversa, sem coleta de QR/seed/código; não é ainda teste do gateway.
- [x] Autora relatou em 25/10 sucesso do procedimento solicitado para ambas na interface de conta: nova autenticação, senha sem OTP não conclui, código incorreto rejeitado e código válido aceito. Não é validação do client da aplicação/gateway.
- [x] Preview administrativo e inspeção do mapper combinados ao fluxo real do gateway; autora confirmou grupo `/secureops-operators` em `/oauth2/userinfo` após login. Não foi exportado/decodificado token real; audience negativa validada no harness, distinta do preview.

**Correção autorizada em 25/10:** restaurados scopes `basic`/`roles` ausentes após `Unexpected error`, sem novas roles de usuário nem reset de credenciais. Template corrigido para defaults nativos; autora depois confirmou cadastro, login e OTP das duas contas. Histórico detalhado nas seções 7–8 das evidências.

**Validação:** IA-05 e preparação de IA-06/IA-07. Required action de cadastro e token preview, isoladamente, não comprovam MFA nem autorização no gateway. Sem autora/autenticador, registrar bloqueio e não avançar alegando sucesso.

**Resultado final:** cadastro, fluxo obrigatório e autorização da aplicação comprovados por inspeção e relatos manuais. Confirmação final do grupo da sessão na seção 19 das evidências. Preparar rascunho 03 em paralelo não implementou monitoramento.

### T05 — Adicionar e configurar o gateway — executada

- [x] OAuth2 Proxy iniciado em 25/10 nas redes `identity`/`service`, porta somente `127.0.0.1:4180`, UID 65532, capabilities removidas e NoNewPrivs. API preservada sem porta/mount, somente `service`.
- [x] Configuração aceita por `--config-test`; início OIDC canônico e PKCE S256, seguidos de login real da aplicação relatado pela autora.
- [x] Configuração mantém nonce/issuer/assinatura/audience/e-mail verificado sem bypass. Redirect real com nonce/state; rejeições específicas aprovadas no harness T06.
- [x] Cookie CSRF inspecionado por HTTP, cookie de sessão conferido pela autora no navegador; forwarding de Authorization ausente no upstream isolado. Configuração de não encaminhar tokens e tempos preservada.
- [x] Logs configurados sem request/auth logging e sem debug; nenhum dump de logs/queries foi incluído na coleta desta retomada.
- [x] Compose válido, discovery interno aprovado, API saudável e gateway `/ready` 200 dentro da espera de 60 s. Inspeção seletiva de portas/redes/mounts/privilégios realizada.

**Validação:** IA-02/IA-03 completos; novos serviços não tornam a API pública. Sem sessão, gateway exige login e `/oauth2/auth` retorna 401; callback incompleto não cria sessão.

**Resultado em 25/10:** runtime, login real, cookies e negações verificados nas seções 9–19 das evidências. Callback incompleto retornou 500 sem sessão; state/nonce foram exercitados com precondições próprias no harness, não inferidos desse primeiro erro.

### T06 — Testar acesso permitido e negações no navegador

- [x] Anônimo negado em `/` e `/health` por cliente HTTP; fluxo manual em sessão limpa, pós-logout e expiração também não liberou API. `/oauth2/start` redireciona somente ao Keycloak canônico.
- [x] Cliente HTTP com headers fictícios de usuário/grupo/autorização sem cookie recebeu 403 em `/health` em 25/10, sem liberação da API.
- [x] Operadora: autora confirmou login exige senha+OTP, rejeição de OTP incorreto, JSON original, `/health` autorizado e controle positivo pós-restauração. Não foi coletado token nem status HTTP autenticado diretamente pelo agente; resposta 200 exercitada tecnicamente no harness e contrato da API.
- [x] Autora confirmou explicitamente em 25/10 que OTP incorreto foi rejeitado no login da aplicação. Ausência de OTP e resposta específica de `/health` não foram detalhadas nessa confirmação; não inferir observação do agente.
- [x] Após instrução de login da visitante com senha+OTP em sessão anônima nova na aplicação, autora relatou `Forbidden 403` em 25/10. Evidência manual relatada, não navegador observado pelo agente; sem JSON da API relatado. Variações de grupo e demais verificações de IA-07 permanecem pendentes.
- [x] Visitante/operadora sem grupo negadas no realm real; associação da operadora restaurada com controle positivo relatado. Claims ausente/vazia/grupo semelhante negadas no proxy real com identidade de fixture isolada, sem alterar mapper do realm principal; limites na seção 18 das evidências.
- [x] Harness reproduzível `Test-IdentityVerifier.ps1`: duas execuções finais completas com mesma imagem do proxy, rede interna temporária e sem portas/segredos reais. ID token de assinatura válida com audience incompatível negado, controle positivo 200; também issuer, assinatura, nonce e expiração inválidos. Gateway principal não alterado; seção 18 das evidências.
- [x] No harness, cookie real emitido e adulterado recebeu 403; original continuou válido. Callback com state alterado e cookie CSRF não chegou ao token endpoint. Nenhum cookie/token persistido nas evidências.
- [x] CSRF conferido por HTTP; atributos do cookie de sessão conferidos pela autora e pelo harness. Login real e controle positivo funcionaram sem erro de tamanho; não foi medido o limite máximo de grupos. Cookies de pré-login Keycloak inspecionados em Chrome headless, sem coletar valores; sessão autenticada Keycloak não inspecionada pelo agente. Seção 19 das evidências.

**Validação:** IA-04 a IA-08; status/caminhos reais e resultados sanitizados registrados. Provar que um token arbitrário sem sessão não passa não é prova isolada da validação de assinatura do fluxo OIDC.

### T07 — Sessão, logout, persistência e falhas

- [x] Autora relatou expiração em aproximadamente cinco minutos com atualizações periódicas e confirmou novo login exigindo senha+OTP sem sair do Keycloak. Medição manual aproximada, não cronometragem independente em segundos.
- [x] Grupo retirado temporariamente: login novo normal 403, sessão antiga anônima perdeu acesso; autora confirmou bloqueio até prazo de cinco minutos. Grupo restaurado e novo login positivo confirmado. Credenciais/demais associações preservadas.

**Revogação e restauração (25/10):** grupo retirado às 08:56:41 (-03:00) e restaurado às 09:06:36; autora confirmou teto até 09:01:41 e controle positivo final. Não houve medição automática da expiração nem revogação instantânea. Nenhum grupo semelhante foi criado no realm principal.
- [x] Autora confirmou sucesso do procedimento de logout em duas camadas: gateway bloqueia `/health`, sessão Keycloak permanece ativa até logout próprio e novo login após ambas exige senha+OTP. Resultado manual relatado; remoção do cookie inferida pelo comportamento, não por inspeção direta do agente. Sem promessa de single logout.
- [x] Após Docker voltar, retomados os containers existentes de Keycloak/API/gateway em 25/10, aproximadamente 08:42–08:43 (-03:00), sem exclusão de volume. Nome do volume e arquivos de segredo preservados; realm/client/fluxo obrigatório, contas, grupos e metadados password/OTP conferidos por leitura administrativa. Autora confirmou depois os dois testes solicitados: operadora acessa com OTP existente e visitante recebe 403 após autenticação, em sessões novas. Persistência validada nessa retomada, sem recadastro de OTP relatado.

**Impedimento resolvido em 25/10:** engine voltou acessível; containers existentes retomados em ordem, sem reset/remover dados. Discovery/probe/metadados e login/negação pós-retomada confirmados. Código 255 anterior não teve causa determinada; não foi tratado como perda de dados.
- [x] Keycloak parado isoladamente em 25/10, 08:52 (-03:00): autora relatou erro ao acessá-lo no procedimento de login novo em sessão limpa, sem conclusão do login. API/gateway permaneceram ativos. Keycloak retomado às 08:53; discovery host/interno, JWKS e probe API aprovados. Não foi testada a continuidade de cookie preexistente durante a falha; não se promete revogação instantânea.
- [x] API parada isoladamente em 25/10, 08:46 (-03:00); autora relatou 502 Bad Gateway na sessão autenticada, sem falso sucesso. API retomada às 08:47, saudável e probe interno aprovado; autora confirmou depois retorno do JSON pelo gateway. Não informou necessidade de novo login. Keycloak/gateway permaneceram ativos.

**Validação:** IA-09 a IA-11. Registrar janela real de revogação, estado das sessões e limites; se ultrapassar o contrato, investigar/revisar explicitamente, não declarar revogação imediata.

### T08 — Regressão, documentação e fechamento

- [x] Regressão final em 25/10, aproximadamente 09:23 (-03:00): 35 API, 10 estáticos e 12 verificações isoladas aprovadas; discovery/probe e fronteiras da API novamente conferidos.
- [x] Bindings `127.0.0.1`, usuários/mounts/restrições e logs inspecionados; sem correspondências a segredos conhecidos/padrão JWT. IPv6 loopback não acessível; limites da varredura registrados.
- [x] Versões/digests, esperas e snapshots de memória registrados sem alegar dimensionamento.
- [x] Runbook revisado com bootstrap, contas/TOTP, login/negação, sessão/logout, falhas e preservação do volume.
- [x] Matriz IA-01–IA-12 consolidada, evidências sanitizadas e sem export de realm/credenciais.
- [x] Procedimentos técnicos executados pelo agente e interativos confirmados pela autora; origem/limites explícitos nas evidências.
- [x] README/arquitetura/roadmap/topologia atualizados conforme o fechamento; monitoramento não implementado.

**Validação:** IA-12 e revisão dos anteriores. Não adiantar monitoramento, automação ou frontend.

## 4. Comandos e recuperação previstos

Serviços implementados no overlay e validados. Procedimentos repetíveis no [runbook](../../runbooks/identity-access.md); registros de falhas/correções nas evidências. Nunca executar novamente o inicializador para rotacionar dados de instalação existente.

```powershell
docker compose -f compose.yaml -f compose.identity.yaml config --quiet
docker compose -f compose.yaml -f compose.identity.yaml up -d keycloak
# Validar readiness e emissor antes de iniciar gateway.
docker compose -f compose.yaml -f compose.identity.yaml up -d api oauth2-proxy
# Inspecionar campos selecionados; testar navegador conforme T06/T07.
docker compose --profile tools run --build --rm api-test
docker compose --profile tools run --rm --no-deps probe
docker compose -f compose.yaml -f compose.identity.yaml stop oauth2-proxy keycloak api
```

Não assumir `--wait` funcional antes de criar health checks reais para os serviços novos. Manter procedimentos de espera limitados e reproduzíveis no runbook; não instalar curl apenas para mascarar essa ausência.

Parar preserva o volume de identidade. Não executar `down -v`, prune, remoção de realm ou exclusão de dados para repetir testes. Corrigir apenas o serviço/configuração envolvido, preservar o volume e pedir autorização se uma ação destrutiva se tornar realmente necessária. Alteração de client secret exige sincronização consciente no client e gateway, não recriar o realm.

## 5. Registro de execução

Preencher quando tarefas forem autorizadas e executadas; não registrar aprovação ou resultado presumido:

| Tarefa/critério | Data | Procedimento e responsável | Resultado real | Pendência/próxima ação |
| --- | --- | --- | --- | --- |
| Documentação inicial | 24/10/2026 | Inspeção dos arquivos e consulta de releases/docs oficiais | SPEC/PLAN propostos; runtime preservado | Revisar D01–D03 e iniciar T01 somente quando solicitado |
| Revisão do desenho | 24/10/2026 | Decisões explícitas da autora em conversa | D01–D03, MFA a cada novo login, sessão de até 5 min e logout em duas camadas aprovados; navegador/autenticador disponíveis | Verificar viabilidade na T01; cadastro TOTP depende de participação manual |
| T01/T02 | 24/10/2026 | Agente: imagens/help, portas, Chrome headless, inicializador e ACL | Preparação/geração local executadas; sem segredos exibidos; recusa de sobrescrita testada | Cadastro de contas e senhas pela autora na T04 |
| T03/D04 | 24/10/2026 | Agente + aprovação explícita da autora para bridge normal | Keycloak pronto em loopback, issuer/DNS interno/JWKS verificados; volume preservado; scopes corrigidos pontualmente | Não alegar bloqueio de egress; gateway ainda sem runtime |
| Preparação de T05 | 24/10/2026 | Agente: arquivos e container temporário `--config-test` | Configuração válida após corrigir cookie-secret-file para 32 bytes brutos | T05 não concluída: iniciar gateway só após gate manual T04 |
| Regressão antecipada | 24/10/2026 | Agente: suites em containers e probe | 35 testes API + 9 verificações estáticas aprovados; API sem portas, só service, zero mounts; API parada novamente | Não substitui login/TOTP/autorização ou fechamento T08 |
| T04 — correção da interface de conta | 25/10/2026 | Autora autorizou; agente corrigiu scopes via cliente administrativo temporário e template | Credenciais/grupos/roles preservados; e-mails fictícios verificados; 10 testes estáticos, import isolado e discovery aprovados; previews com claims esperados | Autora retestar operadora com OTP existente e cadastrar visitante; sucesso interativo ainda não comprovado, gateway não iniciado |
| T05 e negações iniciais T06 | 25/10/2026 | Autora autorizou retomada; agente iniciou API/gateway e testou por cliente HTTP local | API saudável, gateway ready 200; bindings mínimos; anônimo/headers/cookie sintético negados; callback inválido 500 sem sessão; 10 estáticos aprovados | Autora testar login da operadora na aplicação; depois visitante, cookies, sessão/logout e falhas; audiência isolada ainda pendente |
| T08 — regressão parcial no fechamento | 25/10/2026 | Agente: suites, discovery, probe, inspeção seletiva e cliente HTTP | 35 API + 10 estáticos aprovados; API sem publicação; loopback dos serviços de identidade; ready 200 e negações preservadas | Sessão cronometrada ainda aguarda autora; demais testes T06/T07 e documentação final pendentes; entrega não concluída |
| T06–T08 — fechamento final | 25/10/2026 | Autora confirmou procedimento final; agente executou regressão e revisão | 35 API + 10 estáticos + 12 verificações isoladas aprovados; contas/grupo restaurados, sessão/logout/falhas/persistência confirmados; cookies de pré-login Keycloak inspecionados separadamente | Entrega concluída, mantendo limites documentados; próxima ação é revisar monitoramento para intenção de Zabbix, sem implementação nesta etapa |

## 6. Checklist de conclusão

- [x] D01–D04 resolvidas com risco/limites aprovados e desenho revisado.
- [x] IA-01 a IA-12 verificados, diferenciando browser relatado de containers/fixture observados.
- [x] Nenhuma porta da API publicada; interfaces novas somente loopback.
- [x] Autenticação da visitante seguida de negação pelo gateway relatada pela autora.
- [x] Sessão, logout e revogação explicados sem invalidação instantânea.
- [x] Realm e MFA persistentes após retomada, sem exclusão de volumes.
- [x] Logs/templates/evidências sanitizados e varredura limitada documentada.
- [x] Regressão aprovada e documentação consistente.

Entrega concluída em 25/10/2026 no escopo do laboratório. Migração do bootstrap para administradora permanente não executada, fora dos critérios IA-01–IA-12. Não equivale a produção, ZTNA completo ou auditoria independente.
