//
//  OrchestrationModels.swift
//  BeagleCore
//
import Foundation

// MARK: - A: Agent Plan

public struct AgentPlan: Codable, Equatable, Sendable {
    public let planId: String
    public let title: String
    public let steps: [PlanStep]
    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"; case title; case steps
    }
}

public struct PlanStep: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let tool: String
    public let label: String
    public let depthDefault: Int
    public let depthMin: Int
    public let depthMax: Int
    public let depthLabelMin: String
    public let depthLabelMax: String
    enum CodingKeys: String, CodingKey {
        case id; case tool; case label
        case depthDefault = "depth_default"
        case depthMin = "depth_min"
        case depthMax = "depth_max"
        case depthLabelMin = "depth_label_min"
        case depthLabelMax = "depth_label_max"
    }
}

public struct ConfirmedPlan: Codable, Equatable, Sendable {
    public let planId: String
    public let steps: [ConfirmedStep]
    enum CodingKeys: String, CodingKey { case planId = "plan_id"; case steps }
}

public struct ConfirmedStep: Codable, Equatable, Sendable {
    public let id: String
    public let depth: Int
}

// MARK: - B: Verification

public struct VerificationResult: Codable, Equatable, Sendable {
    public let messageId: String
    public let sources: [EvidenceItem]
    public let temporalConflict: TemporalConflict?
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"; case sources
        case temporalConflict = "temporal_conflict"
    }
}

public struct EvidenceItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let url: URL?
    public let confidence: EvidenceConfidence
    public enum EvidenceConfidence: String, Codable, Equatable, Sendable {
        case cited, inferred, unverified, conflict
    }
}

public struct TemporalConflict: Codable, Equatable, Sendable {
    public let summary: String
    public let noteId: String?
    public let daysAgo: Int
    enum CodingKeys: String, CodingKey {
        case summary; case noteId = "note_id"; case daysAgo = "days_ago"
    }
}

// MARK: - C: Autonomy

public enum AutonomyMode: Int, Codable, Equatable, CaseIterable, Sendable {
    case ask = 0, plan = 1, auto = 2
    public var label: String {
        switch self { case .ask: return "Ask"; case .plan: return "Plan"; case .auto: return "Auto" }
    }
    public var subtitle: String {
        switch self {
        case .ask:  return "Beagle asks before every action"
        case .plan: return "Beagle proposes, then acts"
        case .auto: return "Beagle acts, you review after"
        }
    }
}

// MARK: - Instrumentation

public struct OrchestrationEvent: Codable, Equatable, Sendable {
    public let eventType: String
    public let profileId: String
    public let autonomyMode: AutonomyMode
    public let metadata: [String: String]
    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"; case profileId = "profile_id"
        case autonomyMode = "autonomy_mode"; case metadata
    }
}
