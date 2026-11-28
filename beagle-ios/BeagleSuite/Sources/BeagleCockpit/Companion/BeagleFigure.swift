//
//  BeagleFigure.swift
//  BeagleCockpit — Companion chat
//
//  The companion made VISIBLE. The user fell in love with the figure of the beagle — the
//  loyal dog lying at his feet, chin on paws, watching him. This draws that dog: native
//  SwiftUI (Canvas + Paths, no raster asset, scales crisply), breathing, with ears and tail
//  that answer his state (FLOW/STRESS) and the conversation (perks up + wags while it
//  "listens"). It replaces the abstract ember (CompanionPresence) as the presence in chat.
//
//  Craft notes — faithful to the design research (warm, never cartoon-cute-as-gimmick):
//  the dog is stylized and soft, motion is slow and organic (breath, slow blink, gentle
//  wag), and the warm state-aura behind it still "fills the void" the way the ember did.
//

import SwiftUI
import BeagleCore

struct BeagleFigure: View {
    /// State tint + temperament: "FLOW" (bright, ears up, lively wag), "STRESS" (calmer,
    /// ears softer), else neutral resting.
    var state: String?
    /// When the companion is actively listening/answering — the dog lifts, ears perk, the
    /// tail wags a little more. Wire to `store.isStreaming`.
    var listening: Bool = false
    /// Ritmo declarado da respiração; `.neutral` quando o Physiome está mudo.
    var breath: PresenceBreath = .neutral

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Warm fur palette — sits in the hearth, never clinical.
    private let furTan      = Color(red: 0.81, green: 0.58, blue: 0.35)
    private let furTanDeep  = Color(red: 0.72, green: 0.49, blue: 0.28)
    private let furDark     = Color(red: 0.28, green: 0.20, blue: 0.18) // ears + saddle
    private let furWhite    = Color(red: 0.96, green: 0.93, blue: 0.88)
    private let furWhiteDim = Color(red: 0.86, green: 0.82, blue: 0.76)
    private let noseColor   = Color(red: 0.15, green: 0.12, blue: 0.13)
    private let eyeColor    = Color(red: 0.17, green: 0.12, blue: 0.12)

    private var aura: Color {
        switch state {
        case "FLOW":   return Color(red: 235/255, green: 165/255, blue: 110/255)
        case "STRESS": return Color(red: 190/255, green: 150/255, blue: 175/255)
        default:       return Color(red: 222/255, green: 158/255, blue: 120/255)
        }
    }

