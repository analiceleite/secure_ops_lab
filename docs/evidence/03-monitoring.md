# Evidências 03 — Monitoramento com Zabbix (parcial)

**Estado:** em implementação em 25/10/2026. M-D01–M-D06 e sequência disponibilidade → segurança aprovadas explicitamente pela autora. Infraestrutura executada pelo agente; nenhum login Zabbix confirmado pela autora nesta coleta. Cenários de disponibilidade/segurança, dashboard e automação não estão validados.

## 1. Ambiente e preparação

- Docker Engine 28.5.1, Compose 2.40.2-desktop.1, Linux x86_64, 12 CPUs, 8.171.757.568 bytes de memória do daemon (aproximadamente 7,61 GiB).
- Porta 8081 sem listener na inspeção anterior à subida. API, Keycloak e gateway já estavam ativos; API healthy e publicações de identidade em 127.0.0.1.
- Três imagens por tag+digest da SPEC baixadas com sucesso. Entry points e bibliotecas de configuração foram lidos nas próprias imagens, com rede none e restrições. Server/frontend têm usuário 1997; PostgreSQL permite execução explícita como 999:999 com volume novo já pertencente a postgres. Nenhum container foi executado como root.
- Conferidos suporte a POSTGRES_PASSWORD_FILE, configuração mascarada de DBPassword com DEBUG_MODE=false, pg_isready e curl/ping do frontend. PostgreSQL suporta peer no socket e SCRAM TCP. Server não tem health check declarado na imagem.
- Criados dois segredos exclusivos em `.local/monitoring/` com ACL restrita ao usuário atual. Segundo acionamento do inicializador recusado; comparação de hashes em memória confirmou que os arquivos permaneceram iguais, sem exibir hashes/valores. Pasta ignorada e fora do build da API.

## 2. Inspeção somente leitura da identidade

Um container Node efêmero na rede identity leu bootstrap local por mount read-only, obteve token administrativo em memória e consultou somente realm/configuração de eventos. Nenhum token ou resposta bruta foi exportado. Essa credencial é de diagnóstico administrativo separado, **não a credencial do futuro coletor**.

Resultado selecionado: `eventsEnabled=false`, `LOGIN_ERROR` entre tipos retornados, listener `jboss-logging`, admin events desabilitados, `sslRequired=external` e **`bruteForceProtected=false` preexistente**. Não havia retenção explícita retornada. Nenhuma dessas opções foi alterada; não declarar proteção brute force habilitada. O futuro armazenamento deve ser configurado explicitamente e documentar a diferença entre tipos efetivos padrão retornados e o recorte desejado, antes de habilitar eventos.

Não foram consultadas credenciais OTP/senhas, criados clients, alterados grupos ou produzidos logins falsos para gerar eventos. Client técnico/view-events e testes reais da coleta permanecem pendentes.

## 3. Implementação e subida reais — 11:20–11:24, -03:00

- Overlay `compose.monitoring.yaml`: PostgreSQL, Zabbix server e frontend; redes monitoring interna e operations bridge não interna. Server também em service; API intacta.
- PostgreSQL iniciou como UID/GID 999. Script de primeiro volume criou role `zabbix` e banco próprio. Verificação real de rolsuper/rolcreatedb/rolcreaterole/rolreplication retornou **false em todos**. Server/frontend não recebem o segredo de bootstrap.
- Script de inicialização só é executado em banco vazio. Credenciais não foram exibidas. Configurações de autenticação efetivas consultadas em pg_hba_file_rules: somente **peer nos sockets locais e scram-sha-256 nas regras host**; sem trust. Conexão TCP como zabbix sem senha foi rejeitada com “no password supplied”.
- Schema importado pela imagem Zabbix com role dedicada, `mandatory=07000000`, `optional=07000030`. Log selecionado confirmou server 7.0.32 revision `0d6fa36`, versão de banco e processo principal iniciado em 11:21:09 (-03:00).
- Frontend healthy, `/ping` 200 e `apiinfo.version` retornando 7.0.32. `up --wait` não substitui confirmação de inicialização do server; as verificações de schema/log/API são complementares.
- Comparação de IDs/start times antes/depois confirmou que **API, Keycloak e gateway existentes não foram recriados nem reiniciados**. Nenhuma porta da API publicada e nenhum volume/segredo de identidade removido ou alterado.

## 4. Validações executadas e limites

