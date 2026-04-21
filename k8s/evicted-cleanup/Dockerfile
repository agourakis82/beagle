# Minimal kubectl image for the evicted-cleanup CronJob.
# Hand-rolled so we don't depend on pull-through registries that this
# cluster has trouble reaching.

FROM alpine:3.19

ARG KUBECTL_VERSION=v1.31.2

RUN apk add --no-cache ca-certificates curl bash \
 && curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && chmod +x /usr/local/bin/kubectl \
 && apk del curl

ENTRYPOINT ["/bin/sh"]
