# Runbook — Incidentes e relatórios com IA (parcial)

**Estado:** fluxo integrado com relatórios reais #4/#5 no Mailpit, action restrita e workflows publicados; aceite parcial na [matriz](../evidence/04-acceptance-matrix.md). Schema 1/2/3; jobs failed e relatório v1 rejeitado semanticamente preservados. [SPEC](../features/04-incident-automation/SPEC.md), [PLAN](../features/04-incident-automation/PLAN.md) e [evidências](../evidence/04-incident-automation.md) distinguem runtime, fixture e pendências.

## 1. Limites e preservação

- Apenas serviços/dados fictícios locais; nada de API de IA externa, SMTP relay, túnel, router ou credencial pessoal.
- n8n em **http://localhost:5678/** e Mailpit em **http://localhost:8025/**, publicados somente em 127.0.0.1. HTTP não é TLS; SMTP autenticado também é local sem TLS. Banco/Ollama/SMTP não têm porta publicada no host.
- API original continua sem porta. Base/identidade/monitoramento e suas senhas/TOTP/grupos/volumes devem permanecer intactos.
- Novos volumes: automation-db-data, n8n-data, ollama-data e mailpit-data. Segredos novos em `.local/automation/`, com ACL restrita e fora do Git. Nunca remover volumes, sobrescrever pasta/chave n8n ou exportar banco/credenciais para repetir teste.
- A conta owner do editor é local, separada do Keycloak. A autora já criou a conta; não refazer signup ou alterar credenciais existentes.
- Mailpit usa usuário UI `operadora`, com senha exclusiva gerada no arquivo protegido `.local/automation/mailpit-ui-auth`. Consultar esse arquivo **somente localmente**, sem copiar para chat/captura/Git. SMTP usa outro usuário/segredo em mailpit-smtp-auth; nunca usar senha do Keycloak. Não há entrega na caixa pessoal externa.
- Os flags N8N_AI_ENABLED/N8N_AI_GATEWAY_ENABLED=false desabilitam assistant/gateway cloud, **não a geração proposta de relatórios por IA local**: ela usará HTTP Request com destino fixo Ollama. Ainda não há workflow implementado.

## 2. Instalação nova — não repetir bootstrap no ambiente existente

Docker Linux disponível, imagens da API/testes existentes e recursos suficientes. O baseline anterior tinha 12 CPUs/7,61 GiB totais; conferir recursos livres atuais. Releases/digests na SPEC; não usar latest nem atualização silenciosa.

```powershell
# Somente se .local/automation NAO existe; recusa sobrescrita:
./scripts/Initialize-Automation.ps1

# Pull explicito apenas das imagens novas/fixadas:
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation pull n8n automation-db
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation build ollama mailpit incident-receiver
./scripts/Test-AutomationInfrastructure.ps1

docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation up -d --no-deps --pull never --wait --wait-timeout 180 automation-db
./scripts/Install-AutomationModel.ps1
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation up -d --no-deps --pull never --wait --wait-timeout 180 n8n ollama mailpit incident-receiver
```

Build usa bases oficiais fixadas por digest e só prepara diretórios de volumes para UID 1000. Não introduz dependências/npm/GPU. Banco inicia como UID 999 e executa bootstrap apenas em volume novo; falha parcial exige diagnosticar, não apagar o volume ou rerodar bootstrap por cima. Shells Linux têm LF via .gitattributes.

Instalador de modelo cria loader **efêmero**, não root, sem portas ou segredos do runtime, com saída para baixar o modelo. Confere SHA-256 original e todos os blobs locais; remove só seu próprio loader no finally, preserva volume/modelo. Runtime permanece em inference interna e cloud desligado. Modelo existente íntegro não é baixado novamente; divergência bloqueia sem sobrescrever. Não modificar volume enquanto Ollama está executando para instalar outra versão.

Abrir n8n local e cadastrar owner com e-mail fictício/senha exclusiva, sem trial/licença/templates externos, **apenas em instalação nova**. Não publicar workflow antes de confirmar autenticação e todos os gates correspondentes. Instalação em outra máquina ainda não foi repetida de ponta a ponta.

## 3. Retomar ambiente existente sem recriar dados

Primeiro retomar identidade/monitoramento pelo [runbook 03](monitoring.md), sem reset de secrets/realm. Para os quatro componentes novos já instalados:

```powershell
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation up -d --no-recreate --no-deps --pull never --wait --wait-timeout 180 automation-db
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation up -d --no-recreate --no-deps --pull never --wait --wait-timeout 180 n8n ollama mailpit incident-receiver
```

No ambiente inicial, volume do modelo criado administrativamente gerou aviso Compose de labels ausentes. Não remover volume para silenciar aviso. Versão do instalador posterior inclui labels em volumes novos; preserva o existente.

Se n8n não inicia, conferir readiness e erro sanitizado; rootfs permanece read-only, com cache/tmp graváveis limitados. Não mudar para root, montar host home/socket ou desabilitar autenticação. Não solicitar valores de secrets para diagnosticar.

## 4. Verificações repetíveis e seus efeitos

