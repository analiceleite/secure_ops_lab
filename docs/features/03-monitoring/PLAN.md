# PLAN 03 — Monitoramento

**Estado:** em especificação. Rascunho inicial com Uptime Kuma; após fechamento da entrega 02, revisar para intenção de Zabbix antes de aprovar/implementar. Nenhum monitor implementado. Fonte de comportamento e aceite: [SPEC](SPEC.md).

## 1. Gates e estado inicial

- Fundação concluída; `compose.yaml` contém API, probe, suite de teste e rede `service` interna. API sem porta publicada.
- Identidade concluída em 25/10, com matriz IA-01–IA-12 e origem manual/técnica das evidências. Não dispensar regressão de isolamento na implementação futura do monitoramento.
- A autora solicitou preparar SPEC/PLAN 03 em paralelo. Isso não autoriza iniciar monitoramento, mudar controles da identidade nem encerrar a entrega 02.
- Aprovar M-D01–M-D05 antes de implementar. Confirmar opções na versão fixada; divergência exige revisar a SPEC, não improvisar flags ou enfraquecer segurança.
- Não apagar volumes, recriar realm, alterar credenciais existentes, publicar API ou usar sistemas externos para testes.

## 2. Arquivos previstos — ainda não implementados

```text
compose.monitoring.yaml                # overlay independente; base preservada
infra/monitoring/                      # auxiliar/testes mínimos, se necessários
docs/runbooks/monitoring.md            # passos reais, inclusive interface manual
docs/evidence/03-monitoring.md         # resultados sanitizados por MO-01–MO-09
```

Reaproveitar Node/imagem local para o auxiliar, sem bibliotecas adicionais. Credenciais e dados gerados ficam fora do Git/build; volume não é um artefato versionável. Não criar export de banco/configuração com credenciais para substituir um runbook.

## 3. Tarefas e validação

### T01 — Revisar decisões e viabilidade

- [ ] Revisar M-D01–M-D05 com a autora; confirmar conta fictícia e participação na configuração manual.
- [ ] Conferir estado real de Docker/Compose, containers e redes sem parar serviços existentes; verificar conflito da porta 3001.
- [ ] Confirmar imagem exata 2.5.7, manifesto `linux/amd64`, digest, usuário, diretório de dados e health check disponível.
- [ ] Verificar opções reais de timeout, códigos aceitos, redirects, retries, reenvio e retenção de sete dias; registrar campos exatos no runbook.
- [ ] Conferir usuário não root/capabilities, permissões do volume e recursos. Apresentar incompatibilidades antes de mudar a proposta.

**Gate:** MO-01; sem aprovação/viabilidade, não iniciar T02. Não fixar digest inventado nem afirmar configuração suportada só porque há campo parecido na UI.

### T02 — Compor monitoramento sem alterar a API

- [ ] Criar overlay com imagem fixada, redes/volume aprovados, porta loopback, logs limitados e restrições compatíveis.
- [ ] Manter `api` idêntica à base: sem porta, sem mount e somente em `service`. Kuma não participa de `identity`.
- [ ] Validar base + monitoramento e base + identidade + monitoramento, sem imprimir segredos interpolados.
- [ ] Iniciar somente serviços autorizados com prazo finito; validar prontidão com recurso real da imagem/cliente existente, sem instalar ferramenta extra.
- [ ] Inspecionar bindings efetivos, redes, usuário, capacidades, NoNewPrivs, memória e mounts seletivamente.

**Validação:** parte de MO-02; configuração estática não substitui binding observado. Se rede interna suprimir publicação, parar e revisar, sem publicar em todas as interfaces como contorno.

### T03 — Configurar administração e monitor

- [ ] Autora criar administrador fictício com senha local exclusiva; não coletar segredo.
- [ ] Validar painel sem sessão e pós-logout; documentar cookie/transporte sem exportar cookie. Nenhuma desativação não aprovada.
- [ ] Configurar manualmente monitor conforme SPEC, sem credenciais para a API nem status page pública.
- [ ] Registrar passos, retenção efetivamente aplicada e pelo menos dois heartbeats saudáveis; executar probe da fundação.

**Validação:** MO-02/MO-03; HTTP 200 do Kuma é distinto do contrato JSON mais estrito do probe.

### T04 — Preparar captura diagnóstica interna

