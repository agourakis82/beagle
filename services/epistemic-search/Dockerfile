# services/epistemic-search/Dockerfile
# Stage 1: compile conclave-search ONCE, using the Sounio toolchain.
FROM debian:bookworm-slim AS build
COPY sounio-runtime/bin/souc /opt/sounio/bin/souc
COPY sounio-runtime/bin/souc-linux-x86_64 /opt/sounio/bin/souc-linux-x86_64
# Madaros launcher + raw ELF: required because conclave-search's src/main.sio
# spans multiple `use search::*` modules, which only Madaros's modular
# import resolver can compile (lean_single is single-file only and fails
# with "error: no main" on this source).
COPY sounio-runtime/bin/madaros /opt/sounio/bin/madaros
COPY sounio-runtime/bin/madaros-linux-x86_64 /opt/sounio/bin/madaros-linux-x86_64
# bin/souc resolves the raw Madaros ELF as artifacts/self-hosted/madaros
# FIRST, falling back to bin/madaros-linux-x86_64 only if that's absent
# (see bin/souc's own _resolve_madaros). D19: a stale, pre-arena-fix
# bin/madaros-linux-x86_64 was silently used because this file was never
# staged -- always stage the freshly-built artifact so it takes priority.
COPY sounio-runtime/artifacts/self-hosted/madaros /opt/sounio/artifacts/self-hosted/madaros
COPY sounio-runtime/stdlib /opt/sounio/stdlib
COPY conclave-search-src /opt/conclave-search-src
ENV SOUNIO_STDLIB_PATH=/opt/sounio/stdlib
RUN /opt/sounio/bin/souc compile /opt/conclave-search-src/src/main.sio \
      -o /opt/conclave-search-src/bin/conclave-search

# Stage 2: minimal runtime -- just the compiled binary, no toolchain.
FROM python:3.12-slim
COPY --from=build /opt/conclave-search-src/bin/conclave-search /opt/conclave-search/bin/conclave-search
# Trust the internal IP-SAN CA (see k8s/conclave-search-tls/) so
# conclave-search's trust_store_load() -- which reads the fixed system
# path /etc/ssl/certs/ca-certificates.crt with no runtime override --
# validates SearXNG's and beagle-core's HTTPS fronts. `update-ca-certificates`
# on this base image links the cert into /etc/ssl/certs/ (hash symlink) but
# does not reliably regenerate the combined bundle file trust_store_load()
# actually reads -- append directly instead, which is all a PEM bundle is.
COPY internal-ip-ca-root.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates && \
    cat /usr/local/share/ca-certificates/internal-ip-ca-root.crt >> /etc/ssl/certs/ca-certificates.crt
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8800
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8800/health').status==200 else 1)"
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8800"]
