#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[full-shell] public surfaces"
"${script_dir}/check_project_cockpit_public_surfaces.sh"

echo
echo "[full-shell] public assets"
"${script_dir}/check_project_cockpit_public_assets.sh"

echo
echo "[full-shell] showcase route semantics"
"${script_dir}/check_project_cockpit_showcase_route_semantics.sh"

echo
echo "[full-shell] private inference"
"${script_dir}/check_project_cockpit_private_inference.sh"

echo
echo "[full-shell] tailnet VIP sanity"
"${script_dir}/check_sounio_tailnet_vips.sh"
