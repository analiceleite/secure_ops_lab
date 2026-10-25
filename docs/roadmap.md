# Roadmap de implementação

> Status: Fundação Local concluída em 24/10/2026, com 35 testes aprovados via Compose, inspeções de runtime e ciclo de parada/recuperação repetido. Identidade e acesso em especificação; demais entregas não iniciadas.

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

A ordem sugerida de trabalho é 01 → 02 → 03 → 04 → 05. O monitoramento depende da fundação, mas pode ser trabalhado antes da identidade caso exista um bloqueio explícito, sem contornar controles de acesso.

## Visão geral

| Entrega | Estado | Documentação prevista |
| --- | --- | --- |
| 01 — Fundação local | Concluída | `features/01-local-foundation/{SPEC,PLAN}.md` |
| 02 — Identidade e acesso | Em especificação | `features/02-identity-access/{SPEC,PLAN}.md` |
| 03 — Monitoramento | Não iniciada | `features/03-monitoring/{SPEC,PLAN}.md` |
| 04 — Automação de incidentes | Não iniciada | `features/04-incident-automation/{SPEC,PLAN}.md` |
| 05 — Validação integrada e demonstração | Não iniciada | Checklist transversal, runbook e evidências |

Os caminhos da tabela são relativos a `docs/`. A Fundação Local possui [SPEC](features/01-local-foundation/SPEC.md) e [PLAN](features/01-local-foundation/PLAN.md), com T01 a T06 concluídas e [evidências](evidence/01-local-foundation.md). Identidade e acesso possui [SPEC](features/02-identity-access/SPEC.md) e [PLAN](features/02-identity-access/PLAN.md) propostos, sem implementação. Próximo passo: revisar decisões D01–D03 e autorizar preparação T01; HTTP/cookies de desenvolvimento não estão aprovados implicitamente.

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

- [ ] Sem sessão, o navegador precisa se autenticar.
- [ ] A conta autorizada precisa concluir MFA para entrar.
- [ ] A conta autenticada sem permissão tem o acesso negado pelo gateway.
- [ ] A API continua sem acesso direto por porta publicada.
- [ ] Emissor OIDC, redirects e transporte funcionam sem desabilitar validações de tokens.
- [ ] Exceções locais, caso necessárias, estão justificadas e documentadas.

## 03 — Monitoramento

**Resultado:** o monitor detecta queda e recuperação da API pela rede interna.

Escopo da especificação:

- Configurar Uptime Kuma, persistência e administração local.
- Definir intervalos, tolerância a falhas e notificações de estado.
- Inspecionar e documentar o payload real da integração com webhook.
- Definir procedimento seguro de parar e iniciar apenas o container da API.

Critérios de saída:

- [ ] API saudável aparece disponível.
- [ ] Parar somente a API provoca detecção de indisponibilidade.
- [ ] Monitor e demais componentes necessários continuam executando.
- [ ] Reiniciar a API provoca detecção de recuperação.
- [ ] Configuração do monitor sobrevive a reinício sem exclusão do volume.
- [ ] Tempos observados e limites da verificação interna estão documentados.

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
