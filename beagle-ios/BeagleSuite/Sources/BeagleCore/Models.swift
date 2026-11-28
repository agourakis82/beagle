//
//  Models.swift
//  BeagleCore
//
//  Core API envelope types, shared internal helpers, and index for the
//  domain models matching cockpit server API responses.
//  All types are Sendable for Swift 6 strict concurrency.
//
//  Domain model files (under Sources/BeagleCore/DomainModels/):
//  - ProjectModels.swift           Project, posture policy, catalog, lane state, mobile summaries, mission control
//  - AgentModels.swift             Agent sessions, delegation, provider registry, routing, console state
//  - WorkbenchTerminalModels.swift Workspace sessions, terminal panes/blocks, authority/memory/bridge, live events
//  - ClusterComputeModels.swift    Inference runtime, cluster truth/summary, research ops, viewer, science & HPC jobs
//  - CognitiveChatModels.swift     Triad, Round Table, thought capture, discussion/chat, HRV, Void/Fractal/Phi, feedback
//  - LiveActivityModels.swift      iOS ActivityKit Live Activity attributes (#if os(iOS))
//

import Foundation

// MARK: - Core API Envelopes

public struct MobileMeta: Decodable, Sendable {
    public let truthMode: String?
    public let generatedAt: String?
    public let requestId: String?

    enum CodingKeys: String, CodingKey {
        case truthMode
        case truthModeSnake = "truth_mode"
        case generatedAt
        case generatedAtSnake = "generated_at"
        case requestId
        case requestIdSnake = "request_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        truthMode =
            try container.decodeIfPresent(String.self, forKey: .truthMode)
            ?? container.decodeIfPresent(String.self, forKey: .truthModeSnake)
        generatedAt =
            try container.decodeIfPresent(String.self, forKey: .generatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .generatedAtSnake)
        requestId =
            try container.decodeIfPresent(String.self, forKey: .requestId)
            ?? container.decodeIfPresent(String.self, forKey: .requestIdSnake)
    }
}

public struct MobileEnvelopeError: Decodable, Sendable {
    public let message: String?
    public let reason: String?
    public let code: String?

    public init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let stringValue = try? singleValue.decode(String.self)
        {
            message = stringValue
            reason = nil
            code = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        message =
            try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .error)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        code = try container.decodeIfPresent(String.self, forKey: .code)
    }

    enum CodingKeys: String, CodingKey {
        case message
        case error
        case reason
        case code
    }
}

public struct MobileEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    public let ok: Bool?
    public let data: T?
    public let error: MobileEnvelopeError?
    public let meta: MobileMeta?
}

// MARK: - Action Response

public struct ActionResponse: Codable, Sendable {
    public let ok: Bool?
    public let actionId: String?
    public let output: String?
    public let truthMode: String?
}

// MARK: - Internal Model Helpers

extension String {
    var nonBlankOrNil: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
