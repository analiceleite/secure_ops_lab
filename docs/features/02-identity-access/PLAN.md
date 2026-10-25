# PLAN 02 — Identidade e acesso

**Estado:** em implementação. D01–D03 e política de MFA/sessão aprovadas explicitamente pela autora em 24/10/2026; navegador/autenticador disponíveis e implementação autorizada. Resultados reais serão registrados por tarefa.

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

Estrutura implementada nesta etapa (gateway ainda sem execução permanente):

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

### T04 — Provisionar contas, claims e MFA — parcial, aguardando testes negativos

- [ ] Criar client/scopes/mappers conforme SPEC; conferir redirect URI exata, audience e desativação dos fluxos não utilizados.
- [x] Autora criou as duas contas fictícias; inspeção em 25/10 confirmou somente operadora no grupo permitido e presença de senha em ambas. E-mails fictícios marcados como verificados na correção autorizada, sem alterar credenciais/grupos/roles.
- [ ] Vincular fluxo dedicado de senha+OTP obrigatórios, sem alternativa que ignore MFA; testar cadastro inicial em conta sem OTP.
- [x] Autora confirmou em 25/10 o acesso da operadora após correção e o cadastro/acesso da visitante na interface de conta. Confirmação manual relatada em conversa, sem coleta de QR/seed/código; não é ainda teste do gateway.
- [ ] Validar nova autenticação e erro de OTP; comprovar que senha sozinha não conclui o fluxo.
- [ ] Conferir claims do login real sem copiar token. Preview administrativo de 25/10 confirmou subject/roles da interface de conta, email_verified, audience e separação de grupos, mas não substitui token do fluxo real.

**Correção autorizada em 25/10:** após `Unexpected error` no `account-console`, restaurar scopes `basic`/`roles` ausentes com definições nativas da mesma versão, associar `basic/profile/email/roles` à interface de conta e `basic` ao gateway, sem conceder novas roles. Template passou a solicitar geração dos defaults nativos via `CreateDefaultClientScopes`, mantendo apenas `groups` customizado. OTP da operadora preservado; visitante ainda depende de cadastro. Testes e limites nas [evidências](../../evidence/02-identity-access.md), seção 7.

**Validação:** IA-05 e preparação de IA-06/IA-07. Required action de cadastro e token preview, isoladamente, não comprovam MFA nem autorização no gateway. Sem autora/autenticador, registrar bloqueio e não avançar alegando sucesso.

**Progresso manual posterior à correção:** autora confirmou que a página da operadora abriu e depois que o cadastro/acesso da visitante funcionou. Falta novo login da visitante e rejeição de OTP incorreto/ausente para ambas. T04 permanece parcial; detalhes na seção 8 das evidências.

### T05 — Adicionar e configurar o gateway

- [ ] Adicionar OAuth2 Proxy nas duas redes da SPEC, sem alterar redes/bindings da API; porta loopback, usuário não root e logs limitados.
- [ ] Aplicar provider, issuer, client confidencial, PKCE, escopos, grupo exato e domínio da SPEC.
- [ ] Habilitar explicitamente verificação de nonce; manter issuer/assinatura/audience e e-mail verificado. Sem bearer bypass, skip-auth de upstream ou preflight público.
- [ ] Configurar cookies/tempos aprovados, sem `Domain` compartilhado, sem encaminhar tokens à API ou resposta. Conferir documentação dos headers e não inferir que uma opção remove todos os headers por nome parecido.
- [ ] Configurar logs sem query de callback e sem debug; verificar erros localmente antes de exportar saídas.
- [ ] Validar configuração resolvida de forma seletiva/sanitizada e iniciar gateway com prazo finito.

**Validação:** IA-02/IA-03 completos; novos serviços não tornam a API pública. Sem sessão, gateway exige login e `/oauth2/auth` retorna 401; callback incompleto não cria sessão.

### T06 — Testar acesso permitido e negações no navegador

