//
//  SplatDeform.swift
//  BeagleCore — region-based "LBS-lite" deformation for the photoreal splat body.
//
//  The splat is N Gaussians {position, covariance}. To make it react we transform a few
//  REGIONS rigidly each frame, driven by the SAME CompanionPose that drives the vector
//  BeagleFigure (one motion brain, two bodies). Pure + deterministic so it is unit-tested
//  render-free: position rotates about a pivot, covariance transforms as Σ' = R·Σ·Rᵀ
//  (rotation invariants — trace, det — let us assert correctness without a GPU).
//
//  Canonical frame (after the .ply canon): +Y up, +Z toward the viewer, dog facing +Z.
//

import Foundation
import simd

/// Soft membership of one gaussian in each animated region, 0…1 (soft → no seams).
public struct SplatRegionWeights: Equatable, Sendable {
    public var head: Float
    public var earL: Float
    public var earR: Float
    public var tail: Float
    public var chest: Float
    public init(head: Float = 0, earL: Float = 0, earR: Float = 0, tail: Float = 0, chest: Float = 0) {
        self.head = head; self.earL = earL; self.earR = earR; self.tail = tail; self.chest = chest
    }
    /// True if this gaussian is touched by any region (lets the runtime skip static splats).
    public var isActive: Bool { max(head, max(earL, max(earR, max(tail, chest)))) > 0.02 }
}

/// Axis-aligned bounds of the splat in the canonical frame.
public struct SplatBounds: Sendable, Equatable {
    public var lo: SIMD3<Float>
    public var hi: SIMD3<Float>
    public init(lo: SIMD3<Float>, hi: SIMD3<Float>) { self.lo = lo; self.hi = hi }
    public var size: SIMD3<Float> { hi - lo }
    public var mid: SIMD3<Float> { (lo + hi) * 0.5 }
    public var maxAbsX: Float { max(abs(lo.x), abs(hi.x)) }
    /// Bounds over a point cloud.
    public init(points: [SIMD3<Float>]) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in points { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        self.lo = lo; self.hi = hi
    }
}

