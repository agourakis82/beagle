//
//  DirectBrainTools.swift
//  BeagleCore
//
//  Tool schema builders (OpenAI Responses 2026 namespaces, legacy OpenAI,
//  Anthropic) and unified Apple Device / Science / GraphRAG / MCP dispatcher.
//

import Foundation

extension DirectBrainClient {
    // MARK: - Beagle MCP & Cluster Memory Tool Definitions + Dispatcher

    func buildAnthropicTools(mcpTools: [MCPToolSummary]) -> [[String: Any]] {
        let openAITools = buildOpenAITools(mcpTools: mcpTools)
        return openAITools.compactMap { item in
            guard let fn = item["function"] as? [String: Any],
                  let name = fn["name"] as? String else { return nil }
            return [
                "name": name,
                "description": (fn["description"] as? String) ?? "Ferramenta Beagle MCP (\(name))",
                "input_schema": (fn["parameters"] as? [String: Any]) ?? ["type": "object", "properties": [String: Any]()]
            ]
        }
    }

    nonisolated private func buildOpenAITools(mcpTools: [MCPToolSummary]) -> [[String: Any]] {
        var tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "beagle_search_memory",
                    "description": "Busca na memória episódica, semântica e GraphRAG++ do cluster Beagle (conversas passadas, notas, hipóteses científicas, histórico médico/fisiológico e projetos).",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "Consulta semântica ou palavras-chave para buscar no GraphRAG++ e memória do cluster."
                            ]
                        ],
                        "required": ["query"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "beagle_store_memory",
                    "description": "Salva imediatamente uma memória importante, decisão, insight científico, evento clínico ou fato pessoal no cluster Beagle (GraphRAG / ChronoSelf).",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "text": [
                                "type": "string",
                                "description": "Conteúdo completo da memória ou insight a ser persistido permanentemente no cluster."
                            ],
                            "tags": [
                                "type": "string",
                                "description": "Tags separadas por vírgula (ex: 'fisioma,cetamina,pbpk,familia')."
                            ]
                        ],
                        "required": ["text"]
                    ]
                ]
            ]
        ]

        tools.append(contentsOf: ScienceAndWebBridge.openAIToolDefinitions())
        tools.append(contentsOf: AppleDeviceToolsBridge.openAIToolDefinitions())
        tools.append(contentsOf: GrokBotBridgeClient.openAIToolDefinitions())

        var builtinNames: Set<String> = ["beagle_search_memory", "beagle_store_memory"]
        builtinNames.formUnion(ScienceAndWebBridge.toolNames)
        builtinNames.formUnion(AppleDeviceToolsBridge.nativeToolNames)
        builtinNames.formUnion(GrokBotBridgeClient.toolNames)
        let encoder = JSONEncoder()

        for tool in mcpTools.prefix(20) where !builtinNames.contains(tool.name) {
            var paramsObj: [String: Any] = [
                "type": "object",
                "properties": [:] as [String: Any]
            ]
            if let schema = tool.inputSchema,
               let data = try? encoder.encode(schema),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                paramsObj = dict
            }
            tools.append([
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description ?? tool.title ?? "Ferramenta do servidor Beagle MCP (\(tool.name))",
                    "parameters": paramsObj
                ]
            ])
        }

        return tools
    }

    private static func flattenResponsesFunction(_ legacyOrFlat: [String: Any], deferLoading: Bool) -> [String: Any]? {
        if let fn = legacyOrFlat["function"] as? [String: Any],
           let name = fn["name"] as? String, !name.isEmpty {
            var flattened = fn
            flattened["type"] = "function"
            flattened["strict"] = false
            if deferLoading {
                flattened["defer_loading"] = true
            }
            return flattened
        }
        if (legacyOrFlat["type"] as? String) == "function",
           let name = legacyOrFlat["name"] as? String, !name.isEmpty {
            var flattened = legacyOrFlat
            flattened["strict"] = false
            if deferLoading {
                flattened["defer_loading"] = true
            }
            return flattened
        }
        return nil
    }

    nonisolated func buildResponsesTools2026(
        mcpTools: [MCPToolSummary],
        model: String,
        enableNativeWebSearch: Bool,
        enableToolSearch: Bool
    ) -> [[String: Any]] {
        let canUseToolSearch = enableToolSearch && OpenAIModelCatalog.supportsToolSearch(model)
        let allLegacy = buildOpenAITools(mcpTools: [])
        let immediateNames: Set<String> = [
            "beagle_search_memory",
            "beagle_store_memory",
            "beagle_lookup_bula_pcdt"
        ]

        var responseTools: [[String: Any]] = []

        // 1. Immediate high-frequency & clinical safety tools (always loaded in context)
        for item in allLegacy {
            let name = (item["function"] as? [String: Any])?["name"] as? String ?? (item["name"] as? String ?? "")
            if immediateNames.contains(name),
               let flat = Self.flattenResponsesFunction(item, deferLoading: false) {
                responseTools.append(flat)
            }
        }

        // 2. Science & Literature tools
        let scienceDefs = ScienceAndWebBridge.openAIToolDefinitions().compactMap { item -> [String: Any]? in
            let name = (item["function"] as? [String: Any])?["name"] as? String ?? ""
            if immediateNames.contains(name) { return nil }
            if enableNativeWebSearch && name == "beagle_web_search" { return nil }
            return Self.flattenResponsesFunction(item, deferLoading: canUseToolSearch)
        }

        // 3. Apple Device tools
        let appleDefs = AppleDeviceToolsBridge.openAIToolDefinitions().compactMap { item -> [String: Any]? in
            Self.flattenResponsesFunction(item, deferLoading: canUseToolSearch)
        }

        // 4. Grok Bot Bridge tools (webhook routines)
        let grokBotDefs = GrokBotBridgeClient.openAIToolDefinitions().compactMap { item -> [String: Any]? in
            Self.flattenResponsesFunction(item, deferLoading: canUseToolSearch)
        }

        // 5. Live Beagle MCP server tools (up to 32 tools, chunked < 10 per namespace)
        var builtinNames: Set<String> = ["beagle_search_memory", "beagle_store_memory"]
        builtinNames.formUnion(ScienceAndWebBridge.toolNames)
        builtinNames.formUnion(AppleDeviceToolsBridge.nativeToolNames)
        builtinNames.formUnion(GrokBotBridgeClient.toolNames)
        let encoder = JSONEncoder()
        var mcpDefs: [[String: Any]] = []
        for tool in mcpTools.prefix(32) where !builtinNames.contains(tool.name) {
            var paramsObj: [String: Any] = [
                "type": "object",
                "properties": [:] as [String: Any]
            ]
            if let schema = tool.inputSchema,
               let data = try? encoder.encode(schema),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                paramsObj = dict
            }
            var flat: [String: Any] = [
                "type": "function",
                "name": tool.name,
                "description": tool.description ?? tool.title ?? "Ferramenta do servidor Beagle MCP (\(tool.name))",
                "strict": false,
                "parameters": paramsObj
            ]
            if canUseToolSearch {
                flat["defer_loading"] = true
            }
            mcpDefs.append(flat)
        }

        if canUseToolSearch {
            var addedDeferredNamespace = false

            if !scienceDefs.isEmpty {
                for (idx, chunk) in Self.chunkTools(scienceDefs, size: 8).enumerated() {
                    let nsName = idx == 0 ? "science_literature" : "science_literature_\(idx + 1)"
                    responseTools.append([
                        "type": "namespace",
                        "name": nsName,
                        "description": "Literatura biomédica e científica (PubMed, arXiv, Semantic Scholar, ClinicalTrials.gov, ChEMBL e extração de artigos web).",
                        "tools": chunk
                    ])
                    addedDeferredNamespace = true
                }
            }

            if !appleDefs.isEmpty {
                for (idx, chunk) in Self.chunkTools(appleDefs, size: 9).enumerated() {
                    let nsName = idx == 0 ? "apple_device" : "apple_device_\(idx + 1)"
                    responseTools.append([
                        "type": "namespace",
                        "name": nsName,
                        "description": "Ecossistema nativo do iPhone de Demetrios (Calendário EventKit, Lembretes, HealthKit/HRV/Sono, Contatos, Clipboard e Localização).",
                        "tools": chunk
                    ])
                    addedDeferredNamespace = true
                }
            }

            if !grokBotDefs.isEmpty {
                responseTools.append([
                    "type": "namespace",
                    "name": "grok_bot",
                    "description": "Delegação assíncrona e automação de rotinas no Grok Bot (xAI / SpaceXSI) via Webhook autenticado.",
                    "tools": grokBotDefs
                ])
                addedDeferredNamespace = true
            }

            if !mcpDefs.isEmpty {
                for (idx, chunk) in Self.chunkTools(mcpDefs, size: 8).enumerated() {
                    let nsName = idx == 0 ? "beagle_mcp" : "beagle_mcp_\(idx + 1)"
                    responseTools.append([
                        "type": "namespace",
                        "name": nsName,
                        "description": "Ferramentas remotas do cluster Beagle HPC, exocórtex e pipelines científicos via MCP.",
                        "tools": chunk
                    ])
                    addedDeferredNamespace = true
                }
            }

            if addedDeferredNamespace {
                responseTools.append(["type": "tool_search"])
            }
        } else {
            responseTools.append(contentsOf: scienceDefs)
            responseTools.append(contentsOf: appleDefs)
            responseTools.append(contentsOf: grokBotDefs)
            responseTools.append(contentsOf: mcpDefs.prefix(20))
        }

        if enableNativeWebSearch {
            responseTools.append(["type": "web_search"])
        }

        return responseTools
    }

    private static func chunkTools(_ items: [[String: Any]], size: Int) -> [[[String: Any]]] {
        guard size > 0, !items.isEmpty else { return [] }
        var chunks: [[[String: Any]]] = []
        var idx = 0
        while idx < items.count {
            let end = min(idx + size, items.count)
            chunks.append(Array(items[idx..<end]))
            idx = end
        }
        return chunks
    }

    func executeBeagleOrMCPTool(
        name: String,
        argumentsJSON: String,
        projectSlug: String?
    ) async -> String {
        let args: [String: Any] = {
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            return obj
        }()

        if AppleDeviceToolsBridge.isNativeTool(name) {
            return await AppleDeviceToolsBridge.shared.execute(name: name, args: args)
        }
        if GrokBotBridgeClient.isGrokBotTool(name) {
            var enrichedArgs = args
            let fallbackText = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if enrichedArgs.isEmpty && !fallbackText.isEmpty && name == "delegate_to_grok_bot" {
                enrichedArgs["task"] = fallbackText
            }
            return await GrokBotBridgeClient.shared.execute(name: name, args: enrichedArgs, projectSlug: projectSlug)
        }
        if ScienceAndWebBridge.isScienceOrWebTool(name) {
            var enrichedArgs = args
            let fallbackText = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if enrichedArgs.isEmpty && !fallbackText.isEmpty {
                enrichedArgs["query"] = fallbackText
                enrichedArgs["identifier_or_query"] = fallbackText
                enrichedArgs["url"] = fallbackText
            }
            return await ScienceAndWebBridge.shared.execute(name: name, args: enrichedArgs)
        }

        switch name {
        case "beagle_search_memory":
            let query = (args["query"] as? String) ?? argumentsJSON
            let graph = await BeagleClient.shared.graphRagQuery(
                query: query,
                scope: projectSlug,
                maxItems: 8
            )
            var out: [String] = []
            if let val = graph.value, !val.evidence.isEmpty {
                for item in val.evidence.prefix(8) {
                    out.append("- [\(item.atomType)] \(item.text)")
                }
            }
            if out.isEmpty {
                let fallback = await BeagleClient.shared.queryMemory(query: query)
                if let resp = fallback.value?.response, !resp.isEmpty {
                    out.append(resp)
                }
            }
            return out.isEmpty ? "Nenhum registro encontrado no cluster para '\(query)'." : out.joined(separator: "\n")

        case "beagle_store_memory":
            let text = (args["text"] as? String) ?? (args["thought"] as? String) ?? argumentsJSON
            let cap = await BeagleClient.shared.captureThought(
                text: text,
                source: "beagle-mcp-direct"
            )
            return cap.value?.response ?? "Memória salva no cluster Beagle."

        default:
            return await BeagleMCPClient.shared.executeToolForLLM(name: name, argumentsJSON: argumentsJSON)
        }
    }
}
