//
//  DirectBrainOpenAIStreaming.swift
//  BeagleCore
//
//  OpenAI Responses API streaming orchestrator with prompt caching,
//  tool search, native web search, URL citations, and multi-round tool execution.
//

import Foundation

extension DirectBrainClient {
    // MARK: - OpenAI Direct Streaming (GPT-6.2 Responses API + Prompt Caching + Tool Search + Web Search)

    public func streamOpenAI(
        model: String,
        systemPrompt: String,
        developerPrefix: String? = nil,
        turnInstructions: String? = nil,
        reasoningEffort: String? = nil,
        enableNativeWebSearch: Bool? = nil,
        enableToolSearch: Bool? = nil,
        history: [[String: String]] = [],
        turns: [DirectBrainTurn] = [],
        projectSlug: String?,
        onStatus: @Sendable @escaping (String) async -> Void,
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws -> OpenAIStreamResult {
        let apiKey = DirectBrainCredentials.openAIKey
        guard !apiKey.isEmpty else {
            throw NSError(domain: "DirectBrainClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chave OpenAI não configurada."])
        }

        let resolvedModel: String = {
            if model == "moe" || model.isEmpty {
                return DirectBrainCredentials.openAIModel
            }
            return model
        }()

        let resolvedEffort = reasoningEffort ?? DirectBrainCredentials.openAIReasoningEffort.rawValue
        let useWebSearch = enableNativeWebSearch ?? DirectBrainCredentials.enableNativeWebSearch
        let useToolSearch = enableToolSearch ?? DirectBrainCredentials.enableToolSearch

        // Build OpenAI Responses 2026 tools (immediate safety/memory + deferred namespaces + tool_search + web_search)
        let mcpTools = skipRemoteMCPTools ? [] : await BeagleMCPClient.shared.availableTools()
        let openAITools = buildResponsesTools2026(
            mcpTools: mcpTools,
            model: resolvedModel,
            enableNativeWebSearch: useWebSearch,
            enableToolSearch: useToolSearch
        )

        let stableDeveloperPrompt = (developerPrefix?.isEmpty == false) ? developerPrefix! : systemPrompt
        var messages: [[String: Any]] = [
            ["role": "developer", "content": stableDeveloperPrompt]
        ]
        if !turns.isEmpty {
            for turn in turns {
                if let b64 = turn.imageBase64, !b64.isEmpty, turn.role == "user" {
                    let mediaType = turn.imageMediaType ?? "image/jpeg"
                    let promptText = turn.content.isEmpty ? "Analise esta imagem em detalhes." : turn.content
                    messages.append([
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": promptText
                            ],
                            [
                                "type": "image_url",
                                "image_url": [
                                    "url": "data:\(mediaType);base64,\(b64)",
                                    "detail": "high"
                                ]
                            ]
                        ] as [[String: Any]]
                    ])
                } else if !turn.content.isEmpty {
                    messages.append([
                        "role": turn.role,
                        "content": turn.content
                    ])
                }
            }
        } else {
            for msg in history {
                if let role = msg["role"], let content = msg["content"], !content.isEmpty {
                    messages.append([
                        "role": role,
                        "content": content
                    ])
                }
            }
        }

        var executedToolNames: [String] = []

        // Up to 6 agentic tool-call rounds before final streaming synthesis
        for _ in 0..<6 {
            let turnResult = try await performOpenAIStreamRound(
                apiKey: apiKey,
                model: resolvedModel,
                messages: messages,
                tools: openAITools,
                instructions: turnInstructions,
                reasoningEffort: resolvedEffort,
                onStatus: onStatus,
                onToken: onToken
            )

            for builtIn in turnResult.builtInToolsUsed where !executedToolNames.contains(builtIn) {
                executedToolNames.append(builtIn)
            }

            if turnResult.toolCalls.isEmpty {
                return OpenAIStreamResult(
                    content: turnResult.content,
                    model: turnResult.model,
                    executedTools: executedToolNames
                )
            }

            // Replay all output items (reasoning.encrypted_content, tool_search_call/output, function_call with namespace)
            if let outputData = turnResult.outputItemsData,
               let output = try JSONSerialization.jsonObject(with: outputData) as? [[String: Any]] {
                messages.append(contentsOf: output)
            }

            // Execute each tool call against Apple Device Tools / Cluster GraphRAG / BeagleMCPClient
            for tc in turnResult.toolCalls {
                executedToolNames.append(tc.name)
                await onStatus(AppleDeviceToolsBridge.humanStatus(for: tc.name))
                let output = await executeBeagleOrMCPTool(
                    name: tc.name,
                    argumentsJSON: tc.arguments,
                    projectSlug: projectSlug
                )
                messages.append([
                    "type": "function_call_output",
                    "call_id": tc.id,
                    "output": output
                ])
            }
        }

        // Final synthesis round without further tool calls
        let finalResult = try await performOpenAIStreamRound(
            apiKey: apiKey,
            model: resolvedModel,
            messages: messages,
            tools: [],
            instructions: turnInstructions,
            reasoningEffort: resolvedEffort,
            onStatus: onStatus,
            onToken: onToken
        )
        for builtIn in finalResult.builtInToolsUsed where !executedToolNames.contains(builtIn) {
            executedToolNames.append(builtIn)
        }
        return OpenAIStreamResult(
            content: finalResult.content,
            model: finalResult.model,
            executedTools: executedToolNames
        )
    }

    /// Adapts existing conversation turns to Responses input while leaving response
    /// items (reasoning, tool_search, and function calls) intact for stateless continuations.
    static func responsesInput(_ messages: [[String: Any]]) -> [[String: Any]] {
        messages.map { message in
            guard let parts = message["content"] as? [[String: Any]] else { return message }
            var converted = message
            converted["content"] = parts.map { part -> [String: Any] in
                if part["type"] as? String == "text" {
                    return ["type": "input_text", "text": part["text"] as? String ?? ""]
                }
                if part["type"] as? String == "image_url",
                   let image = part["image_url"] as? [String: Any] {
                    return [
                        "type": "input_image",
                        "image_url": image["url"] as? String ?? "",
                        "detail": image["detail"] as? String ?? "auto"
                    ]
                }
                return part
            }
            return converted
        }
    }

    func performOpenAIStreamRound(
        apiKey: String,
        model: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        instructions: String? = nil,
        reasoningEffort: String? = nil,
        onStatus: (@Sendable (String) async -> Void)? = nil,
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws -> OpenAIRoundResult {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "input": Self.responsesInput(messages),
            "stream": true,
            "store": false,
            "include": ["reasoning.encrypted_content"]
        ]
        if let instructions, !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["instructions"] = instructions
        }
        if let effort = OpenAIReasoningEffort.sanitizedEffort(reasoningEffort, forModel: model) {
            body["reasoning"] = ["effort": effort]
        }
        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                if let type = tool["type"] as? String,
                   type == "namespace" || type == "tool_search" || type == "web_search" || type == "mcp" {
                    return tool
                }
                guard let function = tool["function"] as? [String: Any] else { return tool }
                var flattened = function
                flattened["type"] = "function"
                // Existing MCP schemas contain optional fields; preserve that contract.
                flattened["strict"] = false
                return flattened
            }
            body["tool_choice"] = "auto"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            var errText = ""
            for try await line in bytes.lines {
                errText += line
                if errText.count > 600 { break }
            }
            throw NSError(domain: "DirectBrainClient", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errText])
        }

        var fullText = ""
        var announcedWebSearch = false
        var announcedToolSearch = false
        for try await rawLine in bytes.lines {
            try Task.checkCancellation()
            guard rawLine.hasPrefix("data:") else { continue }
            let payload = rawLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { throw URLError(.cannotParseResponse) }
            switch type {
            case "response.web_search_call.in_progress", "response.web_search_call.searching":
                if !announcedWebSearch {
                    announcedWebSearch = true
                    await onStatus?(AppleDeviceToolsBridge.humanStatus(for: "openai_web_search"))
                }
            case "response.tool_search_call.in_progress", "response.tool_search_call.searching":
                if !announcedToolSearch {
                    announcedToolSearch = true
                    await onStatus?(AppleDeviceToolsBridge.humanStatus(for: "openai_tool_search"))
                }
            case "response.output_text.delta", "response.refusal.delta":
                if let delta = event["delta"] as? String {
                    fullText += delta
                    await onToken(delta)
                }
            case "response.completed":
                guard let completed = event["response"] as? [String: Any],
                      completed["status"] as? String == "completed",
                      let output = completed["output"] as? [[String: Any]] else {
                    throw URLError(.cannotParseResponse)
                }
                let calls = try output.compactMap { item -> OpenAIToolCallAccumulator? in
                    guard item["type"] as? String == "function_call" else { return nil }
                    guard let id = item["call_id"] as? String, !id.isEmpty,
                          let name = item["name"] as? String, !name.isEmpty,
                          let arguments = item["arguments"] as? String else {
                        throw URLError(.cannotParseResponse)
                    }
                    return OpenAIToolCallAccumulator(id: id, name: name, arguments: arguments)
                }
                var builtIns: [String] = []
                for item in output {
                    let itemType = item["type"] as? String
                    if itemType == "web_search_call", !builtIns.contains("openai_web_search") {
                        builtIns.append("openai_web_search")
                    } else if itemType == "tool_search_call", !builtIns.contains("openai_tool_search") {
                        builtIns.append("openai_tool_search")
                    }
                }
                if fullText.isEmpty {
                    fullText = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                        .compactMap { ($0["text"] as? String) ?? ($0["refusal"] as? String) }
                        .joined()
                    if !fullText.isEmpty { await onToken(fullText) }
                }
                // Surface verified URL citations from hosted web_search if not already linked inline
                let citations = Self.extractURLCitations(from: output)
                let missingCitations = citations.filter { !fullText.contains($0.url) }
                if !missingCitations.isEmpty && calls.isEmpty {
                    let footerLines = missingCitations.prefix(5).map { "- [\($0.title)](\($0.url))" }
                    let footer = "\n\nFontes:\n" + footerLines.joined(separator: "\n")
                    fullText += footer
                    await onToken(footer)
                }
                return OpenAIRoundResult(
                    model: completed["model"] as? String ?? model,
                    content: fullText,
                    toolCalls: calls,
                    outputItemsData: try JSONSerialization.data(withJSONObject: output),
                    builtInToolsUsed: builtIns
                )
            case "response.failed", "response.incomplete", "error":
                // Do not mistake a partial reply or a failed tool request for success.
                throw NSError(domain: "DirectBrainClient", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "OpenAI Responses: \(type)"])
            default:
                break
            }
        }
        // A transport disconnect without response.completed is not a completed turn.
        throw URLError(.networkConnectionLost)
    }

    static func extractURLCitations(from output: [[String: Any]]) -> [(title: String, url: String)] {
        var seenURLs: Set<String> = []
        var citations: [(title: String, url: String)] = []
        for item in output {
            guard let contents = item["content"] as? [[String: Any]] else { continue }
            for block in contents {
                guard let annotations = block["annotations"] as? [[String: Any]] else { continue }
                for ann in annotations where (ann["type"] as? String) == "url_citation" {
                    guard let url = ann["url"] as? String, !url.isEmpty, !seenURLs.contains(url) else { continue }
                    seenURLs.insert(url)
                    let rawTitle = (ann["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = (rawTitle?.isEmpty == false) ? rawTitle! : (URL(string: url)?.host ?? url)
                    citations.append((title: title, url: url))
                }
            }
        }
        return citations
    }
}
