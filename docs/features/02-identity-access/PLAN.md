# PLAN 02 — Identidade e acesso

**Estado:** plano proposto; nenhuma tarefa de implementação ou validação de identidade executada. Depende da revisão das decisões D01–D03 da [SPEC](SPEC.md).

## 1. Execução e gates

- Uma tarefa por vez, com resultado registrado antes de avançar. Esta solicitação cobre documentos, não implementação.
- A SPEC é a fonte de comportamento, URLs, política e aceite. Não esconder mudanças de segurança neste plano.
- Usar PowerShell e Docker Linux. Preferir os serviços e módulos já existentes; não pressupor shell/curl nas imagens de terceiros.
- Consultar docs e `--help` da versão exata antes de escrever flags, import JSON, testes ou health checks. Não copiar comandos com `latest`/senhas de exemplo.
- Não alterar hosts, firewall, confiança de certificados ou relógio do sistema sem autorização específica. Não usar serviços externos de teste de OIDC/QR/JWT.
- Se D01 não for aprovada, parar e revisar o desenho de HTTPS; não implementar as duas alternativas.
- Evidência exige resultado real. Registrar como pendentes os passos que dependam da autora, inclusive cadastro TOTP e navegador.

## 2. Estado inicial e arquivos previstos

Inspeção documental: Compose contém somente `api`, `probe`, `api-test`; rede `service` interna e API sem porta/volume. Fundação concluída com 35 testes; nenhuma configuração de Keycloak/gateway presente.

Estrutura indicativa, a confirmar sem criar arquivos executáveis nesta fase:

```text
compose.yaml                         # adicionar serviços, rede identity e volume
.env.example                         # placeholders, nunca valores utilizáveis
.gitignore / .dockerignore           # revisar exclusão de artefatos sensíveis
infra/keycloak/realm-template.json   # configuração sanitizada, sem credenciais
infra/oauth2-proxy/                  # configuração não secreta, formato confirmado
docs/runbooks/identity-access.md     # bootstrap, TOTP, testes, logout e recuperação
docs/evidence/02-identity-access.md   # criar ao executar, não fabricar evidência
```

Se um template precisar de renderização com segredos, gerar apenas artefato local ignorado e montar somente o arquivo necessário em modo read-only. Não incluir `.env`, volume ou diretório com segredos no contexto de build. Não adicionar biblioteca de templates por conveniência.

## 3. Tarefas

### T01 — Revisar decisões e conferir viabilidade

- [ ] Apresentar D01–D03 e registrar a decisão explícita da autora, inclusive limites e riscos do HTTP/cookie não seguro.
- [ ] Confirmar navegador e autenticador disponíveis; definir passo manual e janela de acompanhamento da autora.
- [ ] Reconfirmar Docker/Compose Linux e estado dos serviços, preservando dados existentes.
- [ ] Verificar versões candidatas, imagens/manifests `linux/amd64`, digests e documentação do tag. Registrar eventual atualização deliberada na SPEC antes do uso.
- [ ] Conferir opções do provider, nonce, cookie/session, logs, logout, hostname, fluxo OTP e persistência na versão exata.
- [ ] Verificar portas 4180/8080 sem parar programas alheios; confirmar resolução de `app.localhost`/`keycloak.localhost` em loopback no navegador. Se indisponíveis, revisar URLs integralmente antes da implementação.
- [ ] Fixar algoritmo/janela OTP suportados, limite de memória e prazos de inicialização/parada. Proposta: aguardar Keycloak até 120 s e gateway até 60 s; medir, não ampliar indefinidamente.

**Validação/gate:** IA-01 preparado e decisões registradas; sem decisão de transporte não avançar a T02. Consultar metadados e documentação não comprova autenticação.

Comandos de preparação previstos (não executados por este plano): `docker version`, `docker compose version`, `Get-NetTCPConnection` com filtro de portas e inspeção de manifesto das tags aprovadas. Não usar dumps integrais de ambiente.

### T02 — Preparar configuração local e segredos

- [ ] Escrever `.env.example` com placeholders e instrução de geração local; revisar ignores antes de gerar arquivos reais.
- [ ] Definir senhas fictícias exclusivas, client secret e chave aleatória de cookie com tamanho/formato aceito pela versão; não imprimir valores em shell, logs, histórico ou documentação.
- [ ] Definir como passar segredos aos processos com mecanismos realmente suportados; não presumir suporte `_FILE` de variáveis. Preferir arquivos locais estreitos/read-only quando compatíveis; documentar se algum segredo precisar de variável de ambiente e sua visibilidade ao administrador do Docker.
- [ ] Criar template do realm/client/scopes/grupo e fluxo de MFA sem usuários com credenciais nem chaves; planejar bootstrap manual mínimo e atribuições explícitas.
- [ ] Manter administradora de bootstrap separada e registrar como encerrar seu uso de bootstrap sem apagar contas/dados.

**Validação:** placeholders não iniciam o sistema como se fossem credenciais reais; arquivos sensíveis não entram no Git/build. Não coletar `compose config` completo com segredos substituídos.

