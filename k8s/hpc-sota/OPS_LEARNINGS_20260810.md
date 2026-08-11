# Aprendizados operacionais — campanha de 2026-08-10/11

> Registro do que **custou tempo real de diagnóstico** numa campanha que foi de auditoria
> de armazenamento até HA de control-plane, PFC e NVMe-oF. Cada item aqui é uma armadilha
> que já mordeu uma vez. Não é documentação de arquitetura — para isso ver
> [dl380-control-plane-ha.md](dl380-control-plane-ha.md) e [DL380_ONBOARDING.md](DL380_ONBOARDING.md).

---

## 1. Gerência fora de banda — o mapa de iDRAC engana

| Nó | BMC | Rede |
|---|---|---|
| t560 | `192.168.3.163` | mgmt |
| r770 | `10.10.10.138` | isolada |
| **r740** | **`192.168.0.175`** | **isolada** |
| dl380 | iLO `192.168.3.153` | porta desconectada |

**A armadilha:** `192.168.3.163` é o iDRAC do **t560**, não do r740. Um power-cycle ali
derruba o control-plane. Credenciais e IPs estão em `~/RECOVERY-CARD.html`.

**Antes de qualquer ação de energia**, confirme o alvo pelo Redfish:

```bash
curl -sk -u root:<senha> https://<bmc>/redfish/v1/Systems/System.Embedded.1 | jq '{Model, SKU}'
```

Varrer a subnet de mgmt por porta 443 **não** encontra o r740 — ele está em rede isolada,
alcançável via gateway mas fora da faixa varrida.

---

## 2. Slinky (operador Slurm) — três comportamentos não-óbvios

**Reporta réplica pronta sem pod existir.** Após manutenção de nó, o NodeSet mostrou
`desired=1 ready=1` com zero pods no cluster inteiro. O nó ficou `down*` no Slurm.
Diagnostique pelo **pod**, nunca pelo status do NodeSet.

```bash
kubectl -n slurm-pilot patch nodeset <ns> --type merge -p '{"spec":{"replicas":0}}'
sleep 15
kubectl -n slurm-pilot patch nodeset <ns> --type merge -p '{"spec":{"replicas":1}}'
```

**Patch em `extraConf` NÃO reinicia o pod.** Alterei `TmpDisk` e o valor não apareceu por
horas — o pod tinha 4h54m de idade. É preciso deletar o pod explicitamente.

**Os nós são dinâmicos** (`State=...+DYNAMIC`). `TmpDisk`, `RealMemory` e `Features` vêm do
registro do slurmd, não do `slurm.conf` do controlador. `scontrol reconfigure` não adianta.

---

## 3. `containerd.io` remove o `docker.io`

Instalar `containerd.io` (repo Docker) **desinstala** o `docker.io` do Debian, porque este
depende do `containerd` nativo. O `docker.service` desaparece e os containers morrem.

Em nós que rodam Docker (5860 tem o registry; r740 tem qdrant/buildkit), instale tudo na
**mesma transação**:

```bash
apt-get install -y -o Dpkg::Options::=--force-confold containerd.io docker-ce docker-ce-cli docker-buildx-plugin
```

O `--force-confold` é obrigatório: sem ele o dpkg trava num prompt interativo sobre
`config.toml` e deixa pacotes não configurados.

---

## 4. `kubeadm reset` — três efeitos colaterais silenciosos

**Apaga os labels do nó.** Todos os `sounio.dev/*` somem. Consequência em cascata: device
plugins não sobem, o nó para de anunciar `nvidia.com/gpu` / `amd.com/gpu` / `sounio.dev/u250`,
e o slurmd não agenda. Salve antes:

```bash
kubectl get node <n> -o jsonpath='{.metadata.labels}' | tr ',' '\n' | grep sounio
```

**Não remove o membro do etcd.** Apaga o data dir mas deixa a associação. O cluster fica com
N membros e um morto — sem tolerância a falha, e de forma invisível. Remova à mão:

```bash
etcdctl member list          # pegue o ID
etcdctl member remove <id>
```

**O ConfigMap `cluster-info` guarda o endpoint do `kubeadm init` original.** Se o nó que fez o
init sair, todo join futuro falha com `connection refused`. Corrija para o VIP:

```bash
kubectl -n kube-public get cm cluster-info -o jsonpath='{.data.kubeconfig}' | grep server:
```

---

## 5. Componentes fixados a um único nó — o padrão mais perigoso

Encontrados **três** na mesma campanha:

| Componente | Estava preso a | Impacto ao drenar |
|---|---|---|
| `csi-rbdplugin-provisioner` | r740 | **cluster inteiro perdeu anexação de volumes RBD** |
| `csi-cephfsplugin-provisioner` | t560 | mesmo risco, latente |
| `litellm-router` | r740 | companion sem voz |

Um provisioner CSI preso a um nó é contradição de desenho — ele existe para servir o cluster.
Auditoria:

```bash
kubectl get deploy,statefulset,daemonset -A -o json | jq -r '.items[] |
  select((.spec.template.spec.nodeSelector//{}|tostring)|test("proxmox")) |
  "\(.kind) \(.metadata.namespace)/\(.metadata.name)"'
```

Antes de drenar qualquer nó, rode isso para o nó em questão.

---

