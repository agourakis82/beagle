import SwiftUI
import BeagleCore

enum LiquidCodexIntensity: Double, CaseIterable, Sendable {
    case quiet = 0.45
    case standard = 0.72
    case vivid = 1.0
}

enum PresenceState: String, Sendable {
    case running
    case waiting
    case blocked
    case done

    init(_ status: WorkbenchAgentStatus) {
        switch status {
        case .running:
            self = .running
        case .idle, .waiting:
            self = .waiting
        case .blocked:
            self = .blocked
        case .done:
            self = .done
        }
    }

    var truth: TruthMode {
        switch self {
        case .running: return .observed
        case .waiting: return .declared
        case .blocked: return .stale
        case .done: return .remembered
        }
    }

    var symbolName: String {
        switch self {
        case .running: return "play.fill"
        case .waiting: return "hourglass"
        case .blocked: return "lock.trianglebadge.exclamationmark.fill"
        case .done: return "checkmark.seal.fill"
        }
    }
}

struct CommandPaletteItem: Identifiable, Hashable, Sendable {
    let id: String
    let category: CommandPaletteCategory
    let command: String
    let title: String
    let subtitle: String
    let icon: String
    let truth: TruthMode

    init(
        category: CommandPaletteCategory,
        command: String,
        title: String,
        subtitle: String,
        icon: String,
        truth: TruthMode
    ) {
        self.id = command
        self.category = category
        self.command = command
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.truth = truth
    }
}

struct InstrumentMetric: Identifiable {
    let id: String
    let title: String
    let value: Double
    let label: String
    let truth: TruthMode
    let color: Color
}

enum CommandPaletteCategory: String, CaseIterable, Identifiable, Sendable {
    case orient
    case diagnose
    case guardrail
    case compose

    var id: String { rawValue }

    var label: String {
        switch self {
        case .orient: return "Orient"
        case .diagnose: return "Doctor"
        case .guardrail: return "Guard"
        case .compose: return "Compose"
        }
    }

    var icon: String {
        switch self {
        case .orient: return "location.fill"
        case .diagnose: return "stethoscope"
        case .guardrail: return "lock.shield.fill"
        case .compose: return "text.bubble.fill"
        }
    }
}

enum LiquidCodexTheme {
    static let cornerRadius: CGFloat = 18
    static let controlRadius: CGFloat = 12
    static let glassOpacity = 0.76
    static let elevatedGlassOpacity = 0.92
    static let hairline = Color.white.opacity(0.08)
    static let readableInk = Color.black.opacity(0.30)
    static let commandBackdrop = Color.black.opacity(0.42)

    static func accent(for state: PresenceState) -> Color {
        BeagleTheme.color(for: state.truth)
    }

    static func depthShadow(_ level: Int) -> Color {
        Color.black.opacity(level > 1 ? 0.34 : 0.18)
    }
}

struct LiquidCodexBackground: View {
    var intensity: LiquidCodexIntensity = .standard

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints(time: time),
                colors: [
                    WorkbenchTone.void,
                    WorkbenchTone.midnight,
                    WorkbenchTone.cyan.opacity(0.28 * intensity.rawValue),
                    WorkbenchTone.ink,
                    WorkbenchTone.violet.opacity(0.24 * intensity.rawValue),
                    WorkbenchTone.magenta.opacity(0.20 * intensity.rawValue),
                    WorkbenchTone.void,
                    WorkbenchTone.blue.opacity(0.22 * intensity.rawValue),
                    WorkbenchTone.acid.opacity(0.14 * intensity.rawValue)
                ],
                background: WorkbenchTone.void,
                smoothsColors: true
            )
            .ignoresSafeArea()
            .overlay(WorkbenchTone.void.opacity(0.20))
        }
        .allowsHitTesting(false)
    }

    private func meshPoints(time: TimeInterval) -> [SIMD2<Float>] {
        let wobble = Float(sin(time * 0.18) * 0.035)
        let counter = Float(cos(time * 0.14) * 0.035)
        return [
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(0.50 + wobble, 0.0),
            SIMD2<Float>(1.0, 0.0),
            SIMD2<Float>(0.0, 0.50 + counter),
            SIMD2<Float>(0.50 - counter, 0.50 + wobble),
            SIMD2<Float>(1.0, 0.48 - wobble),
            SIMD2<Float>(0.0, 1.0),
            SIMD2<Float>(0.52 + counter, 1.0),
            SIMD2<Float>(1.0, 1.0)
        ]
    }
}

