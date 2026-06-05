from dcim.models import Cable, Device, DeviceRole, DeviceType, Interface, Manufacturer, Site
from ipam.models import IPAddress


site = Site.objects.get(slug="sounio-lab")


def upsert_manufacturer(name, slug):
    obj = Manufacturer.objects.filter(slug=slug).first()
    if not obj:
        obj = Manufacturer(name=name, slug=slug)
        obj.save()
        print("created manufacturer", slug)
    else:
        changed = False
        if obj.name != name:
            obj.name = name
            changed = True
        if changed:
            obj.save()
            print("updated manufacturer", slug)
        else:
            print("existing manufacturer", slug)
    return obj


def upsert_role(name, slug, color):
    obj = DeviceRole.objects.filter(slug=slug).first()
    if not obj:
        obj = DeviceRole(name=name, slug=slug, color=color)
        obj.save()
        print("created role", slug)
    else:
        changed = False
        if obj.name != name:
            obj.name = name
            changed = True
        if obj.color != color:
            obj.color = color
            changed = True
        if changed:
            obj.save()
            print("updated role", slug)
        else:
            print("existing role", slug)
    return obj


def upsert_device_type(manufacturer, model, slug, u_height=1):
    obj = DeviceType.objects.filter(manufacturer=manufacturer, slug=slug).first()
    if not obj:
        obj = DeviceType(
            manufacturer=manufacturer,
            model=model,
            slug=slug,
            u_height=u_height,
            is_full_depth=True,
        )
        obj.save()
        print("created device-type", slug)
    else:
        changed = False
        if obj.model != model:
            obj.model = model
            changed = True
        if obj.u_height != u_height:
            obj.u_height = u_height
            changed = True
        if changed:
            obj.save()
            print("updated device-type", slug)
        else:
            print("existing device-type", slug)
    return obj


def upsert_device(name, role, device_type, description, status="active", serial="lab-managed"):
    obj = Device.objects.filter(name=name).first()
    if not obj:
        obj = Device(
            name=name,
            site=site,
            role=role,
            device_type=device_type,
            status=status,
            description=description,
            serial=serial,
        )
        obj.save()
        print("created device", name)
    else:
        changed = False
        if obj.site_id != site.id:
            obj.site = site
            changed = True
        if obj.role_id != role.id:
            obj.role = role
            changed = True
        if obj.device_type_id != device_type.id:
            obj.device_type = device_type
            changed = True
        if str(obj.status) != status:
            obj.status = status
            changed = True
        if obj.serial != serial:
            obj.serial = serial
            changed = True
        if obj.description != description:
            obj.description = description
            changed = True
        if changed:
            obj.save()
            print("updated device", name)
        else:
            print("existing device", name)
    return obj


def upsert_interface(device, name, iface_type, description="", mtu=None, mgmt_only=False, enabled=True):
    obj = Interface.objects.filter(device=device, name=name).first()
    if not obj:
        obj = Interface(
            device=device,
            name=name,
            type=iface_type,
            description=description,
            mtu=mtu,
            mgmt_only=mgmt_only,
            enabled=enabled,
        )
        obj.save()
        print("created interface", f"{device.name}:{name}")
    else:
        changed = False
        if obj.type != iface_type:
            obj.type = iface_type
            changed = True
        if obj.description != description:
            obj.description = description
            changed = True
        if obj.mtu != mtu:
            obj.mtu = mtu
            changed = True
        if bool(obj.mgmt_only) != bool(mgmt_only):
            obj.mgmt_only = mgmt_only
            changed = True
        if bool(obj.enabled) != bool(enabled):
            obj.enabled = enabled
            changed = True
        if changed:
            obj.save()
            print("updated interface", f"{device.name}:{name}")
        else:
            print("existing interface", f"{device.name}:{name}")
    return obj


def upsert_ip(address, dns_name, iface):
    obj = IPAddress.objects.filter(address=address).first()
    if not obj:
        obj = IPAddress(address=address, status="active", dns_name=dns_name)
        obj.assigned_object = iface
        obj.save()
        print("created ip", address)
    else:
        changed = False
        if str(obj.status) != "active":
            obj.status = "active"
            changed = True
        if obj.dns_name != dns_name:
            obj.dns_name = dns_name
            changed = True
        if obj.assigned_object != iface:
            obj.assigned_object = iface
            changed = True
        if changed:
            obj.save()
            print("updated ip", address)
        else:
            print("existing ip", address)
    return obj


