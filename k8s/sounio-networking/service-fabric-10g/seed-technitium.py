#!/usr/bin/env python3
import argparse
import json
import pathlib
import sys
from urllib.parse import urlencode
from urllib.request import urlopen

import yaml


def get_json(url: str):
    with urlopen(url, timeout=15) as resp:
        return json.loads(resp.read().decode())


def login(base_url: str, password: str) -> str:
    payload = get_json(
        f"{base_url}/api/user/login?{urlencode({'user': 'admin', 'pass': password, 'includeInfo': 'true'})}"
    )
    if payload.get("status") != "ok":
        raise RuntimeError(payload)
    return payload["token"]


def ensure_zone(base_url: str, token: str, zone: str):
    payload = get_json(
        f"{base_url}/api/zones/create?{urlencode({'token': token, 'zone': zone, 'type': 'Primary'})}"
    )
    if payload.get("status") not in {"ok", "error"}:
        raise RuntimeError(payload)
    if payload.get("status") == "error" and "exist" not in str(payload).lower():
        raise RuntimeError(payload)


def add_record(base_url: str, token: str, zone: str, domain: str, ip: str):
    payload = get_json(
        f"{base_url}/api/zones/records/add?{urlencode({'token': token, 'zone': zone, 'domain': domain, 'type': 'A', 'ipAddress': ip, 'overwrite': 'true'})}"
    )
    if payload.get("status") != "ok":
        raise RuntimeError(payload)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--url", default="http://10.30.0.1:5380")
    parser.add_argument("--password", required=True)
    args = parser.parse_args()

    with pathlib.Path(args.inventory).open("r", encoding="utf-8") as fh:
        inventory = yaml.safe_load(fh)

    zone = inventory["dns"]["lab_zone"]
    token = login(args.url.rstrip("/"), args.password)
    ensure_zone(args.url.rstrip("/"), token, zone)
    for record in inventory["dns"]["records"]:
        domain = record["name"]
        ip = record["ip"]
        if not domain.endswith(zone):
            continue
        add_record(args.url.rstrip("/"), token, zone, domain, ip)
        print(f"seeded {domain} -> {ip}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
