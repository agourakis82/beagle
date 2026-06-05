# Beagle.app (macOS)

Phase 2 deliverable: installable Mac app wrapping the `BeagleWorkbench` SPM executable.

## Build on Mac

```bash
# from Mac — pull from t560 and install to ~/Applications
./sync-and-build-beagle-mac.sh

# or local tree already present
cd ../BeagleSuite
../Beagle/bundle-beagle-app.sh INSTALL=1
```

## Signing (Apple Developer)

```bash
export CODESIGN_ID="Apple Development: Your Name (TEAMID)"
INSTALL=1 ../Beagle/bundle-beagle-app.sh
```

## Bundle ID

`dev.sounio.beagle` — see [Info.plist](Info.plist).

## Xcode

Open [`../BeagleSuite/Package.swift`](../BeagleSuite/Package.swift) in Xcode for debugging.
This folder provides the `.app` bundle wrapper for daily double-click use.
