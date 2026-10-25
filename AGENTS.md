# Instruções para agentes de IA

## Contexto e objetivo

O SecureOps Lab é um laboratório pessoal, gratuito e local de operações e segurança. O objetivo é aprender e demonstrar acesso baseado em identidade, monitoramento e automação de incidentes. Não é um ambiente de produção nem uma implementação completa de ZTNA.

Use português brasileiro na documentação e nas explicações. Preserve nomes técnicos e convenções do código quando apropriado. Explique as decisões de forma que a autora consiga reproduzir e defender a solução em uma entrevista.

## Leitura antes de trabalhar

1. Leia o `README.md`.
2. Consulte `docs/architecture.md` e `docs/roadmap.md`.
3. Para implementar uma funcionalidade, leia seu `SPEC.md` e `PLAN.md` em `docs/features/`.
4. Inspecione os arquivos existentes antes de propor mudanças; não presuma que a documentação corresponde ao estado implementado.

Os documentos de funcionalidades ainda podem não existir. Não invente aprovações ou requisitos ausentes. Se uma decisão alterar comportamento, segurança ou escopo, apresente a dúvida antes de implementar.

## Organização dos documentos

- `README.md`: apresentação, limites e instruções reais de uso.
- `docs/architecture.md`: responsabilidades, fronteiras e decisões compartilhadas.
- `docs/roadmap.md`: entregas, dependências e estado geral.
- `docs/features/<numero-nome>/SPEC.md`: comportamento, requisitos e critérios de aceite.
- `docs/features/<numero-nome>/PLAN.md`: tarefas, validação e resultados de execução.
- `docs/runbooks/`: procedimentos operacionais, quando escritos.
- `docs/evidence/`: evidências sanitizadas, quando coletadas.

Evite duplicar decisões em vários documentos. Se houver contradição, sinalize-a e resolva-a explicitamente, em vez de escolher silenciosamente a interpretação mais conveniente.

## Limites obrigatórios

- Não contratar serviços, solicitar cartão, comprar domínio ou adicionar dependências operacionais pagas.
- Não criar túneis públicos, abrir portas no roteador nem testar sistemas externos.
- Usar apenas aplicação, contas e dados fictícios do próprio laboratório.
- Publicar portas de interfaces locais somente em loopback, por exemplo `127.0.0.1`, e validar o resultado.
- Não publicar a porta da API no host, nem mesmo temporariamente como solução de contorno. Para testes internos, usar a rede do Compose.
- Não versionar senhas, tokens, chaves, cookies, sementes TOTP ou `.env` com valores reais. Arquivos de exemplo devem conter placeholders não funcionais.
- Sanitizar logs, capturas, exports do n8n e configurações exportadas antes de incluí-los no repositório.
- Não desabilitar validação de tokens, MFA ou autorização para fazer um teste passar.
- Exceções locais de transporte, cookies ou modo de desenvolvimento precisam de justificativa, limites e validação documentados antes de serem aplicadas.
- Não montar o socket Docker nos serviços nem usar containers privilegiados sem uma necessidade aprovada. O fluxo de incidentes não precisa desses privilégios.
- Não remover volumes, apagar dados, executar limpeza ampla ou sobrescrever trabalho existente sem autorização explícita.
- Não usar integrações de IA em runtime nem enviar logs a serviços externos. Usar IA para desenvolver o laboratório não exige IA no produto.

## Fluxo de trabalho

1. Confirme a entrega e a tarefa solicitadas.
2. Revise a SPEC e o PLAN existentes; quando a tarefa for escrevê-los, não implemente código junto.
3. Trabalhe em mudanças pequenas e verificáveis. Não amplie o escopo nem implemente funcionalidades futuras por conveniência.
4. Execute as validações previstas, incluindo caminhos de negação e falha.
5. Registre o que foi executado, o resultado e os impedimentos. Diferencie análise estática de testes reais com containers e navegador.
6. Atualize o PLAN e o roadmap somente quando o estado da entrega realmente mudar.
7. Explique como a autora pode repetir o teste e o que o resultado comprova ou não comprova.

Não delegue a subagentes por padrão. Não introduza bibliotecas, ferramentas ou infraestrutura sem necessidade para a entrega atual.

## Implementação e validação

- Priorize TypeScript simples e Docker Compose; evite abstrações e serviços desnecessários.
- Escolha versões explícitas e compatíveis de imagens e dependências; evite `latest`.
- Verifique opções de configuração na documentação da versão usada. Não invente flags, payloads ou recursos de ferramentas.
- Mantenha monitoramento e automação independentes do container da API.
- Prefira configurações reproduzíveis; documente passos manuais inevitáveis, especialmente cadastro TOTP.
- Teste autorização no gateway, não apenas elementos visuais ou respostas da aplicação.
- Valide tanto a configuração de exposição de portas quanto o comportamento observado. Não declare isolamento absoluto da máquina hospedeira.
- Deduplicação e persistência de incidentes precisam de evidências; um workflow executado com sucesso não comprova esses requisitos sozinho.
- Não crie atalhos públicos ou endpoints administrativos sem proteção para simular falhas. A parada manual do container é suficiente.

## Critério de conclusão

Uma tarefa só pode ser marcada como concluída quando sua implementação existe e a validação exigida foi executada com sucesso. Se algo depender de interação da autora ou de ferramenta indisponível, registre como pendente ou bloqueado.

Uma entrega só está concluída quando seus critérios de aceite foram verificados, a documentação está consistente e as evidências não contêm segredos. Nunca fabrique resultados, capturas ou testes.
