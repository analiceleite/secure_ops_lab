FROM node:24.22.1-bookworm-slim@sha256:55fb5f5a527ea2c5c4a95f963e48ef90aa38c7b346054fdc8ee9957a2b55d205 AS dependencies
WORKDIR /receiver
RUN chown node:node /receiver
USER node
COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund

FROM node:24.22.1-bookworm-slim@sha256:55fb5f5a527ea2c5c4a95f963e48ef90aa38c7b346054fdc8ee9957a2b55d205 AS runtime
WORKDIR /receiver
ENV NODE_ENV=production
COPY --from=dependencies /receiver/node_modules ./node_modules
COPY package.json *.ts probe.mjs ./
USER node
# TypeScript apagavel executado nativamente no Node 24, como no coletor existente.
CMD ["node", "main.ts"]

FROM runtime AS test
COPY test ./test
CMD ["npm", "test"]
