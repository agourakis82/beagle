#!/bin/bash
# Constrói e implanta o project-cockpit a partir de um commit — verificando o
# ARTEFATO, nunca confiando no "job succeeded".
#
# POR QUE ESTE SCRIPT EXISTE (08-ago-2026):
#
# O jeito antigo era um `sed` que trocava valores antigos hardcoded no
# build-job.yaml. Quando alguém atualizou o arquivo, o sed passou a não casar com
# nada — e substituiu NADA, em silêncio. O job rodou, terminou com sucesso, e
# construiu um commit ANTIGO com uma tag antiga. Eu então implantei uma tag que
# nunca existiu e o companion ficou fora do ar.
#
# Duas regras vieram disso:
#   1. Substituir por CHAVE (regex no nome do campo), nunca pelo valor anterior.
#      Casamento por valor falha calado; casamento por chave falha ruidosamente.
#   2. CONFERIR A TAG NO REGISTRO antes de trocar a imagem. "Job succeeded" diz
#      que um processo terminou, não que a imagem que você quer existe.
set -euo pipefail

SHA="${1:-$(git -C /home/devsounio/beagle rev-parse --short HEAD)}"
PREFIXO="${2:-build}"
TAG="${PREFIXO}-${SHA}"
REG="192.168.3.207:5003"
REPO=/home/devsounio/beagle
export KUBECONFIG="${KUBECONFIG:-/home/devsounio/.kube/config}"

echo "== commit ${SHA} -> tag ${TAG}"
git -C "$REPO" cat-file -e "${SHA}^{commit}" 2>/dev/null || { echo "ERRO: commit ${SHA} não existe"; exit 1; }
git -C "$REPO" merge-base --is-ancestor "$SHA" HEAD 2>/dev/null || echo "AVISO: ${SHA} não é ancestral do HEAD"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
python3 - "$REPO/k8s/project-cockpit/build-job.yaml" "$TMP/job.yaml" "$SHA" "$TAG" <<'PY'
import re, sys, io
origem, destino, sha, tag = sys.argv[1:5]
s = io.open(origem, encoding="utf-8").read()
# Substituição por CHAVE. Cada uma tem que casar, ou o script morre — falha
# calada de sed foi o que construiu o commit errado.
regras = [
    (r'(name:\s*BEAGLE_IMAGE_TAG\s*\n\s*value:\s*)"?[^"\n]+"?', lambda m: m.group(1) + '"%s"' % tag),
    (r'(name:\s*BEAGLE_GIT_REF\s*\n\s*value:\s*)"?[^"\n]+"?',   lambda m: m.group(1) + '"%s"' % sha),
    (r'(^\s*name:\s*)project-cockpit-build[^\s]*',               lambda m: m.group(1) + 'project-cockpit-build-%s' % sha),
]
for padrao, repl in regras:
    s, n = re.subn(padrao, repl, s, flags=re.M)
    if n == 0:
        sys.stderr.write("ERRO: padrão não casou: %s\n" % padrao)
        sys.exit(1)
    print("  substituiu %d ocorrência(s): %s" % (n, padrao.split('\\s')[0][:36]))
io.open(destino, "w", encoding="utf-8").write(s)
PY

kubectl -n beagle delete job "project-cockpit-build-${SHA}" --ignore-not-found >/dev/null 2>&1 || true
kubectl -n beagle apply -f "$TMP/job.yaml" | tail -1

echo "== esperando o build"
for _ in $(seq 1 40); do
  ok=$(kubectl -n beagle get job "project-cockpit-build-${SHA}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)
  bad=$(kubectl -n beagle get job "project-cockpit-build-${SHA}" -o jsonpath='{.status.failed}' 2>/dev/null || true)
  [ "$ok" = "1" ] && { echo "  job concluído"; break; }
  [ "$bad" = "1" ] && { echo "ERRO: job falhou"; exit 1; }
  sleep 20
done

# A VERIFICAÇÃO QUE FALTAVA. Job concluído não é imagem publicada.
echo "== conferindo a tag no registro"
if ! curl -s -m 30 "http://${REG}/v2/project-cockpit/tags/list" | grep -q "\"${TAG}\""; then
  echo "ERRO: a tag ${TAG} NÃO está no registro. Nada será implantado."
  exit 1
fi
echo "  ${TAG} presente"

kubectl -n beagle set image deployment/project-cockpit "app=${REG}/project-cockpit:${TAG}" | tail -1
kubectl -n beagle rollout status deployment/project-cockpit --timeout=300s | tail -1
