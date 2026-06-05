import SwiftUI
import Charts
import BeagleCore

struct SupercomputingControlView: View {
    @EnvironmentObject private var workbench: WorkbenchStore
    @StateObject private var superStore = SupercomputingStore()

    var body: some View {
        let snapshot = superStore.snapshot
        ZStack {
            LiquidCodexBackground(intensity: .standard)
            SignalField(intensity: 0.72).opacity(0.56)

            VStack(spacing: 0) {
                SuperHeader(
                    snapshot: snapshot,
                    activeAgents: workbench.activeAgents.count,
                    endpointText: $superStore.endpointText,
                    isRefreshing: superStore.isRefreshing
                ) {
                    Task { await superStore.refresh() }
                }
                Divider().overlay(Color.white.opacity(0.06))
                HStack(spacing: 16) {
                    VStack(spacing: 16) {
                        ClusterFabricPanel(nodes: snapshot.nodes, truth: snapshot.source.truth)
                            .frame(maxHeight: .infinity)
                        SlurmLanePanel(jobs: snapshot.slurmJobs, truth: snapshot.source.truth)
                            .frame(height: 218)
                    }
                    .frame(minWidth: 500)

                    VStack(spacing: 16) {
                        GPUOrbitPanel(nodes: snapshot.nodes, truth: snapshot.source.truth)
                            .frame(height: 360)
                        HStack(spacing: 16) {
                            StorageRingPanel(thinPoolPct: snapshot.orangefsThinPoolPct, risk: snapshot.orangefsRisk)
                            ThermalMatrixPanel(nodes: snapshot.nodes)
                        }
                    }
                    .frame(width: 500)

                    VStack(spacing: 16) {
                        SuperActionPanel()
                        NodeStackPanel(nodes: snapshot.nodes)
                        ClusterPulsePanel(source: snapshot.source, error: snapshot.error)
                    }
                    .frame(width: 260)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 1180, minHeight: 760)
        .task {
            await superStore.refresh()
        }
    }
}

private struct SuperHeader: View {
    let snapshot: SupercomputingSnapshot
    let activeAgents: Int
    @Binding var endpointText: String
    let isRefreshing: Bool
    let refresh: () -> Void

    private var gpuPeak: Double {
        snapshot.nodes.map(\.gpu).max() ?? 0
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(WorkbenchTone.dreamGradient)
                    .frame(width: 42, height: 42)
                    .shadow(color: WorkbenchTone.cyan.opacity(0.36), radius: 18)
                Image(systemName: "cpu.fill")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(WorkbenchTone.void)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("SUPERCOMPUTING CONTROL")
                    .font(BeagleTheme.dataFont(size: 11, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(WorkbenchTone.acid)
                HStack(spacing: 8) {
                    Text("t560-proxmox fabric")
                        .font(BeagleTheme.displayFont(size: 22, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    TruthBadge(snapshot.source.truth, compact: true)
                    Text(snapshot.source.rawValue.uppercased())
                        .font(BeagleTheme.dataFont(size: 9, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(BeagleTheme.color(for: snapshot.source.truth))
                }
            }

            Spacer()

            TextField("Cockpit URL", text: $endpointText)
                .font(BeagleTheme.dataFont(size: 10, weight: .medium))
                .foregroundStyle(BeagleTheme.textData)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(width: 235)
                .background(RoundedRectangle(cornerRadius: 12).fill(WorkbenchTone.midnight.opacity(0.60)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BeagleTheme.color(for: snapshot.source.truth).opacity(0.18), lineWidth: 1))

            Button(action: refresh) {
                Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(isRefreshing ? WorkbenchTone.amber : WorkbenchTone.cyan)
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)

            SuperMetric(icon: "server.rack", value: "\(snapshot.nodes.count)", label: "nodes", truth: snapshot.source.truth)
            SuperMetric(icon: "bolt.fill", value: "\(Int(gpuPeak * 100))%", label: "gpu peak", truth: snapshot.source.truth)
            SuperMetric(icon: "externaldrive.fill", value: snapshot.orangefsThinPoolPct.map { "\(Int($0))%" } ?? "--", label: "orangefs", truth: snapshot.orangefsRisk == "green" ? .observed : .declared)
            SuperMetric(icon: "person.crop.circle.badge.checkmark", value: "\(activeAgents)", label: "agents", truth: .remembered)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Rectangle().fill(.regularMaterial).opacity(0.48))
        .overlay(alignment: .bottom) {
            Rectangle().fill(WorkbenchTone.hotGradient).frame(height: 1).opacity(0.42)
        }
    }
}

private struct SuperMetric: View {
    let icon: String
    let value: String
    let label: String
    let truth: TruthMode

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BeagleTheme.color(for: truth))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 9).fill(BeagleTheme.color(for: truth).opacity(0.11)))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(BeagleTheme.dataFont(size: 14, weight: .bold))
                    .foregroundStyle(BeagleTheme.textData)
                Text(label.uppercased())
                    .font(BeagleTheme.dataFont(size: 8, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12).fill(WorkbenchTone.midnight.opacity(0.58)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BeagleTheme.color(for: truth).opacity(0.18), lineWidth: 1))
    }
}

private struct ClusterFabricPanel: View {
    let nodes: [SuperNode]
    let truth: TruthMode

    var body: some View {
        LiquidGlassSurface(elevated: true, truth: truth, depth: 2) {
            VStack(alignment: .leading, spacing: 12) {
                PanelTitle(icon: "point.3.connected.trianglepath.dotted", title: "Fabric Map", truth: truth)
                HPCFabricMap(nodes: nodes)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .chromaticFrame(active: true)
    }
}

private struct HPCFabricMap: View {
    let nodes: [SuperNode]
    @State private var pulse = false

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                Canvas { context, size in
                    let points = nodePoints(in: size, count: nodes.count)
                    for index in points.indices {
                        for other in points.indices where other > index {
                            var path = Path()
                            path.move(to: points[index])
                            path.addLine(to: points[other])
                            context.stroke(
                                path,
                                with: .linearGradient(
                                    Gradient(colors: [WorkbenchTone.cyan.opacity(0.05), WorkbenchTone.magenta.opacity(0.12), WorkbenchTone.acid.opacity(0.08)]),
                                    startPoint: points[index],
                                    endPoint: points[other]
                                ),
                                lineWidth: 0.9
                            )
                        }
                    }

                    for ring in 1...4 {
                        let radius = min(size.width, size.height) * CGFloat(ring) / 9
                        context.stroke(
                            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(WorkbenchTone.cyan.opacity(0.055)),
                            style: StrokeStyle(lineWidth: 0.8, dash: ring.isMultiple(of: 2) ? [4, 10] : [])
                        )
                    }
                }

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    let point = nodePoints(in: geometry.size, count: nodes.count)[index]
                    FabricNode(node: node, active: pulse)
                        .position(point)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func nodePoints(in size: CGSize, count: Int) -> [CGPoint] {
        let canonical = [
            CGPoint(x: size.width * 0.50, y: size.height * 0.24),
            CGPoint(x: size.width * 0.24, y: size.height * 0.44),
            CGPoint(x: size.width * 0.68, y: size.height * 0.45),
            CGPoint(x: size.width * 0.36, y: size.height * 0.72),
            CGPoint(x: size.width * 0.78, y: size.height * 0.72)
        ]
        guard count > canonical.count else {
            return Array(canonical.prefix(max(count, 0)))
        }
        let center = CGPoint(x: size.width * 0.52, y: size.height * 0.52)
        return (0..<count).map { index in
            let radians = Double(index) / Double(max(count, 1)) * Double.pi * 2 - Double.pi / 2
            return CGPoint(
                x: center.x + CGFloat(cos(radians)) * size.width * 0.34,
                y: center.y + CGFloat(sin(radians)) * size.height * 0.31
            )
        }
    }
}

private struct FabricNode: View {
    let node: SuperNode
    let active: Bool

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Hexagon()
                    .fill(node.accent.opacity(0.16))
                    .frame(width: 82, height: 74)
                    .shadow(color: node.accent.opacity(active ? 0.50 : 0.20), radius: active ? 22 : 8)
                Hexagon()
                    .stroke(node.accent.opacity(0.72), lineWidth: 1.2)
                    .frame(width: 82, height: 74)
                VStack(spacing: 1) {
                    Image(systemName: node.gpu > 0.5 ? "bolt.horizontal.circle.fill" : "server.rack")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(node.accent)
                    Text(node.id.uppercased())
                        .font(BeagleTheme.dataFont(size: 11, weight: .bold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                }
            }
            Text(node.role)
                .font(BeagleTheme.dataFont(size: 8, weight: .medium))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }
}

private struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.25),
            CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.75),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.75),
            CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.25)
        ]
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

