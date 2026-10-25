# Runbook — Identidade e acesso

**Estado:** entrega concluída em 25/10/2026. Procedimentos técnicos executados pelo agente e interativos confirmados pela autora; resultados/limites na seção 19 das [evidências](../evidence/02-identity-access.md). Requisitos: [SPEC 02](../features/02-identity-access/SPEC.md). Instalação nova ainda exige provisionamento manual; não recriar contas/OTP no ambiente existente.

## 1. Limites e arquivos

- HTTP local aprovado, somente contas fictícias exclusivas. Senha/TOTP/cookies não têm confidencialidade de TLS. Não reutilizar credenciais pessoais.
- `compose.yaml` preserva a Fundação. Somar `compose.identity.yaml` nos comandos de identidade; a API continua sem porta e só na rede `service` interna.
- `identity` é bridge **não interna**, após aprovação explícita D04 e falha observada de publicação com rede interna. Keycloak/gateway podem ter saída de rede. Não foi feito teste de egress externo.
- Keycloak publica `127.0.0.1:8080`; gateway `127.0.0.1:4180`. Não abrir portas adicionais/roteador/túneis.
- Volume `keycloak-data` contém banco, credenciais MFA e chaves: é sensível, não é backup. Não usar `down -v`, prune ou reset de realm.
- `.local/identity` contém segredos locais ignorados pelo Git e excluídos do build. O inicializador restringe sua ACL ao usuário Windows atual, mas isso não protege contra administradores/daemon Docker. Keycloak recebe seus segredos em ambiente (visível ao administrador Docker); o gateway lê dois arquivos read-only.

## 2. Preparar em uma instalação nova

PowerShell na raiz, Docker Linux e imagens disponíveis. A pasta local **já foi criada no ambiente atual**; não rodar novamente para tentar rotacionar.

```powershell
./scripts/Initialize-Identity.ps1
docker compose -f compose.yaml -f compose.identity.yaml config --quiet
docker compose -f compose.yaml -f compose.identity.yaml up -d keycloak
./scripts/Test-IdentityDiscovery.ps1
docker compose -f compose.yaml -f compose.identity.yaml --profile tools run --rm --no-deps identity-check
```

O inicializador recusa pasta existente e gera segredos sem exibi-los. A chave `cookie-secret` usa **32 bytes binários brutos**, formato validado no lab. O arquivo é lido sem normalização; `SecretBytes` no proxy v7.15.5 tenta base64url e, se não obtiver comprimento AES válido, usa bytes brutos. Não confundir base64 padrão com base64url nem substituir o arquivo por texto de 44 bytes. Não abrir o binário no editor, adicionar newline ou copiar exemplos como valores reais.

Antes de executar `identity-check`, construir a imagem local com `docker compose build api` se ainda não existir. O cliente temporário usa essa imagem, sem porta, somente na rede de identidade, e não obtém tokens: testa DNS interno, issuer/endpoints, JWKS e negação HTTP 401 no token endpoint sem client secret. Saída `unauthorized_client` é o erro observado nesta versão. Não comprova MFA ou validação de audiência.

`Test-IdentityDiscovery.ps1` espera até 120 s por metadados do realm, não por um health check de gestão. Usa `curl.exe --resolve` apenas nessa requisição. No Windows testado, `Resolve-DnsName` devolveu NXDOMAIN, mas Chrome headless alcançou `.localhost` em loopback sem alterar o sistema. Isso não garante o comportamento de qualquer outro navegador: testar URLs canônicas no navegador usado na demonstração. Não executar `--remove-orphans`: ao usar só o Compose base, o aviso sobre Keycloak é esperado e não justifica removê-lo.

O template usa `attributes.CreateDefaultClientScopes="true"`, conferido no código da versão 26.8.1, para criar os scopes nativos mesmo com `groups` customizado. Não substituir os scopes nativos por definições parciais: `basic` contém claims básicos e `roles` permite à interface de conta reconhecer as permissões já existentes. O gateway tem somente `basic/profile/email` padrão e `groups` opcional; não se libera a aplicação por roles da interface de conta. O import corrigido foi aceito em container temporário sem rede, portas ou volume do lab, com banco `dev-mem`; isso não é teste de login.

## 3. Provisionar contas e TOTP — somente para instalação nova

