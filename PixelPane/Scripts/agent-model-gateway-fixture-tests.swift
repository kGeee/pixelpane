import Foundation

enum AgentModelGatewayFixtureHarness {
    struct HarnessError: Error, CustomStringConvertible {
        let description: String
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw HarnessError(description: message)
        }
    }

    static func run() async throws {
        try await testTierClassification()
        try await testFullAgentRequiresTierA()
        try await testPlainChatStripsTools()
        try await testProviderFailureMapping()
        try await testContextOverflow()
        try await testGatewayTimeoutAndCancellation()
        try await testToolCallValidation()
        try await testWrappedProtocolPayloadsNormalize()
        try await testAIBackendBridgeUsesRawProtocolText()
        try await testCloudChatAdapterIsPlainChatOnly()
        try await testCloudChatAdapterSupportsToolProtocolWhenEnabled()
        try await testTierCCloudRouteRejectsToolsBeforeAdapterCall()
    }

    private static func testTierClassification() async throws {
        let tierA = fixtureAdapter(id: "fixture.tierA", responses: [.finalAnswer("ok")])
        let tierB = fixtureAdapter(id: "fixture.tierB", toolCallingMode: .textProtocol, structured: .bestEffort, responses: [.finalAnswer("ok")])
        let tierC = fixtureAdapter(id: "fixture.tierC", toolCallingMode: .none, structured: .unsupported, responses: [.finalAnswer("ok")])
        let gateway = AgentModelGateway(adapters: [tierA, tierB, tierC])

        let tierAValue = await gateway.tier(adapterID: tierA.descriptor.id)
        let tierBValue = await gateway.tier(adapterID: tierB.descriptor.id)
        let tierCValue = await gateway.tier(adapterID: tierC.descriptor.id)
        try expect(tierAValue == .tierAFullAgent, "native/strict adapter should be Tier A")
        try expect(tierBValue == .tierBConstrainedStructuredText, "text protocol adapter should be Tier B")
        try expect(tierCValue == .tierCPlainChat, "plain text adapter should be Tier C")
    }

    private static func testFullAgentRequiresTierA() async throws {
        let tierB = fixtureAdapter(
            id: "fixture.fullAgentDenied",
            toolCallingMode: .textProtocol,
            structured: .bestEffort,
            responses: [.toolCall(name: "read_file", arguments: ["path": "README.md"], reason: nil)]
        )
        let gateway = AgentModelGateway(adapters: [tierB])
        let result = await gateway.response(
            adapterID: tierB.descriptor.id,
            request: request(mode: .fullAgent, tools: [readFileTool()])
        )

        try expect(result.failure?.kind == .unsupportedToolMode, "Tier B should not run full-agent mode")
    }

    private static func testPlainChatStripsTools() async throws {
        let adapter = fixtureAdapter(
            id: "fixture.plain",
            toolCallingMode: .none,
            structured: .unsupported,
            responses: [.finalAnswer("plain answer")]
        )
        let gateway = AgentModelGateway(adapters: [adapter])
        let result = await gateway.response(
            adapterID: adapter.descriptor.id,
            request: request(mode: .plainChat, tools: [readFileTool()])
        )
        let lastRequest = await adapter.lastRequest()

        try expect(result.response?.events == [.finalAnswer("plain answer")], "plain chat should still synthesize")
        try expect(lastRequest?.tools.isEmpty == true, "plain chat should not expose tools")
        try expect(lastRequest?.responseFormat == AgentKernelToolCallingModeV2.none, "plain chat should request no structured tool format")
    }

    private static func testProviderFailureMapping() async throws {
        let unavailable = fixtureAdapter(id: "fixture.unavailable", isAvailable: false, responses: [.finalAnswer("unused")])
        let malformed = fixtureAdapter(id: "fixture.malformed", responses: [.malformedOutput("{")])
        let empty = fixtureAdapter(id: "fixture.empty", responses: [.emptyOutput])
        let gateway = AgentModelGateway(adapters: [unavailable, malformed, empty])

        let unavailableResult = await gateway.response(adapterID: unavailable.descriptor.id, request: request(mode: .fullAgent))
        let malformedResult = await gateway.response(adapterID: malformed.descriptor.id, request: request(mode: .fullAgent))
        let emptyResult = await gateway.response(adapterID: empty.descriptor.id, request: request(mode: .plainChat))

        try expect(unavailableResult.failure?.kind == .unavailable, "unavailable adapter should map to unavailable")
        try expect(malformedResult.failure?.kind == .structuredOutputInvalid, "malformed structured output should map to structuredOutputInvalid")
        try expect(emptyResult.failure?.kind == .emptyOutput, "empty output should map to emptyOutput")
    }

    private static func testContextOverflow() async throws {
        let adapter = fixtureAdapter(
            id: "fixture.small",
            limits: AgentKernelModelLimitsV2(maxPromptCharacters: 4),
            responses: [.finalAnswer("unused")]
        )
        let gateway = AgentModelGateway(adapters: [adapter])
        let result = await gateway.response(
            adapterID: adapter.descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .plainChat,
                messages: [AgentKernelMessageV2(role: .user, content: "too long")]
            )
        )

        try expect(result.failure?.kind == .contextTooLarge, "large prompt should fail before provider call")
    }

    private static func testGatewayTimeoutAndCancellation() async throws {
        let timeoutAdapter = fixtureAdapter(id: "fixture.timeout", responses: [.delayedFinalAnswer("late", nanoseconds: 500_000_000)])
        let cancelAdapter = fixtureAdapter(id: "fixture.cancel", responses: [.delayedFinalAnswer("late", nanoseconds: 500_000_000)])
        let gateway = AgentModelGateway(adapters: [timeoutAdapter, cancelAdapter])

        let timeoutResult = await gateway.response(
            adapterID: timeoutAdapter.descriptor.id,
            request: request(mode: .plainChat, timeout: 0.02)
        )
        try expect(timeoutResult.failure?.kind == .timeout, "deadline should map to timeout")

        let task = Task {
            await gateway.response(
                adapterID: cancelAdapter.descriptor.id,
                request: request(mode: .plainChat, timeout: 2)
            )
        }
        task.cancel()
        let cancelResult = await task.value
        try expect(cancelResult.failure?.kind == .canceled, "task cancellation should map to canceled")
    }

    private static func testToolCallValidation() async throws {
        let unknownTool = fixtureAdapter(id: "fixture.unknownTool", responses: [.toolCall(name: "delete_everything", arguments: [:], reason: nil)])
        let missingArgument = fixtureAdapter(id: "fixture.missingArgument", responses: [.toolCall(name: "read_file", arguments: [:], reason: nil)])
        let gateway = AgentModelGateway(adapters: [unknownTool, missingArgument])
        let unknownResult = await gateway.response(
            adapterID: unknownTool.descriptor.id,
            request: request(mode: .fullAgent, tools: [readFileTool()])
        )
        let missingResult = await gateway.response(
            adapterID: missingArgument.descriptor.id,
            request: request(mode: .fullAgent, tools: [readFileTool()])
        )

        try expect(unknownResult.failure?.kind == .toolCallInvalid, "unknown tool call should fail")
        try expect(missingResult.failure?.kind == .toolCallInvalid, "missing required argument should fail")
    }

    private static func testAIBackendBridgeUsesRawProtocolText() async throws {
        let rawProtocol = ##"{"type":"tool_call","name":"stage_write_proposal","arguments":{"operation":"create","targetPath":"story.sh","content":"#!/bin/bash\necho hi"}}"##
        let displayText = ModelOutputFormatter().format(rawProtocol).finalText
        try expect(displayText.contains(" necho"), "display formatter fixture should reproduce newline escape corruption")

        let backend = FixtureRawProtocolBackend(rawText: rawProtocol, displayText: displayText)
        let descriptor = AgentKernelModelDescriptorV2(
            id: "fixture.ai-backend-raw",
            providerKind: .fixture,
            route: .local,
            displayName: "Fixture Raw Backend"
        )
        let adapter = AgentKernelAIBackendAdapterV2(
            descriptor: descriptor,
            backend: backend,
            capabilities: AgentKernelModelAdapterCapabilitiesV2(
                descriptor: descriptor,
                toolCallingMode: .textProtocol,
                structuredOutputReliability: .bestEffort,
                streamingMode: .snapshots
            )
        )
        let gateway = AgentModelGateway(adapters: [adapter])
        let result = await gateway.response(
            adapterID: descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .constrainedStructuredText,
                messages: [AgentKernelMessageV2(role: .user, content: "write script")],
                tools: [stageWriteTool()]
            )
        )

        guard case .toolCall(let call)? = result.response?.events.first else {
            throw HarnessError(description: "raw AI backend protocol text should parse into a tool call")
        }
        try expect(call.arguments["content"] == "#!/bin/bash\necho hi", "tool content should preserve real newline from raw protocol text")
        try expect(call.arguments["content"]?.contains(" necho") == false, "tool content should not use display-normalized newline artifacts")
    }

    private static func testCloudChatAdapterIsPlainChatOnly() async throws {
        let backend = FixtureCloudChatBackend(responseText: "cloud answer")
        let descriptor = AgentKernelModelDescriptorV2(
            id: "fixture.cloud-chat",
            providerKind: .pixelPaneCloud,
            route: .cloud,
            displayName: "Fixture Cloud"
        )
        let adapter = AgentKernelCloudChatAdapterV2(
            descriptor: descriptor,
            backend: backend,
            backendCapabilities: await backend.capabilities()
        )
        try expect(AgentModelGateway.tier(for: adapter.capabilities) == .tierCPlainChat, "cloud chat adapter should be Tier C")

        let gateway = AgentModelGateway(adapters: [adapter])
        let result = await gateway.response(
            adapterID: descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .plainChat,
                messages: [
                    AgentKernelMessageV2(role: .system, content: "local-only system prompt"),
                    AgentKernelMessageV2(role: .user, content: "hello"),
                    AgentKernelMessageV2(role: .assistant, content: "hi"),
                    AgentKernelMessageV2(role: .observation, content: "local file evidence"),
                    AgentKernelMessageV2(role: .user, content: "answer from cloud")
                ],
                requestedMaxOutputTokens: 256
            )
        )
        let captured = backend.lastRequest()

        try expect(result.response?.events == [.finalAnswer("cloud answer")], "cloud chat should return display text as a final answer")
        try expect(captured?.actionKind == .chat, "cloud chat adapter should call the chat action")
        try expect(captured?.cloudQuestion == "answer from cloud", "cloud chat adapter should send the latest user message as question")
        try expect(captured?.prompt == "answer from cloud", "cloud chat adapter should not send an AGENTR protocol prompt")
        try expect(captured?.cloudConversation.count == 2, "cloud chat adapter should send only prior user/assistant turns")
        try expect(captured?.cloudConversation.map(\.content) == ["hello", "hi"], "cloud chat adapter should omit system and observation messages")
    }

    private static func testCloudChatAdapterSupportsToolProtocolWhenEnabled() async throws {
        let backend = FixtureCloudChatBackend(
            responseText: ##"{"type":"tool_call","name":"read_file","arguments":{"path":"notes.txt"},"reason":"Need local evidence."}"##
        )
        let descriptor = AgentKernelModelDescriptorV2(
            id: "fixture.cloud-tools",
            providerKind: .pixelPaneCloud,
            route: .cloud,
            displayName: "Fixture Cloud Tools"
        )
        let adapter = AgentKernelCloudChatAdapterV2(
            descriptor: descriptor,
            backend: backend,
            backendCapabilities: await backend.capabilities(),
            supportsLocalToolProtocol: true
        )
        try expect(AgentModelGateway.tier(for: adapter.capabilities) == .tierBConstrainedStructuredText, "cloud tool adapter should be Tier B")

        let gateway = AgentModelGateway(adapters: [adapter])
        let result = await gateway.response(
            adapterID: descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .constrainedStructuredText,
                messages: [AgentKernelMessageV2(role: .user, content: "read notes")],
                tools: [readFileTool()],
                requestedMaxOutputTokens: 256
            )
        )
        let captured = backend.lastRequest()

        guard case .toolCall(let call)? = result.response?.events.first else {
            throw HarnessError(description: "cloud tool adapter should parse text-protocol tool call")
        }
        try expect(call.name == "read_file", "cloud tool adapter should return the requested tool call")
        try expect(call.arguments["path"] == "notes.txt", "cloud tool adapter should preserve tool arguments")
        try expect(captured?.actionKind == .chat, "cloud tool adapter should still use the cloud chat endpoint")
        try expect(captured?.cloudQuestion?.contains("Valid tool call format") == true, "cloud tool adapter should send the AGENTR protocol prompt as the cloud question")
        try expect(captured?.prompt == captured?.cloudQuestion, "cloud prompt and question should carry the same protocol text")
        try expect(captured?.cloudConversation.isEmpty == true, "cloud tool protocol should keep observations inside the protocol prompt")
    }

    private static func testTierCCloudRouteRejectsToolsBeforeAdapterCall() async throws {
        let cloud = fixtureAdapter(
            id: "fixture.cloud-route-guard",
            route: .cloud,
            toolCallingMode: .none,
            structured: .unsupported,
            responses: [.finalAnswer("should not execute")]
        )
        let gateway = AgentModelGateway(adapters: [cloud])
        let result = await gateway.response(
            adapterID: cloud.descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .constrainedStructuredText,
                messages: [AgentKernelMessageV2(role: .user, content: "read local file")],
                tools: [readFileTool()]
            )
        )
        let lastRequest = await cloud.lastRequest()

        try expect(result.failure?.kind == .unsupportedToolMode, "Tier C cloud route should reject local tool mode")
        try expect(lastRequest == nil, "Tier C cloud route should fail before adapter execution")
    }

    private static func testWrappedProtocolPayloadsNormalize() async throws {
        let rawProtocol = ##"""
        ```json
        {"type":"final_answer","text":"Wrapped answer"}
        ```<|im_end|>
        """##
        let backend = FixtureRawProtocolBackend(rawText: rawProtocol, displayText: rawProtocol)
        let descriptor = AgentKernelModelDescriptorV2(
            id: "fixture.wrapped-protocol",
            providerKind: .fixture,
            route: .local,
            displayName: "Fixture Wrapped Protocol"
        )
        let adapter = AgentKernelAIBackendAdapterV2(
            descriptor: descriptor,
            backend: backend,
            capabilities: AgentKernelModelAdapterCapabilitiesV2(
                descriptor: descriptor,
                toolCallingMode: .textProtocol,
                structuredOutputReliability: .bestEffort,
                streamingMode: .snapshots
            )
        )
        let gateway = AgentModelGateway(adapters: [adapter])
        let result = await gateway.response(
            adapterID: descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .constrainedStructuredText,
                messages: [AgentKernelMessageV2(role: .user, content: "answer")],
                tools: [readFileTool()]
            )
        )

        try expect(result.response?.events == [.finalAnswer("Wrapped answer")], "fenced protocol JSON with stop tokens should normalize")
    }

    private static func request(
        mode: AgentModelGatewayMode,
        tools: [AgentKernelToolSchemaV2] = [],
        timeout: TimeInterval? = nil
    ) -> AgentModelGatewayRequest {
        AgentModelGatewayRequest(
            mode: mode,
            messages: [AgentKernelMessageV2(role: .user, content: "hello")],
            tools: tools,
            timeout: timeout
        )
    }

    private static func readFileTool() -> AgentKernelToolSchemaV2 {
        AgentKernelToolSchemaV2(
            name: "read_file",
            summary: "Read a granted file.",
            requiredArguments: ["path"]
        )
    }

    private static func stageWriteTool() -> AgentKernelToolSchemaV2 {
        AgentKernelToolSchemaV2(
            name: "stage_write_proposal",
            summary: "Stage a write proposal.",
            requiredArguments: ["operation", "targetPath", "content"],
            arguments: [
                AgentKernelToolArgumentSchemaV2(name: "operation", type: .string, isRequired: true, summary: "Operation."),
                AgentKernelToolArgumentSchemaV2(name: "targetPath", type: .string, isRequired: true, summary: "Target path."),
                AgentKernelToolArgumentSchemaV2(name: "content", type: .string, isRequired: true, summary: "Content.")
            ]
        )
    }

    private static func fixtureAdapter(
        id: String = UUID().uuidString,
        route: AgentKernelModelRouteV2 = .local,
        toolCallingMode: AgentKernelToolCallingModeV2 = .native,
        structured: AgentKernelStructuredOutputReliabilityV2 = .strict,
        limits: AgentKernelModelLimitsV2 = AgentKernelModelLimitsV2(contextWindowTokens: 8_192),
        isAvailable: Bool = true,
        responses: [FixtureAgentKernelAdapterV2.ScriptedResponse]
    ) -> FixtureAgentKernelAdapterV2 {
        let descriptor = AgentKernelModelDescriptorV2(
            id: id,
            providerKind: .fixture,
            route: route,
            displayName: id
        )
        let capabilities = AgentKernelModelAdapterCapabilitiesV2(
            descriptor: descriptor,
            toolCallingMode: toolCallingMode,
            structuredOutputReliability: structured,
            streamingMode: .events,
            limits: limits,
            isAvailable: isAvailable,
            unavailableReason: isAvailable ? nil : AgentKernelBoundedTextV2("Fixture unavailable")
        )
        return FixtureAgentKernelAdapterV2(
            descriptor: descriptor,
            capabilities: capabilities,
            responses: responses
        )
    }
}

final class FixtureRawProtocolBackend: AIBackend, @unchecked Sendable {
    let id = "fixture-raw-protocol"
    let displayName = "Fixture Raw Protocol"

    private let rawText: String
    private let displayText: String

    init(rawText: String, displayText: String) {
        self.rawText = rawText
        self.displayText = displayText
    }

    func capabilities() async -> AIBackendCapabilities {
        AIBackendCapabilities(
            text: .available(.mlxText),
            image: .unavailable(.imageInputUnsupported),
            contextWindowTokens: nil,
            maxPromptCharacters: 80_000,
            maxOutputTokens: 1_024
        )
    }

    func streamResponse(for request: AIBackendRequest) -> AsyncThrowingStream<AIBackendStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .output(
                    AIModelOutput(
                        finalText: displayText,
                        reasoningText: nil,
                        statistics: [],
                        rawText: rawText
                    )
                )
            )
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}

final class FixtureCloudChatBackend: AIBackend, @unchecked Sendable {
    let id = "fixture-cloud-chat"
    let displayName = "Fixture Cloud Chat"

    private let responseText: String
    private let lock = NSLock()
    private var capturedRequests: [AIBackendRequest] = []

    init(responseText: String) {
        self.responseText = responseText
    }

    func capabilities() async -> AIBackendCapabilities {
        AIBackendCapabilities(
            text: .available(.pixelPaneCloud),
            image: .unavailable(.cloudImageConsentMissing),
            contextWindowTokens: nil,
            maxPromptCharacters: 80_000,
            maxOutputTokens: 1_024
        )
    }

    func streamResponse(for request: AIBackendRequest) -> AsyncThrowingStream<AIBackendStreamEvent, Error> {
        lock.lock()
        capturedRequests.append(request)
        lock.unlock()
        let responseText = self.responseText
        return AsyncThrowingStream { continuation in
            continuation.yield(.snapshot(responseText))
            continuation.yield(.completed)
            continuation.finish()
        }
    }

    func lastRequest() -> AIBackendRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests.last
    }
}

@main
struct AgentModelGatewayFixtureMain {
    static func main() async {
        do {
            try await AgentModelGatewayFixtureHarness.run()
            print("Agent model gateway fixture tests passed")
        } catch {
            fputs("Agent model gateway fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