def set_primary(device, field_name, ip_obj):
    current = getattr(device, field_name)
    if current != ip_obj:
        setattr(device, field_name, ip_obj)
        device.save()
        print("set", field_name, "for", device.name, "->", ip_obj.address)


def upsert_cable(label, a_iface, b_iface):
    existing = Cable.objects.filter(label=label).first()
    if existing:
        print("existing cable", label)
        return existing
    if a_iface.cable_id or b_iface.cable_id:
        print("skipped cable", label, "interface already connected")
        return None
    obj = Cable(label=label, status="connected", a_terminations=[a_iface], b_terminations=[b_iface])
    obj.save()
    print("created cable", label)
    return obj


lab_mfr = upsert_manufacturer("Sounio Lab", "sounio-lab")
arista_mfr = upsert_manufacturer("Arista Networks", "arista-networks")
hp_mfr = upsert_manufacturer("Hewlett Packard Enterprise", "hpe")

role_control = upsert_role("Control Plane", "control-plane", "1f77b4")
role_gpu = upsert_role("GPU Node", "gpu-node", "ff7f0e")
role_service = upsert_role("Service Edge", "service-edge", "2ca02c")
role_switch = upsert_role("Network Switch", "network-switch", "9467bd")

server_type = upsert_device_type(lab_mfr, "Proxmox HPC Node", "proxmox-hpc-node")
dl380_type = upsert_device_type(hp_mfr, "ProLiant DL380 Gen10", "proliant-dl380-gen10", u_height=2)
switch_type = upsert_device_type(arista_mfr, "DCS-7060CX-32S", "dcs-7060cx-32s")

devices = {
    "t560-proxmox": upsert_device("t560-proxmox", role_control, server_type, "Control-plane host with workspace services"),
    "r770-proxmox": upsert_device("r770-proxmox", role_gpu, server_type, "GPU node with NVIDIA L4"),
    "r740-proxmox": upsert_device("r740-proxmox", role_gpu, server_type, "GPU node with NVIDIA RTX A5000"),
    "5860-proxmox": upsert_device("5860-proxmox", role_service, server_type, "GPU/service-edge node with NVIDIA RTX 4000 Ada"),
    "dl380-proxmox": upsert_device(
        "dl380-proxmox",
        role_gpu,
        dl380_type,
        "Planned HP DL380 G10 expansion node; not admitted to Kubernetes, OrangeFS, or Slurm yet",
        status="planned",
        serial="pending-inventory",
    ),
    "arista-7060": upsert_device("arista-7060", role_switch, switch_type, "Arista 7060 lab fabric switch"),
}

interfaces = {}

for name, mgmt_ip in {
    "t560-proxmox": "192.168.3.169/24",
    "r770-proxmox": "192.168.3.228/24",
    "r740-proxmox": "192.168.3.168/24",
    "5860-proxmox": "192.168.3.207/24",
    "dl380-proxmox": "192.168.3.170/24",
}.items():
    device = devices[name]
    interfaces[(name, "mgmt0")] = upsert_interface(device, "mgmt0", "virtual", "Management bridge/current vmbr0", mgmt_only=True)
    ip = upsert_ip(mgmt_ip, f"{name}.mgmt.lab.sounio", interfaces[(name, "mgmt0")])
    set_primary(device, "oob_ip", ip)

