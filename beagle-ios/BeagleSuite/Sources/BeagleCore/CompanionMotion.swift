//
//  CompanionMotion.swift
//  BeagleCore — the companion's shared "motion brain"
//
//  The companion's motion is state-driven, never per-token-jittery (research: presence,
//  not a cartoon). Energy rises with FLOW and with listening; breath rides the user's breath
//  rate; ears perk and the tail wags faster/wider with energy; the head lifts to listen; a
//  slow blink keeps it alive. One brain, two bodies: the vector BeagleFigure and the splat.
//

import Foundation

public struct CompanionPose: Equatable, Sendable {
    public var breath: Double      // -1...1 chest oscillation phase
    public var breathScale: Double // ~1 ± amplitude (convenience for scaling)
    public var earPerk: Double     // 0...1 (0 drooped, 1 fully perked)
    public var tailWag: Double     // lateral wag, amplitude grows with energy
    public var headLift: Double    // 0...1 (raised toward the user when listening)
    public var blink: Bool         // eyes closed this instant
    public var energy: Double      // 0...1 overall liveliness
}

public struct CompanionMotion: Sendable {
    public var flowState: String?
    public var sleepQuality01: Double?
    public var listening: Bool
    public var breathRate: Double?  // breaths/min; nil → resting default

    public init(flowState: String? = nil, sleepQuality01: Double? = nil,
                listening: Bool = false, breathRate: Double? = nil) {
        self.flowState = flowState
        self.sleepQuality01 = sleepQuality01
        self.listening = listening
        self.breathRate = breathRate
    }

    /// Overall liveliness, 0…1. FLOW is lively, STRESS is subdued; listening adds attentiveness.
    public var energy: Double {
        let base: Double
        switch flowState?.uppercased() {
        case "FLOW":   base = 0.80
        case "STRESS": base = 0.30
        default:       base = 0.48
        }
        return min(1, base + (listening ? 0.25 : 0))
    }

    /// Breath cycle length in seconds — rides the user's real breath rate when known,
    /// else a calm resting default. Clamped so absurd HR-derived rates can't break it.
    public var breathPeriod: Double {
        guard let r = breathRate, r >= 4 else { return 4.4 }
        return 60.0 / r
    }

    public func pose(at t: TimeInterval) -> CompanionPose {
        let e = energy
        let twoPi = 2 * Double.pi

        let breath = sin(twoPi * t / breathPeriod)          // -1…1
        let breathScale = 1 + 0.02 * breath                 // gentle chest expansion

        let earPerk = min(1, max(0, (e - 0.30) / 0.55))     // FLOW→up, STRESS→drooped

        let wagPeriod = max(0.5, 1.9 - 1.1 * e)             // faster when lively
        let wagAmplitude = 0.30 + 0.60 * e                  // wider when lively
        let tailWag = sin(twoPi * t / wagPeriod) * wagAmplitude

        let headLift = listening ? 0.85 : 0.0               // raises to listen

        let blinkInterval = 5.2, blinkDuration = 0.13
        let blink = t.truncatingRemainder(dividingBy: blinkInterval) > (blinkInterval - blinkDuration)

        return CompanionPose(breath: breath, breathScale: breathScale, earPerk: earPerk,
                             tailWag: tailWag, headLift: headLift, blink: blink, energy: e)
    }
}
