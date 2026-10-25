# Evidências 02 — Identidade e acesso

**Estado final:** concluída em 25/10/2026, com testes técnicos executados pelo agente e testes interativos relatados pela autora. Matriz de aceite consolidada na seção 19. As seções anteriores preservam a sequência real de erros, correções e pendências em cada coleta; expressões como “pendente” nesses registros não representam o estado final.

**Coleta inicial:** 24/10/2026, aproximadamente 23:34–23:50, `-03:00` (logs de containers em UTC já indicam 25/10). D01–D03, política MFA/sessão e implementação aprovadas pela autora em conversa; D04 aprovada após falha real de rede.

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

## 6. Estado parcial na coleta inicial — histórico, substituído pela seção 19

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

**Atualização posterior em 25/10:** em resposta a esse procedimento para ambas as contas, a autora informou “os testes deram certo”. Registrado como relato manual de sucesso de novo login, bloqueio sem OTP, rejeição de uma tentativa incorreta e aceitação do código válido na interface de conta. Não houve observação de navegador pelo agente nem coleta de códigos. O teste manual solicitado deixa de estar pendente; IA-05 continua parcial até validar o fluxo do client da aplicação, e os demais testes de gateway/autorização/sessões permanecem pendentes. Na mesma mensagem, a autora solicitou preparar SPEC/PLAN 03, não implementar monitoramento.

## 9. Retomada T05 e negações iniciais T06 — 25/10/2026

Autora priorizou finalizar entrega 02 e autorizou retomar implementação. Coleta pelo agente aproximadamente 00:38–00:40 (`-03:00`). Mudanças documentais anteriores e rascunho 03 preservados; nenhum serviço de monitoramento iniciado.

### Execução e configuração observada

- Compose validado com `config --quiet`; Keycloak já estava executando. Não houve reinício, reset de realm, alteração de credenciais/grupos ou remoção de volume.
- Discovery interno novamente aprovado: issuer exato, JWKS 200, DNS interno para Keycloak e token endpoint 401 sem secret.
- `oauth2-proxy --config-test` aprovado. API iniciada e saudável dentro da espera de 60 s; gateway iniciado e `/ready` retornou 200 dentro da espera de 60 s. Não há medição precisa da duração de startup nesta coleta.
- Inspeção seletiva: API `user=node`, sem porta/mount, apenas `secure_ops_lab_service`; gateway UID 65532, apenas `identity`/`service`, publicação real **127.0.0.1:4180**; Keycloak UID 1000, apenas `identity`, publicação real **127.0.0.1:8080**. Todos sem privileged, `cap_drop=ALL`, `no-new-privileges:true`. Mounts do gateway somente config e dois arquivos de segredo read-only; Keycloak mantém seu volume e template read-only. Nenhum socket Docker montado.
- Probe interno aprovado. Dez testes estáticos de identidade aprovados, zero falhas, **162.191561 ms**. Os 35 testes da API não foram repetidos nesta coleta; regressão final T08 permanece pendente.
- Snapshot de memória: API 21.08 MiB, Keycloak 661.2 MiB com limite 1 GiB, gateway 6.215 MiB com limite 128 MiB. Não é medição de pico nem garantia de dimensionamento.

### Requisições reais sem autenticação

Cliente `curl.exe`, com `--resolve app.localhost:4180:127.0.0.1`, `--noproxy '*'`, timeout 5 s, sem seguir redirects. Nenhum cookie/código/token real persistido ou exibido.

| Caso | Resultado observado |
| --- | --- |
| `/ready` | 200, prontidão do gateway, não da API |
| `/` e `/health` sem sessão | 403, página de início de login, sem JSON da API |
| `/oauth2/auth` sem sessão | 401 |
| `/health` com headers fictícios X-Forwarded-User/Groups, X-Auth-Request-User e Bearer fictício | 403 |
| `/health` com cookie sintético inválido | 403; não é adulteração de cookie válido recém-emitido |
| `/oauth2/callback` sem parâmetros | 500, sem emissão de cookie de sessão |
| Callback com code/state explicitamente fictícios, sem cookie CSRF | 500, sem emissão de cookie de sessão |
| `/oauth2/start` | 302 para endpoint canônico do realm; client esperado, PKCE S256, nonce e state presentes; valores omitidos |

