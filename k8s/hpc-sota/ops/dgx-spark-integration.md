# DGX Spark — Plano de Integração ao Cluster (Fase 2 do roadmap SOTA)

> Autor: cluster-ops · Data: 2026-06-27 · Status: **runbook pré-execução** (Sparks ainda em Wi-Fi, sem fabric)
> Objetivo: trazer os 2 DGX Spark (GB10) de "ilhas de inferência Ollama" para **membros de primeira classe** do
> supercomputador — fabric 200G RoCE, schedulável (k8s/Slurm), e capaz de coletivos NCCL cross-node GB10↔GB10.

## 0. Inventário medido (27-jun)

| Spark | mgmt IP | SSH | Serving hoje | Fabric 200G (10.10.x) |
|-------|---------|-----|--------------|------------------------|
| spark-3c59 | 192.168.3.24 | `ssh demetrios@spark-3c59` | Ollama: glm-air-companion, GLM-4.5-Air Q4, qwen2.5-coder:32b, qwq:32b, qwen2.5:14b | **DOWN** |
| spark-8e54 | 192.168.3.43 | `ssh demetrios@spark-8e54` | Ollama | **DOWN** |

- Arch: **aarch64 (Grace)** + GPU **GB10 sm_121** (unified memory ~121GB, ~100GB livre p/ modelo).
- Hoje: alcançáveis por mgmt/Wi-Fi (.24 com **jitter de 116ms** — Wi-Fi), wired no LiteLLM router p/ inferência.
- Gap: **fora do k8s E do Slurm**; **sem interconnect de alta velocidade** (links diretos 10.10.0/1.x não sobem).

## 1. Pré-requisito físico (você faz) — sem isto, nada de coletivo

1. Rackear os 2 Sparks.
2. **Fabric RoCE 200G** — dois caminhos coexistem (memória [[project_new_hardware_incoming]]):
   - **Link direto Spark↔Spark** (QSFP56, 200G) → sub-rede `10.10.0.x` / `10.10.1.x` (2 links). É o caminho de menor latência p/ NCCL GB10↔GB10.
   - **Uplink Arista** (7060CX, VLAN 130 10.30.0.0/24) p/ falar com r740/r770/5860 no fabric de serviço.
3. Validar de cada Spark: `ip -br link` (porta 200G UP), `ping 10.10.0.<peer>` e `ping 10.10.1.<peer>`.

> **Gate de aceite da camada física:** os 4 IPs `10.10.{0,1}.{24,43}` respondem ping com rtt < 0.3ms.
> Hoje todos estão `down/na` — este é o bloqueador #1.

## 2. Rede / RoCE (gotchas já conhecidos)

- `NCCL_SOCKET_IFNAME` = a interface do **link direto** (não a Wi-Fi/mgmt). Persistir em env dos workloads.
- GDR (GPUDirect RDMA) no Spark é **diferente de GPU discreta** (memória unificada GB10) — validar com `nvidia-smi`,
  `ibv_devinfo`, e um `nccl-tests all_reduce_perf` GB10↔GB10 antes de declarar pronto.
- Arista RoCE QoS (memória [[project_arista_roce_qos]]): PFC, ECN, jumbo 9214 nas portas GPU — replicar config p/
  as portas onde os Sparks entrarem.
- mgmt Arista: 192.168.3.229 admin/Arista123 (sshpass).

## 3. Join ao k8s (heterogêneo arm64) — o desafio real

O cluster é x86_64; os Sparks são **aarch64**. Não compartilham imagens direto.

1. **Kubelet arm64**: instalar containerd + kubelet arm64 nos Sparks, `kubeadm join` ao control-plane t560.
   - ⚠️ Sincronizar versão: cluster está em **v1.35.5**.
   - Taint dedicado: `sounio.dev/gpu=sm121:NoSchedule` (+ label `sounio.dev/gpu-models=gb10`).
   - `runtimeClassName: nvidia` obrigatório (memória [[project_exotic_discussion_models]]); seccomp `Unconfined`
     (memória [[project_cluster_seccomp_unconfined]]).
2. **Pipeline de imagens arm64**: o registry 192.168.3.207:5003 precisa servir tags arm64. Opções:
   - buildar arm64 nativo **no próprio Spark** (kaniko/buildkit arm64) e push, **ou**
   - manifest-list multi-arch nos builds que importam.
3. **Device plugin / GPU operator arm64**: validar que o nvidia-device-plugin anuncia `nvidia.com/gpu` no Spark
   (sm_121 = GPU inteira, sem time-slice; memória [[project_dgx_spark_serving]]).
4. **Storage**: Ceph RBD/CephFS CSI é multi-arch? Validar o csi-rbdplugin em arm64 — senão usar OrangeFS/NFS p/ scratch.

## 4. Join ao Slurm (alternativa/complemento p/ HPC batch)

- Adicionar `slurmd` arm64 como NodeSet dedicado (`gb10`), partição `gpu-gb10`.
- Features/GRES: `--constraint=gb10` (padrão do cluster é Features, não `--gres` typed — memória [[project_slurm_gres_audit]]).
- Controller via CR `extraConf` (memória [[project_slurm_partition_topology]]); diagnosticar SEMPRE pelo controller pod,
  nunca pelo host.

## 5. Cargas-alvo (o "incrível")

1. **Inferência distribuída GB10↔GB10**: modelo reasoning grande (>100GB) shardado nos 2 Sparks via NCCL no link 200G
   (tensor/pipeline parallel). Hoje cada Spark roda modelos isolados via Ollama; o ganho é servir 1 modelo único maior.
2. **Embedding/rerank do pipeline de memória** já roda nos Sparks (memória [[project_memory_pg_pipeline]]) — promover de
   Wi-Fi p/ fabric melhora throughput e tira o jitter.
3. **Training/fine-tune leve** (Axolotl arm64) usando os 2 GB10 como par de data-parallel.

## 6. Ordem de execução (quando o físico estiver pronto)

```
[ ] 1. Rackear + cabos 200G               (físico)
[ ] 2. Subir links diretos 10.10.x        → gate: ping rtt<0.3ms
[ ] 3. NCCL_SOCKET_IFNAME + nccl-tests    → gate: all_reduce GB10↔GB10 > X GB/s
[ ] 4. kubeadm join arm64 (taint sm121)   → gate: nó Ready, device-plugin anuncia gpu
[ ] 5. registry arm64 / multi-arch        → gate: pull de imagem arm64 OK no Spark
[ ] 6. (opc) slurmd arm64 NodeSet gb10     → gate: srun -p gpu-gb10 nvidia-smi
[ ] 7. inferência distribuída 1ª carga     → gate: 1 modelo >100GB servindo nos 2 Sparks
```

## Referências de memória
[[project_dgx_spark_cluster]] · [[project_dgx_spark_serving]] · [[project_new_hardware_incoming]] ·
[[project_nccl_rdma_status]] · [[project_arista_roce_qos]] · [[project_arista_access_service_fabric]] ·
[[project_cluster_seccomp_unconfined]] · [[project_slurm_gres_audit]]
