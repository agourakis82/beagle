#if os(iOS) || os(macOS)

import BeagleCore
import Metal
import MetalKit
import MetalSplatter
import os
import SampleBoxRenderer
import simd
import SplatIO
import SwiftUI

@MainActor
class MetalKitSceneRenderer: NSObject, MTKViewDelegate {
    private static let log =
        Logger(subsystem: Bundle.main.bundleIdentifier!,
               category: "MetalKitSceneRenderer")

    let metalKitView: MTKView
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    var model: ModelIdentifier?
    var modelRenderer: (any ModelRenderer)?
    var proceduralSplatController: ProceduralSplatController?

    let inFlightSemaphore = DispatchSemaphore(value: Constants.maxSimultaneousRenders)

    var lastRotationUpdateTimestamp: Date? = nil
    var rotation: Angle = .zero            // world-space turntable (locked for the companion)
    var frontYaw: Angle = Constants.frontYaw   // TRELLIS camera yaw (overridable via --splat-yaw)
    var frontPitch: Angle = Constants.frontPitch // TRELLIS camera pitch (overridable via --splat-pitch)
    var camVariant: Int = 0   // for a CANONICALIZED ply: 0..3 = eye/up axis-sign combos (MetalSplatter convention probe)
    var camR: Float = Constants.frontRadius  // orbit distance (overridable via --splat-r) to frame the whole dog

    // Reactivity: the shared CompanionMotion brain deforms the splat per frame (ears/head/tail/breath).
    var reactor: SplatReactor?
    var motion = CompanionMotion()           // resting by default; set lively for the demo / from stores
    private var motionStart: Date?
    private var motionOverriddenByArgs = false   // demo launch args win over live store state

    /// Push live conversation/physiology state (from the SwiftUI layer). No-op if a demo
    /// launch arg pinned the motion, so screenshot sweeps stay deterministic.
    func setMotion(_ m: CompanionMotion) {
        guard !motionOverriddenByArgs else { return }
        motion = m
    }

    var drawableSize: CGSize = .zero

