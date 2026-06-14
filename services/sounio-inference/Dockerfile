# Sounio Inference Service.
#
# The entire "Sounio runtime" needed to compile & run .sio programs is just two
# things: the statically-linked self-hosted compiler binary (~2MB, no libc, no
# external linker/assembler) and the stdlib source tree (~12MB). No toolchain.
# That is the whole story of consuming Sounio from outside its dev repo.
#
# Build context must contain: app.py, requirements.txt, and sounio-runtime/
# (bin/souc, bin/souc-linux-x86_64, stdlib/) — staged by build.sh.

FROM python:3.12-slim

# bash + coreutils (dirname/uname/chmod) are needed by the souc launcher script.
# python:slim already ships them; no extra apt needed.

# ── Sounio runtime: static compiler + stdlib, nothing else ──
COPY sounio-runtime/bin/souc            /opt/sounio/bin/souc
COPY sounio-runtime/bin/souc-linux-x86_64 /opt/sounio/bin/souc-linux-x86_64
COPY sounio-runtime/stdlib              /opt/sounio/stdlib
ENV SOUNIO_DIR=/opt/sounio \
    SOUC_BIN=/opt/sounio/bin/souc \
    SOUNIO_STDLIB_PATH=/opt/sounio/stdlib \
    SOUNIO_VERB_CACHE=/tmp/sounio-verb-cache

# ── Service ──
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

EXPOSE 8799
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8799/health').status==200 else 1)"
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8799"]
