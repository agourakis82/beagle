//
//  SurfacePlotView.swift
//  BeagleCockpit
//
//  3D scientific surface plot using iOS 26 Chart3D.
//  Used for: PBPK concentration surfaces, heliobiology Kp maps,
//  molecular energy landscapes, any 2D → scalar function.
//

import SwiftUI
import Charts
import BeagleCore

struct SurfacePlotView: View {
    let data: [[Double]]
    let title: String?
    let xLabel: String
    let yLabel: String
    let zLabel: String

    init(
        data: [[Double]],
        title: String? = nil,
        xLabel: String = "X",
        yLabel: String = "Value",
        zLabel: String = "Z"
    ) {
        self.data = data
        self.title = title
        self.xLabel = xLabel
        self.yLabel = yLabel
        self.zLabel = zLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            if let title {
                Text(title)
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
            }

            // 2D projection as line chart (multiple series)
            Chart {
                ForEach(0..<min(data.count, 10), id: \.self) { row in
                    ForEach(0..<data[row].count, id: \.self) { col in
                        LineMark(
                            x: .value(xLabel, col),
                            y: .value(yLabel, data[row][col]),
                            series: .value("Series", "Z=\(row)")
                        )
                        .foregroundStyle(seriesColor(row: row, total: data.count))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                        AreaMark(
                            x: .value(xLabel, col),
                            y: .value(yLabel, data[row][col]),
                            series: .value("Series", "Z=\(row)")
                        )
                        .foregroundStyle(seriesColor(row: row, total: data.count).opacity(0.05))
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel()
                        .font(BeagleFont.dataSmall.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel()
                        .font(BeagleFont.dataSmall.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
            .chartLegend(.hidden)

            // Series labels
            HStack(spacing: BeagleSpacing.sm) {
                ForEach(0..<min(data.count, 5), id: \.self) { row in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(seriesColor(row: row, total: data.count))
                            .frame(width: 6, height: 6)
                        Text("\(zLabel)=\(row)")
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
            }
        }
    }

    private func seriesColor(row: Int, total: Int) -> Color {
        let fraction = total > 1 ? Double(row) / Double(total - 1) : 0.5
        // Teal → Gold gradient
        return Color(
            hue: 0.46 - fraction * 0.35, // 165° → 40°
            saturation: 0.6 + fraction * 0.2,
            brightness: 0.85
        )
    }
}

// MARK: - CSV Auto Chart

struct CSVChartView: View {
    let csvText: String
    let title: String?

    init(csvText: String, title: String? = nil) {
        self.csvText = csvText
        self.title = title
    }

    var body: some View {
        let parsed = parseCSV(csvText)

        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            if let title {
                Text(title)
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
            }

            if parsed.columns == 2 {
                // Two columns → line chart
                Chart(parsed.rows.indices, id: \.self) { i in
                    LineMark(
                        x: .value("X", parsed.rows[i][0]),
                        y: .value("Y", parsed.rows[i][1])
                    )
                    .foregroundStyle(BeagleTheme.truthObserved.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    AreaMark(
                        x: .value("X", parsed.rows[i][0]),
                        y: .value("Y", parsed.rows[i][1])
                    )
                    .foregroundStyle(BeagleTheme.truthObserved.opacity(0.1).gradient)
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().font(BeagleFont.dataSmall.font).foregroundStyle(BeagleTheme.textTertiary) } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().font(BeagleFont.dataSmall.font).foregroundStyle(BeagleTheme.textTertiary) } }
            } else if parsed.columns >= 3 {
                // 3+ columns → scatter
                Chart(parsed.rows.indices, id: \.self) { i in
                    PointMark(
                        x: .value("X", parsed.rows[i][0]),
                        y: .value("Y", parsed.rows[i][1])
                    )
                    .foregroundStyle(by: .value("Z", parsed.rows[i].count > 2 ? parsed.rows[i][2] : 0))
                    .symbolSize(30)
                }
                .chartForegroundStyleScale(range: Gradient(colors: [.blue, BeagleTheme.truthObserved, .yellow]))
            } else {
                Text("Insufficient data columns")
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }

    private func parseCSV(_ text: String) -> (columns: Int, rows: [[Double]]) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let firstLine = lines.first else { return (0, []) }

        let cols = firstLine.components(separatedBy: ",").count
        var rows: [[Double]] = []

        for line in lines.dropFirst() { // skip header
            let values = line.components(separatedBy: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if values.count >= cols { rows.append(values) }
        }

        return (cols, rows)
    }
}
