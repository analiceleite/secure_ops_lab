# SPEC 02 — Identidade e acesso

**Estado:** concluída em 25/10/2026. D01–D04 e política MFA/sessão aprovadas; IA-01–IA-12 consolidados na seção 19 das [evidências](../../evidence/02-identity-access.md), distinguindo testes técnicos e confirmações manuais da autora. Limites locais abaixo permanecem aplicáveis.

Referências: [README](../../../README.md), [arquitetura](../../architecture.md), [roadmap](../../roadmap.md) e [Fundação Local](../01-local-foundation/SPEC.md). Execução: [PLAN](PLAN.md).

## 1. Objetivo

Proteger a API fictícia por um gateway OIDC. Demonstrar no navegador que senha e TOTP autenticam uma identidade, enquanto a associação a um grupo específico autoriza o acesso. Uma visitante deve conseguir se autenticar com MFA, mas receber negação do gateway.

A Fundação Local e identidade estão concluídas. Keycloak e OAuth2 Proxy executam no overlay; login/MFA, autorização, sessão/logout, retomada e falhas foram validados nos limites registrados. A API não interpreta tokens e continua sem porta publicada; o controle está no gateway, não na aplicação. Estado real: [evidências](../../evidence/02-identity-access.md).

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

D01–D03 aprovadas pela autora com os limites abaixo. Alterações futuras exigem nova revisão; não trocar de topologia ou desabilitar validações silenciosamente.

| ID | Proposta | Justificativa e condição |
| --- | --- | --- |
| D01 | **Aprovada:** HTTP local, Keycloak `start-dev`, cookies sem `Secure` onde necessário | Evitar CA/certificados nesta PoC; somente contas fictícias, loopback e redes do lab. Exceção limitada pela seção 5 |
| D02 | **Aprovada, condicionada a testes:** `app.localhost` e `keycloak.localhost`, mesma URL do emissor por dentro e por fora | Separar hosts de cookies e usar alias DNS do Compose. Falha de resolução exige revisão, não alteração automática de hosts/DNS |
| D03 | **Aprovada:** Keycloak com banco embarcado `dev-file` em volume nomeado | Um único processo local. Volume sensível; não é produção, backup ou alta disponibilidade |
| D04 | **Aprovada na execução:** `identity` como bridge não interna | `internal: true` suprimiu o binding no Docker local. Somente Keycloak/gateway têm rota de saída; API continua apenas em `service` interna. Não comprova bloqueio de egress |

Alternativa a D01: HTTPS local com CA confiável no navegador e no gateway, mantendo validação de certificados. Exige revisar URLs, cookies, distribuição de confiança e passos manuais antes de implementar; não é uma segunda configuração incluída nesta entrega. Não usar certificados ignorados pelo cliente como alternativa.

### Versões implementadas

| Componente | Imagem fixada também por digest no overlay |
| --- | --- |
| Keycloak | `quay.io/keycloak/keycloak:26.8.1` |
| OAuth2 Proxy | `quay.io/oauth2-proxy/oauth2-proxy:v7.15.5` |
| API e ferramentas Node | Manter as versões da SPEC 01 |

Releases/documentação, manifesto `linux/amd64` e opções conferidos em 24/10/2026; fluxo real e harness isolado validados em 25/10. Digests/resultados nas evidências. Não usar `latest`; alterações de versão exigem nova validação.

## 4. Topologia e URLs

### Serviços, redes e persistência

Manter a Fundação em `compose.yaml` e adicionar a identidade em `compose.identity.yaml`, combinados com `docker compose -f compose.yaml -f compose.identity.yaml`. Isso evita exigir segredos de identidade nos comandos existentes da Fundação, sem mudar as fronteiras de rede.

| Serviço | Redes | Publicação proposta | Dados |
| --- | --- | --- | --- |
| `api` | Somente `service`, que permanece `internal: true` | Nenhuma | Sem volume |
| `oauth2-proxy` | `identity` e `service` | `127.0.0.1:4180:4180` | Sessão em cookie; sem Redis/volume |
| `keycloak` | Somente `identity`, bridge não interna (D04) | `127.0.0.1:8080:8080` | Volume nomeado `keycloak-data` em `/opt/keycloak/data` |
| `probe` / `api-test` | Manter configuração da Fundação | Nenhuma | Sem alteração |

A tentativa inicial de `identity` interna falhou: Keycloak iniciou, mas bindings observados ficaram vazios e o host recebeu conexão recusada. D04 autoriza bridge não interna apenas para `identity`, com nova validação de loopback. Não conectar a API a outra rede. Keycloak não participa de `service`; gateway não recebe privilégios de Docker. Não publicar porta de gestão/saúde do Keycloak, nem porta adicional para testes.