- `Test-MonitoringInfrastructure.ps1`: **23 checks estáticos aprovados**, envolvendo base, base+monitoramento e composição com identidade. API comparada à configuração base, redes e segredos/publicações conferidos.
- `Test-MonitoringInfrastructure.ps1 -Runtime`: **42 checks totais aprovados**, somando inspeções de containers/restrições/redes/publicações/usuários/mounts, role, schema e ping. Não são 42 testes de monitoramento funcional.
- Restrições reais: usuários não root esperados, cap_drop ALL, NoNewPrivs, sem privileged/socket. Banco só em monitoring; server em monitoring+service; frontend em monitoring+operations; API só em service e sem mounts.
- Binding novo observado: somente **127.0.0.1:8081 → 8080** do frontend. Banco/server sem publicação. Tentativa em `[::1]:8081` falhou. Não comprova isolamento absoluto do host nem bloqueio de egress.
- Dashboard sem sessão retornou HTTP **200**, título Warning e mensagem de não autenticado, não painel administrativo. Não exigir 401/403 para concluir essa negativa. Inspeção read-only de memberships confirmou guest no grupo **Disabled**, users_status=1; também está em Guests/Internal. Não houve alteração de usuário via SQL.
- **Troca da senha Admin, novo login/logout e cookies autenticados continuam pendentes da autora.** Não houve sessão autenticada de navegador coletada pelo agente. Não houve alteração de senha do painel pelo agente.
- Host padrão `Zabbix server` já veio habilitado e registrou falha de agente local; nenhum agente foi instalado. Deve ser desabilitado pela UI ao configurar o host do lab. Isso é ruído da configuração de fábrica, não incidente da API.
- Logs dos três novos serviços examinados em memória: nenhuma correspondência aos dois segredos novos conhecidos ou padrão selecionado de JWT. Conteúdo bruto não exportado; varredura limitada, sem garantia universal.
- Snapshot de memória: banco **163,3 MiB / 512 MiB**, server **49,87 MiB / 512 MiB**, frontend **24,03 MiB / 384 MiB**. Não representa pico, teste de carga ou dimensionamento mínimo.

### Erros de execução corrigidos

Primeiras inspeções shell falharam por quoting/CRLF ao atravessar PowerShell para sh. Repetidas por leitura direta dos arquivos com `--entrypoint cat` e validação `bash -n`, sem executar configurações do ambiente. Primeiro check estático confundiu `@($null).Count` com uma porta existente; corrigida a verificação de propriedade ausente e repetido o conjunto completo. Esses erros não motivaram permissões extras, rede pública ou remoção de dados.

## 5. Regressão antecipada após novas redes

- API: **35 aprovados**, zero falhas, **5799.136844 ms**; execução por Compose completo com build de teste/cache e container sem rede.
- Configuração de identidade: **10 aprovados**, zero falhas, **227.398807 ms**; imagem local, sem rede, mount read-only.
- Proxy OIDC real isolado: **12 verificações aprovadas**, incluindo audience/issuer/assinatura/nonce/state/grupos/cookie; rede temporária interna, sem publicação, gateway principal inalterado.
- Probe API aprovado. Discovery interno 200, issuer exato, JWKS 200 e token sem secret rejeitado 401.
- Revisão de arquivos: 73 links Markdown locais com destinos existentes (âncoras não verificadas), sintaxe PowerShell e LF do script Linux aprovados; `git diff --check` aprovado. Varredura de 45 arquivos versionados/versionáveis sem correspondências aos segredos locais conhecidos ou padrões selecionados de chave privada/JWT; `.local` fora da seleção. Limites de varredura preservados, sem garantia universal.

Isso não substitui regressão final após implementar coletor/triggers nem confirma novo login de navegador no ambiente principal. Entrega 02 permanece concluída, com dados preservados.

## 6. Estado do aceite

| Critério | Estado nesta coleta |
| --- | --- |
| MO-01 | Parcial: decisões/imagens/recursos/infra conferidos; expressões reais e contrato/permissões do coletor ainda pendentes |
| MO-02 | Parcial: exposição/restrições/guest verificadas; troca de senha Admin e testes autenticados de painel pendentes |
| MO-03/MO-04 | Pendentes: ainda não há cenário web/trigger configurado nem ciclo de parada da API |
| MO-05/MO-06/MO-07 | Pendentes: client/coletor/triggers de segurança não implementados |
| MO-08 | Pendente: primeiro volume/schema funcionando não comprova preservação após reinício/recriação |
| MO-09 | Parcial: containers/configuração preservados e discovery/probe; regressão manual pós-monitoramento ainda pendente |
| MO-10 | Parcial: regressão antecipada aprovada e runbook parcial; fechamento final depende dos demais critérios |

**Estado deixado:** seis serviços ativos (API, Keycloak, gateway e três novos componentes Zabbix). Sem cenário web, coletor, n8n, IA ou e-mail. Volumes/segredos preservados, sem commit/push. Próximo passo é a autora trocar a senha inicial do painel e confirmar novo login/logout, antes de configurar o monitor.
