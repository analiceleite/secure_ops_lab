# SPEC 02 — Identidade e acesso

**Estado:** em especificação; proposta para revisão. Nenhum serviço de identidade implementado ou teste de autenticação executado. As exceções abaixo **não estão aprovadas** por terem sido descritas neste documento.

Referências: [README](../../../README.md), [arquitetura](../../architecture.md), [roadmap](../../roadmap.md) e [Fundação Local](../01-local-foundation/SPEC.md). Execução: [PLAN](PLAN.md).

## 1. Objetivo

Proteger a API fictícia por um gateway OIDC. Demonstrar no navegador que senha e TOTP autenticam uma identidade, enquanto a associação a um grupo específico autoriza o acesso. Uma visitante deve conseguir se autenticar com MFA, mas receber negação do gateway.

Somente a Fundação Local está implementada: `api`, `probe`, `api-test` e rede `service` interna em `compose.yaml`. A API não interpreta tokens e continuará sem porta publicada. Esta entrega acrescentará a proteção no gateway, não na aplicação.

## 2. Escopo e limites

Incluído:

- Keycloak local, realm exclusivo, client confidencial, duas contas fictícias e MFA TOTP obrigatório.
- OAuth2 Proxy como reverse proxy, validação OIDC e autorização por grupo.
- Endereçamento consistente entre navegador e containers; exposição somente em loopback.
- Persistência local do Keycloak; geração/armazenamento local de segredos fora do versionamento.
- Sessões curtas, logout documentado, testes de negação e evidências sanitizadas.
- Preservação do contrato e das validações da Fundação Local.

Não incluído: monitoramento, n8n, incidentes, WAF, certificados públicos, domínio comprado, provedor externo, login social, e-mail transacional, recuperação de conta automatizada, gestão de dispositivo, autorização por recurso na API ou SSO entre múltiplas aplicações. Não adicionar Redis, banco externo ou um terceiro proxy apenas por antecipação.

O controle de usuário é o gateway. Containers deliberadamente conectados à rede `service`, como o probe e o futuro monitor, continuam podendo consultar a API diretamente. Isso é uma fronteira de confiança do laboratório, não um bypass público nem isolamento contra o administrador do Docker.

## 3. Decisões propostas e gate de aprovação

Antes de implementar, revisar explicitamente as decisões D01 a D03. Se forem rejeitadas, atualizar esta SPEC e o PLAN; não trocar de topologia ou desabilitar validações silenciosamente.

| ID | Proposta | Justificativa e condição |
| --- | --- | --- |
| D01 | HTTP local, Keycloak `start-dev`, cookies do gateway sem `Secure` | Evitar CA/certificados e ferramentas adicionais nesta PoC. Exceção limitada descrita na seção 5; exige aprovação explícita antes de aplicar |
| D02 | Nomes `app.localhost` e `keycloak.localhost`, mesma URL do emissor por dentro e por fora | Separar hosts de cookies e usar alias DNS do Compose. Resolução em loopback no navegador precisa ser verificada; não pressupor suporte uniforme no Windows |
| D03 | Keycloak com banco embarcado `dev-file` em volume nomeado | Um único processo local e sem necessidade de banco adicional. Estado sensível persiste; não é configuração de produção, backup ou alta disponibilidade |

Alternativa a D01: HTTPS local com CA confiável no navegador e no gateway, mantendo validação de certificados. Exige revisar URLs, cookies, distribuição de confiança e passos manuais antes de implementar; não é uma segunda configuração incluída nesta entrega. Não usar certificados ignorados pelo cliente como alternativa.

### Versões candidatas

| Componente | Imagem candidata |
| --- | --- |
| Keycloak | `quay.io/keycloak/keycloak:26.8.1` |
| OAuth2 Proxy | `quay.io/oauth2-proxy/oauth2-proxy:v7.15.5` |
| API e ferramentas Node | Manter as versões da SPEC 01 |

Releases oficiais e documentação foram consultadas em 24/10/2026. Tags, manifesto `linux/amd64`, digest, opções e compatibilidade conjunta ainda deverão ser conferidos na preparação. Não houve pull ou execução nesta etapa documental; release existente não comprova imagem disponível nem segurança da combinação. Não usar `latest`.

## 4. Topologia e URLs

### Serviços, redes e persistência

