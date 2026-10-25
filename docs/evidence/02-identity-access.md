# Evidências 02 — Identidade e acesso (parcial)

**Coleta:** 24/10/2026, aproximadamente 23:34–23:50, `-03:00` (logs de containers em UTC já indicam 25/10). Execução técnica pelo agente, não reprodução independente pela autora. D01–D03, política MFA/sessão e implementação aprovadas pela autora em conversa; D04 aprovada após falha real de rede.

## 1. Ambiente e imagens

- Docker Engine `28.5.1`, Linux `amd64`; Compose `v2.40.2-desktop.1`.
- Manifestos oficiais conferidos, imagens baixadas e opções consultadas com `--help` na própria versão, sem rede nos containers de consulta.

| Imagem | Digest do índice fixado no Compose | Manifesto linux/amd64 |
| --- | --- | --- |
| `quay.io/keycloak/keycloak:26.8.1` | `sha256:a78d6b79572168cb25886b80a8b5b8d4ed4390743e3eecb810538683e209dd6b` | `sha256:3e1ac632e743660017b1e6bb4c3ffc800fd02c82cdd0db858cd03456a98a8dfc` |
| `quay.io/oauth2-proxy/oauth2-proxy:v7.15.5` | `sha256:8498b0d0ef0a7b29686414000a08aee467f02d0299c9ed1e006a8f33fc017916` | `sha256:0d989b27d90d5e527fb2b045d864c4001c3104bdd763b3211b7e9ba2110380ea` |

Isso comprova disponibilidade das imagens/arquitetura, não auditoria de vulnerabilidades ou compatibilidade do fluxo de autenticação completo.

## 2. Preparação e segredos (T01/T02)

