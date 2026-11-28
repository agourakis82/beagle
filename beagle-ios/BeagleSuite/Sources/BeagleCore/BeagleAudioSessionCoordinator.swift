//
//  BeagleAudioSessionCoordinator.swift
//  BeagleCore
//
//  Serialized, off-main-thread coordinator for `AVAudioSession` activation and
//  deactivation on iOS and visionOS. Prevents main-thread UI unresponsiveness
//  warnings from synchronous `AVAudioSession.setActive(_:options:)` calls while
//  keeping activation/deactivation transitions strictly ordered.
//

import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

#if os(iOS) || os(visionOS)
public actor BeagleAudioSessionCoordinator {
    public static let shared = BeagleAudioSessionCoordinator()

    private init() {}

    /// Activates a spoken-audio playback session (TTS / WAV replies).
    public func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    /// Activates a recording session for `SpeechRecognizer`.
    public func activateSpeechRecording(
        measurementProfile: Bool,
        allowBluetoothForMeasurement: Bool = false
    ) throws {
        let session = AVAudioSession.sharedInstance()
        if measurementProfile {
            let options: AVAudioSession.CategoryOptions = allowBluetoothForMeasurement
                ? [.duckOthers, .allowBluetoothHFP]
                : [.duckOthers]
            try session.setCategory(.record, mode: .measurement, options: options)
        } else {
            #if os(iOS)
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.duckOthers, .allowBluetoothHFP, .defaultToSpeaker]
            )
            #else
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.duckOthers])
            #endif
        }
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Activates a full-duplex voice-chat session (OpenAI Live / Moshi).
    public func activateFullDuplexVoiceChat(
        preferredSampleRate: Double? = nil,
        preferredIOBufferDuration: TimeInterval? = nil,
        duckOthers: Bool = true
    ) throws {
        let session = AVAudioSession.sharedInstance()
        #if os(iOS)
        var options: AVAudioSession.CategoryOptions = [
            .defaultToSpeaker,
            .allowBluetoothHFP,
            .allowBluetoothA2DP,
        ]
        if duckOthers {
            options.insert(.duckOthers)
        }
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        #else
        let options: AVAudioSession.CategoryOptions = duckOthers ? [.duckOthers] : []
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        #endif

        if let preferredSampleRate {
            try? session.setPreferredSampleRate(preferredSampleRate)
        }
        if let preferredIOBufferDuration {
            try? session.setPreferredIOBufferDuration(preferredIOBufferDuration)
        }
        try session.setActive(true)
    }

    /// Deactivates the shared audio session and notifies other apps to resume.
    public func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#endif
