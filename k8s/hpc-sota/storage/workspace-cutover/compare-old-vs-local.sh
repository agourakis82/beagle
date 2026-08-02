#!/usr/bin/env bash
set -euo pipefail

if kubectl --kubeconfig /etc/kubernetes/admin.conf get ns >/dev/null 2>&1; then
  k() { kubectl --kubeconfig /etc/kubernetes/admin.conf "$@"; }
elif sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get ns >/dev/null 2>&1; then
  k() { sudo kubectl --kubeconfig /etc/kubernetes/admin.conf "$@"; }
else
  echo "unable to find a working admin kubeconfig" >&2
  exit 1
fi

tmp_manifest="$(mktemp)"
trap 'rm -f "$tmp_manifest"' EXIT

cat >"$tmp_manifest" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: workspace-post-cutover-compare
  namespace: beagle
spec:
  restartPolicy: Never
  nodeSelector:
    kubernetes.io/hostname: t560-proxmox
  tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  containers:
  - name: compare
    image: debian:bookworm-slim
    command: ["/bin/bash", "-lc"]
    args:
    - |
      set -euo pipefail
      apt-get update >/dev/null
      apt-get install -y findutils coreutils diffutils >/dev/null
      compare() {
        local name="$1"
        local old="/old-${name}"
        local new="/new-${name}"
        local d="/tmp/${name}"
        mkdir -p "$d"
        (cd "$old" && find . -printf '%P\n' | LC_ALL=C sort) > "$d/old.list"
        (cd "$new" && find . -printf '%P\n' | LC_ALL=C sort) > "$d/new.list"
        (cd "$old" && find . -type f -printf '%P\t%s\n' | LC_ALL=C sort) > "$d/old.meta"
        (cd "$new" && find . -type f -printf '%P\t%s\n' | LC_ALL=C sort) > "$d/new.meta"
        echo "== $name summary =="
        echo "old_actual $(du -sb "$old" | cut -f1)"
        echo "new_actual $(du -sb "$new" | cut -f1)"
        echo "old_apparent $(du -s --apparent-size -B1 "$old" | cut -f1)"
        echo "new_apparent $(du -s --apparent-size -B1 "$new" | cut -f1)"
        echo "old_files $(find "$old" | wc -l)"
        echo "new_files $(find "$new" | wc -l)"
        echo "== $name only-in-old =="
        comm -23 "$d/old.list" "$d/new.list" | head -100 || true
        echo "== $name only-in-new =="
        comm -13 "$d/old.list" "$d/new.list" | head -100 || true
        echo "== $name size-delta =="
        join -t $'\t' -a 1 -a 2 -e MISSING -o 0,1.2,2.2 "$d/old.meta" "$d/new.meta" | awk -F '\t' '$2 != $3 {print}' | head -100 || true
        echo
      }
      compare beagle-workspace
      compare sounio-workspace
      compare beagle-core
    volumeMounts:
    - { name: old-beagle-workspace, mountPath: /old-beagle-workspace, readOnly: true }
    - { name: new-beagle-workspace, mountPath: /new-beagle-workspace, readOnly: true }
    - { name: old-sounio-workspace, mountPath: /old-sounio-workspace, readOnly: true }
    - { name: new-sounio-workspace, mountPath: /new-sounio-workspace, readOnly: true }
    - { name: old-beagle-core, mountPath: /old-beagle-core, readOnly: true }
    - { name: new-beagle-core, mountPath: /new-beagle-core, readOnly: true }
  volumes:
  - { name: old-beagle-workspace, persistentVolumeClaim: { claimName: workspace-data-beagle-workspace-0 } }
  - { name: new-beagle-workspace, persistentVolumeClaim: { claimName: beagle-workspace-local-data } }
  - { name: old-sounio-workspace, persistentVolumeClaim: { claimName: workspace-data-sounio-workspace-habitat-0 } }
  - { name: new-sounio-workspace, persistentVolumeClaim: { claimName: sounio-workspace-local-data } }
  - { name: old-beagle-core, persistentVolumeClaim: { claimName: beagle-data } }
  - { name: new-beagle-core, persistentVolumeClaim: { claimName: beagle-core-local-data } }
YAML

k -n beagle delete pod workspace-post-cutover-compare --ignore-not-found=true --wait=true
k apply -f "$tmp_manifest"

for _ in $(seq 1 90); do
  phase="$(k -n beagle get pod workspace-post-cutover-compare -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]]; then
    break
  fi
  sleep 2
done

k -n beagle logs workspace-post-cutover-compare --tail=400