```powershell
# Sem alterar dados de negocio ou parar servicos:
./scripts/Test-AutomationInfrastructure.ps1 -Runtime
./scripts/Test-AutomationDatabase.ps1
./scripts/Test-AutomationModelIntegrity.ps1
./scripts/Test-AutomationServices.ps1 -Phase interfaces
./scripts/Test-IncidentReceiver.ps1
node --test infra/monitoring/incident-webhook.test.mjs infra/automation/workflows/workflows.test.mjs
# Confere modelo existente e hashes; sem download se integro:
./scripts/Install-AutomationModel.ps1

# Inferencia REAL com cenario ficticio, ate 120s; sem tocar Keycloak/Zabbix:
./scripts/Test-AutomationServices.ps1 -Phase model

# ADICIONA uma mensagem ficticia de infraestrutura na caixa; nao apaga mensagens:
./scripts/Test-AutomationServices.ps1 -Phase smtp
```

- Infrastructure verifica estático/runtime, redes, usuário/caps, binds/limites e preservação da configuração dos sete serviços originais. Não testa workflows/HTML.
- Database verifica grants, login TCP correto, senha errada/acesso cruzado negados e ausência de privilégio de criar schema para ingest. Não cria tabela nem comprova futura transação/deduplicação.
- ModelIntegrity executa seis testes em fixtures exclusivas no tmpfs, incluindo corrupção de peso/licença/manifesto/layer. VerifyModel hasheia os arquivos reais no volume quando executado pelo instalador. Hash do manifesto original é diferente do wrapper local acrescentado por Ollama 0.40; o verificador valida ambos, nunca aceita alias como prova de integridade.
- Interfaces confirma readiness n8n e nega acesso a workflows/caixa sem sessão/segredo, mais leitura Mailpit autorizada. Não inspeciona a sessão autenticada do navegador da autora.
- Test-IncidentReceiver cria somente rede/containers/dados/segredos efêmeros, executa HTTP+PostgreSQL, recria seu receptor de teste e verifica banco offline; remove apenas recursos próprios. A opção `-Build` reconstrói imagem de teste/runtime. Nunca aplica migração ao `automation-db` ativo nem configura Zabbix; não publica porta no host. A fixture valida lógica, não macros reais.
- Model executa Ollama CPU-only com contexto/saída limitados, JSON e prompt sintético sanitizado. Pode consumir aproximadamente 1,1 GiB de pico observado. Resultado de hipóteses não é prova de causa, previsão ou incidente real. Não envia e-mail.
- SMTP verifica negativas e uma mensagem HTML **sem IA**, autenticada/aceita/vista na caixa. Não é o relatório produtivo da entrega. Repetir adiciona nova mensagem; não executar indiscriminadamente nem apagar caixa para “limpar” o ensaio.

Evidências públicas nunca incluem headers, senhas, cookies, tokens, arquivos de credenciais, logs brutos de incidentes ou dumps. Para future integração Zabbix, novo token administrativo temporário local; o anterior continua revogado, runtime não deve usá-lo.

## 5. Parada somente da automação

```powershell
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation stop incident-receiver n8n ollama mailpit automation-db
```

Isso não remove dados nem para os serviços das entregas anteriores. Não usar down -v/limpeza ampla. A action ainda não está conectada; não anunciar ingestão ou e-mail de IA como fluxo funcional.

## 6. Núcleo de incidentes — validação isolada, sem instalar no banco ativo

```powershell
./scripts/Test-AutomationIncidents.ps1
```

O harness reutiliza a imagem PostgreSQL 17.11 já fixada/disponível (`--pull never`) em container com nome exclusivo: UID 999, sem rede, portas, volumes persistentes ou segredos do laboratório, rootfs read-only e dados em tmpfs. Uma senha bootstrap aleatória e descartável existe apenas nessa fixture; conexões dos testes usam socket local com peer, e o listener TCP é desabilitado. Não é substituição das credenciais do banco ativo. Ao finalizar, remove somente o container que criou; não executa limpeza ampla.

Aplica setup fictício + migrações 001 e 002 **na fixture**, testa contrato/transições/permissões/rollback, jobs/leases/HTML/outbox, 20 duplicatas concorrentes, dois primeiros ciclos em disputa, timeout de lock e recusa de reaplicar a migração. Confere ID/start time/running dos serviços existentes antes/depois. O teste consome temporariamente até 256 MiB/2 CPUs mais tmpfs; não é inferência/SMTP ou teste de carga do n8n. Resultado esperado: `$LASTEXITCODE` 0, 86 checks SQL base + 15 checks jobs/outbox, uma aplicação/19 duplicatas, um ciclo aplicado/um conflitante e timeout sem ledger/ciclo gravado.

`infra/automation/tests/` contém somente fixtures; **não executar esses SQL/Bash no automation-db ativo**. As migrações ativas foram instaladas pela invocação autorizada de `scripts/Install-IncidentSchema.ps1 -EndToEndTestAuthorized`: versions 1/2, quatro condições allowlisted, zero deliveries na verificação. Não executar o script novamente: recusa schema preexistente/reaplicação. Se houver divergência, preservar e diagnosticar; nunca apagar dados/volumes para refazer.

