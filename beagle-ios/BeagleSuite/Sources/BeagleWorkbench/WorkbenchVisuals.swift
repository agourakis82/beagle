import SwiftUI
import BeagleCore

enum WorkbenchTone {
    static let void = Color(red: 1/255, green: 2/255, blue: 7/255)
    static let ink = Color(red: 7/255, green: 8/255, blue: 18/255)
    static let midnight = Color(red: 11/255, green: 8/255, blue: 28/255)
    static let cyan = Color(red: 88/255, green: 240/255, blue: 255/255)
    static let mint = BeagleTheme.truthObserved
    static let blue = Color(red: 77/255, green: 148/255, blue: 255/255)
    static let amber = Color(red: 255/255, green: 197/255, blue: 31/255)
    static let violet = Color(red: 149/255, green: 105/255, blue: 255/255)
    static let magenta = Color(red: 255/255, green: 61/255, blue: 162/255)
    static let rose = Color(red: 255/255, green: 114/255, blue: 126/255)
    static let orange = Color(red: 255/255, green: 91/255, blue: 43/255)
    static let acid = Color(red: 196/255, green: 255/255, blue: 82/255)
    static let paper = Color(red: 244/255, green: 236/255, blue: 220/255)
    static let ember = Color(red: 255/255, green: 132/255, blue: 86/255)
    static let sage = Color(red: 142/255, green: 214/255, blue: 178/255)

    static var hotGradient: LinearGradient {
        LinearGradient(
            colors: [cyan, acid, amber, rose, magenta, violet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var dreamGradient: LinearGradient {
        LinearGradient(
            colors: [
                cyan.opacity(0.95),
                blue.opacity(0.92),
                violet.opacity(0.96),
                magenta.opacity(0.90)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var humanistGradient: LinearGradient {
        LinearGradient(
            colors: [
                paper.opacity(0.92),
                sage.opacity(0.84),
                cyan.opacity(0.78),
                ember.opacity(0.82)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func agentColor(_ kind: WorkbenchAgentKind) -> Color {
        switch kind {
        case .claude: return magenta
        case .codex: return amber
        case .kimi: return violet
        case .grok: return blue
        case .beagle: return mint
        }
    }
}

struct SignalField: View {
    var intensity: Double = 1.0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let w = size.width
                let h = size.height
                let gridColor = WorkbenchTone.cyan.opacity(0.06 * intensity)
                let lineColor = WorkbenchTone.mint.opacity(0.17 * intensity)
                let magenta = WorkbenchTone.magenta.opacity(0.10 * intensity)

                for x in stride(from: 0.0, through: w, by: 72) {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + sin(time + x / 90) * 16, y: h))
                    context.stroke(path, with: .color(gridColor), lineWidth: 0.6)
                }

                for y in stride(from: 28.0, through: h, by: 74) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y + cos(time + y / 80) * 10))
                    path.addLine(to: CGPoint(x: w, y: y))
                    context.stroke(path, with: .color(gridColor), lineWidth: 0.6)
                }

                for i in 0..<7 {
                    let phase = time * (0.22 + Double(i) * 0.035) + Double(i)
                    var path = Path()
                    let startY = h * (0.16 + Double(i) * 0.095)
                    path.move(to: CGPoint(x: -40, y: startY))
                    for step in stride(from: 0.0, through: w + 80, by: 42) {
                        let y = startY + sin(step / 140 + phase) * (18 + Double(i % 3) * 8)
                        path.addLine(to: CGPoint(x: step, y: y))
                    }
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [magenta, lineColor, WorkbenchTone.blue.opacity(0.08)]),
                            startPoint: CGPoint(x: 0, y: startY),
                            endPoint: CGPoint(x: w, y: startY)
                        ),
                        lineWidth: 1.0
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct AuroraWash: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [WorkbenchTone.magenta.opacity(drift ? 0.22 : 0.09), .clear],
                center: drift ? .topTrailing : .bottomLeading,
                startRadius: 40,
                endRadius: 640
            )
            RadialGradient(
                colors: [WorkbenchTone.cyan.opacity(drift ? 0.12 : 0.26), .clear],
                center: drift ? .bottomLeading : .topTrailing,
                startRadius: 20,
                endRadius: 720
            )
            RadialGradient(
                colors: [WorkbenchTone.amber.opacity(drift ? 0.09 : 0.16), .clear],
                center: .bottomTrailing,
                startRadius: 80,
                endRadius: 540
            )
        }
        .blur(radius: 24)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 9.5).repeatForever(autoreverses: true)) {
                drift.toggle()
            }
        }
    }
}

