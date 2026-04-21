from dcim.models import Site
from ipam.models import Prefix, VLAN, VLANGroup


site, created = Site.objects.get_or_create(
    slug="sounio-lab",
    defaults={"name": "Sounio Lab"},
)
print(("created" if created else "existing"), "site", site.slug)

vlan_group = VLANGroup.objects.filter(slug="sounio-fabrics").first()
if not vlan_group:
    vlan_group = VLANGroup(name="Sounio Fabrics", slug="sounio-fabrics")
vlan_group.scope = site
vlan_group.save()
print("vlan-group", vlan_group.slug)

vlans = {
    100: "k8s-underlay",
    130: "service-egress-10g",
    200: "storage-migration",
    210: "gpu-rdma",
}

vlan_map = {}
for vid, name in vlans.items():
    vlan = VLAN.objects.filter(group=vlan_group, vid=vid).first()
    if not vlan:
        vlan = VLAN(site=site, group=vlan_group, vid=vid, name=name, status="active")
        vlan.save()
        print("created vlan", vid)
    else:
        changed = False
        if vlan.site_id != site.id:
            vlan.site = site
            changed = True
        if vlan.group_id != vlan_group.id:
            vlan.group = vlan_group
            changed = True
        if vlan.name != name:
            vlan.name = name
            changed = True
        if str(vlan.status) != "active":
            vlan.status = "active"
            changed = True
        if changed:
            vlan.save()
            print("updated vlan", vid)
        else:
            print("existing vlan", vid)
    vlan_map[vid] = vlan

prefixes = [
    ("10.100.100.0/24", "k8s-underlay", 100, True),
    ("10.200.0.0/24", "storage-migration", 200, True),
    ("10.210.0.0/24", "gpu-rdma", 210, True),
    ("10.30.0.0/24", "service-egress-10g", 130, True),
    ("192.168.3.0/24", "management", None, True),
]

for cidr, desc, vid, is_pool in prefixes:
    prefix = Prefix.objects.filter(prefix=cidr).first()
    if not prefix:
        prefix = Prefix(prefix=cidr, description=desc, status="active", is_pool=is_pool)
        prefix.scope = site
        if vid is not None:
            prefix.vlan = vlan_map[vid]
        prefix.save()
        print("created prefix", cidr)
    else:
        changed = False
        if prefix.description != desc:
            prefix.description = desc
            changed = True
        if str(prefix.status) != "active":
            prefix.status = "active"
            changed = True
        if bool(prefix.is_pool) != bool(is_pool):
            prefix.is_pool = is_pool
            changed = True
        prefix.scope = site
        if vid is not None and prefix.vlan_id != vlan_map[vid].id:
            prefix.vlan = vlan_map[vid]
            changed = True
        if vid is None and prefix.vlan_id is not None:
            prefix.vlan = None
            changed = True
        if changed:
            prefix.save()
            print("updated prefix", cidr)
        else:
            print("existing prefix", cidr)

print("NetBox ORM seed complete")
