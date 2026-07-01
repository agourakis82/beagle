//
//  VoiceAcousticAnalyzer.swift
//  BeagleCockpit
//
//  Pure DSP for lightweight voice-acoustic features extracted from the companion chat's
//  ordinary speech — a natural byproduct of conversations the user already has, no extra
//  instrumentation. Scope for v1 (deliberately narrow): F0 mean/variance via autocorrelation,
//  RMS loudness in dB, and pause-ratio via silence detection over the same buffer — NOT
//  clinical-grade jitter/shimmer (that needs a more robust voice-analysis library and is
//  explicitly out of scope for this round).
//
//  No AVFoundation dependency — takes plain [Float] sample arrays, so this is independently
//  unit-testable, in the same spirit as BaroSyncEngine.BaroMath.
//

import Foundation
import Accelerate

public enum VoiceAcousticAnalyzer {

    /// Per-turn acoustic summary, ready to become PhysioHealthSample rows.
    public struct TurnAcousticSummary: Sendable, Equatable {
        public let f0MeanHz: Double?
        public let f0VarianceHz: Double?
        public let rmsDb: Double
        public let pauseRatio: Double
        public let speechRateWpm: Double?

        public init(f0MeanHz: Double?, f0VarianceHz: Double?, rmsDb: Double, pauseRatio: Double, speechRateWpm: Double?) {
            self.f0MeanHz = f0MeanHz
            self.f0VarianceHz = f0VarianceHz
            self.rmsDb = rmsDb
            self.pauseRatio = pauseRatio
            self.speechRateWpm = speechRateWpm
        }
    }

    /// RMS loudness in dBFS (silence = -infinity, clamped to a floor for sanity).
    public static func rmsDb(samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -120 }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        guard rms > 0 else { return -120 }
        return max(Double(20 * log10(rms)), -120)
    }

    /// A window is "silent" when its RMS falls below thresholdDb — used to accumulate
    /// pause-ratio across a turn without needing a full VAD model.
    public static func isSilent(samples: [Float], thresholdDb: Double = -45) -> Bool {
        rmsDb(samples: samples) < thresholdDb
    }

    /// Autocorrelation-based fundamental frequency (F0) estimate for one analysis window.
    /// Searches lags corresponding to the typical human speech F0 range (80-400 Hz) and
    /// returns the lag with the strongest normalized autocorrelation peak, converted to Hz.
    /// Returns nil for windows too quiet/short to yield a usable estimate.
    public static func estimateF0(samples: [Float], sampleRate: Double) -> Double? {
        guard samples.count > 64, !isSilent(samples: samples) else { return nil }

        let minHz = 80.0, maxHz = 400.0
        let minLag = Int(sampleRate / maxHz)
        let maxLag = min(Int(sampleRate / minHz), samples.count - 1)
        guard minLag > 0, maxLag > minLag else { return nil }

        // Zero-mean the window so DC offset doesn't bias the autocorrelation.
        var mean: Float = 0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(samples.count))
        var centered = samples
        var negMean = -mean
        vDSP_vsadd(samples, 1, &negMean, &centered, 1, vDSP_Length(samples.count))

        var energy0: Float = 0
        vDSP_dotpr(centered, 1, centered, 1, &energy0, vDSP_Length(centered.count))
        guard energy0 > 0 else { return nil }

        var bestLag = -1
        var bestScore: Float = 0
        for lag in minLag...maxLag {
            let n = centered.count - lag
            guard n > 0 else { continue }
            var score: Float = 0
            centered.withUnsafeBufferPointer { buf in
                vDSP_dotpr(buf.baseAddress!, 1, buf.baseAddress! + lag, 1, &score, vDSP_Length(n))
            }
            let normalized = score / energy0
            if normalized > bestScore {
                bestScore = normalized
                bestLag = lag
            }
        }
        // A weak peak means no clear periodicity (unvoiced/noisy segment) — don't report a
        // spurious pitch.
        guard bestLag > 0, bestScore > 0.3 else { return nil }
        return sampleRate / Double(bestLag)
    }

    /// Summarize a whole turn from its constituent analysis windows (each ~20-30ms of raw
    /// samples, as accumulated by the caller during the STT tap) plus transcript-derived
    /// speech rate.
    public static func summarize(
        windows: [[Float]],
        sampleRate: Double,
        transcriptWordCount: Int?,
        turnDurationSeconds: Double
    ) -> TurnAcousticSummary {
        let f0s = windows.compactMap { estimateF0(samples: $0, sampleRate: sampleRate) }
        let f0Mean = f0s.isEmpty ? nil : f0s.reduce(0, +) / Double(f0s.count)
        let f0Variance: Double? = {
            guard let mean = f0Mean, f0s.count > 1 else { return nil }
            let sumSq = f0s.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            return sumSq / Double(f0s.count - 1)
        }()

        let allSamples = windows.flatMap { $0 }
        let rms = rmsDb(samples: allSamples)

        let silentWindows = windows.filter { isSilent(samples: $0) }.count
        let pauseRatio = windows.isEmpty ? 0 : Double(silentWindows) / Double(windows.count)

        let speechRate: Double? = {
            guard let words = transcriptWordCount, words > 0, turnDurationSeconds > 0 else { return nil }
            return Double(words) / (turnDurationSeconds / 60.0)
        }()

        return TurnAcousticSummary(
            f0MeanHz: f0Mean,
            f0VarianceHz: f0Variance,
            rmsDb: rms,
            pauseRatio: pauseRatio,
            speechRateWpm: speechRate
        )
    }
}