| Serviço | Redes | Publicação proposta | Dados |
| --- | --- | --- | --- |
| `api` | Somente `service`, que permanece `internal: true` | Nenhuma | Sem volume |
| `oauth2-proxy` | `identity` e `service` | `127.0.0.1:4180:4180` | Sessão em cookie; sem Redis/volume |
| `keycloak` | Somente `identity`, proposta `internal: true` | `127.0.0.1:8080:8080` | Volume nomeado `keycloak-data` em `/opt/keycloak/data` |
| `probe` / `api-test` | Manter configuração da Fundação | Nenhuma | Sem alteração |

Confirmar publicação loopback funcionando com rede interna na versão local do Docker. Não conectar a API a outra rede para resolver falhas de identidade. Keycloak não participa de `service`; gateway não recebe privilégios de Docker. Não publicar porta de gestão/saúde do Keycloak, nem porta adicional para testes.

`keycloak.localhost` será alias de `keycloak` na rede `identity`. O gateway deve resolvê-lo para o container, não para seu próprio loopback. No navegador, os dois nomes devem resolver somente para loopback local. Validar também tentativas de IPv6: não criar listener em `[::]` por conveniência. Se a resolução falhar, registrar bloqueio; edição de `hosts`/DNS do sistema exige autorização específica.

### URLs canônicas — condicionadas à aprovação de D01/D02

| Uso | Valor |
| --- | --- |
| Aplicação via gateway | `http://app.localhost:4180/` |
| Keycloak, login e administração local | `http://keycloak.localhost:8080/` |
| Realm | `secureops-lab` |
| Emissor OIDC | `http://keycloak.localhost:8080/realms/secureops-lab` |
| Discovery | Emissor + `/.well-known/openid-configuration` |
| Client ID | `secureops-gateway` |
| Única redirect URI do client | `http://app.localhost:4180/oauth2/callback` |
| Upstream do gateway | `http://api:3000/` |
| Pós-logout local | `/oauth2/sign_in` no gateway |

Configurar o hostname completo do Keycloak, sem depender de cabeçalhos `Host` para gerar o emissor; backchannel dinâmico não é necessário. O `issuer` do discovery e o `iss` do token devem corresponder exatamente ao valor acima. Endpoints anunciados devem ser acessíveis ao gateway pela rede `identity` e ao navegador onde pertinente.

Não usar `localhost:8080` como emissor no gateway, sobrescrever endpoints ao acaso, permitir redirects com `*`, liberar CORS global ou desligar verificação de emissor. O fluxo é server-side; não requer um SPA nem CORS para a API. Restringir origens do client à origem exata quando necessárias; não cadastrar origens extras sem motivo.

## 5. Exceções de transporte e desenvolvimento (D01)

Esta proposta **amplia** a exceção de HTTP da Fundação: agora transitariam senhas fictícias, códigos TOTP, códigos OIDC e cookies. Ela não é coberta automaticamente pela aprovação anterior de HTTP para respostas sem credenciais.

Limites obrigatórios caso aprovada:

- Apenas computador pessoal, interfaces publicadas em `127.0.0.1`, redes do laboratório e contas exclusivas fictícias. Nenhum acesso por LAN, túnel ou sistema externo.
- Gateway com `cookie_secure=false` somente por HTTP; manter `HttpOnly=true`, `SameSite=Lax`, host-only, sem `Domain` compartilhado, path `/`. Não usar prefixos `__Secure-`/`__Host-` em cookie não seguro. Nome proposto: `secureops_session`.
- Keycloak em `start-dev`, hostname explícito e persistência dev-file. Se o realm exigir ajuste de política SSL para aceitar esse fluxo local, registrar o valor e a necessidade; somente após aprovação da exceção, nunca como correção implícita. Não alterar realm `master` ou outro sistema para contornar erro.
- Sem `ssl-insecure-skip-verify`, `insecure-oidc-skip-issuer-verification`, bypass de assinatura/audience, e-mail não verificado ou nonce. A proposta é HTTP explícito, não ignorar falhas de TLS/OIDC.
- Validar configuração resolvida **e bindings observados**, atributos dos cookies no navegador e comportamento de login/negação antes de aceitar a exceção como funcional.

Risco residual: tráfego não cifrado e cookies sem proteção de transporte. TOTP não elimina captura/roubo de sessão por quem controla host, navegador ou rede Docker. Tratamento especial de `.localhost` pelo navegador não transforma HTTP em TLS. Não exportar esta configuração como pronta para produção.

## 6. Identidades, client e MFA

### Contas e grupos

