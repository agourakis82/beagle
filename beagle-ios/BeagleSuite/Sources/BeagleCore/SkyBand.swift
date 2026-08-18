//
//  SkyBand.swift
//  BeagleCore — named geomagnetic band (Kp + Dst)
//
//  Companion to the existing SpaceWeatherStore: turns raw Kp/Dst into a named state
//  (calm/active/storm) so surfaces speak the sky instead of reciting numbers. Severity is
//  the WORST of Kp and Dst — Dst weighs as much as Kp (the user's call).
//

import Foundation

public enum SkyBand: String, Sendable, CaseIterable {
    case calm
    case active
    case storm

    /// Kp 0–9 band: calm <4, active 4–5, storm ≥5.
    public static func fromKp(_ kp: Double?) -> SkyBand? {
        guard let kp else { return nil }
        if kp < 4 { return .calm }
        if kp < 5 { return .active }
        return .storm
    }

    /// Dst nT band (more negative = deeper): calm >−20, active −20…−50, storm ≤−50.
    public static func fromDst(_ dst: Double?) -> SkyBand? {
        guard let dst else { return nil }
        if dst > -20 { return .calm }
        if dst > -50 { return .active }
        return .storm
    }

    /// Worst of Kp and Dst — nil inputs ignored; both nil → calm.
    public static func from(kp: Double?, dst: Double?) -> SkyBand {
        let bands = [fromKp(kp), fromDst(dst)].compactMap { $0 }
        return bands.max(by: { $0.severity < $1.severity }) ?? .calm
    }

    /// 0 calm, 1 active, 2 storm.
    public var severity: Int {
        switch self {
        case .calm:   return 0
        case .active: return 1
        case .storm:  return 2
        }
    }

    public var isStorm: Bool { self == .storm }

    /// pt-BR named label (strip badge).
    public var label: String {
        switch self {
        case .calm:   return "calmo"
        case .active: return "agitado"
        case .storm:  return "tempestade"
        }
    }

    /// Short narrative phrase for surfaces that speak the sky.
    public var narrative: String {
        switch self {
        case .calm:   return "céu tranquilo"
        case .active: return "céu agitado"
        case .storm:  return "céu em tempestade"
        }
    }
}
