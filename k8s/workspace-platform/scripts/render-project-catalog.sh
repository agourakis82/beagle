#!/usr/bin/env bash
set -euo pipefail

validate_live=false

usage() {
  echo "usage: $0 [--validate-live] <catalog-dir> <output-dir>" >&2
}

if [[ "${1:-}" == "--validate-live" ]]; then
  validate_live=true
  shift
fi

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

catalog_dir="$1"
output_dir="$2"
renderer="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/render-project-workspace.sh"

if [[ ! -d "$catalog_dir" ]]; then
  echo "catalog dir not found: $catalog_dir" >&2
  exit 1
fi

mkdir -p "$output_dir"

shopt -s nullglob
count=0
for mode in always-on warm cold; do
  mode_dir="${catalog_dir}/${mode}"
  [[ -d "$mode_dir" ]] || continue
  for env_file in "${mode_dir}"/*.env; do
    base="$(basename "$env_file" .env)"
    out_file="${output_dir}/${base}.yaml"
    if $validate_live; then
      "${renderer}" --validate-live "$env_file" >"$out_file"
    else
      "${renderer}" "$env_file" >"$out_file"
    fi
    echo "rendered ${env_file} -> ${out_file}"
    count=$((count + 1))
  done
done

echo "rendered ${count} workspace manifests into ${output_dir}"