| Identidade | E-mail fictício | Grupo de aplicação | Resultado esperado |
| --- | --- | --- | --- |
| `operadora` | `operadora@lab.example` | `/secureops-operators` | Senha + TOTP e acesso à API |
| `visitante` | `visitante@lab.example` | Nenhum grupo permitido | Senha + TOTP e negação no gateway |

E-mails provisionados localmente como verificados, pois não existe integração de correio; isso não comprova posse de uma caixa postal. Não permitir cadastro público. Administradora de bootstrap separada das contas da aplicação, somente no ambiente local, sem permissão de aplicação por padrão. Não usar o realm `master` para login da aplicação.

Client confidencial com autenticação de client habilitada, Authorization Code (Standard Flow) e PKCE `S256`. Desabilitar implicit flow, Direct Access Grants e service accounts; não implementar autenticação por senha enviada à API nem aceitar bearer tokens como caminho alternativo ao navegador.

### Claims e autorização

- Escopos explícitos: `openid profile email groups`; não pedir `offline_access`.
- Mapper Group Membership com claim `groups`, caminho completo e presença no ID token e no acesso/userinfo conforme suporte necessário do provider. Anexar client scope `groups` e solicitá-lo explicitamente.
- Audience mapper inclui `secureops-gateway` no ID token e access token. Validar `aud` contra o client; não usar audiência genérica para fazer login passar.
- Gateway usa provider `keycloak-oidc`, claim `groups` e **somente** `allowed-group=/secureops-operators`. Domínio de e-mail permitido: `lab.example`, não `*`; e-mail sozinho não autoriza.
- Claim ausente, vazia ou grupo semelhante (`/secureops-operators-extra`) não permite acesso. Não combinar roles/grupos por regras ambíguas nesta entrega.
- Grupo e e-mail são obtidos do fluxo validado, não de `X-Forwarded-*`, parâmetro de URL ou header enviado pelo usuário.

Não repassar access token ou ID token para API/resposta HTTP. A API continua sem dependência de identidade. Configuração de headers do gateway deve impedir que headers forjados constituam autorização; não se exige mudar o corpo da aplicação para mostrar quem fez login.

### MFA obrigatório

Exigir senha + TOTP para **ambas** as contas no fluxo do client. Proposta: fluxo Browser dedicado/clonado, com senha e OTP obrigatórios, sem alternativas de login só por senha, Cookie/SSO que contorne o fluxo, Kerberos, IdP externo ou OTP condicional a já existir credencial. Confirmar a composição na versão escolhida antes de configurá-la.

`CONFIGURE_TOTP` no primeiro acesso é uma etapa de cadastro, não prova suficiente de exigência de MFA. A conta não deve chegar à API antes de concluir o cadastro e apresentar código válido. Em autenticação nova, ausência/código incorreto deve impedir emissão de sessão utilizável pelo gateway. Sessão já válida no gateway não pede OTP a cada requisição.

Política proposta: TOTP de 6 dígitos, período 30 s, algoritmo suportado pelo aplicativo autenticador e pela política padrão da versão; registrar algoritmo e janela efetivamente escolhidos na preparação. Não ampliar tolerância para contornar relógio incorreto. Manter relógios sincronizados e documentar erros de horário.

Cadastro será manual pela autora, com autenticador gratuito preferencialmente local/offline, sem serviço externo obrigatório. Nunca capturar/commitar QR code, semente, código TOTP ou senha. Fluxo manual pendente mantém a validação dependente correspondente pendente, não autoriza desabilitar MFA. Não considerar teste automatizado de senha como substituto do login TOTP no navegador.

## 7. Sessões, logout e falhas

Proposta inicial para demonstração curta:

- Gateway: cookie com validade absoluta de **5 minutos**, `cookie_refresh=0`, sem renovação periódica. Verificar comportamento efetivo; não permitir sessão deslizante além do limite sem revisar este contrato.
- Keycloak: access token 5 min; SSO idle 10 min e max 15 min; Remember Me desabilitado. Esses tempos não significam revogação instantânea do cookie do gateway.
- Cookie inválido, adulterado ou expirado exige nova autenticação e nunca libera a API. Corromper cookie de teste apenas na sessão fictícia local; não armazenar seu conteúdo em evidências.
- Remover grupo/bloquear conta/encerrar sessão no Keycloak pode não invalidar imediatamente cookie já emitido pelo gateway. Limite aceito proposto: no máximo a validade restante de 5 min, sem refresh. Novo login deve refletir a remoção/bloqueio. Medir e registrar, não presumir revalidação em toda requisição.

