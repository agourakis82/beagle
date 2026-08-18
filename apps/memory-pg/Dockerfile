# memory-pg embed worker image.
#
# Phase 1, Task 1.4. Runs the SKIP-LOCKED embed worker (bin/embed-worker.mjs)
# against the dedicated memory-pg Postgres, embedding chunks via the sovereign
# TEI bge-m3 service. Stateless, single-replica, RAM-bounded (the no-OOM fix).
#
# Build via kaniko -> 192.168.3.207:5003/memory-pg-embed-worker:v1
# Build context is the repo root (clone of feat/memory-pg); we COPY only the
# Node app subtree so the image stays small.
FROM node:20-slim

# Non-root runtime: node:20-slim ships an unprivileged `node` user (uid 1000).
WORKDIR /app

# Install production deps first for layer caching. The app has a single runtime
# dependency (pg); package-lock.json is committed so we use `npm ci`.
COPY apps/memory-pg/package.json apps/memory-pg/package-lock.json ./
RUN npm ci --omit=dev

# App source.
COPY apps/memory-pg/src ./src
COPY apps/memory-pg/sql ./sql
COPY apps/memory-pg/bin ./bin
# O pré-registro viaja NA IMAGEM, junto do código que o aplica. `judge-agreement` confere o
# SHA-256 deste arquivo a cada execução e se recusa a julgar se ele mudou — então a regra e o
# executor precisam ser versionados como uma coisa só. Deixá-lo fora faria o julgamento
# depender de um arquivo que o contêiner não tem.
COPY docs/PREREG_FASE2_DIRECAO_v1.md ./docs/PREREG_FASE2_DIRECAO_v1.md

# Drop privileges.
USER node

# The worker reads MEMORY_PG_DSN + BEAGLE_TEI_EMBED_URL from the environment.
CMD ["node", "bin/embed-worker.mjs"]
