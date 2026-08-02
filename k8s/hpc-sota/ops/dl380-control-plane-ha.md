# DL380 G10 → 3-Member HA Control-Plane (de-SPOF do t560)

> Autor: cluster-ops · 2026-06-27 · **Status: runbook pré-execução** (DL380 ainda não rackeado; PSU pendente).
> Meta decidida: **3 membros etcd = t560 + DL380 + r740** (tolera 1 falha) + endpoint VIP + safeguards de etcd nos 3.
> NÃO executar os passos disruptivos enquanto o control-plane for único — staging seguro só.

## 0. Estado atual (medido 27-jun)
- kubeadm **v1.35.5**, etcd **STACKED**, **1 membro** (`t560-proxmox`, peer `192.168.3.169:2380` na LAN mgmt).
- `controlPlaneEndpoint: k8s-api.darwin.lan:6443` → resolve **10.100.100.2** (= só o t560, no fabric). **SPOF.**
- certSANs: `k8s-api.darwin.lan`, `t560-proxmox`, `192.168.3.169`. clusterName=`darwin`. serviceSubnet `10.96.0.0/16`.
- Nós InternalIP no **fabric 10.100.100.x**; etcd na **mgmt 192.168.3.x**. (Split de rede — manter etcd na mgmt.)
- **VIP escolhido: `10.100.100.20`** (livre; fabric, mesma rede dos InternalIP dos nós).

## ⚠️ A verdade do quorum (por que 3, não 2)
etcd stacked: N membros → quorum = ⌊N/2⌋+1. **2 membros = quorum 2 = tolera 0 falhas** (PIOR: os dois têm que estar vivos).
**3 = quorum 2 = tolera 1 falha.** Por isso o destino é 3 (t560+DL380+r740), com o DL380 sendo o 1º a entrar.

## 1. Pré-flight — STAGE AGORA (não-disruptivo)

### 1a. DNS & VIP
- Reservar **10.100.100.20** p/ VIP (já confirmado livre). Mais tarde: `k8s-api.darwin.lan` → 10.100.100.20.
- Provider do VIP = **kube-vip** em modo ARP/L2 no fabric (`vmbr100`/interface 10.100.100.x). Manifesto: `kube-vip-static-pod.yaml` (neste dir).

### 1b. Preparar DL380 (x86 Xeon; RTX8000+A5000+CX-5)
```
[ ] OS Debian 13 trixie (igual aos outros), kernel 7.0.x-pve
[ ] CX-5 no fabric: IP 10.100.100.5 (próximo livre) + IP mgmt 192.168.3.x p/ etcd peer
[ ] containerd 1.7.x/2.x + runtimeClassName nvidia (driver + toolkit p/ RTX8000+A5000)
[ ] kubeadm/kubelet/kubectl = 1.35.5 (PIN exato; repo k8s)
[ ] swap off; br_netfilter; sysctl net.ipv4.ip_forward=1; time sync (chrony)
[ ] **containerd data-root em disco dedicado, NÃO no root LV** (lição t560) — DL380 tem disco p/ isso
[ ] firewall/fabric: 6443 (API), 2379-2380 (etcd), 10250 (kubelet) abertos entre CPs
```

### 1c. Preparar r740 p/ promoção (é o 3º membro — hoje é worker GPU com cargas)
> kubeadm **não promove** worker→CP in-place. Precisa **drain → reset → join --control-plane**.
```
[ ] IP mgmt 192.168.3.x no r740 p/ etcd peer (confirmar)
[ ] janela: drenar cargas do r740 (serving GPU + Slurm worker) — migrar/parar antes
[ ] etcd em disco rápido no r740 (não no root local que já deu DiskPressure — ver [[project_slurm_diskpressure_builds]])
```

### 1d. certSANs (editar kubeadm-config agora é seguro; regen do cert é na janela)
Adicionar à lista `certSANs` (CM `kube-system/kubeadm-config`, ClusterConfiguration):
`10.100.100.20` (VIP), `dl380-proxmox`, `10.100.100.5`, `r740-proxmox`, `10.100.100.4`.

## 2. Cutover do VIP (janela curta, ~10s blip de API)
```bash
# 1. Subir kube-vip no t560 (advertise 10.100.100.20)
sudo cp kube-vip-static-pod.yaml /etc/kubernetes/manifests/kube-vip.yaml   # vira static pod
# 2. Regenerar cert do apiserver c/ os novos SANs
sudo kubeadm certs renew apiserver && sudo kubeadm certs renew apiserver-kubelet-client
# (reinicia o apiserver static pod; ~10s)
# 3. DNS: k8s-api.darwin.lan -> 10.100.100.20 (no UDM/CoreDNS de casa, ver [[project_home_network_unifi]])
# 4. Validar: kubectl get nodes via VIP; curl -k https://10.100.100.20:6443/healthz
```

## 3. Join DL380 como 2º control-plane
```bash
# No t560:
sudo kubeadm init phase upload-certs --upload-certs        # -> <certificate-key>
sudo kubeadm token create --print-join-command             # -> join base
# No DL380 (juntar como CP):
sudo kubeadm join 10.100.100.20:6443 \
  --token <tok> --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane --certificate-key <certificate-key> \
  --apiserver-advertise-address 10.100.100.5
# Verificar: etcd 2 membros, apiserver/sched/ctrl-mgr static pods no DL380
kubectl -n kube-system exec etcd-t560-proxmox -- etcdctl member list -w table ...
```
**Após:** aplicar safeguards (§5) no DL380. Taint conforme papel (CP + serving GPU, SEM batch pesado).

## 4. Join r740 como 3º control-plane (a etapa que dá HA real)
```bash
kubectl drain r740-proxmox --ignore-daemonsets --delete-emptydir-data   # migrar cargas
# No r740: sudo kubeadm reset -f  (sai como worker)
# Re-join como CP (mesmo padrão do §3, advertise 10.100.100.4)
sudo kubeadm join 10.100.100.20:6443 --control-plane --certificate-key <key> ...
kubectl uncordon r740-proxmox
```
**Resultado:** **3 membros etcd, quorum 2, tolera 1 falha = HA.** Validar `etcdctl endpoint health --cluster`.

## 5. Safeguards de etcd nos 3 CPs (a condição decidida)
Replicar nos 3 o que já existe no t560 (ver [[project_t560_etcd_io_starvation]]):
- **`etcd-ioprio.service`** — I/O realtime p/ o etcd (impede fdatasync de 4s sob carga).
- **io.max / `souc-cap.service`** — capar I/O idle de batch (souc, builds) no cgroup.
- etcd em **disco dedicado/rápido**, NUNCA no root LV que enche.
- `evictionHard` absoluto (15Gi) já padronizado; replicar.
- Operadores control-plane-tolerantes passam a **espalhar** nos 3 CPs (tira a concentração do t560).

## 6. Pós-HA — colher o ganho
- **Liberar os 32 cores reservados do t560** ao Slurm (cpu-ops 32→maior) — agora que o CP é tolerante a falha,
  o t560 deixa de ser sagrado. Ver [cluster-cpu-tiers.md](cluster-cpu-tiers.md).
- Manutenção sem downtime: drenar 1 CP por vez p/ patch/reboot.

## Rollback
- VIP: remover `/etc/kubernetes/manifests/kube-vip.yaml`, DNS volta p/ 10.100.100.2.
- Membro etcd ruim: `etcdctl member remove <id>` + `kubeadm reset` no nó.

Ver [[project_t560_disk_lvm]], [[project_t560_etcd_io_starvation]], [[project_dl380_g10_incoming]],
[[project_cluster_sota_audit]], [[project_home_network_unifi]].
