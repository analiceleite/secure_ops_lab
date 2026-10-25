# Roadmap de implementação

> Status: Fundação Local e Identidade concluídas. Monitoramento com Zabbix em implementação após aprovação explícita M-D01–M-D06 em 25/10/2026: disponibilidade primeiro, depois cenário de falhas de autenticação. Coleta ainda não implementada; n8n fica para entrega 04, sem IA. Nenhum critério 03 é presumido pela aprovação.

## Como usar

Para cada entrega, escrever e revisar primeiro o `SPEC.md`, depois o `PLAN.md`. Implementar em pequenas tarefas, executar as validações e registrar evidências sanitizadas.

Estados permitidos: **não iniciada**, **em especificação**, **pronta para implementar**, **em implementação**, **em validação**, **concluída** e **bloqueada**. Informar o motivo e a próxima ação quando houver bloqueio.

Não marcar uma entrega como concluída com base apenas em código gerado ou leitura de configuração.

## Sequência e dependências

```text
01 Fundação local
 ├── 02 Identidade e acesso
 └── 03 Monitoramento
       └── 04 Automação de incidentes

02 + 03 + 04 → 05 Validação integrada e demonstração
```

A ordem é 01 → 02 → 03 → 04 → 05. Disponibilidade depende da fundação; cenário de segurança também depende da identidade. Após o rascunho antecipado e fechamento 02, a autora aprovou a substituição por Zabbix e autorizou a implementação gradual; essa aprovação não dispensa validações nem autoriza ampliar escopo.

## Visão geral

| Entrega | Estado | Documentação prevista |
| --- | --- | --- |
| 01 — Fundação local | Concluída | `features/01-local-foundation/{SPEC,PLAN}.md` |
| 02 — Identidade e acesso | Concluída | [SPEC](features/02-identity-access/SPEC.md) / [PLAN](features/02-identity-access/PLAN.md) |
| 03 — Monitoramento | Em implementação | [SPEC](features/03-monitoring/SPEC.md) / [PLAN](features/03-monitoring/PLAN.md) |
| 04 — Automação de incidentes | Não iniciada | `features/04-incident-automation/{SPEC,PLAN}.md` |
| 05 — Validação integrada e demonstração | Não iniciada | Checklist transversal, runbook e evidências |

Os caminhos são relativos a `docs/`. Identidade possui [matriz final](evidence/02-identity-access.md), [PLAN concluído](features/02-identity-access/PLAN.md) e [runbook](runbooks/identity-access.md); regressão do fechamento: 35 API + 10 estáticos + 12 verificações isoladas aprovados. API segue somente em rede interna sem porta. Zabbix substitui o desenho Kuma; problemas/recuperações nativos não substituem os critérios futuros de automação. Estado real da nova infraestrutura no PLAN 03.

## 01 — Fundação local

**Resultado:** uma API mínima executa no Compose, é verificável internamente e não expõe sua porta no host.

Escopo da especificação:

- Verificar pré-requisitos no Windows, Docker com containers Linux, recursos e conflitos de portas.
- Definir versões explícitas, estrutura mínima da API e configuração do Compose.
- Definir `/health`, página ou resposta demonstrável e logs sem segredos.
- Planejar redes, configuração de ambiente e arquivos ignorados pelo controle de versão.
- Definir validação interna sem adicionar uma porta de desenvolvimento à API.

Critérios de saída:

- [x] API inicia e responde ao health check pela rede Docker.
- [x] Não há porta da API publicada no host.
- [x] Logs permitem diagnosticar inicialização e falha sem dados sensíveis.
- [x] Instruções de início, parada e validação foram testadas.

## 02 — Identidade e acesso

**Resultado:** operadora autorizada acessa com MFA; visitante autenticada é bloqueada.

Escopo da especificação:

- Resolver transporte local e endereçamento OIDC antes de configurar o fluxo.
- Definir Keycloak, OAuth2 Proxy, client, grupos ou claims e sessões.
- Configurar duas contas fictícias e cadastro TOTP com passos reproduzíveis.
- Limitar as portas publicadas ao loopback.
- Documentar comportamento de logout, expiração e limites de revogação de sessões.

Critérios de saída:

- [x] Sem sessão, o navegador precisa se autenticar.
- [x] A conta autorizada precisa concluir MFA para entrar.
- [x] A conta autenticada sem permissão tem o acesso negado pelo gateway.
- [x] A API continua sem acesso direto por porta publicada.
- [x] Emissor OIDC, redirects e transporte funcionam sem desabilitar validações de tokens.
- [x] Exceções HTTP/dev-file/rede local justificadas, aprovadas e documentadas, sem alegar produção.

