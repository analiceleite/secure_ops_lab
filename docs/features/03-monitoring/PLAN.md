# PLAN 03 — Monitoramento com Zabbix

**Estado:** em implementação desde 25/10/2026. M-D01–M-D06 e implementação em sequência aprovadas explicitamente pela autora. Iniciar por viabilidade e disponibilidade, depois segurança; sem IA e sem antecipar n8n. Fonte do comportamento/aceite: [SPEC](SPEC.md).

## 1. Gates e estado inicial

- Fundação e identidade concluídas. API sem publicação/mounts e somente em `service` interna. Keycloak 26.8.1/gateway existentes devem ser preservados, incluindo credenciais, TOTP, grupos, sessões e volume.
- Working tree estava limpa no início da revisão, após commit `5cacda4`. Rascunho Kuma substituído documentalmente, não migrado em runtime: nenhum Kuma foi instalado.
- A solicitação inicial autorizou somente revisão documental. Depois de apresentar M-D01–M-D06 e seus riscos, a autora respondeu “aprovado!”, autorizando implementação gradual. Preservar os limites e registrar cada validação; configuração manual e testes interativos ainda dependem da autora.
- Aprovar novas exceções locais e privilégios antes de aplicar. Não herdar automaticamente D01–D04 da identidade como autorização para frontend, banco ou coletor.
- Trabalhar uma tarefa por vez, registrar resultado e impedimentos; não criar n8n, IA, SMTP, webhook ou banco adicional de incidentes.

## 2. Artefatos da entrega

```text
compose.monitoring.yaml                  # implementado: server/frontend/banco; coletor pendente
infra/monitoring/10-create-zabbix-db.sh    # implementado: bootstrap sem superusuario permanente
scripts/Initialize-Monitoring.ps1        # implementado: segredos novos, recusa sobrescrita
scripts/Test-MonitoringInfrastructure.ps1 # implementado: configuracao e inspecao real
.local/monitoring/                       # criado, ignorado, jamais versionado
docs/runbooks/monitoring.md              # parcial: infraestrutura e primeiro acesso
docs/evidence/03-monitoring.md            # resultados reais, aceite parcial
```

Escolher nomes definitivos na implementação. Preferir Node simples e testes nativos, reaproveitando imagem local, sem framework novo. Export de configuração não inclui credenciais nem substitui procedimentos/evidências. Não exportar banco, realm ou histórico bruto de autenticação.

## 3. Tarefas e validação

### T01 — Aprovar desenho e confirmar viabilidade

- [x] M-D01–M-D06 aprovadas explicitamente após apresentação dos riscos e limites.
- [ ] Confirmar participação manual para painel, provisionamento autorizado e testes de navegador; nunca solicitar segredos ao chat.
- [x] Engine 28.5.1/Compose 2.40.2, Linux amd64, 12 CPUs/7,61 GiB; nenhum listener 8081 encontrado; API/Keycloak/gateway preservados. Tetos iniciais: banco/server 512 MiB cada e frontend 384 MiB, espera 180 s; medir na subida.
- [x] Tres imagens fixadas baixadas; entrypoints, bibliotecas pgsql/php/config e usuarios conferidos na propria imagem. Frontend contem curl/ping, banco pg_isready; server nao traz health check. Variaveis _FILE suportadas, DBPassword mascarado com DEBUG_MODE=false; caminhos de dados confirmados.
- [x] PostgreSQL inicializado como UID/GID 999; Zabbix como 1997:1995, sem capacidades e NoNewPrivs. Role zabbix criada sem superuser/createdb/createrole/replication; bootstrap exclusivo do banco. Validacao runtime na evidencia, nao apenas desenho.
- [x] Leitura administrativa separada e efemera: eventos persistidos desabilitados, LOGIN_ERROR entre tipos retornados, listener jboss-logging, admin events desabilitados, sslRequired=external e bruteForceProtected=false preexistente. Nenhuma configuracao/credencial de identidade alterada; nao atribuir ao projeto protecao brute force que nao esta habilitada.
- [ ] Filtros/ID/time/max e autorizacao conferidos estaticamente no codigo 26.8.1; leitura real de /events/config feita com administracao separada. Consulta completa por client tecnico e teto efetivo continuam pendentes em T05/T06; nao equivalem a permissao validada.
- [ ] Fechar expressões de trigger, tratamento de ausência de dados e contrato agregado, mantendo regras da SPEC; incompatibilidade de formato/limite exige revisão explícita.

