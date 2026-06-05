# Beagle Workbench (reset)

Native SwiftUI Mac app. **No mock data at startup.**

## Run on Mac

```bash
cd beagle-ios/BeagleSuite
./build-workbench-on-mac.sh   # from Mac, pulls from t560
BEAGLE_COCKPIT_URL=http://127.0.0.1:4370 swift run BeagleWorkbench
```

## Live bridge (Mac ← t560 Cockpit)

```bash
# on t560
./start-workbench-live-bridge.sh
./status-workbench-live-bridge.sh
```

## Doctor (Phase 1 gate)

```bash
./doctor-beagle-workbench.sh
CHECK_MAC=0 ./doctor-beagle-workbench.sh   # t560 only
```

See [../ARCHITECTURE.md](../ARCHITECTURE.md#phase-1-gate-dev-foundation).

## What you should see

- **Connected:** project list from Cockpit, workspace status, zellij tab names as idle agents
- **Disconnected:** orange banner, empty projects/tabs, explicit error — not fake data

## What is not wired yet

- Composer → zellij / multimodel
- Exocortex Φ panel
- GraphRAG / memory inspector
- Lease enforcement

See [../ARCHITECTURE.md](../ARCHITECTURE.md).
