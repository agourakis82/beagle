//
//  MoshiSessionManager.swift
//  BeagleCore
//
//  Full-duplex voice session with the Moshi server running on the cluster L4.
//  Endpoint: GET /api/moshi/v1/session (WebSocket, proxied via beagle-core).
//
//  Wire format (as established by the Moshi Python server):
//    Client → Server: binary frames of raw float32 LE mono PCM at 24 kHz
//    Server → Client: binary frames (float32 audio) + text frames (Inner Monologue)
//
//  Connection lifecycle:
//    idle → connecting → active → disconnected
//
//  Call connect(serverURL:bearerToken:) to start, disconnect() to stop.
//  VoiceModeView observes inputLevel and innerMonologueText for UI.
//

import Foundation
import AVFoundation
import Observation

@Observable @MainActor
public final class MoshiSessionManager {

    public enum ConnectionState: Equatable, Sendable {
        case idle
        case connecting
        case active
        case disconnected
        case failed(String)
    }

    // MARK: - Observable state (read by VoiceModeView)

    public private(set) var connectionState: ConnectionState = .idle
    /// Normalized 0–1 RMS level of mic input; drives waveform bars.
    public private(set) var inputLevel: Float = 0
    /// Accumulated Inner Monologue text from server text frames.
    public private(set) var innerMonologueText: String = ""

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = true
        cfg.httpAdditionalHeaders = ["User-Agent": "BeagleCockpit/Moshi"]
        return URLSession(configuration: cfg)
    }()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var receiveTask: Task<Void, Never>?
    private let playFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    public func connect(serverURL: URL, bearerToken: String) async {
        guard connectionState == .idle || connectionState == .disconnected else { return }
        connectionState = .connecting

        guard await requestMicrophoneAccess() else {
            connectionState = .failed("Microphone access denied")
            return
        }

        var request = URLRequest(url: serverURL)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("beagle-operator", forHTTPHeaderField: "X-Beagle-Consumer")

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        connectionState = .active

        setupAudioEngine()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        teardownAudioEngine()
        inputLevel = 0
        connectionState = .disconnected
    }

    public func clearMonologue() {
        innerMonologueText = ""
    }

    // MARK: - Audio engine

    private func setupAudioEngine() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                   mode: .voiceChat,
                                   options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("[Moshi] AVAudioSession setup failed: \(error)")
        }
        #endif

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        // Install tap at hardware rate; downsample to 24 kHz for Moshi.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buf, _ in
            guard let self else { return }
            let rms = Self.rms(buf)
            Task { @MainActor in self.inputLevel = rms }
            guard let converted = Self.resample(buf, from: hwFormat, to: self.playFormat) else { return }
            let data = Self.asData(converted)
            Task { await self.sendAudio(data) }
        }

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: playFormat)

        do {
            try engine.start()
        } catch {
            print("[Moshi] engine.start failed: \(error)")
        }
    }

    private func teardownAudioEngine() {
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Send / receive

    private func sendAudio(_ data: Data) async {
        guard connectionState == .active else { return }
        try? await webSocketTask?.send(.data(data))
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let task = webSocketTask else { break }
            do {
                let msg = try await task.receive()
                switch msg {
                case .data(let d):
                    playback(d)
                case .string(let s):
                    await MainActor.run { innerMonologueText += s + " " }
                @unknown default:
                    break
                }
            } catch {
                break
            }
        }
        await MainActor.run {
            if connectionState == .active { connectionState = .disconnected }
            inputLevel = 0
        }
    }

    @MainActor
    private func playback(_ data: Data) {
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Float>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData else { return }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            guard let src = raw.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
            channelData[0].initialize(from: src, count: Int(frameCount))
        }
        if !playerNode.isPlaying { playerNode.play() }
        playerNode.scheduleBuffer(buffer)
    }

    // MARK: - Helpers

    private static func rms(_ buf: AVAudioPCMBuffer) -> Float {
        guard let data = buf.floatChannelData else { return 0 }
        let n = Int(buf.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[0][i] * data[0][i] }
        return min(1.0, sqrt(sum / Float(n)) * 8.0)
    }

    private static func resample(
        _ input: AVAudioPCMBuffer,
        from src: AVAudioFormat,
        to dst: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: src, to: dst) else { return nil }
        let ratio = dst.sampleRate / src.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var inputConsumed = false
        converter.convert(to: output, error: &error) { _, status in
            guard !inputConsumed else { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData
            inputConsumed = true
            return input
        }
        return error == nil ? output : nil
    }

    private static func asData(_ buf: AVAudioPCMBuffer) -> Data {
        guard let ptr = buf.floatChannelData else { return Data() }
        return Data(bytes: ptr[0], count: Int(buf.frameLength) * MemoryLayout<Float>.size)
    }

    private func requestMicrophoneAccess() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        #elseif os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
        #else
        return true
        #endif
    }
}