Logout é **de duas camadas**, sem promessa de single logout:

1. `/oauth2/sign_out?rd=/oauth2/sign_in` limpa o cookie do gateway e retorna a uma página local sem acesso à API. `/oauth2/sign_in` também pode limpar cookies conforme comportamento documentado da versão.
2. Encerrar explicitamente a sessão no Keycloak por sua interface de conta (`/realms/secureops-lab/account/`) ou administração local. Confirmar em seguida que uma autenticação nova pede senha e TOTP.

Não prometer que limpar só o cookie do gateway encerra a sessão do provedor. Não incluir `id_token_hint`/tokens em URLs de evidências nem implementar redirects de logout arbitrários. Redirecionamentos de retorno do gateway ficam restritos à própria origem/caminhos locais; não usar whitelist de subdomínios amplos.

Falhas devem negar acesso: Keycloak indisponível impede novo login (sessão gateway já válida pode funcionar até expirar); falha de callback/state/nonce ou troca de código não produz sessão; API parada causa erro de upstream, não conteúdo fictício de sucesso. Gateway nunca faz fallback público para API.

## 8. Rotas e observabilidade

- `/` e `/health` da API ficam protegidos quando acessados pelo gateway; sem `skip-auth-route`, `skip-auth-regex` ou preflight liberado para upstream.
- Sem sessão: `/` apresenta início de login ou redirecionamento para autenticação; nunca retorna o JSON da API. `/oauth2/auth` deve retornar 401 sem sessão e sucesso somente para sessão autorizada.
- Visitante após autenticação e MFA: negação explícita do gateway, esperada como HTTP 403 no fluxo, sem resposta upstream. Operadora: HTTP 200 e JSON original da API.
- Rotas técnicas próprias `/oauth2/*` e saúde do gateway (por exemplo `/ping`/`/ready`, a conferir na versão) podem ser públicas apenas como funções do gateway; não confundir essas respostas com liberação de `/health` da API.
- Desabilitar logs HTTP de requisição que incluam query string de callback/código OIDC; evitar debug e logs de autenticação que registrem dados desnecessários. Confirmar saída real de erros antes de coletar evidências.
- Nunca registrar cookies, Authorization, senha, TOTP, client secret, tokens ou dumps de ambiente. Rotação local explícita de logs como na Fundação.

## 9. Segredos, bootstrap e persistência

- Segredos reais serão gerados localmente: senha de bootstrap, senhas de teste, client secret e chave de cookie aleatória compatível com a versão. Não reutilizar exemplos do fornecedor.
- `.env.example` futuro contém apenas placeholders não funcionais. Arquivos reais `.env`/config sensível ficam ignorados, com acesso local restrito. Não imprimir `docker compose config`, inspect completo ou comandos com valores secretos em evidências.
- Templates de realm/config versionados não contêm credenciais, usuários com senha, OTP, chaves privadas ou client secrets. Segredos são injetados localmente; validar substituições na versão usada, sem presumir suporte em qualquer campo JSON.
- Preferir template sem usuários + provisionamento local documentado por console para duas contas. Passos manuais inevitáveis devem ser detalhados e repetíveis. Não criar scripts administrativos permanentes ou endpoints públicos de bootstrap.
- Volume `keycloak-data` persiste realm, usuários, MFA e chaves privadas de assinatura: **é dado sensível**. Não exportar ou copiar seu conteúdo para o repositório. Não existe volume para o gateway; chave de cookie deve continuar estável entre reinícios, fora da imagem.
- Reinício deve preservar realm/client/grupo e credencial OTP; demonstrar que o login continua funcionando. Import de startup não deve sobrescrever realm existente; atualizar conscientemente sem apagar volume. Não usar reset para refazer bootstrap.
- Conferir usuário efetivo não root, redes/mounts necessários e ausência de privileged/socket/host network nos novos serviços. Registrar limites de memória do Keycloak (valor inicial candidato 1 GiB, sujeito a medição) e prazos finitos de prontidão, sem tratar isso como requisito mínimo comprovado.

## 10. Critérios de aceite

Todos permanecem **não executados** nesta fase documental.

