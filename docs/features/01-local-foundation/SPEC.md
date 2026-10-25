# SPEC 01 — Fundação local

**Estado:** concluída em 24/10/2026 (`-03:00`). T01 a T06 executadas; FL-01 a FL-09 comprovados nas evidências, com 35 testes aprovados e ciclo de parada/recuperação repetido. Isso conclui somente a Fundação Local, não o laboratório completo.

Referências: [README](../../../README.md), [arquitetura](../../architecture.md) e [roadmap](../../roadmap.md).

## 1. Objetivo

Executar uma API fictícia com Docker Compose, verificável pela rede interna e sem porta publicada no computador. Criar uma base pequena e reproduzível para adicionar identidade, monitoramento e automação nas próximas entregas.

## 2. Escopo

Incluído:

- API Node.js + TypeScript com respostas fictícias e sem banco de dados.
- Build, testes automatizados, imagem de execução e Compose.
- Health check, logs mínimos e encerramento controlado.
- Rede de serviço e um cliente temporário para validar acesso entre containers.
- Arquivos de exclusão, instruções de execução e evidências sanitizadas.

Não incluído:

- Keycloak, gateway, autenticação, MFA, Uptime Kuma ou n8n.
- Portas publicadas, acesso pelo navegador do host ou túneis.
- Persistência de dados de negócio, volumes ou segredos necessários à API.
- HTTPS, regras de firewall, WAF ou dependências externas em runtime.

Nesta entrega, a API ainda não é protegida por identidade. A restrição demonstrada é a ausência de uma porta publicada e o acesso por rede Docker; não apresentar isso como autorização ou isolamento absoluto.

## 3. Pré-requisitos e viabilidade

- Windows com Docker disponível e daemon configurado para containers Linux.
- Docker Compose V2 com suporte à configuração utilizada, verificado antes da implementação.
- Internet para downloads iniciais de imagens e pacotes; a API não depende de internet para atender requisições depois do build.
- Espaço e memória suficientes para o build e execução. Registrar consumo observado e ambiente de teste, sem inventar um requisito mínimo para o laboratório completo.

Node.js instalado no host não deve ser obrigatório: build e testes precisam ter um caminho via containers. Instalar ou alterar Docker/WSL no computador exige orientação e autorização da autora; não fazer mudanças de sistema silenciosamente.

## 4. Decisões adotadas

| Tema | Decisão |
| --- | --- |
| Serviço Compose | `api` |
| Linguagem e runtime | TypeScript compilado para JavaScript; Node.js `24.22.1` LTS, imagem `node:24.22.1-bookworm-slim` |
| Compilador e tipos | `typescript` `5.9.3` e `@types/node` `24.19.2`, sem intervalos de versão nas dependências diretas |
| Dependências | HTTP e testes com módulos nativos do Node; TypeScript e tipos apenas no desenvolvimento/build |
| Gerenciador | npm, com lockfile versionado e instalação reproduzível |
| Porta interna | TCP `3000`, sem `ports` no Compose |
| Bind no container | `0.0.0.0`, necessário para clientes na rede Docker |
| Rede lógica | `service`, bridge com `internal: true`, sem nome global fixo |
| DNS interno | `api`, sem `container_name` fixo |
| Cliente de validação | Serviço auxiliar `probe`, executado sob demanda e ligado apenas à rede `service` |
| Imagem do probe | Reutilizar o runtime da API e um script Node, sem adicionar ferramenta de terceiros |
| Persistência | Nenhuma nesta entrega |

Versões e disponibilidade foram conferidas em T01; fontes e resultados estão nas [evidências](../../evidence/01-local-foundation.md). TypeScript 5.9.3 foi escolhido por ser suficiente para a API e não ter dependências próprias no pacote publicado, evitando adotar uma nova major sem necessidade. Isso não significa que seja a versão mais recente. Não usar `latest`; atualizar versões exige registrar a mudança e repetir build e testes.

A tag Node possui manifesto `linux/amd64`; foi usada em T02 e no build multi-stage de T03. Digest da base e identificação das imagens locais estão nas evidências. A tag fixa a versão nominal, não torna a imagem imutável; conferir novamente o digest em futuros builds.

A rede `internal: true` aplica-se à rede de execução desta entrega; não promete impedir downloads durante o build. Redes de identidade e eventos só serão criadas quando necessárias. Não conectar a API a uma rede adicional com saída externa sem revisar a arquitetura.

### Transporte interno

Adotado HTTP sem TLS somente entre containers na rede local do laboratório, para respostas fictícias e sem credenciais. Essa escolha simplifica a fundação, mas não cifra o tráfego e pressupõe confiança no host e no Docker. Não há relaxamento de validação TLS, cookies ou tokens nesta entrega. O transporte do navegador e do OIDC permanece uma decisão da SPEC 02.

## 5. Contrato HTTP

As respostas abaixo são JSON com `Content-Type: application/json` e sem campos sensíveis. Ordem das propriedades e espaços não fazem parte do contrato.