    init?(_ metalKitView: MTKView) {
        self.device = metalKitView.device!
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.metalKitView = metalKitView
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float
        metalKitView.sampleCount = 1
        metalKitView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        // Camera tuning: override the TRELLIS-frame yaw/pitch via launch args (no rebuild).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--splat-yaw"), i + 1 < args.count, let d = Double(args[i + 1]) {
            self.frontYaw = .degrees(d)
        }
        if let i = args.firstIndex(of: "--splat-pitch"), i + 1 < args.count, let d = Double(args[i + 1]) {
            self.frontPitch = .degrees(d)
        }
        if let i = args.firstIndex(of: "--cam-variant"), i + 1 < args.count, let d = Int(args[i + 1]) {
            self.camVariant = d
        }
        if let i = args.firstIndex(of: "--splat-r"), i + 1 < args.count, let d = Float(args[i + 1]) {
            self.camR = d
        }
        // Demo/preview drive for the reactivity (real app feeds CompanionMotion from the stores):
        // --splat-flow FLOW|STRESS, --splat-listen, --splat-breath <rpm>.
        var flow: String? = nil
        if let i = args.firstIndex(of: "--splat-flow"), i + 1 < args.count { flow = args[i + 1] }
        let listening = args.contains("--splat-listen")
        var breath: Double? = nil
        if let i = args.firstIndex(of: "--splat-breath"), i + 1 < args.count, let d = Double(args[i + 1]) { breath = d }
        if flow != nil || listening || breath != nil {
            // `--splat-breath` é uma medida DECLARADA pelo operador, com carimbo de agora.
            self.motion = CompanionMotion(
                flowState: flow, listening: listening,
                breath: PresenceBreath.from(bpm: breath, observedAt: breath == nil ? nil : Date())
            )
            self.motionOverriddenByArgs = true
        }
    }

    func load(_ model: ModelIdentifier?) async throws {
        guard model != self.model else { return }
        self.model = model

        modelRenderer = nil
        proceduralSplatController = nil
        switch model {
        case .gaussianSplat(let url):
            let splat = try SplatRenderer(device: device,
                                          colorFormat: metalKitView.colorPixelFormat,
                                          depthFormat: metalKitView.depthStencilPixelFormat,
                                          sampleCount: metalKitView.sampleCount,
                                          maxViewCount: 1,
                                          maxSimultaneousRenders: Constants.maxSimultaneousRenders)
            let reader = try AutodetectSceneReader(url)
            let points = try await reader.readAll()
            let chunk = try SplatChunk(device: device, from: points)
            _ = await splat.addChunk(chunk)            // may reorder splats in place; same shared buffer
            modelRenderer = splat
            // Snapshot rest pose + region labels from the (post-reorder) shared buffer so the
            // CompanionMotion brain can deform ears/head/tail/chest each frame.
            reactor = SplatReactor(chunk: chunk)
            reactor?.selfTest = ProcessInfo.processInfo.arguments.contains("--splat-selftest")
            // On-device ear tuning (no rebuild): --ear-mag <rad> --ear-py <frac> --ear-px <frac>
            let a = ProcessInfo.processInfo.arguments
            func argF(_ k: String) -> Float? {
                if let i = a.firstIndex(of: k), i + 1 < a.count { return Float(a[i + 1]) }
                return nil
            }
            if let r = reactor {
                if let v = argF("--ear-mag") { r.rig.earMaxPerk = v }
                if let v = argF("--ear-py")  { r.rig.earPivotYFrac = v }
                if let v = argF("--ear-px")  { r.rig.earPivotXFrac = v }
            }
            print("SPLAT_REACTOR \(reactor?.debugSummary ?? "nil") selfTest=\(reactor?.selfTest ?? false)")
        case .proceduralSplat:
            let controller = try await ProceduralSplatController(
                device: device,
                colorFormat: metalKitView.colorPixelFormat,
                depthFormat: metalKitView.depthStencilPixelFormat,
                sampleCount: metalKitView.sampleCount,
                maxViewCount: 1,
                maxSimultaneousRenders: Constants.maxSimultaneousRenders)
            proceduralSplatController = controller
            modelRenderer = controller.splatRenderer
        case .sampleBox:
            modelRenderer = try! SampleBoxRenderer(device: device,
                                                   colorFormat: metalKitView.colorPixelFormat,
                                                   depthFormat: metalKitView.depthStencilPixelFormat,
                                                   sampleCount: metalKitView.sampleCount,
                                                   maxViewCount: 1,
                                                   maxSimultaneousRenders: Constants.maxSimultaneousRenders)
        case .none:
            break
        }
    }

    private var viewport: ModelRendererViewportDescriptor {
        let aspect = Float(drawableSize.width / max(1, drawableSize.height))
        let projectionMatrix = matrix_perspective_right_hand(fovyRadians: Float(Constants.frontFov.radians),
                                                             aspectRatio: aspect,
                                                             nearZ: 0.4,
                                                             farZ: 8.0)
        // The ply is CANONICALIZED on the cluster: dog front → +Z, up → +Y. So a fixed simple
        // front camera shows the face for ANY seed — no per-seed search. camVariant flips the
        // eye/up axis signs to pin MetalSplatter's load convention once.
        // Orbit the canonical upright dog: yaw=pitch=0 → eye=(0,0,r) (face the +Z front).
        // --splat-yaw/--splat-pitch relocate the eye on a sphere with NO rebuild, so we can
        // sweep to find which horizontal angle shows the face for this seed, then bake it.
        let r = camR
        let yaw = Float(frontYaw.radians)
        let pitch = Float(frontPitch.radians)
        let eye = SIMD3<Float>(r * cos(pitch) * sin(yaw),
                               r * sin(pitch),
                               r * cos(pitch) * cos(yaw))
        let viewMatrix = matrix_look_at_right_hand(eye: eye, center: SIMD3<Float>(0, 0, 0),
                                                   up: SIMD3<Float>(0, 1, 0))

        let viewport = MTLViewport(originX: 0, originY: 0, width: drawableSize.width, height: drawableSize.height, znear: 0, zfar: 1)

        return ModelRendererViewportDescriptor(viewport: viewport,
                                               projectionMatrix: projectionMatrix,
                                               viewMatrix: viewMatrix,
                                               screenSize: SIMD2(x: Int(drawableSize.width), y: Int(drawableSize.height)))
    }

    private func updateRotation() {
        let now = Date()
        defer {
            lastRotationUpdateTimestamp = now
        }

        guard let lastRotationUpdateTimestamp else { return }
        rotation += Constants.rotationPerSecond * now.timeIntervalSince(lastRotationUpdateTimestamp)
    }

    func draw(in view: MTKView) {
        guard let modelRenderer, modelRenderer.isReadyToRender else { return }
        guard let drawable = view.currentDrawable else { return }

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            return
        }

        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
            semaphore.signal()
        }

        updateRotation()
        proceduralSplatController?.update()

        // Reactivity: deform the splat from rest for this instant's pose. Safe to mutate the
        // shared gaussian buffer here — with one frame in flight, the previous frame's GPU read
        // has completed (we hold the in-flight semaphore).
        if let reactor {
            let now = Date()
            let start = motionStart ?? now
            if motionStart == nil { motionStart = now }
            reactor.update(pose: motion.pose(at: now.timeIntervalSince(start)))
        }

        let didRender: Bool
        do {
            didRender = try modelRenderer.render(viewports: [viewport],
                                                 colorTexture: view.multisampleColorTexture ?? drawable.texture,
                                                 colorStoreAction: view.multisampleColorTexture == nil ? .store : .multisampleResolve,
                                                 depthTexture: view.depthStencilTexture,
                                                 rasterizationRateMap: nil,
                                                 renderTargetArrayLength: 0,
                                                 to: commandBuffer)
        } catch {
            Self.log.error("Unable to render scene: \(error.localizedDescription)")
            didRender = false
        }

        if didRender {
            commandBuffer.present(drawable)
        }

        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
    }
}

#endif // os(iOS) || os(macOS)
