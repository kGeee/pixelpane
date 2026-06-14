import Foundation
import os

/// Stores per-provider bring-your-own API keys in the Keychain. Keys are never
/// written to UserDefaults. Reuses `KeychainStore` (defined alongside the cloud
/// auth provider) so storage semantics — data-protection keychain with a
/// file-based fallback, stale-item recovery — match the rest of the app.
struct CustomProviderKeyStore: Sendable {
    private let keychain: KeychainStore
    private static let log = Logger(subsystem: "pane.PixelPane", category: "CustomProviderKeyStore")

    // Uses the legacy file-based keychain: the data-protection keychain needs a
    // stable code-signing identity, and on ad-hoc/unsigned builds a write can
    // report success yet be unreadable. The file-based keychain persists
    // reliably across both, which matters for a bring-your-own-key field.
    init(keychain: KeychainStore = KeychainStore(service: "pane.PixelPane.custom-provider", usesDataProtection: false)) {
        self.keychain = keychain
    }

    /// The stored key for `provider`, or nil when none is saved (or the keychain
    /// is momentarily unavailable — callers treat that as "not configured").
    func apiKey(for provider: CustomProvider) -> String? {
        do {
            guard let value = try keychain.string(account: provider.keychainAccount) else {
                return nil
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            Self.log.error("Keychain read failed for \(provider.keychainAccount, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func hasAPIKey(for provider: CustomProvider) -> Bool {
        apiKey(for: provider) != nil
    }

    /// Saves (or, for an empty value, clears) the key for `provider`. Returns
    /// `true` only when the value can be read back afterward, so a swallowed
    /// Keychain failure surfaces to the caller instead of silently "succeeding".
    @discardableResult
    func setAPIKey(_ value: String, for provider: CustomProvider) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearAPIKey(for: provider)
            // Verify the delete the same way saves verify the write, so a
            // failed removal surfaces instead of silently "succeeding".
            let cleared = !hasAPIKey(for: provider)
            if !cleared {
                Self.log.error("Keychain delete left a readable key for \(provider.keychainAccount, privacy: .public)")
            }
            return cleared
        }
        do {
            try keychain.setString(trimmed, account: provider.keychainAccount)
        } catch {
            Self.log.error("Keychain write failed for \(provider.keychainAccount, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
        let storedOK = hasAPIKey(for: provider)
        if !storedOK {
            Self.log.error("Keychain write reported success but read-back was empty for \(provider.keychainAccount, privacy: .public)")
        }
        return storedOK
    }

    func clearAPIKey(for provider: CustomProvider) {
        // A real delete: storing an empty string instead is rejected by
        // SecItemUpdate on some macOS versions, leaving the old key in place.
        keychain.remove(account: provider.keychainAccount)
    }
}
