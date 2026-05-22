import AppKit
import CoreGraphics
import Foundation

struct CloudAIBackendConfiguration: Sendable {
    let baseURL: URL
    let clientVersion: String
    let isCloudModeEnabled: Bool
    let allowsImageUpload: Bool

    @MainActor
    init(
        baseURL: URL = URL(string: "https://api.pixelpane.app/v1")!,
        clientVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
        isCloudModeEnabled: Bool = false,
        allowsImageUpload: Bool = false
    ) {
        self.baseURL = baseURL
        self.clientVersion = clientVersion
        self.isCloudModeEnabled = isCloudModeEnabled
        self.allowsImageUpload = allowsImageUpload
    }
}

@MainActor
protocol CloudAuthTokenProviding: Sendable {
    func cloudAuthToken() async throws -> String
}

struct MissingCloudAuthTokenProvider: CloudAuthTokenProviding {
    func cloudAuthToken() async throws -> String {
        throw CloudAIBackendError.unauthorized
    }
}

final class CloudAIBackend: AIBackend, @unchecked Sendable {
    let id = "pixel-pane-cloud"
    let displayName = "Pixel Pane Cloud"

    private let configuration: CloudAIBackendConfiguration
    private let tokenProvider: any CloudAuthTokenProviding
    private let urlSession: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @MainActor
    convenience init() {
        self.init(
            configuration: CloudAIBackendConfiguration(),
            tokenProvider: MissingCloudAuthTokenProvider(),
            urlSession: .shared
        )
    }

    init(
        configuration: CloudAIBackendConfiguration,
        tokenProvider: any CloudAuthTokenProviding,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func capabilities() async -> AIBackendCapabilities {
        let status: AIBackendCapabilityStatus = configuration.isCloudModeEnabled
            ? .available(.pixelPaneCloud)
            : .unavailable(.cloudModeDisabled)

        return AIBackendCapabilities(
            text: status,
            image: configuration.allowsImageUpload ? status : .unavailable(.cloudImageConsentMissing),
            contextWindowTokens: nil,
            maxPromptCharacters: AIModelLimits.maxPromptCharacters,
            maxOutputTokens: AIModelLimits.defaultMaxOutputTokens
        )
    }

    func streamResponse(for request: AIBackendRequest) -> AsyncThrowingStream<AIBackendStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard configuration.isCloudModeEnabled else {
                        throw CloudAIBackendError.cloudModeDisabled
                    }

                    let urlRequest = try await makeURLRequest(for: request)
                    let (bytes, response) = try await urlSession.bytes(for: urlRequest)
                    try validate(response: response)

                    var didReceiveDisplayableText = false
                    for try await event in SSEParser().events(from: bytes) {
                        try Task.checkCancellation()
                        switch event.name {
                        case "meta":
                            let payload = try decoder.decode(CloudMetaEvent.self, from: event.data)
                            continuation.yield(.metadata(payload.statistics))
                        case "snapshot":
                            let payload = try decoder.decode(CloudSnapshotEvent.self, from: event.data)
                            if !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                didReceiveDisplayableText = true
                            }
                            continuation.yield(.snapshot(payload.text))
                        case "done":
                            guard didReceiveDisplayableText else {
                                throw CloudAIBackendError.emptyResponse
                            }
                            continuation.yield(.completed)
                            continuation.finish()
                            return
                        case "error":
                            let payload = try decoder.decode(CloudErrorEnvelope.self, from: event.data)
                            throw CloudAIBackendError.proxy(payload.error)
                        default:
                            continue
                        }
                    }

                    continuation.finish(throwing: CloudAIBackendError.streamEndedUnexpectedly)
                } catch is CancellationError {
                    continuation.finish(throwing: AIBackendError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func makeURLRequest(for request: AIBackendRequest) async throws -> URLRequest {
        let requestID = UUID().uuidString
        let token = try await tokenProvider.cloudAuthToken()
        let endpoint = request.actionKind.cloudEndpoint
        let payload = try CloudActionRequest(
            request: request,
            configuration: configuration
        )

        var urlRequest = URLRequest(url: configuration.baseURL.appendingPathComponent(endpoint))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue(configuration.clientVersion, forHTTPHeaderField: "X-PixelPane-Client-Version")
        urlRequest.setValue(requestID, forHTTPHeaderField: "X-PixelPane-Request-ID")
        urlRequest.httpBody = try encoder.encode(payload)
        return urlRequest
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIBackendError.networkUnavailable
        }

        if httpResponse.statusCode == 429 {
            throw CloudAIBackendError.rateLimited(retryAfterSeconds: retryAfter(from: httpResponse))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CloudAIBackendError.httpStatus(httpResponse.statusCode)
        }
    }

    private func retryAfter(from response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return Int(value)
    }
}

