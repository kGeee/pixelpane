import Foundation

struct AgentKernelOpenAICompatibleAdapter: AgentKernelModelAdapter {
    let descriptor: AgentKernelModelDescriptor
    let capabilities: AgentKernelModelAdapterCapabilities

    private let endpoint: URL
    private let apiKey: String?
    private let urlSession: URLSession
    private let promptBuilder: AgentKernelTextProtocolPromptBuilder
    private let parser: AgentKernelTextProtocolParser

    nonisolated init(
        descriptor: AgentKernelModelDescriptor,
        endpoint: URL,
        apiKey: String? = nil,
        capabilities: AgentKernelModelAdapterCapabilities,
        urlSession: URLSession = .shared,
        promptBuilder: AgentKernelTextProtocolPromptBuilder = AgentKernelTextProtocolPromptBuilder(),
        parser: AgentKernelTextProtocolParser = AgentKernelTextProtocolParser()
    ) {
        self.descriptor = descriptor
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.capabilities = capabilities
        self.urlSession = urlSession
        self.promptBuilder = promptBuilder
        self.parser = parser
    }

    nonisolated func response(
        for request: AgentKernelModelAdapterRequest
    ) async -> AgentKernelModelAdapterResponse {
        let shouldUseProtocol = !request.tools.isEmpty || request.responseFormat == .textProtocol
        let prompt = shouldUseProtocol
            ? promptBuilder.prompt(for: request)
            : request.messages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
        do {
            let text = try await complete(prompt: prompt, maxOutputTokens: request.requestedMaxOutputTokens)
            if shouldUseProtocol {
                switch parser.parse(text, tools: request.tools) {
                case .success(let event):
                    return response(for: request, events: [event])
                case .failure(let reason):
                    return response(for: request, events: [.malformedOutput(text)], diagnostics: reason.summary)
                }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return response(for: request, events: trimmed.isEmpty ? [.emptyOutput] : [.finalAnswer(trimmed)])
        } catch {
            return response(
                for: request,
                events: [.malformedOutput(error.localizedDescription)],
                diagnostics: AgentKernelBoundedText(error.localizedDescription)
            )
        }
    }

    nonisolated func requestForTesting(
        prompt: String,
        maxOutputTokens: Int
    ) throws -> URLRequest {
        try makeRequest(prompt: prompt, maxOutputTokens: maxOutputTokens)
    }

    private nonisolated func complete(
        prompt: String,
        maxOutputTokens: Int
    ) async throws -> String {
        let request = try makeRequest(prompt: prompt, maxOutputTokens: maxOutputTokens)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AgentKernelOpenAICompatibleError.httpStatus(httpResponse.statusCode)
        }
        let decoded = try JSONDecoder().decode(OpenAICompatibleChatResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    private nonisolated func makeRequest(
        prompt: String,
        maxOutputTokens: Int
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let payload = OpenAICompatibleChatRequest(
            model: descriptor.modelName ?? "local",
            messages: [
                OpenAICompatibleChatMessage(role: "user", content: prompt)
            ],
            maxTokens: maxOutputTokens,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private nonisolated func response(
        for request: AgentKernelModelAdapterRequest,
        events: [AgentKernelModelAdapterEvent],
        diagnostics: AgentKernelBoundedText? = nil
    ) -> AgentKernelModelAdapterResponse {
        AgentKernelModelAdapterResponse(
            requestID: request.id,
            descriptor: descriptor,
            events: events,
            diagnostics: diagnostics
        )
    }
}

enum AgentKernelOpenAICompatibleError: LocalizedError, Sendable {
    case httpStatus(Int)

    nonisolated var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            "OpenAI-compatible endpoint returned HTTP \(status)."
        }
    }
}

nonisolated private struct OpenAICompatibleChatRequest: Encodable {
    let model: String
    let messages: [OpenAICompatibleChatMessage]
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case stream
    }
}

nonisolated private struct OpenAICompatibleChatMessage: Codable {
    let role: String
    let content: String
}

nonisolated private struct OpenAICompatibleChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: OpenAICompatibleChatMessage
    }
}
