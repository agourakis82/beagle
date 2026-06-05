#!/usr/bin/env bash
set -euo pipefail

SOURCE_HOST="${SOURCE_HOST:-devsounio@t560-proxmox.tail21cbc4.ts.net}"
DEST_ROOT="${DEST_ROOT:-$HOME/dev/beagle-workbench-ssh}"
REMOTE_SUITE="/home/devsounio/beagle/beagle-ios/BeagleSuite"

printf '==> checking Mac toolchain\n'
command -v swift >/dev/null || { echo 'swift not found on this Mac'; exit 1; }
if command -v xcodebuild >/dev/null; then
  xcodebuild -version || true
fi
sw_vers || true

printf '==> checking SSH pull from %s\n' "$SOURCE_HOST"
ssh -o BatchMode=yes -o ConnectTimeout=8 "$SOURCE_HOST" 'test -d /home/devsounio/beagle/beagle-ios/BeagleSuite && echo ok'

printf '==> syncing BeagleSuite to %s\n' "$DEST_ROOT"
mkdir -p "$DEST_ROOT"
rsync -az --delete \
  --exclude '.build/' \
  --exclude '.swiftpm/' \
  "$SOURCE_HOST:$REMOTE_SUITE/" \
  "$DEST_ROOT/"

printf '==> describing package\n'
cd "$DEST_ROOT"
swift package describe --type json >/tmp/beagle-workbench-package.json
python3 - <<'PY'
import json
p=json.load(open('/tmp/beagle-workbench-package.json'))
print('products:', ', '.join(x['name'] for x in p['products']))
for t in p['targets']:
    if t['name']=='BeagleWorkbench':
        print('BeagleWorkbench sources:', ', '.join(t.get('sources', [])))
PY

printf '==> building BeagleWorkbench\n'
swift build --product BeagleWorkbench

printf '\nOK: BeagleWorkbench built at %s\n' "$DEST_ROOT"
printf 'Run it with:\n  cd %q && swift run BeagleWorkbench\n' "$DEST_ROOT"
