# Runbook — Monitoramento com Zabbix (parcial)

**Estado:** infraestrutura de disponibilidade executada em 25/10/2026. PostgreSQL, server e frontend ativos; configuração do cenário web, dashboard e testes de queda/recuperação ainda pendentes. Coletor de segurança não implementado. Contrato: [SPEC 03](../features/03-monitoring/SPEC.md); resultados: [evidências](../evidence/03-monitoring.md).

## 1. Limites e dados

- Frontend em **http://localhost:8081/**, publicado somente em `127.0.0.1`; HTTP local aprovado, sem confidencialidade TLS. Somente contas/dados fictícios e senha exclusiva do lab.
- API não publica porta. Banco/server não publicam 5432/10051. Não abrir portas no roteador, túneis ou acesso externo.
- `zabbix-db-data` contém configuração, histórico e contas do painel. Não remover o volume, apagar eventos, resetar banco ou rerodar bootstrap para repetir testes.
- `.local/monitoring/` contém segredos do banco. Preserve pasta e volume juntos; não abrir segredos no chat, exportá-los, incluí-los em screenshots ou versioná-los.
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

## 3. Primeiro acesso manual — próximo gate

1. Abrir **http://localhost:8081/**. Acesso anônimo ao dashboard deve apresentar aviso de não autenticado, sem dados administrativos, mesmo que o status HTTP seja 200.
2. Entrar com a credencial inicial oficial do Zabbix, somente no ambiente local: [documentação de primeiro login](https://www.zabbix.com/documentation/7.0/en/manual/quickstart/basic_config/login). Nunca reutilizar senha pessoal.
3. Em **Users → Users → Admin**, alterar a senha por uma exclusiva e guardar fora do repositório/chat. Não trocar senha do banco nem editar o banco para fazer login.
4. Conferir que `guest` continua no grupo **Disabled**, com status desabilitado. Na imagem executada já veio assim; não é necessário alterar grupos apenas por precaução. Não habilitar guest para contornar erro de acesso.
5. Sair do painel, confirmar que a página protegida volta ao aviso/login e entrar novamente com a nova senha. Registrar só sucesso/erro, sem compartilhar senha ou cookie.

Depois dessa confirmação, seguir T03 do PLAN para configuração do host/cenário/trigger. O host padrão `Zabbix server` veio habilitado e tenta agente em loopback; não há agente instalado. Desabilitar seu monitoramento pela UI ao configurar o host do laboratório; isso não para o serviço Zabbix server. Não importar templates externos ou habilitar verificações cloud.

**Ainda pendentes:** cenário `api-health`, retenções da UI, dashboard, atributos de cookie autenticado, dois ciclos de disponibilidade, persistência por reinício/recriação e coleta de segurança. Não apresentar login do painel ou ping como conclusão da entrega.

## 4. Verificação de infraestrutura e regressão

`Test-MonitoringInfrastructure.ps1` valida configuração base/overlay completo, API inalterada, imagens fixadas, redes, usuários, capabilities, segredos por arquivo e publicações. `-Runtime` também inspeciona containers, role do banco, schema e ping. Verifica somente infraestrutura implementada; não existe ainda profile/coletor de segurança.

Regressão usada na coleta inicial:

```powershell
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile tools run --build --rm api-test
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile tools run --rm --no-deps probe
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml --profile tools run --rm --no-deps identity-check
./scripts/Test-IdentityVerifier.ps1
```

Os dez testes estáticos de identidade mantêm o comando do [runbook de identidade](identity-access.md#6-testes-estáticos-repetíveis). Nenhuma suite substitui logins reais com a autora ou verificação de eventos do Keycloak.

## 5. Parada preservando dados

Quando for necessário parar **somente monitoramento**, sem remover containers/volumes:

```powershell
docker compose -f compose.yaml -f compose.monitoring.yaml stop zabbix-web zabbix-server zabbix-db
```

Não é o estado deixado pela coleta inicial: os três serviços estão ativos. Não usar `down -v`, limpeza ampla ou reset de segredos. Antes de ensaios de falha, confirmar quais serviços serão parados e registrar a retomada; ainda não executar testes T04 sem configurar o cenário web.