Cookie CSRF do início do fluxo observado nos headers: HttpOnly, SameSite=Lax, sem Domain e sem Secure, conforme exceção D01. Cookie de sessão e cookies do Keycloak no fluxo da aplicação ainda dependem do navegador.

**Falha da primeira verificação e limite:** o primeiro script esperava 302/401/403 também no callback incompleto e interrompeu ao receber 500. Requisição específica posterior confirmou falha fechada sem cookie de sessão. Isso não valida tratamento amigável de erro, nem prova isoladamente checagem criptográfica de state, nonce ou audiência. Nenhuma proteção foi alterada para obter outro status. Respostas/headers foram inspecionados em memória e apenas resultados sanitizados exibidos.

**Estado ao fim:** API, Keycloak e gateway executando, dados/segredos preservados. Próximo passo: autora testar operadora em `http://app.localhost:4180/`, começando sessão anônima nova, verificando senha/OTP ausente/incorreto/válido e resposta da aplicação. Depois testar visitante autenticada e negada pelo gateway. T06–T08 e aceite integral da entrega continuam pendentes.

## 10. Acesso da operadora e negação da visitante — relato manual em 25/10/2026

- Após instrução de login da operadora pelo gateway, a autora informou sucesso e apresentou a resposta `{"service":"secureops-api","message":"Serviço fictício do laboratório"}`. Isso registra acesso positivo à aplicação via procedimento solicitado; não é confirmação específica de `/health` nem medição do status HTTP pelo agente.
- Em seguida, foi solicitado fechar todas as janelas anônimas e autenticar como visitante na aplicação com senha e OTP válidos. A autora relatou **“forbidden 403 para o usuario visitante”**. Registrado como resultado manual de negação no gateway após o procedimento solicitado, não como observação direta do navegador nem inspeção independente dos eventos do IdP pelo agente.
- Não foram coletados senha, OTP, cookie, token ou URL de callback. A rejeição de OTP ausente/incorreto no client da aplicação ainda precisa de confirmação explícita, separada dos testes já relatados na interface de conta. `/health` autorizado, grupos semelhantes/vazios, cookies, audiência, sessão/logout, persistência e falhas continuam pendentes. IA-06/IA-07 não foram declarados integralmente concluídos.

**Confirmação posterior da autora:** “o OTP incorreto foi rejeitado sim, está tudo ok”. Registrada rejeição de OTP incorreto no fluxo da aplicação como teste manual relatado. A confirmação não detalhou o teste de ausência de OTP nem o corpo de `/health`; esses itens não foram presumidos aprovados. Não houve coleta de código nem observação direta pelo agente. Próxima validação manual: duração da sessão do gateway, com referência de horário a partir de login novo e sem renovar autenticação durante a medição.

## 11. Regressão durante fechamento — 25/10/2026

Autora autorizou continuar o fechamento da entrega 02. Execução pelo agente aproximadamente 01:34–01:35 (`-03:00`), sem interromper serviços nem alterar contas, grupos, segredos ou volume.

- `docker compose --profile tools run --build --rm api-test`: **35 aprovados, zero falhas**, 5605.675942 ms. Container de teste sem rede; build reaproveitou cache. Aviso de serviços de identidade órfãos ao usar só a base foi mantido, sem `--remove-orphans`.
- Suite estática de identidade na imagem Node existente, sem rede e com mount read-only: **10 aprovados, zero falhas**, 161.55149 ms. Não equivale a login nem teste criptográfico de audiência.
- Discovery interno: issuer exato, JWKS 200, DNS interno e rejeição 401 sem client secret. Probe interno: `probe_succeeded`.
- Compose combinado válido. Inspeção real confirmou novamente API sem portas/mounts e somente `service`; Keycloak somente `identity`; gateway em ambas. Bindings de Keycloak/gateway exclusivamente `127.0.0.1`, usuários esperados, capabilities removidas, NoNewPrivs, sem privileged/socket Docker.
- Cliente HTTP local sem sessão confirmou `/ready` 200, `/oauth2/auth` 401 e `/health` 403. Nenhum dado de sessão foi coletado.

