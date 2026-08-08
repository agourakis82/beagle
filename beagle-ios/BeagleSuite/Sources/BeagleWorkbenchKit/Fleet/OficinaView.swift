#if os(iOS) || os(macOS)
import SwiftUI
import BeagleCore

// OFICINA — the dev half of Mission Control, in brass.
//
// It answers exactly three operational questions, and nothing else exists on this screen:
//   1. "Está verde?"     → main's verdict, then every open PR, red first.
//   2. "O que quebrou?"  → the NAMES of the failing checks, tappable to the run.
//   3. "Onde estou?"     → branch, head commit, uncommitted files.
//
// It cannot start a build. The server side is read-only too: a souc build costs ~61GiB and
// minutes, so this screen reads verdicts instead of producing them — and says plainly when its
// reading is old rather than implying a freshness it does not have.
public struct OficinaView: View {
    @State private var client = OficinaClient()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    private static let canvas = Color(red: 0.043, green: 0.055, blue: 0.086)
    /// Brass: the dev half's identity, distinct from the Frota's per-agent hues.
    private static let brass = Color(red: 0.85, green: 0.72, blue: 0.50)

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerPanel
                if let err = client.fetchError { problemPanel(err) }
                prSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Self.canvas.ignoresSafeArea())
        .navigationTitle("Oficina")
        .refreshable { await client.refresh() }
        .onAppear { client.start() }
        .onDisappear { client.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await client.refresh() } }
        }
    }

    // MARK: - "Está verde?" + "Onde estou?"

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                verdictLamp(client.state.mainVerdict)
                VStack(alignment: .leading, spacing: 1) {
                    Text("main").font(.system(.body, weight: .semibold)).foregroundStyle(.white)
                    Text(client.state.mainVerdict.label)
                        .font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                truthBadge
            }

            if let head = client.state.head {
                Divider().overlay(Color.white.opacity(0.10))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2).foregroundStyle(Self.brass)
                        Text(head.branch)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    if !head.subject.isEmpty {
                        Text(head.subject)
                            .font(.caption2).foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        Text(head.sha)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                        if let dirty = head.dirtyFiles, dirty > 0 {
                            Text("\(dirty) arquivo\(dirty == 1 ? "" : "s") não commitado\(dirty == 1 ? "" : "s")")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Self.brass.opacity(0.9))
                        }
                        if let at = head.committedAt {
                            Text(at, style: .relative)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oficinaGlass(tint: client.state.mainVerdict == .red ? .red.opacity(0.7) : nil)
    }

    /// Truth mode, per the platform invariant — the reading's age, or why it is old.
    private var truthBadge: some View {
        Group {
            if client.state.observedAt == nil {
                Text("não observado").foregroundStyle(BeagleTheme.truthDeclared)
            } else if client.state.error != nil {
                Text("leitura antiga").foregroundStyle(.orange)
            } else if client.state.isStale() {
                Text("leitura antiga").foregroundStyle(.orange)
            } else if let at = client.state.observedAt {
                Text(at, style: .relative).foregroundStyle(BeagleTheme.truthObserved.opacity(0.8))
            }
        }
        .font(.system(.caption2, weight: .medium).monospacedDigit())
    }

    /// A problem states what happened AND what to do — never a bare "Error".
    private func problemPanel(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.footnote).foregroundStyle(.white.opacity(0.9))
                Button("Tentar de novo") { Task { await client.refresh() } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            Spacer()
        }
        .padding(12)
        .oficinaGlass(tint: .orange.opacity(0.5))
    }

    // MARK: - "O que quebrou?"

    private var prSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("PRS ABERTOS").font(.system(.caption, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(.white.opacity(0.55))
                if !client.state.red.isEmpty {
                    Text("\(client.state.red.count) vermelho\(client.state.red.count == 1 ? "" : "s")")
                        .font(.system(.caption2, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.red.opacity(0.28)))
                        .foregroundStyle(.white)
                }
                Spacer()
                if client.loading { ProgressView().controlSize(.small) }
            }

            if client.state.prs.isEmpty {
                Text(client.state.observedAt == nil
                     ? "Ainda sem leitura do cockpit."
                     : "Nenhum PR aberto.")
                    .font(.callout).foregroundStyle(.white.opacity(0.6))
                    .padding(.vertical, 8)
            } else {
                ForEach(client.state.ordered) { pr in
                    prCard(pr)
                }
            }
        }
    }

    private func prCard(_ pr: PRRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                verdictLamp(pr.verdict)
                Text("#\(pr.number)")
                    .font(.system(.subheadline, weight: .bold).monospacedDigit())
                    .foregroundStyle(Self.brass)
                if pr.draft {
                    Text("draft")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                // How much actually ran: "green over 1/4 checks" ≠ "green over 24/28".
                Text(pr.checksSummary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Text(pr.title)
                .font(.subheadline).foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)

            Text(pr.branch)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1).truncationMode(.middle)

            if !pr.failing.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pr.failing) { check in
                        Button {
                            if let u = URL(string: check.url) { openURL(u) }
                        } label: {
                            HStack(spacing: 6) {
                                Text("✕").font(.system(size: 9, weight: .black)).foregroundStyle(.red)
                                Text(check.name)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                if !check.workflow.isEmpty {
                                    Text(check.workflow)
                                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                                }
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 8)).foregroundStyle(.white.opacity(0.35))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Content, not chrome: the names sit in an opaque well.
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.32)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oficinaGlass(tint: pr.verdict == .red ? .red.opacity(0.55) : nil)
        .contentShape(Rectangle())
        .onTapGesture { if let u = URL(string: pr.url) { openURL(u) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PR \(pr.number), \(pr.verdict.label), \(pr.checksSummary) checks. \(pr.title)")
    }

    /// Light + glyph: the verdict encoded twice in one mark.
    private func verdictLamp(_ v: CIVerdict) -> some View {
        ZStack {
            Circle().fill(color(v).opacity(0.9)).frame(width: 11, height: 11)
                .shadow(color: color(v).opacity(0.5), radius: v == .red ? 6 : 2)
            Text(v.glyph)
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(Self.canvas)
        }
    }

    private func color(_ v: CIVerdict) -> Color {
        switch v {
        case .green: return BeagleTheme.truthObserved
        case .red: return .red
        case .pending: return Self.brass
        case .unknown: return Color(white: 0.55)
        }
    }
}

private extension View {
    @ViewBuilder
    func oficinaGlass(tint: Color?) -> some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(tint ?? Color.white.opacity(0.08), lineWidth: tint == nil ? 0.5 : 1.2)
                )
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(tint ?? Color.white.opacity(0.08), lineWidth: tint == nil ? 0.5 : 1.2)
                )
        }
    }
}
#endif