**Gate de execução:** aprovação e viabilidade de exposição, imagens, usuários, volume e recursos verificadas antes da subida da infraestrutura de disponibilidade. MO-01 ainda é parcial: expressões reais do monitor dependem de T03 e permissão/contrato de segurança dependem de T05/T06. A separação evita presumir validação de uma configuração ainda não criada; nenhum cenário de segurança pode iniciar sem seu gate próprio. Não usar administrador como credencial permanente do coletor, leitura direta do banco Keycloak, plugin ou socket como atalho.

### T02 — Alinhar documentação e compor infraestrutura mínima

- [x] README/arquitetura/roadmap/topologia alinhados ao desenho aprovado, com disponibilidade em implementacao e coleta/n8n ainda nao implementados. Entregas 01/02 mantidas concluidas.
- [x] Overlay com server/frontend/PostgreSQL e redes aprovadas executado; somente 127.0.0.1:8081 publicado. Nenhum coletor existe ainda.
- [x] Redes de infraestrutura validadas estaticamente e em runtime; API identica a base. Rede do coletor sera adicionada apenas em T06.
- [x] Volume nomeado e role dedicada funcionando; dois segredos exclusivos em pasta com ACL restrita. Reexecucao do inicializador recusada com hashes preservados; mounts de segredo read-only e pasta fora do build/Git.
- [ ] Colocar coletor em profile explícito: base+monitoramento inicia disponibilidade sem identidade; composição completa permite segurança. Documentar habilitação/desabilitação dos itens/triggers de segurança no Zabbix conforme modo escolhido, preservando histórico: profile do Compose não muda configuração no banco. Registrar comandos exatos, sem `--remove-orphans` ou remoção de volumes.
- [x] Base, base+monitoramento e composicao completa resolvidas sem imprimir secrets; somente tres componentes novos iniciados com --no-deps/--pull never e espera 180 s. Containers/start times dos tres servicos existentes preservados.
- [x] 23 verificacoes estaticas e 42 no modo -Runtime aprovadas; negativos de senha TCP e IPv6 loopback, API/provedor preservados. Snapshots: banco 163,3 MiB, server 49,87 MiB, frontend 24,03 MiB; nao representam pico ou dimensionamento.

**Validação:** parte de MO-02. Se rede interna suprimir publicação, revisar desenho, nunca publicar em `0.0.0.0` como contorno.

### T03 — Proteger frontend e configurar disponibilidade

- [ ] Autora trocar senha administrativa padrão e desabilitar guest; documentar acesso inicial e cuidados sem coletar senhas. Confirmar painel protegido sem sessão e pós-logout.
- [ ] Conferir atributos de cookies/HTTP de acordo com exceção aprovada; não exportar cookie nem desativar proteção por tentativa e erro.
- [ ] Criar host lógico, web scenario e trigger Single conforme SPEC, validando item de falha e expressão na versão. Configurar detecção de ausência de resultados, sem apresentar último sucesso antigo como saúde atual.
- [ ] Aplicar retenção suportada de itens/eventos e registrar campos reais; configurar dashboard e tags. Separar configuração de housekeeping de expurgo observado.
- [ ] Observar duas execuções saudáveis, executar probe existente e registrar resposta/tempo sem inferir validação JSON que o cenário não executa.
- [ ] Em alvo auxiliar interno temporário, testar 500/redirect e ausência de resultados. Não alterar API nem destino do monitor principal permanentemente; limpar só recursos próprios do ensaio.

