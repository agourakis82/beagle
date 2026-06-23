# memory-pg custom Postgres image.
#
# Base: ParadeDB 0.24.1 on PG16 — ships pg_search 0.24.1 (BM25) and pgvector 0.8.2.
# We REQUIRE pgvector >=0.8.3 (HNSW vacuum-corruption fix), so we compile and
# install pgvector v0.8.3 over the base, keeping pg_search and all other bundled
# extensions intact.
#
# Build via kaniko -> 192.168.3.207:5003/memory-pg-postgres:pgvector083-pg16
#
# NOTE: the base image's entrypoint starts as root and drops to the `postgres`
# user via gosu (the running pod confirms this). We must NOT end with
# `USER postgres` — that would break the gosu drop in the official postgres
# entrypoint. The build steps run as root to write into the root-owned
# pg_config pkglibdir/sharedir.
FROM paradedb/paradedb:0.24.1-pg16

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        postgresql-server-dev-16 \
        ca-certificates; \
    git clone --depth 1 --branch v0.8.3 https://github.com/pgvector/pgvector.git /tmp/pgvector; \
    cd /tmp/pgvector; \
    make OPTFLAGS=""; \
    make install; \
    rm -rf /tmp/pgvector; \
    apt-get purge -y build-essential git postgresql-server-dev-16; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*

# Leave the image's default USER/ENTRYPOINT/CMD from the ParadeDB base unchanged.
