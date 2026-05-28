import Foundation

struct AgentKernelOpenAICompatibleAdapterV2: AgentKernelModelAdapterV2 {
    let descriptor: AgentKernelModelDescriptorV2
    let capabilities: AgentKernelModelAdapterCapabilitiesV2

    private let endpoint: URL
    private let apiKey: String?
    private let urlSession: URLSession
    private let promptBuilder: AgentKernelTextProtocolPromptBuilderV2
    private let parser: AgentKernelTextProtocolParserV2

    nonisolated init(
        descriptor: AgentKernelModelDescriptorV2,
        endpoint: URL,
        apiKey: String? = nil,
        capabilities: AgentKernelModelAdapterCapabilitiesV2,
        urlSession: URLSession = .shared,
        promptBuilder: AgentKernelTextProtocolPromptBuilderV2 = AgentKernelTextProtocolPromptBuilderV2(),
        parser: AgentKernelTextProtocolParserV2 = AgentKernelTextProtocolParserV2()
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
        for request: AgentKernelModelAdapterRequestV2
    ) async -> AgentKernelModelAdapterResponseV2 {
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
                diagnostics: AgentKernelBoundedTextV2(error.localizedDescription)
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
            throw AgentKernelOpenAICompatibleErrorV2.httpStatus(httpResponse.statusCode)
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
        for request: AgentKernelModelAdapterRequestV2,
        events: [AgentKernelModelAdapterEventV2],
        diagnostics: AgentKernelBoundedTextV2? = nil
    ) -> AgentKernelModelAdapterResponseV2 {
        AgentKernelModelAdapterResponseV2(
            requestID: request.id,
            descriptor: descriptor,
            events: events,
            diagnostics: diagnostics
        )
    }
}

enum AgentKernelOpenAICompatibleErrorV2: LocalizedError, Sendable {
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