**Validação:** MO-02/MO-03. Configuração exportada e dashboard visual não bastam para comprovar detecção.

### T04 — Executar ciclos reais da API

- [ ] Registrar horário/fuso, parar somente `api`, observar falha do cenário e abertura do problema em até 60 s da parada confirmada.
- [ ] Manter parada por duas execuções adicionais e confirmar um problema ativo na trigger; server/frontend/banco continuam executando.
- [ ] Retomar somente API, aguardar saúde/probe e recuperação em até 60 s da saúde confirmada.
- [ ] Repetir ciclo sem apagar histórico; registrar eventos, duração observada e referências temporais separadas.

**Validação:** MO-04. Nunca usar `down`, endpoint de falha ou publicação temporária da API para o teste.

### T05 — Provisionar leitura de eventos sem mudar identidade dos usuários

- [ ] Com aprovação administrativa específica, registrar configuração anterior relevante e habilitar armazenamento de `LOGIN_ERROR`/retenção aprovada sem apagar histórico ou substituir tipos existentes inadvertidamente.
- [ ] Criar client técnico exclusivo, confidencial, service account, sem login interativo/password grant/redirects. Atribuir somente `realm-management/view-events`, sem grupos de aplicação nem roles de escrita/admin amplas.
- [ ] Preservar client OIDC/flow MFA da aplicação, scopes, mappers, grupos, senha/OTP e volume atuais. Não reinicializar realm nem rerodar inicializador de segredos da identidade.
- [ ] Confirmar leitura real de `/events/config` e consulta filtrada; verificar escrita negada com operação controlada sem mudança efetiva e estado antes/depois. Escolher operação segura antes do teste; se houver risco de alteração, bloquear e revisar, nunca tentar DELETE de eventos ou mutação de credenciais.
- [ ] Confirmar que a permissão de leitura alcança o realm inteiro, documentando esse limite; filtro por client não deve ser descrito como ACL do Keycloak.
- [ ] Guardar segredo exclusivo localmente, nunca exibir token, payload bruto, secret ou resposta integral de eventos. Provisionamento manual reproduzível no runbook; não depende de ferramenta paga ou API privada.

**Validação:** parte de MO-05/MO-09. Se `view-events` não bastar, investigar a causa antes de pedir privilégio adicional.

### T06 — Implementar e testar o coletor mínimo

- [ ] Implementar GET de métricas interno autenticado, com destino/realm/client/janela fixos, sem URLs arbitrárias e sem porta no host. Header secreto exclusivo; negar acesso inválido antes de consultar Keycloak.
- [ ] Obter/renovar token em memória com chamadas limitadas; ler configuração de eventos e validar persistência/tipos/retenção antes de contar.
- [ ] Consultar janela fixa de 300 s com filtros documentados e validação local, ID estável e prova de resposta completa. Respeitar limite de eventos, bytes, tempo e concorrência da SPEC; teto atingido/inconsistência não produz contagem parcial válida.
- [ ] Publicar somente agregado permitido; `collection_ok=0` omite contagem. Nenhum dump de corpo/headers e nenhuma cópia persistida dos eventos/credenciais.
- [ ] Criar testes nativos com issuer/API de fixture local: token negado/expirado, renovação limitada, 403, timeout, erro de transporte, JSON/schema inválido, eventos desabilitados e retenção incompatível.
- [ ] Testar janela vazia, 1/4/5 eventos, timestamps nas duas fronteiras e fora delas, outro client/tipo, duplicações, ID ausente, limite atingido e corpo excessivo. Garantir que polling repetido não soma a mesma janela.
- [ ] Testar endpoint sem/errado segredo e parâmetros não permitidos; verificar que não há consulta à fonte nos casos negados.
- [ ] Conferir sanitização de saída/logs em sucesso e falha, com marcadores fictícios de dados sensíveis; não usar credenciais reais nos testes.

