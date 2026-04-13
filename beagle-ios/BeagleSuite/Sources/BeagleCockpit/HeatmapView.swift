//
//  HeatmapView.swift
//  BeagleCockpit
//
//  Generic scientific heatmap using Swift Charts RectangleMark.
//  Used for: GPU utilization grids, PBPK concentration maps, correlation matrices,
//  attention heatmaps, any 2D scalar field.
//

import SwiftUI
import Charts
import BeagleCore

struct HeatmapView: View {
    let grid: [[Double]]
    let xLabels: [String]?
    let yLabels: [String]?
    let title: String?
    let colorScale: [Color]

    init(
        grid: [[Double]],
        xLabels: [String]? = nil,
        yLabels: [String]? = nil,
        title: String? = nil,
        colorScale: [Color] = [
            Color(red: 0.05, green: 0.05, blue: 0.2),  // deep blue
            Color(red: 0.1, green: 0.4, blue: 0.6),     // teal-blue
            BeagleTheme.truthObserved,                    // teal
            Color(red: 0.2, green: 0.85, blue: 0.4),     // green
            BeagleTheme.postureWarm,                      // gold
            BeagleTheme.stateError                        // red (hot)
        ]
    ) {
        self.grid = grid
        self.xLabels = xLabels
        self.yLabels = yLabels
        self.title = title
        self.colorScale = colorScale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            if let title {
                Text(title)
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
            }

            Chart {
                ForEach(0..<grid.count, id: \.self) { row in
                    ForEach(0..<grid[row].count, id: \.self) { col in
                        RectangleMark(
                            xStart: .value("X", col),
                            xEnd: .value("X", col + 1),
                            yStart: .value("Y", row),
                            yEnd: .value("Y", row + 1)
                        )
                        .foregroundStyle(by: .value("Value", grid[row][col]))
                    }
                }
            }
            .chartForegroundStyleScale(range: Gradient(colors: colorScale))
            .chartXAxis {
                if let xLabels {
                    AxisMarks(values: Array(0..<xLabels.count)) { value in
                        AxisValueLabel {
                            if let idx = value.as(Int.self), idx < xLabels.count {
                                Text(xLabels[idx])
                                    .font(BeagleFont.dataSmall.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                        }
                    }
                } else {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
            }
            .chartYAxis {
                if let yLabels {
                    AxisMarks(values: Array(0..<yLabels.count)) { value in
                        AxisValueLabel {
                            if let idx = value.as(Int.self), idx < yLabels.count {
                                Text(yLabels[idx])
                                    .font(BeagleFont.dataSmall.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                        }
                    }
                } else {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
            }
            .chartLegend(.hidden)
        }
    }
}

// MARK: - GPU Utilization Heatmap (specialized)

struct GPUHeatmapView: View {
    let metrics: [GPUNodeMetric]

    private var computedGrid: (grid: [[Double]], xLabels: [String], yLabels: [String]) {
        let nodes = Set(metrics.compactMap(\.node)).sorted()
        let maxGPUs = metrics.map { $0.gpuId ?? 0 }.max() ?? 0
        var grid: [[Double]] = []
        for node in nodes {
            var row: [Double] = []
            for gpu in 0...maxGPUs {
                let metric = metrics.first { $0.node == node && $0.gpuId == gpu }
                row.append(metric?.utilization ?? 0)
            }
            grid.append(row)
        }
        return (grid, (0...maxGPUs).map { "GPU\($0)" }, nodes)
    }

    var body: some View {
        let data = computedGrid
        HeatmapView(
            grid: data.grid,
            xLabels: data.xLabels,
            yLabels: data.yLabels,
            title: "GPU Utilization",
            colorScale: [
                Color(red: 0.05, green: 0.08, blue: 0.15),
                BeagleTheme.truthObserved.opacity(0.5),
                BeagleTheme.truthObserved,
                BeagleTheme.postureWarm,
                BeagleTheme.stateError
            ]
        )
    }
}
