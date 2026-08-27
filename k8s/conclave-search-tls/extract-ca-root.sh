#!/usr/bin/env bash
# k8s/conclave-search-tls/extract-ca-root.sh
#
# Prints the internal IP-SAN CA's root certificate (PEM) to stdout.
# A future conclave-search container-image build step should pipe this
# into its own image's trust bundle, e.g.:
#
#   bash extract-ca-root.sh > internal-ip-ca-root.crt
#   # then, in that image's Dockerfile:
#   #   COPY internal-ip-ca-root.crt /usr/local/share/ca-certificates/
#   #   RUN update-ca-certificates
#
# conclave-search's trust_store_load() (stdlib/x509/trust_store.sio in the
# sibling sounio repo) reads a single hardcoded path,
# /etc/ssl/certs/ca-certificates.crt, with no runtime parameterization --
# so the CA root MUST be present in that exact file inside whatever
# container actually runs the conclave-search binary. There is no such
# container/deploy pipeline yet; this script is what that future pipeline
# should call.
set -euo pipefail
kubectl get secret internal-ip-ca-root -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d
