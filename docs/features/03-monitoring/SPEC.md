# SPEC 03 — Monitoramento

**Estado:** em especificação. Rascunho inicial com Uptime Kuma, solicitado em 25/10/2026. Após conclusão da identidade, autora manifestou intenção de usar Zabbix; este documento ainda precisa dessa revisão, incluindo fronteira com incidentes. Decisões abaixo não estão aprovadas; nenhum monitor implementado.

Referências: [README](../../../README.md), [arquitetura](../../architecture.md), [roadmap](../../roadmap.md), [Fundação Local](../01-local-foundation/SPEC.md) e [PLAN](PLAN.md).

## 1. Objetivo e dependências

Detectar indisponibilidade e recuperação da API fictícia pelo Uptime Kuma, mantendo monitor e dados independentes do container monitorado. Preparar a integração com a entrega 04 a partir de notificações reais, sem implementar o ciclo de incidentes nesta entrega.

A Fundação Local e a Identidade estão concluídas: API somente na rede `service` interna, sem porta no host, com `/health` e probe; gateway aplica MFA/autorizações conforme evidências da entrega 02. Este rascunho foi escrito em paralelo antes do fechamento e não implementa monitoramento nem altera a identidade.

O monitoramento interno não atravessa o gateway e não usa credenciais de usuário. Isso é uma verificação operacional na rede Docker, não uma exceção pública de autenticação. `/health` pelo gateway continua protegido conforme SPEC 02.

## 2. Escopo

Incluído:

- Um Uptime Kuma local, um administrador fictício e um monitor da API.
- Painel autenticado em loopback e persistência em volume nomeado local.
- Verificação HTTP periódica, detecção de queda/recuperação e medição dos tempos observados.
- Dois ciclos controlados de parada/retorno da API e persistência após reinício/recriação do monitor.
- Captura sanitizada de notificações reais em receptor de teste temporário, exclusivamente na rede Docker.
- Runbook de configuração manual e evidências reproduzíveis.

Fora do escopo: n8n, banco de incidentes, deduplicação, fila, garantia de entrega, notificações externas, status page pública, monitoramento do Docker por socket, autorrecuperação e verificação sintética de login/gateway. Não adicionar endpoint de falha à API.

## 3. Decisões propostas — aprovação pendente

| ID | Proposta | Motivo e limite |
| --- | --- | --- |
| M-D01 | Painel `http://localhost:3001`, publicação `127.0.0.1:3001:3001`; HTTP local com conta fictícia | Simplifica o lab; senha/sessão não cifradas. A exceção da identidade não aprova automaticamente este novo painel. Confirmar cookies e limites antes de aplicar; não desligar proteções por tentativa e erro. |
| M-D02 | Kuma em `service` interna e rede `operations` bridge não interna; API permanece somente em `service` | A rede adicional permite testar publicação do painel sem depender de publicação em rede exclusivamente interna, que falhou na identidade. Kuma ganha rota de saída: não alegar bloqueio de egress. Não reutilizar `identity`. |
| M-D03 | Volume nomeado `kuma-data` em `/app/data`; banco local suportado pela imagem, sem banco separado | Persistir configuração, histórico e dados de autenticação. Volume sensível, sem backup/HA; não exportar banco nem removê-lo para repetir testes. |
| M-D04 | Intervalo 20 s, timeout 5 s, zero retries de confirmação e reenvio periódico de DOWN desabilitado | Demonstração curta, com menor tolerância a falhas transitórias. Uma checagem falha pode declarar DOWN. Não confundir retry de checagem com retry de webhook. |
| M-D05 | Receptor temporário Node, reaproveitando a imagem local da API, sem porta publicada e sem dependência nova | Observar payload/entrega sem antecipar n8n. Serviço auxiliar no profile `tools`, não inicia API nem coleta headers/segredos. Não é receptor de incidentes de produção. |

Antes de implementar, registrar aprovação ou revisar as propostas. Mudança de transporte, rede, persistência ou comportamento exige decisão explícita; não tratar valores candidatos como aprovados.

## 4. Versão e composição

