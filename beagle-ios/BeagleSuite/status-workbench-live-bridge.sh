#!/usr/bin/env bash
set -euo pipefail

COCKPIT_PORT="${COCKPIT_PORT:-4370}"
MAC_SSH="${MAC_SSH:-demetriosagourakis@macbook-pro-de-demetrios-2.tail21cbc4.ts.net}"

systemctl --user --no-pager --plain status project-cockpit-api.service beagle-workbench-cockpit-tunnel.service || true

echo
echo "t560 local readback:"
curl -fsS --max-time 20 "http://127.0.0.1:${COCKPIT_PORT}/api/cluster/ops/summary" \
  | jq '{status, generatedAt, nodes: .lanes.kubernetes.counts, slurm: .lanes.slurm.status, orangefs: {risk: .lanes.orangefs.risk, thinPoolPct: .lanes.orangefs.thinPoolPct}, risks: [.risks[].code]}' \
  || true

echo
echo "t560 Sounio workspace readback:"
curl -fsS --max-time 20 "http://127.0.0.1:${COCKPIT_PORT}/api/projects/sounio/go-work-now?depth=deep" \
  | jq '{status: .goWorkNow.workspaceState.status, node: .goWorkNow.workspaceState.nodeName, pod: .goWorkNow.workspaceState.podName, session: .project.zellijSession, tabs: .project.zellijTabs}' \
  || true

echo
echo "Mac localhost readback:"
ssh -o BatchMode=yes -o ConnectTimeout=8 "${MAC_SSH}" \
  "curl -fsS --max-time 20 http://127.0.0.1:${COCKPIT_PORT}/api/cluster/ops/summary" \
  | jq '{status, generatedAt, nodes: .lanes.kubernetes.counts, slurm: .lanes.slurm.status, orangefs: {risk: .lanes.orangefs.risk, thinPoolPct: .lanes.orangefs.thinPoolPct}, risks: [.risks[].code]}' \
  || true

echo
echo "Mac Sounio workspace readback:"
ssh -o BatchMode=yes -o ConnectTimeout=8 "${MAC_SSH}" \
  "curl -fsS --max-time 20 'http://127.0.0.1:${COCKPIT_PORT}/api/projects/sounio/go-work-now?depth=deep'" \
  | jq '{status: .goWorkNow.workspaceState.status, node: .goWorkNow.workspaceState.nodeName, pod: .goWorkNow.workspaceState.podName, session: .project.zellijSession, tabs: .project.zellijTabs}' \
  || true