private struct GPUOrbitPanel: View {
    let nodes: [SuperNode]
    let truth: TruthMode

    var body: some View {
        LiquidGlassSurface(elevated: true, truth: truth, depth: 2) {
            VStack(alignment: .leading, spacing: 12) {
                PanelTitle(icon: "bolt.horizontal.fill", title: "GPU Pressure", truth: truth)
                GPUOrbit(nodes: nodes)
            }
        }
        .chromaticFrame(active: true)
    }
}

private struct GPUOrbit: View {
    let nodes: [SuperNode]
    @State private var spin = false

    private var peak: Double {
        nodes.map(\.gpu).max() ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                Canvas { context, _ in
                    for ring in 1...4 {
                        let radius = size * CGFloat(ring) / 9
                        context.stroke(
                            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(WorkbenchTone.violet.opacity(0.10)),
                            style: StrokeStyle(lineWidth: 1, dash: ring == 3 ? [3, 9] : [])
                        )
                    }
                }

                VStack(spacing: 2) {
                    Text("\(Int(peak * 100))")
                        .font(.system(size: 66, weight: .black, design: .rounded))
                        .foregroundStyle(WorkbenchTone.hotGradient)
                    Text("GPU PEAK")
                        .font(BeagleTheme.dataFont(size: 10, weight: .bold))
                        .tracking(2.0)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                .shadow(color: WorkbenchTone.magenta.opacity(0.24), radius: 26)

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    let radians = Double(index) / Double(max(nodes.count, 1)) * Double.pi * 2 + (spin ? 0.14 : -0.14)
                    let radius = size * 0.39
                    GPUNode(node: node)
                        .position(
                            x: center.x + CGFloat(cos(radians)) * radius,
                            y: center.y + CGFloat(sin(radians)) * radius * 0.73
                        )
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 5.2).repeatForever(autoreverses: true)) {
                spin = true
            }
        }
    }
}

