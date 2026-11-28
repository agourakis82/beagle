//
//  DirectBrainClient.swift
//  BeagleCore
//
//  Direct Brain OpenAI / Anthropic / MCP streaming orchestrator entry-point.
//  Extracted components live under Sources/BeagleCore/DirectBrain/:
//  - DirectBrainCredentials.swift
//  - DirectBrainPromptContext.swift
//  - DirectBrainOpenAIStreaming.swift
//  - DirectBrainAnthropicStreaming.swift
//  - DirectBrainTools.swift
//

import Foundation

// MARK: - Direct Brain MoE / OpenAI / Anthropic / MCP Orchestrator

public actor DirectBrainClient {
    public static let shared = DirectBrainClient()

    let session: URLSession
    let skipRemoteMCPTools: Bool

    public init(session: URLSession? = nil, skipRemoteMCPTools: Bool = false) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 300
        self.session = session ?? URLSession(configuration: config)
        self.skipRemoteMCPTools = skipRemoteMCPTools
    }

    // MARK: - Streaming Result & Round Accumulator Types

    public struct OpenAIStreamResult: Sendable {
        public let content: String
        public let model: String
        public let executedTools: [String]

        public init(content: String, model: String, executedTools: [String] = []) {
            self.content = content
            self.model = model
            self.executedTools = executedTools
        }
    }

    struct OpenAIToolCallAccumulator: Sendable {
        var id: String = ""
        var name: String = ""
        var arguments: String = ""
    }

    struct OpenAIRoundResult: Sendable {
        let model: String
        let content: String
        let toolCalls: [OpenAIToolCallAccumulator]
        var outputItemsData: Data? = nil
        var builtInToolsUsed: [String] = []
    }
}
