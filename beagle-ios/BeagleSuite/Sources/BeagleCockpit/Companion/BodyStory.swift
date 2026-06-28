//
//  BodyStory.swift
//  BeagleCockpit — Companion chat
//
//  Body-as-STORY, never metrics (Gaggioli: the body is a story, not a dashboard number).
//  Weaves the user's physiological snapshot (sleep, heart/flow from HRV, resting HR) into
//  a warm, attuned opening line + a caring follow-up. This is the #1 aliveness lever from
//  the research: ATTUNEMENT (adapt to body+life) beats personalization beats visual polish.
//  No numbers ever reach the surface.
//

import Foundation

struct PhysioSnapshot: Sendable {
    var sleepQuality: String?   // "short" | "light" | "deep"
    var flow: String?           // "STRESS" | "FLOW" | "NORMAL"  (derived from HRV)
    var restingHRElevated: Bool = false
    var hasSignal: Bool { sleepQuality != nil || (flow != nil && flow != "NORMAL") || restingHRElevated }
}

enum BodyStory {

    /// Returns (opening line, caring follow-up). Warm, narrative, attuned to the body.
    static func opening(_ s: PhysioSnapshot, hour: Int) -> (line: String, follow: String) {
        let hello = salutation(hour: hour)

        guard s.hasSignal else {
            return ("\(hello). Que bom te ver.", "Me conta como está o teu dia.")
        }

        var clauses: [String] = []
        switch s.sleepQuality {
        case "short": clauses.append("você dormiu pouco")
        case "light": clauses.append("teu sono foi leve")
        case "deep":  clauses.append("você dormiu fundo")
        default: break
        }
        switch s.flow {
        case "STRESS": clauses.append("o coração andou tenso")
        case "FLOW":   clauses.append("teu coração está sereno")
        default: break
        }
        if s.restingHRElevated, s.flow != "STRESS" { clauses.append("o corpo ainda acelerado") }

        let body = join(clauses)
        let line = "\(hello). \(capitalizeFirst(body))."

        let follow: String
        switch s.flow {
        case "STRESS": follow = "Como está o peito agora?"
        case "FLOW":   follow = "Aproveita esse fôlego — no que a gente mergulha?"
        default:       follow = "Como você está se sentindo?"
        }
        return (line, follow)
    }

    // MARK: - Helpers

    private static func salutation(hour: Int) -> String {
        switch hour {
        case 5..<12:  return "Bom dia"
        case 12..<18: return "Boa tarde"
        case 18..<24: return "Boa noite"
        default:      return "Ainda acordado"
        }
    }

    private static func join(_ parts: [String]) -> String {
        switch parts.count {
        case 0:  return "que bom te ver"
        case 1:  return parts[0]
        default: return parts.dropLast().joined(separator: ", ") + " e " + parts.last!
        }
    }

    private static func capitalizeFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }
}
