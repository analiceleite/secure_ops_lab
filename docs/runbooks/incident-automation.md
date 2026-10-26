# Runbook — Incidentes e relatórios com IA (parcial)

**Estado:** somente infraestrutura inicial exercitada em 26/10/2026. Onze serviços do laboratório ativos; **sem workflows ou action Zabbix**. Não há incidente persistido nem relatório integrado pronto. [SPEC](../features/04-incident-automation/SPEC.md), [PLAN](../features/04-incident-automation/PLAN.md) e [evidências](../evidence/04-incident-automation.md) distinguem testes reais/sintéticos e pendências.

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
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation build ollama mailpit
./scripts/Test-AutomationInfrastructure.ps1

docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation up -d --no-deps --pull never --wait --wait-timeout 180 automation-db
./scripts/Install-AutomationModel.ps1
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation up -d --no-deps --pull never --wait --wait-timeout 180 n8n ollama mailpit
```

Build usa bases oficiais fixadas por digest e só prepara diretórios de volumes para UID 1000. Não introduz dependências/npm/GPU. Banco inicia como UID 999 e executa bootstrap apenas em volume novo; falha parcial exige diagnosticar, não apagar o volume ou rerodar bootstrap por cima. Shells Linux têm LF via .gitattributes.

Instalador de modelo cria loader **efêmero**, não root, sem portas ou segredos do runtime, com saída para baixar o modelo. Confere SHA-256 original e todos os blobs locais; remove só seu próprio loader no finally, preserva volume/modelo. Runtime permanece em inference interna e cloud desligado. Modelo existente íntegro não é baixado novamente; divergência bloqueia sem sobrescrever. Não modificar volume enquanto Ollama está executando para instalar outra versão.

Abrir n8n local e cadastrar owner com e-mail fictício/senha exclusiva, sem trial/licença/templates externos, **apenas em instalação nova**. Não publicar workflow antes de confirmar autenticação e todos os gates correspondentes. Instalação em outra máquina ainda não foi repetida de ponta a ponta.

## 3. Retomar ambiente existente sem recriar dados

Primeiro retomar identidade/monitoramento pelo [runbook 03](monitoring.md), sem reset de secrets/realm. Para os quatro componentes novos já instalados:

```powershell
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation up -d --no-recreate --no-deps --pull never --wait --wait-timeout 180 automation-db
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation up -d --no-recreate --no-deps --pull never --wait --wait-timeout 180 n8n ollama mailpit
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
- Model executa Ollama CPU-only com contexto/saída limitados, JSON e prompt sintético sanitizado. Pode consumir aproximadamente 1,1 GiB de pico observado. Resultado de hipóteses não é prova de causa, previsão ou incidente real. Não envia e-mail.
- SMTP verifica negativas e uma mensagem HTML **sem IA**, autenticada/aceita/vista na caixa. Não é o relatório produtivo da entrega. Repetir adiciona nova mensagem; não executar indiscriminadamente nem apagar caixa para “limpar” o ensaio.

Evidências públicas nunca incluem headers, senhas, cookies, tokens, arquivos de credenciais, logs brutos de incidentes ou dumps. Para future integração Zabbix, novo token administrativo temporário local; o anterior continua revogado, runtime não deve usá-lo.

## 5. Parada somente da automação

```powershell
docker compose -f compose.yaml -f compose.identity.yaml -f compose.monitoring.yaml -f compose.automation.yaml --profile automation stop n8n ollama mailpit automation-db
```

Isso não remove dados nem para os serviços das entregas anteriores. Não usar down -v/limpeza ampla. O fluxo de incidentes/relatórios ainda será implementado; não anunciar coleta automática/e-mail de IA enquanto há apenas serviços ativos e smokes independentes.
