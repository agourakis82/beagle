FROM ttl.sh/sounio-sglang-runtime-20260409-163137-9a6e6d:24h

ENV DYNAMO_VENV=/opt/dynamo-venv
ENV PATH="${DYNAMO_VENV}/bin:${PATH}"
ENV PYTHONUNBUFFERED=1

RUN python3 -m venv "${DYNAMO_VENV}" \
 && "${DYNAMO_VENV}/bin/pip" install --no-cache-dir "ai-dynamo[sglang]"

COPY entrypoint.sh /opt/dynamo/bin/entrypoint.sh

RUN chmod +x /opt/dynamo/bin/entrypoint.sh

ENTRYPOINT ["/opt/dynamo/bin/entrypoint.sh"]
