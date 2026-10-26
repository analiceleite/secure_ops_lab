# Reutiliza o runtime Node 24.22.1 local ja construido; sem npm/framework.
FROM secureops-api:0.1.0
WORKDIR /collector
COPY --chown=node:node collector.ts main.ts ./
USER node
# Node 24 executa apenas sintaxe TypeScript apagavel nativamente.
CMD ["node", "main.ts"]