struct LiquidGlassSurface<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let elevated: Bool
    let truth: TruthMode?
    let depth: Int
    let content: Content

    init(
        elevated: Bool = false,
        truth: TruthMode? = nil,
        depth: Int = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.elevated = elevated
        self.truth = truth
        self.depth = depth
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LiquidCodexTheme.cornerRadius, style: .continuous)
        content
            .padding(16)
            .background {
                shape
                    .fill(reduceTransparency ? WorkbenchTone.ink.opacity(0.96) : WorkbenchTone.ink.opacity(0.28))
                    .background {
                        shape
                            .fill(.regularMaterial)
                            .opacity(reduceTransparency ? 1 : (elevated ? LiquidCodexTheme.elevatedGlassOpacity : LiquidCodexTheme.glassOpacity))
                    }
                    .overlay(LiquidCodexTheme.readableInk.blendMode(.multiply))
            }
            .overlay {
                shape.strokeBorder(borderStyle, lineWidth: elevated ? 1.1 : 0.8)
            }
            .glassEffect(.regular, in: shape)
            .shadow(color: LiquidCodexTheme.depthShadow(depth), radius: elevated ? 18 : 9, y: elevated ? 10 : 5)
    }

    private var borderStyle: AnyShapeStyle {
        if let truth {
            return AnyShapeStyle(BeagleTheme.color(for: truth).opacity(0.22))
        }
        return AnyShapeStyle(LiquidCodexTheme.hairline)
    }
}

struct PresenceOrb: View {
    let agent: WorkbenchAgent
    var compact = false
    @State private var pulse = false

    private var state: PresenceState { PresenceState(agent.status) }
    private var accent: Color { agent.kind.color }

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(state == .running ? 0.24 : 0.12))
                .frame(width: compact ? 46 : 84, height: compact ? 46 : 84)
                .shadow(color: accent.opacity(pulse && state == .running ? 0.62 : 0.22), radius: pulse ? 24 : 10)
            Circle()
                .strokeBorder(WorkbenchTone.hotGradient, lineWidth: compact ? 1.4 : 2.0)
                .frame(width: compact ? 46 : 84, height: compact ? 46 : 84)
                .rotationEffect(.degrees(pulse ? 10 : -10))
            VStack(spacing: compact ? 0 : 2) {
                Text(agent.kind.shortName)
                    .font(BeagleTheme.dataFont(size: compact ? 11 : 20, weight: .bold))
                    .foregroundStyle(accent)
                if !compact {
                    Image(systemName: state.symbolName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LiquidCodexTheme.accent(for: state))
                        .symbolEffect(.pulse, value: pulse)
                }
            }
        }
        .accessibilityLabel("\(agent.displayName), \(state.rawValue)")
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct InstrumentRing: View {
    let metric: InstrumentMetric
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(metric.value, 0), 1))
                .stroke(
                    LinearGradient(
                        colors: [WorkbenchTone.cyan, metric.color, WorkbenchTone.magenta.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: metric.color.opacity(0.30), radius: 14)
            VStack(spacing: 1) {
                Text(metric.title)
                    .font(BeagleTheme.dataFont(size: 10, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text("\(Int(metric.value * 100))")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(metric.color)
                    .contentTransition(.numericText())
                Text(metric.label)
                    .font(BeagleTheme.dataFont(size: 8, weight: .medium))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }
}

struct LeaseCollisionGraph: View {
    let lanes: [WorkbenchLane]
    let selectedID: String

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                SignalRibbon(intensity: .quiet)
                    .clipShape(Circle())
                    .opacity(0.55)

                ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                    let selected = lane.id == selectedID
                    let radians = Double(index) / Double(max(lanes.count, 1)) * Double.pi * 2 - Double.pi / 2
                    let radius = size * (selected ? 0.25 : 0.37)
                    let color = BeagleTheme.color(for: lane.leaseState.truth)
                    VStack(spacing: 3) {
                        Image(systemName: icon(for: lane.leaseState))
                            .font(.system(size: selected ? 14 : 10, weight: .bold))
                            .foregroundStyle(color)
                            .frame(width: selected ? 34 : 26, height: selected ? 34 : 26)
                            .background(Circle().fill(color.opacity(selected ? 0.24 : 0.12)))
                            .shadow(color: color.opacity(selected ? 0.45 : 0.14), radius: selected ? 12 : 5)
                        Text(lane.title.split(separator: " ").first.map(String.init) ?? lane.id)
                            .font(BeagleTheme.dataFont(size: 7, weight: selected ? .bold : .medium))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                    .position(
                        x: center.x + CGFloat(cos(radians)) * radius,
                        y: center.y + CGFloat(sin(radians)) * radius
                    )
                }
            }
        }
    }

    private func icon(for state: LeaseState) -> String {
        switch state {
        case .clear: return "checkmark"
        case .owned: return "hand.raised.fill"
        case .overlap: return "arrow.triangle.branch"
        case .blocked: return "lock.fill"
        }
    }
}

