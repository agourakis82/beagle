//
//  SplatReactor.swift
//  BeagleCockpit — drives the photoreal splat with the shared CompanionMotion brain.
//
//  MetalSplatter stores each gaussian as `EncodedSplatPoint { position, colorSH0, covA, covB }`
//  in a storageModeShared buffer that the GPU reads by address every frame. Its fields are
//  `internal`, so we write THROUGH the public `splats.buffer` using a layout-matched mirror
//  struct (guarded by a stride assertion). At load we snapshot the rest pose + covariance and
//  label each gaussian into soft regions (BeagleCore.SplatRig); each frame we re-deform only
//  the active (head/ears/tail/chest) gaussians from rest — body gaussians never move.
//
//  Thread-safety: the renderer runs with one frame in flight (maxSimultaneousRenders == 1) and
//  calls `update(pose:)` only after the in-flight semaphore is acquired, i.e. when the previous
//  frame's GPU read of this buffer has completed — so the CPU write never races the GPU.
//

#if os(iOS) || os(macOS)
import Foundation
import Metal
import simd
import MetalSplatter
import BeagleCore

/// Byte-for-byte mirror of MetalSplatter's `EncodedSplatPoint` (position f32×3, colorSH0 f16×4,
/// covA f16×3 = Σ00,Σ01,Σ02, covB f16×3 = Σ11,Σ12,Σ22). Validated against the real stride.
private struct MirrorSplat {
    var px: Float32, py: Float32, pz: Float32
    var cr: Float16, cg: Float16, cb: Float16, ca: Float16
    var a0: Float16, a1: Float16, a2: Float16
    var b0: Float16, b1: Float16, b2: Float16
}

@MainActor
final class SplatReactor {
    private let ptr: UnsafeMutablePointer<MirrorSplat>
    private let restPos: [SIMD3<Float>]
    private let restCov: [simd_float3x3]
    private let weights: [SplatRegionWeights]
    private let active: [Int]
    private let bounds: SplatBounds
    var rig = CompanionRig()

    /// Snapshot rest state from the chunk's shared buffer AFTER `addChunk` (which may reorder it).
    init?(chunk: SplatChunk) {
        guard MemoryLayout<MirrorSplat>.stride == MemoryLayout<EncodedSplatPoint>.stride,
              MemoryLayout<MirrorSplat>.stride == 32 else {
            assertionFailure("MirrorSplat layout drifted from EncodedSplatPoint (\(MemoryLayout<EncodedSplatPoint>.stride) bytes)")
            return nil
        }
        let n = chunk.splatCount
        guard n > 0 else { return nil }
        self.ptr = chunk.splats.buffer.contents().bindMemory(to: MirrorSplat.self, capacity: n)

        var rp = [SIMD3<Float>](); rp.reserveCapacity(n)
        var rc = [simd_float3x3](); rc.reserveCapacity(n)
        for i in 0..<n {
            let s = ptr[i]
            rp.append(SIMD3(s.px, s.py, s.pz))
            let a0 = Float(s.a0), a1 = Float(s.a1), a2 = Float(s.a2)
            let b0 = Float(s.b0), b1 = Float(s.b1), b2 = Float(s.b2)
            // symmetric Σ from the 6 stored upper-triangle entries
            rc.append(simd_float3x3(rows: [SIMD3(a0, a1, a2), SIMD3(a1, b0, b1), SIMD3(a2, b1, b2)]))
        }
        self.restPos = rp
        self.restCov = rc
        let b = SplatBounds(points: rp)
        self.bounds = b

        var w = [SplatRegionWeights](); w.reserveCapacity(n)
        var act = [Int]()
        for i in 0..<n {
            let ww = SplatRig.weights(for: rp[i], bounds: b)
            w.append(ww)
            if ww.isActive { act.append(i) }
        }
        self.weights = w
        self.active = act
    }

    var activeCount: Int { active.count }
    var totalCount: Int { restPos.count }
    var debugSummary: String { "active=\(active.count)/\(restPos.count) bounds lo=\(bounds.lo) hi=\(bounds.hi)" }
    /// Diagnostic: translate EVERY splat up by a gross fixed amount (region-independent), to prove
    /// the buffer-write path reaches the screen. Set via --splat-selftest.
    var selfTest = false

    /// Re-deform the active gaussians from rest for this pose and write them into the shared buffer.
    func update(pose: CompanionPose) {
        if selfTest {
            for i in 0..<restPos.count {
                let p = restPos[i] + SIMD3<Float>(0, 0.18, 0)
                ptr[i].px = p.x; ptr[i].py = p.y; ptr[i].pz = p.z
            }
            return
        }
        let frame = rig.frame(pose: pose, bounds: bounds)
        for i in active {
            let (p, c) = rig.deform(restPos: restPos[i], restCov: restCov[i], w: weights[i], frame: frame)
            var s = ptr[i]
            s.px = p.x; s.py = p.y; s.pz = p.z
            s.a0 = Float16(c[0][0]); s.a1 = Float16(c[0][1]); s.a2 = Float16(c[0][2])
            s.b0 = Float16(c[1][1]); s.b1 = Float16(c[1][2]); s.b2 = Float16(c[2][2])
            ptr[i] = s
        }
    }
}
#endif