struct SounioCoreGlyph: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(WorkbenchTone.cyan.opacity(0.22), lineWidth: 1)
                .frame(width: 182, height: 182)
                .scaleEffect(pulse ? 1.05 : 0.96)
            Circle()
                .stroke(WorkbenchTone.magenta.opacity(0.18), lineWidth: 1)
                .frame(width: 132, height: 132)
                .scaleEffect(pulse ? 0.94 : 1.08)
            Circle()
                .stroke(WorkbenchTone.amber.opacity(0.20), lineWidth: 1)
                .frame(width: 92, height: 92)
                .rotationEffect(.degrees(pulse ? 9 : -9))

            SignalField(intensity: 0.65)
                .clipShape(Circle())
                .frame(width: 170, height: 170)
                .opacity(0.78)

            VStack(spacing: 2) {
                Text("S")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(WorkbenchTone.hotGradient)
                Text("SOUNIO")
                    .font(BeagleTheme.dataFont(size: 10, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(WorkbenchTone.cyan)
            }
        }
        .frame(width: 190, height: 190)
        .background(
            Circle()
                .fill(WorkbenchTone.mint.opacity(0.06))
                .shadow(color: WorkbenchTone.cyan.opacity(pulse ? 0.55 : 0.24), radius: pulse ? 34 : 16)
                .shadow(color: WorkbenchTone.magenta.opacity(pulse ? 0.28 : 0.10), radius: pulse ? 52 : 22)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct AgentOrbitMap: View {
    let agents: [WorkbenchAgent]
    let selectedID: String?
    @State private var spin = false

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                Canvas { context, canvasSize in
                    let localCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    for index in 0..<3 {
                        let inset = CGFloat(index) * 30 + 14
                        let rect = CGRect(
                            x: localCenter.x - size / 2 + inset,
                            y: localCenter.y - size / 2 + inset,
                            width: size - inset * 2,
                            height: size - inset * 2
                        )
                        let ring = Path(ellipseIn: rect)
                        context.stroke(
                            ring,
                            with: .color((index == 1 ? WorkbenchTone.violet : WorkbenchTone.cyan).opacity(0.18)),
                            style: StrokeStyle(lineWidth: 0.8, dash: index == 2 ? [3, 8] : [])
                        )
                    }

                    var spine = Path()
                    spine.move(to: CGPoint(x: 18, y: localCenter.y))
                    spine.addCurve(
                        to: CGPoint(x: canvasSize.width - 18, y: localCenter.y),
                        control1: CGPoint(x: canvasSize.width * 0.32, y: localCenter.y - 58),
                        control2: CGPoint(x: canvasSize.width * 0.68, y: localCenter.y + 58)
                    )
                    context.stroke(
                        spine,
                        with: .linearGradient(
                            Gradient(colors: [
                                WorkbenchTone.magenta.opacity(0.04),
                                WorkbenchTone.cyan.opacity(0.32),
                                WorkbenchTone.amber.opacity(0.18)
                            ]),
                            startPoint: CGPoint(x: 0, y: localCenter.y),
                            endPoint: CGPoint(x: canvasSize.width, y: localCenter.y)
                        ),
                        lineWidth: 1.4
                    )
                }

                Circle()
                    .fill(WorkbenchTone.dreamGradient)
                    .frame(width: size * 0.31, height: size * 0.31)
                    .blur(radius: 0.2)
                    .shadow(color: WorkbenchTone.cyan.opacity(0.38), radius: spin ? 40 : 22)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("S")
                                .font(.system(size: size * 0.15, weight: .black, design: .rounded))
                                .foregroundStyle(WorkbenchTone.void)
                            Text("CORE")
                                .font(BeagleTheme.dataFont(size: 9, weight: .bold))
                                .tracking(1.4)
                                .foregroundStyle(WorkbenchTone.void.opacity(0.72))
                        }
                    }

                ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                    let angle = Double(index) / Double(max(agents.count, 1)) * 360 + (spin ? 8 : -8)
                    let radius = size * (selectedID == agent.id ? 0.39 : 0.44)
                    let radians = angle * Double.pi / 180
                    let x = center.x + CGFloat(cos(radians)) * radius
                    let y = center.y + CGFloat(sin(radians)) * radius * 0.70
                    AgentOrbitNode(agent: agent, selected: selectedID == agent.id)
                        .position(x: x, y: y)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6.5).repeatForever(autoreverses: true)) {
                spin = true
            }
        }
    }
}