**Pendências mantidas:** não houve resposta ao teste cronometrado de expiração solicitado anteriormente. Sessão/revogação, logout, cookies no navegador, persistência de OTP após reinício, falhas do caminho autenticado, variações de grupo e audiência isolada continuam sem aceite completo. A troca futura de monitoramento por Zabbix não foi implementada nesta tarefa. Regressão aprovada não conclui a entrega 02.

## 12. Relato do teste de saúde e expiração — 25/10/2026

Após instrução para novo login da operadora, consulta de `/health` e atualizações a cada 30 s sem refazer login até bloqueio, a autora informou **“tudo certo com esse teste”**. Registrado como relato manual de sucesso do procedimento solicitado, incluindo saúde autorizada e perda de acesso durante o teste, sem observação direta do navegador pelo agente.

A autora não informou duração nem horários. Não foi atribuída uma medição de 300 s ou afirmado cumprimento exato do limite de cinco minutos. IA-09 permanece parcial: confirmar duração aproximada, nova exigência de senha+OTP após expiração e teste de revogação. Próximo passo manual: logout do gateway separado da sessão Keycloak e encerramento das duas camadas. Nenhum cookie, código ou senha coletado.

**Confirmação posterior:** a autora informou que o bloqueio aconteceu em **aproximadamente cinco minutos**. Isso complementa o relato anterior de atualizações a cada 30 s sem novo login e é compatível com a duração configurada. Trata-se de tempo aproximado relatado, não medição precisa de 300 s pelo agente. Nova exigência dos dois fatores após expiração, revogação e logout em duas camadas continuam pendentes; esta resposta confirmou somente a duração, não o procedimento de logout solicitado.

## 13. Logout confirmado e impedimento para teste de persistência

Em resposta à confirmação solicitada dos três resultados do logout, a autora informou **“executado e deu certo”**. Registrado como relato manual de sucesso: sair do gateway bloqueia `/health`, sessão Keycloak permanece até logout separado e login após sair de ambas as camadas exige senha+OTP. Não houve inspeção direta de cookie pelo agente; não se afirma single logout nem validação de revogação de sessão por bloqueio da conta.

Na sequência, o agente tentou consultar o estado dos serviços antes de reiniciar Keycloak/gateway. `docker compose -f compose.yaml -f compose.identity.yaml ps -a` falhou: pipe `dockerDesktopLinuxEngine` não encontrado. Isso demonstra engine inacessível naquele momento, não perda de volume nem falha da aplicação. **Nenhum reinício, remoção de dados ou alteração de segredos foi executado.** Persistência após reinício segue pendente, aguardando Docker Desktop com engine Linux acessível. Não declarar estado atual dos containers a partir da coleta anterior.

## 14. Retomada após retorno do Docker — 25/10/2026

Autora informou engine acessível novamente. Coleta pelo agente aproximadamente 08:42–08:43 (`-03:00`). Consulta real encontrou API, Keycloak e gateway parados, saída 255. Não foi determinada a causa desse código nem inferida perda de dados.

- Compose combinado validado. Keycloak existente iniciado com `start keycloak`; discovery do host aprovado em 16856 ms, issuer/endpoints canônicos. API retomada e saudável com `up -d --wait --wait-timeout 60 api`; gateway existente iniciado com `start oauth2-proxy`, `/ready` 200 dentro de 60 s.
- Comparações antes/depois confirmaram mesmo nome de volume de dados e hashes inalterados dos arquivos de client secret e cookie secret; hashes/valores omitidos. Nenhum volume removido, arquivo de segredo gerado ou configuração alterada. Isso preserva o armazenamento, mas não comprova por si só integridade de todos os registros.
- Discovery interno novamente aprovado, JWKS 200, rejeição 401 sem client secret e probe da API aprovado.
- Inspeção real: API executando sem publicação e somente `service`; Keycloak somente `identity`, binding `127.0.0.1:8080`; gateway em `identity`/`service`, binding `127.0.0.1:4180`.
- Cliente administrativo Node temporário, sem porta e com bootstrap montado read-only, consultou somente leitura. Confirmou client confidencial habilitado, code flow, redirect URI exata, implicit/direct grants/service accounts desabilitados e fluxo do client com senha+OTP `REQUIRED`, sem alternativa Cookie. Tokens apenas em memória; nenhum segredo OTP consultado/exportado.
- Para ambas as contas, confirmou habilitação, e-mail verificado e metadados de credenciais password/OTP presentes. Grupo permitido presente somente na operadora. Não houve alteração de contas, grupos ou credenciais.

