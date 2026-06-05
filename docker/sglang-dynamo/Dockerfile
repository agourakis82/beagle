FROM nvcr.io/nvidia/ai-dynamo/sglang-runtime:1.0.1

ENV PYTHONUNBUFFERED=1

USER root

RUN python3 -m pip install --no-cache-dir --no-deps "bitsandbytes>=0.46.1"

COPY --chmod=0755 entrypoint.sh /opt/dynamo/bin/entrypoint.sh

USER dynamo

ENTRYPOINT ["/opt/dynamo/bin/entrypoint.sh"]
