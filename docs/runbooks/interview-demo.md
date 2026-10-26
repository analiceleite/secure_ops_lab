# Demo funcional — preparação para entrevista

## Escopo combinado

A autora pediu priorizar o fluxo mínimo funcional, sem prolongar testes, para validação de conceitos e preparação para a entrevista. **Demo funcional entregue; matriz completa de endurecimento/aceite ainda parcial.** Não é produção nem diagnóstico autônomo.

Fluxo já observado: **Zabbix → receptor → PostgreSQL → n8n → Ollama local → HTML → SMTP → Mailpit**. Action e dois workflows retomados. Não alterar credenciais, volumes ou registros para preparar a apresentação.

## Roteiro de 5 minutos

1. Abra o Zabbix local e mostre a disponibilidade da API e a coleta de autenticação. A API não publica porta no host; o acesso do usuário passa pelo gateway/Keycloak.
2. Abra `http://127.0.0.1:5678` com sua conta local. Mostre os dois workflows: **SecureOps - Incident Report** e **SecureOps - Mail Delivery**.
3. Abra `http://127.0.0.1:8025` com a credencial local do Mailpit e mostre **SecureOps | Relatório #5 v1**, já recebido. A versão do prompt nesse relatório é 2. Nunca exponha senhas, cookies, chave TOTP ou configuração de credenciais na apresentação.
4. Mostre os fatos/duração, a separação entre análise e hipóteses e o aviso de que a IA pode errar. **Há erro conhecido:** mesmo com prompt restritivo, o modelo pequeno pode sugerir/afirmar causa sem evidência. Não trate o texto como diagnóstico; os fatos confiáveis vêm do banco, não do modelo.
5. Explique as fronteiras: receptor confirma depois do commit; banco faz correlação/deduplicação; n8n consome snapshots sanitizados; IA não recebe logs/segredos, não altera incidentes e não executa ações. SMTP é só a caixa fictícia local, sem envio externo.

## Novo ciclo opcional (cerca de 3 minutos)

Se o tempo for curto, use o relatório #5 e as evidências existentes; não é necessário repetir testes negativos. Para mostrar um ciclo novo, use PowerShell na raiz do projeto:

```powershell
$c = @('compose', '-f', 'compose.yaml', '-f', 'compose.identity.yaml',
       '-f', 'compose.monitoring.yaml', '-f', 'compose.automation.yaml',
       '--profile', 'monitoring-security', '--profile', 'automation')
try {
    docker @c stop api
    if ($LASTEXITCODE -ne 0) { throw 'API não parou; não prossiga.' }
    Start-Sleep -Seconds 45
} finally {
    docker @c up -d --no-deps --wait --wait-timeout 120 api
    if ($LASTEXITCODE -ne 0) { throw 'Restaurar API antes de continuar.' }
}
```

Aguarde a recuperação no Zabbix e até dois minutos para inferência/envio. Consulte sem alterar dados:

```powershell
docker exec secure_ops_lab-automation-db-1 psql -X -qAt -U postgres -d incidents -c "SELECT incident_id,state,duration_seconds FROM incident.incident_summary ORDER BY incident_id; SELECT incident_id,state,attempts,prompt_version FROM incident.report_jobs ORDER BY incident_id; SELECT incident_id,state,attempts FROM incident.report_outbox_summary ORDER BY incident_id;"
```

Resultados esperados do novo ciclo: incidente `closed`, job `ready`, outbox `accepted` e mensagem na caixa. IDs aumentam; não apague os anteriores. Para verificar uma mensagem específica: `./scripts/Test-AutomationServices.ps1 -Phase report -IncidentId <ID>`.

Se falhar, não repetir em loop nem reenfileirar por SQL: use o ciclo já documentado e explique o limite observado. `accepted` significa aceite SMTP, não leitura humana. `delivery_unknown` não pode ser reenviado automaticamente.

## Como defender as decisões

- **Por que receptor separado?** O candidato n8n persistia headers de entrada; o receptor mínimo evita encaminhar segredos da ingestão ao n8n.
- **Por que PostgreSQL?** Identidade do evento, transação, constraints e unicidade mantêm consistência mesmo com repetição/concorrência. Não depender do histórico do workflow.
- **Por que jobs/outbox?** IA e SMTP ficam fora do ACK ao monitor. N8n parado não impede registrar incidentes; teste #5 comprovou retomada.
- **E se a IA errar?** Schema e escape de HTML protegem formato/renderização, **não verdade semântica**. O modelo pequeno alucinou em ensaios; revisão humana é necessária. Evolução futura: gate de aprovação ou validação semântica mais forte, sem fingir que já existem.
- **E se o SMTP cair?** No ensaio #7, o relatório persistiu e o envio virou `delivery_unknown`, sem reenvio cego na retomada. Retry pré-aceite/reconciliação ainda são pontos de evolução.
- **O que não foi comprovado?** Aceite integral IA-01–IA-14, segurança de produção, inferência causal, previsão de falhas ou entrega SMTP externa. Consulte a [matriz](../evidence/04-acceptance-matrix.md).

Ao terminar os ensaios administrativos, revogue o token temporário do Zabbix na UI. O fluxo runtime não depende dele; scripts administrativos dependerão de novo token autorizado.
