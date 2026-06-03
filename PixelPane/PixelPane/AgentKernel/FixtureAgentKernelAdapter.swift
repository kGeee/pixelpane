import Foundation

actor FixtureAgentKernelAdapter: AgentKernelModelAdapter {
    enum ScriptedResponse: Sendable {
        case finalAnswer(String)
        case toolCall(name: String, arguments: [String: String], reason: String?)
        case malformedOutput(String)
        case emptyOutput
        case timeout
        case delayedFinalAnswer(String, nanoseconds: UInt64)
        case events([AgentKernelModelAdapterEvent])
    }

    let descriptor: AgentKernelModelDescriptor
    let capabilities: AgentKernelModelAdapterCapabilities

    private var responses: [ScriptedResponse]
    private(set) var receivedRequests: [AgentKernelModelAdapterRequest] = []

    init(
        descriptor: AgentKernelModelDescriptor = AgentKernelModelDescriptor(
            id: "fixture.adapter",
            providerKind: .fixture,
            route: .local,
            displayName: "Fixture Adapter"
        ),
        capabilities: AgentKernelModelAdapterCapabilities? = nil,
        responses: [ScriptedResponse]
    ) {
        self.descriptor = descriptor
        self.capabilities = capabilities ?? AgentKernelModelAdapterCapabilities(
            descriptor: descriptor,
            toolCallingMode: .native,
            structuredOutputReliability: .strict,
            streamingMode: .events,
            limits: AgentKernelModelLimits(contextWindowTokens: 8_192)
        )
        self.responses = responses
    }

    func response(
        for request: AgentKernelModelAdapterRequest
    ) async -> AgentKernelModelAdapterResponse {
        receivedRequests.append(request)
        guard !responses.isEmpty else {
            return AgentKernelModelAdapterResponse(
                requestID: request.id,
                descriptor: descriptor,
                events: [.emptyOutput]
            )
        }
        let scripted = responses.removeFirst()
        if case .delayedFinalAnswer(_, let nanoseconds) = scripted {
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
        return AgentKernelModelAdapterResponse(
            requestID: request.id,
            descriptor: descriptor,
            events: events(for: scripted)
        )
    }

    func lastRequest() -> AgentKernelModelAdapterRequest? {
        receivedRequests.last
    }

    func requests() -> [AgentKernelModelAdapterRequest] {
        receivedRequests
    }

    private nonisolated func events(
        for scripted: ScriptedResponse
    ) -> [AgentKernelModelAdapterEvent] {
        switch scripted {
        case .finalAnswer(let text):
            [.finalAnswer(text)]
        case .toolCall(let name, let arguments, let reason):
            [
                .toolCall(
                    AgentKernelToolCall(
                        name: name,
                        arguments: arguments,
                        reason: reason
                    )
                )
            ]
        case .malformedOutput(let text):
            [.malformedOutput(text)]
        case .emptyOutput:
            [.emptyOutput]
        case .timeout:
            [.timedOut]
        case .delayedFinalAnswer(let text, _):
            [.finalAnswer(text)]
        case .events(let events):
            events
        }
    }
}
