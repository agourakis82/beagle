# Beagle splat reactivity — design

How the photoreal goldendoodle Gaussian splat becomes a *living* companion that
reacts to the user's body and the conversation. The static splat (from LGM / TRELLIS)
is the body; this doc is the rig + the nervous system.

## 1. The motion brain (DONE)

`BeagleCore/CompanionMotion.swift` (tested, `CompanionMotionTests`) is the single source
of motion for **both** bodies — the vector `BeagleFigure` and the splat. Pure, deterministic:

```
CompanionMotion(flowState, sleepQuality01, listening, breathRate) -> pose(at: t) -> CompanionPose
CompanionPose { breath, breathScale, earPerk, tailWag, headLift, blink, energy }
```

- `energy` rises with FLOW and with `listening`.
- `breath` rides the user's real breath rate (`breathRate`, from HealthKit/HRV) — the dog
  literally breathes at his pace; falls back to a calm 4.4 s resting cycle.
- `earPerk` / `tailWag` grow (perk up, wag faster + wider) with energy.
- `headLift` raises toward the user when listening/responding.
- `blink` — a slow ~5.2 s cycle keeps it alive.

The splat consumer reads the SAME pose; only the *mapping to geometry* differs per body.

## 2. Deforming a Gaussian splat

A splat is N Gaussians, each `{position xyz, rotation quat, scale, opacity, SH color}`.
To animate it we transform positions (and rotations) per frame. Two tiers:

### v1 — Region-based LBS-lite (ship this first)

No skeleton fitting. At load, label each Gaussian into a **region** by its position in the
splat's canonical (front-facing, normalized) frame:

| Region | Heuristic (canonical, +Y up, +Z toward viewer) | Driven by |
|--------|-----------------------------------------------|-----------|
| `head` | upper-front cluster (high Y, high Z)          | `headLift` → rotate about a neck pivot |
| `earL/earR` | head sides, below ear-root, |X| large    | `earPerk` → rotate up about the ear root |
| `tail` | rear (low Z), mid Y                            | `tailWag` → rotate L/R about tail base |
| `chest`| lower-front mass                              | `breathScale` → anisotropic scale about chest center |
| `body` | everything else                               | static (anchor) |

Labels are a `uint8` per Gaussian, computed once on the CPU (or a one-shot compute pass)
when the splat loads. Each frame, a **Metal compute shader** applies the per-region affine
(rotation about a pivot / scale) to position + rotation, writing a deformed copy of the
gaussian buffer that the rasterizer then draws. Pivots + region boxes are 6–8 constants,
tuned once against the real doodle splat.

Cost: one compute dispatch over N gaussians per frame — trivial on A-series/M-series and on
the GB10. Blends are linear in region weight at boundaries to avoid seams (give each gaussian
a soft weight per region instead of a hard label → no cracking where the ear meets the head).

### v2 — SMAL skinning (upgrade for finer motion / Vision Pro)

Fit **SMAL** (the parametric quadruped model — the animal SMPL) to the splat once, offline,
on the cluster: register SMAL to the splat geometry, transfer skinning weights to each
Gaussian (nearest-surface LBS). Then joints (ears, tail, neck, jaw, spine-for-breath) drive
the splat via linear blend skinning — same `CompanionPose` → joint angles. Gives anatomically
correct articulation and pose generalization (sit/lie/turn), at the cost of the SMAL fit.
v1's region pivots are a strict subset of v2's joints, so the runtime API is identical —
v2 just swaps the weight source (soft region labels → SMAL skinning weights).

## 3. Renderer integration (MetalSplatter)

`BeagleSplatView` → `MetalKitSceneView` → `MetalKitSceneRenderer` drives a `SplatRenderer`.
Insertion point: between "gaussians uploaded" and "rasterize". Options, in order of preference:
1. **Deform compute pass** owning a deformed buffer the `SplatRenderer` draws (cleanest; needs
   access to the chunk's gaussian buffer — extend `SplatChunk`/renderer with a deform hook).
2. **Per-frame chunk replace** via the existing `addChunk`/`setChunkEnabled` API (the procedural
   demo already mutates chunks live) — simpler, coarser, fine for low gaussian counts.
   Start here to prove motion, move to (1) for 60 fps at full density.

Camera: lock front-facing for the companion (it faces the user); disable the demo turntable.
Compositing: `clearColor` alpha 0 → the dog floats in the chat hearth (already wired).

## 4. Eyes / gaze / blink on a splat

Hardest on a splat (no eyelid geometry). Options, cheap→rich:
- **Blink**: briefly drop opacity / darken the eye-region Gaussians (label an `eye` region) —
  reads as a blink without geometry.
- **Gaze**: small rigid rotation of the `head` region toward the user (ties to `headLift`).
- v2: SMAL eye/jaw joints for real lid + mouth motion.

## 5. State wiring

`ConversationStore` already exposes `flowState`, `sleepQuality01`, `isStreaming`.
Add `breathRate` (from `PhysioStore`/HealthKit respiratory rate or HRV-derived) → feed
`CompanionMotion`. `listening = isStreaming`. The vector figure and the splat both subscribe;
the companion's body and face move as one because they share `CompanionMotion`.

## Next

1. Generate the final splat (TRELLIS, A5000) → `.ply`.
2. Load into `BeagleSplatView` (one-line `ModelIdentifier` swap), front-facing, on device.
3. Region-label + v1 deform compute pass, wired to `CompanionMotion`.
4. Tune pivots/boxes against the real doodle; soft weights at seams.
5. (later) SMAL fit for v2.