struct RitualFlowInstrument: View {
    @State private var flow = false

    private let steps: [(icon: String, label: String, color: Color)] = [
        ("macbook", "MAC", WorkbenchTone.cyan),
        ("terminal", "SSH", WorkbenchTone.blue),
        ("server.rack", "T560", WorkbenchTone.amber),
        ("rectangle.3.group", "ZELLIJ", WorkbenchTone.magenta)
    ]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let y = height * 0.46
            ZStack {
                Canvas { context, size in
                    var spine = Path()
                    spine.move(to: CGPoint(x: 28, y: y))
                    spine.addCurve(
                        to: CGPoint(x: width - 28, y: y),
                        control1: CGPoint(x: width * 0.28, y: y - 34),
                        control2: CGPoint(x: width * 0.70, y: y + 34)
                    )
                    context.stroke(
                        spine,
                        with: .linearGradient(
                            Gradient(colors: [
                                WorkbenchTone.cyan.opacity(0.12),
                                WorkbenchTone.acid.opacity(0.72),
                                WorkbenchTone.magenta.opacity(0.46)
                            ]),
                            startPoint: CGPoint(x: 0, y: y),
                            endPoint: CGPoint(x: width, y: y)
                        ),
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                    )

                    for index in 0..<10 {
                        let t = (Double(index) / 10.0 + (flow ? 0.62 : 0.0)).truncatingRemainder(dividingBy: 1.0)
                        let x = 28 + CGFloat(t) * (width - 56)
                        let wobble = sin(t * Double.pi * 2) * 16
                        let rect = CGRect(x: x - 2, y: y + CGFloat(wobble) - 2, width: 4, height: 4)
                        context.fill(Path(ellipseIn: rect), with: .color(WorkbenchTone.acid.opacity(0.72)))
                    }
                }

                HStack {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(step.color.opacity(0.15))
                                    .frame(width: 42, height: 42)
                                    .shadow(color: step.color.opacity(flow ? 0.38 : 0.14), radius: flow ? 16 : 7)
                                Circle()
                                    .strokeBorder(step.color.opacity(0.58), lineWidth: 1)
                                    .frame(width: 42, height: 42)
                                Image(systemName: step.icon)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(step.color)
                            }
                            Text(step.label)
                                .font(BeagleTheme.dataFont(size: 8, weight: .bold))
                                .tracking(1.0)
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(height: 74)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                flow = true
            }
        }
    }
}

struct LeaseGauge: View {
    let state: LeaseState
    var compact = false

    private var color: Color {
        BeagleTheme.color(for: state.truth)
    }

    private var value: Double {
        switch state {
        case .clear: return 0.22
        case .owned: return 0.52
        case .overlap: return 0.76
        case .blocked: return 0.96
        }
    }

    private var icon: String {
        switch state {
        case .clear: return "checkmark.seal.fill"
        case .owned: return "hand.raised.fill"
        case .overlap: return "arrow.triangle.branch"
        case .blocked: return "lock.trianglebadge.exclamationmark.fill"
        }
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let rect = CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16)
                let start = Angle.degrees(146)
                let end = Angle.degrees(394)
                var base = Path()
                base.addArc(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: start,
                    endAngle: end,
                    clockwise: false
                )
                context.stroke(base, with: .color(Color.white.opacity(0.08)), style: StrokeStyle(lineWidth: compact ? 6 : 9, lineCap: .round))

                var arc = Path()
                arc.addArc(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: start,
                    endAngle: Angle.degrees(146 + 248 * value),
                    clockwise: false
                )
                context.stroke(
                    arc,
                    with: .linearGradient(
                        Gradient(colors: [WorkbenchTone.cyan, color, WorkbenchTone.magenta.opacity(0.85)]),
                        startPoint: CGPoint(x: rect.minX, y: rect.midY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                    ),
                    style: StrokeStyle(lineWidth: compact ? 6 : 9, lineCap: .round)
                )
            }

            VStack(spacing: compact ? 1 : 4) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 16 : 25, weight: .bold))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.42), radius: 10)
                Text(state.rawValue.uppercased())
                    .font(BeagleTheme.dataFont(size: compact ? 8 : 10, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(BeagleTheme.textData)
            }
        }
        .frame(width: compact ? 72 : 118, height: compact ? 72 : 118)
    }
}

