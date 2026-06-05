//
//  MultimodelChatEvent.swift
//  BeagleCore
//

import Foundation

public struct MultimodelChatEvent: Sendable {
    public let type: String
    public let turnId: String?
    public let provider: String?
    public let label: String?
    public let sourceProvider: String?
    public let text: String?
    public let error: String?
    public let reason: String?
    public let status: String?
    public let truthMode: String?
    public let defaultProviders: [String]?
    public let providers: [MultimodelProvider]?

    public init?(jsonData: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let type = object["type"] as? String
        else { return nil }

        self.type = type
        turnId = object["turnId"] as? String
        provider = object["provider"] as? String
        label = object["label"] as? String
        sourceProvider = object["sourceProvider"] as? String
        text = object["text"] as? String
        error = object["error"] as? String
        reason = object["reason"] as? String
        status = object["status"] as? String
        truthMode = object["truthMode"] as? String
        defaultProviders = object["defaultProviders"] as? [String]

        if let rawProviders = object["providers"] as? [[String: Any]] {
            providers = rawProviders.compactMap { item in
                guard let data = try? JSONSerialization.data(withJSONObject: item) else { return nil }
                return try? JSONDecoder().decode(MultimodelProvider.self, from: data)
            }
        } else {
            providers = nil
        }
    }

    public var streamKey: String {
        "\(turnId ?? "turn"):\(provider ?? label ?? sourceProvider ?? "agent")"
    }
}
