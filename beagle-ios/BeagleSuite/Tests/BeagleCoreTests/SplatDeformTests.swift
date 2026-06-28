//
//  SplatDeformTests.swift
//  BeagleCoreTests — render-free proofs for the splat deformer.
//
//  We can't see a GPU here, so we lean on rotation INVARIANTS: a rigid rotation about a
//  pivot preserves a point's distance to that pivot, and Σ' = R·Σ·Rᵀ preserves trace and
//  determinant. Those let us assert the deform is correct without rendering a single pixel.
//

import Testing
import Foundation
import simd
@testable import BeagleCore

@Suite("SplatDeform")
struct SplatDeformTests {

    // A unit-ish dog box, +Y up, +Z front, centered near origin.
    let bounds = SplatBounds(lo: SIMD3(-0.17, -0.37, -0.50), hi: SIMD3(0.17, 0.37, 0.50))
    let restCov = simd_float3x3(diagonal: SIMD3<Float>(0.0009, 0.0004, 0.0016))  // anisotropic
    let rig = CompanionRig()

    // Representative splats in each region.
    var headSplat: SIMD3<Float> { SIMD3(0.0, 0.34, 0.10) }       // top center
    var earLSplat: SIMD3<Float> { SIMD3(0.15, 0.22, 0.05) }      // top +X side
    var tailSplat: SIMD3<Float> { SIMD3(0.0, 0.05, -0.45) }      // back, mid Y
    var chestSplat: SIMD3<Float> { SIMD3(0.0, 0.0, 0.40) }       // mid-front center

    // MARK: - Region labelling

    @Test func headRegionWinsAtTop() {
        let w = SplatRig.weights(for: headSplat, bounds: bounds)
        #expect(w.head > 0.5)
        #expect(w.tail < 0.05)
    }

    @Test func earRegionPicksTheCorrectSide() {
        let l = SplatRig.weights(for: earLSplat, bounds: bounds)
        #expect(l.earL > 0.2)
        #expect(l.earR == 0)
        let r = SplatRig.weights(for: SIMD3(-0.15, 0.22, 0.05), bounds: bounds)
        #expect(r.earR > 0.2)
        #expect(r.earL == 0)
    }

    @Test func tailRegionAtTheBack() {
        let w = SplatRig.weights(for: tailSplat, bounds: bounds)
        #expect(w.tail > 0.3)
    }

    @Test func chestRegionMidFront() {
        let w = SplatRig.weights(for: chestSplat, bounds: bounds)
        #expect(w.chest > 0.3)
    }

    @Test func bodySplatIsInactive() {
        let w = SplatRig.weights(for: SIMD3(0.0, -0.30, 0.0), bounds: bounds) // lower legs/belly center
        #expect(!w.isActive)
    }

    // MARK: - Deform identity at rest

    @Test func restingPoseIsIdentity() {
        let pose = CompanionMotion(flowState: "FLOW", listening: false).pose(at: 0)
        // force the oscillators to zero phase so breath/tail are 0 at t=0 anyway:
        let calm = CompanionPose(breath: 0, breathScale: 1, earPerk: 0, tailWag: 0, headLift: 0, blink: false, energy: pose.energy)
        let w = SplatRig.weights(for: headSplat, bounds: bounds)
        let (p, c) = rig.deform(restPos: headSplat, restCov: restCov, w: w, pose: calm, bounds: bounds)
        #expect(distance(p, headSplat) < 1e-6)
        #expect(matMaxDiff(c, restCov) < 1e-6)
    }

    // MARK: - Head nod is a rigid rotation about the neck pivot

    @Test func headNodPreservesDistanceToPivot() {
        let pose = CompanionPose(breath: 0, breathScale: 1, earPerk: 0, tailWag: 0, headLift: 1, blink: false, energy: 1)
        let w = SplatRig.weights(for: headSplat, bounds: bounds)
        let (p, _) = rig.deform(restPos: headSplat, restCov: restCov, w: w, pose: pose, bounds: bounds)
        #expect(distance(p, headSplat) > 1e-4)                       // it actually moved
        let pivot = rig.headPivot(bounds)
        #expect(abs(distance(p, pivot) - distance(headSplat, pivot)) < 1e-5)  // rigid about pivot
    }

    @Test func headNodLiftsTheNoseUp() {
        let pose = CompanionPose(breath: 0, breathScale: 1, earPerk: 0, tailWag: 0, headLift: 1, blink: false, energy: 1)
        let w = SplatRig.weights(for: headSplat, bounds: bounds)
        let (p, _) = rig.deform(restPos: headSplat, restCov: restCov, w: w, pose: pose, bounds: bounds)
        #expect(p.y > headSplat.y)   // the front of the head rises toward the user
    }

    // MARK: - Covariance transforms as a rotation (trace & det invariant)

    @Test func covarianceRotationPreservesTraceAndDet() {
        let pose = CompanionPose(breath: 0, breathScale: 1, earPerk: 1, tailWag: 0, headLift: 0, blink: false, energy: 1)
        let w = SplatRig.weights(for: earLSplat, bounds: bounds)
        let (_, c) = rig.deform(restPos: earLSplat, restCov: restCov, w: w, pose: pose, bounds: bounds)
        #expect(abs(trace(c) - trace(restCov)) < 1e-5)
        #expect(abs(c.determinant - restCov.determinant) < 1e-7)
        #expect(matMaxDiff(c, restCov) > 1e-6)   // but it did change orientation
    }

    // MARK: - Breath scales the chest covariance up (inhale)

    @Test func breathInhaleGrowsChest() {
        let pose = CompanionPose(breath: 1, breathScale: 1.035, earPerk: 0, tailWag: 0, headLift: 0, blink: false, energy: 0.5)
        let w = SplatRig.weights(for: chestSplat, bounds: bounds)
        let (_, c) = rig.deform(restPos: chestSplat, restCov: restCov, w: w, pose: pose, bounds: bounds)
        #expect(trace(c) > trace(restCov))   // chest gaussians swell on the inhale
    }

    // helpers
    private func trace(_ m: simd_float3x3) -> Float { m[0][0] + m[1][1] + m[2][2] }
    private func matMaxDiff(_ a: simd_float3x3, _ b: simd_float3x3) -> Float {
        var d: Float = 0
        for i in 0..<3 { for j in 0..<3 { d = max(d, abs(a[i][j] - b[i][j])) } }
        return d
    }
}
