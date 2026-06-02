import Foundation

nonisolated enum AgentModelConformanceProbeStatus: String, Codable, Equatable, Sendable {
    case passed
    case failed
    case timedOut
    case canceled
    case skipped

    var isPassed: Bool {
        self == .passed
    }
}

nonisolated struct AgentModelConformanceProbeResult: Codable, Equatable, Sendable {
    let status: AgentModelConformanceProbeStatus
    let summary: AgentRunText
    let durationSeconds: Double?
    let rawOutput: AgentRunText?

    init(
        status: AgentModelConformanceProbeStatus,
        summary: AgentRunText,
        durationSeconds: Double? = nil,
        rawOutput: AgentRunText? = nil
    ) {
        self.status = status
        self.summary = summary
        self.durationSeconds = durationSeconds
        self.rawOutput = rawOutput
    }

    static func passed(_ summary: String, durationSeconds: Double? = nil, rawOutput: String? = nil) -> AgentModelConformanceProbeResult {
        AgentModelConformanceProbeResult(
            status: .passed,
            summary: AgentRunText(summary),
            durationSeconds: durationSeconds,
            rawOutput: rawOutput.map { AgentRunText($0, characterLimit: 2_000) }
        )
    }

    static func failed(_ summary: String, durationSeconds: Double? = nil, rawOutput: String? = nil) -> AgentModelConformanceProbeResult {
        AgentModelConformanceProbeResult(
            status: .failed,
            summary: AgentRunText(summary),
            durationSeconds: durationSeconds,
            rawOutput: rawOutput.map { AgentRunText($0, characterLimit: 2_000) }
        )
    }

    static func timedOut(_ summary: String, durationSeconds: Double? = nil) -> AgentModelConformanceProbeResult {
        AgentModelConformanceProbeResult(
            status: .timedOut,
            summary: AgentRunText(summary),
            durationSeconds: durationSeconds
        )
    }

    static func canceled(_ summary: String) -> AgentModelConformanceProbeResult {
        AgentModelConformanceProbeResult(
            status: .canceled,
            summary: AgentRunText(summary)
        )
    }

    static func skipped(_ summary: String) -> AgentModelConformanceProbeResult {
        AgentModelConformanceProbeResult(
            status: .skipped,
            summary: AgentRunText(summary)
        )
    }
}

nonisolated enum AgentModelConformanceDerivedTier: String, Codable, Equatable, Sendable {
    case tierA
    case tierB
    case tierC
    case unavailable

    var gatewayTier: AgentModelCapabilityTier {
        switch self {
        case .tierA:
            .tierAFullAgent
        case .tierB:
            .tierBConstrainedStructuredText
        case .tierC, .unavailable:
            .tierCPlainChat
        }
    }
}

nonisolated struct AgentModelConformanceTarget: Codable, Equatable, Sendable {
    static let localMLXChatAdapterID = "local.hybrid-local.chat"

    let providerKind: AgentKernelModelProviderKindV2
    let route: AgentKernelModelRouteV2
    let adapterID: String
    let modelID: String
    let modelPath: String?
    let runtimeExecutablePath: String?
    let runtimeVersion: String?

    init(
        providerKind: AgentKernelModelProviderKindV2,
        route: AgentKernelModelRouteV2,
        adapterID: String,
        modelID: String,
        modelPath: String? = nil,
        runtimeExecutablePath: String? = nil,
        runtimeVersion: String? = nil
    ) {
        self.providerKind = providerKind
        self.route = route
        self.adapterID = adapterID
        self.modelID = modelID
        self.modelPath = modelPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        self.runtimeExecutablePath = runtimeExecutablePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        self.runtimeVersion = runtimeVersion
    }

    var storageKey: String {
        [
            providerKind.rawValue,
            route.rawValue,
            adapterID,
            modelID,
            modelPath ?? "",
            runtimeExecutablePath ?? "",
            runtimeVersion ?? ""
        ].joined(separator: "\u{1F}")
    }

    func matches(descriptor: AgentKernelModelDescriptorV2) -> Bool {
        guard providerKind == descriptor.providerKind,
              route == descriptor.route,
              adapterID == descriptor.id else {
            return false
        }
        guard let descriptorModelName = descriptor.modelName else {
            return true
        }
        return descriptorModelName == modelID
    }
}