bridge_defs = [
    ("t560-proxmox", "underlay0", "bridge", "Current bridge vmbr100", 9000, "10.100.100.2/24", "t560.lab.sounio", True),
    ("t560-proxmox", "storage0", "bridge", "Current bridge vmbr200", 9000, "10.200.0.2/24", "t560-storage.lab.sounio", False),
    ("r770-proxmox", "underlay0", "bridge", "Current bridge vmbr2", 9000, "10.100.100.1/24", "r770.lab.sounio", True),
    ("r770-proxmox", "storage0", "bridge", "Current bridge vmbr1", 9000, "10.200.0.1/24", "r770-storage.lab.sounio", False),
    ("r770-proxmox", "gpufabric0", "bridge", "Current bridge vmbr210", 9000, "10.210.0.1/24", "r770-gpu.lab.sounio", False),
    ("r740-proxmox", "underlay0", "bridge", "Current bridge vmbr100", 9000, "10.100.100.4/24", "r740.lab.sounio", True),
    ("r740-proxmox", "storage0", "bridge", "Current bridge vmbr200", 9000, "10.200.0.4/24", "r740-storage.lab.sounio", False),
    ("r740-proxmox", "gpufabric0", "bridge", "Current bridge vmbr210", 9000, "10.210.0.4/24", "r740-gpu.lab.sounio", False),
    ("5860-proxmox", "underlay0", "bridge", "Current bridge vmbr100g", 9000, "10.100.100.3/24", "pve-5860.lab.sounio", True),
    ("5860-proxmox", "storage0", "bridge", "Current bridge vmbr200", 9000, "10.200.0.3/24", "pve-5860-storage.lab.sounio", False),
    ("5860-proxmox", "gpufabric0", "bridge", "Current bridge vmbr210", 9000, "10.210.0.3/24", "pve-5860-gpu.lab.sounio", False),
    ("5860-proxmox", "service0", "bridge", "Current bridge vmbr30", 9000, "10.30.0.1/24", "svc10g-gw.lab.sounio", False),
    ("dl380-proxmox", "underlay0", "bridge", "Planned Kubernetes underlay bridge", 9000, "10.100.100.5/24", "dl380.lab.sounio", True),
    ("dl380-proxmox", "storage0", "bridge", "Planned OrangeFS/storage bridge", 9000, "10.200.0.5/24", "dl380-storage.lab.sounio", False),
    ("dl380-proxmox", "gpufabric0", "bridge", "Planned GPU/RDMA fabric bridge", 9000, "10.210.0.5/24", "dl380-gpu.lab.sounio", False),
    ("dl380-proxmox", "service0", "bridge", "Optional planned service/egress bridge", 9000, "10.30.0.5/24", "dl380-service.lab.sounio", False),
]

for device_name, iface_name, iface_type, desc, mtu, address, dns_name, primary in bridge_defs:
    iface = upsert_interface(devices[device_name], iface_name, iface_type, desc, mtu=mtu)
    interfaces[(device_name, iface_name)] = iface
    ip = upsert_ip(address, dns_name, iface)
    if primary:
        set_primary(devices[device_name], "primary_ip4", ip)

switch_interfaces = [
    ("Management1", "1000base-t", "MGMT-LAN", 1500, True),
    ("Vlan130", "virtual", "SERVICE-FABRIC-10G", 9000, False),
    ("Ethernet1/1", "100gbase-x-qsfp28", "T560-100G (pve100g backbone)", 9214, False),
    ("Ethernet2/1", "100gbase-x-qsfp28", "R770-100G (pve100g backbone)", 9214, False),
    ("Ethernet3/1", "100gbase-x-qsfp28", "5860-proxmox 100G (ens5f0np0)", 9214, False),
    ("Ethernet5/1", "100gbase-x-qsfp28", "R740-100G", 9214, False),
    ("Ethernet29/1", "100gbase-x-qsfp28", "5860-proxmox GPU-FABRIC secondary 100G", 9214, False),
    ("Ethernet30/1", "100gbase-x-qsfp28", "t560-proxmox secondary 100G", 9214, False),
    ("Ethernet31/1", "100gbase-x-qsfp28", "r740-proxmox GPU-FABRIC secondary 100G", 9214, False),
    ("Ethernet32/1", "100gbase-x-qsfp28", "r770-proxmox GPU-FABRIC secondary 100G", 9214, False),
    ("Ethernet33", "10gbase-x-sfpp", "5860-proxmox SERVICE-FABRIC 10G", 9214, False),
    ("Ethernet34", "100gbase-x-qsfp28", "planned DL380 primary 100G uplink", 9214, False),
    ("Ethernet35", "100gbase-x-qsfp28", "planned DL380 GPU/storage 100G uplink", 9214, False),
]

for iface_name, iface_type, desc, mtu, mgmt_only in switch_interfaces:
    interfaces[("arista-7060", iface_name)] = upsert_interface(
        devices["arista-7060"], iface_name, iface_type, desc, mtu=mtu, mgmt_only=mgmt_only
    )

