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
        try testConformanceProfileTierDerivation()
        try await testLocalMLXDefaultsToPlainChatUntilChecked()
        try await testLocalMLXConformanceProfileEnablesTierB()
        try await testLocalMLXNativeProfileUsesNativeToolRequests()
        try await testConformanceRunnerRecordsProbeResults()
        try await testConformanceRunnerUsesNativeToolProbes()
        try await testNativeConformanceDoesNotRequireTextProtocolJSON()
        try testConformanceStoreUsesExactTarget()
        try await testConformanceTimeoutFallsBackToPlainChatTier()
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

    private static func testConformanceProfileTierDerivation() throws {
        let target = mlxConformanceTarget(modelID: "fixture/model-a", modelPath: "/tmp/model-a")
        let plainPass = AgentModelConformanceProbeResult.passed("plain")
        let pass = AgentModelConformanceProbeResult.passed("pass")
        let fail = AgentModelConformanceProbeResult.failed("fail")
        let tierCProfile = AgentModelConformanceProfile(
            target: target,
            plainChat: plainPass,
            structuredJSON: fail,
            toolCall: fail,
            toolResultFollowUp: fail,
            latency: pass
        )
        let tierBProfile = AgentModelConformanceProfile(
            target: target,
            plainChat: plainPass,
            structuredJSON: pass,
            toolCall: pass,
            toolResultFollowUp: pass,
            latency: pass
        )
        let unavailableProfile = AgentModelConformanceProfile(
            target: target,
            plainChat: .timedOut("plain timed out"),
            structuredJSON: .skipped("not reached"),
            toolCall: .skipped("not reached"),
            toolResultFollowUp: .skipped("not reached"),
            latency: .timedOut("timeout")
        )

        try expect(tierCProfile.derivedTier == .tierC, "plain chat plus failed JSON/tool probes should derive Tier C")
        try expect(tierBProfile.derivedTier == .tierB, "structured JSON, tool-call, and tool-result probes should derive Tier B")
        try expect(unavailableProfile.derivedTier == .unavailable, "plain chat failure should derive unavailable")
        try expect(unavailableProfile.derivedTier.gatewayTier == .tierCPlainChat, "unavailable conformance should route as plain chat only")
    }

    private static func testLocalMLXDefaultsToPlainChatUntilChecked() async throws {
        let adapter = fixtureAdapter(
            id: AgentModelConformanceTarget.localMLXChatAdapterID,
            providerKind: .mlxLocal,
            modelName: "fixture/model-a",
            toolCallingMode: .textProtocol,
            structured: .bestEffort,
            responses: [.finalAnswer("plain")]
        )
        let gateway = AgentModelGateway(adapters: [adapter])
        let tier = await gateway.tier(adapterID: adapter.descriptor.id)
        let toolResult = await gateway.response(
            adapterID: adapter.descriptor.id,
            request: request(mode: .constrainedStructuredText, tools: [readFileTool()])
        )
        let plainResult = await gateway.response(
            adapterID: adapter.descriptor.id,
            request: request(mode: .plainChat, tools: [readFileTool()])
        )
        let requests = await adapter.requests()

        try expect(tier == .tierCPlainChat, "unchecked local MLX text protocol adapters should default to Tier C")
        try expect(toolResult.failure?.kind == .unsupportedToolMode, "unchecked local MLX should reject tool-loop mode before adapter execution")
        try expect(plainResult.response?.events == [.finalAnswer("plain")], "unchecked local MLX should remain usable for plain chat")
        try expect(requests.count == 1, "only the plain chat request should reach the adapter")
        try expect(requests.first?.tools.isEmpty == true, "plain chat should not receive tool schemas")
        try expect(requests.first?.responseFormat == AgentKernelToolCallingMode.none, "plain chat should not request JSON protocol")
    }

    private static func testLocalMLXConformanceProfileEnablesTierB() async throws {
        let target = mlxConformanceTarget(modelID: "fixture/model-b", modelPath: "/tmp/model-b")
        let profile = tierBConformanceProfile(target: target)
        let adapter = fixtureAdapter(
            id: target.adapterID,
            providerKind: .mlxLocal,
            modelName: target.modelID,
            toolCallingMode: .textProtocol,
            structured: .bestEffort,
            responses: [.toolCall(name: "read_file", arguments: ["path": "notes.txt"], reason: nil)]
        )
        let staticTier = AgentModelGateway.tier(for: adapter.capabilities, conformanceProfile: profile)
        let gateway = AgentModelGateway(adapters: [adapter], conformanceProfiles: [profile])
        let gatewayTier = await gateway.tier(adapterID: adapter.descriptor.id)
        let result = await gateway.response(
            adapterID: adapter.descriptor.id,
            request: request(mode: .constrainedStructuredText, tools: [readFileTool()])
        )

        guard case .toolCall(let call)? = result.response?.events.first else {
            throw HarnessError(description: "proved local MLX profile should allow constrained tool calls")
        }
        try expect(staticTier == .tierBConstrainedStructuredText, "matching conformance profile should make local MLX Tier B")
        try expect(gatewayTier == .tierBConstrainedStructuredText, "gateway tier should consult the matching conformance profile")
        try expect(call.name == "read_file", "proved local MLX should return the validated tool call")
    }

    private static func testLocalMLXNativeProfileUsesNativeToolRequests() async throws {
        let target = mlxConformanceTarget(modelID: "fixture/model-native", modelPath: "/tmp/model-native")
        let profile = tierBConformanceProfile(target: target)
        let adapter = fixtureAdapter(
            id: target.adapterID,
            providerKind: .mlxLocal,
            modelName: target.modelID,
            toolCallingMode: .native,
            structured: .bestEffort,
            responses: [.toolCall(name: "read_file", arguments: ["path": "notes.txt"], reason: nil)]
        )
        let gateway = AgentModelGateway(adapters: [adapter], conformanceProfiles: [profile])
        let result = await gateway.response(
            adapterID: adapter.descriptor.id,
            request: request(mode: .constrainedStructuredText, tools: [readFileTool()])
        )
        let lastRequest = await adapter.lastRequest()

        guard case .toolCall(let call)? = result.response?.events.first else {
            throw HarnessError(description: "proved native local MLX profile should allow constrained native tool calls")
        }
        try expect(call.name == "read_file", "native local MLX should return the validated tool call")
        try expect(lastRequest?.responseFormat == .native, "profile-backed native local MLX should use native tool protocol")
        try expect(lastRequest?.tools.map(\.name) == ["read_file"], "native local MLX should receive tool schemas")
    }

    private static func testConformanceRunnerRecordsProbeResults() async throws {
        let target = mlxConformanceTarget(modelID: "fixture/model-c", modelPath: "/tmp/model-c")
        let adapter = fixtureAdapter(
            id: target.adapterID,
            providerKind: .mlxLocal,
            modelName: target.modelID,
            toolCallingMode: .textProtocol,
            structured: .bestEffort,
            responses: [
                .finalAnswer("4"),
                .finalAnswer("structured-ok"),
                .toolCall(name: "pixelpane_probe_echo", arguments: ["text": "probe-ok"], reason: nil),
                .finalAnswer("probe-ok")
            ]
        )
        let profile = await AgentModelConformanceRunner(perProbeTimeout: 2).run(
            adapter: adapter,
            target: target
        )
        let requests = await adapter.requests()

        try expect(profile.derivedTier == .tierB, "passing conformance probes should record a Tier B profile")
        try expect(profile.plainChat.status == .passed, "plain chat probe should pass")
        try expect(profile.structuredJSON.status == .passed, "structured JSON probe should pass")
        try expect(profile.toolCall.status == .passed, "tool-call probe should pass")
        try expect(profile.toolResultFollowUp.status == .passed, "tool-result follow-up probe should pass")
        try expect(profile.latency.durationSeconds != nil, "profile should record latency timing")
        try expect(requests.count == 4, "conformance runner should issue four probes")
        try expect(requests.map(\.responseFormat) == [.none, .textProtocol, .textProtocol, .textProtocol], "conformance should test plain chat separately from JSON/tool protocol")
        try expect(requests[2].tools.map(\.name) == ["pixelpane_probe_echo"], "tool-call probe should use an explicit schema")
    }

    private static func testConformanceRunnerUsesNativeToolProbes() async throws {
        let target = mlxConformanceTarget(modelID: "fixture/model-native-probes", modelPath: "/tmp/model-native-probes")
        let adapter = fixtureAdapter(
            id: target.adapterID,
            providerKind: .mlxLocal,
            modelName: target.modelID,
            toolCallingMode: .native,
            structured: .bestEffort,
            responses: [
                .finalAnswer("4"),
                .finalAnswer("structured-ok"),
                .toolCall(name: "pixelpane_probe_echo", arguments: ["text": "probe-ok"], reason: nil),
                .finalAnswer("probe-ok")
            ]
        )
        let profile = await AgentModelConformanceRunner(perProbeTimeout: 2).run(
            adapter: adapter,
            target: target
        )
        let requests = await adapter.requests()

        try expect(profile.derivedTier == .tierB, "native tool conformance probes should derive Tier B after passing")
        try expect(requests.map(\.responseFormat) == [.none, .textProtocol, .native, .native], "native adapters should use native tool probes while still checking structured JSON")
        try expect(requests[2].tools.map(\.name) == ["pixelpane_probe_echo"], "native tool-call probe should use an explicit schema")
        try expect(requests[3].messages.contains(where: { $0.role == .observation && $0.content.contains("probe-ok") }), "native tool-result probe should include the runtime observation")
    }

    private static func testNativeConformanceDoesNotRequireTextProtocolJSON() async throws {
        let target = mlxConformanceTarget(modelID: "fixture/model-native-json-flake", modelPath: "/tmp/model-native-json-flake")
        let adapter = fixtureAdapter(
            id: target.adapterID,
            providerKind: .mlxLocal,
            modelName: target.modelID,
            toolCallingMode: .native,
            structured: .bestEffort,
            responses: [
                .finalAnswer("4"),
                .malformedOutput("not-json"),
                .toolCall(name: "pixelpane_probe_echo", arguments: ["text": "probe-ok"], reason: nil),
                .finalAnswer("probe-ok")
            ]
        )
        let profile = await AgentModelConformanceRunner(perProbeTimeout: 2).run(
            adapter: adapter,
            target: target
        )

        try expect(profile.structuredJSON.status == .failed, "fixture should reproduce a failed generic JSON probe")
        try expect(profile.toolCall.status == .passed, "native tool-call probe should pass")
        try expect(profile.toolResultFollowUp.status == .passed, "native tool-result follow-up probe should pass")
        try expect(profile.derivedTier == .tierB, "native MLX tool readiness should not be vetoed by generic text-protocol JSON flake")
    }

    private static func testConformanceStoreUsesExactTarget() throws {
        let defaultsName = "AgentModelGatewayFixture-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsName) else {
            throw HarnessError(description: "could not create fixture defaults")
        }
        defaults.removePersistentDomain(forName: defaultsName)
        let store = AgentModelConformanceStore(defaults: defaults)
        let firstTarget = mlxConformanceTarget(modelID: "fixture/model-d", modelPath: "/tmp/model-d")
        let secondTarget = mlxConformanceTarget(modelID: "fixture/model-d", modelPath: "/tmp/other-model-d")
        let profile = tierBConformanceProfile(target: firstTarget)

        store.save(profile)

        try expect(store.profile(for: firstTarget) == profile, "store should return the exact saved target profile")
        try expect(store.profile(for: secondTarget) == nil, "changing the selected model path should not reuse the old profile")
        defaults.removePersistentDomain(forName: defaultsName)
    }

    private static func testConformanceTimeoutFallsBackToPlainChatTier() async throws {
        let target = mlxConformanceTarget(modelID: "fixture/model-e", modelPath: "/tmp/model-e")
        let adapter = fixtureAdapter(
            id: target.adapterID,
            providerKind: .mlxLocal,
            modelName: target.modelID,
            toolCallingMode: .textProtocol,
            structured: .bestEffort,
            responses: [
                .timeout,
                .finalAnswer("unused"),
                .toolCall(name: "pixelpane_probe_echo", arguments: ["text": "probe-ok"], reason: nil),
                .finalAnswer("probe-ok")
            ]
        )
        let profile = await AgentModelConformanceRunner(perProbeTimeout: 2).run(
            adapter: adapter,
            target: target
        )
        let tier = AgentModelGateway.tier(for: adapter.capabilities, conformanceProfile: profile)

        try expect(profile.plainChat.status == .timedOut, "timeout result should be recorded in the profile")
        try expect(profile.derivedTier == .unavailable, "plain chat timeout should derive unavailable conformance")
        try expect(tier == .tierCPlainChat, "timeout conformance should leave routing at plain chat only")
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
        try expect(lastRequest?.responseFormat == AgentKernelToolCallingMode.none, "plain chat should request no structured tool format")
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
            limits: AgentKernelModelLimits(maxPromptCharacters: 4),
            responses: [.finalAnswer("unused")]
        )
        let gateway = AgentModelGateway(adapters: [adapter])
        let result = await gateway.response(
            adapterID: adapter.descriptor.id,
            request: AgentModelGatewayRequest(
                mode: .plainChat,
                messages: [AgentKernelMessage(role: .user, content: "too long")]
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
        let descriptor = AgentKernelModelDescriptor(
            id: "fixture.ai-backend-raw",
            providerKind: .fixture,
            route: .local,
            displayName: "Fixture Raw Backend"
        )
        let adapter = AgentKernelAIBackendAdapter(
            descriptor: descriptor,
            backend: backend,
            capabilities: AgentKernelModelAdapterCapabilities(
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
                messages: [AgentKernelMessage(role: .user, content: "write script")],
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
        let descriptor = AgentKernelModelDescriptor(
            id: "fixture.cloud-chat",
            providerKind: .pixelPaneCloud,
            route: .cloud,
            displayName: "Fixture Cloud"
        )
        let adapter = AgentKernelCloudChatAdapter(
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
                    AgentKernelMessage(role: .system, content: "local-only system prompt"),
                    AgentKernelMessage(role: .user, content: "hello"),
                    AgentKernelMessage(role: .assistant, content: "hi"),
                    AgentKernelMessage(role: .observation, content: "local file evidence"),
                    AgentKernelMessage(role: .user, content: "answer from cloud")
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
        let descriptor = AgentKernelModelDescriptor(
            id: "fixture.cloud-tools",
            providerKind: .pixelPaneCloud,
            route: .cloud,
            displayName: "Fixture Cloud Tools"
        )
        let adapter = AgentKernelCloudChatAdapter(
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
                messages: [AgentKernelMessage(role: .user, content: "read notes")],
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
                messages: [AgentKernelMessage(role: .user, content: "read local file")],
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
        let descriptor = AgentKernelModelDescriptor(
            id: "fixture.wrapped-protocol",
            providerKind: .fixture,
            route: .local,
            displayName: "Fixture Wrapped Protocol"
        )
        let adapter = AgentKernelAIBackendAdapter(
            descriptor: descriptor,
            backend: backend,
            capabilities: AgentKernelModelAdapterCapabilities(
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
                messages: [AgentKernelMessage(role: .user, content: "answer")],
                tools: [readFileTool()]
            )
        )

        try expect(result.response?.events == [.finalAnswer("Wrapped answer")], "fenced protocol JSON with stop tokens should normalize")
    }

    private static func request(
        mode: AgentModelGatewayMode,
        tools: [AgentKernelToolSchema] = [],
        timeout: TimeInterval? = nil
    ) -> AgentModelGatewayRequest {
        AgentModelGatewayRequest(
            mode: mode,
            messages: [AgentKernelMessage(role: .user, content: "hello")],
            tools: tools,
            timeout: timeout
        )
    }

    private static func readFileTool() -> AgentKernelToolSchema {
        AgentKernelToolSchema(
            name: "read_file",
            summary: "Read a granted file.",
            requiredArguments: ["path"]
        )
    }

    private static func stageWriteTool() -> AgentKernelToolSchema {
        AgentKernelToolSchema(
            name: "stage_write_proposal",
            summary: "Stage a write proposal.",
            requiredArguments: ["operation", "targetPath", "content"],
            arguments: [
                AgentKernelToolArgumentSchema(name: "operation", type: .string, isRequired: true, summary: "Operation."),
                AgentKernelToolArgumentSchema(name: "targetPath", type: .string, isRequired: true, summary: "Target path."),
                AgentKernelToolArgumentSchema(name: "content", type: .string, isRequired: true, summary: "Content.")
            ]
        )
    }

    private static func fixtureAdapter(
        id: String = UUID().uuidString,
        providerKind: AgentKernelModelProviderKind = .fixture,
        route: AgentKernelModelRoute = .local,
        modelName: String? = nil,
        toolCallingMode: AgentKernelToolCallingMode = .native,
        structured: AgentKernelStructuredOutputReliability = .strict,
        limits: AgentKernelModelLimits = AgentKernelModelLimits(contextWindowTokens: 8_192),
        isAvailable: Bool = true,
        responses: [FixtureAgentKernelAdapter.ScriptedResponse]
    ) -> FixtureAgentKernelAdapter {
        let descriptor = AgentKernelModelDescriptor(
            id: id,
            providerKind: providerKind,
            route: route,
            displayName: id,
            modelName: modelName
        )
        let capabilities = AgentKernelModelAdapterCapabilities(
            descriptor: descriptor,
            toolCallingMode: toolCallingMode,
            structuredOutputReliability: structured,
            streamingMode: .events,
            limits: limits,
            isAvailable: isAvailable,
            unavailableReason: isAvailable ? nil : AgentKernelBoundedText("Fixture unavailable")
        )
        return FixtureAgentKernelAdapter(
            descriptor: descriptor,
            capabilities: capabilities,
            responses: responses
        )
    }

    private static func mlxConformanceTarget(
        modelID: String,
        modelPath: String
    ) -> AgentModelConformanceTarget {
        AgentModelConformanceTarget(
            providerKind: .mlxLocal,
            route: .local,
            adapterID: AgentModelConformanceTarget.localMLXChatAdapterID,
            modelID: modelID,
            modelPath: modelPath,
            runtimeExecutablePath: "/usr/local/bin/mlx_lm.generate",
            runtimeVersion: nil
        )
    }

    private static func tierBConformanceProfile(
        target: AgentModelConformanceTarget
    ) -> AgentModelConformanceProfile {
        let pass = AgentModelConformanceProbeResult.passed("pass")
        return AgentModelConformanceProfile(
            target: target,
            plainChat: pass,
            structuredJSON: pass,
            toolCall: pass,
            toolResultFollowUp: pass,
            latency: pass
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
