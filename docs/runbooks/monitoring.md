# Runbook — Monitoramento com Zabbix

**Estado:** entrega 03 concluída em 26/10/2026. Disponibilidade e segurança integradas, quatro widgets, falhas/persistência/regressão e aceite manual aprovados. Token administrativo temporário revogado e negativa confirmada; runtime não depende dele. Contrato: [SPEC 03](../features/03-monitoring/SPEC.md); resultados e limites na matriz final das [evidências](../evidence/03-monitoring.md).

## 1. Limites e dados

- Frontend em **http://localhost:8081/**, publicado somente em `127.0.0.1`; HTTP local aprovado, sem confidencialidade TLS. Somente contas/dados fictícios e senha exclusiva do lab.
- API não publica porta. Banco/server não publicam 5432/10051. Não abrir portas no roteador, túneis ou acesso externo.
- `zabbix-db-data` contém configuração, histórico e contas do painel. Não remover o volume, apagar eventos, resetar banco ou rerodar bootstrap para repetir testes.
- `.local/monitoring/` contém segredos do banco/coletor e arquivos ignorados da validação. Preserve segredos e volumes; não abrir valores no chat, exportá-los, incluí-los em screenshots ou versioná-los.
- PostgreSQL executa como usuário de SO 999; papel bootstrap `postgres` fica somente no banco. Server/frontend usam role `zabbix`, sem superuser/createdb/createrole/replication. TCP exige SCRAM; socket local usa peer para o usuário postgres dentro do container.
- O secret é carregado pelo entrypoint e pode existir na configuração interna gerada do serviço. Não exportar arquivos de configuração, ambiente ou filesystem dos containers sem revisão; montá-lo como arquivo não é um cofre de segredos.
- Não há TLS interno; `operations` é bridge não interna. Host e daemon são confiáveis, sem alegar isolamento absoluto ou egress bloqueado.

## 2. Inicialização — instalação nova versus ambiente existente

Somente numa instalação **nova**, com Docker Linux e as três imagens fixadas disponíveis:

```powershell
./scripts/Initialize-Monitoring.ps1
./scripts/Test-MonitoringInfrastructure.ps1
```

O inicializador usa aleatoriedade criptográfica, grava sem BOM/newline e restringe a ACL ao usuário atual antes de criar arquivos. Recusa pasta existente e não faz rotação/reset. No ambiente entregue, já foi executado; **não executar de novo**. Não imprimir `docker compose config` completo; o verificador processa o JSON em memória e mostra somente nomes/resultados dos checks.

```powershell
docker compose -f compose.yaml -f compose.monitoring.yaml up -d --no-deps --pull never --wait --wait-timeout 180 zabbix-db
docker compose -f compose.yaml -f compose.monitoring.yaml up -d --no-deps --pull never --wait --wait-timeout 180 zabbix-server zabbix-web
./scripts/Test-MonitoringInfrastructure.ps1 -Runtime
```

Pare se qualquer comando falhar; preserve dados. `--pull never` exige imagens locais com os digests da SPEC; downloads iniciais requerem internet. O banco pode criar schema apenas no primeiro volume vazio. Se a inicialização falhar parcialmente, não apagar o volume nem repetir SQL manualmente sem diagnóstico.

Aviso de “orphan containers” ao usar só dois arquivos é esperado porque identidade usa outro overlay. **Nunca seguir a sugestão `--remove-orphans`.** Os comandos acima selecionam somente os novos serviços e não reiniciam API/Keycloak/gateway.

O health check do frontend usa `/ping`; ele **não comprova login, MFA ou cenário web**. Server não possui health check na imagem; `up --wait` sozinho não garante import/prontidão do server. O verificador também consulta `dbversion`; as evidências iniciais confirmam a mensagem real de início do processo principal. Nenhum desses checks demonstra que um monitor já foi configurado.

## 3. Primeiro acesso manual e configuração de disponibilidade