**Validação:** MO-05 e parte de MO-07. Fixture demonstra contrato/casos extremos, não login real nem privilégio efetivo no realm.

### T07 — Integrar itens e testar cenário real de segurança

- [ ] Configurar HTTP agent e itens dependentes, descartando contagem inválida em vez de converter para zero. Fechar expressões reais de trigger Single e de falha/ausência de coleta.
- [ ] Início sem amostra válida aparece desconhecido; perda de frescor não encerra problema de autenticação aberto. Testar explicitamente esse comportamento antes dos ensaios manuais.
- [ ] Verificar relógios e aguardar janela limpa sem excluir eventos. Autora inicia login pela aplicação com conta fictícia e produz um erro isolado: coleta incrementa, alerta de segurança não abre.
- [ ] Completar sequência até ≥5 eventos dentro de 5 min sem enfraquecer brute force/MFA. Conferir eventos efetivamente gerados e abertura até 60 s do quinto evento persistido; não equiparar submissão/evento sem observação.
- [ ] Manter condição por várias amostras e confirmar um só problema; aguardar esvaziamento natural e recuperação em até 60 s após contagem válida ficar abaixo do limiar.
- [ ] Repetir segundo ciclo. Login bem-sucedido não limpa histórico da janela; registrar essa distinção.
- [ ] Testar login da operadora com senha+OTP e visitante autenticada 403. Confirmar que sucesso/negação de autorização não geram incremento indevido de LOGIN_ERROR; teste de filtro de outro client pode combinar observação manual e fixture, com origem explícita.

**Validação:** MO-06/MO-09. Regra é agregado de eventos do client, não reputação de IP/usuário nem confirmação de ataque.

### T08 — Falhas de coleta e persistência

- [ ] Com problema de autenticação aberto, indisponibilizar fonte/coletor em ensaios separados e autorizados: nenhum zero ou recuperação indevida. Problema técnico detectado até 120 s; frontend responder não significa fonte saudável.
- [ ] Para falha da fonte real, parar somente Keycloak e retomar com volume existente, aguardando discovery. API saudável deve permanecer saudável no monitor interno; novos logins devem falhar enquanto provedor está parado. Não prometer revogação imediata de sessão gateway existente.
- [ ] Testar credencial inválida/eventos desabilitados/schema/teto com fixtures, evitando estragar credenciais/configuração real. Registrar o que foi e não foi demonstrado em runtime real.
- [ ] Retomar fonte/coletor e confirmar amostra completa antes de recuperar problema técnico e reavaliar alerta de segurança.
- [ ] Reiniciar e depois recriar somente componentes novos com volumes preservados, incluindo banco/frontend/server/coletor; conferir conta, configuração, dashboard, histórico/eventos e novo ciclo de disponibilidade.
- [ ] Reinício do coletor deve reconstruir janela a partir de eventos persistidos, sem duplicar contagem. Confirmar retomada com amostra válida, não zero de inicialização.
- [ ] Registrar retenções configuradas, lacunas durante monitor parado e limites de reconstrução. Não excluir volumes, eventos ou credenciais para repetir testes.

**Validação:** MO-07/MO-08 e complemento de MO-09. Registrar datas/horários e restaurar todos os serviços/configurações alterados pelo ensaio.

### T09 — Regressão, reprodução e fechamento

- [ ] Reexecutar suites existentes: 35 testes API, 10 estáticos de identidade e 12 verificações isoladas do proxy; executar novos testes do coletor sem inventar contagem antecipada. Discovery e probe aprovados.
- [ ] Revalidar configurações resolvidas e bindings reais nas composições; API sem portas/mounts e só em `service`. Verificar perfis que permitem disponibilidade sem identidade e cenário completo com identidade.
- [ ] Confirmar manualmente operadora permitida, visitante negada e política de sessão/MFA preservada, sem repetir cadastro OTP ou mudar grupos por conveniência.
- [ ] Registrar tags/IDs e problemas/recuperações reais úteis à futura integração, sem configurar webhook ou afirmar contrato n8n validado.
- [ ] Escrever e repetir runbook: bootstrap seguro, perfil de segurança, configuração pela UI/API documentada, início/parada, testes, persistência e retomada. Distinguir autoria técnica e relatos de navegador.
- [ ] Consolidar MO-01–MO-10 em evidências reais; revisar logs, exports, screenshots e links. Varredura de segredos é limitada e não equivale a garantia universal.
- [ ] Atualizar PLAN/roadmap somente conforme estado real. Concluir apenas com todos os critérios verificados; nenhum commit/push automático.

