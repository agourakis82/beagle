//
//  Truth.swift
//  BeagleCore
//
//  Truth modes — the most important semantic in the platform.
//
//  Every data point carries its epistemic status:
//  - observed:   live, verified, luminous
//  - remembered: cached, still valid (within TTL)
//  - declared:   policy fallback (no live/cached data)
//  - stale:      expired cache
//
//  Maps directly to Sounio's Knowledge<T> concept.
//

import Foundation

public enum TruthMode: String, Codable, Sendable, CaseIterable {
    case observed
    case remembered
    case declared
    case stale

    public var displaySymbol: String {
        switch self {
        case .observed:   return "\u{25CF}"  // ●
        case .remembered: return "\u{25D2}"  // ◒
        case .declared:   return "\u{25CB}"  // ○
        case .stale:      return "\u{25CC}"  // ◌
        }
    }

    public var displayLabel: String { rawValue }

    /// Downgrade a mode to `.stale` once its observation is older than `staleAfter`.
    /// Lets any surface show freshness-aware provenance from a `Truthful`'s observedAt.
    public func aged(_ observedAt: Date?, staleAfter: TimeInterval = 86_400) -> TruthMode {
        guard self != .stale else { return .stale }
        guard let observedAt else { return .stale }
        return Date().timeIntervalSince(observedAt) > staleAfter ? .stale : self
    }
}

public extension Date {
    /// Compact freshness label for truth surfaces: "just now", "12s ago", "2mo ago".
    var truthFreshness: String {
        let s = Date().timeIntervalSince(self)
        switch s {
        case ..<5:         return "just now"
        case ..<60:        return "\(Int(s))s ago"
        case ..<3_600:     return "\(Int(s / 60))m ago"
        case ..<86_400:    return "\(Int(s / 3_600))h ago"
        case ..<2_592_000: return "\(Int(s / 86_400))d ago"
        default:           return "\(Int(s / 2_592_000))mo ago"
        }
    }
}

public extension Optional where Wrapped == String {
    /// Parse a cluster ISO-8601 timestamp string (with or without fractional seconds).
    var iso8601Date: Date? {
        guard let self, !self.isEmpty else { return nil }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: self) ?? ISO8601DateFormatter().date(from: self)
    }
}

/// A truth-aware container: value + epistemic metadata.
/// Equivalent to SolidJS `createTruthSignal` + Sounio `Knowledge<T>`.
public struct Truthful<Value: Sendable>: Sendable {
    public let value: Value?
    public let mode: TruthMode
    public let observedAt: Date?
    public let source: String?
    public let error: String?

    public init(
        value: Value?,
        mode: TruthMode,
        observedAt: Date? = nil,
        source: String? = nil,
        error: String? = nil
    ) {
        self.value = value
        self.mode = mode
        self.observedAt = observedAt
        self.source = source
        self.error = error
    }

    public static func observed(_ value: Value, source: String? = nil) -> Truthful<Value> {
        Truthful(value: value, mode: .observed, observedAt: .now, source: source)
    }

    public static func remembered(_ value: Value, observedAt: Date? = nil, source: String? = nil) -> Truthful<Value> {
        Truthful(value: value, mode: .remembered, observedAt: observedAt, source: source)
    }

    public static func declared(_ value: Value, source: String? = nil) -> Truthful<Value> {
        Truthful(value: value, mode: .declared, source: source)
    }

    public static func staleError(_ error: String, source: String? = nil) -> Truthful<Value> {
        Truthful(value: nil, mode: .stale, source: source, error: error)
    }

    /// Age of the observation in seconds. Returns nil if never observed.
    public var ageSeconds: TimeInterval? {
        guard let observedAt else { return nil }
        return Date.now.timeIntervalSince(observedAt)
    }

    /// Human-readable age: "2s ago", "5m ago", "3h ago".
    public var ageLabel: String {
        guard let age = ageSeconds else { return "—" }
        if age < 60 { return "\(Int(age))s ago" }
        if age < 3600 { return "\(Int(age / 60))m ago" }
        if age < 86400 { return "\(Int(age / 3600))h ago" }
        return "\(Int(age / 86400))d ago"
    }
}

extension Truthful: Equatable where Value: Equatable {}