nonisolated struct AgentModelConformanceProfile: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 3

    let id: String
    let schemaVersion: Int
    let target: AgentModelConformanceTarget
    let testedAt: Date
    let plainChat: AgentModelConformanceProbeResult
    let structuredJSON: AgentModelConformanceProbeResult
    let toolCall: AgentModelConformanceProbeResult
    let toolResultFollowUp: AgentModelConformanceProbeResult
    let latency: AgentModelConformanceProbeResult
    let derivedTier: AgentModelConformanceDerivedTier

    init(
        target: AgentModelConformanceTarget,
        testedAt: Date = Date(),
        plainChat: AgentModelConformanceProbeResult,
        structuredJSON: AgentModelConformanceProbeResult,
        toolCall: AgentModelConformanceProbeResult,
        toolResultFollowUp: AgentModelConformanceProbeResult,
        latency: AgentModelConformanceProbeResult,
        derivedTier: AgentModelConformanceDerivedTier? = nil
    ) {
        id = target.storageKey
        schemaVersion = Self.currentSchemaVersion
        self.target = target
        self.testedAt = testedAt
        self.plainChat = plainChat
        self.structuredJSON = structuredJSON
        self.toolCall = toolCall
        self.toolResultFollowUp = toolResultFollowUp
        self.latency = latency
        self.derivedTier = derivedTier ?? Self.deriveTier(
            plainChat: plainChat,
            structuredJSON: structuredJSON,
            toolCall: toolCall,
            toolResultFollowUp: toolResultFollowUp
        )
    }

    static func deriveTier(
        plainChat: AgentModelConformanceProbeResult,
        structuredJSON: AgentModelConformanceProbeResult,
        toolCall: AgentModelConformanceProbeResult,
        toolResultFollowUp: AgentModelConformanceProbeResult
    ) -> AgentModelConformanceDerivedTier {
        guard plainChat.status.isPassed else {
            return .unavailable
        }
        guard structuredJSON.status.isPassed,
              toolCall.status.isPassed,
              toolResultFollowUp.status.isPassed else {
            return .tierC
        }
        return .tierB
    }

    static func deriveNativeToolTier(
        plainChat: AgentModelConformanceProbeResult,
        toolCall: AgentModelConformanceProbeResult,
        toolResultFollowUp: AgentModelConformanceProbeResult
    ) -> AgentModelConformanceDerivedTier {
        guard plainChat.status.isPassed else {
            return .unavailable
        }
        guard toolCall.status.isPassed,
              toolResultFollowUp.status.isPassed else {
            return .tierC
        }
        return .tierB
    }
}

nonisolated struct AgentModelConformanceStore: @unchecked Sendable {
    private static let profilesKey = "AgentModelConformanceProfiles.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func profile(for target: AgentModelConformanceTarget?) -> AgentModelConformanceProfile? {
        guard let target else { return nil }
        return profiles()[target.storageKey]
    }

    func save(_ profile: AgentModelConformanceProfile) {
        var values = profiles()
        values[profile.target.storageKey] = profile
        if let data = try? encoder.encode(values) {
            defaults.set(data, forKey: Self.profilesKey)
        }
    }

    func removeProfile(for target: AgentModelConformanceTarget) {
        var values = profiles()
        values.removeValue(forKey: target.storageKey)
        if let data = try? encoder.encode(values) {
            defaults.set(data, forKey: Self.profilesKey)
        }
    }

    func profiles() -> [String: AgentModelConformanceProfile] {
        guard let data = defaults.data(forKey: Self.profilesKey),
              let values = try? decoder.decode([String: AgentModelConformanceProfile].self, from: data) else {
            return [:]
        }
        return values.filter { _, profile in
            profile.schemaVersion == AgentModelConformanceProfile.currentSchemaVersion
        }
    }
}

private enum AgentModelConformanceRunnerError: Error {
    case timeout
}

