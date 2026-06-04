import Foundation
import Security

@MainActor
final class CloudAuthTokenProvider: CloudAuthTokenProviding, @unchecked Sendable {
    private let baseURL: URL
    private let clientVersion: String
    private let urlSession: URLSession
    private let keychain: KeychainStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        baseURL: URL = URL(string: "https://api.pixelpane.app/v1")!,
        clientVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
        urlSession: URLSession = .shared,
        keychain: KeychainStore = KeychainStore(service: "pane.PixelPane.cloud-auth")
    ) {
        self.baseURL = baseURL
        self.clientVersion = clientVersion
        self.urlSession = urlSession
        self.keychain = keychain
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .pixelPaneISO8601
    }

    /// Keychain persistence is a durability layer, not a prerequisite: a
    /// fetched token (and the device ID) is cached in memory for this process,
    /// so a keychain that rejects writes degrades to per-launch caching
    /// instead of failing every cloud request.
    private var memoryToken: StoredCloudAuthToken?
    private var memoryDeviceID: String?

    func cloudAuthToken() async throws -> String {
        if let storedToken = memoryToken ?? storedToken(), storedToken.expiresAt.timeIntervalSinceNow > 300 {
            memoryToken = storedToken
            return storedToken.token
        }

        let deviceID = try anonymousDeviceID()
        let request = try makeTokenRequest(deviceID: deviceID)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CloudAIBackendError.unauthorized
        }

        let tokenResponse = try decoder.decode(CloudAuthTokenResponse.self, from: data)
        let storedToken = StoredCloudAuthToken(token: tokenResponse.token, expiresAt: tokenResponse.expiresAt)
        memoryToken = storedToken
        if let encoded = try? encoder.encode(storedToken) {
            try? keychain.set(encoded, account: KeychainAccount.authToken)
        }
        return tokenResponse.token
    }

    func anonymousDeviceID() throws -> String {
        if let existing = memoryDeviceID {
            return existing
        }
        if let existing = (try? keychain.string(account: KeychainAccount.deviceID)) ?? nil {
            memoryDeviceID = existing
            return existing
        }

        let deviceID = UUID().uuidString.lowercased()
        memoryDeviceID = deviceID
        try? keychain.setString(deviceID, account: KeychainAccount.deviceID)
        return deviceID
    }

    private func storedToken() -> StoredCloudAuthToken? {
        guard let data = (try? keychain.data(account: KeychainAccount.authToken)) ?? nil else {
            return nil
        }
        return try? decoder.decode(StoredCloudAuthToken.self, from: data)
    }

    private func makeTokenRequest(deviceID: String) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientVersion, forHTTPHeaderField: "X-PixelPane-Client-Version")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-PixelPane-Request-ID")
        request.httpBody = try encoder.encode(CloudAuthTokenRequest(
            deviceID: deviceID,
            clientContext: CloudAuthClientContext(appVersion: clientVersion)
        ))
        return request
    }
}

private enum KeychainAccount {
    static let deviceID = "anonymous-device-id"
    static let authToken = "cloud-auth-token"
}

/// Prefers the data-protection keychain (items protected by the app's stable
/// identity instead of per-binary code-signature ACLs) and falls back to the
/// legacy file-based keychain when the build has no keychain access group
/// entitlement. Items a build can no longer use — e.g. legacy items whose ACL
/// is bound to an older code signature after a re-signed debug build — are
/// treated as recreatable: deleted and reported as missing rather than failing
/// the cloud request with errSecAuthFailed.
struct KeychainStore: Sendable {
    let service: String

