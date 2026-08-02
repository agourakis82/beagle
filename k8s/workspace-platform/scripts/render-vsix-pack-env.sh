#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <pack-file.json>" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

pack_file="$1"

if [[ ! -f "${pack_file}" ]]; then
  echo "pack file not found: ${pack_file}" >&2
  exit 1
fi

python3 - "$pack_file" <<'PY'
import json
import pathlib
import shlex
import sys

pack_path = pathlib.Path(sys.argv[1]).resolve()
root = pack_path.parent

seen = set()

def load_pack(path: pathlib.Path):
    data = json.loads(path.read_text())
    parent_name = data.get("extends")
    merged = {"required": [], "recommended": [], "experimental": [], "aiIdeAgents": []}
    if parent_name:
        parent_path = root / f"{parent_name}.project-vsix-pack.json"
        parent = load_pack(parent_path)
        for key in merged:
            merged[key].extend(parent.get(key, []))
    for key in ("required", "recommended", "experimental"):
        merged[key].extend(data.get(key, []))
        dedup = []
        local_seen = set()
        for item in merged[key]:
            if item not in local_seen:
                dedup.append(item)
                local_seen.add(item)
        merged[key] = dedup
    merged["aiIdeAgents"].extend(data.get("aiIdeAgents", []))
    dedup_agents = []
    seen_agents = set()
    for agent in merged["aiIdeAgents"]:
        name = agent.get("name")
        if not name or name in seen_agents:
            continue
        dedup_agents.append(agent)
        seen_agents.add(name)
    merged["aiIdeAgents"] = dedup_agents
    merged["projectSlug"] = data.get("projectSlug", path.stem)
    merged["packVersion"] = data.get("packVersion", "unversioned")
    return merged

pack = load_pack(pack_path)

def emit(key, value):
    print(f"{key}={value}")

emit("PROJECT_VSIX_PACK", pack["projectSlug"])
emit("PROJECT_VSIX_PACK_VERSION", pack["packVersion"])
emit("PROJECT_VSIX_REQUIRED_EXTENSIONS", ",".join(pack["required"]))
emit("PROJECT_VSIX_RECOMMENDED_EXTENSIONS", ",".join(pack["recommended"]))
emit("PROJECT_VSIX_EXPERIMENTAL_EXTENSIONS", ",".join(pack["experimental"]))
emit("PROJECT_AI_IDE_AGENTS", shlex.quote(json.dumps(pack["aiIdeAgents"], separators=(",", ":"))))
PY
