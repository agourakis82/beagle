//
//  DirectBrainCredentials.swift
//  BeagleCore
//
//  Keychain-backed Direct Brain API credentials and OpenAI / MoE preferences.
//

import Foundation
import Security
import Synchronization

// MARK: - Direct Brain Credentials Keychain

enum DirectCredentialKeychain {
    private static let service = "dev.sounio.beagle.direct-credentials"
    private static let lock = Mutex<Void>(())

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func load(account: String) -> String? {
        lock.withLock { _ in
            var request = query(account: account)
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(request as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data,
               let value = String(data: data, encoding: .utf8), !value.isEmpty {
                UserDefaults.standard.removeObject(forKey: account)
                return value
            }
            // A locked/unavailable Keychain must not be mistaken for an absent item.
            guard status == errSecItemNotFound else { return nil }
            guard let legacy = UserDefaults.standard.string(forKey: account)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty else { return nil }
            // Preserve the old value until migration succeeds; never use plaintext on failure.
            guard write(legacy, account: account) else { return nil }
            UserDefaults.standard.removeObject(forKey: account)
            return legacy
        }
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        lock.withLock { _ in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let success: Bool
            if trimmed.isEmpty {
                let status = SecItemDelete(query(account: account) as CFDictionary)
                success = status == errSecSuccess || status == errSecItemNotFound
            } else {
                success = write(trimmed, account: account)
            }
            if success {
                UserDefaults.standard.removeObject(forKey: account)
            } else {
                print("[DirectBrainCredentials] Keychain update failed; credential unchanged.")
            }
            return success
        }
    }

    private static func write(_ value: String, account: String) -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let request = query(account: account)
        let status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            return SecItemAdd(request.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
}

// MARK: - Direct Brain Credentials & Settings

public enum DirectBrainCredentials {
    private static let openAIKeyDefault = "beagle.direct.openai.apiKey"
    private static let anthropicKeyDefault = "beagle.direct.anthropic.apiKey"
    private static let openAIModelDefault = "beagle.direct.openai.model"
    private static let openAIMigrated62Key = "beagle.direct.openai.migrated62"
    private static let openAIReasoningEffortKey = "beagle.direct.openai.reasoningEffort"
    private static let openAINativeWebSearchKey = "beagle.direct.openai.nativeWebSearch"
    private static let openAIToolSearchKey = "beagle.direct.openai.toolSearch"
    private static let keepLocalLoadedDefault = "beagle.moe.keepLocalLoaded"

    /// Ephemeral override used exclusively by unit tests so Keychain entitlements are never required in CI/simulator.
    private static let testOpenAIKeyStorage = Mutex<String?>(nil)
    static var testOpenAIKeyOverride: String? {
        get { testOpenAIKeyStorage.withLock { $0 } }
        set { testOpenAIKeyStorage.withLock { $0 = newValue } }
    }

    public static var openAIKey: String {
        get {
            if let override = testOpenAIKeyOverride, !override.isEmpty {
                return override
            }
            if let saved = DirectCredentialKeychain.load(account: openAIKeyDefault) {
                return saved
            }
            if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty {
                return env
            }
            return secretValue(forKey: "OPENAI_API_KEY") ?? ""
        }
        set {
            DirectCredentialKeychain.save(newValue, account: openAIKeyDefault)
        }
    }

    public static var anthropicKey: String {
        get {
            if let saved = DirectCredentialKeychain.load(account: anthropicKeyDefault) {
                return saved
            }
            if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
                return env
            }
            return secretValue(forKey: "ANTHROPIC_API_KEY") ?? ""
        }
        set {
            DirectCredentialKeychain.save(newValue, account: anthropicKeyDefault)
        }
    }

    /// Preferred OpenAI model (Nov 2026 flagship default: `gpt-6.2-astra`).
    /// Provider errors never silently select another OpenAI model during requests.
    public static var openAIModel: String {
        get {
            migrateLegacyOpenAIModelIfNeeded()
            let saved = UserDefaults.standard.string(forKey: openAIModelDefault)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? OpenAIModelCatalog.defaultFlagshipModel : saved
        }
        set {
            UserDefaults.standard.set(true, forKey: openAIMigrated62Key)
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: openAIModelDefault)
        }
    }

    private static func migrateLegacyOpenAIModelIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: openAIMigrated62Key) else { return }
        UserDefaults.standard.set(true, forKey: openAIMigrated62Key)
        let current = UserDefaults.standard.string(forKey: openAIModelDefault)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if current.isEmpty || current == "gpt-5.5" || OpenAIModelCatalog.obsoleteOrRetiredIDs.contains(current.lowercased()) {
            UserDefaults.standard.set(OpenAIModelCatalog.defaultFlagshipModel, forKey: openAIModelDefault)
        }
    }

    public static var openAIReasoningEffort: OpenAIReasoningEffort {
        get {
            let raw = UserDefaults.standard.string(forKey: openAIReasoningEffortKey) ?? ""
            return OpenAIReasoningEffort(rawValue: raw) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: openAIReasoningEffortKey)
        }
    }

    public static var enableNativeWebSearch: Bool {
        get {
            if UserDefaults.standard.object(forKey: openAINativeWebSearchKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: openAINativeWebSearchKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: openAINativeWebSearchKey)
        }
    }

    public static var enableToolSearch: Bool {
        get {
            if UserDefaults.standard.object(forKey: openAIToolSearchKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: openAIToolSearchKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: openAIToolSearchKey)
        }
    }

    /// Whether to keep the local uncensored MLX model loaded in RAM even when online (for MoE & instant uncensored listening).
    public static var keepLocalLoadedWhenOnline: Bool {
        get {
            if UserDefaults.standard.object(forKey: keepLocalLoadedDefault) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: keepLocalLoadedDefault)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keepLocalLoadedDefault)
        }
    }

    public static var hasOpenAI: Bool { !openAIKey.isEmpty }
    public static var hasAnthropic: Bool { !anthropicKey.isEmpty }

    private static func secretValue(forKey key: String) -> String? {
        for bundle in Bundle.allBundles {
            if let path = bundle.path(forResource: "Secrets", ofType: "plist"),
               let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
               let val = dict[key] as? String,
               !val.isEmpty {
                return val
            }
        }
        return nil
    }
}