- Candidata: **Uptime Kuma 2.5.7**, release estável publicada em 23/10/2026, consultada em 25/10. Confirmar tag de imagem, manifesto `linux/amd64`, digest e compatibilidade antes de fixar a imagem. Não usar `latest` nem tag major mutável na implementação.
- Overlay proposto `compose.monitoring.yaml`, preservando os comandos da fundação e da identidade. Composição base + monitoramento deve funcionar sem iniciar Keycloak/gateway; validar também a composição dos três arquivos.
- Serviços propostos: `uptime-kuma` e auxiliar `webhook-capture`; redes/volume apenas após aprovação. A rede de eventos com n8n será definida na entrega 04, sem criar conectividade futura por conveniência.
- Sem `privileged`, Docker socket, host network ou capacidades extras. Conferir suporte da imagem a usuário não root e retirada de capabilities. Se houver incompatibilidade, parar e apresentar a necessidade; não executar como root silenciosamente.
- Rotação de logs proposta: `json-file`, 10 MiB por arquivo e três arquivos, como na fundação. Histórico de heartbeats: propor sete dias, confirmando suporte/configuração na versão; não declarar política aplicada antes de verificar.
- Espera inicial finita proposta: 120 s; parada graciosa: 30 s. Limite inicial candidato de memória: 512 MiB, sujeito a medição e revisão; não é dimensionamento comprovado. Não instalar curl apenas para inventar um health check.

## 5. Monitor e administração

| Campo | Valor proposto |
| --- | --- |
| Nome lógico | `secureops-api` |
| Tipo | HTTP(s), GET |
| Destino | `http://api:3000/health` |
| Código aceito | Somente 200 |
| Intervalo / timeout | 20 s / 5 s |
| Retries de confirmação | 0 |
| Reenvio periódico durante DOWN | Desabilitado |
| Credenciais/headers da API | Nenhum |
| Redirects | Não seguir; confirmar opção suportada na versão |

Este monitor comprova resposta HTTP 200 no destino fixo. O probe da fundação continua verificando o contrato mais estrito: `Content-Type: application/json` e corpo exato `{"status":"ok"}`. Não atribuir ao monitor simples uma validação de JSON que ele não executa. Resposta inesperada/redirect deve ser testada no auxiliar isolado, sem modificar a API nem mudar o monitor principal permanentemente.

A autora cria a conta administrativa com senha exclusiva local, sem enviar segredo ao chat. Registrar configuração pela interface e passos repetíveis; não depender de API interna não documentada nem editar o banco. Painel sem sessão não deve liberar dados administrativos nem alterações. Não criar status page pública. Qualquer necessidade de relaxar cookie/transporte volta à revisão M-D01 antes da aplicação.

## 6. Detecção, falhas e medição

1. Iniciar API e Kuma, aguardar prontidão e pelo menos dois heartbeats saudáveis.
2. Registrar instante/fuso e parar **somente** `api`; não usar `down`.
3. Confirmar DOWN e que Kuma/receptor continuam executando; manter a API parada por pelo menos dois intervalos adicionais.
4. Retomar API sem mudar configuração/volume; aguardar probe saudável e observar UP.
5. Repetir o ciclo, sem limpar o histórico, para demonstrar repetibilidade.

Meta local proposta: detectar DOWN e UP em até **60 s** de cada mudança efetiva, com Docker operacional. Registrar separadamente início do comando, confirmação da parada/saúde, heartbeat e recebimento do webhook. Intervalo/timeout não garantem prazo exato; se superar a meta, registrar falha/investigar, não ajustar evidência. Não confundir duração observada com instante exato da indisponibilidade.

Durante parada do Kuma não existe observação contínua: o retorno não deve ser apresentado como reconstrução garantida de eventos perdidos. Reinício e recriação apenas do container, sem remover o volume, devem preservar conta, monitor e histórico; comprovar por nova autenticação, consulta do histórico e novo ciclo.

## 7. Preparação do webhook, sem automação