private struct GPUNode: View {
    let node: SuperNode

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(node.accent.opacity(0.14))
                    .frame(width: 58, height: 58)
                Circle()
                    .trim(from: 0, to: node.gpu)
                    .stroke(node.gpu > 0.85 ? WorkbenchTone.rose : node.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 58, height: 58)
                Text("\(Int(node.gpu * 100))")
                    .font(BeagleTheme.dataFont(size: 13, weight: .bold))
                    .foregroundStyle(BeagleTheme.textData)
            }
            Text(node.id)
                .font(BeagleTheme.dataFont(size: 8, weight: .bold))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }
}

private struct SlurmLanePanel: View {
    let jobs: [SuperSlurmJob]
    let truth: TruthMode

    var body: some View {
        LiquidGlassSurface(elevated: false, truth: truth) {
            VStack(alignment: .leading, spacing: 12) {
                PanelTitle(icon: "timeline.selection", title: "Slurm Lanes", truth: truth)
                Chart(jobs) { job in
                    BarMark(
                        x: .value("Job", job.id.uppercased()),
                        y: .value("Progress", job.progress)
                    )
                    .foregroundStyle(job.color.opacity(0.82))
                    .cornerRadius(8)
                    .annotation(position: .top) {
                        Image(systemName: job.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(job.color)
                    }
                }
                .chartYScale(domain: 0...1)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(BeagleTheme.dataFont(size: 8, weight: .bold))
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
            }
        }
    }
}

private struct StorageRingPanel: View {
    let thinPoolPct: Double?
    let risk: String

    private var pct: Double {
        min(max((thinPoolPct ?? 87) / 100, 0), 1)
    }

    private var truth: TruthMode {
        risk == "green" ? .observed : .declared
    }

    private var color: Color {
        if risk == "red" { return WorkbenchTone.rose }
        if risk == "green" { return WorkbenchTone.cyan }
        return WorkbenchTone.amber
    }

