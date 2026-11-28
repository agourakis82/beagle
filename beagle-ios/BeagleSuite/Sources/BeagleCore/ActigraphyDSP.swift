//
//  ActigraphyDSP.swift
//  BeagleCore
//
//  Pure signal-processing math for actigraphy complexity metrics — Detrended Fluctuation
//  Analysis (DFA) and Sample Entropy (SampEn) over 1-minute-epoch activity counts derived
//  from raw accelerometer data. Complexity/regulation metrics, not raw step counts — the
//  N-of-1 relapse-prediction literature (Scientific Reports 2023, n=277) used exactly this
//  signal-processing approach on per-patient wrist actigraphy to catch circadian disturbance
//  2-3 weeks before depressive relapse.
//
//  No CoreMotion dependency — takes plain [Double] epoch-count arrays, so this is
//  independently unit-testable, in the same spirit as BaroSyncEngine.BaroMath and
//  VoiceAcousticAnalyzer.
//

import Foundation

public enum ActigraphyDSP {

    /// Collapse raw tri-axial accelerometer samples into one activity-count value per
    /// 1-minute epoch: sum of the magnitude of high-pass-filtered acceleration (removes the
    /// gravity DC component), a standard actigraphy activity-count proxy.
    public static func epochActivityCounts(
        magnitudes: [Double],
        samplesPerEpoch: Int
    ) -> [Double] {
        guard samplesPerEpoch > 0, !magnitudes.isEmpty else { return [] }
        // High-pass filter: subtract a slow-moving mean (removes gravity/orientation drift)
        // so what remains reflects movement, not device tilt.
        let alpha = 0.9
        var filtered: [Double] = []
        filtered.reserveCapacity(magnitudes.count)
        var runningMean = magnitudes[0]
        for m in magnitudes {
            runningMean = alpha * runningMean + (1 - alpha) * m
            filtered.append(abs(m - runningMean))
        }

        var counts: [Double] = []
        var i = 0
        while i < filtered.count {
            let end = min(i + samplesPerEpoch, filtered.count)
            let epoch = filtered[i..<end]
            counts.append(epoch.reduce(0, +))
            i = end
        }
        return counts
    }

    /// Detrended Fluctuation Analysis scaling exponent (alpha) over a daily epoch-count
    /// series. alpha ~0.5 = uncorrelated noise, ~1.0 = well-regulated 1/f fractal structure
    /// (healthy circadian activity regulation), >1.0 or <0.5 = degraded regulation.
    /// Returns nil when there isn't enough data for a meaningful fit (needs several window
    /// sizes with multiple non-overlapping windows each).
    public static func dfaAlpha(series: [Double]) -> Double? {
        guard series.count >= 40 else { return nil }

        let mean = series.reduce(0, +) / Double(series.count)
        var cumulative: [Double] = []
        cumulative.reserveCapacity(series.count)
        var running = 0.0
        for x in series {
            running += (x - mean)
            cumulative.append(running)
        }

        // Window sizes: logarithmically spaced from 4 epochs to a quarter of the series.
        let minWindow = 4
        let maxWindow = series.count / 4
        guard maxWindow > minWindow else { return nil }

        var windowSizes: [Int] = []
        var n = Double(minWindow)
        while Int(n) <= maxWindow {
            windowSizes.append(Int(n))
            n *= 1.3
        }
        windowSizes = Array(Set(windowSizes)).sorted()
        guard windowSizes.count >= 3 else { return nil }

        var logN: [Double] = []
        var logF: [Double] = []

        for windowSize in windowSizes {
            let windowCount = cumulative.count / windowSize
            guard windowCount >= 2 else { continue }
            var squaredResiduals: [Double] = []
            for w in 0..<windowCount {
                let start = w * windowSize
                let segment = Array(cumulative[start..<(start + windowSize)])
                guard let residual = detrendedMeanSquare(segment) else { continue }
                squaredResiduals.append(residual)
            }
            guard !squaredResiduals.isEmpty else { continue }
            let fn = (squaredResiduals.reduce(0, +) / Double(squaredResiduals.count)).squareRoot()
            guard fn > 0 else { continue }
            logN.append(Foundation.log(Double(windowSize)))
            logF.append(Foundation.log(fn))
        }

        guard logN.count >= 3 else { return nil }
        return linearRegressionSlope(x: logN, y: logF)
    }

    /// Local linear-trend detrended mean-square residual for one window (least-squares fit
    /// of a line to the segment, then mean squared deviation from that line).
    private static func detrendedMeanSquare(_ segment: [Double]) -> Double? {
        let n = segment.count
        guard n >= 2 else { return nil }
        let xs = (0..<n).map { Double($0) }
        guard let (slope, intercept) = linearFit(x: xs, y: segment) else { return nil }
        var sumSq = 0.0
        for i in 0..<n {
            let trend = slope * xs[i] + intercept
            let diff = segment[i] - trend
            sumSq += diff * diff
        }
        return sumSq / Double(n)
    }

    private static func linearFit(x: [Double], y: [Double]) -> (slope: Double, intercept: Double)? {
        let n = Double(x.count)
        guard n > 1 else { return nil }
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = x.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumXX - sumX * sumX
        guard denom != 0 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        return (slope, intercept)
    }

    private static func linearRegressionSlope(x: [Double], y: [Double]) -> Double? {
        linearFit(x: x, y: y)?.slope
    }

    /// Sample entropy (SampEn) — regularity/randomness of the series; higher = more
    /// unpredictable. embedding dimension m=2, tolerance r=0.2*stddev are the conventional
    /// defaults used across the actigraphy-complexity literature.
    public static func sampleEntropy(series: [Double], m: Int = 2, rFactor: Double = 0.2) -> Double? {
        guard series.count > m + 1 else { return nil }
        let mean = series.reduce(0, +) / Double(series.count)
        let variance = series.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(series.count)
        let stddev = variance.squareRoot()
        guard stddev > 0 else { return nil }
        let r = rFactor * stddev

        func countMatches(dimension: Int) -> Int {
            var count = 0
            let n = series.count - dimension
            guard n > 1 else { return 0 }
            for i in 0..<n {
                for j in (i + 1)..<n {
                    var maxDiff = 0.0
                    for k in 0..<dimension {
                        maxDiff = max(maxDiff, abs(series[i + k] - series[j + k]))
                    }
                    if maxDiff <= r { count += 1 }
                }
            }
            return count
        }

        let b = countMatches(dimension: m)
        let a = countMatches(dimension: m + 1)
        guard b > 0, a > 0 else { return nil }
        return -Foundation.log(Double(a) / Double(b))
    }
}
