//
//  CognitiveBridgeField.swift
//  BeagleCockpit
//
//  Scientific bridge visualization for the relationship between the
//  device mind and the cluster mind. Used in the living briefing and the
//  Talk / Ideas hero cards to make provenance feel alive rather than implied.
//

import SwiftUI
import BeagleCore

struct CognitiveBridgeField: View {
    enum Emphasis {
        case balanced
        case talk
        case ideas
    }

    let localWeight: Double
    let bridgeWeight: Double
    let clusterWeight: Double
    let emphasis: Emphasis

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.2 : 1 / 24, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                drawBackground(in: &context, size: size, time: t)
                drawBridge(in: &context, size: size, time: t)
                drawSignals(in: &context, size: size, time: t)
                drawNodes(in: &context, size: size, time: t)
            }
        }
        .frame(height: 118)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: BeagleSpacing.xs) {
                legend("Device", color: BeagleTheme.truthDeclared)
                legend("Bridge", color: BeagleTheme.postureWarm)
                legend("Cluster", color: BeagleTheme.truthObserved)
            }
            .padding(.leading, BeagleSpacing.xs)
            .padding(.bottom, BeagleSpacing.xs)
        }
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(
                    LinearGradient(
                        colors: [
                            BeagleTheme.surface0.opacity(0.98),
                            BeagleTheme.surface1.opacity(0.84)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.lg))
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let rect = CGRect(origin: .zero, size: size)
        let glow = 0.08 + (reduceMotion ? 0 : 0.04 * sin(time * 0.9))

        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [
                    BeagleTheme.truthDeclared.opacity(0.05 + localWeight * glow),
                    BeagleTheme.surface0.opacity(0.88),
                    BeagleTheme.truthObserved.opacity(0.05 + clusterWeight * glow)
                ]),
                startPoint: CGPoint(x: 0, y: size.height * 0.45),
                endPoint: CGPoint(x: size.width, y: size.height * 0.6)
            )
        )

        for row in stride(from: 14.0, through: size.height, by: 18.0) {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: row))
            line.addLine(to: CGPoint(x: size.width, y: row))
            context.stroke(line, with: .color(Color.white.opacity(0.02)), lineWidth: 0.5)
        }
    }

    private func drawBridge(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let left = CGPoint(x: size.width * 0.16, y: size.height * 0.55)
        let right = CGPoint(x: size.width * 0.84, y: size.height * 0.46)
        let controlA = CGPoint(x: size.width * 0.36, y: size.height * 0.14)
        let controlB = CGPoint(x: size.width * 0.64, y: size.height * 0.86)

        var main = Path()
        main.move(to: left)
        main.addCurve(to: right, control1: controlA, control2: controlB)

        var upper = Path()
        upper.move(to: CGPoint(x: left.x, y: left.y - 12))
        upper.addCurve(
            to: CGPoint(x: right.x, y: right.y - 10),
            control1: CGPoint(x: size.width * 0.40, y: size.height * 0.02),
            control2: CGPoint(x: size.width * 0.66, y: size.height * 0.38)
        )

        var lower = Path()
        lower.move(to: CGPoint(x: left.x + 2, y: left.y + 14))
        lower.addCurve(
            to: CGPoint(x: right.x - 6, y: right.y + 12),
            control1: CGPoint(x: size.width * 0.32, y: size.height * 0.78),
            control2: CGPoint(x: size.width * 0.62, y: size.height * 0.98)
        )

        let lineWidth = 1.8 + bridgeWeight * 1.6
        context.stroke(
            main,
            with: .linearGradient(
                Gradient(colors: [
                    BeagleTheme.truthDeclared.opacity(0.55),
                    BeagleTheme.postureWarm.opacity(0.95),
                    BeagleTheme.truthObserved.opacity(0.9)
                ]),
                startPoint: left,
                endPoint: right
            ),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )

        context.stroke(upper, with: .color(BeagleTheme.postureWarm.opacity(0.18)), lineWidth: 1)
        context.stroke(lower, with: .color(BeagleTheme.truthObserved.opacity(0.14)), lineWidth: 1)
    }

    private func drawSignals(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let particleCount = switch emphasis {
        case .balanced: 6
        case .talk: 4
        case .ideas: 8
        }

        for index in 0..<particleCount {
            let progressBase = Double(index) / Double(max(1, particleCount))
            let travel = fmod((time * (reduceMotion ? 0.04 : 0.11)) + progressBase, 1)
            let point = bridgePoint(size: size, progress: travel)
            let radius = 2.0 + CGFloat((1 - abs(0.5 - travel) * 2)) * 1.8
            let color: Color = travel < 0.5
                ? BeagleTheme.postureWarm.opacity(0.75)
                : BeagleTheme.truthObserved.opacity(0.88)
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    private func drawNodes(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let localPulse = 0.7 + (reduceMotion ? 0.0 : 0.18 * sin(time * 1.4))
        let clusterPulse = 0.7 + (reduceMotion ? 0.0 : 0.2 * cos(time * 1.1))
        let bridgePulse = 0.55 + (reduceMotion ? 0.0 : 0.2 * sin(time * 1.8))

        let localNodes: [CGPoint] = [
            CGPoint(x: size.width * 0.12, y: size.height * 0.26),
            CGPoint(x: size.width * 0.20, y: size.height * 0.52),
            CGPoint(x: size.width * 0.14, y: size.height * 0.78)
        ]
        let clusterNodes: [CGPoint] = [
            CGPoint(x: size.width * 0.86, y: size.height * 0.22),
            CGPoint(x: size.width * 0.79, y: size.height * 0.46),
            CGPoint(x: size.width * 0.88, y: size.height * 0.76)
        ]

        for point in localNodes {
            drawNode(in: &context, at: point, color: BeagleTheme.truthDeclared, intensity: localWeight * localPulse)
        }

        let bridgePointCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.50)
        drawNode(in: &context, at: bridgePointCenter, color: BeagleTheme.postureWarm, intensity: bridgeWeight * bridgePulse, radius: 5.2)

        for point in clusterNodes {
            drawNode(in: &context, at: point, color: BeagleTheme.truthObserved, intensity: clusterWeight * clusterPulse)
        }
    }

    private func drawNode(in context: inout GraphicsContext, at point: CGPoint, color: Color, intensity: Double, radius: CGFloat = 4.2) {
        let glowRadius = radius * (1.8 + intensity)
        let glowRect = CGRect(
            x: point.x - glowRadius,
            y: point.y - glowRadius,
            width: glowRadius * 2,
            height: glowRadius * 2
        )
        context.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(0.06 + intensity * 0.10)))

        let coreRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: coreRect), with: .color(color.opacity(0.85)))
    }

    private func bridgePoint(size: CGSize, progress: Double) -> CGPoint {
        let p = max(0, min(1, progress))
        let start = CGPoint(x: size.width * 0.16, y: size.height * 0.55)
        let c1 = CGPoint(x: size.width * 0.36, y: size.height * 0.14)
        let c2 = CGPoint(x: size.width * 0.64, y: size.height * 0.86)
        let end = CGPoint(x: size.width * 0.84, y: size.height * 0.46)
        let t = CGFloat(p)
        let mt = 1 - t
        let x = mt * mt * mt * start.x
            + 3 * mt * mt * t * c1.x
            + 3 * mt * t * t * c2.x
            + t * t * t * end.x
        let y = mt * mt * mt * start.y
            + 3 * mt * mt * t * c1.y
            + 3 * mt * t * t * c2.y
            + t * t * t * end.y
        return CGPoint(x: x, y: y)
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 5, height: 5)
            Text(title)
                .font(BeagleFont.dataSmall.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }
}
