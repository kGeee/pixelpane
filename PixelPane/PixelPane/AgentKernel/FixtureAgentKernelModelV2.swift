import Foundation

actor FixtureAgentKernelModelV2: AgentKernelModelClientV2 {
    enum ScriptedResponse: Sendable {
        case finalAnswer(String)
        case toolCall(name: String, arguments: [String: String], reason: String?)
        case malformedOutput(String)
        case emptyOutput
        case timeout
        case events([AgentKernelModelEventV2])
    }

    let id: String
    let capabilities: AgentKernelModelCapabilitiesV2

    private var responses: [ScriptedResponse]
    private(set) var receivedRequests: [AgentKernelModelRequestV2] = []

    init(
        id: String,
        capabilities: AgentKernelModelCapabilitiesV2 = AgentKernelModelCapabilitiesV2(
            supportsNativeToolCalling: false,
            supportsStreaming: false,
            contextWindowTokens: 8_192
        ),
        responses: [ScriptedResponse]
    ) {
        self.id = id
        self.capabilities = capabilities
        self.responses = responses
    }

    func events(for request: AgentKernelModelRequestV2) async -> [AgentKernelModelEventV2] {
        receivedRequests.append(request)
        guard !responses.isEmpty else {
            return [.emptyOutput]
        }
        let response = responses.removeFirst()
        switch response {
        case .finalAnswer(let text):
            return [.finalAnswer(text)]
        case .toolCall(let name, let arguments, let reason):
            return [
                .toolCall(
                    AgentKernelToolCallV2(
                        name: name,
                        arguments: arguments,
                        reason: reason
                    )
                )
            ]
        case .malformedOutput(let text):
            return [.malformedOutput(text)]
        case .emptyOutput:
            return [.emptyOutput]
        case .timeout:
            return [.timedOut]
        case .events(let events):
            return events
        }
    }

    func lastRequest() -> AgentKernelModelRequestV2? {
        receivedRequests.last
    }
}
