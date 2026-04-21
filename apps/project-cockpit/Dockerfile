FROM node:20-bookworm-slim AS build

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ \
  && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
RUN npm ci --no-fund --no-audit

COPY index.html vite.config.js ./
COPY public ./public
COPY server ./server
COPY src ./src
# Agent pod manifests — needed by agent-routes.mjs for spawning.
# Symlinks in source resolve here because COPY follows symlinks by default.
COPY agent-manifests ./agent-manifests

RUN npm run build

FROM node:20-bookworm-slim

ARG KUBECTL_VERSION=v1.35.2

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
  && chmod +x /usr/local/bin/kubectl

WORKDIR /app

COPY --from=build /app/package.json ./package.json
COPY --from=build /app/package-lock.json ./package-lock.json
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/public ./public
COPY --from=build /app/server ./server
COPY --from=build /app/agent-manifests ./agent-manifests

ENV NODE_ENV=production \
    PROJECT_COCKPIT_AGENT_MANIFEST_DIR=/app/agent-manifests
EXPOSE 4370

USER node

CMD ["npm", "start"]
