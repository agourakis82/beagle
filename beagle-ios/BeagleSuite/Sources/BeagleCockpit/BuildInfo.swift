//
//  BuildInfo.swift
//  BeagleCockpit
//
//  Shared build/version helpers for making preview builds legible on device.
//

import Foundation

enum BuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    static var previewLabel: String {
        "Preview \(build)"
    }

    static var detailedLabel: String {
        "v\(version) (\(build))"
    }
}
