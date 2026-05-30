#!/usr/bin/env bash
# Wrap BeagleWorkbench SPM binary in Beagle.app (Phase 2).
set -euo pipefail

SUITE_DIR="${SUITE_DIR:-$(cd "$(dirname "$0")/../BeagleSuite" && pwd)}"
BUILD_CONFIG="${BUILD_CONFIG:-debug}"
APP_NAME="${APP_NAME:-Beagle.app}"
INSTALL="${INSTALL:-0}"
CODESIGN_ID="${CODESIGN_ID:-}"

cd "${SUITE_DIR}"
swift build --product BeagleWorkbench -c "${BUILD_CONFIG}"

BIN=".build/${BUILD_CONFIG}/BeagleWorkbench"
if [[ ! -x "${BIN}" ]]; then
  echo "missing binary: ${BIN}" >&2
  exit 1
fi

APP_DIR="${SUITE_DIR}/${APP_NAME}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
cp "$(dirname "$0")/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${BIN}" "${APP_DIR}/Contents/MacOS/Beagle"
chmod +x "${APP_DIR}/Contents/MacOS/Beagle"

if [[ -n "${CODESIGN_ID}" ]]; then
  codesign --force --sign "${CODESIGN_ID}" --options runtime "${APP_DIR}"
elif codesign -s - --force "${APP_DIR}" 2>/dev/null; then
  echo "ad-hoc signed ${APP_NAME}"
else
  echo "warning: codesign skipped"
fi

echo "OK: ${APP_DIR}"
if [[ "${INSTALL}" == "1" ]]; then
  dest="${HOME}/Applications/${APP_NAME}"
  rm -rf "${dest}"
  cp -R "${APP_DIR}" "${dest}"
  echo "Installed: ${dest}"
fi