**Limite e próximo passo:** dados e configuração foram encontrados após retomada real de containers que estavam parados. Ainda falta autora efetuar login da operadora com a entrada OTP existente e conferir nova negação da visitante, sem recadastrar OTP. Existência de metadados não substitui esses testes. Não se afirma que houve reinício controlado anterior pelo agente; a retomada aproveitou o estado parado observado após indisponibilidade do engine. Testes de falha/revogação/audiência e demais itens não foram dispensados.

**Confirmação manual posterior:** em resposta ao procedimento com operadora usando o OTP existente e visitante autenticada/negada em sessões anônimas separadas, a autora informou **“confirmado pelo teste, tudo certo”**. Registrado como sucesso relatado dos dois caminhos após retomada, sem recadastro de OTP. Combinado à inspeção somente-leitura acima, confirma persistência funcional de configuração, contas, grupo e OTP nessa retomada. Não é observação direta de navegador pelo agente nem teste de falha do upstream, revogação ou audiência. IA-11 permanece parcial pelos testes de indisponibilidade ainda pendentes.

## 15. Falha controlada da API — em andamento

Em 25/10/2026, a autora confirmou JSON da aplicação após novo login da operadora, preparando sessão autenticada. Às aproximadamente 08:46:53 (`-03:00`), o agente executou `stop api` com os dois arquivos Compose. API parou com código 0; Keycloak e gateway continuaram executando, `/ready` do gateway retornou 200. Nenhum volume, segredo ou configuração foi alterado.

**Estado intermediário intencional:** API parada, aguardando atualização da página autenticada pela autora e relato do resultado. Ainda não há evidência de erro de upstream no navegador nem teste de recuperação. Se a sessão expirar, negação de autenticação não substitui a prova de falha do upstream.

**Resultado da falha e retomada:** autora relatou **502 Bad Gateway** na página autenticada. O agente então retomou somente API com `up -d --wait --wait-timeout 60 api`; container saudável e probe interno `probe_succeeded`, às aproximadamente 08:47:57 (`-03:00`). Keycloak/gateway permaneceram ativos. Estado ao fim desta execução: os três serviços executando, API saudável. Falta confirmação da autora de retorno do JSON via gateway após atualizar a página; saúde interna não substitui recuperação do caminho autenticado.

**Confirmação da recuperação no navegador:** em resposta à atualização solicitada, a autora informou **“voltou!”**, confirmando retorno do JSON da aplicação via gateway. Não informou necessidade de novo login; não se infere preservação de cookie além do que foi relatado. Ciclo de falha/recuperação da API aprovado por inspeção de containers/probe e relatos manuais do 502 e retorno do JSON. Falha do Keycloak e demais critérios restantes continuam pendentes.

## 16. Falha controlada do Keycloak — em andamento

Autora solicitou sequência objetiva para concluir os testes. Em 25/10/2026, aproximadamente 08:52:40 (`-03:00`), o agente parou somente Keycloak com `stop keycloak`. Container encerrou com código 143; API permaneceu saudável e gateway ativo. Cliente HTTP sem sessão recebeu `/ready` 200 e `/oauth2/auth` 401. Discovery no host deixou de responder (`curl` código 7, HTTP 000). Nenhuma credencial, volume ou configuração foi alterada.

