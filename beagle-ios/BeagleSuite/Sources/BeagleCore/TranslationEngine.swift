//
//  TranslationEngine.swift
//  BeagleCore
//
//  Bilingual thought processing for the exocortex.
//  Portuguese thoughts automatically get English translation
//  for international collaboration.
//
//  Language detection: NLLanguageRecognizer (always available).
//  Translation: Apple Translation framework via TranslationSession.
//  The session is obtained through SwiftUI's .translationTask modifier
//  in the UI layer, which handles model download and session lifecycle.
//
//  The researcher thinks in Portuguese. The exocortex speaks both.
//

import Foundation
import NaturalLanguage
import Observation
import Translation

// MARK: - Translation Engine

@Observable
@MainActor
public final class TranslationEngine {
    public static let shared = TranslationEngine()
    private init() {}

    /// Portuguese language codes we recognize.
    private static let portugueseCodes: Set<String> = ["pt", "pt-BR", "pt-PT"]

    /// Pending translations: thought ID -> text to translate.
    /// The UI layer drains this via `.translationTask` modifier.
    public var pendingTranslations: [(id: String, text: String)] = []

    /// Completed translations: thought ID -> English text.
    public var completedTranslations: [String: String] = [:]

    /// Whether a translation batch is currently in flight.
    public var isTranslating = false

    /// The translation configuration for Portuguese -> English.
    /// Trigger by setting this on a view's `.translationTask(configuration:)`.
    public var activeConfiguration: TranslationSession.Configuration?

    /// Detect the dominant language of the given text.
    /// Returns the BCP-47 language code (e.g. "pt", "en", "es") or nil.
    public func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Whether the detected language is any variant of Portuguese.
    public func isPortuguese(_ text: String) -> Bool {
        guard let lang = detectLanguage(text) else { return false }
        return Self.portugueseCodes.contains(lang) || lang.hasPrefix("pt")
    }

    /// Check if a language code represents Portuguese.
    public static func isPortugueseCode(_ code: String?) -> Bool {
        guard let code else { return false }
        return portugueseCodes.contains(code) || code.hasPrefix("pt")
    }

    /// Enqueue a thought for translation. Call this after language detection
    /// confirms the text is Portuguese. The SwiftUI layer picks up pending
    /// items via the `.translationTask` modifier.
    public func enqueueForTranslation(thoughtId: String, text: String) {
        guard !text.isEmpty else { return }
        // Don't re-enqueue if already translated or pending
        guard completedTranslations[thoughtId] == nil else { return }
        guard !pendingTranslations.contains(where: { $0.id == thoughtId }) else { return }
        pendingTranslations.append((id: thoughtId, text: text))
    }

    /// Record a completed translation (called by the UI layer after
    /// TranslationSession finishes).
    public func recordTranslation(thoughtId: String, translatedText: String) {
        completedTranslations[thoughtId] = translatedText
        pendingTranslations.removeAll { $0.id == thoughtId }
    }

    /// Get the English translation for a thought, if available.
    public func translation(for thoughtId: String) -> String? {
        completedTranslations[thoughtId]
    }

    /// Drain the next pending translation request. Returns nil if empty.
    public func nextPending() -> (id: String, text: String)? {
        pendingTranslations.first
    }

    /// Trigger translation for all pending items. Call this to set the
    /// configuration that a `.translationTask(configuration:)` will pick up.
    /// Each call creates a fresh configuration to ensure SwiftUI detects the change.
    public func triggerPendingTranslations() {
        guard !pendingTranslations.isEmpty else { return }
        // Reset first so SwiftUI sees a nil -> value transition
        activeConfiguration = nil
        activeConfiguration = .init(
            source: Locale.Language(identifier: "pt"),
            target: Locale.Language(identifier: "en")
        )
    }

    /// Drain pending translations and return them for processing.
    /// Called from `.translationTask` closure — the caller does `session.translate()`.
    public func drainPending() -> [(id: String, text: String)] {
        guard !pendingTranslations.isEmpty else { return [] }
        isTranslating = true
        return pendingTranslations
    }

    /// Apply translation results after the `.translationTask` closure finishes.
    public func applyResults(_ results: [(id: String, translated: String)], failedIds: [String] = []) {
        for r in results {
            recordTranslation(thoughtId: r.id, translatedText: r.translated)
        }
        for fid in failedIds {
            pendingTranslations.removeAll { $0.id == fid }
        }
        isTranslating = false
        activeConfiguration = nil
    }
}
