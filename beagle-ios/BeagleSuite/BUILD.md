# BeagleSuite — Build & Distribution Guide

This guide takes you from "Swift source files on disk" to "apps installed on your Apple devices via TestFlight."

The source layout has been written on the Linux dev machine. Build and ship happens on your Mac.

---

## Prerequisites

On your Mac:
- **macOS 26 Tahoe** (or latest)
- **Xcode 26+** installed (download from Apple Developer — not the App Store version if newer is available)
- **Apple Developer Program** membership (active)
- **Apple ID** signed in to Xcode (Settings → Accounts → add)
- **Command Line Tools**: `xcode-select --install`
- **Vision Pro** device (for visionOS testing) — optional, simulator works too
- **Apple Watch** paired to your iPhone (for watchOS testing)

---

## Step 1 — Pull the source to your Mac

```bash
# On your Mac
cd ~/dev  # wherever you keep code
git clone <your-beagle-repo>    # or rsync from the Proxmox dev machine
cd beagle/beagle-ios/BeagleSuite
```

---

## Step 2 — Open Package.swift in Xcode (SPM mode)

```bash
xed Package.swift
```

This opens the shared `BeagleCore` library in Xcode. Build it once:
- Select scheme: `BeagleCore`
- Product → Build (⌘B)

If build fails due to Swift 6 strict concurrency:
- Fix any warnings Xcode points out (likely shared state access)
- The code is written for Swift 6 — should build clean

---

## Step 3 — Use the tracked app project

The app targets already exist in Git:

- `beagle-ios/BeagleSuite.xcodeproj`
- `beagle-ios/project.yml` (XcodeGen source of truth when `xcodegen` is installed)
- `BeagleCockpit`, `BeagleVisionOS`, `BeagleWatch`, `BeagleWidgets`, and `BeagleShare`

Do not recreate targets manually. Open the project from the repo root:

```bash
xed beagle-ios/BeagleSuite.xcodeproj
```

For CI or local verification on a Mac with Xcode:

```bash
./scripts/build_beagle_apple.sh
```

The shared Swift package still owns `BeagleCore`; app targets link that package and render the same cluster-canonical Exocortex state.

---

## Step 4 — Configure capabilities

### BeagleCockpit:
- **App Intents** (automatic — detected by Xcode)
- **Network extension** (if using Tailscale SDK)
- **App Groups**: `group.dev.sounio.cockpit` (for sharing data with widget extension)
- **Background Modes**: Remote notifications (for APNs), Background fetch
- **Push Notifications** (for APNs)

### BeagleVisionOS:
- Same as BeagleCockpit, plus:
- **Immersive Spaces** (automatic)
- **Hand Tracking** (if needed for advanced gestures)

### BeagleWatch:
- **HealthKit**: Heart Rate Variability read

### BeagleWidgets:
- Share **App Group** with main app

---

## Step 5 — Generate app icons

Option A (quick): use any icon generator to produce a 1024x1024 PNG with the Beagle teal/glass aesthetic, then drop it into `Assets.xcassets` → `AppIcon`.

Option B (bespoke): design in Figma/Sketch with teal gradient over dark base. Generate all required sizes via:
```bash
brew install imagemagick
# or use an online tool that produces ios-icons.zip
```

---

## Step 6 — Privacy manifest (required for App Store)

For each app target, create `PrivacyInfo.xcprivacy`:
- **File → New → File → App Privacy**
- Declare required reason APIs (file timestamp, user defaults, etc.)
- Declare data collection (for most Beagle apps: none — minimal data)

For BeagleWatch: declare HealthKit usage:
- `NSHealthShareUsageDescription` → "Beagle monitors HRV to suggest flow-state focus modes."

For BeagleCockpit (if using voice later):
- `NSSpeechRecognitionUsageDescription`
- `NSMicrophoneUsageDescription`

---

## Step 7 — Set up secrets

The cockpit apps need API keys for Anthropic/OpenAI/XAI for the Foundation Models tier-0 alternatives. **Never check in secrets.**

For local dev: use `.xcconfig` files (gitignored):
```
// BeagleSuite/Config/Secrets.xcconfig
ANTHROPIC_API_KEY = sk-ant-...
OPENAI_API_KEY = sk-...
```

For shipping: use Keychain via `AuthenticationServices` on first launch, or require user to sign in.

---

## Step 8 — Build and run on simulator

1. Select scheme **BeagleCockpit** → iPhone 16 Pro (iOS 26) simulator
2. Cmd+R to build and run
3. Verify:
   - App launches, shows Sovereign Surfaces title
   - Tailnet connection works (simulator might need DNS override — try direct IP if tailnet fails)
   - Project list populates from `/api/catalog/executive`
   - Tap project → control room shows 5 lanes with truth badges