`keycloak.localhost` será alias de `keycloak` na rede `identity`. O gateway deve resolvê-lo para o container, não para seu próprio loopback. No navegador, os dois nomes devem resolver somente para loopback local. Validar também tentativas de IPv6: não criar listener em `[::]` por conveniência. Se a resolução falhar, registrar bloqueio; edição de `hosts`/DNS do sistema exige autorização específica.

### URLs canônicas — D01/D02 aprovadas e validadas no ambiente

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

Limites obrigatórios da exceção aprovada:

- Apenas computador pessoal, interfaces publicadas em `127.0.0.1`, redes do laboratório e contas exclusivas fictícias. Nenhum acesso por LAN, túnel ou sistema externo.
- Gateway com `cookie_secure=false` somente por HTTP; manter `HttpOnly=true`, `SameSite=Lax`, host-only, sem `Domain` compartilhado, path `/`. Não usar prefixos `__Secure-`/`__Host-` em cookie não seguro. Nome proposto: `secureops_session`.
- Keycloak em `start-dev`, hostname explícito e persistência dev-file. Se o realm exigir ajuste de política SSL para aceitar esse fluxo local, registrar o valor e a necessidade; somente após aprovação da exceção, nunca como correção implícita. Não alterar realm `master` ou outro sistema para contornar erro.
- A exceção abrange também os cookies emitidos pelo Keycloak por HTTP, cujos atributos reais serão inspecionados no navegador. Não prometer `Secure` em transporte não cifrado. A política SSL inicial do realm será `external` (padrão), sem alterá-la preventivamente. Se ela bloquear o tráfego interno ou o login, registrar bloqueio e solicitar aprovação do valor alternativo específico antes de aplicá-lo.
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
- O import deve preservar os scopes nativos do Keycloak, inclusive os necessários ao `account-console`, usando `attributes.CreateDefaultClientScopes="true"` (conferido no código da versão 26.8.1). Definir somente `groups` como scope customizado; uma lista parcial de scopes sem esse atributo suprime os defaults e pode quebrar a interface de conta após autenticação.
- O gateway tem `basic`, `profile` e `email` como scopes padrão do client e `groups` opcional solicitado explicitamente. `basic` fornece os claims básicos, inclusive `sub` no access token; não é uma permissão adicional. O `account-console` precisa de claims de roles para consultar a própria conta. Restaurar seus scopes não atribui roles administrativas aos usuários nem muda a autorização do gateway por grupo.
- Mapper Group Membership com claim `groups`, caminho completo e presença no ID token e no acesso/userinfo conforme suporte necessário do provider. Anexar client scope `groups` e solicitá-lo explicitamente.
- O **ID token** deve ter `aud` contendo `secureops-gateway`, atribuído pelo Keycloak ao client que iniciou o login. O gateway valida esse token (assinatura, issuer, audience, expiração e nonce). Não adicionar audiência extra aceita nem claim alternativo para contornar validação.
- Um audience mapper pode acrescentar `secureops-gateway` ao **access token**, sem alegar que isso comprova validação de audiência desse token pelo gateway. A API não recebe nem valida access tokens; este não é um desenho de resource server.
- Gateway usa provider `keycloak-oidc`, claim `groups` e **somente** `allowed-group=/secureops-operators`. Domínio de e-mail permitido: `lab.example`, não `*`; e-mail sozinho não autoriza.
- Claim ausente, vazia ou grupo semelhante (`/secureops-operators-extra`) não permite acesso. Não combinar roles/grupos por regras ambíguas nesta entrega.
- Grupo e e-mail são obtidos do fluxo validado, não de `X-Forwarded-*`, parâmetro de URL ou header enviado pelo usuário.

Não repassar access token ou ID token para API/resposta HTTP. A API continua sem dependência de identidade. Configuração de headers do gateway deve impedir que headers forjados constituam autorização; não se exige mudar o corpo da aplicação para mostrar quem fez login.

### MFA obrigatório

Exigir senha + TOTP para **ambas** as contas no fluxo do client. Proposta: fluxo Browser dedicado/clonado, com senha e OTP obrigatórios, sem alternativas de login só por senha, Cookie/SSO que contorne o fluxo, Kerberos, IdP externo ou OTP condicional a já existir credencial. Confirmar a composição na versão escolhida antes de configurá-la.

`CONFIGURE_TOTP` no primeiro acesso é uma etapa de cadastro, não prova suficiente de exigência de MFA. A conta não deve chegar à API antes de concluir o cadastro e apresentar código válido. Em autenticação nova, ausência/código incorreto deve impedir emissão de sessão utilizável pelo gateway. Sessão já válida no gateway não pede OTP a cada requisição.