| Requisição | Status | Corpo |
| --- | --- | --- |
| `GET /health` | `200` | `{"status":"ok"}` |
| `GET /` | `200` | `{"service":"secureops-api","message":"Serviço fictício do laboratório"}` |
| `GET /nao-existe` e demais caminhos inexistentes | `404` | `{"error":"not_found"}` |
| `POST /health` e métodos não suportados em caminhos existentes | `405` | `{"error":"method_not_allowed"}` |

- Métodos aceitos nos caminhos existentes: somente `GET`; respostas `405` incluem `Allow: GET`.
- Para `HEAD`, o Node preserva status e headers, mas suprime o corpo conforme a semântica HTTP; isso não transforma `HEAD` em método aceito. A validação cobre essa distinção.
- Query strings não alteram o recurso: `GET /health?probe=1` responde como `/health`.
- Não implementar rotas de desligamento, simulação de falha ou administração.
- `/health` representa a capacidade do processo de responder HTTP, não a saúde do laboratório inteiro.
- Não retornar hostname, configuração, variáveis de ambiente, stack traces ou dados de usuários.

## 6. Ciclo de vida e observabilidade

- O processo deve iniciar em foreground e o Compose deve refletir sua saída.
- O health check executado dentro do container deve consultar `/health`, exigir `200` e corpo esperado, e ter timeout finito.
- A validação a partir de outro container deve ser separada do health check: responder por loopback interno não comprova acesso pela rede de serviço.
- `SIGTERM` e `SIGINT` devem interromper o recebimento de novas conexões e encerrar o processo com prazo limitado, inferior ao período de parada do Compose.
- A parada manual deve manter a API parada; não usar reinício automático para mascarar a simulação de indisponibilidade.
- Registrar inicialização, encerramento e falhas de inicialização em stdout/stderr com timestamp UTC e tipo de evento.
- Não registrar cabeçalhos, corpos, tokens ou todas as variáveis do ambiente. Logs por requisição não são necessários nesta etapa.
- Falha de inicialização deve produzir saída não zero e diagnóstico sanitizado, sem continuar como se o serviço estivesse saudável.

## 7. Segurança da execução

- Executar a aplicação como usuário não root na imagem final.
- Separar build e runtime; não instalar compilador e dependências de desenvolvimento na imagem final sem justificativa.
- Não publicar portas nem usar rede do host, modo privilegiado, socket Docker ou bind mounts abrangentes.
- Não criar volumes nesta etapa; dados persistentes pertencem a entregas posteriores.
- Excluir `.env`, `node_modules`, artefatos e arquivos locais desnecessários dos contextos apropriados de Git e Docker.
- Não exigir `.env` ou criar credenciais fictícias funcionais sem necessidade. A API não usa segredos.
- Limitar a rotação de logs do container e registrar a configuração escolhida.

## 8. Critérios de aceite

| ID | Critério | Comprovação |
| --- | --- | --- |
| FL-01 | Ambiente suporta o caminho de execução documentado | Versões do Docker/Compose e tipo de daemon registrados |
| FL-02 | Build e testes reproduzíveis sem Node no host | Build e suíte executados por containers com sucesso |
| FL-03 | Contrato HTTP atendido | Testes de sucesso, `404`, `405`, headers e query string |
| FL-04 | Container saudável e acessível por DNS interno | Health check aprovado e probe separado consultando `http://api:3000/health` |
| FL-05 | API sem porta publicada | Configuração resolvida e inspeção do container sem bindings para o host |
| FL-06 | Execução com privilégio reduzido | Inspeção e usuário efetivo não root; sem mounts ou modos proibidos |
| FL-07 | Falha e recuperação controladas | Parar API faz probe falhar; iniciar API restaura resposta esperada |
| FL-08 | Parada e inicialização diagnosticáveis | Logs sanitizados, parada dentro do prazo e falha de inicialização testada |
| FL-09 | Instruções e evidências fiéis | Procedimento repetido e resultados reais documentados |

O teste HTTP negativo no host é complementar: um erro em `localhost:3000` sozinho não prova ausência de exposição, e uma resposta pode pertencer a outro programa. Não parar aplicações alheias para liberar essa porta; nenhuma porta do host é necessária aqui.

## 9. Evidências e conclusão

Registrar ambiente, comandos, horário e resultado por critério em `docs/evidence/01-local-foundation.md` quando os testes existirem. Capturas são opcionais; saídas sanitizadas e reproduzíveis bastam.

A entrega só poderá ser concluída quando FL-01 a FL-09 forem validados. Docker indisponível, testes não executados ou decisões pendentes devem ser registrados como bloqueios ou pendências, nunca como sucesso presumido.

## 10. Resultado da revisão e próximos passos

- Contrato e topologia revisados: não foi identificada necessidade de ampliar ou alterar o comportamento proposto.
- Docker e daemon Linux acessíveis sem alterações no sistema; detalhes em FL-01 nas evidências.
- Versões diretas fixadas e parâmetros operacionais definidos no PLAN.
- T01 a T06 executadas, com registros por critério nas [evidências](../../evidence/01-local-foundation.md).
- Nenhum critério de aceite desta entrega permanece pendente. Autenticação, MFA, gateway, monitor e automação pertencem às próximas entregas, não são resultados desta fundação.
