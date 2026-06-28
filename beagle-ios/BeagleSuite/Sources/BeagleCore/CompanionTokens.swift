//
//  CompanionTokens.swift
//  BeagleCore
//
//  Companion warmth layer for the design system. BeagleTheme's truth-modes stay COOL
//  (epistemic accents: observed/remembered/declared); the companion's *content* voice
//  gets a warm palette so it reads like a friend, not a clinical dashboard.
//  See docs/design/2026-06-24-companion-design-system.md (§3 Color).
//

import SwiftUI

public extension BeagleTheme {

    // MARK: - Companion content warmth (the spoken voice)

    /// Warm off-white for the companion's text (vs the cool, clinical `textPrimary`).
    static let companionInk = Color(red: 246/255, green: 241/255, blue: 233/255).opacity(0.95)

    /// The companion's voice bubble — a warm raised surface (brown-grey, lit from the
    /// hearth) so the companion's voice reads warm, not clinical grey.
    static let companionSurface = Color(red: 61/255, green: 51/255, blue: 46/255)

    /// The user's bubble — a confident teal (you = the live signal), distinct from the
    /// warm companion voice and brighter than the surface so the conversation has contrast.
    static let userSurface = Color(red: 20/255, green: 64/255, blue: 84/255)

    /// Subtle warm hairline for companion-side elements.
    static let companionHairline = Color(red: 255/255, green: 240/255, blue: 220/255).opacity(0.10)

    // MARK: - Provenance (memory surfacing, finding 7)

    /// Tint for a "remembered" grounding chip — the companion recalling your biography.
    static let memoryGrounded = truthRemembered
}
