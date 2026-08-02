# Cluster CPU/Compute Tiers — Converged k8s + Slurm Policy

> Autor: cluster-ops · 2026-06-27 · Cluster convergido: k8s (plataforma/serving) + Slurm (HPC batch) no mesmo metal.
> Decisão central: **quanto de cada nó o Slurm pode tomar sem estrangular os serviços co-residentes.**
> O teto do Slurm por nó = `spec.slurmd.resources.limits.cpu` no NodeSet CR (`nodesets.slinky.slurm.net`, ns `slurm-pilot`).
> `CPUEfctv` (o que o Slurm aloca) SEGUE esse cgroup limit, NÃO o request do k8s.

## Por que existem tiers

Não é HPC "puro" (onde o Slurm é dono do nó). Aqui o batch divide o metal com: control-plane, fleet de LLM
(vLLM/moshi/trellis/falcon), memory pipeline (pg/embed/rerank), MCP, etc. Medição 2026-06-27: **utilização real de
CPU = 0–11% em todos os nós** — o gargalo NUNCA foi hardware, eram caps conservadores. Mas serving precisa de
**headroom de burst**, então cada nó recebe um tier conforme o que mais roda nele.

## Tiers vigentes

| Nó | HW cores | RAM | Tier | Slurm cap (CPUEfctv) | Headroom p/ k8s | Racional |
|----|----------|-----|------|----------------------|------------------|----------|
| **r770** | 128 | 128G | **HPC-first** | **120** | 8 | serving leve (vllm-qwen14b), CPU 0% → batch manda |
| **r740** | 80 | **515G** | **Balanceado** | **72** | 8 | monstro de RAM; serving GPU pesado (trellis/baichuan/moshi) precisa de burst; ideal p/ jobs CPU+memória |
| **t560** | 64 | 192G | **Service-first** | **32** (fixo) | 32 | control-plane ÚNICO (etcd/apiserver) — NÃO subir até existir HA |
| **5860** | 12 | 128G | GPU-probe | 12 | 0 | nó pequeno, GPU on-demand |
| | | | | **= ~236 cores Slurm** | | (era 172 no início da sessão) |

## Como usar (submissão)

```bash
# Job CPU grande, HPC-first:
srun -p all -w gpuorangefs-r770-proxmox -c 120 ...        # até 120 cores
sbatch -p all -w gpuorangefs-multi-r740-proxmox -c 72 ... # 72 cores + 515G RAM (SAT, memória-pesado)
# NÃO usar cpu-ops (t560) p/ jobs grandes — é control-plane, cap 32 EXCLUSIVE.
```

## Como ajustar um tier (durável)

```bash
kubectl patch nodeset.slinky.slurm.net -n slurm-pilot <NODESET> --type=merge \
  -p '{"spec":{"slurmd":{"resources":{"limits":{"cpu":"<N>"}}}}}'
# NodeSets: gpuorangefs (r770+5860, 5860 clampa a 12) · gpuorangefs-multi (r740) · cpuops (t560)
```
- `workloadDisruptionProtection:true` → Slinky DRENA o worker e só reinicia quando os jobs terminam (requeue p/ forçar).
- Verificar: `kubectl exec -n slurm-pilot slurm-pilot-controller-0 -c slurmctld -- scontrol show node <node> | grep CPUEfctv`.
- **MemSpecLimit** é o análogo p/ RAM (`slurmd.resources.limits.memory`); subir junto se o job for memória-pesado.

## Tier 4 (futuro) — DGX Spark dedicado HPC

Quando os 2 GB10 entrarem no fabric 200G (ver [dgx-spark-integration.md](dgx-spark-integration.md)):
- **HPC-first total** — sem serviços k8s competindo; Slurm dono do nó.
- NodeSet arm64 dedicado `gb10`, partição `gpu-gb10`, `--constraint=gb10`.
- ~20 cores Grace + GB10 cada; batch e training distribuído GB10↔GB10 via NCCL no link direto.
- Este é o caminho pra capacidade HPC "pura" sem o trade-off convergido.

## Roadmap pra HPC de verdade (reduz o trade-off convergido)
1. **Control-plane HA** (3 masters, usar DL380 G10) → libera t560 dos 32 reservados.
2. **Right-size requests** dos serviços que reservam e não usam (não muda CPUEfctv, mas limpa scheduling do k8s).
3. **Sparks como Tier 4 dedicado** → metal HPC puro.

Ver [[project_slurm_partition_topology]], [[project_cluster_sota_audit]], [[project_slurm_gres_audit]].