1. Abrir **http://keycloak.localhost:8080/admin/master/console/** no navegador. Essa URL é administrativa, não login da aplicação.
2. Consultar `.local/identity/keycloak.env` **somente em editor local**. Usar `KC_BOOTSTRAP_ADMIN_USERNAME` e `KC_BOOTSTRAP_ADMIN_PASSWORD` para entrar. Não executar comandos que imprimam o arquivo, nem enviar valores/capturas ao chat.
3. A administradora de bootstrap é temporária e pertence ao `master`; não é a operadora da aplicação. Planejar uma conta administrativa permanente local, testar seu acesso e só então decidir com autorização específica sobre retirar o bootstrap. Não apagá-lo automaticamente nem usar suas credenciais no gateway.
4. Selecionar realm **`secureops-lab`**, não criar contas de aplicação no `master`.
5. Em **Users → Add user**, criar `operadora`, e-mail `operadora@lab.example`, enabled e e-mail verificado. Nome/sobrenome, se exigidos pela interface, devem ser fictícios. Incluir a required action **Configure OTP** (`CONFIGURE_TOTP`). Não marcar e-mail verificado em contas de fora do laboratório: aqui isso é provisionamento fictício, não verificação de caixa postal.
6. Em **Credentials**, definir senha nova e exclusiva do lab, sem compartilhá-la; desativar **Temporary** para evitar uma troca de senha não prevista no cenário. Em **Groups**, associar somente essa conta a **`/secureops-operators`**.
7. Repetir para `visitante`, e-mail `visitante@lab.example`, required action Configure OTP e senha exclusiva, **sem** associação ao grupo permitido.
8. Não atribuir roles administrativas às duas contas. Confirmar que o client `secureops-gateway` usa o override Browser `secureops-browser-mfa`, com **Username Password Form REQUIRED** e **OTP Form REQUIRED**; não alterar o fluxo global para fazer login passar.

No ambiente entregue, ambas as contas já possuem senha/OTP e e-mail fictício verificado; somente operadora tem o grupo permitido. Cadastro/login/negações foram confirmados pela autora e repetidos após retomada. Não recriar credenciais nem required actions para repetir a demonstração.

### Diagnóstico de erro após OTP — correção histórica de 25/10

O `account-console` estava sem scopes padrão e o realm sem `basic`/`roles`. Restaurados scopes nativos, sem reset de credenciais nem novas roles. Autora confirmou desaparecimento do erro e login das duas contas. Se o problema reaparecer, inspecionar client/scopes/fluxo antes de alterar credenciais; repetir os passos abaixo só quando necessário.

1. Fechar todas as janelas anônimas usadas no laboratório para descartar a sessão/token antigo. Não é necessário limpar o perfil pessoal do navegador.
2. Abrir nova janela anônima em **http://keycloak.localhost:8080/realms/secureops-lab/account/**, não na URL administrativa `/admin/master/console/`.
3. Entrar como `operadora`, com a senha da própria conta e o código atual da entrada **já cadastrada** no autenticador. Não remover/recriar OTP nem escanear outro QR para essa conta.
4. Verificar se a página de conta abre. Se falhar, informar somente a mensagem e a etapa (antes/depois de enviar o OTP); não enviar código, QR, cookies ou URL completa com parâmetros de sessão.
5. Se funcionar, sair e repetir para `visitante`. Configure OTP só aparece em instalação nova sem credencial cadastrada; nesse caso usar entrada separada no autenticador. No ambiente atual, usar o OTP existente.

Não confundir gerenciar a própria conta no Keycloak com autorização à aplicação; visitante gerencia a conta e é negada no gateway.

### Cadastro TOTP e validação

- TOTP HmacSHA1, 6 dígitos, 30 s e janela de tolerância 1; não ampliar a janela para mascarar relógio incorreto.
- O cadastro deve ocorrer no navegador/autenticador da autora. Não exportar QR/seed e não usar serviços externos de decodificação/JWT/QR.
- A interface de conta `http://keycloak.localhost:8080/realms/secureops-lab/account/` foi usada pela autora para cadastro. Testar também na aplicação: cadastro/interface de conta não substitui MFA no client do gateway.
- Concluir Configure OTP com código válido para **cada** conta. Depois sair e repetir autenticação, incluindo ausência de OTP e código incorreto. O primeiro cadastro sozinho não comprova MFA nos logins seguintes.
- Se a interface de conta falhar, registrar o erro sanitizado e revisar a ordem T04/T05 antes de seguir; não criar fluxo alternativo sem MFA nem editar cookies para contornar erro.