## 6. LVM thin não devolve bloco sem `fstrim`

Apagar 246 GB dentro de um volume thin deixou o **pool em 94%** enquanto o filesystem
mostrava 13%. Pool cheio dá erro de I/O em **todos** os volumes dele, inclusive discos de VM.

O `fstrim.timer` é semanal. Após deleção grande, force:

```bash
fstrim -v /caminho     # devolveu 249 GiB em 12s
lvs -o lv_name,data_percent <vg>/<pool>
```

Também: `autoextend` está desligado em todos os nós (`thin_pool_autoextend_threshold`
comentado = 100) e os pools estão em `lv_when_full=queue` — se encherem, a escrita **trava
60 s** antes de falhar, fazendo o nó parecer congelado em vez de dar erro.

---

## 7. Armazenamento e latência — o que o fabric de 100G resolve e o que não

Medido com o perfil de escrita do etcd (`fio --ioengine=sync --fdatasync=1 --bs=2300`):

| Alvo | p50 | p99 |
|---|---|---|
| NVMe local | 63 µs | 71 µs |
| **NVMe-oF sobre RoCE** | **65 µs** | **120 µs** |
| Ceph RBD (mesmo fabric) | 7.630 µs | 33.160 µs |

**O RBD é 117× mais lento que o local no mediano** — e isso não é banda, é a serialização de
round-trips de replicação. Os 100 Gb não ajudam.

**Regra:** RBD/CephFS para dado durável e compartilhado. NVMe-oF ou disco local para escrita
síncrona pequena (etcd, build de compilador). **Nunca etcd em Ceph** — 33 ms de p99 contra
requisito de 10 ms.

**Nunca etcd em NVMe-oF tampouco**: a latência serve, mas o transporte não replica, e o Raft
assume falhas de membros independentes. Um alvo servindo dois membros = perda de quorum num
reboot.

---

## 8. RoCE / PFC — o fabric estava lossless por acidente

**O PFC estava nas portas erradas.** Configurado em `Et31/1` e `Et32/1`, que são as *outras*
redes do r740 e r770 — não as do fabric `10.100.100.0/24`. Mapeie por MAC, nunca por suposição:

```bash
ssh <arista> "show lldp neighbors"            # porta -> MAC
cat /sys/class/net/<porta-fisica>/address     # MAC do host
```

**Ligar PFC desliga o pause global automaticamente.** Se o tráfego RoCE não estiver marcado na
prioridade 3, o link fica **sem controle de fluxo nenhum** — pior que antes. Sempre configure
marcação **antes** de habilitar PFC.

**Não precisa de `mlnx_qos`.** Ferramenta padrão do Linux resolve:

```bash
echo 104 > /sys/kernel/config/rdma_cm/<rdma-dev>/ports/1/default_roce_tos   # DSCP 26
dcb app add dev <netdev> dscp-prio 26:3
dcb pfc set dev <netdev> prio-pfc 3:on
```

Persistido em `roce-pfc.service` nos 5 nós. **A config do Arista precisa de `write memory`** —
sem isso evapora no reboot do switch.

**Verificação de que funciona** (contadores devem sair de zero):

```bash
ethtool -S <netdev> | grep prio3_pause
ssh <arista> "show priority-flow-control counters | nz"
```

---

## 9. Erros de medição que produzem conclusão errada

**`ibv_devinfo` ausente conta como zero.** Reportei "0 portas RDMA ativas" em três nós; era
o binário que não existia. Leia o sysfs:

```bash
cat /sys/class/infiniband/*/ports/1/state
```

**Carga no mesmo dispositivo contamina a latência.** Medi 49 ms de p99 rodando fio de banda no
*mesmo* namespace do teste de latência — media contenção de dispositivo, não de rede. Gere
carga em caminho separado.

**Cuidado com o denominador.** `504047/17652477 objects misplaced` — um regex de
`[0-9]+ objects misplaced` pega o **total**, não os deslocados.

---

## 10. Ceph — reweights manuais escondem capacidade

O balancer reportava *"distribuição já perfeita"* enquanto o `osd.10` estava a 85% e em
`nearfull`. O balancer `upmap` equilibra **contagem de PGs**, não bytes.

A causa eram reweights manuais bloqueando **~1,7 TiB**: `osd.15`/`osd.17` em 0,50 e os quatro
HDDs do r740 em 0,25, todos com espaço sobrando. Subir gradualmente resolveu.

**Causa estrutural por trás:** os pools HDD usam `size=3` com domínio de falha por **host**, e
só 4 hosts têm HDD. Como r770 (2,05 TiB) e r740 (1,64 TiB) participam da maioria dos PGs mas
detêm menos de 8% da capacidade cada, **o tier é limitado pelos hosts menores**, não pelos
25 TiB brutos. Reequilibrar não cura; cura é adicionar HDD nos nós pequenos.

---

## 11. Observabilidade — o que faltava

Havia **5 node-exporters e zero regras de filesystem**. Foi por isso que um thin pool chegou a
94% e um volume a 100% (com o `beagle-memory-engine` em HTTP 500) sem nenhum aviso.

Criado `darwin-filesystem-capacity-rules` com espaço, **inodes** (build de compilador esgota
inode antes de bloco) e `predict_linear` para pegar runaway antes de virar incidente.
