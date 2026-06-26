//
//  CompanionMotionTests.swift
//  BeagleCoreTests
//
//  The companion's shared motion brain — pure functions mapping state
//  (flow/sleep/listening/breath) → a continuous pose that drives BOTH the vector
//  BeagleFigure and the photoreal splat (ears/tail/head/breath/blink).
//

import Testing
import Foundation
@testable import BeagleCore

@Suite("CompanionMotion")
struct CompanionMotionTests {

    private func signChanges(_ f: (TimeInterval) -> Double, over span: TimeInterval, step: TimeInterval = 0.01) -> Int {
        var count = 0
        var prev = f(0)
        var t = step
        while t <= span {
            let v = f(t)
            if (v >= 0) != (prev >= 0) { count += 1 }
            prev = v
            t += step
        }
        return count
    }

    // MARK: - Energy

    @Test func energyHigherInFlowThanStress() {
        #expect(CompanionMotion(flowState: "FLOW").energy > CompanionMotion(flowState: "STRESS").energy)
    }

    @Test func listeningRaisesEnergy() {
        let calm = CompanionMotion(flowState: "FLOW", listening: false).energy
        let attentive = CompanionMotion(flowState: "FLOW", listening: true).energy
        #expect(attentive > calm)
    }

    @Test func energyAlwaysInUnitRange() {
        for state in [nil, "FLOW", "STRESS", "other"] as [String?] {
            for listening in [true, false] {
                let e = CompanionMotion(flowState: state, listening: listening).energy
                #expect(e >= 0 && e <= 1)
            }
        }
    }

    // MARK: - Breath

    @Test func breathStaysBounded() {
        let m = CompanionMotion(flowState: "FLOW")
        for i in 0..<200 {
            let b = m.pose(at: Double(i) * 0.05).breath
            #expect(b >= -1.0001 && b <= 1.0001)
        }
    }

    @Test func breathIsPeriodicAtBreathRate() {
        // 15 breaths/min → 4.0s period; breath should return to ~same phase after one period.
        let m = CompanionMotion(flowState: "FLOW", breathRate: 15)
        let a = m.pose(at: 0).breath
        let b = m.pose(at: 4.0).breath
        #expect(abs(a - b) < 0.02)
    }

    // MARK: - Ears

    @Test func earsPerkInFlowNotStress() {
        let flow = CompanionMotion(flowState: "FLOW", listening: true).pose(at: 0).earPerk
        let stress = CompanionMotion(flowState: "STRESS").pose(at: 0).earPerk
        #expect(flow > 0.8)
        #expect(stress < 0.2)
    }

    // MARK: - Tail

    @Test func tailWagsFasterAtHigherEnergy() {
        let flow = CompanionMotion(flowState: "FLOW", listening: true)
        let stress = CompanionMotion(flowState: "STRESS")
        let cFlow = signChanges({ flow.pose(at: $0).tailWag }, over: 4.0)
        let cStress = signChanges({ stress.pose(at: $0).tailWag }, over: 4.0)
        #expect(cFlow > cStress)
    }

    @Test func tailAmplitudeGrowsWithEnergy() {
        let flow = CompanionMotion(flowState: "FLOW", listening: true)
        let stress = CompanionMotion(flowState: "STRESS")
        func peak(_ m: CompanionMotion) -> Double {
            (0..<400).map { abs(m.pose(at: Double($0) * 0.01).tailWag) }.max() ?? 0
        }
        #expect(peak(flow) > peak(stress))
    }

    // MARK: - Head

    @Test func headLiftRequiresListening() {
        #expect(CompanionMotion(flowState: "FLOW", listening: false).pose(at: 0).headLift < 0.1)
        #expect(CompanionMotion(flowState: "FLOW", listening: true).pose(at: 0).headLift > 0.5)
    }

    // MARK: - Blink

    @Test func blinkIsRareButHappens() {
        let m = CompanionMotion()
        var blinks = 0
        let n = 4000
        for i in 0..<n where m.pose(at: Double(i) * 0.01).blink { blinks += 1 }
        let fraction = Double(blinks) / Double(n)
        #expect(blinks > 0)          // it does blink
        #expect(fraction < 0.1)      // but rarely
    }

    // MARK: - Determinism

    @Test func poseIsDeterministic() {
        let m = CompanionMotion(flowState: "FLOW", listening: true)
        #expect(m.pose(at: 1.234) == m.pose(at: 1.234))
    }
}
