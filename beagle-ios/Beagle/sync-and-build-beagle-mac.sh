#!/usr/bin/env bash
# Pull BeagleSuite from t560, build, and produce Beagle.app on the Mac.
set -euo pipefail

SOURCE_HOST="${SOURCE_HOST:-devsounio@t560-proxmox.tail21cbc4.ts.net}"
REMOTE_ROOT="/home/devsounio/beagle/beagle-ios"
DEST_ROOT="${DEST_ROOT:-$HOME/dev/beagle-native-apple}"
INSTALL="${INSTALL:-1}"

printf '==> sync beagle-ios from %s\n' "${SOURCE_HOST}"
mkdir -p "${DEST_ROOT}"
rsync -az --delete \
  --exclude 'BeagleSuite/.build/' \
  --exclude 'BeagleSuite/.swiftpm/' \
  "${SOURCE_HOST}:${REMOTE_ROOT}/" \
  "${DEST_ROOT}/"

printf '==> build Beagle.app\n'
INSTALL="${INSTALL}" "${DEST_ROOT}/Beagle/bundle-beagle-app.sh"

printf '\nPhase 2 gate: open ~/Applications/Beagle.app (or BeagleSuite/Beagle.app)\n'
printf 'Set BEAGLE_COCKPIT_URL=http://127.0.0.1:4370 before launch if needed.\n'
