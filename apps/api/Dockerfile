FROM node:24.22.1-bookworm-slim AS build
WORKDIR /app
RUN chown node:node /app
USER node
COPY --chown=node:node apps/api/package.json apps/api/package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY --chown=node:node apps/api/tsconfig.json ./
COPY --chown=node:node apps/api/src ./src
COPY --chown=node:node apps/api/test ./test
COPY --chown=node:node apps/api/scripts ./scripts
RUN npm run build

FROM build AS test
CMD ["npm", "test"]

FROM node:24.22.1-bookworm-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
# Sem dependências npm de produção: copiar somente JS compilado e probe.
COPY --from=build /app/dist/src ./dist/src
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/scripts/probe.mjs ./scripts/probe.mjs
USER node
CMD ["node", "dist/src/main.js"]