**Estado intermediário intencional:** Keycloak parado para autora testar novo login em sessão anônima limpa. Ainda não foi relatado o resultado no navegador nem retomado o Keycloak. Redirecionar para um provedor indisponível não significa que o gateway autenticou alguém; requisito é impedir conclusão de novo login e acesso à API. Após relato, retomar Keycloak e aguardar discovery antes do controle positivo.

**Resultado e retomada:** autora informou **“deu erro para acessar o Keycloak”**, em resposta ao teste de login novo sem sessão. Registrada falha de acesso ao provedor e impossibilidade de concluir esse login como resultado manual; nenhum cookie/token foi coletado. O agente retomou Keycloak com `start keycloak`; discovery do host aprovado em 12292 ms e discovery interno/JWKS/negação sem secret aprovados. Probe API também aprovado. Às aproximadamente 08:53:46 (`-03:00`), os três serviços estavam executando, API saudável. Ainda será confirmado login positivo pós-retomada na preparação do teste de revogação. Não foi testado uso de cookie preexistente enquanto o provedor estava parado.

## 17. Retirada temporária de grupo — em andamento

A autora confirmou JSON após novo login da operadora, também fornecendo controle positivo após a retomada do Keycloak. Em 25/10/2026, às **08:56:41 (-03:00)** / **11:56:41Z**, o agente retirou somente a associação da operadora ao grupo `/secureops-operators` por cliente administrativo temporário na rede do lab. Antes da operação, conferidos username/e-mail fictícios, conta habilitada e associação existente. Comparações após a operação confirmaram demais associações, metadados de credenciais, habilitação e required actions preservados. Nenhuma senha, OTP ou role foi alterada; o grupo em si não foi excluído.

**Estado intermediário intencional:** operadora temporariamente sem o grupo permitido, exigindo restauração após os testes. Aguardam-se relato de negação em novo login e término de acesso da sessão antiga até o limite restante de cinco minutos. O horário de criação do cookie não foi coletado; medir a partir da retirada fornece limite superior, não duração exata da sessão. Não confundir acesso residual autorizado por cookie anterior com falha do controle de novo login.

**Resultado parcial relatado:** autora informou 403 ao fazer novo login “por uma nova aba no navegador” e aguarda verificar o acesso na aba com sessão anterior. Isso confirma o relato de negação no novo login. É necessário esclarecer se foram usados contextos de cookies separados (normal versus anônimo), pois abas do mesmo perfil compartilham cookies e logout/novo login podem interferir na sessão antiga. Até esse esclarecimento, eventual bloqueio da aba antiga não comprova isoladamente expiração/revogação do cookie anterior. Associação ainda requer restauração após teste.

**Esclarecimento e resultado:** autora confirmou login novo na janela normal e sessão antiga na anônima, portanto contextos de cookies separados. Em seguida informou que a janela anônima perdeu acesso. Registrados novo login negado (403) e término do acesso residual relatados; não foi fornecido horário exato do bloqueio para medir independentemente o teto de cinco minutos. A medição anterior da sessão foi aproximadamente cinco minutos, não medição precisa desta retirada de grupo.

**Restauração executada às 09:06:36 (-03:00):** agente recolocou somente a associação da operadora ao grupo existente `/secureops-operators`. Comparações confirmaram metadados de credenciais e demais associações preservados; visitante permanece sem o grupo autorizado. Nenhuma conta, grupo ou OTP recriado. Falta controle positivo de novo login da operadora após restauração e confirmação aproximada de que o bloqueio observado ocorreu até 09:01:41.

## 18. Verificador OIDC isolado reproduzível — 25/10/2026

Implementados `scripts/Test-IdentityVerifier.ps1` e `infra/identity/verify-isolated.mjs`, no escopo do harness previsto em T06/IA-08. Usa a mesma imagem OAuth2 Proxy **v7.15.5 com digest fixado**, a imagem Node já existente e cópia da configuração principal. Substitui apenas issuer/callback/upstream por serviços diagnósticos e os dois segredos por valores aleatórios efêmeros. Mantém provider Keycloak OIDC, grupo exato, domínio, PKCE S256, algoritmo RS256 e validações habilitadas. Configuração principal não é escrita nem o realm apontado para emissor falso.

### Isolamento e precondições

