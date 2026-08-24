ARG BASE_IMAGE=192.168.3.207:5003/sounio-lab-beagle-workspace-ssh-20260619-chownfix:slurm-warn-20260811
FROM ${BASE_IMAGE}

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      dune \
      git \
      curl \
      libcryptokit-ocaml-dev \
      ocaml-findlib \
      ocaml-nox \
      pkg-config \
      util-linux \
    && rm -rf /var/lib/apt/lists/* \
    && ocamlopt -version \
    && dune --version \
    && ocamlfind query cryptokit

LABEL org.opencontainers.image.title="Sounio Loom Pod replay canary"
LABEL org.opencontainers.image.description="Beagle workspace image with the OCaml and native build toolchain required by Sounio Loom"
