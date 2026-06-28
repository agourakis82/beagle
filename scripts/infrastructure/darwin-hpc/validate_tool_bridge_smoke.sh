#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/tool-bridge-smoke}"

required=(
  health.json
  providers.json
  execute-human.json
  ledger-tail.jsonl
)

for file in "${required[@]}"; do
  [[ -f "${OUT}/${file}" ]] || {
    echo "[FAIL] missing ${file}" >&2
    exit 1
  }
done

python3 - <<'PY' "${OUT}"
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
health = json.loads((out / "health.json").read_text(encoding="utf-8"))
providers = json.loads((out / "providers.json").read_text(encoding="utf-8"))
human = json.loads((out / "execute-human.json").read_text(encoding="utf-8"))
ledger_lines = [line for line in (out / "ledger-tail.jsonl").read_text(encoding="utf-8").splitlines() if line.strip()]

if health.get("status") != "ok":
    raise SystemExit("health.status is not ok")

provider_names = {provider["provider"] for provider in providers}
expected = {"deepseek", "glm5", "grok_fast", "minimax", "codex_human", "claude_human", "mcp_generic"}
missing = sorted(expected - provider_names)
if missing:
    raise SystemExit(f"missing providers: {', '.join(missing)}")

if human.get("status") != "deferred":
    raise SystemExit(f"expected deferred human bridge status, got {human.get('status')}")

if not any("b122b-human-smoke" in line for line in ledger_lines):
    raise SystemExit("ledger does not contain the human smoke request")

cheap_path = out / "execute-cheap.json"
if cheap_path.exists():
    cheap = json.loads(cheap_path.read_text(encoding="utf-8"))
    if cheap.get("status") != "success":
        raise SystemExit(f"cheap provider execution did not succeed: {cheap.get('status')}")
    print("[OK] tool bridge smoke passed with real cheap provider execution")
else:
    print("[OK] tool bridge foundation validated; real cheap provider execution still blocked by missing provider secret")
PY