| ID | Critério | Evidência exigida |
| --- | --- | --- |
| IA-01 | Preparação e exceções revisadas | Aprovação explícita de D01–D03 ou SPEC revisada; versões/digests/opções e portas conferidos |
| IA-02 | Endereçamento OIDC coerente | Resolução no host/navegador e gateway; discovery com issuer exato e endpoints acessíveis; nenhuma verificação desligada |
| IA-03 | Exposição mínima preservada | Compose sanitizado + bindings observados em loopback somente; API sem publicação e somente em `service`; usuário e mounts inspecionados |
| IA-04 | Sem sessão não chega à aplicação | `/` e `/health` pelo gateway não retornam JSON da API; `/oauth2/auth` retorna 401; headers de identidade forjados não liberam |
| IA-05 | MFA realmente obrigatório | Cadastro manual e nova autenticação das duas contas; senha sozinha/OTP incorreto não liberam; senha+OTP válido concluem autenticação |
| IA-06 | Operadora autorizada | Login válido + grupo exato resulta em `/` 200 e JSON original; `/health` autorizado preserva contrato |
| IA-07 | Autenticação não basta | Visitante autenticada com MFA recebe negação do gateway; grupo ausente/vazio/semelhante não permite; prova separada de sucesso no IdP e negação de aplicação |
| IA-08 | Sessão/callback inválido falha fechado | Cookie adulterado, callback sem state válido e audience incompatível em cenário local controlado não liberam; configuração mantém assinatura, issuer, nonce e audience validados |
| IA-09 | Expiração e revogação limitadas conhecidas | Medição do cookie de 5 min sem renovação; remoção de grupo/bloqueio nega login novo e acesso antigo cessa até o limite aceito |
| IA-10 | Logout fiel ao escopo | Cookie do gateway removido; distinguir sessão Keycloak remanescente; encerramento das duas camadas seguido de nova exigência de senha+TOTP |
| IA-11 | Persistência e falhas previsíveis | Reinício sem remover volume preserva configuração/MFA; Keycloak parado bloqueia login novo; API parada não produz sucesso e recuperação restaura acesso |
| IA-12 | Regressão e documentação | 35 testes da Fundação e probe interno aprovados, sem abrir porta; procedimentos repetidos e evidências sem segredos |

Testes de audience/grupo usam apenas o client e contas fictícios, com registro/restauração pontual da configuração; nunca desabilitam a verificação para passar. Um bearer token rejeitado em um modo que não aceita bearer não comprova validação criptográfica; não fazer essa alegação.

## 11. Evidências e saída

Criar `docs/evidence/02-identity-access.md` somente quando houver execução. Registrar ID, data/fuso, versão, procedimento, resultado observado e limitações. Testes de containers não substituem cadastro TOTP, atributos de cookies e login no navegador. Capturas são opcionais; nunca incluir telas de QR/OTP, cookies ou URLs com `code`, state, session IDs e tokens.

Concluir somente após IA-01 a IA-12 verificados. Falta de navegador/autenticador, decisões não aprovadas ou impossibilidade de validar um cenário mantém a tarefa correspondente pendente/bloqueada. Não preencher resultados esperados como se tivessem sido observados.

## 12. Fontes consultadas e pendências

Consultas documentais, sem validação de runtime:

- [Release Keycloak 26.8.1](https://github.com/keycloak/keycloak/releases/tag/26.8.1), [hostname v2](https://www.keycloak.org/server/hostname), [containers e dev mode](https://www.keycloak.org/server/containers), [administração e fluxos](https://www.keycloak.org/docs/latest/server_admin/index.html).
- [Release OAuth2 Proxy v7.15.5](https://github.com/oauth2-proxy/oauth2-proxy/releases/tag/v7.15.5), [provider Keycloak OIDC](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/keycloak_oidc/).
- Documentação no tag do proxy: [opções](https://github.com/oauth2-proxy/oauth2-proxy/blob/v7.15.5/docs/versioned_docs/version-7.15.x/configuration/overview.md) e [endpoints/logout](https://github.com/oauth2-proxy/oauth2-proxy/blob/v7.15.5/docs/versioned_docs/version-7.15.x/features/endpoints.md).

Documentação online pode mudar. Atenção: a documentação consultada indica default permissivo para `insecure-oidc-skip-nonce`; na implementação, configurar explicitamente a **verificação de nonce habilitada** e conferir na versão, sem confiar no default.

Pendências de revisão: aprovar/rejeitar D01–D03, confirmar nomes/portas no ambiente e disponibilidade de autenticador/navegador. Até lá, estado **em especificação**, não pronta para implementar.