## 4. Iniciar gateway e demonstrar autorização

Antes de iniciar gateway, Keycloak precisa estar pronto conforme seção 2. Configuração, discovery, negações e caminhos de operadora/visitante foram validados no fechamento.

```powershell
docker compose -f compose.yaml -f compose.identity.yaml run --rm --no-deps oauth2-proxy --config=/etc/oauth2-proxy/oauth2-proxy.cfg --config-test
docker compose -f compose.yaml -f compose.identity.yaml up -d --wait --wait-timeout 60 api
docker compose -f compose.yaml -f compose.identity.yaml up -d oauth2-proxy
# Aguardar HTTP 200, repetindo por no máximo 60 segundos:
curl.exe --noproxy '*' --resolve app.localhost:4180:127.0.0.1 --max-time 3 --silent --output NUL --write-out '%{http_code}' http://app.localhost:4180/ready
```

Não há health check de container para Keycloak/proxy nesta etapa: não interpretar `up -d` como prontidão. Aguardar o gateway até 60 s por `/ready` com um cliente local e verificar status; `/ready` retornou 200 na retomada. `/ping` e `/ready` são do gateway, **não** `/health` da API.

### Operadora na aplicação

1. Fechar todas as janelas anônimas do laboratório e abrir uma nova em **http://app.localhost:4180/**. Sem sessão, deve aparecer início de login, não JSON da API.
2. Selecionar o login pelo Keycloak; conferir host `keycloak.localhost:8080` e realm `secureops-lab`.
3. Entrar como `operadora`, com sua senha existente. Confirmar que senha sozinha não conclui; enviar uma única tentativa de OTP propositalmente incorreto e verificar rejeição. Depois enviar o código atual correto da entrada já cadastrada.
4. Confirmar retorno para `app.localhost:4180` e resposta JSON da aplicação. Na mesma janela abrir **http://app.localhost:4180/health**: esperado `{"status":"ok"}`.
5. Relatar somente resultados/mensagem e etapa de eventual falha. Não enviar senha, código OTP, cookie, token ou URL completa de callback. Não recadastrar OTP.

Repetir com visitante após fechar todas as janelas anônimas: senha+OTP válidos devem terminar em **403**, sem JSON da API. Ambos os caminhos foram confirmados pela autora. Na operadora, `/oauth2/userinfo` permite conferir grupo da sessão sem copiar token; registrar só o grupo esperado, não o ID de usuário nem resposta integral.

Sem sessão, `/` e `/health` retornam 403 com início de login; `/oauth2/auth` retorna 401. Headers de identidade enviados pelo cliente não autorizam. Cookie de sessão conferido pela autora: HttpOnly, SameSite=Lax, Secure desmarcado e Path `/`; host-only na configuração/headers. Não exportar valores. Não inferir atributos de todos os cookies Keycloak a partir desses atributos do gateway.

## 5. Sessão, logout, falhas e preservação

Logout local do gateway: **http://app.localhost:4180/oauth2/sign_out?rd=/oauth2/sign_in**. Atualizar `/health`: não deve liberar JSON. A sessão Keycloak pode continuar ativa na interface de conta. Sair também dela e confirmar senha+OTP em novo login. Autora validou as duas camadas; não há promessa de single logout.

### Expiração e retirada de grupo

1. Em sessão limpa da operadora, anotar horário do JSON e atualizar `/health` a cada 30 s sem novo login. Acesso deve cessar em aproximadamente cinco minutos; anotar último sucesso/primeiro bloqueio. Requisições não devem renovar prazo.
2. Com sessão Keycloak ainda existente, iniciar novo login da aplicação: deve exigir senha+OTP novamente.
3. Para testar revogação, manter sessão antiga na janela anônima; usar janela normal separada para login novo. **Abas ou janelas anônimas do mesmo perfil compartilham cookies.**
4. Com autorização para o teste, retirar apenas associação da operadora ao grupo pela administração local; registrar horário e configuração anterior, sem mexer em senha/OTP. Login novo deve resultar 403 e acesso antigo cessar até cinco minutos após retirada, podendo cessar antes.
5. Restaurar a associação original e confirmar novo login positivo. Não deixar a operadora sem permissão ao terminar. Resultados entregues são medições manuais aproximadas, não cronometragem automática em segundos.

