FROM node:22-bookworm-slim AS build

WORKDIR /app

COPY beagle-mcp-server/package*.json ./
RUN npm ci

COPY beagle-mcp-server/tsconfig.json ./
COPY beagle-mcp-server/src ./src
RUN npm run build

FROM node:22-bookworm-slim AS runtime

WORKDIR /app

ENV NODE_ENV=production \
    MCP_TRANSPORT=http \
    MCP_HTTP_PORT=3000 \
    BEAGLE_CORE_URL=http://beagle-core.beagle.svc.cluster.local:8080

COPY beagle-mcp-server/package*.json ./
RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist
COPY docs/public/beagle_connector ./docs/public/beagle_connector

USER 1000:1000

EXPOSE 3000

ENTRYPOINT ["node", "dist/index.js"]