    func string(account: String) throws -> String? {
        guard let data = try data(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setString(_ value: String, account: String) throws {
        try set(Data(value.utf8), account: account)
    }

    func data(account: String) throws -> Data? {
        do {
            return try read(account: account, useDataProtection: true)
        } catch KeychainStoreError.missingEntitlement {
            return try read(account: account, useDataProtection: false)
        }
    }

    func set(_ data: Data, account: String) throws {
        do {
            try write(data, account: account, useDataProtection: true)
        } catch KeychainStoreError.missingEntitlement {
            try write(data, account: account, useDataProtection: false)
        }
    }

    private func read(account: String, useDataProtection: Bool) throws -> Data? {
        var result: AnyObject?
        let status = SecItemCopyMatching(query(
            account: account,
            useDataProtection: useDataProtection,
            extra: [
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
        ) as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        if status == errSecMissingEntitlement {
            throw KeychainStoreError.missingEntitlement
        }
        if status == errSecInteractionNotAllowed {
            // Keychain is locked right now; the item itself is fine. Report
            // "not found" so callers fall back, without destroying the item.
            return nil
        }
        if Self.isStaleItemStatus(status) {
            removeItem(account: account)
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(status)
        }
        return result as? Data
    }

    private func write(_ data: Data, account: String, useDataProtection: Bool) throws {
        let query = query(account: account, useDataProtection: useDataProtection)
        let attributes: [String: Any] = useDataProtection
            ? [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            : [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecMissingEntitlement {
            throw KeychainStoreError.missingEntitlement
        }
        if Self.isStaleItemStatus(updateStatus) {
            removeItem(account: account)
        } else if updateStatus != errSecItemNotFound {
            throw KeychainStoreError.unhandledStatus(updateStatus)
        }

        var addQuery = query
        attributes.forEach { key, value in addQuery[key] = value }
        var addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // An item invisible to this query (other keychain implementation,
            // stale ACL) can still collide on add; clear it and retry once.
            removeItem(account: account)
            addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        }
        if addStatus == errSecMissingEntitlement {
            throw KeychainStoreError.missingEntitlement
        }
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(addStatus)
        }
    }

    private func query(
        account: String,
        useDataProtection: Bool,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if useDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        extra.forEach { key, value in query[key] = value }
        return query
    }

    /// Statuses that mean "the stored item is permanently unusable by this
    /// build" rather than a programming error — primarily auth failures from
    /// file-based keychain ACLs bound to a previous build's code signature.
    /// The stored values are recreatable, so such items are safe to drop.
    private static func isStaleItemStatus(_ status: OSStatus) -> Bool {
        status == errSecAuthFailed
    }

    private func removeItem(account: String) {
        // Best effort, in both keychain implementations, so a stale legacy
        // item cannot keep shadowing the data-protection one. The follow-up
        // read/add reports any real failure.
        SecItemDelete(query(account: account, useDataProtection: true) as CFDictionary)
        SecItemDelete(query(account: account, useDataProtection: false) as CFDictionary)
    }
}

enum KeychainStoreError: LocalizedError {
    case unhandledStatus(OSStatus)
    case missingEntitlement

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            "Keychain operation failed with status \(status)."
        case .missingEntitlement:
            "This build has no keychain access group entitlement."
        }
    }
}

private struct CloudAuthTokenRequest: Encodable {
    let schemaVersion = "2026-04-29"
    let deviceID: String
    let clientContext: CloudAuthClientContext

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case deviceID = "device_id"
        case clientContext = "client_context"
    }
}

private struct CloudAuthClientContext: Encodable {
    let appVersion: String
    let platform = "macOS"
    let locale: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
        case platform
        case locale
        case timezone
    }

    init(appVersion: String) {
        self.appVersion = appVersion
        locale = Locale.current.identifier
        timezone = TimeZone.current.identifier
    }
}

private struct CloudAuthTokenResponse: Decodable {
    let token: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }
}

private struct StoredCloudAuthToken: Codable {
    let token: String
    let expiresAt: Date
}

private extension JSONDecoder.DateDecodingStrategy {
    static var pixelPaneISO8601: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = ISO8601DateFormatter.pixelPaneWithFractionalSeconds.date(from: value)
                ?? ISO8601DateFormatter.pixelPane.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO8601 date string."
            )
        }
    }
}

private extension ISO8601DateFormatter {
    static let pixelPaneWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let pixelPane: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
