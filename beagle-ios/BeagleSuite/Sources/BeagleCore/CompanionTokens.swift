//
//  CompanionTokens.swift
//  BeagleCore
//
//  Companion AURORA palette (2026-06-28 — replaces the brown "hearth/warm" palette).
//  Pivot: the presence is no longer a beagle figure — it's the SKY, the geomagnetic
//  field, the heliobiology breathing into the chat. Colors map to that:
//    - Companion side reads as deep aurora night (indigo-violet with green-teal life).
//    - User side reads as cool plum-cyan (the live signal, distinct but adjacent).
//    - Aurora tokens (green/teal/violet/pink) drive the AuroraPresence + hearth glow,
//      mixed by hour-of-day and modulated by Kp (geomagnetic activity).
//

import SwiftUI

public extension BeagleTheme {

    // MARK: - Companion content (the spoken voice)

    /// Warm-leaning off-white for the companion's text. Preserved from the prior
    /// palette — reads as "his voice" against the deep night background.
    static let companionInk = Color(red: 246/255, green: 241/255, blue: 233/255).opacity(0.95)

    /// The companion's voice bubble — a DEEP NIGHT surface (indigo-violet with a
    /// touch of green undertone, like a clear winter sky over aurora). Was a warm
    /// brown raised surface; the brown felt domestic/heavy, the aurora night feels
    /// alive and cosmic without being cold.
    static let companionSurface = Color(red: 28/255, green: 30/255, blue: 48/255)

    /// The user's bubble — confident plum-cyan. Cool but vivid (more saturated
    /// than before): user is the live signal that pulls the night into focus.
    static let userSurface = Color(red: 26/255, green: 62/255, blue: 92/255)

    /// Subtle iridescent hairline for companion-side elements — aurora-cyan, not warm.
    static let companionHairline = Color(red: 140/255, green: 220/255, blue: 210/255).opacity(0.14)

    // MARK: - Aurora tokens (presence + hearth gradients)

    /// Aurora green — the dominant aurora ribbon color, oxygen at 100–300 km.
    static let auroraGreen  = Color(red: 110/255, green: 230/255, blue: 170/255)
    /// Aurora teal — the cool edge between green and violet.
    static let auroraTeal   = Color(red: 80/255,  green: 200/255, blue: 220/255)
    /// Aurora violet — high-altitude nitrogen, the rare red-violet curtain.
    static let auroraViolet = Color(red: 160/255, green: 130/255, blue: 230/255)
    /// Aurora pink — dawn-band pink, used sparingly for warmth without brown.
    static let auroraPink   = Color(red: 220/255, green: 130/255, blue: 200/255)
    /// Deep night base — the sky between the curtains.
    static let auroraNight  = Color(red: 10/255,  green: 12/255,  blue: 22/255)

    // MARK: - Provenance (memory surfacing)

    /// Tint for a "remembered" grounding chip — the companion recalling your biography.
    static let memoryGrounded = truthRemembered
}
