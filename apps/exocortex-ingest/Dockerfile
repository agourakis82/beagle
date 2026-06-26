# Exocortex ingest + biography digest tool. Node ESM, no deps (uses node: builtins + fetch).
# git is needed by run-digest.mjs (gathers recent commits from mounted repos).
FROM node:22-alpine
RUN apk add --no-cache git
WORKDIR /app
COPY apps/exocortex-ingest/package.json ./
COPY apps/exocortex-ingest/src ./src
COPY apps/exocortex-ingest/bin ./bin
# Default entrypoint = the recurring digest. The corpus/conversation backfill
# Jobs override with: node bin/run-ingest.mjs  /  node bin/run-conversations.mjs
CMD ["node", "bin/run-digest.mjs"]