### T03 — Adicionar Keycloak e validar emissor

- [ ] Acrescentar somente Keycloak, rede `identity` e volume aprovados. Publicação somente em loopback, memória limitada, usuário não root, logs limitados e sem socket/privilégios extras.
- [ ] Configurar hostname completo e alias interno da SPEC, sem backchannel dinâmico ou URLs divergentes.
- [ ] Iniciar Keycloak com o modo de transporte aprovado e readiness finito, sem presumir `curl` dentro da imagem.
- [ ] Criar/importar realm de forma idempotente: se já existir, não sobrescrever nem apagar volume. Registrar divergências e correções pontuais.
- [ ] Validar discovery do navegador/host e, com cliente Node temporário na rede `identity`, os endpoints internos, issuer exato e acesso a JWKS/token endpoint conforme método esperado.
- [ ] Conferir bindings efetivos, rede e mount estritamente necessário; porta de gestão não publicada.

**Validação:** parte de IA-02/IA-03; confirmar que `keycloak.localhost:8080` resolve para o container dentro de `identity`, nunca para o próprio gateway. Falha de DNS/issuer é bloqueio, não motivo para pular validações.

### T04 — Provisionar contas, claims e MFA

- [ ] Criar client/scopes/mappers conforme SPEC; conferir redirect URI exata, audience e desativação dos fluxos não utilizados.
- [ ] Criar as duas contas fictícias, marcar e-mails locais como verificados e adicionar somente operadora ao grupo permitido; senhas entram apenas no ambiente local.
- [ ] Vincular fluxo dedicado de senha+OTP obrigatórios, sem alternativa que ignore MFA; testar cadastro inicial em conta sem OTP.
- [ ] Autora cadastrar TOTP manualmente para ambas as contas; não coletar QR/seed ou código como evidência.
- [ ] Validar nova autenticação e erro de OTP; comprovar que senha sozinha não conclui o fluxo.
- [ ] Conferir claims no ambiente local sem copiar token: evidência contém apenas nomes de claims, audiência esperada e grupo fictício sanitizado.

**Validação:** IA-05 e preparação de IA-06/IA-07. Required action de cadastro e token preview, isoladamente, não comprovam MFA nem autorização no gateway. Sem autora/autenticador, registrar bloqueio e não avançar alegando sucesso.

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
- [ ] Em client/conta fictícios, testar grupos ausente/vazio/semelhante e audience incompatível, um ajuste por vez; registrar configuração anterior, testar com sessão nova e restaurar pontualmente. Confirmar teste positivo após restauração.
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

Os nomes dos serviços são propostas. Confirmar opções da versão e arquivos antes de executar; **nenhum comando desta seção foi executado para identidade**.

```powershell
docker compose config --quiet
docker compose up -d keycloak
# Validar readiness e emissor antes de iniciar gateway.
docker compose up -d api oauth2-proxy
# Inspecionar campos selecionados; testar navegador conforme T06/T07.
docker compose --profile tools run --build --rm api-test
docker compose --profile tools run --rm --no-deps probe
docker compose stop oauth2-proxy keycloak api
```

Não assumir `--wait` funcional antes de criar health checks reais para os serviços novos. Manter procedimentos de espera limitados e reproduzíveis no runbook; não instalar curl apenas para mascarar essa ausência.

Parar preserva o volume de identidade. Não executar `down -v`, prune, remoção de realm ou exclusão de dados para repetir testes. Corrigir apenas o serviço/configuração envolvido, preservar o volume e pedir autorização se uma ação destrutiva se tornar realmente necessária. Alteração de client secret exige sincronização consciente no client e gateway, não recriar o realm.

## 5. Registro de execução

Preencher quando tarefas forem autorizadas e executadas; não registrar aprovação ou resultado presumido:

| Tarefa/critério | Data | Procedimento e responsável | Resultado real | Pendência/próxima ação |
| --- | --- | --- | --- | --- |
| Documentação inicial | 24/10/2026 | Inspeção dos arquivos e consulta de releases/docs oficiais | SPEC/PLAN propostos; runtime preservado | Revisar D01–D03 e iniciar T01 somente quando solicitado |

## 6. Checklist de conclusão

- [ ] D01–D03 resolvidas, com risco/limites aprovados ou desenho revisado.
- [ ] IA-01 a IA-12 comprovados, incluindo navegador e TOTP real fictício.
- [ ] Nenhuma porta da API publicada; interfaces novas somente loopback.
- [ ] Autenticação da visitante bem-sucedida e autorização negada pelo gateway.
- [ ] Sessão, logout e revogação explicados sem promessas de invalidação instantânea.
- [ ] Realm e MFA persistentes sem exclusão de volumes.
- [ ] Logs, templates, arquivos e evidências sem segredos.
- [ ] Regressão da Fundação aprovada e documentos consistentes.

Até cumprir o checklist, a entrega não está concluída. Aprovar um desenho não equivale a validar sua implementação.