## 03 — Monitoramento

**Resultado esperado:** Zabbix detecta queda/recuperação da API e falhas repetidas de autenticação, sem confundir falha da coleta com ausência de erros.

Escopo da especificação:

- Configurar Zabbix server/frontend/PostgreSQL com persistência e administração local.
- Detectar disponibilidade interna e ausência de resultados; testar dois ciclos de queda/recuperação.
- Ler eventos do Keycloak com client técnico restrito, entregando somente agregado sanitizado.
- Alertar com pelo menos cinco LOGIN_ERROR em cinco minutos e detectar falha da própria coleta.
- Preservar identidade/MFA e preparar referências de eventos, sem webhook/n8n nesta entrega.

Critérios de saída:

- [ ] API saudável aparece disponível.
- [ ] Parar somente a API provoca detecção de indisponibilidade.
- [ ] Monitor e demais componentes necessários continuam executando.
- [ ] Reiniciar a API provoca detecção de recuperação.
- [ ] Configuração do monitor sobrevive a reinício sem exclusão do volume.
- [ ] Tempos observados e limites da verificação interna estão documentados.
- [ ] Regra de autenticação, falhas de coleta, persistência e regressão verificadas conforme MO-01–MO-10 da SPEC.

## 04 — Automação de incidentes

**Resultado:** eventos reais do monitor geram um ciclo persistente de abertura e encerramento, sem duplicação de incidentes abertos.

Escopo da especificação:

- Definir contrato e autenticação do webhook conforme capacidades reais das ferramentas.
- Escolher armazenamento local consultável e regras de consistência.
- Definir identificação do serviço, timestamps e duração observada.
- Tratar eventos inválidos, repetidos, simultâneos, fora de ordem e recuperação sem incidente aberto.
- Definir falhas de entrega ou armazenamento e limites de retries.
- Exportar workflow sem credenciais e documentar importação/configuração.

Critérios de saída:

- [ ] Webhook sem autenticação válida ou com payload inválido não altera incidentes.
- [ ] Falha real abre um incidente para o serviço correto.
- [ ] Repetição da falha não cria outro incidente aberto para o mesmo serviço.
- [ ] Reinício da automação preserva o estado necessário à deduplicação.
- [ ] Recuperação encerra o incidente e registra duração coerente.
- [ ] Recuperação repetida ou isolada não cria incidente indevido.
- [ ] Um novo ciclo de queda após encerramento pode abrir um novo incidente.
- [ ] Limites para eventos fora de ordem e falhas de entrega foram testados e registrados.

## 05 — Validação integrada e demonstração

**Resultado:** uma pessoa consegue reproduzir o fluxo completo seguindo a documentação.

Esta é uma etapa transversal, não uma nova funcionalidade. Usar os critérios das SPECS como referência, sem duplicá-los em uma quinta SPEC desnecessária.

- [ ] Repetir os testes de acesso autorizado, MFA e acesso negado no navegador.
- [ ] Executar queda → detecção → incidente → recuperação → encerramento.
- [ ] Repetir o ciclo e conferir ausência de duplicações indevidas.
- [ ] Verificar persistência após reinício sem apagar volumes.
- [ ] Criar um runbook em `docs/runbooks/` com diagnóstico, recuperação e cuidados com dados.
- [ ] Registrar relato do incidente simulado e evidências sanitizadas em `docs/evidence/`.
- [ ] Atualizar o README com versões, comandos e resultados reais.
- [ ] Conferir que nenhum segredo entrou nos arquivos ou nas evidências.
- [ ] Preparar uma demonstração de 3–5 minutos, explicando também as limitações.

## Organização sugerida do fim de semana

**Sábado:** especificar e implementar a fundação e o acesso por identidade. Dar prioridade às decisões de OIDC e transporte, que podem bloquear o login.

**Domingo:** implementar monitoramento, automação e validação integrada. Reservar tempo para a documentação e a demonstração.

É uma meta de organização, não uma estimativa garantida. Se houver impedimento, registrar a entrega parcial e os critérios pendentes; não enfraquecer controles nem chamar o escopo inteiro de concluído.

## Extensões fora do caminho principal

- WAF com ModSecurity e OWASP Core Rule Set.
- Monitoramento sintético do caminho do usuário, incluindo gateway e identidade.
- Estratégia de backup e restauração validada.

Somente avaliar extensões após a demonstração principal funcionar e mediante decisão explícita de ampliar o escopo. Nenhuma extensão deve exigir serviço pago.
