//
//  DirectBrainAnthropicStreaming.swift
//  BeagleCore
//
//  Anthropic Claude direct streaming orchestrator with vision support
//  and multi-round Beagle MCP tool calling.
//

import Foundation

extension DirectBrainClient {
    // MARK: - Anthropic Claude Direct Streaming with Vision + Beagle MCP Tool Calling

    public func streamAnthropic(
        model: String,
        systemPrompt: String,
        history: [[String: String]] = [],
        turns: [DirectBrainTurn] = [],
        projectSlug: String? = nil,
        onStatus: (@Sendable (String) async -> Void)? = nil,
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws -> OpenAIStreamResult {
        let apiKey = DirectBrainCredentials.anthropicKey
        guard !apiKey.isEmpty else {
            throw NSError(domain: "DirectBrainClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chave Anthropic não configurada."])
        }

        let resolvedModel: String = {
            if model.contains("opus") { return "claude-opus-4-8" }
            if model.contains("sonnet-5") { return "claude-sonnet-5" }
            return model.isEmpty ? "claude-sonnet-5" : model
        }()

        let mcpTools = await BeagleMCPClient.shared.availableTools()
        let anthropicTools = buildAnthropicTools(mcpTools: mcpTools)

        var messages: [[String: Any]] = []
        if !turns.isEmpty {
            for turn in turns {
                let normalizedRole = turn.role == "assistant" ? "assistant" : "user"
                if let b64 = turn.imageBase64, !b64.isEmpty, normalizedRole == "user" {
                    let mediaType = turn.imageMediaType ?? "image/jpeg"
                    let promptText = turn.content.isEmpty ? "Analise esta imagem em detalhes." : turn.content
                    messages.append([
                        "role": "user",
                        "content": [
                            [
                                "type": "image",
                                "source": [
                                    "type": "base64",
                                    "media_type": mediaType,
                                    "data": b64
                                ]
                            ],
                            [
                                "type": "text",
                                "text": promptText
                            ]
                        ] as [[String: Any]]
                    ])
                } else if !turn.content.isEmpty {
                    messages.append([
                        "role": normalizedRole,
                        "content": turn.content
                    ])
                }
            }
        } else {
            messages = history.compactMap { msg in
                guard let role = msg["role"], let content = msg["content"], !content.isEmpty else { return nil }
                return ["role": role == "assistant" ? "assistant" : "user", "content": content]
            }
        }

        var executedToolNames: [String] = []

        for _ in 0..<3 {
            let round = try await performAnthropicStreamRound(
                apiKey: apiKey,
                model: resolvedModel,
                systemPrompt: systemPrompt,
                messages: messages,
                tools: anthropicTools,
                onToken: onToken
            )

            if round.toolCalls.isEmpty {
                return OpenAIStreamResult(
                    content: round.content,
                    model: round.model,
                    executedTools: executedToolNames
                )
            }

            var assistantBlocks: [[String: Any]] = []
            if !round.content.isEmpty {
                assistantBlocks.append([
                    "type": "text",
                    "text": round.content
                ])
            }
            for tc in round.toolCalls {
                let parsedInput: Any = {
                    if let d = tc.arguments.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d) {
                        return obj
                    }
                    return [String: Any]()
                }()
                assistantBlocks.append([
                    "type": "tool_use",
                    "id": tc.id,
                    "name": tc.name,
                    "input": parsedInput
                ])
            }
            messages.append([
                "role": "assistant",
                "content": assistantBlocks
            ])

            var toolResultBlocks: [[String: Any]] = []
            for tc in round.toolCalls {
                executedToolNames.append(tc.name)
                await onStatus?(AppleDeviceToolsBridge.humanStatus(for: tc.name))
                let output = await executeBeagleOrMCPTool(
                    name: tc.name,
                    argumentsJSON: tc.arguments,
                    projectSlug: projectSlug
                )
                toolResultBlocks.append([
                    "type": "tool_result",
                    "tool_use_id": tc.id,
                    "content": output
                ])
            }
            messages.append([
                "role": "user",
                "content": toolResultBlocks
            ])
        }

        let finalRound = try await performAnthropicStreamRound(
            apiKey: apiKey,
            model: resolvedModel,
            systemPrompt: systemPrompt,
            messages: messages,
            tools: [],
            onToken: onToken
        )
        return OpenAIStreamResult(
            content: finalRound.content,
            model: finalRound.model,
            executedTools: executedToolNames
        )
    }

    private func performAnthropicStreamRound(
        apiKey: String,
        model: String,
        systemPrompt: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws -> OpenAIRoundResult {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": messages,
            "stream": true
        ]
        if !tools.isEmpty {
            body["tools"] = tools
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var errText = ""
            for try await line in bytes.lines {
                errText += line
                if errText.count > 600 { break }
            }
            if http.statusCode == 404 || http.statusCode == 400 {
                let fallbackModel: String? = {
                    switch model {
                    case "claude-opus-4-8": return "claude-opus-4-6"
                    case "claude-opus-4-6": return "claude-3-7-sonnet-latest"
                    case "claude-sonnet-5": return "claude-sonnet-4-6"
                    case "claude-sonnet-4-6": return "claude-3-7-sonnet-latest"
                    default: return nil
                    }
                }()
                if let fallbackModel {
                    return try await performAnthropicStreamRound(
                        apiKey: apiKey,
                        model: fallbackModel,
                        systemPrompt: systemPrompt,
                        messages: messages,
                        tools: tools,
                        onToken: onToken
                    )
                }
            }
            throw NSError(domain: "DirectBrainClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errText])
        }

        var fullText = ""
        var toolCallsByIndex: [Int: OpenAIToolCallAccumulator] = [:]

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }
            if type == "content_block_start",
               let index = json["index"] as? Int,
               let block = json["content_block"] as? [String: Any],
               (block["type"] as? String) == "tool_use" {
                var acc = OpenAIToolCallAccumulator()
                acc.id = (block["id"] as? String) ?? "tool_\(index)"
                acc.name = (block["name"] as? String) ?? ""
                toolCallsByIndex[index] = acc
            } else if type == "content_block_delta",
                      let delta = json["delta"] as? [String: Any] {
                let deltaType = (delta["type"] as? String) ?? ""
                if let text = delta["text"] as? String, !text.isEmpty {
                    fullText += text
                    await onToken(text)
                } else if deltaType == "input_json_delta",
                          let index = json["index"] as? Int,
                          let partial = delta["partial_json"] as? String {
                    var acc = toolCallsByIndex[index] ?? OpenAIToolCallAccumulator()
                    acc.arguments += partial
                    toolCallsByIndex[index] = acc
                }
            }
        }

        let orderedCalls = toolCallsByIndex.keys.sorted().compactMap { idx -> OpenAIToolCallAccumulator? in
            guard let tc = toolCallsByIndex[idx], !tc.name.isEmpty else { return nil }
            return tc
        }
        return OpenAIRoundResult(model: model, content: fullText, toolCalls: orderedCalls)
    }
}
