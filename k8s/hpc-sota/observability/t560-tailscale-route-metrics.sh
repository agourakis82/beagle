#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile}"
OUT_FILE="${OUT_DIR}/tailscale_route.prom"
PROBE_IP="${PROBE_IP:-192.168.3.228}"

mkdir -p "${OUT_DIR}"

route_all="$(tailscale debug prefs 2>/dev/null | sed -n 's/.*"RouteAll": \(true\|false\).*/\1/p' | head -n1 || true)"
if [[ "${route_all}" == "true" ]]; then
  route_all_value=1
else
  route_all_value=0
fi

if ip route show table 52 2>/dev/null | grep -q '^192\.168\.3\.0/24 '; then
  overlap_value=1
else
  overlap_value=0
fi

route_probe="$(ip route get "${PROBE_IP}" 2>/dev/null | tr -s ' ' || true)"
if [[ "${route_probe}" == *" dev vmbr0 "* && "${route_probe}" == *" src 192.168.3.169 "* ]]; then
  vmbr0_value=1
else
  vmbr0_value=0
fi

healthy_value=1
if [[ "${route_all_value}" -ne 0 || "${overlap_value}" -ne 0 || "${vmbr0_value}" -ne 1 ]]; then
  healthy_value=0
fi

tmp="$(mktemp "${OUT_FILE}.XXXXXX")"
cat > "${tmp}" <<EOF
# HELP darwin_tailscale_routeall_enabled Whether t560 is accepting Tailscale subnet routes.
# TYPE darwin_tailscale_routeall_enabled gauge
darwin_tailscale_routeall_enabled ${route_all_value}
# HELP darwin_tailscale_overlapping_subnet_imported Whether t560 is importing the management LAN subnet through Tailscale table 52.
# TYPE darwin_tailscale_overlapping_subnet_imported gauge
darwin_tailscale_overlapping_subnet_imported{cidr="192.168.3.0/24"} ${overlap_value}
# HELP darwin_tailscale_management_route_via_vmbr0 Whether traffic to the management LAN returns through vmbr0 as expected.
# TYPE darwin_tailscale_management_route_via_vmbr0 gauge
darwin_tailscale_management_route_via_vmbr0{probe_ip="${PROBE_IP}"} ${vmbr0_value}
# HELP darwin_tailscale_route_doctor_healthy Aggregate route-health status for t560 management/Tailscale interaction.
# TYPE darwin_tailscale_route_doctor_healthy gauge
darwin_tailscale_route_doctor_healthy ${healthy_value}
EOF

mv "${tmp}" "${OUT_FILE}"
chmod 0644 "${OUT_FILE}"