- Configurar provider **Webhook**, método POST e corpo JSON padrão, direcionado somente ao receptor temporário na rede Docker. Confirmar opções na versão antes de configurar.
- Código 2.5.7 consultado monta `heartbeat`, `monitor` e `msg`; teste de notificação pode ter objetos nulos. Esses nomes são análise de fonte, não payload já observado. A integração 04 só deve fixar campos/status/timestamps após capturar eventos reais de DOWN e UP.
- Registrar de forma sanitizada: método, tipo de conteúdo, estrutura/campos, tipo/valor do estado, identificação fictícia do monitor, timestamps/fuso, status HTTP do receptor e sequência de chegada. Separar teste manual de notificação de uma transição real.
- Não registrar headers de autenticação, cookies, URLs com segredo nem dumps integrais de configuração. O payload pode incluir configuração sensível do monitor; usar allowlist de campos e revisar antes de persistir evidências.
- Receptor sem porta no host, limitado a JSON e tamanho finito a definir no PLAN de implementação. Responder 2xx apenas após aceitar o evento de teste; rejeitar entradas malformadas/maiores que o limite. Não manter estado de incidentes.
- Parar o receptor durante uma transição e observar o erro de entrega sem derrubar o monitor. Retomar e documentar se há retry/reenvio automático; não prometer fila, replay ou entrega garantida. Em seguida, executar um novo ciclo com receptor disponível.
- A autenticação definitiva do webhook pertence à SPEC 04. O provider consultado suporta headers adicionais, mas sua configuração segura e os caminhos negativos ainda precisam de revisão/validação nessa entrega futura. O receptor diagnóstico interno não comprova um webhook autenticado.

## 8. Critérios de aceite

| ID | Critério | Evidência exigida |
| --- | --- | --- |
| MO-01 | Preparação e decisões resolvidas | M-D01–M-D05 aprovadas; versão/digest/opções, porta e permissões conferidos |
| MO-02 | Exposição mínima e painel autenticado | Compose seletivo + bindings reais; loopback apenas; API sem porta e somente `service`; sem socket/privilégios; painel sem sessão não administra |
| MO-03 | Monitor interno saudável | Dois heartbeats 200, destino correto e probe da fundação aprovado |
| MO-04 | Queda detectada | Parada somente da API, DOWN em até 60 s, Kuma/receptor vivos e evento real recebido |
| MO-05 | Recuperação e repetibilidade | UP em até 60 s após saúde e segundo ciclo DOWN/UP, tempos registrados |
| MO-06 | Persistência real | Reinício e recriação do Kuma sem apagar volume preservam conta/configuração/histórico e novo monitoramento funciona |
| MO-07 | Contrato observado de notificação | Payloads reais DOWN/UP sanitizados e distintos do teste manual; sem inferir contrato somente do código |
| MO-08 | Falhas e limites documentados | Resposta não 200/redirect em alvo isolado; receptor indisponível; retomada e comportamento real de entrega registrados |
| MO-09 | Regressão e reprodução | 35 testes API + 10 estáticos de identidade, probe, composições e isolamento conferidos; runbook repetido, evidências sem segredos |

Concluir apenas com todos os critérios executados com sucesso. Indisponibilidade de interação da autora, incompatibilidade de imagem ou decisão em aberto deixa a tarefa pendente/bloqueada. Sucesso do monitor não fecha a identidade nem demonstra incidentes persistentes.

## 9. Fontes e saída

Fontes consultadas em 25/10/2026, somente leitura:

- [Release 2.5.7](https://github.com/louislam/uptime-kuma/releases/tag/2.5.7).
- [README no tag: Docker, volume e publicação loopback](https://github.com/louislam/uptime-kuma/blob/2.5.7/README.md).
- [Campos do monitor na interface](https://github.com/louislam/uptime-kuma/blob/2.5.7/src/pages/EditMonitor.vue).
- [Provider Webhook](https://github.com/louislam/uptime-kuma/blob/2.5.7/server/notification-providers/webhook.js).

Na implementação, criar `docs/runbooks/monitoring.md` e `docs/evidence/03-monitoring.md` apenas com procedimentos/resultados reais e sanitizados. Não há imagem baixada, monitor configurado, payload capturado ou teste de runtime realizado nesta especificação.
