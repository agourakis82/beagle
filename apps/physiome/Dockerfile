# Beagle Physiome — ingest server + poller/digest entrypoints. Node ESM.
# Includes apps/exocortex-ingest/src so the digest can reuse the assisted-import contract.
FROM node:22-alpine
WORKDIR /app
COPY apps/physiome/package.json apps/physiome/package-lock.json ./physiome/
RUN cd physiome && npm ci --omit=dev
COPY apps/physiome ./physiome
COPY apps/exocortex-ingest/src ./exocortex-ingest/src
WORKDIR /app/physiome
CMD ["node", "bin/serve.mjs"]