1. Abrir **http://localhost:8081/**. Acesso anônimo ao dashboard deve apresentar aviso de não autenticado, sem dados administrativos, mesmo que o status HTTP seja 200.
2. Entrar com a credencial inicial oficial do Zabbix, somente no ambiente local: [documentação de primeiro login](https://www.zabbix.com/documentation/7.0/en/manual/quickstart/basic_config/login). Nunca reutilizar senha pessoal.
3. Em **Users → Users → Admin**, alterar a senha por uma exclusiva e guardar fora do repositório/chat. Não trocar senha do banco nem editar o banco para fazer login.
4. Conferir que `guest` continua no grupo **Disabled**, com status desabilitado. Na imagem executada já veio assim; não é necessário alterar grupos apenas por precaução. Não habilitar guest para contornar erro de acesso.
5. Sair do painel, confirmar que a página protegida volta ao aviso/login e entrar novamente com a nova senha. Registrar só sucesso/erro, sem compartilhar senha ou cookie.

Depois dessa confirmação, seguir T03 do PLAN para configuração do host/cenário/trigger. O host padrão `Zabbix server` veio habilitado e tenta agente em loopback; não há agente instalado. Desabilitar seu monitoramento pela UI ao configurar o host do laboratório; isso não para o serviço Zabbix server. Não importar templates externos ou habilitar verificações cloud.

### Importar host, cenário e triggers — executado no ambiente atual

O arquivo [availability-host.json](../../infra/monitoring/availability-host.json) contém apenas um grupo/host fictícios, um cenário e duas triggers, sem credenciais, interfaces de agente ou referências à identidade. Não é um export do banco real nem depende de senha salva em script.

1. Sair e entrar com a nova senha, sem compartilhá-la. Em **Data collection → Hosts**, confirmar que não existe outro host `secureops-api`. Se já existir, não sobrescrever: interromper e revisar sua configuração primeiro.
2. Clicar **Import** e selecionar `infra/monitoring/availability-host.json` na pasta deste repositório.
3. Nas regras, permitir **Create new** para host groups, hosts, web scenarios e triggers. Não habilitar **Delete missing**. Para o primeiro import, não é necessário atualizar entidades existentes. Conferir a prévia: somente grupo `SecureOps Lab`, host `secureops-api`, cenário `api-health` e duas triggers novas. Se houver alterações inesperadas, cancelar.
4. Confirmar **Import**. Não corrigir erro de import editando o banco, habilitando guest ou expondo a API. Informar apenas mensagem sanitizada de erro, se ocorrer.
5. Aguardar até 60 s pela primeira execução e depois pelo menos duas execuções saudáveis. Em **Monitoring → Hosts**, filtrar `secureops-api` e abrir **Web**: cenário `api-health` deve indicar execução bem-sucedida. Em **Latest data**, conferir código 200 da etapa `health` e valor 0 de `web.test.fail[api-health]`. Interface web pode renderizar nome amigável em vez da key.
6. Em **Data collection → Hosts**, desabilitar somente o host padrão **Zabbix server**, que não possui agente nesta entrega. Não parar o serviço/container e não alterar o host `secureops-api`.

Antes de repetir ensaio, confirmar importação e duas execuções saudáveis. Valores iniciais ausentes não comprovam saúde; verificar amostras recentes, não somente ausência de problemas. No ambiente atual a importação e os dois ciclos já foram confirmados; não reimportar nem sobrescrever o host para repetir testes.

Configuração implementada: GET interno em `http://api:3000/health`, intervalo 20 s, timeout 5 s, uma tentativa, somente 200 e sem redirects. Trigger de falha usa `last(...web.test.fail...)<>0`; trigger técnica separada usa `nodata(...,90s)=1`. Sem fechamento manual nem notificações. API/SQL usam `retries`; export usa `attempts`. Falha da API é diferente de perda de observação; o Zabbix parado não monitora a si mesmo em tempo real.

### Validar arquivo sem acessar o ambiente real

```powershell
./scripts/Test-MonitoringAvailabilityConfig.ps1
```

Executa oito testes Node sem rede e sete verificações com schema/parser originais do Zabbix 7.0.32 via PHP-FPM efêmero. A imagem não contém PHP CLI: um cliente mínimo FastCGI usa rede interna exclusiva de teste, sem porta no host, banco, credenciais, volume persistente ou acesso às redes reais. O harness remove apenas seu próprio container/rede. Não baixa pacotes/imagens; exige imagens já locais. Falhas de cleanup geram aviso e nome do recurso exclusivo.

Aceitar schema/gramática **não comprova importação, semântica/vinculação dos itens, intervalo real ou trigger funcionando**. Coletas posteriores comprovaram importação, ciclos, negativos e integração separadamente. Itens web têm defaults nativos (histórico 30 d/tendências 90 d); override de histórico 7d foi aplicado via housekeeping.

### Repetir dois ciclos de disponibilidade — teste com interrupção intencional

```powershell
# Primeiro, leitura apenas; nao para servicos:
./scripts/Test-MonitoringAvailability.ps1

# Somente quando for oportuno interromper a API por dois ciclos:
./scripts/Test-MonitoringAvailability.ps1 -RunFailureCycles
```

O script usa somente SELECTs para observar configuração, amostras e eventos nativos, sem configurar/alterar Zabbix por SQL ou pedir senha do painel. Recusa iniciar o ensaio sem duas amostras saudáveis recentes, triggers/configuração compatíveis, API healthy e relógios coerentes. Usa a composição completa: para somente API, aguarda problema/três amostras falhas, retoma API e exige recuperação/probe. Repete duas vezes e verifica que os outros **seis** serviços, inclusive coletor, não reiniciaram; esse modo de intervenção exige o laboratório completo ativo.

O `finally` tenta retomar a API que o script parou se qualquer verificação falhar; não é garantia de recuperação se Docker/build/host estiver indisponível. Não remover dados para contornar falha. Datas/eventos usam segundos; detecção pode acontecer entre início do comando e confirmação de parada. Nesse caso o script registra `detectedBeforeStopConfirmation=true` e diferença negativa em relação à confirmação, não uma latência física negativa. Duração observada do problema é diferente da duração exata da indisponibilidade.

### Aplicar retenção aprovada e retirar ruído do host padrão — executado

1. Em **Data collection → Hosts**, desabilitar somente o host de fábrica **Zabbix server**. Isso interrompe a coleta de um agente que não instalamos, não o container do monitor. Não excluir o host nem parar serviços.
2. Em **Administration → Housekeeping**, seção **Events and alerts**, manter internal housekeeping habilitado e alterar **Trigger data storage period** para `7d`. Não alterar períodos de outras categorias por conveniência.
3. Na seção **History**, manter internal housekeeping habilitado, marcar **Override item history period** e definir **Data storage period** como `7d`. Salvar com **Update**.
4. Não clicar em Reset defaults nem executar limpeza manual/housekeeper forçado. A política é aplicada a expurgo futuro; não há exigência de apagar registros para demonstrar funcionamento. Itens web podem continuar exibindo history=30d no cadastro, pois o override global prevalece.

Defaults reais observados antes da alteração: eventos de trigger 365d, history override desabilitado, history global 31d não efetivo; itens web com history 30d/trends 90d. Trends permanecem com default dos itens, sem override global; sete dias aprovados aqui se referem a histórico bruto e eventos de trigger, não a agregados de tendências. Registrar separadamente política configurada e remoção efetivamente observada.

Referência da versão: [Housekeeping 7.0](https://www.zabbix.com/documentation/7.0/en/manual/web_interface/frontend_sections/administration/housekeeping). Após salvar, conferir por leitura da configuração antes de marcar retenção aplicada. Resultados de dashboard/negativos no PLAN/evidências.

Na coleta de 12:20 (-03:00), verificados eventos de trigger 7d, history override 7d e housekeeping habilitado nas duas categorias; host padrão desabilitado e API habilitada. Sem expurgo forçado ou comprovação de remoção após sete dias. Não alterar novamente esses campos para repetir a demonstração.

### Criar dashboard mínimo de disponibilidade — executado

1. Em **Dashboards**, criar dashboard **SecureOps Lab**. Se já existir um dashboard com esse nome, abri-lo em modo de edição, sem excluir/substituir trabalho existente.
2. Adicionar widget **Web monitoring**, título **Disponibilidade da API**; filtrar **Host groups = SecureOps Lab** e **Hosts = secureops-api**. Não deixar filtro vazio, que inclui outros hosts/grupos. Usar refresh de 30s quando disponível.
3. Adicionar widget **Problems**, título **Problemas ativos da API**; **Show = Problems**, **Hosts = secureops-api** e mostrar tags se desejado. Não aplicar filtro somente de severidade alta, para não esconder o alerta Warning de perda de coleta.
4. Salvar com **Save changes**. Em **Sharing**, manter **Private**, sem compartilhamento adicional. Não criar acesso guest/publicação externa ou relatório por e-mail.
5. Atualizar a página e verificar que o dashboard salvo continua disponível. Com a API saudável, esperado um cenário Ok, zero Failed e zero Unknown no widget web e nenhum problema ativo do host. Não inferir saúde somente de widget de problemas vazio; conferir também execução recente do cenário.

O widget web é resumo de cenários e não substitui nodata; último estado antigo não comprova saúde atual. Na integração foram acrescentados dois widgets de item reais: última contagem válida de LOGIN_ERROR e qualidade (1 válida/0 falha), com horário e títulos avisando para conferir a coleta. Ambos podem mostrar valores históricos: sempre olhar horário e problemas técnicos. Não são cartões estáticos nem prova de ataque.

Procedimento baseado na documentação 7.0 de [Dashboards](https://www.zabbix.com/documentation/7.0/en/manual/web_interface/frontend_sections/dashboards), [Web monitoring](https://www.zabbix.com/documentation/7.0/en/manual/web_interface/frontend_sections/dashboards/widgets/web_monitoring) e [Problems](https://www.zabbix.com/documentation/7.0/en/manual/web_interface/frontend_sections/dashboards/widgets/problems). Autora confirmou o resultado e a configuração salva foi conferida por SELECT: privado, sem shares e com os dois filtros esperados. Isso não é captura autenticada de navegador pelo agente.

### Testar persistência — disponibilidade e integração executadas

```powershell
# Somente leitura, por padrao:
./scripts/Test-MonitoringPersistence.ps1

# Interrompe temporariamente APENAS os tres componentes do monitoramento:
./scripts/Test-MonitoringPersistence.ps1 -RunRestartAndRecreate

# Laboratorio completo, incluindo coletor e historico de dois ciclos de seguranca:
./scripts/Test-MonitoringPersistence.ps1 -IncludeCollector
./scripts/Test-MonitoringPersistence.ps1 -RunRestartAndRecreate -IncludeCollector
```

Executar com os serviços necessários ativos e API/banco/frontend healthy, depois de dashboard/retenção configurados. O script exige quatro eventos de ciclos anteriores e duas amostras saudáveis para snapshot público selecionado, sem senhas/hashes/tokens/sessões/dumps. Compara configuração/IDs, dashboard/filtros, retenção, metadados de contas/grupos, eventos e amostras antigas, sem sobrescrever estado divergente. Com -IncludeCollector exige sete serviços, quatro widgets, três itens e quatro eventos anteriores/duas amostras de autenticação. Sem histórico suficiente, repetir os ciclos em momento autorizado, não fabricar registros.

Na primeira fase, para frontend/server, reinicia banco e, se incluído, coletor; retoma os mesmos containers. Na segunda, recria somente componentes selecionados de monitoramento com --force-recreate/--no-deps e **mesmo volume**, sem excluir dados. Cada fase exige duas amostras saudáveis novas e, com coletor, duas qualidades válidas novas em até 120s; API/Keycloak/gateway preservados. Finally tenta retomar sem remover recursos; não garante recuperação se host/Docker falhar. Retestar login real com a autora após o ensaio; metadados iguais não comprovam autenticação.

As duas formas foram exercitadas; a integrada preservou configuração/histórico selecionados e quatro widgets. Reconstrução de janela real não vazia do coletor é ensaio separado, na seção 7. Não monitoramos continuamente enquanto server está parado. Depois da recriação, repetir ciclos da API; isso foi feito e deixou API saudável, com outros seis serviços intactos.

### Confirmar sessão do painel após recriação — confirmado manualmente pela autora

1. Sair do Zabbix e tentar abrir novamente o dashboard protegido: deve pedir login ou mostrar aviso de não autenticado, sem seus dados administrativos. Não confundir HTTP200 da página de aviso com liberação.
2. Entrar com a senha exclusiva nova, verificar dashboard e estado atual da API. Não enviar senha/captura da tela de login.
3. No Chrome/Edge, abrir **F12 → Application → Cookies → http://localhost:8081** e localizar `zbx_session`. Registrar **somente** HttpOnly, Secure, SameSite, Path e Domain, sem copiar o Value, decodificar cookie, exportar HAR ou enviar screenshot com valores.

Análise estática da imagem 7.0.32: CCookieSession usa zbx_session; CCookieHelper chama setcookie com HttpOnly=true, Secure dependente de HTTPS e domínio vazio, sem SameSite explícito nesse helper. Portanto espera-se Secure desmarcado no HTTP local aprovado; **não presumir SameSite=Lax explícito**: registrar exatamente o navegador, inclusive campo vazio/ausente. O navegador pode aplicar comportamento padrão sem que esse atributo tenha sido emitido. Path/domínio devem ser observados, não inventados a partir da configuração de cookies do gateway.

Essa leitura de código não comprova atributos autenticados em runtime, logout ou login após persistência. Se algum atributo/comportamento divergir, investigar sem relaxar proteções ou compartilhar credenciais. Não foi concedida exceção para continuar usando senha padrão.

Resultado manual em 25/10/2026: autora confirmou logout, dashboard exigindo login e entrada com senha nova após recriação. Informou HttpOnly marcado, Secure desmarcado, SameSite vazio, Path=/ e Domain=localhost. Origem e limites, inclusive tratamento de compartilhamento involuntário de cookie seguido de logout, na seção 11 das evidências. Nenhum valor deve ser copiado ao repositório; essa confirmação não é teste de replay da sessão encerrada.

## 4. Verificação de infraestrutura e regressão

`Test-MonitoringInfrastructure.ps1` valida configuração base/overlay completo, API inalterada, imagens fixadas, redes, usuários, capabilities, segredos por arquivo e publicações. `-Runtime` também inspeciona containers, role do banco, schema e ping. Restrições/endpoint do coletor são verificados separadamente por `Test-MonitoringCollector.ps1 -Runtime`.

Regressão usada na coleta inicial:

```powershell
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile tools run --build --rm api-test
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile tools run --rm --no-deps probe
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile tools run --rm --no-deps identity-check
./scripts/Test-IdentityVerifier.ps1
```

Os dez testes estáticos de identidade mantêm o comando do [runbook de identidade](identity-access.md#6-testes-estáticos-repetíveis). Nenhuma suite substitui logins reais com a autora ou verificação de eventos do Keycloak.

## 5. Coleta de eventos — provisionada e integrada

O realm agora armazena **somente LOGIN_ERROR por 86400 s**, após aprovação explícita do recorte mínimo. Antes: armazenamento desabilitado, 102 tipos padrão retornados e nenhuma retenção explícita. Listener e eventos administrativos foram preservados; nenhum evento foi apagado. A configuração anterior fica apenas em `.local/monitoring/events-config-before.json`, ignorada, para diagnóstico. Não a reaplicar sem revisão.

O client `secureops-event-reader` é confidencial, sem login interativo/password grant/redirects, fullScopeAllowed=false e somente `realm-management/view-events` em role/scope da service account. Essa permissão lê eventos do **realm inteiro**; o recorte por client no coletor não é ACL do Keycloak. Um PUT da configuração atual, sem mudança efetiva, foi negado com 403 e o estado permaneceu igual. Nunca testar DELETE de eventos.

### Instalação nova, somente após aprovação do recorte

```powershell
./scripts/Initialize-MonitoringSecurity.ps1
./scripts/Provision-MonitoringEventReader.ps1                       # somente leitura
./scripts/Provision-MonitoringEventReader.ps1 -ApplyLoginErrorOnly   # aplica uma unica vez
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile monitoring-security build identity-event-collector
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile monitoring-security up -d --no-deps --pull never identity-event-collector
./scripts/Test-MonitoringCollector.ps1
./scripts/Test-MonitoringCollector.ps1 -Runtime
```

**No ambiente atual, segredos/client/eventos já foram provisionados. Não repetir os comandos de criação/aplicação.** Os scripts recusam sobrescrita/client existente; falha parcial exige diagnóstico, não reset. `Provision-MonitoringEventReader.ps1` sem flag é inspeção administrativa efêmera; lê bootstrap local em memória, não grava token e não faz parte do runtime. O snapshot selecionado de identidade compara gateway, usuários/grupos e IDs/tipos/datas de credenciais, sem exportar senhas ou sementes OTP. Não substitui regressão manual.

O runtime recebe apenas três arquivos read-only: segredo do client, segredo das métricas e ID interno do realm. Esse ID é diferente do nome `secureops-lab` e permite conferir `realmId` dos eventos, sem conceder configuração arbitrária ao chamador. Sem porta publicada, socket, volume Keycloak ou credencial administrativa; somente redes monitoring+identity e 128 MiB, rootfs read-only e usuário node.

O código TypeScript usa apenas sintaxe apagável suportada nativamente pelo Node 24.22.1, com checagem --strict separada na imagem local de testes. Sem dependências novas. Runtime reutiliza imagem local versionada da API, que deve existir antes do build. Leitura sob demanda: processo ativo sozinho não prova saúde; conferir qualidade/frescor do item. Integração atual foi aplicada e validada pela API oficial.

### Token temporário para configurar/testar Zabbix — revogado no fechamento

1. Em **Users → API tokens** (ou **User settings → API tokens**), revogar o token divulgado na conversa. Não usá-lo novamente.
2. Criar um token novo para Admin, `secureops-validacao-03`, habilitado e com expiração curta. Gerar/copiar somente localmente.
3. No PowerShell, aberto na pasta do projeto, executar:

```powershell
./scripts/Save-MonitoringApiToken.ps1
```

4. Colar o **novo** token exclusivamente no prompt oculto desse terminal e pressionar Enter. O arquivo `.local/monitoring/zabbix-api-token` é criado sem sobrescrita, na pasta ignorada com ACL restrita. Não enviar token, print, HAR, senha ou cookie ao chat. Informar apenas “arquivo salvo”.

Para repetir depois da revogação, preserve o arquivo antigo: mova-o manualmente para um nome único dentro da mesma pasta ignorada antes de salvar o novo. Não sobrescrever automaticamente, reativar token divulgado ou imprimir valores. Esses tokens só são necessários durante administração/testes pela API, nunca na operação normal.

`Configure-MonitoringSecurity.ps1` inspeciona por padrão. Em instalação nova, depois de disponibilidade/dashboard mínimo e coletor válidos, `-Apply` cria macro secreta, três itens e duas triggers e acrescenta dois widgets sem substituir os atuais. **No ambiente atual já foi aplicado: não repetir -Apply.** Recusa itens/macro existentes; em falha parcial, preservar e diagnosticar sem sobrescrever. Marcador local security-zabbix-created.json contém somente referências de objetos criados. Os 14 testes locais de contrato/API não substituem aceitação e execução reais, verificadas separadamente.

Tipo secret da macro mascara a exibição; não é prova de criptografia em repouso ou cofre de segredos. Não exportar seu valor nem o banco, e não apresentar HTTP local como transporte cifrado.

```powershell
./scripts/Configure-MonitoringSecurity.ps1          # leitura, exige token temporario valido
# SOMENTE numa nova configuracao, sem itens/macro de seguranca:
./scripts/Configure-MonitoringSecurity.ps1 -Apply
```

Se o preflight informar **API token expired**, editar o token novo na UI, manter Enabled, mudar Expires at para data futura e salvar com Update, sem Generate. Essa edição preservou o valor local no ensaio. Não usar SQL, trocar senha ou relaxar autorização para contornar negativa. Após o ajuste, repetir primeiro somente leitura. No fechamento, o token temporário foi revogado e a negativa real confirmada.

### Modos de operação

```powershell
# Exige token temporario valido; recusa desabilitar com problema de seguranca ativo:
./scripts/Set-MonitoringSecurityMode.ps1 -Mode availability
# No modo disponibilidade, parar coletor separadamente, sem apagar historico:
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile monitoring-security stop identity-event-collector

# Retomar modo completo (identidade pronta), sem recriar dados:
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile monitoring-security up -d --no-deps --pull never identity-event-collector
./scripts/Set-MonitoringSecurityMode.ps1 -Mode full
```

availability desabilita três itens/duas triggers; full habilita e exige duas qualidades novas válidas. Cenário api-health não muda. Não basta retirar o profile Compose, pois ele não altera o banco. Se houver problema ativo, investigar/recuperar legitimamente antes de mudar para disponibilidade; não apagar eventos ou fechar manualmente para esconder alerta. No estado entregue, **full habilitado**.

Ao terminar administração/testes, desabilitar/excluir somente o token temporário pela UI e executar `./scripts/Test-MonitoringTokenRevoked.ps1`. Testado: token deixou de autorizar leitura e coletor permaneceu válido. Arquivo local preservado; remoção exige autorização, nunca limpeza ampla.

## 6. Retomar ambiente existente

Se engine estiver parado, `docker desktop start` foi exercitado no Windows. Não iniciar outros projetos. Com imagens/segredos/volumes existentes:

```powershell
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile monitoring-security up -d --no-recreate --no-deps --pull never --wait --wait-timeout 180 api keycloak zabbix-db
# Aguarda prontidao real de Keycloak; running nao basta:
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile tools run --rm --no-deps identity-check
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile monitoring-security up -d --no-recreate --no-deps --pull never --wait --wait-timeout 180 oauth2-proxy zabbix-server zabbix-web identity-event-collector
./scripts/Test-MonitoringInfrastructure.ps1 -Runtime
./scripts/Test-MonitoringCollector.ps1 -Runtime
./scripts/Test-MonitoringAvailability.ps1
```

Se discovery falhar por inicialização ainda em curso, aguardar de forma limitada e repetir o check (o helper wait-keycloak.mjs usa prazo de 90s na automação dos testes). Não avançar ao gateway antes do discovery válido. No ensaio de retomada, gateway saiu quando Keycloak ainda não estava pronto e retomou normalmente após discovery. `start --wait` não existe no Compose validado; usar `up --no-recreate --wait`. Não excluir volumes ou importar realm de novo.

## 7. Reproduzir negativos e ciclos de segurança

**Interrupções intencionais somente no laboratório.** Combinar o momento com a autora, conferir sete serviços e deixar a configuração full ao final. Scripts administrativos abaixo exigem novo token local temporário; o token do fechamento já foi revogado. Não reenviar valores no chat.

```powershell
# Offline: 39 coletor + TypeScript strict + 14 contrato/API + 2 alvo ficticio:
./scripts/Test-MonitoringCollector.ps1
# Confirmacao real de leitura/escrita negada, PUTs iguais aos valores atuais:
./scripts/Provision-MonitoringEventReader.ps1 -VerifyPermissions
# Host/container ficticios exclusivos; cleanup so dos proprios recursos:
./scripts/Test-MonitoringNegatives.ps1
# Pausa apenas http poller; nao API/avaliador; CONT em finally + watchdog 180s:
./scripts/Test-MonitoringNoData.ps1 -RunNoData
```

Negativos fictícios exercitam 500/302, início sem contagem, qualidade inválida, credencial/config/teto e master unsupported/obsoleto sem recuperar autenticação. A API principal nunca aponta para o auxiliar. Controle/métricas do alvo exigem chave aleatória efêmera exclusiva, criada em arquivo ignorado com ACL herdada restrita e montada read-only; não compartilha segredo do runtime real. Cleanup remove somente chave/container/host/histórico fictícios próprios. `./scripts/Test-MonitoringNegatives.ps1 -VerifyTargetOnly` valida autenticação/HTTP do alvo em containers e cleanup sem chamar Zabbix ou usar token administrativo, inclusive após revogação. Nodata deve abrir em 90–120s desde última amostra, não exatamente aos 90; falha do host/Docker pode impedir finally/watchdog.

### Dois ciclos reais, sem apagar eventos

1. `./scripts/Observe-MonitoringSecurity.ps1 -Phase clean`: esperar fonte e Zabbix zero/qualidade válida. Relógios incoerentes ou janela inesperada bloqueiam conclusão; não ajustar timestamps para passar.
2. Autora abre aplicação em janela anônima nova, conta fictícia existente, envia **uma** senha deliberadamente errada e para. Executar `./scripts/Observe-MonitoringSecurity.ps1 -Phase one -Cycle 1`: deve observar um LOGIN_ERROR e nenhum alerta.
3. Autora envia quatro adicionais erradas, sem senha correta/OTP; executar `./scripts/Observe-MonitoringSecurity.ps1 -Phase threshold -Cycle 1`. Script exige cinco eventos na fonte, abertura até 60s e três amostras/um problema. Se quantidade divergir, consultar status e registrar eventos observados, não inventar número de submissões.
4. Com problema aberto, `./scripts/Test-MonitoringSourceFailure.ps1 -Component keycloak -RunFailure`: para só a fonte, espera técnico sem zero/recuperação falsa, retoma mesmo volume e exige discovery/consulta completa. API saudável; sessão gateway existente pode persistir até prazo normal.
5. `./scripts/Observe-MonitoringSecurity.ps1 -Phase recovery -Cycle 1`, depois `-Phase clean`: aguardar recuperação/esvaziamento natural sem excluir eventos. Janela é inclusiva de 300s; os eventos saem pelo relógio, não por sucesso de login.
6. Repetir passos 2–3 usando `-Cycle 2`. Com janela=5 e tempo remanescente suficiente: `./scripts/Test-MonitoringCollectorPersistence.ps1 -RunRestartAndRecreate` comprova novas amostras=5 após restart/recreate, sem volume de eventos no coletor.
7. Ainda com autenticação aberta: `./scripts/Test-MonitoringSourceFailure.ps1 -Component identity-event-collector -RunFailure`. Esperar nodata/problema técnico até 120s, sem zerar/recuperar alerta; retomar e aceitar recuperação somente com consulta completa. Se a janela cair durante a parada, amostra válida <5 pode recuperar depois da retomada — isso não é falsa recuperação.
8. `./scripts/Observe-MonitoringSecurity.ps1 -Phase recovery -Cycle 2`, depois `-Phase clean`. Repetir persistência integrada/ciclos API e confirmar login/dashboard com a autora, conforme seção 3.

O observador administrativo publica só contagens, timestamps e categorias permitidas; eventos brutos/tokens ficam na memória. Saturação de 1001/bytes é fixture, não carga real no Keycloak. Regra agrega eventos por client, não pessoas, IPs ou ataque confirmado. Não mudar brute force/MFA para gerar eventos; no ambiente, bruteForceProtected=false era preexistente e não foi introduzido para teste.

Para comprovar sucesso/403 sem incremento: executar `Observe-MonitoringSecurity.ps1 -Phase positive-before` em janela limpa; autora faz logins corretos de operadora e visitante em sessões limpas; executar `-Phase positive-after` em até 15 min. A consulta cobre desde o início registrado, sem descartar falhas antigas favoravelmente. Resultado deve ser zero LOGIN_ERROR, qualidade válida e relato manual de acesso/403. Não confundir 403 do gateway com erro de autenticação do Keycloak.

### Artefatos de ensaio e repetição

Marcadores em `.local/monitoring/validation-state/` são ignorados, com agregados/referências, não backups nem provas imutáveis. Scripts recusam sobrescrever o início de ciclos/ensaios para não mascarar resultados anteriores. Para nova rodada, **preservar e arquivar manualmente em subpasta única** somente: security-cycle-1.json, security-cycle-2.json, availability-nodata.json, outage-keycloak.json, outage-identity-event-collector.json e positive-logins.json. Manter security-zabbix-created.json, que referencia itens/triggers existentes. Não apagar/recriar recursos reais ou reexecutar -Apply para limpar marcadores. Nunca mover/expor os arquivos de segredo como se fossem evidências públicas.

`./scripts/Test-MonitoringFinal.ps1` exige esse histórico selecionado e token válido, confere itens/macro secreta/headers/triggers/dashboard/eventos sem exportar valores. Executar antes de revogar o token. `Test-MonitoringTokenRevoked.ps1` é a última negativa administrativa; operação normal e probes do coletor continuam sem ele.

## 8. Parada preservando dados

## 6. Parada preservando dados

Quando for necessário parar **somente monitoramento**, sem remover containers/volumes:

```powershell
docker compose -f compose.yaml -f compose.monitoring.yaml stop zabbix-web zabbix-server zabbix-db
```

O comando não para o coletor. Para parar também esse componente, acrescentar separadamente `docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile monitoring-security stop identity-event-collector`. Não usar `down -v`, limpeza ampla ou reset de segredos. Antes de ensaios, confirmar serviços e registrar retomada. No estado entregue, sete serviços ativos e modo full habilitado. n8n, notificações e tratamento persistente de incidentes ainda não implementados.
