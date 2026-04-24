#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

preset="${1:-}"

if [[ -z "$preset" ]]; then
  echo "Usage: scripts/infrastructure/beagle/scoped-stage.sh <preset>" >&2
  exit 1
fi

case "$preset" in
  ios-icons)
    path_array=(
      "beagle-ios/Assets.xcassets/AppIcon.appiconset"
      "beagle-ios/Assets.xcassets/BeagleWatchAppIcon.appiconset"
    )
    ;;
  ios-new-shell)
    path_array=(
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/BuildInfo.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/CognitiveBridgeField.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/PresencePill.swift"
    )
    ;;
  ios-diagnostics)
    path_array=(
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/DiagnosticsRunner.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/DiagnosticsView.swift"
    )
    ;;
  ios-terminal)
    path_array=(
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/AgentSessionView.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/TerminalContentView.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/BeagleCockpitApp.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCore/Models.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCore/Theme.swift"
    )
    ;;
  ios-soul)
    path_array=(
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/BeagleCockpitApp.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/HomeView.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/PlatformView.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/AgentSessionView.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/TerminalContentView.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCore/Theme.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCore/Models.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/BuildInfo.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/CognitiveBridgeField.swift"
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit/PresencePill.swift"
    )
    ;;
  ios-shell)
    path_array=(
      "beagle-ios/BeagleSuite/Sources/BeagleCockpit"
      "beagle-ios/BeagleSuite/Sources/BeagleCore"
      "beagle-ios/Assets.xcassets"
      "beagle-ios/BeagleCockpit-Info.plist"
      "beagle-ios/BeagleSuite/Package.swift"
      "beagle-ios/project.yml"
    )
    ;;
  cockpit-runtime)
    path_array=(
      "apps/project-cockpit/server/index.mjs"
      "apps/project-cockpit/server/agent-routes.mjs"
      "k8s/project-cockpit/server-runtime-configmap.yaml"
    )
    ;;
  *)
    echo "Unknown preset: $preset" >&2
    exit 1
    ;;
esac

git add -- "${path_array[@]}"
