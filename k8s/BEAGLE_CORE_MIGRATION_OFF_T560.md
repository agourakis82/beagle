# Dívida: migrar `beagle-core` do t560-proxmox

**Por que existe:** `t560-proxmox` (control-plane) adquire `DiskPressure` periodicamente (taint `node.kubernetes.io/disk-pressure:NoSchedule`), evictando os pods de `beagle-core` que estão pinados lá. O ReplicaSet cria substitutos que também são evictados — acumulando centenas de pods terminais antes do `evicted-cleanup` CronJob passar.

**Por que não foi resolvido agora:** `beagle-core` monta `/var/lib/beagle` de uma PVC `beagle-core-local-data` com storageClass `local-zfast-t560` — node-local, não portable. Toda a persistência cognitiva vive lá:

```
/var/lib/beagle/cognitive/voids.jsonl
/var/lib/beagle/cognitive/fractals.jsonl
/var/lib/beagle/cognitive/phis.jsonl
/var/lib/beagle/cognitive/deep_thinks.jsonl
/var/lib/beagle/cognitive/mcp_tool_calls.jsonl
/var/lib/beagle/cognitive/physio.jsonl
/var/lib/beagle/feedback/*.jsonl
```

Dropar o PVC = perder histórico. Migrar data = trabalho dedicado.

## Opções para uma sessão dedicada

**A. Migrar para Ceph-backed PVC (recomendado).**
Já existe `beagle-data` (20Gi ceph-rbd-ssd, RWO, Bound). Cria-se um Job que:
1. Mount-a ambas as PVCs no mesmo pod (só possível se ambas forem RWO e o pod rodar em t560).
2. `cp -av /old/* /new/`.
3. Edita Deployment: `claimName: beagle-core-local-data` → `beagle-data`.
4. Remove `nodeSelector: kubernetes.io/hostname: t560-proxmox`.
5. Rollout.

**Riscos:**
- Window de race: tool/feedback events que chegam durante o cp podem ser perdidos. Mitigação: scale beagle-core pra 0 durante a cópia (janela de 2-3min).
- `beagle-data` pode já ter uso próprio — verificar antes (`kubectl -n beagle describe pvc beagle-data` + `ls /var/lib/beagle` via pod atual).

**B. Expandir o PVC local em um nó maior.**
Se algum outro nó tiver `local-zfast` disponível (r740, r770), criar `local-zfast-<node>-beagle-core-pv` e migrar via rsync através do network. Menos arriscado mas requer um nó com disco SSD local provisionado.

**C. Migrar para um bind mount NFS/OrangeFS compartilhado.**
Há OrangeFS no cluster (`orangefs-training` PVC). Seria semanticamente mais correto pro "substrato cognitivo distribuído". Mas RWX + FS-level consistency pode introduzir latência em JSONL appends.

## Critério de decisão

Fazer **A** quando o próximo disk-pressure event causar downtime perceptível (> 5min). Até lá, o CronJob `evicted-cleanup` (every 10min) mantém a lixeira sob controle e o ReplicaSet eventualmente consegue schedular um pod válido quando a pressão baixa.

## Verificação pós-migração

```
kubectl -n beagle get pod -l app.kubernetes.io/name=beagle-core -o jsonpath='{.items[0].spec.nodeName}'
# Expected: não-t560-proxmox (r770 ou r740)

kubectl -n beagle exec deploy/beagle-core -- ls /var/lib/beagle/cognitive
# Expected: all 6 jsonl files present with recent mtime

curl -s -H "X-Beagle-Consumer: beagle-operator" \
     -H "Authorization: Bearer $(curl -s http://beagle-auth.tail21cbc4.ts.net/api/auth/beagle-token | jq -r .token)" \
     http://beagle-core.tail21cbc4.ts.net/api/v1/cognitive/state | \
  jq '.recent_void_journeys | length'
# Expected: > 0 (history carried over)
```