@inline(__always) private func smoothstep(_ a: Float, _ b: Float, _ v: Float) -> Float {
    let t = max(0, min(1, (v - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

public enum SplatRig {
    /// Pure soft region weights for a rest position (mirrors the tuned point-cloud heuristics).
    public static func weights(for p: SIMD3<Float>, bounds b: SplatBounds) -> SplatRegionWeights {
        let s = b.size
        let yn = s.y > 0 ? (p.y - b.lo.y) / s.y : 0          // 0 bottom … 1 top
        let zn = s.z > 0 ? (p.z - b.lo.z) / s.z : 0          // 0 back  … 1 front
        let xa = b.maxAbsX > 0 ? abs(p.x) / b.maxAbsX : 0    // 0 center … 1 side

        let head = smoothstep(0.60, 0.74, yn)
        let earBand = smoothstep(0.46, 0.60, yn) * (1 - smoothstep(0.80, 0.92, yn)) * smoothstep(0.50, 0.72, xa)
        let earL = p.x > 0 ? earBand : 0
        let earR = p.x < 0 ? earBand : 0
        let tail = smoothstep(0.22, 0.10, zn) * smoothstep(0.28, 0.45, yn) * (1 - smoothstep(0.55, 0.65, yn))
        let chest = smoothstep(0.30, 0.40, yn) * (1 - smoothstep(0.52, 0.62, yn))
                  * smoothstep(0.50, 0.66, zn) * (1 - smoothstep(0.60, 0.80, xa))
        return SplatRegionWeights(head: head, earL: earL, earR: earR, tail: tail, chest: chest)
    }
}

/// Tunable rig: pivots (as fractions of bounds) + max angles/amplitudes. Defaults match the
/// vector BeagleFigure's feel (ear perk ≈ 0.22 rad, etc.); signs/magnitudes refined on device.
public struct CompanionRig: Sendable {
    public var headMaxNod: Float   // rad at headLift = 1  (nose lifts toward the user)
    public var earMaxPerk: Float   // rad at earPerk = 1   (ear tips lift up-out)
    public var tailMaxWag: Float   // rad at tailWag = ±1
    public var breathAmp: Float    // fractional chest expansion at breath = ±1

    // pivot positions as fractions within bounds (x: −1…1 across half-width, y/z: 0…1)
    public var headPivotYFrac: Float
    public var earPivotYFrac: Float
    public var earPivotXFrac: Float   // |x| fraction of half-width for each ear root
    public var tailPivotYFrac: Float
    public var chestYFrac: Float
    public var chestZFrac: Float

    public init(headMaxNod: Float = 0.20, earMaxPerk: Float = 0.50, tailMaxWag: Float = 0.35,
                breathAmp: Float = 0.035, headPivotYFrac: Float = 0.58, earPivotYFrac: Float = 0.70,
                earPivotXFrac: Float = 0.40, tailPivotYFrac: Float = 0.40, chestYFrac: Float = 0.42,
                chestZFrac: Float = 0.70) {
        self.headMaxNod = headMaxNod; self.earMaxPerk = earMaxPerk; self.tailMaxWag = tailMaxWag
        self.breathAmp = breathAmp; self.headPivotYFrac = headPivotYFrac; self.earPivotYFrac = earPivotYFrac
        self.earPivotXFrac = earPivotXFrac; self.tailPivotYFrac = tailPivotYFrac
        self.chestYFrac = chestYFrac; self.chestZFrac = chestZFrac
    }

    @inline(__always) private func yAt(_ f: Float, _ b: SplatBounds) -> Float { b.lo.y + f * b.size.y }
    @inline(__always) private func zAt(_ f: Float, _ b: SplatBounds) -> Float { b.lo.z + f * b.size.z }

    public func headPivot(_ b: SplatBounds) -> SIMD3<Float> { SIMD3(b.mid.x, yAt(headPivotYFrac, b), b.mid.z) }
    public func earPivotL(_ b: SplatBounds) -> SIMD3<Float> { SIMD3( earPivotXFrac * b.maxAbsX, yAt(earPivotYFrac, b), b.mid.z) }
    public func earPivotR(_ b: SplatBounds) -> SIMD3<Float> { SIMD3(-earPivotXFrac * b.maxAbsX, yAt(earPivotYFrac, b), b.mid.z) }
    public func tailPivot(_ b: SplatBounds) -> SIMD3<Float> { SIMD3(b.mid.x, yAt(tailPivotYFrac, b), b.lo.z) }
    public func chestCenter(_ b: SplatBounds) -> SIMD3<Float> { SIMD3(b.mid.x, yAt(chestYFrac, b), zAt(chestZFrac, b)) }

    @inline(__always) private func rot(_ angle: Float, _ axis: SIMD3<Float>) -> simd_float3x3 {
        simd_float3x3(simd_quatf(angle: angle, axis: axis))
    }

    /// One per-region rigid transform (rotation about a pivot, or a scale about a center),
    /// resolved ONCE per frame from the pose. Per-splat deform then just blends by weight —
    /// no trig in the hot loop over hundreds of thousands of gaussians.
    public struct DeformFrame: Sendable {
        var headR: simd_float3x3, headPivot: SIMD3<Float>
        var earLR: simd_float3x3, earLPivot: SIMD3<Float>
        var earRR: simd_float3x3, earRPivot: SIMD3<Float>
        var tailR: simd_float3x3, tailPivot: SIMD3<Float>
        var breathS: simd_float3x3, chestCenter: SIMD3<Float>
    }

    /// Build the per-frame region transforms for a pose (called once per rendered frame).
    public func frame(pose: CompanionPose, bounds b: SplatBounds) -> DeformFrame {
        let X = SIMD3<Float>(1, 0, 0), Y = SIMD3<Float>(0, 1, 0), Z = SIMD3<Float>(0, 0, 1)
        let s = 1 + breathAmp * Float(pose.breath)
        return DeformFrame(
            headR: rot(-headMaxNod * Float(pose.headLift), X), headPivot: headPivot(b),  // −X: snout lifts toward the user
            earLR: rot(-earMaxPerk * Float(pose.earPerk), Z), earLPivot: earPivotL(b),
            earRR: rot( earMaxPerk * Float(pose.earPerk), Z), earRPivot: earPivotR(b),
            tailR: rot(tailMaxWag * Float(pose.tailWag), Y), tailPivot: tailPivot(b),
            breathS: simd_float3x3(diagonal: SIMD3(s, s, 1)), chestCenter: chestCenter(b))
    }

    /// Blend one region's full transform into the running (pos, cov) by membership weight `w`.
    /// Linear blend of position and covariance → soft seams, no cracking. w=1 is the exact
    /// rigid transform (distance-to-pivot and Σ trace/det preserved); w=0 is a no-op.
    @inline(__always)
    private func blendRot(_ R: simd_float3x3, _ pivot: SIMD3<Float>, _ w: Float,
                          _ pos: inout SIMD3<Float>, _ cov: inout simd_float3x3) {
        let fp = pivot + R * (pos - pivot)
        let fc = R * cov * R.transpose
        pos = pos + (fp - pos) * w
        cov = cov + (fc - cov) * w
    }

    /// Deform ONE gaussian from rest, given precomputed frame transforms. Pure.
    public func deform(restPos: SIMD3<Float>, restCov: simd_float3x3,
                       w: SplatRegionWeights, frame f: DeformFrame)
        -> (pos: SIMD3<Float>, cov: simd_float3x3) {
        var pos = restPos
        var cov = restCov
        if w.head > 0 { blendRot(f.headR, f.headPivot, w.head, &pos, &cov) }
        if w.earL > 0 { blendRot(f.earLR, f.earLPivot, w.earL, &pos, &cov) }
        if w.earR > 0 { blendRot(f.earRR, f.earRPivot, w.earR, &pos, &cov) }
        if w.tail > 0 { blendRot(f.tailR, f.tailPivot, w.tail, &pos, &cov) }
        if w.chest > 0 {                      // chest breathes — scale about its center, weighted
            let c = f.chestCenter
            let fp = c + f.breathS * (pos - c)
            let fc = f.breathS * cov * f.breathS.transpose
            pos = pos + (fp - pos) * w.chest
            cov = cov + (fc - cov) * w.chest
        }
        return (pos, cov)
    }

    /// Convenience for tests / one-off use: builds the frame then deforms.
    public func deform(restPos: SIMD3<Float>, restCov: simd_float3x3,
                       w: SplatRegionWeights, pose: CompanionPose, bounds b: SplatBounds)
        -> (pos: SIMD3<Float>, cov: simd_float3x3) {
        deform(restPos: restPos, restCov: restCov, w: w, frame: frame(pose: pose, bounds: b))
    }
}