Política definida no template: TOTP de 6 dígitos, período 30 s, `HmacSHA1`, janela de tolerância 1. Confirmar compatibilidade no cadastro manual com o autenticador da autora. Não ampliar tolerância para contornar relógio incorreto. Manter relógios sincronizados e documentar erros de horário.

Política aprovada: cada novo login OIDC **da aplicação** exige senha+TOTP, mesmo havendo sessão anterior do Keycloak. O override do client usa fluxo sem autenticador Cookie; não mudar globalmente o fluxo administrativo/de conta do Keycloak para conseguir esse efeito. Após expirar o cookie do gateway, o novo login deve repetir ambos os fatores. O cadastro inicial valida o código da nova credencial antes de concluir; não basta marcar a required action como concluída.

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

A tabela abaixo define o contrato de aceite. Resultados executados, origem manual/automática e limitações estão na seção 19 das [evidências](../../evidence/02-identity-access.md); a tabela sozinha não é evidência.

| ID | Critério | Evidência exigida |
| --- | --- | --- |
| IA-01 | Preparação e exceções revisadas | Aprovação explícita de D01–D04; versões/digests/opções e portas conferidos |
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

Testes de grupo usam apenas contas fictícias e restauração pontual. Para audiência, definir um teste isolado do verificador da versão do gateway com ID token de assinatura válida e audiência divergente, com controle positivo equivalente; não apontar o gateway principal para um IdP falso. Se o harness oficial/local não estiver disponível, IA-08 permanece parcial/bloqueado até uma estratégia reproduzível ser aprovada. Trocar client ID/secret e obter erro na troca do código **não** comprova rejeição por audiência. Remover audience mapper do access token também não testa a audiência do ID token. Um bearer token rejeitado num modo que não aceita bearer não comprova validação criptográfica.

Estratégia implementada em 25/10 para esse teste: [verificador isolado](../../../scripts/Test-IdentityVerifier.ps1), com mesma imagem do proxy e cópia da configuração, substituindo somente endereços e segredos de teste. Dois containers em rede interna sem publicação, emissor/identidade/upstream fictícios e chaves em memória. Testa o fluxo code+PKCE e ID token válido com audience divergente sem alterar o issuer do gateway principal. Casos adicionais de grupos/cookie/state complementam, não substituem, testes reais de contas e navegador. Resultados e limites na seção 18 das evidências.

## 11. Evidências e saída

Registrar em [evidências](../../evidence/02-identity-access.md) somente o que foi executado, com ID, data/fuso, versão, procedimento, resultado observado e limitações. Testes de containers não substituem cadastro TOTP, atributos de cookies e login no navegador. Capturas são opcionais; nunca incluir telas de QR/OTP, cookies ou URLs com `code`, state, session IDs e tokens.

Concluir somente após IA-01 a IA-12 verificados. Falta de navegador/autenticador, decisões não aprovadas ou impossibilidade de validar um cenário mantém a tarefa correspondente pendente/bloqueada. Não preencher resultados esperados como se tivessem sido observados.

## 12. Fontes consultadas e pendências

Fontes de configuração (resultados de runtime separados nas evidências):

- [Release Keycloak 26.8.1](https://github.com/keycloak/keycloak/releases/tag/26.8.1), [hostname v2](https://www.keycloak.org/server/hostname), [containers e dev mode](https://www.keycloak.org/server/containers), [administração e fluxos](https://www.keycloak.org/docs/latest/server_admin/index.html).
- [Release OAuth2 Proxy v7.15.5](https://github.com/oauth2-proxy/oauth2-proxy/releases/tag/v7.15.5), [provider Keycloak OIDC](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/keycloak_oidc/).
- Documentação no tag do proxy: [opções](https://github.com/oauth2-proxy/oauth2-proxy/blob/v7.15.5/docs/versioned_docs/version-7.15.x/configuration/overview.md) e [endpoints/logout](https://github.com/oauth2-proxy/oauth2-proxy/blob/v7.15.5/docs/versioned_docs/version-7.15.x/features/endpoints.md).

Documentação online pode mudar. Atenção: a documentação consultada indica default permissivo para `insecure-oidc-skip-nonce`; na implementação, configurar explicitamente a **verificação de nonce habilitada** e conferir na versão, sem confiar no default.

Fechamento em 25/10: testes de navegador executados e confirmados pela autora, inspeções técnicas/rede pelo agente e casos criptográficos no proxy real isolado. Tempo de sessão/revogação aproximado e relatado, não medição automática; atributos da sessão do gateway relatados, cookies de pré-login Keycloak observados em Chrome headless. Cookies autenticados do Keycloak não inspecionados pelo agente. Sem coleta de segredos ou alegação de segurança de produção. Detalhes na matriz final de evidências.