struct ZellijConstellation: View {
    let tabs: [String]
    let agents: [WorkbenchAgent]
    let selectedID: String?
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                Canvas { context, canvasSize in
                    let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    for ring in 1...3 {
                        let radius = size * CGFloat(ring) / 7.4
                        context.stroke(
                            Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(WorkbenchTone.cyan.opacity(0.10)),
                            style: StrokeStyle(lineWidth: 0.8, dash: ring == 2 ? [4, 8] : [])
                        )
                    }
                }

                Text("Z")
                    .font(.system(size: size * 0.19, weight: .black, design: .rounded))
                    .foregroundStyle(WorkbenchTone.hotGradient)
                    .shadow(color: WorkbenchTone.cyan.opacity(0.32), radius: 18)

                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    let agent = agents.first { $0.zellijTabName == tab }
                    let selected = agent?.id == selectedID
                    let radians = Double(index) / Double(max(tabs.count, 1)) * Double.pi * 2 + (drift ? 0.08 : -0.08)
                    let radius = size * (selected ? 0.35 : 0.42)
                    let color = color(for: tab, agent: agent)
                    VStack(spacing: 3) {
                        Circle()
                            .fill(color.opacity(selected ? 0.95 : 0.64))
                            .frame(width: selected ? 13 : 9, height: selected ? 13 : 9)
                            .shadow(color: color.opacity(0.56), radius: selected ? 10 : 5)
                        Text(tab)
                            .font(BeagleTheme.dataFont(size: selected ? 8 : 7, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? BeagleTheme.textPrimary : BeagleTheme.textTertiary)
                            .lineLimit(1)
                    }
                    .position(
                        x: center.x + CGFloat(cos(radians)) * radius,
                        y: center.y + CGFloat(sin(radians)) * radius * 0.74
                    )
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func color(for tab: String, agent: WorkbenchAgent?) -> Color {
        if let agent { return agent.kind.color }
        if tab == "repo" { return WorkbenchTone.acid }
        return BeagleTheme.truthDeclared
    }
}

struct SignalRibbon: View {
    var intensity: LiquidCodexIntensity = .standard

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<5 {
                    var path = Path()
                    let y = size.height * (0.18 + CGFloat(index) * 0.16)
                    path.move(to: CGPoint(x: -24, y: y))
                    for x in stride(from: 0.0, through: size.width + 48, by: 24) {
                        let wave = sin((x / 88) + time * (0.42 + Double(index) * 0.07)) * (8 + Double(index) * 1.7)
                        path.addLine(to: CGPoint(x: x, y: y + CGFloat(wave)))
                    }
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [
                                WorkbenchTone.cyan.opacity(0.04 * intensity.rawValue),
                                WorkbenchTone.acid.opacity(0.36 * intensity.rawValue),
                                WorkbenchTone.magenta.opacity(0.18 * intensity.rawValue)
                            ]),
                            startPoint: CGPoint(x: 0, y: y),
                            endPoint: CGPoint(x: size.width, y: y)
                        ),
                        style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct CommandPaletteOverlay: View {
    @Binding var isPresented: Bool
    let items: [CommandPaletteItem]
    let onSelect: (CommandPaletteItem) -> Void
    @State private var query = ""
    @State private var selectedCategory: CommandPaletteCategory?

    private var filteredItems: [CommandPaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let categoryMatches = selectedCategory.map { $0 == item.category } ?? true
            guard categoryMatches else { return false }
            guard !trimmed.isEmpty else { return true }
            return item.category.label.localizedCaseInsensitiveContains(trimmed)
                || item.command.localizedCaseInsensitiveContains(trimmed)
                || item.title.localizedCaseInsensitiveContains(trimmed)
                || item.subtitle.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var firstMatch: CommandPaletteItem? {
        filteredItems.first
    }

    var body: some View {
        ZStack(alignment: .top) {
            LiquidCodexTheme.commandBackdrop
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            LiquidGlassSurface(elevated: true, truth: .observed, depth: 2) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "command")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(WorkbenchTone.cyan)
                            .symbolEffect(.pulse, value: query)
                        TextField("Run a Beagle command", text: $query)
                            .textFieldStyle(.plain)
                            .font(BeagleTheme.displayFont(size: 20, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .onSubmit {
                                guard let firstMatch else { return }
                                onSelect(firstMatch)
                                isPresented = false
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(WorkbenchTone.void.opacity(0.72)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WorkbenchTone.cyan.opacity(0.24), lineWidth: 1))

                    CommandCategoryPicker(selection: $selectedCategory)

                    VStack(spacing: 7) {
                        ForEach(filteredItems) { item in
                            Button {
                                onSelect(item)
                                isPresented = false
                            } label: {
                                CommandPaletteRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 640)
            .padding(.top, 72)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct CommandCategoryPicker: View {
    @Binding var selection: CommandPaletteCategory?

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                CommandCategoryChip(
                    label: "All",
                    icon: "square.grid.2x2.fill",
                    selected: selection == nil
                ) {
                    withAnimation(.snappy) { selection = nil }
                }

                ForEach(CommandPaletteCategory.allCases) { category in
                    CommandCategoryChip(
                        label: category.label,
                        icon: category.icon,
                        selected: selection == category
                    ) {
                        withAnimation(.snappy) { selection = category }
                    }
                }
            }
        }
    }
}

private struct CommandCategoryChip: View {
    let label: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(BeagleTheme.dataFont(size: 10, weight: .bold))
            }
            .foregroundStyle(selected ? WorkbenchTone.void : BeagleTheme.textData)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(selected ? AnyShapeStyle(WorkbenchTone.hotGradient) : AnyShapeStyle(WorkbenchTone.ink.opacity(0.46))))
            .overlay(Capsule().strokeBorder(selected ? Color.white.opacity(0.22) : WorkbenchTone.cyan.opacity(0.14), lineWidth: 1))
            .glassEffect(.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct CommandPaletteRow: View {
    let item: CommandPaletteItem

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(BeagleTheme.color(for: item.truth))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(BeagleTheme.color(for: item.truth).opacity(0.11)))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(BeagleTheme.uiFont(size: 13, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text(item.subtitle)
                    .font(BeagleTheme.uiFont(size: 11))
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(item.command)
                .font(BeagleTheme.dataFont(size: 11, weight: .medium))
                .foregroundStyle(BeagleTheme.textData)
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 13).fill(WorkbenchTone.ink.opacity(0.62)))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(BeagleTheme.color(for: item.truth).opacity(0.15), lineWidth: 1))
    }
}