    var body: some View {
        LiquidGlassSurface(elevated: false, truth: truth) {
            VStack(alignment: .leading, spacing: 12) {
                PanelTitle(icon: "externaldrive.fill", title: "OrangeFS", truth: truth)
                ZStack {
                    Chart {
                        SectorMark(
                            angle: .value("Thin pool", pct),
                            innerRadius: .ratio(0.70),
                            angularInset: 1.4
                        )
                        .foregroundStyle(color)
                        SectorMark(
                            angle: .value("Headroom", max(1 - pct, 0.001)),
                            innerRadius: .ratio(0.70),
                            angularInset: 1.4
                        )
                        .foregroundStyle(Color.white.opacity(0.08))
                    }
                    .chartLegend(.hidden)
                    .shadow(color: color.opacity(0.30), radius: 14)
                    VStack(spacing: 0) {
                        Text("\(Int(pct * 100))")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(color)
                        Text("THIN")
                            .font(BeagleTheme.dataFont(size: 9, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
                .frame(width: 156, height: 156)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct ThermalMatrixPanel: View {
    let nodes: [SuperNode]

    var body: some View {
        LiquidGlassSurface(elevated: false, truth: .remembered) {
            VStack(alignment: .leading, spacing: 12) {
                PanelTitle(icon: "thermometer.medium", title: "Thermal", truth: .remembered)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                    ForEach(0..<24, id: \.self) { index in
                        let node = nodes[index % nodes.count]
                        RoundedRectangle(cornerRadius: 6)
                            .fill(thermalColor(node.temperature + Double(index % 5) * 0.015).opacity(0.78))
                            .frame(height: 22)
                            .shadow(color: thermalColor(node.temperature).opacity(0.16), radius: 5)
                    }
                }
            }
        }
    }

    private func thermalColor(_ value: Double) -> Color {
        if value > 0.78 { return WorkbenchTone.rose }
        if value > 0.58 { return WorkbenchTone.amber }
        return WorkbenchTone.cyan
    }
}

private struct NodeStackPanel: View {
    let nodes: [SuperNode]

    var body: some View {
        LiquidGlassSurface(elevated: false, truth: .observed) {
            VStack(alignment: .leading, spacing: 10) {
                PanelTitle(icon: "square.stack.3d.up.fill", title: "Nodes", truth: .observed)
                ForEach(nodes) { node in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(node.accent)
                            .frame(width: 8, height: 8)
                            .shadow(color: node.accent.opacity(0.6), radius: 6)
                        Text(node.id.uppercased())
                            .font(BeagleTheme.dataFont(size: 10, weight: .bold))
                            .foregroundStyle(BeagleTheme.textData)
                        Spacer()
                        MiniBar(value: node.cpu, color: WorkbenchTone.cyan)
                        MiniBar(value: node.gpu, color: node.accent)
                    }
                }
            }
        }
    }
}

private struct MiniBar: View {
    let value: Double
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.07))
            Capsule().fill(color.opacity(0.75)).frame(width: 34 * value)
        }
        .frame(width: 34, height: 5)
    }
}

private struct SuperActionPanel: View {
    var body: some View {
        LiquidGlassSurface(elevated: false, truth: .declared) {
            VStack(spacing: 12) {
                PanelTitle(icon: "lock.shield.fill", title: "Action Gate", truth: .declared)
                HStack(spacing: 10) {
                    GateButton(icon: "stethoscope", color: WorkbenchTone.cyan)
                    GateButton(icon: "arrow.triangle.2.circlepath", color: WorkbenchTone.amber)
                    GateButton(icon: "power", color: WorkbenchTone.rose)
                }
            }
        }
    }
}

private struct GateButton: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.24), lineWidth: 1))
    }
}

private struct ClusterPulsePanel: View {
    let source: SupercomputingSource
    let error: String?

    var body: some View {
        LiquidGlassSurface(elevated: false, truth: source.truth) {
            VStack(alignment: .leading, spacing: 10) {
                PanelTitle(icon: "waveform", title: "Pulse", truth: source.truth)
                SignalField(intensity: 1.20)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WorkbenchTone.cyan.opacity(0.14), lineWidth: 1))
                if let error {
                    HStack(spacing: 7) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(WorkbenchTone.amber)
                        Text(error)
                            .font(BeagleTheme.dataFont(size: 9, weight: .medium))
                            .lineLimit(2)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
            }
        }
    }
}

private struct PanelTitle: View {
    let icon: String
    let title: String
    let truth: TruthMode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BeagleTheme.color(for: truth))
            Text(title.uppercased())
                .font(BeagleTheme.dataFont(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(BeagleTheme.textTertiary)
            Spacer()
            TruthBadge(truth, compact: true)
        }
    }
}
