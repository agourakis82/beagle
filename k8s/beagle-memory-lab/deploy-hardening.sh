#!/usr/bin/env bash
# Deploy the hardened memory-engine image (worker batched-embed + parallel embed
# BEAGLE_MEMORY_EMBED_CONCURRENCY=8 + pylance compaction, all BAKED INTO the image)
# and remove the now-dead ConfigMap-override leftovers.
#
# PRECONDITION: run ONLY after the full-corpus reindex has finished (this rollout
# restarts the memory-engine pod, which would abort an in-flight rebuild).
#
# Build that produced the image: k8s/beagle-memory-lab/build-job-hardening.yaml
#   image = 192.168.3.207:5003/beagle-memory-engine:exocortex-6d83ad5a (ref 6d83ad5a)
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-/home/devsounio/.kube/config}"
NS=beagle-memory-lab
IMG=192.168.3.207:5003/beagle-memory-engine:exocortex-6d83ad5a

echo "== 1. verify the image exists in the registry =="
curl -sf "http://192.168.3.207:5003/v2/beagle-memory-engine/tags/list" | grep -q "exocortex-6d83ad5a" \
  && echo "  ok: tag present" || { echo "  MISSING tag exocortex-6d83ad5a — build first"; exit 1; }

echo "== 2. roll out the new image =="
kubectl -n "$NS" set image deploy/beagle-memory-engine beagle-memory-engine="$IMG"

echo "== 3. remove the dead, unmounted worker-patch volume (ConfigMap override is now baked in) =="
# The volume 'worker-patch' (cm memory-engine-worker) is defined but NOT mounted on the
# container — strip it so the spec matches reality. JSON-patch by index is fragile, so
# re-resolve the index each run.
idx=$(kubectl -n "$NS" get deploy beagle-memory-engine -o json \
  | python3 -c 'import sys,json;v=json.load(sys.stdin)["spec"]["template"]["spec"].get("volumes",[]);print(next((i for i,x in enumerate(v) if x.get("name")=="worker-patch"),-1))')
if [ "$idx" != "-1" ]; then
  kubectl -n "$NS" patch deploy beagle-memory-engine --type=json \
    -p "[{\"op\":\"remove\",\"path\":\"/spec/template/spec/volumes/$idx\"}]"
  echo "  removed worker-patch volume at index $idx"
else
  echo "  worker-patch volume already absent"
fi

echo "== 4. wait for rollout =="
kubectl -n "$NS" rollout status deploy/beagle-memory-engine --timeout=300s

echo "== 5. delete stale override ConfigMaps (no longer referenced) =="
kubectl -n "$NS" delete cm semantic-backbone-worker-fix --ignore-not-found
kubectl -n "$NS" delete cm memory-engine-worker --ignore-not-found

echo "== 6. verify the running worker now has parallel embed baked in =="
POD=$(kubectl -n "$NS" get pods --field-selector=status.phase=Running -o name | grep memory-engine | grep -v build | head -1); POD=${POD#pod/}
kubectl -n "$NS" exec "$POD" -c beagle-memory-engine -- \
  grep -c "BEAGLE_MEMORY_EMBED_CONCURRENCY" /opt/beagle-memory-engine/workers/semantic_backbone.py \
  && echo "  ok: parallel-embed present in baked image" || echo "  WARN: not found"
echo "DONE: memory-engine hardened (image $IMG), overrides removed."
