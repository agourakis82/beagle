//
//  LorenzAttractorView.swift
//  BeagleCockpit
//
//  Animated Lorenz attractor visualization.
//  The butterfly shape emerges from the deterministic chaos of the Lorenz system.
//  Used to visualize thought stagnation — wilder orbits = more stuck.
//

import SwiftUI

struct LorenzAttractorView: View {
    let stagnation: Double  // 0.0-1.0, controls orbit intensity
    let tintColor: Color
    @State private var points: [CGPoint] = []
    @State private var trailEnd: Int = 0
    @State private var timer: Timer?

    // Lorenz system parameters
    private let sigma: Double = 10.0
    private let rho: Double = 28.0
    private let beta: Double = 8.0 / 3.0
    private let dt: Double = 0.005

    var body: some View {
        Canvas { context, size in
            guard trailEnd > 1 else { return }

            let centerX = size.width / 2
            let centerY = size.height / 2
            let scale = min(size.width, size.height) / 50

            let visible = points.prefix(trailEnd)

            // Draw the attractor trail with fading segments
            let segmentCount = visible.count
            for i in 1..<segmentCount {
                let fraction = Double(i) / Double(segmentCount)
                let opacity = fraction * 0.6
                let p0 = visible[i - 1]
                let p1 = visible[i]
                var seg = Path()
                seg.move(to: CGPoint(
                    x: centerX + p0.x * scale,
                    y: centerY - p0.y * scale
                ))
                seg.addLine(to: CGPoint(
                    x: centerX + p1.x * scale,
                    y: centerY - p1.y * scale
                ))
                context.stroke(seg, with: .color(tintColor.opacity(opacity)), lineWidth: 0.8)
            }

            // Current point as a bright dot
            if trailEnd > 0 {
                let last = visible[trailEnd - 1]
                let x = centerX + last.x * scale
                let y = centerY - last.y * scale
                let dotSize: CGFloat = 3
                let dot = Path(ellipseIn: CGRect(
                    x: x - dotSize / 2,
                    y: y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                ))
                context.fill(dot, with: .color(tintColor))
            }
        }
        .onAppear {
            generatePoints()
            startAnimation()
        }
        .onDisappear { stopAnimation() }
        .onChange(of: stagnation) {
            generatePoints()
            trailEnd = 0
            startAnimation()
        }
    }

    private func generatePoints() {
        var x = 1.0 + stagnation * 5.0
        var y = 1.0
        var z = 1.0
        var result: [CGPoint] = []

        let steps = Int(500 + stagnation * 1500)
        for _ in 0..<steps {
            let dx = sigma * (y - x) * dt
            let dy = (x * (rho - z) - y) * dt
            let dz = (x * y - beta * z) * dt
            x += dx
            y += dy
            z += dz
            result.append(CGPoint(x: x, y: z - 25))  // project X-Z plane, offset Z
        }

        points = result
    }

    private func startAnimation() {
        stopAnimation()
        let total = points.count
        guard total > 0 else { return }
        let batchSize = max(total / 60, 4)  // reveal over ~60 frames
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                if trailEnd < total {
                    trailEnd = min(trailEnd + batchSize, total)
                } else {
                    stopAnimation()
                }
            }
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    VStack(spacing: 20) {
        LorenzAttractorView(stagnation: 0.3, tintColor: .orange)
            .frame(width: 80, height: 60)
        LorenzAttractorView(stagnation: 0.8, tintColor: .orange)
            .frame(width: 80, height: 60)
    }
    .padding()
    .background(Color.black)
}