- Nenhum listener nas portas 4180/8080 antes de iniciar a identidade.
- `Resolve-DnsName` retornou NXDOMAIN para ambos os nomes `.localhost` no Windows. Chrome headless, em perfil temporário separado, acessou `app.localhost` e `keycloak.localhost` contra um listener de teste ligado **somente a `127.0.0.1:4180`**. Listener encerrado ao fim do teste; nenhum hosts/DNS/firewall alterado. Primeiro ensaio não capturou corretamente a saída do processo GUI; repetição com `Start-Process`, espera e redirecionamento explícitos confirmou ambos os nomes.
- `Initialize-Identity.ps1` criou os segredos sem exibir valores, com ACL protegida e apenas o SID atual com FullControl. `git check-ignore` confirmou os três arquivos ignorados. Segunda execução recusou pasta existente; comparação de hashes em memória confirmou ausência de alteração (hashes de segredos não publicados).
- `docker compose config --quiet` e a combinação com `compose.identity.yaml` foram aceitos. O contexto restrito de build da API permanece sem arquivos de identidade/segredos.
- Correção de compatibilidade: primeiro `--config-test` rejeitou o cookie secret em arquivo de 44 bytes base64. O código da versão (`pkg/apis/options/cookie.go`, `GetSecret`) lê o arquivo como bytes, sem decodificar. Corrigido inicializador para 32 bytes binários brutos e convertido **apenas o arquivo recém-gerado nesta execução** aos 32 bytes aleatórios originais. Nenhuma sessão de gateway havia sido criada. Nova validação retornou `configuration is valid`.
- Fonte de substituição `${SECUREOPS_CLIENT_SECRET}` no import: [guia oficial](https://www.keycloak.org/server/importExport), seção de environment variables; nenhum JSON renderizado com segredo foi versionado.

## 3. Falha real de rede e D04

Primeira tentativa com `identity.internal: true`:

- Keycloak iniciou e importou o realm; não houve OOM.
- Discovery no host não ficou disponível no prazo de 120 s; `curl` observou conexão recusada.
- Binding observado em `NetworkSettings.Ports`: `{"8080/tcp":[]}`, apesar de `ports` configurado no Compose.
- A autora aprovou explicitamente mudar **somente `identity`** para bridge não interna, mantendo loopback e `service` interna.
- Foram parados/removidos apenas o container Keycloak e a rede criados nesta etapa, recriados com a configuração aprovada. **Volume preservado**; nenhum `down -v`, prune ou exclusão de realm/dados.

Após correção, binding observado:

```text
8080/tcp -> HostIp=127.0.0.1, HostPort=8080
identity internal=false
service internal=true
```

`Get-NetTCPConnection` confirmou listener **127.0.0.1:8080**; nenhum listener 4180 nesta etapa. Não foi feito teste a partir de outra máquina/LAN, nem teste de egress externo. A rede de identidade agora permite rota de saída; não afirmar bloqueio de egress ou isolamento absoluto.

## 4. Keycloak e metadados (T03)

- Discovery do host com URL canônica e `curl --resolve` explícito: HTTP 200, issuer exato `http://keycloak.localhost:8080/realms/secureops-lab` e endpoints na mesma origem. Isso não comprova resolução pelo DNS Windows.
- Espera após recriação com bridge normal: **23209 ms** nesta verificação. Espera após reinício posterior: **11252 ms**. São tempos do procedimento de espera, não benchmark de boot nem SLA.
- Cliente Node temporário na rede `identity`, reutilizando imagem da API, sem porta e sem credenciais:

```json
{"check":"identity_discovery","dns":["172.21.0.2"],"discovery":200,"issuer":"exact_match","jwks":200,"token_without_secret":401}
```

IP é transitório, não deve ser fixado. Token endpoint sem secret retornou HTTP 401/`unauthorized_client`, sem emissão de token. O teste inicialmente esperava `invalid_client`, falhou e foi corrigido para o resultado real da versão, mantendo exigência de HTTP 401. Isso não testa audiência, MFA nem autorização.

- Chrome headless acessou a URL OIDC canônica do client com PKCE/scopes e encontrou formulário de usuário, sem autenticar ou seguir callback. Nenhuma senha, QR ou token foi introduzido/coletado. Não substitui navegador interativo.
- Ensaio headless de `/account/` excedeu 20 s e foi interrompido. Consulta HTTP independente do endpoint de autorização do `account-console` retornou 200 e formulário de usuário, sem erro inesperado. Navegação interativa e cadastro nessa interface permanecem pendentes.

### Correção pontual de scopes sem apagar realm

O primeiro import definiu `groups`, mas o Keycloak não criou implicitamente `profile`/`email`; log indicou referências inexistentes. O template foi corrigido para definir os três scopes explicitamente, incluindo `email_verified` booleano.

Como import de startup usa `IGNORE_EXISTING`, reiniciar não aplicaria a correção ao realm existente. Um cliente Node administrativo **temporário**, usando somente a rede do lab e bootstrap local, criou apenas os dois scopes ausentes e suas associações ao client; não sobrescreveu realm, client ou contas. Tokens ficaram apenas em memória; arquivo temporário do procedimento foi removido. Não se adicionou script administrativo permanente ao projeto.

Leitura administrativa na mesma execução confirmou:

```text
profile/email criados e associados pontualmente
sslRequired=external (sem redução de política SSL)
override do client -> secureops-browser-mfa
auth-username-password-form REQUIRED
auth-otp-form REQUIRED
contas de aplicação existentes: 0
```

O realm permaneceu disponível após reinício com volume preservado. Persistência de usuários/OTP ainda **não** foi testada, pois não foram cadastrados.

### Execução e privilégios observados

```text
Keycloak: user da imagem=1000; UID efetivo=1000; GID efetivo=0
CapEff=0000000000000000; NoNewPrivs=1; privileged=false
mem_limit=1073741824 bytes
snapshot de consumo=545.1 MiB / 1 GiB, CPU=0.46%
mounts: volume /opt/keycloak/data rw; template de import bind read-only
```

GID 0 é o padrão da imagem e não foi apresentado como grupo não root. Não há socket Docker, host network ou porta de gestão publicada. Snapshot não representa pico, requisito mínimo ou dimensionamento completo.

## 5. Configuração do gateway e regressão

- Gateway **não iniciado como serviço**; somente container temporário `--config-test`, removido ao terminar. Usuário declarado pela imagem: `65532`; usuário/capacidades efetivos em runtime ainda pendentes.
- Resultado final de `--config-test`: `configuration is valid`. Não realiza login, prova de grupo, inspeção de cookies ou teste de disponibilidade do IdP/upstream.
- **9 testes estáticos**, 9 aprovados/0 falhas, via Node da imagem da API, `network_mode=none`, mount read-only: **195.825564 ms**. Antes de incluir a regressão de scopes, passaram 8 verificações; relatório final usa a suite de 9.
- **35 testes da API**, 35 aprovados/0 falhas, via Compose: **5959.377421 ms**.
- API iniciada para regressão, saudável, probe interno retornou `probe_succeeded`; inspect confirmou bindings `{}`, apenas `service`, zero mounts e user `node`. API parada novamente com sucesso, sem remover container/dados.
- Aviso de órfão ao usar somente o Compose base refere-se ao Keycloak do overlay; não foi usado `--remove-orphans`.
- Revisão final: comparação seletiva do Compose resolvido confirmou serviço `api` idêntico à base, redes esperadas e duas publicações projetadas exclusivamente em loopback. 53 destinos de links locais existentes (âncoras não verificadas), `git diff --check` sem erros de whitespace e varredura de 33 arquivos versionados/versionáveis sem correspondências aos segredos locais ou padrões selecionados de chaves/tokens. A varredura automatizada é limitada, não uma garantia universal de ausência de segredos.

## 6. Estado dos critérios e próximos testes

| Critério | Estado real |
| --- | --- |
| IA-01 | Aprovações e preparação realizadas; D04 acrescentada com autorização |
| IA-02 | Discovery/DNS interno/issuer/JWKS e formulário inicial da aplicação verificados; integração efetiva gateway/IdP ainda pendente |
| IA-03 | API e Keycloak inspecionados; gateway runtime e cookies pendentes |
| IA-04 a IA-10 | Pendentes: nenhum login das contas, TOTP, negação pelo gateway, sessão, audiência ou logout foi validado |
| IA-11 | Realm disponível após reinício; persistência de usuários/OTP e falhas do caminho completo pendentes |
| IA-12 | Regressão API/probe realizada e documentação parcial escrita; reprodução manual completa pendente |

Estado ao fim da coleta de 24/10: **Keycloak em execução somente em 127.0.0.1:8080; API parada (`exited`/0); gateway não iniciado; volume e segredos preservados**. Naquele momento, próxima ação era criar as contas conforme [runbook](../runbooks/identity-access.md). O progresso posterior está registrado abaixo, sem substituir o histórico.

## 7. Correção da interface de conta após cadastro OTP — 25/10/2026

**Contexto:** autora criou as contas e relatou `Unexpected error` ao cadastrar OTP da operadora; na tentativa seguinte, foi solicitado somente o código, mas a interface voltou a falhar. Autora autorizou explicitamente correção pontual sem recriar realm nem apagar dados. Execução técnica aproximadamente 00:14–00:17 (`-03:00`); logs UTC em 25/10.

### Diagnóstico confirmado e limites

- Leitura administrativa local confirmou `operadora` habilitada com credenciais `password` e `otp`, sem required action; `visitante` habilitada com `password` e `CONFIGURE_TOTP` pendente. **Credencial OTP presente não prova que um login novo com MFA funcionou.** Nenhum segredo OTP foi consultado/exportado e nenhum código foi solicitado à autora.
- `account-console` não tinha nenhum default client scope; realm tinha `groups`, `profile`, `email` e `offline_access`, mas não `basic`/`roles`.
- A lista customizada de scopes do template suprimia a criação dos defaults nativos. A correção anterior que acrescentava apenas `profile`/`email` era insuficiente para os clients internos do Keycloak.
- Código oficial 26.8.1: [RealmManager](https://github.com/keycloak/keycloak/blob/26.8.1/services/src/main/java/org/keycloak/services/managers/RealmManager.java), [constante CreateDefaultClientScopes](https://github.com/keycloak/keycloak/blob/26.8.1/server-spi-private/src/main/java/org/keycloak/models/Constants.java), [criação nativa de basic/roles](https://github.com/keycloak/keycloak/blob/26.8.1/services/src/main/java/org/keycloak/protocol/oidc/OIDCLoginProtocolFactory.java), [autorização da API de conta](https://github.com/keycloak/keycloak/blob/26.8.1/services/src/main/java/org/keycloak/services/resources/account/AccountRestService.java).
- O log `already_logged_in` da tentativa inicial não era evidência suficiente para atribuir o problema somente a abas/sessão. Outro log de tentativa no `master` indicava conta de aplicação usada na URL administrativa, um problema distinto. A falha dos scopes foi comprovada por inspeção; o desaparecimento do erro visual ainda depende do reteste interativo.

### Mudanças aplicadas, sem reset

1. Cliente Node administrativo temporário, somente na rede do lab, com token apenas em memória. Criados no `secureops-lab` **somente `basic` e `roles` ausentes**, a partir das definições nativas do `master` da mesma instância/versão, removendo IDs das cópias. Nenhuma alteração feita no `master`.
2. Associados `basic/profile/email/roles` como defaults do `account-console`. Ao gateway, acrescentado somente `basic`, mantendo `profile/email` e `groups` opcional. **Não** associado `roles`/`offline_access` ao gateway e não alterada sua regra de autorização.
3. Marcados `emailVerified=true` somente nas duas contas, após conferir usernames e e-mails exatos `@lab.example`. É provisionamento fictício previsto na SPEC, não prova de posse de e-mail nem desativação da verificação no gateway.
4. Comparação em memória de metadados de credenciais, grupos, roles e required actions antes/depois confirmou preservação. Nenhuma operação de troca de senha, exclusão/recriação de OTP, atribuição de role, associação de grupo ou alteração de fluxo MFA foi executada. Campos críticos/secret do client gateway também comparados sem exportação e preservados.
5. Template para instalações novas passou a usar `attributes.CreateDefaultClientScopes="true"`, mantendo somente `groups` customizado e `basic/profile/email` no gateway. Removidas as definições parciais de `profile/email` criadas pelo agente na etapa inicial, que são substituídas pelos defaults nativos. Isso não modifica automaticamente o realm existente: a correção atual foi pontual via API.

Resultado administrativo sanitizado:

```text
operadora: emailVerified=true; credenciais=password,otp; grupo=/secureops-operators; requiredActions=[]
visitante: emailVerified=true; credenciais=password; grupos=[]; requiredActions=[CONFIGURE_TOTP]
account-console defaults=basic,email,profile,roles
secureops-gateway defaults=basic,email,profile
credenciais/grupos/roles e fluxo MFA preservados
```

Roles de gestão da própria conta já existiam via roles padrão; foram preservadas. O scope `roles` faz esses direitos existentes aparecerem no token da interface de conta, sem conceder administração do realm. A visitante poder acessar sua própria conta não é autorização para a aplicação.

### Validações executadas

- **10 testes estáticos**, 10 aprovados/0 falhas, **214.939026 ms**, com regressões para geração de scopes nativos e lista restrita do gateway. Execução na imagem Node existente, sem rede e com mount read-only. Não são testes de navegador/MFA.
- **Import novo do template corrigido aprovado** na imagem Keycloak fixada: container temporário sem rede, portas ou volume existente, `--db=dev-mem`, `--override=false`, mount do template read-only e limite 1 GiB. Retornou `Realm 'secureops-lab' imported`, sem referências a scopes inexistentes; container removido ao terminar. Não alterou o realm/volume em uso e não comprova login de instalação nova.
- **Discovery interno aprovado novamente:** issuer exato, JWKS 200, DNS para o container e token endpoint 401 sem secret. Nenhuma validação desligada.
- Endpoint oficial de **preview administrativo** `evaluate-scopes/generate-example-access-token` confirmou para ambas as contas: `sub` correto, role `account/manage-account` presente e ausência de `resource_access.realm-management`. Preview de ID token do gateway confirmou e-mail verificado, audience esperada e grupo permitido presente somente na operadora. Somente booleans foram exibidos; nenhum payload/token/ID de usuário foi persistido. Preview não realiza login, não testa senha/OTP, não comprova assinatura/audience no gateway nem é evidência de autorização HTTP pelo gateway.
- API de conta consultada com `Accept: application/json`, sem sessão: **401**, preservando negação de acesso anônimo.
- Binding do Keycloak continua somente `127.0.0.1:8080`; API permaneceu parada e sem porta. Gateway não iniciado. Sem reinício, limpeza, remoção de volumes ou revogação forçada de sessões existentes.
- Suite de 35 testes da API não repetida nesta correção restrita; último resultado permanece o de 24/10.

**Próximo passo pendente:** autora abrir uma sessão anônima nova em `/realms/secureops-lab/account/`, autenticar como operadora com a entrada OTP existente e confirmar abertura da página. Não recriar o OTP. Depois cadastrar OTP da visitante e executar os caminhos negativos/novo login previstos. T04 permanece parcial e IA-05 não está concluído; nenhuma correção foi declarada validada de ponta a ponta apenas por preview.

## 8. Confirmação manual da autora — 25/10/2026

Após as instruções de reteste em sessão anônima nova, a autora confirmou em conversa que a página da **operadora abriu**. Na sequência, confirmou que o procedimento de cadastro OTP e abertura da página também funcionou para **visitante**. São resultados manuais relatados pela autora, não uma sessão de navegador observada pelo agente. Nenhum QR, semente, código ou senha foi coletado para registrar essa confirmação.

Isso confirma o caminho positivo relatado da interface de conta após a correção e o cadastro das duas contas. Ainda não comprova rejeição de OTP incorreto/ausente, login subsequente da visitante com credencial já cadastrada ou autorização no gateway. T04 permanece parcial e IA-05 não está concluído. Próximo passo: testar em sessão nova senha sem OTP, uma única tentativa de código incorreto e depois código válido para ambas as contas; não ampliar janela OTP nem desabilitar MFA.
