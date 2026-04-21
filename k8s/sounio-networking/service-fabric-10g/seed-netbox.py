#!/usr/bin/env python3
import json
import os
import sys
from urllib import request, error

BASE = os.environ.get("NETBOX_URL", "http://192.168.3.207:8080").rstrip("/")
TOKEN = (
    os.environ.get("NETBOX_TOKEN")
    or os.environ.get("NETBOX_API_TOKEN_V2")
    or os.environ.get("NETBOX_API_TOKEN")
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
    "Content-Type": "application/json",
    "Accept": "application/json",
}


def api(method, path, payload=None):
    body = None if payload is None else json.dumps(payload).encode()
    req = request.Request(f"{BASE}{path}", data=body, headers=HEADERS, method=method)
    try:
        with request.urlopen(req) as resp:
            data = resp.read()
            return json.loads(data.decode()) if data else {}
    except error.HTTPError as exc:
        detail = exc.read().decode()
        raise SystemExit(f"{method} {path} failed: {exc.code} {detail}")


def get_or_create(path, unique_key, payload):
    existing = api("GET", f"{path}?{unique_key}={payload[unique_key]}")
    if existing.get("count"):
      return existing["results"][0]
    return api("POST", path, payload)


def main():
    site = get_or_create("/api/dcim/sites/", "slug", {"name": "Sounio Lab", "slug": "sounio-lab"})

    vlan_group = get_or_create(
        "/api/ipam/vlan-groups/",
        "slug",
        {"name": "Sounio Fabrics", "slug": "sounio-fabrics", "scope_type": "dcim.site", "scope_id": site["id"]},
    )

    vlans = {
        100: ("k8s-underlay", "active"),
        130: ("service-egress-10g", "active"),
        200: ("storage-migration", "active"),
        210: ("gpu-rdma", "active"),
    }
    vlan_ids = {}
    for vid, (name, status) in vlans.items():
        vlan = get_or_create(
            "/api/ipam/vlans/",
            "vid",
            {
                "site": site["id"],
                "group": vlan_group["id"],
                "vid": vid,
                "name": name,
                "status": status,
            },
        )
        vlan_ids[vid] = vlan["id"]

    prefixes = [
        ("10.100.100.0/24", "k8s-underlay", 100, True),
        ("10.200.0.0/24", "storage-migration", 200, True),
        ("10.210.0.0/24", "gpu-rdma", 210, True),
        ("10.30.0.0/24", "service-egress-10g", 130, True),
        ("192.168.3.0/24", "management", None, True),
    ]
    for cidr, desc, vid, is_pool in prefixes:
        payload = {
            "prefix": cidr,
            "site": site["id"],
            "status": "active",
            "description": desc,
            "is_pool": is_pool,
        }
        if vid is not None:
            payload["vlan"] = vlan_ids[vid]
        get_or_create("/api/ipam/prefixes/", "prefix", payload)

    print("NetBox seed complete.")


if __name__ == "__main__":
    main()
