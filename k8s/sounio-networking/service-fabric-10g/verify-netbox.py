#!/usr/bin/env python3
import json
import os
import sys
from urllib import request


BASE = os.environ.get("NETBOX_URL", "http://192.168.3.207:8080").rstrip("/")
TOKEN = (
    os.environ.get("NETBOX_TOKEN")
    or os.environ.get("NETBOX_API_TOKEN")
    or os.environ.get("NETBOX_API_TOKEN_V2")
)
if not TOKEN:
    raise SystemExit("Set NETBOX_TOKEN, NETBOX_API_TOKEN, or NETBOX_API_TOKEN_V2")

if TOKEN.startswith("Bearer ") or TOKEN.startswith("Token "):
    auth_header = TOKEN
elif TOKEN.startswith("nbt_"):
    auth_header = f"Bearer {TOKEN}"
else:
    auth_header = f"Token {TOKEN}"

HEADERS = {
    "Authorization": auth_header,
    "Accept": "application/json",
}


def api(path):
    req = request.Request(f"{BASE}{path}", headers=HEADERS)
    with request.urlopen(req) as resp:
        return json.loads(resp.read().decode())


def main():
    site = api("/api/dcim/sites/?slug=sounio-lab")
    vlans = api("/api/ipam/vlans/?group=sounio-fabrics")
    prefixes = api("/api/ipam/prefixes/?limit=100")
    devices = api("/api/dcim/devices/?site=sounio-lab&limit=100")
    cables = api("/api/dcim/cables/?limit=100")

    wanted_prefixes = {
        "10.100.100.0/24",
        "10.200.0.0/24",
        "10.210.0.0/24",
        "10.30.0.0/24",
        "192.168.3.0/24",
    }
    wanted_devices = {
        "t560-proxmox",
        "r770-proxmox",
        "r740-proxmox",
        "5860-proxmox",
        "arista-7060",
    }
    have_prefixes = {item["prefix"] for item in prefixes.get("results", [])}
    have_devices = {item["name"] for item in devices.get("results", [])}
    missing = sorted(wanted_prefixes - have_prefixes)
    missing_devices = sorted(wanted_devices - have_devices)

    print(f"site_count={site.get('count', 0)}")
    print(f"vlan_count={vlans.get('count', 0)}")
    print(f"prefix_count={prefixes.get('count', 0)}")
    print(f"device_count={devices.get('count', 0)}")
    print(f"cable_count={cables.get('count', 0)}")
    print("prefixes=" + ",".join(sorted(have_prefixes & wanted_prefixes)))
    print("devices=" + ",".join(sorted(have_devices & wanted_devices)))
    if missing:
        print("missing_prefixes=" + ",".join(missing), file=sys.stderr)
        raise SystemExit(1)
    if missing_devices:
        print("missing_devices=" + ",".join(missing_devices), file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
