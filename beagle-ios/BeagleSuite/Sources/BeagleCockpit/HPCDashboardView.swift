//
//  HPCDashboardView.swift
//  BeagleCockpit
//
//  HPC operations dashboard — GPU utilization heatmap, job queue Gantt,
//  resource allocation, job launcher. The computational heartbeat.
//

import SwiftUI
import Charts
import BeagleCore

struct HPCDashboardView: View {
    @Environment(HPCStore.self) private var hpc
    @State private var selectedJobKind: String?

    private let jobKinds = [
        ("pbpk",     "cross.vial.fill",      "PBPK"),
        ("helio",    "sun.max.fill",          "Helio"),
        ("scaffold", "cube.transparent.fill", "Scaffold"),
        ("pcs",      "atom",                  "PCS"),
        ("kec",      "brain.head.profile",    "KEC")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
                if hpc.jobQueue.mode == .stale, let error = hpc.jobQueue.error {
                    hpcErrorBanner(error)
                }
                gpuOverview
                gpuHeatmap
                jobLauncher
                jobQueueGantt
                runningJobs
                if hpc.runningJobs.isEmpty && hpc.jobs.isEmpty {
                    emptyJobsState
                }
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.md)
        }
        .background { HealthPulseGradient(truth: hpc.jobQueue.mode) }
        .navigationTitle("Cluster")
        .task { await hpc.refresh() }
        .refreshable { await hpc.refresh() }
    }

    // MARK: - GPU Overview bar

    private var gpuOverview: some View {
        GlassPanel(elevation: .floating, truth: hpc.jobQueue.mode) {
            VStack(spacing: BeagleSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(hpc.allocatedGPUs)")
                        .font(BeagleFont.hero.font)
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text("/ \(hpc.totalGPUs) GPUs")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f%%", hpc.gpuUtilizationPercent))
                        .font(BeagleFont.title2.font)
                        .foregroundStyle(utilizationColor)
                }

                // Utilization bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(utilizationColor.gradient)
                            .frame(width: geo.size.width * min(hpc.gpuUtilizationPercent / 100, 1.0))
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("\(hpc.runningJobs.count) jobs running")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer()
                    TruthBadge(hpc.jobQueue.mode, compact: true)
                }
            }
        }
    }

    private var utilizationColor: Color {
        let pct = hpc.gpuUtilizationPercent
        if pct > 90 { return BeagleTheme.stateError }
        if pct > 70 { return BeagleTheme.postureWarm }
        return BeagleTheme.truthObserved
    }

    // MARK: - GPU Heatmap

    @ViewBuilder
    private var gpuHeatmap: some View {
        if !hpc.gpuMetrics.isEmpty {
            GlassPanel(elevation: .raised) {
                GPUHeatmapView(metrics: hpc.gpuMetrics)
                    .frame(height: 120)
            }
        }
    }

    // MARK: - Job Launcher

    private var jobLauncher: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text("Submit job")
                .font(BeagleFont.caption.font)
                .fontWeight(.medium)
                .foregroundStyle(BeagleTheme.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BeagleSpacing.sm) {
                    ForEach(jobKinds, id: \.0) { kind, icon, label in
                        Button {
                            Task {
                                selectedJobKind = kind
                                _ = await hpc.submitJob(kind: kind)
                                try? await Task.sleep(for: .seconds(0.5))
                                selectedJobKind = nil
                            }
                        } label: {
                            VStack(spacing: BeagleSpacing.xxs) {
                                Image(systemName: icon)
                                    .font(.system(size: 20))
                                    .symbolEffect(.pulse, isActive: selectedJobKind == kind)
                                Text(label)
                                    .font(BeagleFont.dataSmall.font)
                            }
                            .foregroundStyle(selectedJobKind == kind ? BeagleTheme.truthObserved : BeagleTheme.textSecondary)
                            .frame(width: 70, height: 60)
                            .background(
                                RoundedRectangle(cornerRadius: BeagleRadius.md)
                                    .fill(selectedJobKind == kind ? BeagleTheme.truthObserved.opacity(0.1) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: BeagleRadius.md)
                                    .strokeBorder(selectedJobKind == kind ? BeagleTheme.truthObserved.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(weight: .medium), trigger: selectedJobKind)
                    }
                }
            }
        }
    }

    // MARK: - Job Queue Gantt

    @ViewBuilder
    private var jobQueueGantt: some View {
        if !hpc.jobs.isEmpty {
            GlassPanel(elevation: .raised) {
                VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                    HStack {
                        Text("Job Queue")
                            .font(BeagleFont.headline.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        TruthBadge(hpc.jobQueue.mode, compact: true)
                        Spacer()
                        Text("\(hpc.jobs.count) total")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }

                    Chart(hpc.jobs.prefix(10)) { job in
                        BarMark(
                            x: .value("Job", job.kind ?? "unknown"),
                            y: .value("GPUs", job.gpuCount ?? 1)
                        )
                        .foregroundStyle(jobColor(job).gradient)
                        .cornerRadius(BeagleRadius.sm)
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(BeagleFont.dataSmall.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(BeagleFont.dataSmall.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
    }

    // MARK: - Running Jobs List

    @ViewBuilder
    private var runningJobs: some View {
        if !hpc.runningJobs.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("Running")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.truthObserved)

                ForEach(hpc.runningJobs) { job in
                    GlassPanel(elevation: .raised, truth: .observed) {
                        HStack(spacing: BeagleSpacing.sm) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(BeagleTheme.truthObserved)
                                .symbolEffect(.pulse)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.kind ?? "job")
                                    .font(BeagleFont.headline.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                HStack(spacing: BeagleSpacing.xs) {
                                    Text(job.jobId ?? "—")
                                        .font(BeagleFont.dataSmall.font)
                                    if let nodes = job.nodeList {
                                        Text("on \(nodes)")
                                            .font(BeagleFont.dataSmall.font)
                                    }
                                    if let gpus = job.gpuCount {
                                        Text("\(gpus) GPU\(gpus > 1 ? "s" : "")")
                                            .font(BeagleFont.dataSmall.font)
                                            .foregroundStyle(BeagleTheme.truthObserved)
                                    }
                                }
                                .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func jobColor(_ job: HPCJob) -> Color {
        if job.isCompleted { return BeagleTheme.truthObserved }
        if job.isRunning { return BeagleTheme.postureWarm }
        return BeagleTheme.truthDeclared
    }

    // MARK: - Error + empty states

    private func hpcErrorBanner(_ error: String) -> some View {
        GlassPanel(elevation: .raised, truth: .stale) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BeagleTheme.stateError)
                    Text("Cluster unreachable")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                }
                Text(error)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
                Button {
                    Task { await hpc.refresh() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButton(color: BeagleTheme.stateError))
            }
        }
    }

    private var emptyJobsState: some View {
        VStack(spacing: BeagleSpacing.sm) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(BeagleTheme.textTertiary.opacity(0.4))
            Text("No jobs running")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textTertiary)
            Text("Use the launcher above to submit a job")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BeagleSpacing.xl)
    }
}