nonisolated struct AgentModelConformanceRunner: Sendable {
    let perProbeTimeout: TimeInterval

    init(perProbeTimeout: TimeInterval = 45) {
        self.perProbeTimeout = max(1, perProbeTimeout)
    }

    func run(
        adapter: any AgentKernelModelAdapterV2,
        target: AgentModelConformanceTarget,
        requestedMaxOutputTokens: Int = 128
    ) async -> AgentModelConformanceProfile {
        let startedAt = Date()
        let plainChat = await probePlainChat(adapter: adapter, requestedMaxOutputTokens: requestedMaxOutputTokens)
        let structuredJSON = await nextProbeIfNotCanceled {
            await probeStructuredJSON(adapter: adapter, requestedMaxOutputTokens: requestedMaxOutputTokens)
        }
        let toolCall = await nextProbeIfNotCanceled {
            await probeToolCall(adapter: adapter, requestedMaxOutputTokens: requestedMaxOutputTokens)
        }
        let toolResultFollowUp = await nextProbeIfNotCanceled {
            await probeToolResultFollowUp(adapter: adapter, requestedMaxOutputTokens: requestedMaxOutputTokens)
        }
        let totalDuration = Date().timeIntervalSince(startedAt)
        let latencyStatus: AgentModelConformanceProbeStatus = [
            plainChat.status,
            structuredJSON.status,
            toolCall.status,
            toolResultFollowUp.status
        ].contains(.timedOut) ? .timedOut : (Task.isCancelled ? .canceled : .passed)
        let latency = AgentModelConformanceProbeResult(
            status: latencyStatus,
            summary: AgentRunText("Conformance probes finished in \(String(format: "%.2f", totalDuration)) seconds."),
            durationSeconds: totalDuration
        )
        return AgentModelConformanceProfile(
            target: target,
            testedAt: Date(),
            plainChat: plainChat,
            structuredJSON: structuredJSON,
            toolCall: toolCall,
            toolResultFollowUp: toolResultFollowUp,
            latency: latency,
            derivedTier: adapter.capabilities.toolCallingMode == .native
                ? AgentModelConformanceProfile.deriveNativeToolTier(
                    plainChat: plainChat,
                    toolCall: toolCall,
                    toolResultFollowUp: toolResultFollowUp
                )
                : nil
        )
    }

    private func nextProbeIfNotCanceled(
        _ operation: @escaping @Sendable () async -> AgentModelConformanceProbeResult
    ) async -> AgentModelConformanceProbeResult {
        guard !Task.isCancelled else {
            return .canceled("Conformance check was canceled before this probe ran.")
        }
        return await operation()
    }

    private func probePlainChat(
        adapter: any AgentKernelModelAdapterV2,
        requestedMaxOutputTokens: Int
    ) async -> AgentModelConformanceProbeResult {
        let request = AgentKernelModelAdapterRequestV2(
            messages: [
                AgentKernelMessageV2(role: .user, content: "Conformance probe: what is 2+2? Reply with a short answer.")
            ],
            requestedMaxOutputTokens: requestedMaxOutputTokens,
            responseFormat: .none,
            metadata: ["conformanceProbe": .string("plain_chat")]
        )
        return await responseProbe(adapter: adapter, request: request) { response, duration in
            guard let answer = Self.finalAnswer(from: response.events) else {
                return .failed("Plain chat did not return a final answer.", durationSeconds: duration, rawOutput: Self.rawOutput(from: response.events))
            }
            return .passed("Plain chat returned a final answer.", durationSeconds: duration, rawOutput: answer.text)
        }
    }

    private func probeStructuredJSON(
        adapter: any AgentKernelModelAdapterV2,
        requestedMaxOutputTokens: Int
    ) async -> AgentModelConformanceProbeResult {
        let request = AgentKernelModelAdapterRequestV2(
            messages: [
                AgentKernelMessageV2(role: .user, content: "Conformance probe: return a final answer saying structured-ok.")
            ],
            requestedMaxOutputTokens: requestedMaxOutputTokens,
            responseFormat: .textProtocol,
            metadata: ["conformanceProbe": .string("structured_json")]
        )
        return await responseProbe(adapter: adapter, request: request) { response, duration in
            guard let answer = Self.finalAnswer(from: response.events) else {
                return .failed("Structured JSON probe did not parse into a final answer.", durationSeconds: duration, rawOutput: Self.rawOutput(from: response.events))
            }
            return .passed("Structured JSON probe parsed into a final answer.", durationSeconds: duration, rawOutput: answer.text)
        }
    }

    private func probeToolCall(
        adapter: any AgentKernelModelAdapterV2,
        requestedMaxOutputTokens: Int
    ) async -> AgentModelConformanceProbeResult {
        let tool = Self.echoToolSchema()
        let responseFormat = adapter.capabilities.toolCallingMode == .native
            ? AgentKernelToolCallingModeV2.native
            : .textProtocol
        let request = AgentKernelModelAdapterRequestV2(
            messages: [
                AgentKernelMessageV2(role: .user, content: "Conformance probe: call pixelpane_probe_echo with text probe-ok.")
            ],
            tools: [tool],
            requestedMaxOutputTokens: requestedMaxOutputTokens,
            responseFormat: responseFormat,
            metadata: ["conformanceProbe": .string("tool_call")]
        )
        return await responseProbe(adapter: adapter, request: request) { response, duration in
            guard let call = Self.firstToolCall(from: response.events) else {
                return .failed("Tool-call probe did not parse into a tool call.", durationSeconds: duration, rawOutput: Self.rawOutput(from: response.events))
            }
            guard call.name == tool.name, call.arguments["text"] == "probe-ok" else {
                return .failed("Tool-call probe returned the wrong tool name or arguments.", durationSeconds: duration, rawOutput: Self.rawOutput(from: response.events))
            }
            return .passed("Tool-call probe returned the expected tool call.", durationSeconds: duration)
        }
    }

    private func probeToolResultFollowUp(
        adapter: any AgentKernelModelAdapterV2,
        requestedMaxOutputTokens: Int
    ) async -> AgentModelConformanceProbeResult {
        let responseFormat = adapter.capabilities.toolCallingMode == .native
            ? AgentKernelToolCallingModeV2.native
            : .textProtocol
        let request = AgentKernelModelAdapterRequestV2(
            messages: [
                AgentKernelMessageV2(role: .user, content: "Conformance probe: answer from the observation."),
                AgentKernelMessageV2(role: .observation, content: "Tool result\nname: pixelpane_probe_echo\nstatus: succeeded\nobservation: probe-ok")
            ],
            tools: [Self.echoToolSchema()],
            requestedMaxOutputTokens: requestedMaxOutputTokens,
            responseFormat: responseFormat,
            metadata: ["conformanceProbe": .string("tool_result_follow_up")]
        )
        return await responseProbe(adapter: adapter, request: request) { response, duration in
            guard let answer = Self.finalAnswer(from: response.events) else {
                return .failed("Tool-result follow-up probe did not parse into a final answer.", durationSeconds: duration, rawOutput: Self.rawOutput(from: response.events))
            }
            guard answer.text.localizedCaseInsensitiveContains("probe-ok") else {
                return .failed("Tool-result follow-up did not use the tool observation.", durationSeconds: duration, rawOutput: answer.text)
            }
            return .passed("Tool-result follow-up returned a final answer from the observation.", durationSeconds: duration, rawOutput: answer.text)
        }
    }

    private func responseProbe(
        adapter: any AgentKernelModelAdapterV2,
        request: AgentKernelModelAdapterRequestV2,
        validate: @escaping @Sendable (AgentKernelModelAdapterResponseV2, Double) -> AgentModelConformanceProbeResult
    ) async -> AgentModelConformanceProbeResult {
        let startedAt = Date()
        do {
            let response = try await withTimeout {
                await adapter.response(for: request)
            }
            let duration = Date().timeIntervalSince(startedAt)
            if response.events.contains(.timedOut) {
                return .timedOut("Adapter reported a timeout.", durationSeconds: duration)
            }
            if let malformed = Self.firstMalformedOutput(in: response.events) {
                return .failed("Adapter returned malformed protocol output.", durationSeconds: duration, rawOutput: malformed)
            }
            if response.events.isEmpty || Self.isSingleEmptyOutput(response.events) {
                return .failed("Adapter returned empty output.", durationSeconds: duration)
            }
            return validate(response, duration)
        } catch AgentModelConformanceRunnerError.timeout {
            return .timedOut("Probe timed out after \(Int(perProbeTimeout)) seconds.", durationSeconds: Date().timeIntervalSince(startedAt))
        } catch is CancellationError {
            return .canceled("Conformance probe was canceled.")
        } catch {
            return .failed("Conformance probe failed: \(String(describing: error))", durationSeconds: Date().timeIntervalSince(startedAt))
        }
    }

    private func withTimeout(
        _ operation: @escaping @Sendable () async -> AgentKernelModelAdapterResponseV2
    ) async throws -> AgentKernelModelAdapterResponseV2 {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: AgentKernelModelAdapterResponseV2.self) { group in
            group.addTask {
                try Task.checkCancellation()
                return await operation()
            }
            group.addTask {
                let nanoseconds = UInt64((perProbeTimeout * 1_000_000_000).rounded(.up))
                try await Task.sleep(nanoseconds: nanoseconds)
                throw AgentModelConformanceRunnerError.timeout
            }
            do {
                guard let result = try await group.next() else {
                    throw AgentModelConformanceRunnerError.timeout
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private static func echoToolSchema() -> AgentKernelToolSchemaV2 {
        AgentKernelToolSchemaV2(
            name: "pixelpane_probe_echo",
            summary: "Conformance probe echo tool. The app owns execution.",
            requiredArguments: ["text"],
            arguments: [
                AgentKernelToolArgumentSchemaV2(
                    name: "text",
                    type: .string,
                    isRequired: true,
                    summary: "Echo text."
                )
            ]
        )
    }

    private static func finalAnswer(from events: [AgentKernelModelAdapterEventV2]) -> AgentKernelFinalAnswerV2? {
        for event in events.reversed() {
            if case .finalAnswer(let answer) = event,
               !answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return answer
            }
        }
        return nil
    }

    private static func firstToolCall(from events: [AgentKernelModelAdapterEventV2]) -> AgentKernelToolCallV2? {
        for event in events {
            if case .toolCall(let call) = event {
                return call
            }
        }
        return nil
    }

    private static func firstMalformedOutput(in events: [AgentKernelModelAdapterEventV2]) -> String? {
        for event in events {
            if case .malformedOutput(let text) = event {
                return text
            }
        }
        return nil
    }

    private static func isSingleEmptyOutput(_ events: [AgentKernelModelAdapterEventV2]) -> Bool {
        guard events.count == 1 else { return false }
        guard case .emptyOutput = events[0] else { return false }
        return true
    }

    private static func rawOutput(from events: [AgentKernelModelAdapterEventV2]) -> String {
        events.map { event in
            switch event {
            case .snapshot(let text):
                return "snapshot: \(text)"
            case .finalAnswer(let answer):
                return "final_answer: \(answer.text)"
            case .toolCall(let call):
                return "tool_call: \(call.name) \(call.arguments)"
            case .malformedOutput(let text):
                return "malformed: \(text)"
            case .emptyOutput:
                return "empty"
            case .timedOut:
                return "timed_out"
            }
        }.joined(separator: "\n")
    }
}

nonisolated enum AgentModelCapabilityTier: String, Codable, Equatable, Sendable {
    case tierAFullAgent
    case tierBConstrainedStructuredText
    case tierCPlainChat
}

nonisolated enum AgentModelGatewayMode: String, Codable, Equatable, Sendable {
    case fullAgent
    case constrainedStructuredText
    case plainChat
}

nonisolated enum AgentModelGatewayFailureKind: String, Codable, Equatable, Error, Sendable {
    case unavailable
    case auth
    case rateLimited
    case contextTooLarge
    case timeout
    case canceled
    case emptyOutput
    case structuredOutputInvalid
    case toolCallInvalid
    case transportError
    case providerRefusal
    case unsupportedToolMode
    case unknown
}

nonisolated struct AgentModelGatewayFailure: Error, Codable, Equatable, Sendable, CustomStringConvertible {
    let kind: AgentModelGatewayFailureKind
    let adapterID: String
    let message: AgentRunText
    let metadata: [String: AgentRunMetadataValue]

    init(
        kind: AgentModelGatewayFailureKind,
        adapterID: String,
        message: AgentRunText,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) {
        self.kind = kind
        self.adapterID = adapterID
        self.message = message
        self.metadata = metadata
    }

    var description: String {
        "\(kind.rawValue): \(message.text)"
    }
}

nonisolated struct AgentModelGatewayRequest: Identifiable, Codable, Sendable {
    let id: UUID
    let mode: AgentModelGatewayMode
    let messages: [AgentKernelMessageV2]
    let tools: [AgentKernelToolSchemaV2]
    let attachments: [AgentKernelModelAttachmentV2]
    let requestedMaxOutputTokens: Int
    let timeout: TimeInterval?
    let metadata: [String: AgentRunMetadataValue]

    init(
        id: UUID = UUID(),
        mode: AgentModelGatewayMode,
        messages: [AgentKernelMessageV2],
        tools: [AgentKernelToolSchemaV2] = [],
        attachments: [AgentKernelModelAttachmentV2] = [],
        requestedMaxOutputTokens: Int = 1_024,
        timeout: TimeInterval? = nil,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) {
        self.id = id
        self.mode = mode
        self.messages = messages
        self.tools = tools
        self.attachments = attachments
        self.requestedMaxOutputTokens = max(1, requestedMaxOutputTokens)
        self.timeout = timeout
        self.metadata = metadata
    }
}

nonisolated struct AgentModelGatewayResponse: Sendable {
    let requestID: UUID
    let adapterID: String
    let descriptor: AgentKernelModelDescriptorV2
    let tier: AgentModelCapabilityTier
    let responseFormat: AgentKernelToolCallingModeV2
    let events: [AgentKernelModelAdapterEventV2]
    let diagnostics: AgentRunText?
}

nonisolated enum AgentModelGatewayResult: Sendable {
    case success(AgentModelGatewayResponse)
    case failure(AgentModelGatewayFailure)

    var failure: AgentModelGatewayFailure? {
        guard case .failure(let failure) = self else { return nil }
        return failure
    }

    var response: AgentModelGatewayResponse? {
        guard case .success(let response) = self else { return nil }
        return response
    }
}

actor AgentModelGateway {
    private var adapters: [String: any AgentKernelModelAdapterV2]
    private var conformanceProfiles: [String: AgentModelConformanceProfile]
    private let outputNormalizer = AgentKernelModelOutputNormalizerV2()

    init(
        adapters: [any AgentKernelModelAdapterV2] = [],
        conformanceProfiles: [AgentModelConformanceProfile] = []
    ) {
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.descriptor.id, $0) })
        self.conformanceProfiles = Dictionary(uniqueKeysWithValues: conformanceProfiles.map { ($0.target.adapterID, $0) })
    }

    func register(_ adapter: any AgentKernelModelAdapterV2) {
        adapters[adapter.descriptor.id] = adapter
    }

    func registerConformanceProfile(_ profile: AgentModelConformanceProfile) {
        conformanceProfiles[profile.target.adapterID] = profile
    }

    func adapterIDs() -> [String] {
        adapters.keys.sorted()
    }

    func tier(adapterID: String) -> AgentModelCapabilityTier? {
        guard let adapter = adapters[adapterID] else { return nil }
        return Self.tier(
            for: adapter.capabilities,
            conformanceProfile: conformanceProfile(for: adapter.capabilities.descriptor)
        )
    }

    func response(
        adapterID: String,
        request gatewayRequest: AgentModelGatewayRequest
    ) async -> AgentModelGatewayResult {
        if Task.isCancelled {
            return .failure(
                AgentModelGatewayFailure(
                    kind: .canceled,
                    adapterID: adapterID,
                    message: AgentRunText("Model request was canceled.")
                )
            )
        }

        guard let adapter = adapters[adapterID] else {
            return .failure(
                AgentModelGatewayFailure(
                    kind: .unavailable,
                    adapterID: adapterID,
                    message: AgentRunText("No registered model adapter has id \(adapterID).")
                )
            )
        }

        let capabilities = adapter.capabilities
        guard capabilities.isAvailable else {
            return .failure(
                AgentModelGatewayFailure(
                    kind: .unavailable,
                    adapterID: adapterID,
                    message: AgentRunText(capabilities.unavailableReason?.text ?? "Model adapter is unavailable.")
                )
            )
        }

        let tier = Self.tier(
            for: capabilities,
            conformanceProfile: conformanceProfile(for: capabilities.descriptor)
        )
        if let failure = validate(gatewayRequest, adapterID: adapterID, capabilities: capabilities, tier: tier) {
            return .failure(failure)
        }

        let adapterRequest = makeAdapterRequest(gatewayRequest, capabilities: capabilities, tier: tier)

        do {
            let rawAdapterResponse = try await execute(adapter: adapter, request: adapterRequest, timeout: gatewayRequest.timeout)
            let adapterResponse = outputNormalizer.normalize(response: rawAdapterResponse, tools: gatewayRequest.tools)
            try Task.checkCancellation()
            if let failure = validate(adapterResponse, gatewayRequest: gatewayRequest, adapterID: adapterID) {
                return .failure(failure)
            }
            return .success(
                AgentModelGatewayResponse(
                    requestID: gatewayRequest.id,
                    adapterID: adapterID,
                    descriptor: adapter.descriptor,
                    tier: tier,
                    responseFormat: adapterRequest.responseFormat,
                    events: adapterResponse.events,
                    diagnostics: adapterResponse.diagnostics.map { AgentRunText($0.text) }
                )
            )
        } catch is CancellationError {
            return .failure(
                AgentModelGatewayFailure(
                    kind: .canceled,
                    adapterID: adapterID,
                    message: AgentRunText("Model request was canceled.")
                )
            )
        } catch AgentModelGatewayFailureKind.timeout {
            return .failure(
                AgentModelGatewayFailure(
                    kind: .timeout,
                    adapterID: adapterID,
                    message: AgentRunText("Model request timed out.")
                )
            )
        } catch {
            return .failure(
                AgentModelGatewayFailure(
                    kind: .transportError,
                    adapterID: adapterID,
                    message: AgentRunText(String(describing: error))
                )
            )
        }
    }

    nonisolated static func tier(
        for capabilities: AgentKernelModelAdapterCapabilitiesV2,
        conformanceProfile: AgentModelConformanceProfile? = nil
    ) -> AgentModelCapabilityTier {
        if let conformanceProfile,
           conformanceProfile.target.matches(descriptor: capabilities.descriptor) {
            return conformanceProfile.derivedTier.gatewayTier
        }

        if capabilities.descriptor.providerKind == .mlxLocal,
           capabilities.descriptor.route == .local,
           capabilities.toolCallingMode == .textProtocol || capabilities.structuredOutputReliability == .bestEffort {
            return .tierCPlainChat
        }

        if capabilities.toolCallingMode == .native || capabilities.structuredOutputReliability == .strict {
            return .tierAFullAgent
        }
        if capabilities.toolCallingMode == .textProtocol || capabilities.structuredOutputReliability == .bestEffort {
            return .tierBConstrainedStructuredText
        }
        return .tierCPlainChat
    }

    private nonisolated func validate(
        _ request: AgentModelGatewayRequest,
        adapterID: String,
        capabilities: AgentKernelModelAdapterCapabilitiesV2,
        tier: AgentModelCapabilityTier
    ) -> AgentModelGatewayFailure? {
        let promptCharacters = request.messages.reduce(0) { $0 + $1.content.count }
        if promptCharacters > capabilities.limits.maxPromptCharacters {
            return AgentModelGatewayFailure(
                kind: .contextTooLarge,
                adapterID: adapterID,
                message: AgentRunText("Prompt has \(promptCharacters) characters; maximum is \(capabilities.limits.maxPromptCharacters)."),
                metadata: [
                    "promptCharacters": .int(promptCharacters),
                    "maxPromptCharacters": .int(capabilities.limits.maxPromptCharacters)
                ]
            )
        }

        switch request.mode {
        case .fullAgent:
            guard tier == .tierAFullAgent else {
                return unsupportedModeFailure(request: request, adapterID: adapterID, tier: tier)
            }
        case .constrainedStructuredText:
            guard tier == .tierAFullAgent || tier == .tierBConstrainedStructuredText else {
                return unsupportedModeFailure(request: request, adapterID: adapterID, tier: tier)
            }
        case .plainChat:
            break
        }

        if !request.tools.isEmpty && tier == .tierCPlainChat && request.mode != .plainChat {
            return unsupportedModeFailure(request: request, adapterID: adapterID, tier: tier)
        }

        return nil
    }

    private func conformanceProfile(
        for descriptor: AgentKernelModelDescriptorV2
    ) -> AgentModelConformanceProfile? {
        guard let profile = conformanceProfiles[descriptor.id],
              profile.target.matches(descriptor: descriptor) else {
            return nil
        }
        return profile
    }

    private nonisolated func validate(
        _ response: AgentKernelModelAdapterResponseV2,
        gatewayRequest: AgentModelGatewayRequest,
        adapterID: String
    ) -> AgentModelGatewayFailure? {
        guard !response.events.isEmpty else {
            return AgentModelGatewayFailure(
                kind: .emptyOutput,
                adapterID: adapterID,
                message: AgentRunText("Model adapter returned no events.")
            )
        }

        if response.events.contains(.timedOut) {
            return AgentModelGatewayFailure(
                kind: .timeout,
                adapterID: adapterID,
                message: AgentRunText("Model adapter reported a timeout.")
            )
        }

        if isSingleEmptyOutput(response.events) {
            return AgentModelGatewayFailure(
                kind: .emptyOutput,
                adapterID: adapterID,
                message: AgentRunText("Model adapter returned empty output.")
            )
        }

        if let malformed = firstMalformedOutput(in: response.events) {
            let kind: AgentModelGatewayFailureKind = gatewayRequest.mode == .plainChat
                ? .transportError
                : .structuredOutputInvalid
            return AgentModelGatewayFailure(
                kind: kind,
                adapterID: adapterID,
                message: malformedOutputMessage(kind: kind),
                metadata: ["rawOutput": .string(malformed)]
            )
        }

        for event in response.events {
            guard case .toolCall(let call) = event else { continue }
            if gatewayRequest.mode == .plainChat {
                return AgentModelGatewayFailure(
                    kind: .toolCallInvalid,
                    adapterID: adapterID,
                    message: AgentRunText("Plain chat mode cannot return tool calls.")
                )
            }
            guard let schema = gatewayRequest.tools.first(where: { $0.name == call.name }) else {
                return AgentModelGatewayFailure(
                    kind: .toolCallInvalid,
                    adapterID: adapterID,
                    message: AgentRunText("Model called unknown tool \(call.name).")
                )
            }
            let missing = schema.requiredArguments.filter { call.arguments[$0]?.isEmpty ?? true }
            if !missing.isEmpty {
                return AgentModelGatewayFailure(
                    kind: .toolCallInvalid,
                    adapterID: adapterID,
                    message: AgentRunText("Tool call \(call.name) is missing required arguments: \(missing.joined(separator: ", "))."),
                    metadata: ["toolName": .string(call.name)]
                )
            }
        }

        return nil
    }

    private nonisolated func makeAdapterRequest(
        _ request: AgentModelGatewayRequest,
        capabilities: AgentKernelModelAdapterCapabilitiesV2,
        tier: AgentModelCapabilityTier
    ) -> AgentKernelModelAdapterRequestV2 {
        let tools: [AgentKernelToolSchemaV2]
        let responseFormat: AgentKernelToolCallingModeV2

        switch request.mode {
        case .plainChat:
            tools = []
            responseFormat = .none
        case .fullAgent, .constrainedStructuredText:
            tools = request.tools
            if request.tools.isEmpty {
                responseFormat = .none
            } else if capabilities.toolCallingMode == .native {
                responseFormat = .native
            } else {
                responseFormat = .textProtocol
            }
        }

        return AgentKernelModelAdapterRequestV2(
            id: request.id,
            messages: request.messages,
            tools: tools,
            attachments: request.attachments,
            requestedMaxOutputTokens: min(request.requestedMaxOutputTokens, capabilities.limits.maxOutputTokens),
            responseFormat: responseFormat,
            metadata: request.metadata.reduce(into: [:]) { partial, item in
                partial[item.key] = kernelMetadataValue(from: item.value)
            }
        )
    }

    private nonisolated func execute(
        adapter: any AgentKernelModelAdapterV2,
        request: AgentKernelModelAdapterRequestV2,
        timeout: TimeInterval?
    ) async throws -> AgentKernelModelAdapterResponseV2 {
        guard let timeout, timeout > 0 else {
            return await adapter.response(for: request)
        }

        return try await withThrowingTaskGroup(of: AgentKernelModelAdapterResponseV2.self) { group in
            group.addTask {
                await adapter.response(for: request)
            }
            group.addTask {
                let nanoseconds = UInt64((timeout * 1_000_000_000).rounded(.up))
                try await Task.sleep(nanoseconds: nanoseconds)
                throw AgentModelGatewayFailureKind.timeout
            }
            guard let result = try await group.next() else {
                throw AgentModelGatewayFailureKind.timeout
            }
            group.cancelAll()
            return result
        }
    }

    private nonisolated func unsupportedModeFailure(
        request: AgentModelGatewayRequest,
        adapterID: String,
        tier: AgentModelCapabilityTier
    ) -> AgentModelGatewayFailure {
        AgentModelGatewayFailure(
            kind: .unsupportedToolMode,
            adapterID: adapterID,
            message: AgentRunText("Mode \(request.mode.rawValue) is not supported by \(tier.rawValue)."),
            metadata: [
                "mode": .string(request.mode.rawValue),
                "tier": .string(tier.rawValue)
            ]
        )
    }

    private nonisolated func isSingleEmptyOutput(_ events: [AgentKernelModelAdapterEventV2]) -> Bool {
        guard events.count == 1 else { return false }
        guard case .emptyOutput = events[0] else { return false }
        return true
    }

    private nonisolated func firstMalformedOutput(in events: [AgentKernelModelAdapterEventV2]) -> String? {
        for event in events {
            if case .malformedOutput(let text) = event {
                return text
            }
        }
        return nil
    }

    private nonisolated func malformedOutputMessage(kind: AgentModelGatewayFailureKind) -> AgentRunText {
        switch kind {
        case .structuredOutputInvalid:
            return AgentRunText("Model returned invalid structured output. Try again or switch to a provider with reliable tool/JSON support.")
        case .transportError:
            return AgentRunText("Model transport returned output that Pixel Pane could not use.")
        default:
            return AgentRunText("Model returned unusable output.")
        }
    }

    private nonisolated func kernelMetadataValue(from value: AgentRunMetadataValue) -> AgentKernelMetadataValueV2 {
        switch value {
        case .string(let value):
            .string(value)
        case .int(let value):
            .int(value)
        case .double(let value):
            .double(value)
        case .bool(let value):
            .bool(value)
        }
    }
}

extension AgentKernelModelAdapterCapabilitiesV2 {
    nonisolated func applyingAgentConformanceProfile(
        _ profile: AgentModelConformanceProfile?
    ) -> AgentKernelModelAdapterCapabilitiesV2 {
        guard descriptor.providerKind == .mlxLocal, descriptor.route == .local else {
            return self
        }

        let tier = AgentModelGateway.tier(for: self, conformanceProfile: profile)
        switch tier {
        case .tierAFullAgent, .tierBConstrainedStructuredText:
            return self
        case .tierCPlainChat:
            return AgentKernelModelAdapterCapabilitiesV2(
                descriptor: descriptor,
                inputModalities: inputModalities,
                outputModalities: outputModalities,
                toolCallingMode: .none,
                structuredOutputReliability: .unsupported,
                streamingMode: streamingMode,
                limits: limits,
                isAvailable: isAvailable,
                unavailableReason: unavailableReason
            )
        }
    }
}
