# BeagleCockpit for Windows

Native **WinUI 3 / .NET 9** cockpit client. The 4th client (after Apple/Web) over the ONE cluster
contract: the P0 `/pty/<agent>` WebSocket gateway + coord/memory HTTP APIs. First feature: **Fleet
Terminals**. Mirrors the Apple client (`/home/devsounio/beagle/beagle-ios`).

- **Design:** `darwin-cluster/docs/superpowers/specs/2026-06-08-cockpit-windows-native-design.md`
- **Plan:** `darwin-cluster/docs/superpowers/plans/2026-06-08-cockpit-windows-native.md`

## Layout

| Project | Purpose | UI | Verifiable on Linux? |
|---------|---------|----|----------------------|
| `src/BeagleCore.Net` | Cluster contract: `FleetEndpoint` + `PtyClient` (`/pty` protocol) | No | **Yes** (.NET 9 SDK) |
| `src/BeagleWorkbench.WinUI` | XtermSharp terminal view + keep-alive store + fleet screen | Yes | No (needs Windows) |
| `src/BeagleCockpit.Windows` | WinUI 3 app shell | Yes | No (needs Windows) |

## Verification status

- `BeagleCore.Net` (+ tests): **written**. To verify on any .NET 9 SDK (Linux ok, no Windows needed):
  ```bash
  cd /home/devsounio/beagle/beagle-windows
  dotnet test tests/BeagleCore.Net.Tests
  ```
- `BeagleWorkbench.WinUI` / `BeagleCockpit.Windows`: **NOT YET WRITTEN / UNVERIFIED** — pending a
  Windows build host (.NET 9 SDK + Windows App SDK + WinUI workload). Do not claim the UI works until
  the live screenshot oracle (plan Task 7) exists.

## Terminal renderer decision

XtermSharp (pure-managed VT100 engine, same author as Apple's SwiftTerm) + a custom WinUI render
view. Rationale + alternatives: see the design doc §3.