**Gate final:** MO-01–MO-10 aprovados. Entrega 04 permanece não implementada; problema único no Zabbix não comprova deduplicação ou entrega de futuras notificações.

## 4. Registro de execução

| Data | Atividade | Resultado real | Pendência |
| --- | --- | --- | --- |
| 25/10/2026 | Rascunho inicial | SPEC/PLAN descreviam Kuma; nenhum monitor implementado | Desenho substituído por esta revisão, não usar tarefas/opções antigas |
| 25/10/2026 | Aprovação funcional em conversa | Autora concordou com Zabbix, disponibilidade e cenário pequeno de LOGIN_ERROR; n8n depois, sem IA | Aprovar novas decisões técnicas M-D01–M-D06 antes da implementação |
| 25/10/2026 | Revisão documental solicitada | Arquivos Compose/config existentes inspecionados; docs Zabbix 7.0/Keycloak 26.8.1, código de autorização/filtros e metadados de três imagens consultados somente por HTTP; SPEC/PLAN reescritos | Sem pull, client, evento real ou teste de runtime; validar viabilidade e contrato antes de implementar |
| 25/10/2026 | Validação estática dos documentos | `git diff --check` aprovado; sete links locais com destinos existentes; MO-01–MO-10 presentes nos dois documentos e M-D01–M-D06 definidos na SPEC | Não valida links externos/âncoras, expressões executáveis, infraestrutura ou critérios de runtime |
| 25/10/2026 | Aprovacao e inicio T01/T02 | Autora aprovou M-D01–M-D06 e implementacao; imagens baixadas, scripts/overlay escritos, banco inicializado nao root e schema Zabbix importado com role nao superuser | Gate de disponibilidade separado da verificacao runtime da coleta; nenhum client/evento provisionado |
| 25/10/2026, 11:20–11:24 -03:00 | Infraestrutura real | Server 7.0.32 iniciou, schema 07000000/07000030; frontend ping 200/API 7.0.32. 23 estaticos/42 runtime aprovados. Guest pertence ao grupo Disabled; anonimo recebeu aviso de nao autenticado | Troca de senha Admin e validacao manual do painel pendentes; nenhum cenario web configurado |
| 25/10/2026 | Regressao antecipada apos novas redes | 35 API (5799.136844 ms), 10 estaticos identidade (227.398807 ms), 12 verificacoes OIDC isoladas aprovados; probe/discovery aprovados | Nao substitui regressao final T09 nem testes manuais; entrega permanece em implementacao |

## 5. Checklist de conclusão — entrega ainda parcial

- [ ] M-D01–M-D06 resolvidas, viabilidade confirmada e implementação autorizada.
- [ ] MO-01–MO-10 executados com sucesso, com origem/limites de cada evidência.
- [ ] API intacta; painel autenticado em loopback; banco/coletor/server sem publicação/socket/privilégios não aprovados.
- [ ] Dois ciclos de queda/recuperação e dois ciclos de segurança validados com tempos reais.
- [ ] Coleta mínima, autenticada e restrita; falha/ausência de dados não viram saúde ou recuperação indevida.
- [ ] Conta/configuração/histórico persistentes; identidade/MFA/grupos preservados.
- [ ] Runbook reproduzido, regressão aprovada e documentação compartilhada alinhada.
- [ ] Evidências/exports sanitizados; nenhuma IA, n8n, SMTP ou automação futura implementada.