struct LaneRadar: View {
    let lanes: [WorkbenchLane]
    let selectedID: String

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                Canvas { context, _ in
                    for ring in 1...3 {
                        let radius = size * CGFloat(ring) / 7
                        context.stroke(
                            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(WorkbenchTone.cyan.opacity(0.10)),
                            style: StrokeStyle(lineWidth: 0.8, dash: ring == 2 ? [4, 7] : [])
                        )
                    }
                    for index in lanes.indices {
                        let radians = Double(index) / Double(max(lanes.count, 1)) * Double.pi * 2 - Double.pi / 2
                        let endpoint = CGPoint(
                            x: center.x + CGFloat(cos(radians)) * size * 0.40,
                            y: center.y + CGFloat(sin(radians)) * size * 0.40
                        )
                        var spoke = Path()
                        spoke.move(to: center)
                        spoke.addLine(to: endpoint)
                        context.stroke(spoke, with: .color(Color.white.opacity(0.06)), lineWidth: 0.7)
                    }
                }

                ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                    let radians = Double(index) / Double(max(lanes.count, 1)) * Double.pi * 2 - Double.pi / 2
                    let selected = lane.id == selectedID
                    let radius = size * (selected ? 0.34 : 0.40)
                    let color = BeagleTheme.color(for: lane.leaseState.truth)
                    ZStack {
                        Circle()
                            .fill(color.opacity(selected ? 0.28 : 0.14))
                            .frame(width: selected ? 34 : 25, height: selected ? 34 : 25)
                            .shadow(color: color.opacity(selected ? 0.48 : 0.14), radius: selected ? 15 : 5)
                        Image(systemName: laneIcon(lane.leaseState))
                            .font(.system(size: selected ? 13 : 10, weight: .bold))
                            .foregroundStyle(color)
                    }
                    .position(
                        x: center.x + CGFloat(cos(radians)) * radius,
                        y: center.y + CGFloat(sin(radians)) * radius
                    )
                }
            }
        }
        .frame(height: 138)
    }

    private func laneIcon(_ state: LeaseState) -> String {
        switch state {
        case .clear: return "circle"
        case .owned: return "hand.raised.fill"
        case .overlap: return "arrow.triangle.branch"
        case .blocked: return "xmark.octagon.fill"
        }
    }
}

private struct AgentOrbitNode: View {
    let agent: WorkbenchAgent
    let selected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(agent.kind.color.opacity(selected ? 0.26 : 0.13))
                    .frame(width: selected ? 46 : 38, height: selected ? 46 : 38)
                    .shadow(color: agent.kind.color.opacity(selected ? 0.56 : 0.18), radius: selected ? 22 : 9)
                Circle()
                    .strokeBorder(agent.kind.color.opacity(selected ? 0.95 : 0.38), lineWidth: selected ? 1.4 : 0.8)
                    .frame(width: selected ? 46 : 38, height: selected ? 46 : 38)
                Text(agent.kind.shortName)
                    .font(BeagleTheme.dataFont(size: selected ? 12 : 10, weight: .bold))
                    .foregroundStyle(agent.kind.color)
            }
            Text(agent.zellijTabName)
                .font(BeagleTheme.dataFont(size: 8, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? BeagleTheme.textPrimary : BeagleTheme.textTertiary)
                .lineLimit(1)
        }
        .animation(.snappy, value: selected)
    }
}

struct ChromaticFrame: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                WorkbenchTone.cyan.opacity(active ? 0.75 : 0.24),
                                WorkbenchTone.violet.opacity(active ? 0.65 : 0.16),
                                WorkbenchTone.magenta.opacity(active ? 0.70 : 0.18),
                                WorkbenchTone.amber.opacity(active ? 0.55 : 0.14),
                                WorkbenchTone.cyan.opacity(active ? 0.75 : 0.24)
                            ],
                            center: .center
                        ),
                        lineWidth: active ? 1.2 : 0.7
                    )
            )
            .shadow(color: WorkbenchTone.cyan.opacity(active ? 0.18 : 0.04), radius: active ? 18 : 6)
    }
}

extension View {
    func chromaticFrame(active: Bool = true) -> some View {
        modifier(ChromaticFrame(active: active))
    }
}
