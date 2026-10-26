# Entrega 04 — matriz de aceite parcial (26/10/2026)

**Demo mínima funcional entregue; aceite integral não concluído.** A autora pediu encerrar testes extensos e priorizar validação de conceitos/entrevista. [Roteiro](../runbooks/interview-demo.md). IA tem alucinação causal conhecida inclusive no prompt2; não é diagnóstico. As lacunas abaixo são evoluções/pendências documentadas, não gates falsamente aprovados. Resultados detalhados nas [evidências](04-incident-automation.md); referência normativa na [SPEC](../features/04-incident-automation/SPEC.md).

| Critério | Estado verificado e lacuna |
| --- | --- |
| IA-01 | Seleção/digests/licenças documentados; macros reais problem/recovery observadas; migrações 1/2/3 ativas. Viabilidade técnica provada, revisão final de todos os gates ainda parcial. |
| IA-02 | 82 checks estáticos/runtime e interfaces passaram; API/receptor/banco sem portas, UIs loopback autenticadas. Diagnóstico temporário voltou a warn/progress=false; varredura final de segredos pendente. |
| IA-03 | Receptor efêmero: 139 checks principais, 7 resume, 4 offline; negativos HTTP/SQL/contrato sem alteração indevida. Sem teste externo. |
| IA-04 | Cinco ciclos reais de disponibilidade, incidentes 1–5 distintos/fechados. #4: eventos 159/160, 41 s; #5: eventos 161/162, 40 s. |
| IA-05 | Fixture: 1 applied/19 duplicates, corrida de condição e rollback; após restart, 20 replays concorrentes reais do evento 161 retornaram duplicate, contadores 10 deliveries/5 incidentes/5 jobs/2 outbox inalterados. |
| IA-06 | Transições/correlação/fora de ordem exercitadas na fixture SQL (86 checks), não confundir com inversão de eventos reais no Zabbix. |
| IA-07 | Perda de ACK/banco offline 503 na fixture; n8n parado em ciclo real #5 manteve incidente fechado/job pending com 0 tentativas. Retomada produziu ready/accepted na primeira tentativa. Retry/esgotamento/replay real do media type com receptor/banco indisponível ainda pendente. |
| IA-08 | Restart de automation-db/receptor e stop/start n8n preservaram incidentes/jobs/credenciais; replay real após restart não duplicou. Recriação completa do banco/volume sem perda e novo ciclo pós-recriação ainda pendentes. |
| IA-09 | Coleta real trigger 25232 abriu/fechou incidente #6 sem alterar disponibilidade. Ciclo LOGIN_ERROR integrado, falha de coleta durante autenticação aberta e 403 visitante sem LOGIN_ERROR ainda dependem da autora no navegador. Evidência antiga da entrega 03 não substitui esse ensaio integrado. |
| IA-10 | 35 testes API; verificador isolado gateway positivo/negativos; discovery; 39 testes coletor +16 configuração/alvo; TypeScript; monitor final; isolamento do banco; 9 workflow/webhook; 6 integridade do modelo. MFA/acesso real após mudanças requerem confirmação manual. |
| IA-11 | #4/prompt1 e #5/prompt2 gerados por Ollama real, HTML persistido e Mailpit confirmado por API autenticada. #4 rejeitado semanticamente por causa afirmada sem evidência, preservado. #5 usa hipótese especulativa genérica, não causa confirmada; revisão humana ainda pendente. |
| IA-12 | Template escapa HTML e identifica IA/hipóteses/limites. Schema rejeita tipos/campos/comprimentos inválidos; XSS escapado em fixture; mensagens #4/#5 sem HTML ativo/recursos remotos conforme inspeção automatizada. Prompt injection real/saída truncada e renderização em navegador ainda pendentes; não prometer impossibilidade de alucinação. |
| IA-13 | Jobs/outbox/leases/aceite/unknown na fixture (15 checks), dois relatórios reais accepted com 1 tentativa. IA offline real: job #6 failed/2, sem outbox. SMTP offline real: #7 ready, outbox unknown/1, sem reenvio após retomada. Crash após aceite e retry pré-aceite em runtime pendentes; fluxo não implementa ainda retries explícitos de rejeição SMTP comprovadamente pré-aceite. |
| IA-14 | Limites Compose e redes verificados, sem cloud/relay/portas Ollama/SMTP. Mensagem #4 permaneceu após restart Mailpit/Ollama/n8n; #5 entregue após restart do banco/receptor/n8n. Monitor final passou; impacto sob inferência com MFA interativa ainda não testado. |

## Revisão humana necessária

Em `http://127.0.0.1:8025`, abrir **SecureOps | Relatório #5 v1** (prompt 2; versão de relatório 1). Verificar HTML/texto, fatos, hipóteses explicitamente não confirmadas e limitações. A hipótese genérica de rede/hardware/software **não é diagnóstico validado**, e não deve ser defendida como causa raiz. Não compartilhar senha, cookie ou export bruto.

Relatório #4 permanece como resultado de ensaio rejeitado, não como relatório aprovado. Jobs 1–3 failed não foram apagados/reenfileirados. A quantidade de registros não mede a quantidade de critérios concluídos.