- [ ] Sessão limpa: visitar `/` e `/health` pelo gateway, sem receber conteúdo da API; inspecionar redirecionamento somente para hosts previstos.
- [ ] Injetar headers fictícios de usuário/grupo/autorização sem cookie: acesso continua bloqueado.
- [ ] Operadora: senha sozinha não libera; OTP incorreto falha; OTP válido e grupo exato permitem 200/JSON original.
- [ ] Visitante: concluir senha+OTP no Keycloak e observar negação no gateway. Separar evidência de autenticação do IdP da evidência HTTP 403, sem tratar mero erro de login como teste de autorização.
- [ ] Em conta fictícia, testar grupos ausente/vazio/semelhante, um ajuste por vez; registrar/restaurar configuração e usar sessão nova. Confirmar controle positivo após restauração.
- [ ] Definir/executar teste isolado do verificador de ID token do gateway com assinatura válida, audiência incompatível e controle positivo. Sem harness reproduzível, registrar IA-08 parcial/bloqueado. Erro de client secret/código não substitui esse teste; não modificar o emissor do gateway principal nem desligar verificações.
- [ ] Cookie adulterado e callback sem state válido: não liberam; não armazenar cookie/código em relatório.
- [ ] Conferir atributos dos cookies no navegador, incluindo cookie de CSRF e limite de tamanho; erro de cookie grande não se resolve desabilitando proteção ou adicionando Redis sem análise.

**Validação:** IA-04 a IA-08; status/caminhos reais e resultados sanitizados registrados. Provar que um token arbitrário sem sessão não passa não é prova isolada da validação de assinatura do fluxo OIDC.

### T07 — Sessão, logout, persistência e falhas

- [ ] Medir validade de 5 min sem renovação; requisições periódicas não estendem o prazo. Verificar comportamento após expiração com sessão do Keycloak existente.
- [ ] Remover grupo da operadora ou bloquear sua conta temporariamente; login novo negado e sessão anterior deixa de dar acesso até o limite da SPEC. Restaurar apenas a configuração alterada e retestar.
- [ ] Logout só no gateway: cookie removido e distinguir sessão remanescente no IdP. Encerrar ambas as camadas e verificar nova senha+OTP; sem prometer single logout.
- [ ] Reiniciar Keycloak/gateway sem apagar volume, mantendo chave de cookie local; verificar realm/client/grupo/OTP persistentes e login/negação após reinício.
- [ ] Parar Keycloak e testar login novo negado; sessão existente pode funcionar até expirar. Retomar e aguardar prontidão.
- [ ] Parar somente API: sessão autorizada recebe erro upstream, nunca falso sucesso. Retomar API, aguardar saúde e verificar acesso.

**Validação:** IA-09 a IA-11. Registrar janela real de revogação, estado das sessões e limites; se ultrapassar o contrato, investigar/revisar explicitamente, não declarar revogação imediata.

### T08 — Regressão, documentação e fechamento

- [ ] Reexecutar os 35 testes da Fundação via Compose e probe interno; reinspecionar API sem portas, só em `service` e sem mounts novos.
- [ ] Conferir bindings de gateway/Keycloak em `127.0.0.1`, usuário efetivo, mounts aprovados e logs sem segredos.
- [ ] Registrar consumo observado, versões/digests e prazos de prontidão; medir é diferente de estimar.
- [ ] Criar runbook com bootstrap/import, cadastro TOTP, login/negação, expiração/logout, parada/recuperação e preservação do volume.
- [ ] Criar evidências por IA-01 a IA-12, sanitizadas; revisar screenshots, URLs, configs e exports. Não versionar export integral do realm com dados reais do laboratório.
- [ ] Repetir procedimento documentado no ambiente disponível; registrar quem executou cada passo manual e quais limitações permanecem.
- [ ] Atualizar README/arquitetura/roadmap somente conforme resultados; concluir apenas com todos os critérios verificados.

**Validação:** IA-12 e revisão dos anteriores. Não adiantar monitoramento, automação ou frontend.

## 4. Comandos e recuperação previstos

Nomes implementados no overlay. T01–T03, regressão e `--config-test` executados; cadastro de contas/MFA e início permanente do gateway não executados. Procedimentos repetíveis no [runbook](../../runbooks/identity-access.md).

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

## 6. Checklist de conclusão

- [x] D01–D04 resolvidas com risco/limites aprovados e desenho revisado.
- [ ] IA-01 a IA-12 comprovados, incluindo navegador e TOTP real fictício.
- [ ] Nenhuma porta da API publicada; interfaces novas somente loopback.
- [ ] Autenticação da visitante bem-sucedida e autorização negada pelo gateway.
- [ ] Sessão, logout e revogação explicados sem promessas de invalidação instantânea.
- [ ] Realm e MFA persistentes sem exclusão de volumes.
- [ ] Logs, templates, arquivos e evidências sem segredos.
- [ ] Regressão da Fundação aprovada e documentos consistentes.

Até cumprir o checklist, a entrega não está concluída. Aprovar um desenho não equivale a validar sua implementação.