- [ ] Implementar auxiliar temporário no profile `tools`, sem porta no host, independente da API e sem acesso a segredos/volumes dela.
- [ ] Limitar corpo a 64 KiB, aceitar POST JSON e validar formato básico; erros 4xx para entradas inválidas, sem refletir payload em logs.
- [ ] Emitir apenas campos permitidos e sanitizados de monitor/heartbeat/mensagem; não registrar headers nem configuração completa do monitor. Mensagem precisa de revisão antes de virar evidência.
- [ ] Testar auxiliar localmente: válido, JSON inválido e corpo acima do limite; sem modificar incidentes nem introduzir autenticação definitiva.
- [ ] Configurar Webhook POST JSON padrão para o auxiliar; registrar teste manual separadamente de transições reais.

**Validação:** preparação MO-07/MO-08. Não criar receptor público, fila ou banco de incidentes. Não confundir o código de captura com automação concluída.

### T05 — Executar queda, recuperação e repetição

- [ ] Usar `docker compose stop api` na raiz para parar somente a API; registrar horários/fuso, estado e heartbeat DOWN.
- [ ] Confirmar monitor/auxiliar vivos; aguardar pelo menos dois intervalos adicionais e observar se há notificações repetidas.
- [ ] Retomar com `docker compose up -d --wait --wait-timeout 60 api`; conferir probe e heartbeat UP.
- [ ] Medir DOWN/UP contra meta de 60 s, separando parada/saúde, heartbeat e recebimento.
- [ ] Repetir ciclo e registrar payloads reais sanitizados; conferir valores/tipos de status, IDs fictícios, timestamps e objetos ausentes no teste manual.

**Validação:** MO-04/MO-05/MO-07. Registrar falhas honestamente; não somar tempo de startup à latência do monitor sem explicar a referência.

### T06 — Persistência e caminhos de falha

- [ ] Reiniciar apenas Kuma, sem apagar volume, e comprovar conta/configuração/histórico e novos heartbeats.
- [ ] Recriar apenas o container de Kuma mantendo volume nomeado e comprovar novamente; não remover/recriar dados.
- [ ] Testar resposta não 200 e redirect em alvo temporário interno, sem mudar a API; confirmar monitor de teste não declara UP indevido. Remover somente a configuração temporária criada para esse teste.
- [ ] Indisponibilizar receptor durante uma transição; verificar erro de entrega, independência do monitor e comportamento real de retry/reenvio após retorno.
- [ ] Executar novo ciclo com receptor disponível para confirmar recuperação da integração. Documentar lacuna de observação quando Kuma fica parado.

**Validação:** MO-06/MO-08; falha de webhook não é falha do health check. Não prometer replay após retorno sem evidência.

### T07 — Regressão e fechamento

- [ ] Reexecutar 35 testes da API e 10 testes estáticos de identidade com comandos existentes; executar probe.
- [ ] Revalidar composições e bindings reais; API permanece sem porta e só na rede interna. Não iniciar gateway para declarar regressão de navegador não executada.
- [ ] Registrar versões/digests, consumo observado e resultados por MO-01–MO-09; distinguir testes automáticos de ações manuais da autora.
- [ ] Escrever/repetir runbook com início, configuração manual, falha/recuperação, persistência e parada preservando dados.
- [ ] Revisar evidências/links/whitespace e ausência de segredos; atualizar README/arquitetura/roadmap só conforme resultados.

**Gate final:** todos os critérios aprovados. Persistência do Kuma não comprova persistência/deduplicação de incidentes. Não iniciar entrega 04 nesta tarefa.

## 4. Registro de execução

| Data | Tarefa | Resultado real | Pendência |
| --- | --- | --- | --- |
| 25/10/2026 | Preparação documental | README, arquitetura, roadmap, Compose/probe e estado da identidade inspecionados; release e fontes 2.5.7 consultadas; SPEC/PLAN redigidos | Revisar propostas; nenhum serviço/auxiliar implementado ou teste de runtime executado |

## 5. Checklist de conclusão

- [ ] M-D01–M-D05 explicitamente resolvidas e implementação autorizada.
- [ ] MO-01–MO-09 executados com sucesso e evidências sanitizadas.
- [ ] Nenhuma porta da API publicada; painel só em loopback e autenticado.
- [ ] Queda/recuperação repetidas, tempos medidos e notificações reais inspecionadas.
- [ ] Configuração/histórico persistentes após reinício e recriação sem exclusão do volume.
- [ ] Falhas de alvo/receptor e limites de entrega/observação documentados.
- [ ] Runbook repetido, regressão aprovada e estado da identidade mantido fiel ao executado.
