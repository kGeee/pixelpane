import Foundation
import os

struct CustomProviderAIBackendConfiguration: Sendable {
    let provider: CustomProvider
    let modelName: String
    /// Optional base-URL override; nil/empty uses the provider's default.
    let baseURLOverride: String?

    var baseURL: URL {
        if let override = baseURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           let url = URL(string: override) {
            return url
        }
        return provider.defaultBaseURL
    }

    var trimmedModelName: String {
        modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        !trimmedModelName.isEmpty
    }
}

/// An `AIBackend` that routes every action to a user-supplied third-party
/// provider (OpenAI or Anthropic) using the user's own API key. Because it
/// conforms to `AIBackend`, both dispatch paths reach it: quick actions call it
/// directly, and the chat/ask path reaches it through `AgentKernelAIBackendAdapter`.
///
/// v1 is non-streaming (a single completion) and text-only — the prompt is
/// already built by the caller (`AIBackendRequest.prompt`), exactly as the local
/// backends consume it.
final class CustomProviderAIBackend: AIBackend, @unchecked Sendable {
    let id = "custom-provider"
    let displayName = "Custom Provider"
    private static let log = Logger(subsystem: "pane.PixelPane", category: "CustomProviderAIBackend")

    private let configuration: CustomProviderAIBackendConfiguration
    private let keyStore: CustomProviderKeyStore
    private let urlSession: URLSession

    nonisolated init(
        configuration: CustomProviderAIBackendConfiguration,
        keyStore: CustomProviderKeyStore = CustomProviderKeyStore(),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.keyStore = keyStore
        self.urlSession = urlSession
    }

    nonisolated func capabilities() async -> AIBackendCapabilities {
        let status: AIBackendCapabilityStatus
        if !configuration.isConfigured {
            status = .unavailable(.customProviderNotConfigured)
        } else if !keyStore.hasAPIKey(for: configuration.provider) {
            status = .unavailable(.customProviderKeyMissing)
        } else {
            status = .available(.custom)
        }
        return AIBackendCapabilities(
            text: status,
            image: .unavailable(.imageInputUnsupported),
            contextWindowTokens: nil,
            maxPromptCharacters: AIModelLimits.maxPromptCharacters,
            maxOutputTokens: AIModelLimits.defaultMaxOutputTokens
        )
    }

    nonisolated func streamResponse(
        for request: AIBackendRequest
    ) -> AsyncThrowingStream<AIBackendStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    guard self.configuration.isConfigured else {
                        throw AIBackendError.unavailable(.customProviderNotConfigured)
                    }
                    guard let apiKey = self.keyStore.apiKey(for: self.configuration.provider) else {
                        throw AIBackendError.unavailable(.customProviderKeyMissing)
                    }
                    // Fingerprint only (never the full key) so a wrong value —
                    // e.g. an AutoFill-injected Keychain entry — is diagnosable.
                    Self.log.debug("Sending \(self.configuration.provider.rawValue, privacy: .public) key: length=\(apiKey.count, privacy: .public) prefix=\(apiKey.prefix(4), privacy: .public)")

                    let urlRequest = try self.makeURLRequest(for: request, apiKey: apiKey)
                    let (data, response) = try await self.urlSession.data(for: urlRequest)
                    try Task.checkCancellation()
                    try self.validate(response: response, data: data)

                    let text = try self.parseCompletion(from: data)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        throw AIBackendError.generationFailed("The provider returned no text.")
                    }

                    continuation.yield(.metadata([
                        AIModelOutputStatistic(
                            label: "Provider",
                            value: self.configuration.provider.displayName,
                            detail: self.configuration.trimmedModelName
                        )
                    ]))
                    continuation.yield(.output(AIModelOutput(
                        finalText: trimmed,
                        reasoningText: nil,
                        statistics: []
                    )))
                    continuation.yield(.completed)
                    continuation.finish()
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

    // MARK: - Request construction

    private nonisolated func makeURLRequest(
        for request: AIBackendRequest,
        apiKey: String
    ) throws -> URLRequest {
        switch configuration.provider {
        case .openAI:
            return try makeOpenAIRequest(for: request, apiKey: apiKey)
        case .anthropic:
            return try makeAnthropicRequest(for: request, apiKey: apiKey)
        }
    }

    private nonisolated func makeOpenAIRequest(
        for request: AIBackendRequest,
        apiKey: String
    ) throws -> URLRequest {
        var urlRequest = URLRequest(url: configuration.baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let payload = OpenAIChatRequest(
            model: configuration.trimmedModelName,
            messages: [OpenAIChatMessage(role: "user", content: request.prompt)],
            maxTokens: request.maxOutputTokens,
            stream: false
        )
        urlRequest.httpBody = try JSONEncoder().encode(payload)
        return urlRequest
    }

    private nonisolated func makeAnthropicRequest(
        for request: AIBackendRequest,
        apiKey: String
    ) throws -> URLRequest {
        var urlRequest = URLRequest(url: configuration.baseURL.appendingPathComponent("messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let payload = AnthropicMessagesRequest(
            model: configuration.trimmedModelName,
            maxTokens: request.maxOutputTokens,
            messages: [AnthropicMessage(role: "user", content: request.prompt)]
        )
        urlRequest.httpBody = try JSONEncoder().encode(payload)
        return urlRequest
    }

    // MARK: - Response handling

    private nonisolated func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIBackendError.generationFailed("The provider returned an invalid response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = Self.providerErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw AIBackendError.generationFailed("\(configuration.provider.displayName) request failed: \(detail)")
        }
    }

    private nonisolated func parseCompletion(from data: Data) throws -> String {
        switch configuration.provider {
        case .openAI:
            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            return decoded.choices.first?.message.content ?? ""
        case .anthropic:
            let decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
            return decoded.content
                .filter { $0.type == "text" }
                .compactMap { $0.text }
                .joined()
        }
    }

    private nonisolated static func providerErrorMessage(from data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(ProviderErrorEnvelope.self, from: data),
              let message = envelope.error?.message,
              !message.isEmpty else {
            return nil
        }
        return message
    }
}

// MARK: - OpenAI wire format

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: OpenAIChatMessage
    }
}

// MARK: - Anthropic wire format

private struct AnthropicMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [AnthropicMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicMessagesResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

// MARK: - Shared error envelope (both providers nest a `.error.message`)

private struct ProviderErrorEnvelope: Decodable {
    let error: ProviderError?

    struct ProviderError: Decodable {
        let message: String?
    }
}