private struct CloudActionRequest: Encodable {
    let schemaVersion = "2026-04-29"
    let action: String
    let capture: CloudCapture
    let targetLanguage: String?
    let question: String?
    let conversation: [CloudConversationTurn]?
    let image: CloudImage?
    let clientContext: CloudClientContext
    let limits: CloudLimits

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case action
        case capture
        case targetLanguage = "target_language"
        case question
        case conversation
        case image
        case clientContext = "client_context"
        case limits
    }

    init(
        request: AIBackendRequest,
        configuration: CloudAIBackendConfiguration
    ) throws {
        let ocrText = (request.cloudOCRText ?? request.prompt)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if ocrText.isEmpty, request.actionKind != .chat {
            throw CloudAIBackendError.emptyOCRText
        }

        action = request.actionKind.rawValue
        capture = CloudCapture(
            ocrText: ocrText,
            detectedLanguage: request.cloudDetectedLanguage
        )
        targetLanguage = request.cloudTargetLanguage
        question = request.cloudQuestion
        conversation = request.cloudConversation.isEmpty
            ? nil
            : request.cloudConversation.map(CloudConversationTurn.init)
        if let image = request.capturedImage {
            guard configuration.allowsImageUpload else {
                throw CloudAIBackendError.imageConsentMissing
            }
            self.image = try CloudImage(cgImage: image)
        } else {
            self.image = nil
        }
        clientContext = CloudClientContext(
            appVersion: configuration.clientVersion,
            cloudMode: configuration.isCloudModeEnabled
        )
        limits = CloudLimits(maxOutputTokens: request.maxOutputTokens)
    }
}

private struct CloudCapture: Encodable {
    let sourceType = "ocr"
    let ocrText: String
    let detectedLanguage: String?

    enum CodingKeys: String, CodingKey {
        case sourceType = "source_type"
        case ocrText = "ocr_text"
        case detectedLanguage = "detected_language"
    }
}

private struct CloudConversationTurn: Encodable {
    let role: String
    let content: String

    nonisolated init(_ turn: AIBackendConversationTurn) {
        role = turn.role.rawValue
        content = turn.content
    }
}

private struct CloudImage: Encodable {
    let mimeType = "image/png"
    let dataBase64: String
    let userConsented = true

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case dataBase64 = "data_base64"
        case userConsented = "user_consented"
    }

    init(cgImage: CGImage) throws {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CloudAIBackendError.imageEncodingFailed
        }
        dataBase64 = data.base64EncodedString()
    }
}

private struct CloudClientContext: Encodable {
    let appVersion: String
    let platform = "macOS"
    let locale: String
    let timezone: String
    let cloudMode: Bool

    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
        case platform
        case locale
        case timezone
        case cloudMode = "cloud_mode"
    }

    init(appVersion: String, cloudMode: Bool) {
        self.appVersion = appVersion
        self.cloudMode = cloudMode
        locale = Locale.current.identifier
        timezone = TimeZone.current.identifier
    }
}

private struct CloudLimits: Encodable {
    let maxOutputTokens: Int

    enum CodingKeys: String, CodingKey {
        case maxOutputTokens = "max_output_tokens"
    }
}

private struct CloudSnapshotEvent: Decodable {
    let text: String
}

private struct CloudMetaEvent: Decodable {
    let model: String?
    let remainingCloudActions: Int?
    let resetAt: String?

    enum CodingKeys: String, CodingKey {
        case model
        case remainingCloudActions = "remaining_cloud_actions"
        case resetAt = "reset_at"
    }

    var statistics: [AIModelOutputStatistic] {
        var values: [AIModelOutputStatistic] = []
        if let model {
            values.append(AIModelOutputStatistic(label: "Cloud model", value: model, detail: nil))
        }
        if let remainingCloudActions {
            values.append(AIModelOutputStatistic(
                label: "Actions left",
                value: "\(remainingCloudActions)",
                detail: Self.formattedResetText(from: resetAt)
            ))
        }
        return values
    }

