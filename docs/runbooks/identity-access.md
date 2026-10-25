# Runbook — Identidade e acesso (parcial)

**Estado:** Keycloak executado, duas contas criadas e cadastro/acesso positivo à interface de conta confirmado pela autora para ambas após correção dos scopes em 25/10. Testes negativos, login subsequente da visitante e gateway em runtime pendentes. Não é ainda um procedimento validado de ponta a ponta. Requisitos: [SPEC 02](../features/02-identity-access/SPEC.md). Resultados reais: [evidências](../evidence/02-identity-access.md).

## 1. Limites e arquivos

- HTTP local aprovado, somente contas fictícias exclusivas. Senha/TOTP/cookies não têm confidencialidade de TLS. Não reutilizar credenciais pessoais.
- `compose.yaml` preserva a Fundação. Somar `compose.identity.yaml` nos comandos de identidade; a API continua sem porta e só na rede `service` interna.
- `identity` é bridge **não interna**, após aprovação explícita D04 e falha observada de publicação com rede interna. Keycloak/gateway podem ter saída de rede. Não foi feito teste de egress externo.
- Keycloak publica `127.0.0.1:8080`; gateway, quando autorizado/iniciado, `127.0.0.1:4180`. Não abrir portas adicionais/roteador/túneis.
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

O script de inicialização recusa pasta existente, gera client secret, senha de bootstrap e chave de cookie sem exibi-los. A chave `cookie-secret` tem **32 bytes binários brutos**, pois `cookie-secret-file` no proxy v7.15.5 não decodifica base64. Não abrir esse arquivo binário no editor, não adicionar newline e não copiar exemplos como valores reais.

Antes de executar `identity-check`, construir a imagem local com `docker compose build api` se ainda não existir. O cliente temporário usa essa imagem, sem porta, somente na rede de identidade, e não obtém tokens: testa DNS interno, issuer/endpoints, JWKS e negação HTTP 401 no token endpoint sem client secret. Saída `unauthorized_client` é o erro observado nesta versão. Não comprova MFA ou validação de audiência.

`Test-IdentityDiscovery.ps1` espera até 120 s por metadados do realm, não por um health check de gestão. Usa `curl.exe --resolve` apenas nessa requisição. No Windows testado, `Resolve-DnsName` devolveu NXDOMAIN, mas Chrome headless alcançou `.localhost` em loopback sem alterar o sistema. Isso não garante o comportamento de qualquer outro navegador: testar URLs canônicas no navegador usado na demonstração. Não executar `--remove-orphans`: ao usar só o Compose base, o aviso sobre Keycloak é esperado e não justifica removê-lo.

O template usa `attributes.CreateDefaultClientScopes="true"`, conferido no código da versão 26.8.1, para criar os scopes nativos mesmo com `groups` customizado. Não substituir os scopes nativos por definições parciais: `basic` contém claims básicos e `roles` permite à interface de conta reconhecer as permissões já existentes. O gateway tem somente `basic/profile/email` padrão e `groups` opcional; não se libera a aplicação por roles da interface de conta. O import corrigido foi aceito em container temporário sem rede, portas ou volume do lab, com banco `dev-mem`; isso não é teste de login.

## 3. Próxima interação manual — criar contas (T04 pendente)

1. Abrir **http://keycloak.localhost:8080/admin/master/console/** no navegador. A abertura interativa desta página ainda precisa ser confirmada pela autora.
2. Consultar `.local/identity/keycloak.env` **somente em editor local**. Usar `KC_BOOTSTRAP_ADMIN_USERNAME` e `KC_BOOTSTRAP_ADMIN_PASSWORD` para entrar. Não executar comandos que imprimam o arquivo, nem enviar valores/capturas ao chat.
3. A administradora de bootstrap é temporária e pertence ao `master`; não é a operadora da aplicação. Planejar uma conta administrativa permanente local, testar seu acesso e só então decidir com autorização específica sobre retirar o bootstrap. Não apagá-lo automaticamente nem usar suas credenciais no gateway.
4. Selecionar realm **`secureops-lab`**, não criar contas de aplicação no `master`.
5. Em **Users → Add user**, criar `operadora`, e-mail `operadora@lab.example`, enabled e e-mail verificado. Nome/sobrenome, se exigidos pela interface, devem ser fictícios. Incluir a required action **Configure OTP** (`CONFIGURE_TOTP`). Não marcar e-mail verificado em contas de fora do laboratório: aqui isso é provisionamento fictício, não verificação de caixa postal.
6. Em **Credentials**, definir senha nova e exclusiva do lab, sem compartilhá-la; desativar **Temporary** para evitar uma troca de senha não prevista no cenário. Em **Groups**, associar somente essa conta a **`/secureops-operators`**.
7. Repetir para `visitante`, e-mail `visitante@lab.example`, required action Configure OTP e senha exclusiva, **sem** associação ao grupo permitido.
8. Não atribuir roles administrativas às duas contas. Confirmar que o client `secureops-gateway` usa o override Browser `secureops-browser-mfa`, com **Username Password Form REQUIRED** e **OTP Form REQUIRED**; não alterar o fluxo global para fazer login passar.

Em 25/10, a inspeção administrativa confirmou ambas as contas e a associação correta de grupos. A operadora tem credenciais `password` e `otp`, sem required action pendente; a visitante tem somente `password` e `CONFIGURE_TOTP` pendente. E-mails fictícios foram marcados como verificados na correção autorizada. Isso não comprova login/MFA bem-sucedidos nem autorização no gateway.

