//
//  Posture.swift
//  BeagleCore
//
//  Project posture — always-on / warm / cold.
//  Mirrors the sovereign posture policy.
//

import Foundation

public enum ProjectPosture: String, Codable, Sendable, CaseIterable {
    case alwaysOn = "always-on"
    case warm
    case cold
    case unknown

    public init(from raw: String?) {
        self = ProjectPosture(rawValue: raw ?? "") ?? .unknown
    }

    public var displaySymbol: String {
        switch self {
        case .alwaysOn: return "\u{25CF}"  // ●
        case .warm:     return "\u{25D0}"  // ◐
        case .cold:     return "\u{25CB}"  // ○
        case .unknown:  return "—"
        }
    }

    public var displayLabel: String {
        switch self {
        case .alwaysOn: return "always-on"
        case .warm:     return "warm"
        case .cold:     return "cold"
        case .unknown:  return "unknown"
        }
    }

    /// Operational meaning (from posture policy).
    public var operationalMeaning: String {
        switch self {
        case .alwaysOn:
            return "continuous sovereign habitat — replicas stay at 1"
        case .warm:
            return "persistent sovereign habitat on standby — PVC retained, replicas 0"
        case .cold:
            return "cataloged sovereign habitat activated intentionally"
        case .unknown:
            return "posture not yet determined"
        }
    }
}
