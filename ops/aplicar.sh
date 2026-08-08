#!/bin/bash
# Aplica manifesto k8s com as verificações que faltavam.
#
# POR QUE EXISTE (07-ago-2026): apliquei k8s/project-cockpit/deployment.yaml para
# adicionar uma variável de ambiente e DERRUBEI O COCKPIT. O arquivo tinha
# `nodeSelector`, `tolerations` e `securityContext` DUPLICADOS no mesmo nível —
# alguém colou um dump do cluster por cima do manifesto. Em YAML a última
# ocorrência vence, então o bloco de cima, justamente o que tinha os comentários
# de intenção, era decorativo. O que valia era o dump: pin de hostname num nó que
# já não tinha o rótulo, e sem a tolerância de control-plane. Pod Pending para
# sempre, endpoints vazios, companion fora do ar.
#
# Três portões, todos aprendidos daquela noite:
#   1. CHAVE DUPLICADA É ERRO. Não aviso: erro. Foi a causa raiz.
#   2. MOSTRAR O DIFF antes de aplicar. `kubectl diff` responde "o que muda de
#      verdade", que é diferente de "o que eu acho que estou mudando".
#   3. SONDAR DEPOIS. Aplicar com sucesso não é o serviço de pé — o apply
#      daquela noite retornou 'configured' e o serviço morreu em seguida.
set -uo pipefail

ARQ="${1:?uso: aplicar.sh <manifesto.yaml> [namespace]}"
NS="${2:-beagle}"
export KUBECONFIG="${KUBECONFIG:-/home/devsounio/.kube/config}"

echo "== 1) chaves duplicadas"
python3 - "$ARQ" <<'PY'
import sys, yaml

# Parser DE VERDADE, nao regex de indentacao.
#
# A primeira versao comparava chaves por nivel de indentacao e acusava
# `operator`, `value`, `effect` — que se repetem LEGITIMAMENTE, uma vez por item
# de lista (cada toleration tem os tres). Ruido assim ensina a ignorar a
# ferramenta, e alarme ignorado e silencio por outro caminho.
#
# Um loader que rejeita chave duplicada no MESMO mapa acerta por construcao:
# entende lista, entende aninhamento, e nao tem falso positivo.
class SemDuplicatas(yaml.SafeLoader):
    pass

def mapa(loader, node, deep=False):
    chaves = []
    for k, _ in node.value:
        chave = loader.construct_object(k, deep=deep)
        if chave in chaves:
            m = k.start_mark
            raise yaml.constructor.ConstructorError(
                None, None,
                "chave duplicada '%s' na linha %d — em YAML a ULTIMA vence, "
                "entao o bloco de cima vira decoracao" % (chave, m.line + 1), m)
        chaves.append(chave)
    return yaml.SafeLoader.construct_mapping(loader, node, deep)

SemDuplicatas.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapa)

erros = 0
with open(sys.argv[1], encoding="utf-8") as f:
    try:
        for _ in yaml.load_all(f, Loader=SemDuplicatas):
            pass
    except yaml.constructor.ConstructorError as e:
        print("  ERRO: %s" % e.problem); erros = 1
    except yaml.YAMLError as e:
        print("  ERRO: YAML invalido: %s" % str(e)[:120]); erros = 1

if erros:
    print("  Corrija antes de aplicar: chave duplicada faz o arquivo aplicar o oposto do que documenta.")
    sys.exit(1)
print("  nenhuma chave duplicada")
PY
[ $? -ne 0 ] && exit 1

echo "== 2) o que muda de verdade"
DIFF=$(kubectl -n "$NS" diff -f "$ARQ" 2>/dev/null | grep -E "^[+-]" | grep -vE "^[+-]{3}|restartedAt|resourceVersion|generation|lastTransitionTime" | head -25)
if [ -z "$DIFF" ]; then
  echo "  (nada muda — arquivo e cluster idênticos)"
else
  echo "$DIFF" | sed 's/^/  /'
fi

# A IMAGEM É O CAMPO MAIS PERIGOSO DO DIFF.
#
# Ao testar este próprio script eu apliquei o manifesto do git por cima do
# cluster e REVERTI a imagem para uma anterior — o companion caiu. O diff mostrou
# a linha; eu segui assim mesmo. Um portão que só informa não protege de quem
# está no automático, e às 3h da manhã todo mundo está no automático.
if echo "$DIFF" | grep -qE "^[+-]\s*image:"; then
  echo "  !! ESTE APPLY TROCA A IMAGEM DE UM CONTAINER."
  echo "$DIFF" | grep -E "^[+-]\s*image:" | sed 's/^/     /'
  if [ "${APLICAR_TROCA_IMAGEM:-}" != "sim" ]; then
    echo "  Recusado. Deploy de imagem é trabalho do ops/build-cockpit.sh, que confere a tag"
    echo "  no registro antes de trocar. Se é isto que você quer mesmo:"
    echo "     APLICAR_TROCA_IMAGEM=sim $0 $ARQ $NS"
    exit 1
  fi
  echo "  (autorizado por APLICAR_TROCA_IMAGEM=sim)"
fi

echo "== 3) validação do servidor (dry-run)"
kubectl -n "$NS" apply -f "$ARQ" --dry-run=server >/dev/null || { echo "  ERRO: o servidor recusou"; exit 1; }
echo "  aceito"

echo "== 4) aplicando"
kubectl -n "$NS" apply -f "$ARQ" | sed 's/^/  /'

# Sondagem: nomes de Deployment/StatefulSet do próprio arquivo.
ALVOS=$(python3 -c "
import re,sys
s=open('$ARQ',encoding='utf-8').read()
for bloco in s.split('\n---'):
    k=re.search(r'^kind:\s*(Deployment|StatefulSet)', bloco, re.M)
    n=re.search(r'^\s*name:\s*(\S+)', bloco, re.M)
    if k and n: print('%s/%s' % (k.group(1).lower(), n.group(1)))
")
[ -z "$ALVOS" ] && exit 0

echo "== 5) o serviço subiu? (apply com sucesso não é serviço de pé)"
falhou=0
for alvo in $ALVOS; do
  if ! kubectl -n "$NS" rollout status "$alvo" --timeout=180s >/dev/null 2>&1; then
    echo "  FALHOU: $alvo não ficou pronto"
    kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep "${alvo##*/}" | head -2 | sed 's/^/     /'
    falhou=1
  else
    echo "  OK: $alvo"
  fi
done
exit $falhou
