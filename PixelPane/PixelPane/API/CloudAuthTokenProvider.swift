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

    func cloudAuthToken() async throws -> String {
        if let storedToken = try storedToken(), storedToken.expiresAt.timeIntervalSinceNow > 300 {
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
        try keychain.set(
            encoder.encode(StoredCloudAuthToken(token: tokenResponse.token, expiresAt: tokenResponse.expiresAt)),
            account: KeychainAccount.authToken
        )
        return tokenResponse.token
    }

    func anonymousDeviceID() throws -> String {
        if let existing = try keychain.string(account: KeychainAccount.deviceID) {
            return existing
        }

        let deviceID = UUID().uuidString.lowercased()
        try keychain.setString(deviceID, account: KeychainAccount.deviceID)
        return deviceID
    }

    private func storedToken() throws -> StoredCloudAuthToken? {
        guard let data = try keychain.data(account: KeychainAccount.authToken) else {
            return nil
        }
        return try decoder.decode(StoredCloudAuthToken.self, from: data)
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(status)
        }
        return result as? Data
    }

    func set(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.unhandledStatus(updateStatus)
        }

        var addQuery = query
        attributes.forEach { key, value in addQuery[key] = value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(addStatus)
        }
    }
}

enum KeychainStoreError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            "Keychain operation failed with status \(status)."
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