### Erro após digitar OTP — reteste após correção de 25/10

O `account-console` estava sem scopes padrão e o realm não tinha `basic`/`roles`. Foram acrescentados esses scopes nativos (definições da própria versão) sem modificar senhas, OTP, grupos ou roles dos usuários. Atribuídos `basic/profile/email/roles` ao `account-console` e `basic` ao gateway; os fluxos MFA permanecem intactos. O reteste de navegador ainda está pendente: existência de credencial OTP e preview de claims não provam que o erro visual desapareceu.

1. Fechar todas as janelas anônimas usadas no laboratório para descartar a sessão/token antigo. Não é necessário limpar o perfil pessoal do navegador.
2. Abrir nova janela anônima em **http://keycloak.localhost:8080/realms/secureops-lab/account/**, não na URL administrativa `/admin/master/console/`.
3. Entrar como `operadora`, com a senha da própria conta e o código atual da entrada **já cadastrada** no autenticador. Não remover/recriar OTP nem escanear outro QR para essa conta.
4. Verificar se a página de conta abre. Se falhar, informar somente a mensagem e a etapa (antes/depois de enviar o OTP); não enviar código, QR, cookies ou URL completa com parâmetros de sessão.
5. Se funcionar, sair e repetir para `visitante`, que ainda deverá apresentar Configure OTP. Cadastrar uma entrada separada no autenticador e confirmar com código válido, sem compartilhar segredos.

O gateway permanece não iniciado. Não confundir acessar a própria conta no Keycloak com autorização para a aplicação; visitante pode gerenciar sua própria conta e ainda assim deve ser negada pelo gateway.

### Cadastro TOTP e testes previstos (ainda não validados)

- TOTP HmacSHA1, 6 dígitos, 30 s e janela de tolerância 1; não ampliar a janela para mascarar relógio incorreto.
- O cadastro deve ocorrer no navegador/autenticador da autora. Não exportar QR/seed e não usar serviços externos de decodificação/JWT/QR.
- A interface de conta `http://keycloak.localhost:8080/realms/secureops-lab/account/` é o caminho proposto para cadastro antes de iniciar o gateway; sua navegação interativa permanece pendente (o ensaio headless excedeu 20 s).
- Concluir Configure OTP com código válido para **cada** conta. Depois sair e repetir autenticação, incluindo ausência de OTP e código incorreto. O primeiro cadastro sozinho não comprova MFA nos logins seguintes.
- Se a interface de conta falhar, registrar o erro sanitizado e revisar a ordem T04/T05 antes de seguir; não criar fluxo alternativo sem MFA nem editar cookies para contornar erro.

## 4. Gateway — arquivo pronto, runtime ainda pendente de T04

A configuração foi aceita por `--config-test`, mas isso não realiza discovery, login, autorização ou criação de cookies.

```powershell
docker compose -f compose.yaml -f compose.identity.yaml run --rm --no-deps oauth2-proxy --config=/etc/oauth2-proxy/oauth2-proxy.cfg --config-test
# Somente após o gate de T04 e retomada da implementação:
docker compose -f compose.yaml -f compose.identity.yaml up -d --wait --wait-timeout 60 api
docker compose -f compose.yaml -f compose.identity.yaml up -d oauth2-proxy
```

Não há health check de container para Keycloak/proxy nesta etapa: não interpretar `up -d` como prontidão. Aguardar o gateway até 60 s por `/ready` com um cliente local e verificar status; essa validação ainda não foi executada. `/ping` e `/ready` são do gateway, **não** `/health` da API.

Testes manuais seguintes ficam no [PLAN T06/T07](../features/02-identity-access/PLAN.md): `/` e `/health` protegidos, `/oauth2/auth` 401 sem sessão, headers forjados rejeitados, operadora 200, visitante autenticada+MFA 403 e nenhum conteúdo upstream. Só coletar atributos do cookie sem seu valor. Janela de sessão/revogação até 5 min exige medição real.

## 5. Logout previsto e preservação

Logout local do gateway: **http://app.localhost:4180/oauth2/sign_out?rd=/oauth2/sign_in**. Isso não garante encerrar a sessão do Keycloak. Encerrar também na interface de conta/admin e confirmar nova exigência de senha+TOTP no client da aplicação. Esses testes continuam pendentes.

Parar preservando estado:

```powershell
docker compose -f compose.yaml -f compose.identity.yaml stop oauth2-proxy keycloak api
```

Reiniciar Keycloak preserva realm existente: import de startup usa `IGNORE_EXISTING`. Alterar template não atualiza realm já importado. Corrigir conscientemente o recurso divergente; não apagar/recriar o realm ou volume para sincronizar JSON. Mudança de client secret deve ser sincronizada no Keycloak e no arquivo local do gateway; não rodar o inicializador outra vez.

## 6. Testes estáticos repetíveis

```powershell
docker run --rm --network none --cap-drop ALL --security-opt no-new-privileges:true --mount "type=bind,source=$PWD\infra,target=/workspace/infra,readonly" --workdir /workspace secureops-api:0.1.0 node --test infra/identity/config.test.mjs
docker compose --profile tools run --build --rm api-test
```

São 10 verificações estáticas de templates/config. A última regressão da API tem 35 testes aprovados, executados em 24/10; não foi repetida na correção restrita de scopes em 25/10. Nenhuma dessas suites substitui navegador/TOTP, validade do cookie em runtime, teste isolado da audiência ou negação de autorização pelo gateway.
