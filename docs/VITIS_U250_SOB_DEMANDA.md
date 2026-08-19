# `vitis-u250-builder` — sair do t560 e ligar sob demanda

**Estado em 18-ago-2026:** VM 100, **ligada há 6,2 dias**, no **t560** — que é o SPOF P0 do cluster.

## Por que mexer

O t560 tem 197 GB de RAM. Medido com ele sob carga:

| | |
|---|---|
| memória usada | **169 GB de 188** (2 GB livres) |
| swap | **0** — sem rede de segurança: pressão de memória vira OOM direto |
| load average (15 min) | **60** |

Só duas VMs reservam **113 GB**: esta (81.920 MB) e a `cockpit` (32.768 MB). O resto é o
workspace com os agentes, o etcd e o control-plane.

Uma VM de **build de FPGA**, que é usada em rajadas, mantém 80 GB presos 24×7 no nó de que o
cluster inteiro depende. O custo é pago todo dia; o benefício, em poucas horas por mês.

## Ela PODE sair do t560 — verificado

`vitis-u250-builder` **não tem passthrough PCIe**. A linha de comando do processo KVM não traz
`vfio-pci`, `hostpci` nem `romfile`. A U250 é alcançada **pela rede** (VNx no fabric, responde
ping), não pela placa local.

Isso é a diferença entre "pode migrar" e "está presa ao host", e foi a primeira coisa checada:
uma VM com a FPGA em passthrough não sairia daqui sem mover a placa.

**Recursos a acomodar no destino:** 16 vCPU · 80 GB RAM · disco de 400 GB (`vm-100-disk-0`,
LVM local) · 2 NICs (uma delas MTU 9000 — o fabric).

## Destino

| nó | RAM | vCPU | observação |
|---|---|---|---|
| **r740** | **527 GB** | 80 | folga de RAM enorme; ⚠️ disco historicamente apertado (~115 GB livres) — **conferir o thin pool antes** |
| dl380 | 131 GB | 96 | os 80 GB da VM deixariam o nó no limite |
| r770 | 131 GB | 128 | idem, e é onde vive o serving de LLM |
| 5860 | 263 GB | **12** | RAM sobra, CPU não: 16 vCPU num host de 12 é overcommit |

**Recomendação: r740** — é o único com folga de RAM real. O bloqueio é o disco de 400 GB, que
precisa ser medido no thin pool (`lvs -o lv_name,lv_size,data_percent pve`) antes de migrar. Se
não couber, a alternativa é mover o disco para **Ceph RBD** primeiro, o que também torna
migrações futuras baratas.

## O ganho não depende da migração

**Desligar já devolve os 80 GB.** Migrar decide onde ela liga quando for preciso; desligar decide
que ela não ocupa nada quando não for. As duas coisas são independentes, e a segunda é a que
alivia o t560 hoje.

---

## Procedimento

Nada abaixo roda sem `sudo` no host Proxmox. Os comandos estão explícitos para serem executados
por quem tem o acesso.

### 1. Confirmar que não há build em andamento

Desligar no meio de uma síntese perde horas de trabalho. **Sempre** antes de qualquer passo:

```bash
sudo qm guest exec 100 -- uptime
sudo qm guest exec 100 -- pgrep -a -f 'vitis|vpp|vivado'
```

Saída vazia no segundo comando = ninguém sintetizando.

### 2. Tirar do boot automático (o passo que evita a volta silenciosa)

```bash
sudo qm set 100 --onboot 0
```

Sem isto, o próximo reboot do t560 religa a VM e desfaz tudo — e ninguém vai perceber, porque
não há nada que acuse 80 GB voltando a ficar presos.

### 3. Desligar

```bash
sudo qm shutdown 100 --timeout 300     # shutdown limpo, NUNCA `qm stop` (corta na energia)
sudo qm status 100                     # esperar: status: stopped
free -g                                # confirmar os ~80 GB de volta
```

### 4. Migrar (depois de medir o disco)

```bash
sudo lvs -o lv_name,lv_size,data_percent pve | grep vm-100   # quanto o disco USA de fato
sudo qm migrate 100 r740-proxmox --with-local-disks --online 0
```

`--online 0` porque a VM já está desligada — migração a frio é mais simples e não precisa de
banda para o estado de memória.

### 5. Ligar sob demanda

```bash
sudo qm start 100                                  # no nó onde ela estiver
sudo qm guest exec 100 -- systemctl is-system-running
# ... trabalho de síntese ...
sudo qm shutdown 100 --timeout 300                 # DESLIGAR AO TERMINAR faz parte do trabalho
```

---

## A regra

> A `vitis-u250-builder` fica **desligada** por padrão. Ligá-la é um ato deliberado, e
> desligá-la ao terminar faz parte da tarefa que a ligou.

Deixá-la ligada "só por hoje" é como ela chegou a 6,2 dias.

## O que verificar depois

- `free -g` no t560: os 80 GB voltaram e permanecem.
- `qm config 100 | grep onboot`: tem que ser `onboot: 0`.
- O load do t560 sob carga normal: a saturação era de memória e I/O, não de disco (havia 101 GB
  livres em `/` quando isto foi medido) — se persistir com a VM fora, a causa é outra e este
  documento não a resolve.