O gate de ingestão passou em fixture; rede Zabbix→receptor foi confirmada por DNS e GET liveness. Em ciclo controlado, problem 153/recovery 154 passaram pelo webhook; trigger 25229, duas entregas applied e duração fechada de 80 s confirmam expansão real das macros. O report job terminou `failed` por leases expiradas; ambos workflows foram despublicados e action/media types desabilitados para evitar novas falhas silenciosas.

## 7. Gate legado do receptor n8n — reprovado, não instalar

`./scripts/Test-AutomationWebhook.ps1` cria uma rede interna exclusiva e dois containers n8n/PostgreSQL efêmeros, sem portas/volumes persistentes/segredos do lab. Usa a configuração restrita da imagem n8n fixada e contas/credenciais **novas da fixture**, nunca a conta owner da autora. Arquivos env temporários exclusivos ficam em `%LOCALAPPDATA%/Temp/opencode/`, com ACL restrita; remove somente arquivos/pasta/rede/containers próprios ao finalizar. Requer esse diretório temporário disponível e imagens já instaladas (`--pull never`). Consome temporariamente até 512 MiB no n8n e 256 MiB no PostgreSQL, mais tmpfs.

**Resultado atual esperado: exit não zero, stage execution_storage.** Não é suíte concluída: gate encontrou header/marcador fictícios no metadata n8n mesmo com flags none/false, e impede promover o candidato a produção. Autenticação, validação raw, commit, concorrência e 503 funcionaram antes desse bloqueio. Não apagar linhas manualmente, reduzir asserção, habilitar Code/serviço extra ou alterar o n8n ativo para obter verde. Não usar `/webhook-test/` ou credenciais reais neste ensaio.

O [candidato](../../infra/automation/workflows/README.md) não tem credenciais e **não deve ser publicado/importado no n8n ativo**. Resolver a arquitetura com a autora antes da integração; pruning posterior ou remoção do header em um node seguinte não demonstram que ele nunca foi gravado. Nenhum envio externo de relatório é configurado por esse harness.

A autora aprovou a revisão e o receptor dedicado foi implementado. O workflow legado de ingestão n8n continua proibido. Para resultados, consultar evidências e `Test-IncidentReceiver.ps1`. Nenhuma porta de host deve ser criada.

## 8. Operação e verificação do fluxo integrado

1. Workflows reais: `SecureOps - Incident Report` e `SecureOps - Mail Delivery`. Os JSON do repositório são exports sanitizados inativos para instalação; não reimportar sobre a instância configurada por conveniência.
2. Schema versions 1/2/3 e quatro condições estão ativos. O instalador inicial recusa schema existente. Para atualização já provisionada, aplicar **somente** a migração aditiva ainda ausente, após fixture e autorização; nunca reaplicar 001/002, apagar dados ou reconstruir allowlist para resolver erro.
3. Usuário ID 3 sem frontend, leitura somente no host group dedicado; action 7: host 10684 + triggers 25229–25232, problem media 72/recovery 73, sem update/comandos. Macro webhook Secret. Para pausa operacional autorizada: `./scripts/Configure-IncidentAction.ps1 -Mode disable`; inspecionar antes de retomar e usar `-Mode enable` apenas com triggers claros e consumidores prontos. Revogar token administrativo ao fim dos ensaios; runtime não depende dele.
4. Ler incidentes/jobs/outbox por views com papel de leitura, sem DML. `ready` prova relatório persistido; `accepted` prova retorno SMTP, não leitura humana. `./scripts/Test-AutomationServices.ps1 -Phase report -IncidentId 5` verifica por API autenticada mensagem única, destinatário e corpos HTML/texto; abrir `http://127.0.0.1:8025` para revisão visual/semântica com a credencial local, nunca compartilhada.
5. Jobs de IA usam leases com duas tentativas; falha esgotada permanece failed. Outbox com lease expirada passa a delivery_unknown porque o SMTP pode ter aceitado antes da perda do ACK. Não reenviar/reclassificar por SQL nem presumir falha de entrega. Inspecionar a caixa por assunto/ID, preservar registros e revisar procedimento explícito antes de qualquer reenvio. Retry seguro pré-aceite ainda precisa implementação/validação.
6. Relatório #4 (prompt1) foi rejeitado semanticamente, mas preservado. #5 usa prompt2 e relatório v1; revisão humana segue pendente. A hipótese genérica do modelo não é causa comprovada. Nenhum relatório muda estado de incidente ou executa ações.

### Diagnóstico seguro do n8n

Com progresso desabilitado, `execution_data` pode conter só a pilha inicial; `execution_entity` pode conservar `running` mesmo após soft-delete (`deletedAt` preenchido). Isso **não prova** travamento no trigger. Não habilitar retenção/debug por padrão. A reprodução autorizada temporária mostrou erro de expressão no prompt e stream HTTP raw; correções estão nos exports/testes. Depois da reprodução, warn/progress=false foram restaurados. Não usar metadata n8n como banco de incidentes, nem exportar payloads/credenciais para diagnosticar.