- Dois containers em rede bridge temporária **interna**, sem porta publicada, sem volume, sem conexões com `identity`/`service`, sem privileged/socket/capabilities, NoNewPrivs e rootfs read-only. Reutiliza imagens locais (`--pull never`), sem biblioteca adicional.
- Emissor/usuário/upstream são fictícios de teste. Chaves RSA geradas em memória e descartadas com o processo. Nenhuma senha, OTP, cookie ou token do laboratório principal foi lido. Config temporária em `.local/identity-verifier/<identificador>/`, removida ao terminar; contém apenas segredos novos do teste.
- Controle positivo completa authorization code + PKCE, emite cookie real pelo binário do proxy e alcança upstream HTTP 200. O emissor valida client secret e code verifier antes de responder.
- Para cada teste negativo de token, assertiva confirma que o emissor forneceu exatamente uma resposta de tokens com sucesso; verificação local de assinatura confirma a precondição RS256 válida em todos exceto no caso proposital de assinatura incorreta. Audience incompatível é alterada **somente no ID token**, com mesma chave/issuer e demais claims válidos; não é erro de client secret nem bearer arbitrário.
- O script encerra/remove apenas seus containers/rede de nomes únicos e arquivos que criou; não remove volumes nem executa limpeza ampla.

### Resultados reais

Duas execuções consecutivas da versão corrigida aprovadas, terminando aproximadamente **09:16:37 (-03:00)**. Cada execução passou em 12 verificações (mais linha final de resumo):

| Cenário | Resultado |
| --- | --- |
| Token válido, nonce correto e grupo exato | Sessão criada; upstream 200; Authorization não encaminhado |
| Atributos do cookie de sessão emitido | HttpOnly, SameSite=Lax, host-only, sem Secure, uma parte; somente contexto isolado |
| Audience incompatível no ID token com assinatura válida | Callback 500; nenhuma sessão emitida |
| Issuer incompatível | Callback 500; nenhuma sessão emitida |
| Assinatura incompatível com JWKS | Callback 500; nenhuma sessão emitida |
| Nonce incompatível | Callback 403; nenhuma sessão emitida |
| ID token expirado | Callback 500; nenhuma sessão emitida |
| Claim groups ausente | Callback 403; nenhuma sessão emitida |
| Claim groups vazia | Callback 403; nenhuma sessão emitida |
| Grupo semelhante `/secureops-operators-extra` | Callback 403; nenhuma sessão emitida |
| State alterado com cookie CSRF emitido pelo proxy | Callback 500; não chegou ao token endpoint |
| Cookie válido emitido pelo proxy e depois adulterado | 403, sem upstream; cookie original ainda alcança 200 como controle |

Os negativos de token não alcançaram upstream nem emitiram cookie de sessão. Erros 500 nesses callbacks significam rejeição fechada, não status amigável nem disponibilidade do emissor principal. Testes de grupos usam identidade fictícia do emissor isolado; complementam visitante sem grupo e retirada real de grupo, não simulam edição adicional do realm principal. Atributos no navegador principal ainda precisam ser conferidos; não se confunde fixture com login real nem com cadastro MFA.

### Problemas encontrados durante preparação

