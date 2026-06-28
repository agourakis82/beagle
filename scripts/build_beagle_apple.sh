#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_ROOT="${ROOT}/beagle-ios"
PROJECT="${IOS_ROOT}/BeagleSuite.xcodeproj"

if [[ ! -d "${PROJECT}" ]]; then
  echo "Missing ${PROJECT}" >&2
  exit 1
fi

if command -v xcodegen >/dev/null 2>&1; then
  (cd "${IOS_ROOT}" && xcodegen generate --spec project.yml)
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is not available on this machine; run this script on a Mac with Xcode." >&2
  exit 1
fi

CONFIGURATION="${CONFIGURATION:-Debug}"
APPLE_SIM_ARCH="${APPLE_SIM_ARCH:-$(uname -m)}"
XCODE_JOBS="${XCODE_JOBS:-1}"

build_scheme() {
  local scheme="$1"
  local sdk="$2"
  shift 2
  echo "==> Building ${scheme} (${sdk})"
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${scheme}" \
    -configuration "${CONFIGURATION}" \
    -sdk "${sdk}" \
    -jobs "${XCODE_JOBS}" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES \
    ARCHS="${APPLE_SIM_ARCH}" \
    SWIFT_ENABLE_EXPLICIT_MODULES=NO \
    "$@" \
    build
}

build_scheme BeagleCockpit iphonesimulator
build_scheme BeagleVisionOS xrsimulator
build_scheme BeagleWatch watchsimulator

echo "Apple build spine passed."
