// SynthesisSSEParser.swift — parses one SSE `data:` line from /api/mobile/v1/synthesize.
// Standalone: NO chat imports, NO persistence. Part of the deliberate synthesis surface
// (the hard wall — see docs/superpowers/specs/2026-07-17-ios-synthesis-screen-design.md).
import Foundation

public enum SSEChunk: Equatable {
    case token(String)
    case done(insufficient: Bool, error: String?)
}

public struct SynthesisSSEParser {
    /// One SSE `data:` line → a chunk. Returns nil for comments, blanks, `[DONE]`,
    /// or non-token/non-done payloads.
    public static func parse(line: String) -> SSEChunk? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("data:") else { return nil }
        let json = t.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !json.isEmpty, json != "[DONE]",
              let d = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if obj["done"] as? Bool == true {
            return .done(insufficient: obj["insufficient"] as? Bool ?? false, error: obj["error"] as? String)
        }
        if let tok = obj["token"] as? String { return .token(tok) }
        return nil
    }
}
