import Foundation

actor FixtureAgentKernelAdapterV2: AgentKernelModelAdapterV2 {
    enum ScriptedResponse: Sendable {
        case finalAnswer(String)
        case toolCall(name: String, arguments: [String: String], reason: String?)
        case malformedOutput(String)
        case emptyOutput
        case timeout
        case delayedFinalAnswer(String, nanoseconds: UInt64)
        case events([AgentKernelModelAdapterEventV2])
    }

    let descriptor: AgentKernelModelDescriptorV2
    let capabilities: AgentKernelModelAdapterCapabilitiesV2

    private var responses: [ScriptedResponse]
    private(set) var receivedRequests: [AgentKernelModelAdapterRequestV2] = []

    init(
        descriptor: AgentKernelModelDescriptorV2 = AgentKernelModelDescriptorV2(
            id: "fixture.adapter",
            providerKind: .fixture,
            route: .local,
            displayName: "Fixture Adapter"
        ),
        capabilities: AgentKernelModelAdapterCapabilitiesV2? = nil,
        responses: [ScriptedResponse]
    ) {
        self.descriptor = descriptor
        self.capabilities = capabilities ?? AgentKernelModelAdapterCapabilitiesV2(
            descriptor: descriptor,
            toolCallingMode: .native,
            structuredOutputReliability: .strict,
            streamingMode: .events,
            limits: AgentKernelModelLimitsV2(contextWindowTokens: 8_192)
        )
        self.responses = responses
    }

    func response(
        for request: AgentKernelModelAdapterRequestV2
    ) async -> AgentKernelModelAdapterResponseV2 {
        receivedRequests.append(request)
        guard !responses.isEmpty else {
            return AgentKernelModelAdapterResponseV2(
                requestID: request.id,
                descriptor: descriptor,
                events: [.emptyOutput]
            )
        }
        let scripted = responses.removeFirst()
        if case .delayedFinalAnswer(_, let nanoseconds) = scripted {
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
        return AgentKernelModelAdapterResponseV2(
            requestID: request.id,
            descriptor: descriptor,
            events: events(for: scripted)
        )
    }

    func lastRequest() -> AgentKernelModelAdapterRequestV2? {
        receivedRequests.last
    }

    private nonisolated func events(
        for scripted: ScriptedResponse
    ) -> [AgentKernelModelAdapterEventV2] {
        switch scripted {
        case .finalAnswer(let text):
            [.finalAnswer(text)]
        case .toolCall(let name, let arguments, let reason):
            [
                .toolCall(
                    AgentKernelToolCallV2(
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