---

## Step 9 — Install on real device

1. Connect iPhone/iPad via USB or use wireless debugging
2. Select device from Xcode device picker
3. Cmd+R to install
4. Trust the developer profile on device (Settings → General → VPN & Device Management)

For Vision Pro:
- Connect via USB-C (or use Developer Strap if available)
- Select in Xcode device picker
- BeagleVisionOS scheme → Cmd+R
- Put on the headset, see spatial cockpit

For Apple Watch:
- Pair Watch to your iPhone
- BeagleWatch scheme → select watch
- Cmd+R

---

## Step 10 — TestFlight internal distribution

For personal use (just you across your devices):

1. **Archive**: Product → Destination → Any iOS Device → Product → Archive
2. **Upload**: Organizer window → Distribute App → App Store Connect → Upload
3. **App Store Connect** (https://appstoreconnect.apple.com):
   - My Apps → BeagleCockpit (create if not exists)
   - TestFlight tab → your build appears after processing (10-30 min)
   - Create an Internal Testing group → add yourself
   - Enable your build for that group
4. **TestFlight app on your devices**: install builds from invites

Repeat for BeagleVisionOS and BeagleWatch.

---

## Step 11 (optional) — Fastlane for repeatable builds

Install fastlane:
```bash
gem install fastlane
cd beagle-ios
fastlane init
```

Create a `Fastfile`:
```ruby
default_platform(:ios)

platform :ios do
  desc "Build and upload to TestFlight"
  lane :beta do
    build_app(scheme: "BeagleCockpit")
    upload_to_testflight(skip_waiting_for_build_processing: true)
  end
end
```

Then just: `fastlane beta`.

---

## Verification checklist

After first successful build:

- [ ] `BeagleCockpit` builds for iPhone 16 Pro Max simulator
- [ ] `BeagleCockpit` builds for macOS (Mac Catalyst or native)
- [ ] `BeagleVisionOS` builds for Vision Pro simulator
- [ ] `BeagleWatch` builds for Apple Watch Series 10 simulator
- [ ] `BeagleWidgets` target builds, widgets appear in widget gallery on home screen
- [ ] App launches, loads cockpit catalog from Tailnet
- [ ] Project tapped → control room renders with truth badges
- [ ] Siri responds to "Show BeagleCockpit cluster status"
- [ ] Archive succeeds
- [ ] TestFlight upload succeeds
- [ ] Build appears in TestFlight within 30 min
- [ ] Install via TestFlight on real iPhone
- [ ] Deep link `dev.sounio.cockpit://project/sounio` opens control room

---

## Architecture notes

- **BeagleCore** is the shared SPM library — it has all models, API client, theme, components. Don't duplicate this code in individual apps.
- **No auth yet** — the cockpit server trusts Tailnet identity. When multi-tenancy is added later, the iOS apps need to acquire JWT via OAuth.
- **All apps consume the same cockpit API** — `sounio-cockpit.tail21cbc4.ts.net`. If running locally for dev, point to `http://100.107.208.198` or in-cluster service DNS.
- **Foundation Models (tier-0)** is used as fallback when cloud agent unreachable. Always available on device.
- **Agent pods (tier-2)** are spawned via `/api/projects/:slug/agent/session/start` — see `k8s/agent-pods/`.

---

## Roadmap (after initial TestFlight ship)

1. **Deep linking polish** — universal links (`https://cockpit.sounio.dev/...`) + scheme
2. **Handoff / Continuity** — NSUserActivity for session state
3. **SharePlay** for collaborative Vision Pro sessions
4. **watchOS Smart Stack widget** (beyond complication)
5. **macOS menu bar extra** (already stub'd in `BeagleCockpitApp.swift`)
6. **Siri vocabulary expansion** — custom utterances for Sounio-specific commands
7. **HealthKit-driven Focus modes** — flow state → quiet mode automatically

---

## Troubleshooting

**Build error: "Cannot find type 'FoundationModels' in scope"**
→ Install Xcode 26+ or newer. Foundation Models framework requires iOS 26+ SDK.

**Build error: "actor isolation" warnings on Swift 6**
→ Shared state must be `@MainActor` or `Sendable`. Fix by annotating with `@MainActor` or wrapping in `actor`.

**Widget doesn't show live data**
→ Make sure widget target and main app share the same App Group.

**Vision Pro immersive space is empty**
→ Check RealityView closure is setting content correctly. Look at Xcode logs.

**TestFlight upload fails with "Missing Compliance"**
→ Set `ITSAppUsesNonExemptEncryption` to `NO` in Info.plist (you only use HTTPS which is exempt).
