//
//  BeagleSplatView.swift
//  BeagleCockpit — Companion chat (Gaussian-splat presence)
//
//  De-risk host for the photoreal Gaussian-splat beagle. Wraps the MetalSplatter MTKView
//  renderer (the same renderer that serves visionOS — see VisionSceneRenderer). For now it
//  renders a PROCEDURAL splat (zero asset) to prove the on-device Metal splat pipeline end to
//  end. The real beagle drops in by swapping `.proceduralSplat` → `.gaussianSplat(bundleURL)`
//  once the stock video is trained into a .splat and SMAL-rigged for reactivity.
//
//  Behind the `--beagle-splat` launch flag; the vector `BeagleFigure` stays the default face
//  and graceful fallback (no regression).
//

#if os(iOS) || os(macOS)
import SwiftUI
import BeagleCore

struct BeagleSplatView: View {
    /// The companion's photoreal Gaussian splat. Prefers `plush.splat` — a high-fidelity
    /// real capture (antimatter15 sample) — over the lower-fidelity TRELLIS-generated doodle,
    /// then the procedural test splat as a last resort. Swap the bundled file to change the
    /// mascot (any 3DGS `.splat` or `.ply` MetalSplatter can read).
    static var doodleModel: ModelIdentifier {
        // Default to the recognizable TRELLIS doodle (canonicalized for the renderer's fixed
        // camera). The `plush` test capture is kept bundled but off by default — it's low-fidelity
        // and only loads via --beagle-plush. The real photoreal mascot will be the user's own
        // captured subject, run through the same canonicalization pipeline as the doodle.
        if ProcessInfo.processInfo.arguments.contains("--beagle-plush"),
           let url = Bundle.main.url(forResource: "plush", withExtension: "splat") {
            return .gaussianSplat(url)
        }
        if let url = Bundle.main.url(forResource: "trellis_doodle", withExtension: "ply") {
            return .gaussianSplat(url)
        }
        return .proceduralSplat
    }

    var model: ModelIdentifier = BeagleSplatView.doodleModel
    /// Live conversation/physiology → the shared CompanionMotion brain that deforms the splat
    /// (ears perk / head lifts on FLOW + listening, chest breathes at the user's rate).
    var motion: CompanionMotion = CompanionMotion()

    var body: some View {
        MetalKitSceneView(modelIdentifier: model, motion: motion)
            .background(Color.clear)   // transparent clearColor → composites into the hearth
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif
