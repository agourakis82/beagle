//
//  DiagnosticsView.swift
//  BeagleCockpit
//
//  Automated test results UI. One tap → runs all checks.
//  Access: Mind → gear → Diagnostics
//

import SwiftUI
import BeagleCore

struct DiagnosticsView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @State private var runner = DiagnosticsRunner()

    var body: some View {
        ScrollView {
            VStack(spacing: BeagleSpacing.lg) {
                headerCard
                ForEach(runner.categories, id: \.self) { category in
                    categorySection(category)
                }
                if runner.overallResult != .pending {
                    summaryCard
                }
                Spacer(minLength: BeagleSpacing.jumbo)
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.lg)
        }
        .background { DiagnosticsGradient(result: runner.overallResult) }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayModeIfAvailable(.inline)
        .toolbar {
            ToolbarItem(placement: diagnosticsToolbarPlacement) {
                if runner.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BeagleTheme.postureWarm)
                } else {
                    Button {
                        Task { await runner.runAll(catalog: catalog, cognitive: cognitive) }
                    } label: {
                        Label("Run", systemImage: "play.fill")
                            .font(BeagleFont.footnote.font)
                    }
                    .tint(BeagleTheme.truthObserved)
                }
            }
        }
    }

    private var diagnosticsToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarTrailing
        #endif
    }

    // MARK: - Header

    private var headerCard: some View {
        GlassPanel(elevation: .raised, truth: overallTruthMode) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.sm) {
                    overallStatusIcon
                    VStack(alignment: .leading, spacing: 3) {
                        Text(overallTitle)
                            .font(BeagleFont.title3.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        if let detail = runner.overallResult.detail {
                            Text(detail)
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                        }
                    }
                    Spacer()
                    if runner.overallResult != .pending {
                        scoreBadge
                    }
                }

                if runner.overallResult == .pending {
                    Button {
                        Task { await runner.runAll(catalog: catalog, cognitive: cognitive) }
                    } label: {
                        Label("Run All Tests", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(runner.isRunning)
                } else if !runner.isRunning {
                    Button {
                        runner.reset()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButton(color: BeagleTheme.textTertiary))
                }
            }
        }
    }

    private var overallStatusIcon: some View {
        ZStack {
            Circle()
                .fill(runner.overallResult.color.opacity(0.1))
                .frame(width: 44, height: 44)
            Image(systemName: runner.overallResult.icon)
                .font(.system(size: 20))
                .foregroundStyle(runner.overallResult.color)
                .symbolEffect(.pulse, isActive: runner.isRunning)
        }
    }

    private var overallTitle: String {
        switch runner.overallResult {
        case .pending:         return "Ready to test"
        case .running:         return "Running..."
        case .passed:          return "All systems go"
        case .failed:          return "Issues detected"
        case .skipped:         return "Completed"
        }
    }

    private var overallTruthMode: TruthMode {
        switch runner.overallResult {
        case .pending:  return .declared
        case .running:  return .remembered
        case .passed:   return .observed
        case .failed:   return .stale
        case .skipped:  return .declared
        }
    }

    private var scoreBadge: some View {
        VStack(spacing: 3) {
            Text("\(runner.passCount + runner.skipCount)/\(runner.tests.count)")
                .font(BeagleFont.dataProminent.font)
                .foregroundStyle(runner.failCount == 0 ? BeagleTheme.truthObserved : BeagleTheme.stateError)
            Text("passing")
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }

    // MARK: - Category sections

    private func categorySection(_ category: String) -> some View {
        let tests = runner.tests(in: category)
        let allDone = tests.allSatisfy { $0.result != .pending && $0.result != .running }
        let anyFailed = tests.contains { $0.result.isFailed }

        return VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            HStack(spacing: BeagleSpacing.xs) {
                Text(category.uppercased())
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .tracking(0.5)
                Spacer()
                if allDone {
                    Circle()
                        .fill(anyFailed ? BeagleTheme.stateError : BeagleTheme.truthObserved)
                        .frame(width: 6, height: 6)
                }
            }

            VStack(spacing: 1) {
                ForEach(tests) { test in
                    testRow(test)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.surface1.opacity(0.4))
            )
            .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func testRow(_ test: DiagTest) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: test.result.icon)
                .font(.system(size: 14))
                .foregroundStyle(test.result.color)
                .symbolEffect(.pulse, isActive: test.result == .running)
                .frame(width: 20)

            Text(test.name)
                .font(BeagleFont.subheadline.font)
                .foregroundStyle(BeagleTheme.textPrimary)

            Spacer()

            if let detail = test.result.detail {
                Text(detail)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(test.result.color.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm)
        .frame(minHeight: 44)
        .background(
            test.result.isFailed
            ? BeagleTheme.stateError.opacity(0.04)
            : Color.clear
        )
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        GlassPanel(elevation: .raised, truth: runner.failCount == 0 ? .observed : .stale) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("SUMMARY")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .tracking(0.5)

                HStack(spacing: BeagleSpacing.lg) {
                    summaryPill(count: runner.passCount, label: "passed", color: BeagleTheme.truthObserved)
                    summaryPill(count: runner.failCount, label: "failed", color: BeagleTheme.stateError)
                    summaryPill(count: runner.skipCount, label: "skipped", color: BeagleTheme.textTertiary)
                }

                if runner.totalDurationMs > 0 {
                    Text("\(runner.totalDurationMs)ms total")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }

                if runner.failCount > 0 {
                    let failedTests = runner.tests.filter(\.result.isFailed)
                    Text("Fix: " + failedTests.map(\.name).joined(separator: ", "))
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.stateError.opacity(0.8))
                        .lineLimit(3)
                }
            }
        }
    }

    private func summaryPill(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(BeagleFont.dataProminent.font)
                .foregroundStyle(count > 0 ? color : BeagleTheme.textTertiary)
            Text(label)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }
}

// MARK: - Background

private struct DiagnosticsGradient: View {
    let result: DiagResult
    // Living mesh background removed — flat adaptive surface (redesign).
    var body: some View {
        BeagleTheme.surface0.ignoresSafeArea()
    }
}
