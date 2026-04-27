//
//  WatchExocortexBridge.swift
//  BeagleCore
//
//  WatchConnectivity bridge for wrist micro-intentions and compact body context.
//

import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity

public struct WatchExocortexCapture: Codable, Sendable {
    public let text: String
    public let bodySummary: String?
    public let capturedAt: String

    public init(text: String, bodySummary: String? = nil, capturedAt: String = AssistedImportRequestFactory.isoTimestamp()) {
        self.text = text
        self.bodySummary = bodySummary
        self.capturedAt = capturedAt
    }
}

public final class WatchExocortexBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = WatchExocortexBridge()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var activated = false

    private override init() {
        super.init()
    }

    public func activate() {
        guard WCSession.isSupported(), !activated else { return }
        activated = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    public func sendCapture(_ capture: WatchExocortexCapture) async -> Bool {
        activate()
        guard
            WCSession.default.activationState == .activated,
            WCSession.default.isReachable,
            let data = try? encoder.encode(capture),
            let payload = String(data: data, encoding: .utf8)
        else {
            return false
        }
        return await withCheckedContinuation { continuation in
            WCSession.default.sendMessage(
                ["kind": "beagle-watch-capture", "payload": payload],
                replyHandler: { _ in continuation.resume(returning: true) },
                errorHandler: { _ in continuation.resume(returning: false) }
            )
        }
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    #if os(iOS) || os(visionOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard
            message["kind"] as? String == "beagle-watch-capture",
            let payload = message["payload"] as? String,
            let data = payload.data(using: .utf8),
            let capture = try? decoder.decode(WatchExocortexCapture.self, from: data)
        else {
            return
        }
        Task {
            let request = AssistedImportRequestFactory.capture(
                text: capture.text,
                source: "apple-watch",
                bodySummary: capture.bodySummary,
                metadata: [
                    "captured_at": .string(capture.capturedAt),
                    "watch_connectivity": .bool(true)
                ]
            )
            guard request.privacyClass != "restricted" else { return }
            _ = await BeagleClient.shared.assistedImportBatch(request)
        }
    }
}
#endif
