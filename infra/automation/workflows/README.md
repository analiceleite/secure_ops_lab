# Workflows de relatório — fluxo integrado, aceite parcial

`incident-receiver.json` é um **candidato bloqueado pelo gate de segurança**, sem credenciais vinculadas. Não importar/publicar no n8n ativo.

No teste isolado da versão 2.44.7, autenticação/raw body/transação/concorrência funcionaram, mas `execution_data` reteve header e marcador fictícios mesmo com salvamento success/error/manual/progress desabilitado. O pruning posterior não satisfaz a exigência de nunca persistir headers/bodies de entrada. Adicionar Set/Code depois do Webhook não é correção demonstrada para a gravação inicial.

O harness `scripts/Test-AutomationWebhook.ps1` cria somente fixtures efêmeras, com credenciais aleatórias exclusivas, sem portas/volumes persistentes/segredos do laboratório, e **deve falhar no gate execution_storage enquanto essa incompatibilidade existir**. Não reduzir a asserção para obter teste verde.

`incident-reports.json` e `incident-mail-delivery.json` são exports sanitizados/inativos para instalação, não cópias de credenciais. Na instância local existem `SecureOps - Incident Report` (`aqhbDEZE5eGYegqp`) e `SecureOps - Mail Delivery` (`WnP9yQzfVSyBH8n7`), publicados com credenciais vinculadas pela autora. Relatórios #4/#5 chegaram ao Mailpit. O prompt atual é revisão 2, depende de migrações 001–003. Não reimportar em cima de workflows existentes sem inspecionar/preservar IDs, configurações e referências de credenciais.

Para futura configuração manual local (não exportar credenciais): criar uma credencial Postgres para host `automation-db`, porta 5432, database `incidents`, user `incident_report`, SSL desabilitado na rede interna; senha fica em `.local/automation/incident-report-password`. Criar SMTP para host `mailpit`, porta 1025, segurança TLS desligada (Mailpit local); o arquivo protegido `.local/automation/mailpit-smtp-auth` contém `usuario:senha` (usuário `secureops`), usar a senha após `:` no formulário n8n, sem imprimir/compartilhar o conteúdo. Destinatário/remetente permanecem fixos no workflow (`operadora@lab.invalid` / `secureops@lab.invalid`). Nunca importar/exportar uma credencial ou execução com valores.

O envio só registra `accepted` depois de o node SMTP retornar sucesso. Crash, timeout ou erro depois de possível aceitação expira lease como `delivery_unknown`, sem reenvio cego. A reclassificação/reenvio explícito e as retries após rejeição comprovadamente anterior à aceitação ainda precisam de implementação/revisão antes de ativar o workflow.

Diagnóstico: `running` com `deletedAt` e runData inicial não prova travamento; com save-on-progress=false o banco não localiza o node atual. Logs temporários mostraram expressão inválida no prompt (newline e `}}` prematuro). Espaços entre fechamentos e transporte HTTP JSON nativo foram validados. `node --test infra/automation/workflows/workflows.test.mjs` protege essas regressões. Falha de IA ainda depende de expiração de lease com duas tentativas; tratamento explícito por `fail_report_job` e retry SMTP pré-aceite continuam pendentes. Nenhum esquema de retry pode reenviar automaticamente uma aceitação ambígua.

Autora autorizou receptor mínimo dedicado para autenticação/validação/commit/ACK, deixando o n8n somente com snapshots sanitizados. O fluxo já foi exercitado, mas o aceite completo depende da matriz IA-01–IA-14. Nunca publicar o workflow legado de ingestão n8n.