### Falhas controladas e retomada

Com login da operadora recém-concluído e janela aberta, parar **somente** API:

```powershell
docker compose -f compose.yaml -f compose.identity.yaml stop api
# Autora atualiza a página autenticada: esperado 502, não JSON nem falso sucesso.
docker compose -f compose.yaml -f compose.identity.yaml up -d --wait --wait-timeout 60 api
docker compose -f compose.yaml -f compose.identity.yaml --profile tools run --rm --no-deps probe
# Confirmar retorno do JSON no navegador; se sessão expirou, informar novo login.
```

Em teste separado, parar somente Keycloak e tentar login em sessão limpa; deve falhar ao acessar o provedor, sem concluir autenticação. Sessão gateway anterior pode funcionar até expirar: não é revogação instantânea.

```powershell
docker compose -f compose.yaml -f compose.identity.yaml stop keycloak
# Confirmar falha de novo login antes de retomar.
docker compose -f compose.yaml -f compose.identity.yaml start keycloak
./scripts/Test-IdentityDiscovery.ps1
docker compose -f compose.yaml -f compose.identity.yaml --profile tools run --rm --no-deps identity-check
```

Para persistência, reiniciar Keycloak, aguardar discovery e reiniciar gateway; conferir prontidão antes de login da operadora e negação da visitante com OTP existente. Não apagar volume/segredos nem recadastrar OTP. No fechamento, a evidência foi retomada real dos containers parados após indisponibilidade do Docker, mais inspeção e novos logins, não instalação limpa.

Parar preservando estado:

```powershell
docker compose -f compose.yaml -f compose.identity.yaml stop oauth2-proxy keycloak api
```

Reiniciar Keycloak preserva realm existente: import de startup usa `IGNORE_EXISTING`. Alterar template não atualiza realm já importado. Corrigir conscientemente o recurso divergente; não apagar/recriar o realm ou volume para sincronizar JSON. Mudança de client secret deve ser sincronizada no Keycloak e no arquivo local do gateway; não rodar o inicializador outra vez.

## 6. Testes estáticos repetíveis

### Verificador OIDC isolado

Com Docker Linux acessível e imagens da API/proxy já disponíveis, executar da raiz:

```powershell
./scripts/Test-IdentityVerifier.ps1
```

O script lê a configuração versionada e gera cópia com endereços/segredos exclusivamente de teste. Cria dois containers sem portas e uma rede interna temporária, sem conectar ao realm nem ler segredos do lab. O binário real v7.15.5 é exercitado com ID tokens assinados pelo emissor fictício, controle positivo, audiência/issuer/assinatura/nonce/expiração inválidos, grupos ausente/vazio/semelhante, state alterado e cookie emitido/adulterado. São 12 verificações mais resumo final; falha deve interromper, não ser ignorada.

Chaves ficam em memória; config efêmera em `.local/identity-verifier/` e recursos exclusivos dessa execução são removidos ao terminar, sem remover volumes. Se Docker ficar inacessível durante a execução, a limpeza pode não terminar: inspecionar os nomes específicos antes de qualquer ação, nunca executar prune ou limpeza ampla. Não apontar o gateway principal para o emissor diagnóstico.

O harness não substitui login com MFA no navegador, atributos de cookies do realm real ou medição da sessão. Resultados e falhas corrigidas: seção 18 das [evidências](../evidence/02-identity-access.md).

### Templates e regressão da API

```powershell
docker run --rm --network none --cap-drop ALL --security-opt no-new-privileges:true --mount "type=bind,source=$PWD\infra,target=/workspace/infra,readonly" --workdir /workspace secureops-api:0.1.0 node --test infra/identity/config.test.mjs
docker compose --profile tools run --build --rm api-test
```

No fechamento em 25/10: 35 testes API, 10 estáticos de identidade e 12 verificações isoladas aprovados, além de discovery/probe. Nenhuma suite estática substitui navegador/TOTP, sessão em runtime ou autorização real. Evidências distinguem cada origem.