    private static func formattedResetText(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: rawValue) ?? ISO8601DateFormatter().date(from: rawValue)
        guard let date else { return nil }

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        if Calendar.current.isDateInTomorrow(date) {
            return "resets tomorrow"
        }
        if Calendar.current.isDateInToday(date) {
            return "resets \(timeFormatter.string(from: date))"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        return "resets \(dateFormatter.string(from: date))"
    }
}

private struct CloudErrorEnvelope: Decodable {
    let error: CloudProxyError
}

struct CloudProxyError: Decodable, Sendable {
    let code: String
    let message: String
    let retryAfterSeconds: Int?
    let requestID: String?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case retryAfterSeconds = "retry_after_seconds"
        case requestID = "request_id"
    }
}

enum CloudAIBackendError: LocalizedError, Sendable {
    case cloudModeDisabled
    case imageConsentMissing
    case imageEncodingFailed
    case emptyOCRText
    case unauthorized
    case rateLimited(retryAfterSeconds: Int?)
    case networkUnavailable
    case httpStatus(Int)
    case proxy(CloudProxyError)
    case emptyResponse
    case streamEndedUnexpectedly

    var errorDescription: String? {
        switch self {
        case .cloudModeDisabled:
            "Cloud Mode is off."
        case .imageConsentMissing:
            "Sending images to cloud requires explicit consent."
        case .imageEncodingFailed:
            "Could not prepare the captured image for cloud processing."
        case .emptyOCRText:
            "No OCR text was available for the cloud action."
        case .unauthorized:
            "Cloud authentication is unavailable."
        case .rateLimited(let retryAfterSeconds):
            if let retryAfterSeconds {
                "Cloud action limit reached. Try again in \(retryAfterSeconds) seconds."
            } else {
                "Cloud action limit reached."
            }
        case .networkUnavailable:
            "Cloud is unreachable."
        case .httpStatus(let status):
            "Cloud request failed with HTTP \(status)."
        case .proxy(let error):
            error.message
        case .emptyResponse:
            "Cloud completed the request but returned no text."
        case .streamEndedUnexpectedly:
            "Cloud stream ended before completion."
        }
    }
}

private struct ServerSentEvent {
    let name: String
    let data: Data
}

private struct SSEParser {
    func events(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<ServerSentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var buffer = Data()

                    for try await byte in bytes {
                        try Task.checkCancellation()
                        buffer.append(byte)

                        if buffer.ends(with: Self.crlfDelimiter) {
                            let eventData = buffer.dropLast(Self.crlfDelimiter.count)
                            yieldEvent(data: Data(eventData), continuation: continuation)
                            buffer.removeAll(keepingCapacity: true)
                        } else if buffer.ends(with: Self.lfDelimiter) {
                            let eventData = buffer.dropLast(Self.lfDelimiter.count)
                            yieldEvent(data: Data(eventData), continuation: continuation)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }

                    if !buffer.isEmpty {
                        yieldEvent(data: buffer, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static let lfDelimiter = Data([0x0A, 0x0A])
    private static let crlfDelimiter = Data([0x0D, 0x0A, 0x0D, 0x0A])

    private func yieldEvent(
        data eventData: Data,
        continuation: AsyncThrowingStream<ServerSentEvent, Error>.Continuation
    ) {
        guard let rawEvent = String(data: eventData, encoding: .utf8) else { return }
        var name = "message"
        var dataLines: [String] = []

        for line in rawEvent.components(separatedBy: .newlines) {
            if line.hasPrefix("event:") {
                name = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        guard !dataLines.isEmpty else { return }
        let data = dataLines.joined(separator: "\n").data(using: .utf8) ?? Data()
        continuation.yield(ServerSentEvent(name: name, data: data))
    }
}

private extension Data {
    func ends(with suffix: Data) -> Bool {
        guard count >= suffix.count else { return false }
        return self[index(endIndex, offsetBy: -suffix.count)..<endIndex].elementsEqual(suffix)
    }
}

private extension AIActionKind {
    var cloudEndpoint: String {
        switch self {
        case .translate:
            "translate"
        case .explain:
            "explain"
        case .simplify:
            "simplify"
        case .ask:
            "ask"
        case .chat:
            "chat"
        case .debug:
            "debug"
        }
    }
}
