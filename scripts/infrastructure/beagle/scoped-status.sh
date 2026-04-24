#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

preset="${1:-ios-shell}"

paths_for_preset() {
  case "$1" in
    ios-icons)
      cat <<'EOF'
beagle-ios/Assets.xcassets/AppIcon.appiconset
beagle-ios/Assets.xcassets/BeagleWatchAppIcon.appiconset
EOF
      ;;
    ios-new-shell)
      cat <<'EOF'
beagle-ios/BeagleSuite/Sources/BeagleCockpit/BuildInfo.swift
beagle-ios/BeagleSuite/Sources/BeagleCockpit/CognitiveBridgeField.swift
beagle-ios/BeagleSuite/Sources/BeagleCockpit/PresencePill.swift
EOF
      ;;
    ios-diagnostics)
      cat <<'EOF'
beagle-ios/BeagleSuite/Sources/BeagleCockpit/DiagnosticsRunner.swift
beagle-ios/BeagleSuite/Sources/BeagleCockpit/DiagnosticsView.swift
EOF
      ;;
    ios-terminal)
      cat <<'EOF'
beagle-ios/BeagleSuite/Sources/BeagleCockpit/AgentSessionView.swift
beagle-ios/BeagleSuite/Sources/BeagleCockpit/TerminalContentView.swift
beagle-ios/BeagleSuite/Sources/BeagleCockpit/BeagleCockpitApp.swift
beagle-ios/BeagleSuite/Sources/BeagleCore/Models.swift
beagle-ios/BeagleSuite/Sources/BeagleCore/Theme.swift
EOF
      ;;
    ios-soul)
      cat <<'EOF'
beagle-ios/BeagleSuite/Sources/BeagleCockpit/BeagleCockpitApp.swift
beagle-ios/BeagleSuite/Sources/BeagleCockpit/HomeView.swift
beagle-ios/BeagleSuite/Sources/BeagleCockpit/PlatformView.swift
beagle-ios/BeagleSuite/Sources/BeagleCockpit/AgentSessionView.swift
beagle-ios/BeagleSuite/Sources/BeagleCockpit/TerminalContentView.swift
beagle-ios/BeagleSuite/Sources/BeagleCore/Theme.swift
beagle-ios/BeagleSuite/Sources/BeagleCore/Models.swift
beagle-ios/BeagleSuite/Sources/BeagleCockpit/BuildInfo.swift
beagle-ios/BeagleSuite/Sources/BeagleCockpit/CognitiveBridgeField.swift
beagle-ios/BeagleSuite/Sources/BeagleCockpit/PresencePill.swift
EOF
      ;;
    ios-shell)
      cat <<'EOF'
beagle-ios/BeagleSuite/Sources/BeagleCockpit
beagle-ios/BeagleSuite/Sources/BeagleCore
beagle-ios/Assets.xcassets
beagle-ios/BeagleCockpit-Info.plist
beagle-ios/BeagleSuite/Package.swift
beagle-ios/project.yml
EOF
      ;;
    cockpit-runtime)
      cat <<'EOF'
apps/project-cockpit/server/index.mjs
apps/project-cockpit/server/agent-routes.mjs
k8s/project-cockpit/server-runtime-configmap.yaml
EOF
      ;;
    *)
      return 1
      ;;
  esac
}

print_usage() {
  cat <<'EOF'
Usage: scripts/infrastructure/beagle/scoped-status.sh [preset]

Presets:
  ios-icons         App icon and watch icon asset migration
  ios-new-shell     New shell-support source files
  ios-diagnostics   Diagnostics feature source files
  ios-terminal      Terminal/session focused files
  ios-soul          Living-shell visual pass files
  ios-shell         Broad iOS app shell and design-system changes
  cockpit-runtime   Cockpit backend/runtime files
EOF
}

if ! paths="$(paths_for_preset "$preset")"; then
  print_usage
  exit 1
fi

mapfile -t path_array <<<"$paths"
git status --short -- "${path_array[@]}"