Tentativas iniciais falharam por corrida de startup do emissor (RSA antes de escutar), quoting de JavaScript inline no PowerShell, rota de upstream `/upstream/` que não correspondia a `/`, e assertiva que presumiu apenas uma chamada ao token endpoint quando a biblioteca tentou novamente. Corrigidos espera finita por discovery, comando de readiness em arquivo, upstream raiz e assertiva separando chamadas de respostas bem-sucedidas. Uma repetição ainda revelou base64 padrão incompatível com `SecretBytes` quando continha `+`/`/`; geração do cookie secret efêmero corrigida para **base64url**, conforme [fonte v7.15.5](https://github.com/oauth2-proxy/oauth2-proxy/blob/v7.15.5/pkg/encryption/utils.go). Nenhum segredo do gateway principal foi alterado. Só as duas execuções finais completas constituem aprovação da versão final.

Suite estática principal repetida durante esse trabalho: **10 aprovados, zero falhas, 151.299068 ms**; probe da API principal aprovado. Suite de 35 testes API não repetida nesta coleta (última execução na seção 11). Critérios manuais finais e revisão documental permanecem pendentes; a entrega não foi declarada concluída.

## 19. Confirmação final e fechamento — 25/10/2026

### Confirmação manual da autora

Em resposta ao procedimento final (novo login da operadora sem sair do Keycloak, conferir grupo em `/oauth2/userinfo`, atributos do cookie de sessão e bloqueio da sessão anterior até 09:01:41), a autora informou **“esta tudo certo! finalize a entrega 02”**. Registrado como sucesso relatado desses itens, incluindo controle positivo após restaurar o grupo, nova exigência de senha+OTP com sessão do provedor existente e confirmação do teto de cinco minutos para a retirada de grupo.

Atributos de `secureops_session` confirmados pela autora no navegador: HttpOnly, SameSite=Lax, Secure desmarcado, Path `/`. Grupo esperado confirmado na sessão via endpoint do gateway, sem exportar token/ID de usuário. Não houve coleta de valor de cookie, screenshot de credenciais ou horário exato do bloqueio. A medição de expiração é aproximada; confirmação do limite não equivale a cronometragem independente em segundos pelo agente.

### Regressão e segurança finais pelo agente

Execução aproximadamente 09:23–09:25 (`-03:00`):

- **35 testes API aprovados**, zero falhas, **5791.312698 ms**, via Compose com build de teste/cache; container sem rede.
- **10 verificações estáticas de identidade aprovadas**, zero falhas, **209.396423 ms**, sem rede e mount read-only.
- **12 verificações do proxy real no harness isolado aprovadas** novamente, incluindo assinatura válida/audience incompatível, controle positivo, nonce/state, grupos e cookie adulterado; containers/rede efêmeros sem publicação. Não substituem cadastro OTP real.
- Discovery interno, issuer/JWKS e rejeição sem secret aprovados; probe interno aprovado. Compose válido; comparação da configuração resolvida confirmou `api` idêntica à base.
- Inspeção real de redes/bindings/usuário/mounts: API somente `service` interna, sem publicação/mount; Keycloak apenas `identity`; gateway em ambas; publicações de 8080/4180 exclusivamente `127.0.0.1`; usuários não root esperados, ALL capabilities removidas, NoNewPrivs e sem privileged/socket Docker.
- Tentativas de acesso em `[::1]:4180` e `[::1]:8080` falharam, sem listener IPv6 observado por esses caminhos. Não comprova isolamento absoluto do host.
- Sem sessão: `/` e `/health` 403, `/oauth2/auth` 401, `/ready` 200. Logs dos três containers examinados em memória: zero correspondências aos segredos locais conhecidos e ao padrão selecionado de JWT; conteúdo bruto não exportado. Varredura limitada, não garantia universal.
- Snapshot de memória: API **22.05 MiB**, Keycloak **615.5 MiB / 1 GiB**, gateway **24.86 MiB / 128 MiB**; não é medição de pico/dimensionamento.
- Revisão documental final: **65 links Markdown locais** e links do HTML com destinos existentes (âncoras não verificadas); `git diff --check` e sintaxe PowerShell aprovados. Varredura de **38 arquivos versionados/versionáveis**, sem correspondências aos segredos locais conhecidos (incluindo representações da chave de cookie) e aos padrões selecionados de chave privada/JWT. `.local` fora da seleção; ausência universal de segredos não garantida. Nenhum container/rede `secureops-verifier-*` remanescente na consulta final.

**Correção de precisão documental sobre a chave de cookie:** os registros iniciais simplificavam `cookie-secret-file` como “não decodifica base64”. O arquivo é lido sem normalização, mas `SecretBytes` tenta **base64url** e usa bytes brutos se não obtiver comprimento AES válido. A chave principal de 32 bytes brutos segue válida e inalterada; o runbook foi corrigido. Essa descoberta no harness não motivou rotação de segredo do gateway principal.

### Cookies do Keycloak antes do login — navegador separado

Chrome headless em perfil temporário próprio, CDP restrito a loopback com porta dinâmica, acessou autorização canônica sem digitar credenciais nem completar login. Foram exibidos somente nomes/atributos, não valores:

| Cookie | HttpOnly | Secure | SameSite | Path |
| --- | --- | --- | --- | --- |
| AUTH_SESSION_ID | Sim | Sim | None | `/realms/secureops-lab/` |
| KC_AUTH_SESSION_HASH | Não | Sim | None | `/realms/secureops-lab/` |
| KC_RESTART | Sim | Sim | None | `/realms/secureops-lab/` |

Domínio observado: `keycloak.localhost`; tamanhos 163, 86 e 1279 bytes, respectivamente. Chrome aceitou cookies Secure nesse contexto `.localhost` mesmo com URL HTTP; isso não significa transporte TLS nem disponibilidade desse comportamento em outros navegadores. Nenhuma configuração SSL/realm foi relaxada. **Cookies de sessão autenticada do Keycloak não foram inspecionados pelo agente**; não se atribuem a eles os atributos dos cookies de pré-login. Primeira tentativa CDP falhou ao selecionar target; corrigida enumeração da resposta e repetido com sucesso. Navegador diagnóstico encerrado, sem interagir com perfis/sessões da autora.

### Matriz final de aceite

| Critério | Resultado e origem da evidência |
| --- | --- |
| IA-01 | Aprovado: decisões D01–D04 explícitas, versões/digests/opções conferidos; seções 1–4 |
| IA-02 | Aprovado: issuer/discovery/DNS interno e login canônico real relatado; seções 9–10, 14 e 19 |
| IA-03 | Aprovado: configuração + inspeção real de bindings/redes/mounts/usuários, atributos de sessão relatados; seções 9 e 19 |
| IA-04 | Aprovado: anônimo/headers forjados não alcançam API, 401 em auth e fluxo manual; seções 9 e 19 |
| IA-05 | Aprovado: fluxo obrigatório inspecionado, cadastro e testes negativos/positivos relatados pela autora, novo login exige ambos fatores; seções 8, 10, 14 e 19 |
| IA-06 | Aprovado: JSON original e `/health` autorizado relatados, grupo confirmado na sessão, controle positivo pós-restauração; seções 10, 12 e 19 |
| IA-07 | Aprovado: visitante autenticada negada e grupo retirado negou novo login; grupos ausente/vazio/semelhante também exercitados no proxy isolado; seções 10, 17–19 |
| IA-08 | Aprovado: harness com assinatura válida/audience incompatível, state/nonce e cookie real adulterado, com controles positivos; seção 18 e repetição final |
| IA-09 | Aprovado com medição manual aproximada: cinco minutos sem refresh e confirmação de bloqueio até prazo após retirada, sem revogação imediata; seções 12, 17 e 19 |
| IA-10 | Aprovado por relato manual: logout de gateway e Keycloak separados, nova senha+OTP; seção 13 |
| IA-11 | Aprovado: dados/OTP preservados após retomada real e login/negação confirmados; provedor parado impede novo login; API parada 502 e recuperação confirmada; seções 14–16 |
| IA-12 | Aprovado: regressão final, runbook revisado, documentação consistente e varredura sanitizada; seção 19 |

### Estado entregue e limites preservados

API, Keycloak e gateway permanecem executando; operadora com grupo autorizado restaurado, visitante sem esse grupo. Volume e segredos preservados. Nenhum serviço de monitoramento, n8n ou Zabbix implementado neste fechamento. Sem commit/push automático.

Continuam limites do laboratório, não testes silenciosamente dispensados: HTTP local, `start-dev`/dev-file, host/daemon na base de confiança, ausência de backup/HA, nenhuma garantia de egress bloqueado ou ZTNA completo. Bootstrap administrativo permanece local; migração para administradora permanente não foi executada nem constitui critério de aceite IA-01–IA-12. Cookies autenticados do Keycloak não foram exportados/inspecionados e tempo de sessão não foi cronometrado automaticamente. Os testes isolados usam identidade de fixture e não demonstram MFA por si mesmos; essa evidência vem da autora no realm real.
