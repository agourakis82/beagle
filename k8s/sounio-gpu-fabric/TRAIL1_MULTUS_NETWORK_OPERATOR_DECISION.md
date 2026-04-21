# Trail 1: Multus + NVIDIA Network Operator decision

## Recommendation for this cluster today

Current live cluster facts:

- Kubernetes: `v1.35.2`
- Nodes: Debian 13 + containerd
- Secondary GPU fabric already live on `10.200.0.0/24`
- Live CRDs/components today:
  - `network-attachment-definitions.k8s.cni.cncf.io`
  - `ippools.whereabouts.cni.cncf.io`
  - `kube-multus-ds`
  - `whereabouts`
  - `rdma-shared-dp-ds`

Official NVIDIA Network Operator support does **not** list Debian 13. The
validated OS/runtime matrix for Network Operator v26.1.0 is Ubuntu 22.04/24.04,
RHEL 8/9/10, RHCOS, and SLES 15 SP7 with containerd/CRI-O depending on OS.

Therefore:

1. **Do not install full NVIDIA Network Operator on this cluster today** as the
   production baseline.
2. **Keep the current minimal secondary-network stack**, but pin it to released
   versions instead of `snapshot` / `latest`.
3. For the **officially supported final design** for multi-node GPU training,
   standardize GPU nodes to a supported OS and then install:
   - NVIDIA Network Operator `v26.1.0`
   - NVIDIA GPU Operator `v26.3.0`
   - dedicated GPU fabric on a separate VLAN/subnet (target `10.210.0.0/24`)

## Why

- Multus + Whereabouts + RDMA shared device plugin is enough to stand up a
  working secondary network and advertise RDMA resources.
- It is **not** enough to give you the full supported lifecycle that NVIDIA
  documents for GPUDirect RDMA:
  - NFD integration
  - optional OFED/DOCA driver lifecycle
  - `NicClusterPolicy`
  - `MacvlanNetwork` / `HostDeviceNetwork` / `IPPool`
  - tighter integration with GPU Operator

## Exact "apply today" commands

Pin the current manually-managed stack to upstream released images:

```bash
sudo kubectl -n kube-system set image ds/kube-multus-ds \
  kube-multus=ghcr.io/k8snetworkplumbingwg/multus-cni:v4.2.4

sudo kubectl -n kube-system set image ds/whereabouts \
  whereabouts=ghcr.io/k8snetworkplumbingwg/whereabouts:v0.9.3

sudo kubectl -n kube-system set image ds/rdma-shared-dp-ds \
  k8s-rdma-shared-dp-ds=ghcr.io/mellanox/k8s-rdma-shared-dev-plugin:v1.5.3

sudo kubectl -n kube-system rollout status ds/kube-multus-ds --timeout=180s
sudo kubectl -n kube-system rollout status ds/whereabouts --timeout=180s
sudo kubectl -n kube-system rollout status ds/rdma-shared-dp-ds --timeout=180s
```

Keep the current pilot NAD pattern on the dedicated GPU fabric:

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: gpu-fabric-10-200
  namespace: beagle
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "gpu-fabric-10-200",
      "type": "macvlan",
      "master": "gpufabricbr0",
      "mode": "bridge",
      "mtu": 9000,
      "ipam": {
        "type": "whereabouts",
        "range": "10.200.0.128/25",
        "exclude": ["10.200.0.254/32"]
      }
    }
```

## Official supported target stack

### Order of installation

1. **Install NVIDIA Network Operator v26.1.0**
2. **Apply `NicClusterPolicy`**
3. **Create secondary network objects**
   - `IPPool` (for `nv-ipam`) or use Whereabouts if you deliberately stay
     outside the full operator path
   - `MacvlanNetwork` or `HostDeviceNetwork`
4. **Install NVIDIA GPU Operator v26.3.0**
   - with `driver.rdma.useHostMofed=true` if you keep host NIC drivers
   - prefer DMA-BUF

### CRDs you should expect from the full operator path

- `nicclusterpolicies.mellanox.com`
- `macvlannetworks.mellanox.com`
- `hostdevicenetworks.mellanox.com`
- `ippools.nv-ipam.nvidia.com`
- if you choose the SR-IOV path, also the SR-IOV Network Operator CRDs

## Concrete supported target for multi-node training

For serious multi-node NCCL/RDMA, the official quickstart points to
**SR-IOV Network with RDMA** for distributed ML training, while
**MacVLAN Network with RDMA Shared Device** is positioned as a shared,
moderate-throughput option.

That means:

- **Today on Debian 13**: keep the current Macvlan + Whereabouts + RDMA shared
  device pilot for iteration.
- **Final supported training fabric**: dedicated GPU VLAN/subnet +
  Network Operator + SR-IOV RDMA on supported OS nodes.

## Risks: Multus only vs full Network Operator

### Multus-only / minimal stack

Pros:

- smallest blast radius
- already works on this cluster
- matches current Debian 13 reality

Risks:

- you own all lifecycle/integration work
- current cluster was using floating tags (`snapshot`, `latest`)
- no `NicClusterPolicy`
- no official NVIDIA support path for GPUDirect RDMA on this OS

### Full Network Operator

Pros:

- official NVIDIA control plane for RDMA secondary networking
- integrates with GPUDirect RDMA guidance from GPU Operator docs
- gives you `NicClusterPolicy`, managed secondary networking objects, and
  optional NIC driver lifecycle

Risks:

- current GPU nodes are Debian 13, which is outside the validated OS matrix
- enabling OFED/DOCA management on already-working hosts can conflict with your
  current host-managed inbox driver approach if done carelessly
- SR-IOV path is operationally heavier but is the right final choice for
  serious multi-node training

## Exact supported-path commands (when nodes are on supported OS)

Install Network Operator:

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install network-operator nvidia/network-operator \
  -n nvidia-network-operator \
  --create-namespace \
  --version v26.1.0 \
  --wait
```

Example `NicClusterPolicy` for secondary network + RDMA shared device:

```yaml
apiVersion: mellanox.com/v1alpha1
kind: NicClusterPolicy
metadata:
  name: nic-cluster-policy
spec:
  secondaryNetwork:
    cniPlugins:
      image: plugins
      repository: nvcr.io/nvidia/mellanox
      version: network-operator-v26.1.0
    multus:
      image: multus-cni
      repository: nvcr.io/nvidia/mellanox
      version: network-operator-v26.1.0
  nvIpam:
    image: nvidia-k8s-ipam
    repository: nvcr.io/nvidia/mellanox
    version: network-operator-v26.1.0
    enableWebhook: false
  rdmaSharedDevicePlugin:
    image: k8s-rdma-shared-dev-plugin
    repository: nvcr.io/nvidia/mellanox
    version: network-operator-v26.1.0
    config: |
      {
        "configList": [
          {
            "resourceName": "rdma_shared_device_a",
            "rdmaHcaMax": 63,
            "selectors": {
              "ifNames": ["gpufabric0"]
            }
          }
        ]
      }
  nfd:
    enabled: true
```

Then install GPU Operator for GPUDirect RDMA:

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install --wait gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  --version=v26.3.0 \
  --set driver.rdma.useHostMofed=true
```

If you need the legacy `nvidia-peermem` path instead of DMA-BUF:

```bash
helm upgrade --install --wait gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  --version=v26.3.0 \
  --set driver.rdma.useHostMofed=true \
  --set driver.rdma.enabled=true
```