switch_mgmt = upsert_ip("192.168.3.229/24", "arista-7060.lab.sounio", interfaces[("arista-7060", "Management1")])
set_primary(devices["arista-7060"], "oob_ip", switch_mgmt)
switch_service = upsert_ip("10.30.0.254/24", "svc10g-sw.lab.sounio", interfaces[("arista-7060", "Vlan130")])

uplinks = [
    ("t560-proxmox", "uplink100g0", "100gbase-x-qsfp28", "Backs vmbr100 / 10.100.100.2", 9214),
    ("t560-proxmox", "uplink100g1", "100gbase-x-qsfp28", "Backs vmbr200 / 10.200.0.2", 9214),
    ("r770-proxmox", "uplink100g0", "100gbase-x-qsfp28", "Backs vmbr2 / 10.100.100.1", 9214),
    ("r770-proxmox", "uplink100g1", "100gbase-x-qsfp28", "Backs vmbr210 / 10.210.0.1 and vmbr1 / 10.200.0.1", 9214),
    ("r740-proxmox", "uplink100g0", "100gbase-x-qsfp28", "Backs vmbr100 / 10.100.100.4", 9214),
    ("r740-proxmox", "uplink100g1", "100gbase-x-qsfp28", "Backs vmbr210 / 10.210.0.4 and vmbr200 / 10.200.0.4", 9214),
    ("5860-proxmox", "uplink100g0", "100gbase-x-qsfp28", "Current host interface ens5f0np0 backing vmbr100g", 9214),
    ("5860-proxmox", "uplink100g1", "100gbase-x-qsfp28", "Current host interface ens5f1np1 backing vmbr210/vmbr200", 9214),
    ("5860-proxmox", "uplink10g0", "10gbase-t", "Current host interface nic0 backing vmbr30", 9214),
    ("dl380-proxmox", "uplink100g0", "100gbase-x-qsfp28", "Planned primary 100G uplink for underlay/service", 9214),
    ("dl380-proxmox", "uplink100g1", "100gbase-x-qsfp28", "Planned GPU/storage fabric 100G uplink", 9214),
]

for device_name, iface_name, iface_type, desc, mtu in uplinks:
    interfaces[(device_name, iface_name)] = upsert_interface(
        devices[device_name], iface_name, iface_type, desc, mtu=mtu
    )

cables = [
    ("link-arista-eth1-1-to-t560-uplink100g0", ("arista-7060", "Ethernet1/1"), ("t560-proxmox", "uplink100g0")),
    ("link-arista-eth2-1-to-r770-uplink100g0", ("arista-7060", "Ethernet2/1"), ("r770-proxmox", "uplink100g0")),
    ("link-arista-eth3-1-to-5860-uplink100g0", ("arista-7060", "Ethernet3/1"), ("5860-proxmox", "uplink100g0")),
    ("link-arista-eth5-1-to-r740-uplink100g0", ("arista-7060", "Ethernet5/1"), ("r740-proxmox", "uplink100g0")),
    ("link-arista-eth29-1-to-5860-uplink100g1", ("arista-7060", "Ethernet29/1"), ("5860-proxmox", "uplink100g1")),
    ("link-arista-eth30-1-to-t560-uplink100g1", ("arista-7060", "Ethernet30/1"), ("t560-proxmox", "uplink100g1")),
    ("link-arista-eth31-1-to-r740-uplink100g1", ("arista-7060", "Ethernet31/1"), ("r740-proxmox", "uplink100g1")),
    ("link-arista-eth32-1-to-r770-uplink100g1", ("arista-7060", "Ethernet32/1"), ("r770-proxmox", "uplink100g1")),
    ("link-arista-eth33-to-5860-uplink10g0", ("arista-7060", "Ethernet33"), ("5860-proxmox", "uplink10g0")),
    ("planned-link-arista-eth34-to-dl380-uplink100g0", ("arista-7060", "Ethernet34"), ("dl380-proxmox", "uplink100g0")),
    ("planned-link-arista-eth35-to-dl380-uplink100g1", ("arista-7060", "Ethernet35"), ("dl380-proxmox", "uplink100g1")),
]

for label, a_key, b_key in cables:
    upsert_cable(label, interfaces[a_key], interfaces[b_key])

print("NetBox lab devices/interfaces/cables seed complete")