    var body: some View {
        ZStack {
            // Warm breathing aura — keeps the "fills the void" warmth the ember gave.
            auraField
            // The dog.
            if reduceMotion {
                Canvas { ctx, size in
                    drawBeagle(ctx, size: size, t: 0)
                }
            } else {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        drawBeagle(ctx, size: size, t: t)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Beagle, seu companheiro, descansando")
    }

    private var auraField: some View {
        Circle()
            .fill(RadialGradient(
                colors: [aura.opacity(0.28), aura.opacity(0.07), .clear],
                center: .center, startRadius: 2, endRadius: 150))
            .frame(width: 300, height: 300)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }

    // MARK: - Drawing

    private func drawBeagle(_ context: GraphicsContext, size: CGSize, t: TimeInterval) {
        // Square design box, anchored toward the bottom (a dog lying down).
        let S = min(size.width, size.height)
        let x0 = (size.width - S) / 2
        let y0 = size.height - S * 0.98
        func P(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(x: x0 + nx * S, y: y0 + ny * S)
        }
        func R(_ nx: CGFloat, _ ny: CGFloat, _ nw: CGFloat, _ nh: CGFloat) -> CGRect {
            CGRect(x: x0 + nx * S, y: y0 + ny * S, width: nw * S, height: nh * S)
        }

        // Slow continuous clocks.
        // Shared motion brain — the same CompanionMotion (tested) that will drive the splat.
        let pose = CompanionMotion(flowState: state, listening: listening, breath: breath).pose(at: t)
        let breath = 1 + 0.018 * pose.breath                      // belly rise/fall
        let wag = CGFloat(pose.tailWag) * 0.5                     // normalized wag → vector tail range
        let earSway = sin(t * 2 * .pi / 6.0) * 0.04               // cosmetic idle ear drift
        let perk = CGFloat(pose.earPerk) * 0.22                   // 0…0.22 rad ear lift
        let blinking = pose.blink
        let headLift = CGFloat(pose.headLift) * 0.014             // lifts to listen
        let energy = CGFloat(pose.energy)                         // eye openness below

        // Whole-body breath: scale vertically about the chest.
        var dog = context
        let chest = P(0.5, 0.66)
        dog.translateBy(x: chest.x, y: chest.y)
        dog.scaleBy(x: 1, y: breath)
        dog.translateBy(x: -chest.x, y: -chest.y - headLift * S)

        // ---- Ground shadow (he's lying ON something, not floating) ----
        for (i, op) in [(0.0, 0.10), (0.5, 0.12), (1.0, 0.10)].enumerated() {
            let spread = 0.30 - 0.06 * CGFloat(i)
            dog.fill(Path(ellipseIn: R(0.5 - spread, 0.93 - 0.004 * CGFloat(i), spread * 2, 0.07)),
                     with: .color(Color.black.opacity(op.1)))
            _ = op.0
        }

        // ---- Tail (behind the body, wagging) ----
        let tailBase = P(0.74, 0.66)
        var tctx = dog
        tctx.translateBy(x: tailBase.x, y: tailBase.y)
        tctx.rotate(by: .radians(-0.5 + wag))
        let tailRect = CGRect(x: -0.018 * S, y: -0.20 * S, width: 0.05 * S, height: 0.22 * S)
        tctx.fill(Path(roundedRect: tailRect, cornerRadius: 0.025 * S), with: .color(furTanDeep))
        // white tail tip
        tctx.fill(Path(ellipseIn: CGRect(x: -0.02 * S, y: -0.21 * S, width: 0.055 * S, height: 0.07 * S)),
                  with: .color(furWhite))

        // ---- Body mound (lying) — shaded for roundness, lit from above ----
        let bodyRect = R(0.15, 0.55, 0.70, 0.42)
        dog.fill(Path(ellipseIn: bodyRect), with: .radialGradient(
            Gradient(colors: [furTan, furTanDeep]),
            center: CGPoint(x: bodyRect.midX, y: bodyRect.minY + bodyRect.height * 0.25),
            startRadius: 0.02 * S, endRadius: bodyRect.width * 0.62))
        // dark saddle over the back
        dog.fill(Path(ellipseIn: R(0.30, 0.49, 0.44, 0.26)), with: .color(furDark))
        // soft chest shadow under the chin (so the paws read as "in front")
        dog.fill(Path(ellipseIn: R(0.36, 0.70, 0.28, 0.16)), with: .color(furTanDeep.opacity(0.55)))

        // ---- Front paws (extended forward, chin rests above) ----
        for px in [CGFloat(0.375), CGFloat(0.525)] {
            // paw shadow
            dog.fill(Path(roundedRect: R(px + 0.004, 0.755, 0.15, 0.205), cornerRadius: 0.072 * S),
                     with: .color(furTanDeep.opacity(0.4)))
            dog.fill(Path(roundedRect: R(px, 0.75, 0.15, 0.20), cornerRadius: 0.072 * S),
                     with: .radialGradient(
                        Gradient(colors: [furWhite, furWhiteDim]),
                        center: CGPoint(x: x0 + (px + 0.075) * S, y: y0 + 0.80 * S),
                        startRadius: 0.01 * S, endRadius: 0.13 * S))
            // toe lines
            var toes = Path()
            for tx in [CGFloat(0.045), CGFloat(0.085), CGFloat(0.105)] {
                toes.move(to: P(px + tx, 0.88)); toes.addLine(to: P(px + tx, 0.945))
            }
            dog.stroke(toes, with: .color(furWhiteDim.opacity(0.8)), lineWidth: 0.005 * S)
        }

        // ---- Head ----
        let headRect = R(0.28, 0.40, 0.44, 0.42)
        dog.fill(Path(ellipseIn: headRect), with: .color(furTan))
        // brown crown patch
        dog.fill(Path(ellipseIn: R(0.32, 0.38, 0.36, 0.20)), with: .color(furDark))
        // white blaze down the face
        dog.fill(Path(roundedRect: R(0.465, 0.42, 0.07, 0.30), cornerRadius: 0.035 * S),
                 with: .color(furWhite))
        // muzzle (lower face, white)
        dog.fill(Path(ellipseIn: R(0.37, 0.60, 0.26, 0.22)), with: .color(furWhite))

        // ---- Ears (long, droopy, perk with energy) ----
        for side in [CGFloat(-1), CGFloat(1)] {
            let attach = P(0.5 + side * 0.20, 0.46)
            var ectx = dog
            ectx.translateBy(x: attach.x, y: attach.y)
            ectx.rotate(by: .radians(side * (0.45 - perk + earSway * side)))
            let earRect = CGRect(x: -0.075 * S, y: -0.03 * S, width: 0.15 * S, height: 0.34 * S)
            ectx.fill(Path(ellipseIn: earRect), with: .color(furDark))
            // inner-ear warmth
            ectx.fill(Path(ellipseIn: earRect.insetBy(dx: 0.03 * S, dy: 0.05 * S)),
                      with: .color(furTanDeep.opacity(0.5)))
        }

        // ---- Eyes ----
        for side in [CGFloat(-1), CGFloat(1)] {
            let ec = P(0.5 + side * 0.105, 0.575)
            if blinking {
                var lid = Path()
                lid.move(to: CGPoint(x: ec.x - 0.035 * S, y: ec.y))
                lid.addLine(to: CGPoint(x: ec.x + 0.035 * S, y: ec.y))
                dog.stroke(lid, with: .color(eyeColor), lineWidth: 0.012 * S)
            } else {
                let openY = 0.075 + 0.02 * energy
                dog.fill(Path(ellipseIn: CGRect(x: ec.x - 0.038 * S, y: ec.y - openY / 2 * S,
                                                width: 0.076 * S, height: openY * S)),
                         with: .color(eyeColor))
                // catchlight
                dog.fill(Path(ellipseIn: CGRect(x: ec.x - 0.005 * S, y: ec.y - 0.022 * S,
                                                width: 0.018 * S, height: 0.018 * S)),
                         with: .color(furWhite.opacity(0.9)))
            }
        }

        // ---- Nose + mouth ----
        dog.fill(Path(ellipseIn: R(0.465, 0.63, 0.07, 0.055)), with: .color(noseColor))
        var mouth = Path()
        mouth.move(to: P(0.5, 0.685))
        mouth.addQuadCurve(to: P(0.45, 0.715), control: P(0.47, 0.715))
        mouth.move(to: P(0.5, 0.685))
        mouth.addQuadCurve(to: P(0.55, 0.715), control: P(0.53, 0.715))
        dog.stroke(mouth, with: .color(noseColor.opacity(0.7)), lineWidth: 0.006 * S)
    }
}
