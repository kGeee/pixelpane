import Foundation

nonisolated struct AgentRunViewContext: Codable, Equatable, Sendable {
    let title: String
    let contextID: String?
    let contextKind: String?
    let selectedAction: String?

    init(
        title: String,
        contextID: String? = nil,
        contextKind: String? = nil,
        selectedAction: String? = nil
    ) {
        self.title = title
        self.contextID = contextID
        self.contextKind = contextKind
        self.selectedAction = selectedAction
    }
}

nonisolated enum AgentRuntimeError: Error, CustomStringConvertible {
    case activeRunInProgress(UUID)
    case missingActiveRun
    case missingRunConfiguration(UUID)
    case adapterChanged(expected: AgentKernelModelDescriptorV2, actual: AgentKernelModelDescriptorV2)

    var description: String {
        switch self {
        case .activeRunInProgress(let runID):
            "Agent run \(runID) is already active."
        case .missingActiveRun:
            "No active agent run is loaded."
        case .missingRunConfiguration(let runID):
            "Agent run \(runID) is missing its saved model and tool configuration."
        case .adapterChanged(let expected, let actual):
            "Agent run was staged with \(expected.displayName), but the current adapter is \(actual.displayName)."
        }
    }
}

nonisolated struct AgentRuntimeStartRunRequest: Sendable {
    let currentSessionID: UUID?
    let userMessage: String
    let context: AgentRunViewContext
    let adapter: any AgentKernelModelAdapterV2
    let mode: AgentModelGatewayMode
    let tools: [AgentKernelToolSchemaV2]
    let toolContext: AgentToolRunContext
    let modelConformanceProfile: AgentModelConformanceProfile?
    let attachments: [AgentKernelModelAttachmentV2]
    let systemPrompt: String?
    let maxOutputTokens: Int
    let timeout: TimeInterval?

    init(
        currentSessionID: UUID?,
        userMessage: String,
        context: AgentRunViewContext,
        adapter: any AgentKernelModelAdapterV2,
        mode: AgentModelGatewayMode = .plainChat,
        tools: [AgentKernelToolSchemaV2] = [],
        toolContext: AgentToolRunContext = .plainChat,
        modelConformanceProfile: AgentModelConformanceProfile? = nil,
        attachments: [AgentKernelModelAttachmentV2] = [],
        systemPrompt: String? = nil,
        maxOutputTokens: Int = 1_024,
        timeout: TimeInterval? = 90
    ) {
        self.currentSessionID = currentSessionID
        self.userMessage = userMessage
        self.context = context
        self.adapter = adapter
        self.mode = mode
        self.tools = tools
        self.toolContext = toolContext
        self.modelConformanceProfile = modelConformanceProfile
        self.attachments = attachments
        self.systemPrompt = systemPrompt
        self.maxOutputTokens = maxOutputTokens
        self.timeout = timeout
    }
}

nonisolated struct AgentRuntimeApprovalRequest: Sendable {
    let waitID: UUID
    let adapter: any AgentKernelModelAdapterV2
    let context: AgentRunViewContext
    let mode: AgentModelGatewayMode
    let tools: [AgentKernelToolSchemaV2]
    let toolContext: AgentToolRunContext
    let modelConformanceProfile: AgentModelConformanceProfile?
    let attachments: [AgentKernelModelAttachmentV2]
    let systemPrompt: String?
    let maxOutputTokens: Int
    let timeout: TimeInterval?

    init(
        waitID: UUID,
        adapter: any AgentKernelModelAdapterV2,
        context: AgentRunViewContext,
        mode: AgentModelGatewayMode = .plainChat,
        tools: [AgentKernelToolSchemaV2] = [],
        toolContext: AgentToolRunContext = .plainChat,
        modelConformanceProfile: AgentModelConformanceProfile? = nil,
        attachments: [AgentKernelModelAttachmentV2] = [],
        systemPrompt: String? = nil,
        maxOutputTokens: Int = 1_024,
        timeout: TimeInterval? = 90
    ) {
        self.waitID = waitID
        self.adapter = adapter
        self.context = context
        self.mode = mode
        self.tools = tools
        self.toolContext = toolContext
        self.modelConformanceProfile = modelConformanceProfile
        self.attachments = attachments
        self.systemPrompt = systemPrompt
        self.maxOutputTokens = maxOutputTokens
        self.timeout = timeout
    }
}

nonisolated struct AgentRuntimeRunResult: Sendable {
    let sessionID: UUID
    let runID: UUID
}

actor AgentRuntime {
    private let store: AgentRunStore
    private let runner: AgentRunner
    private var activeRunIDs: Set<UUID> = []
    private var activeTasks: [UUID: Task<Void, Error>] = [:]

    init(store: AgentRunStore, runner: AgentRunner? = nil) {
        self.store = store
        self.runner = runner ?? AgentRunner(store: store)
    }

    @discardableResult
    func startRun(_ request: AgentRuntimeStartRunRequest) async throws -> AgentRuntimeRunResult {
        let session = try await ensureSession(currentSessionID: request.currentSessionID, context: request.context)
        if let busyRun = await busyRun(sessionID: session.id) {
            throw AgentRuntimeError.activeRunInProgress(busyRun.runID)
        }

        let run = try await store.createRun(sessionID: session.id, status: .queued)
        try await store.appendEvent(
            runID: run.runID,
            kind: .userMessage,
            payload: .text(AgentRunText(request.userMessage))
        )

        let visibleMessages = await store.visibleMessages(sessionID: session.id)
        let gatewayRequest = AgentModelGatewayRequest(
            mode: request.mode,
            messages: Self.modelMessages(from: visibleMessages, systemPrompt: request.systemPrompt),
            tools: request.tools,
            attachments: request.attachments,
            requestedMaxOutputTokens: request.maxOutputTokens,
            timeout: request.timeout,
            metadata: Self.requestMetadata(sessionID: session.id, runID: run.runID, context: request.context)
        )
        try await store.appendEvent(
            runID: run.runID,
            kind: .custom,
            payload: .runConfiguration(
                AgentRunModelConfigurationRecord(
                    adapterDescriptor: request.adapter.descriptor,
                    request: gatewayRequest,
                    toolContext: request.toolContext
                )
            )
        )

        activeRunIDs.insert(run.runID)
        let task = Task.detached { [
            store,
            runID = run.runID,
            adapter = request.adapter,
            gatewayRequest,
            toolContext = request.toolContext,
            modelConformanceProfile = request.modelConformanceProfile
        ] () throws -> Void in
            await Self.runOrchestratorTask(
                store: store,
                runID: runID,
                adapter: adapter,
                request: gatewayRequest,
                toolContext: toolContext,
                modelConformanceProfile: modelConformanceProfile
            )
            await self.finishActiveRun(runID: runID)
        }
        activeTasks[run.runID] = task

        return AgentRuntimeRunResult(sessionID: session.id, runID: run.runID)
    }

    func cancelRun(runID: UUID?) async {
        guard let runID else { return }
        activeTasks[runID]?.cancel()
        activeTasks[runID] = nil
        activeRunIDs.remove(runID)
        let currentStatus = (try? await store.runRecord(runID: runID))?.status
        if currentStatus?.isTerminal == true, currentStatus != .interrupted {
            return
        }

        for wait in await store.pendingWaits(runID: runID) {
            _ = try? await store.resolveWait(
                waitID: wait.waitID,
                status: .canceled,
                summary: AgentRunText("User canceled the pending approval.")
            )
        }
        _ = try? await store.updateRunStatus(
            runID: runID,
            status: .canceled,
            reason: AgentRunText("User canceled the task."),
            allowsTerminalTransition: currentStatus == .interrupted
        )
    }

    func approveWait(
        _ request: AgentRuntimeApprovalRequest,
        didProjectDecision: ((AgentRuntimeRunResult) async -> Void)? = nil
    ) async throws -> AgentRuntimeRunResult {
        try await continueAfterApproval(
            request,
            approved: true,
            didProjectDecision: didProjectDecision
        )
    }

    func denyWait(
        _ request: AgentRuntimeApprovalRequest,
        didProjectDecision: ((AgentRuntimeRunResult) async -> Void)? = nil
    ) async throws -> AgentRuntimeRunResult {
        try await continueAfterApproval(
            request,
            approved: false,
            didProjectDecision: didProjectDecision
        )
    }

    @discardableResult
    func approveWaitWithoutContinuation(_ waitID: UUID) async throws -> AgentRuntimeRunResult {
        let wait = try await store.waitRecord(waitID: waitID)
        if let sideEffect = await store.sideEffects(runID: wait.runID).first(where: { $0.approvalWaitID == waitID }) {
            _ = try await store.updateSideEffect(sideEffectID: sideEffect.sideEffectID, status: .approved)
        }
        _ = try await store.resolveWait(
            waitID: waitID,
            status: .approved,
            summary: AgentRunText("Approved by user.")
        )
        return AgentRuntimeRunResult(sessionID: wait.sessionID, runID: wait.runID)
    }

    @discardableResult
    func denyWaitWithoutContinuation(_ waitID: UUID) async throws -> AgentRuntimeRunResult {
        let wait = try await store.waitRecord(waitID: waitID)
        if let sideEffect = await store.sideEffects(runID: wait.runID).first(where: { $0.approvalWaitID == waitID }) {
            _ = try await store.updateSideEffect(sideEffectID: sideEffect.sideEffectID, status: .denied)
        }
        _ = try await store.resolveWait(
            waitID: waitID,
            status: .denied,
            summary: AgentRunText("Denied by user.")
        )
        return AgentRuntimeRunResult(sessionID: wait.sessionID, runID: wait.runID)
    }

    func retryInterruptedRun(runID: UUID?) async throws -> AgentRuntimeRunResult {
        guard let runID else {
            throw AgentRuntimeError.missingActiveRun
        }
        let run = try await store.runRecord(runID: runID)
        try await store.updateRunStatus(
            runID: runID,
            status: .queued,
            reason: AgentRunText("Queued for retry by user."),
            allowsTerminalTransition: true
        )
        return AgentRuntimeRunResult(sessionID: run.sessionID, runID: runID)
    }

    func clearAll() async throws {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        activeRunIDs.removeAll()
        try await store.clearAll()
    }

    @discardableResult
    func recoverOnLaunch() async throws -> AgentRunnerLaunchRecoveryResult {
        try await runner.recoverOnLaunch()
    }

    func isRunActive(_ runID: UUID) -> Bool {
        activeRunIDs.contains(runID)
    }

    private func continueAfterApproval(
        _ request: AgentRuntimeApprovalRequest,
        approved: Bool,
        didProjectDecision: ((AgentRuntimeRunResult) async -> Void)? = nil
    ) async throws -> AgentRuntimeRunResult {
        let wait = try await store.waitRecord(waitID: request.waitID)
        if activeRunIDs.contains(wait.runID) {
            throw AgentRuntimeError.activeRunInProgress(wait.runID)
        }
        activeRunIDs.insert(wait.runID)
        defer {
            activeRunIDs.remove(wait.runID)
            activeTasks[wait.runID] = nil
        }

        let configuration = try await continuationConfiguration(
            for: wait,
            adapter: request.adapter,
            fallback: await fallbackConfiguration(for: wait, request: request)
        )
        let result = AgentRuntimeRunResult(sessionID: wait.sessionID, runID: wait.runID)
        try await projectApprovalDecision(
            wait,
            decision: approved ? .approved : .denied,
            immediateStatus: approved ? .running : .blocked,
            progress: approved
                ? AgentRunText("Approved. Running approved action.")
                : AgentRunText("Denied. The proposed action will not run.")
        )
        await didProjectDecision?(result)
        let task = Task.detached { [
            store,
            adapter = request.adapter,
            modelConformanceProfile = request.modelConformanceProfile,
            waitID = request.waitID,
            runID = wait.runID,
            continuationRequest = Self.request(configuration.request, approvalWaitID: request.waitID),
            toolContext = configuration.toolContext
        ] () throws -> Void in
            try await Self.runApprovalContinuation(
                store: store,
                adapter: adapter,
                modelConformanceProfile: modelConformanceProfile,
                waitID: waitID,
                runID: runID,
                request: continuationRequest,
                toolContext: toolContext,
                approved: approved
            )
        }
        activeTasks[wait.runID] = task
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        return result
    }

    private nonisolated static func runApprovalContinuation(
        store: AgentRunStore,
        adapter: any AgentKernelModelAdapterV2,
        modelConformanceProfile: AgentModelConformanceProfile?,
        waitID: UUID,
        runID: UUID,
        request: AgentModelGatewayRequest,
        toolContext: AgentToolRunContext,
        approved: Bool
    ) async throws {
        let gateway = AgentModelGateway(
            adapters: [adapter],
            conformanceProfiles: modelConformanceProfile.map { [$0] } ?? []
        )
        let orchestrator = AgentToolOrchestrator(
            store: store,
            gateway: gateway,
            adapterID: adapter.descriptor.id
        )
        try await orchestrator.continueAfterApproval(
            waitID: waitID,
            runID: runID,
            request: request,
            context: toolContext,
            approved: approved
        )
    }

    private nonisolated static func runOrchestratorTask(
        store: AgentRunStore,
        runID: UUID,
        adapter: any AgentKernelModelAdapterV2,
        request: AgentModelGatewayRequest,
        toolContext: AgentToolRunContext,
        modelConformanceProfile: AgentModelConformanceProfile?
    ) async {
        do {
            let gateway = AgentModelGateway(
                adapters: [adapter],
                conformanceProfiles: modelConformanceProfile.map { [$0] } ?? []
            )
            let orchestrator = AgentToolOrchestrator(
                store: store,
                gateway: gateway,
                adapterID: adapter.descriptor.id
            )
            try await orchestrator.run(
                runID: runID,
                request: request,
                context: toolContext
            )
        } catch is CancellationError {
            _ = try? await store.updateRunStatus(
                runID: runID,
                status: .canceled,
                reason: AgentRunText("Runner canceled.")
            )
        } catch {
            if let current = try? await store.runRecord(runID: runID),
               !current.status.isTerminal {
                _ = try? await store.updateRunStatus(
                    runID: runID,
                    status: .failed,
                    reason: AgentRunText(String(describing: error))
                )
                _ = try? await store.appendEvent(
                    runID: runID,
                    kind: .failure,
                    payload: .diagnostic(AgentRunText(String(describing: error)))
                )
            }
        }
    }

    private func finishActiveRun(runID: UUID) {
        activeTasks[runID] = nil
        activeRunIDs.remove(runID)
    }

    private func ensureSession(
        currentSessionID: UUID?,
        context: AgentRunViewContext
    ) async throws -> AgentRunSessionRecord {
        if let currentSessionID {
            return try await store.sessionRecord(sessionID: currentSessionID)
        }
        if let existing = await store.sessions(contextID: context.contextID, contextKind: context.contextKind).first {
            return existing
        }
        return try await store.createSession(
            title: context.title,
            contextID: context.contextID,
            contextKind: context.contextKind
        )
    }

    private func busyRun(sessionID: UUID) async -> AgentRunRecord? {
        for run in await store.runs(sessionID: sessionID) {
            if activeRunIDs.contains(run.runID) || run.status == .queued || run.status == .running {
                return run
            }
        }
        return nil
    }

    private func projectApprovalDecision(
        _ wait: AgentRunWaitRecord,
        decision: AgentSideEffectApprovalDecision,
        immediateStatus: AgentRunStatus,
        progress: AgentRunText
    ) async throws {
        if let sideEffect = await store.sideEffects(runID: wait.runID).first(where: { $0.approvalWaitID == wait.waitID }) {
            _ = try await AgentSideEffectController(store: store).resolveApproval(
                sideEffectID: sideEffect.sideEffectID,
                decision: decision,
                summary: progress
            )
        } else {
            _ = try await store.resolveWait(
                waitID: wait.waitID,
                status: decision == .approved ? .approved : .denied,
                summary: progress
            )
        }
        try await store.updateRunStatus(
            runID: wait.runID,
            status: immediateStatus,
            reason: progress
        )
        try await store.appendEvent(
            runID: wait.runID,
            kind: .progress,
            payload: .progress(progress)
        )
    }

    private func continuationConfiguration(
        for wait: AgentRunWaitRecord,
        adapter: any AgentKernelModelAdapterV2,
        fallback: AgentRunModelConfigurationRecord
    ) async throws -> AgentRunModelConfigurationRecord {
        let configuration = (try? await store.traceProjection(runID: wait.runID).events.reversed().compactMap { event -> AgentRunModelConfigurationRecord? in
            guard case .runConfiguration(let configuration) = event.payload else { return nil }
            return configuration
        }.first) ?? fallback

        guard configuration.adapterDescriptor == adapter.descriptor else {
            throw AgentRuntimeError.adapterChanged(
                expected: configuration.adapterDescriptor,
                actual: adapter.descriptor
            )
        }

        return configuration
    }

    private func fallbackConfiguration(
        for wait: AgentRunWaitRecord,
        request: AgentRuntimeApprovalRequest
    ) async -> AgentRunModelConfigurationRecord {
        AgentRunModelConfigurationRecord(
            adapterDescriptor: request.adapter.descriptor,
            request: AgentModelGatewayRequest(
                mode: request.mode,
                messages: Self.modelMessages(
                    from: await store.visibleMessages(sessionID: wait.sessionID),
                    systemPrompt: request.systemPrompt
                ),
                tools: request.tools,
                attachments: request.attachments,
                requestedMaxOutputTokens: request.maxOutputTokens,
                timeout: request.timeout,
                metadata: Self.requestMetadata(
                    sessionID: wait.sessionID,
                    runID: wait.runID,
                    context: request.context,
                    approvalWaitID: request.waitID
                )
            ),
            toolContext: request.toolContext
        )
    }

    private nonisolated static func request(
        _ baseRequest: AgentModelGatewayRequest,
        approvalWaitID: UUID
    ) -> AgentModelGatewayRequest {
        var metadata = baseRequest.metadata
        metadata["approvalWaitID"] = .string(approvalWaitID.uuidString)
        return AgentModelGatewayRequest(
            id: baseRequest.id,
            mode: baseRequest.mode,
            messages: baseRequest.messages,
            tools: baseRequest.tools,
            attachments: baseRequest.attachments,
            requestedMaxOutputTokens: baseRequest.requestedMaxOutputTokens,
            timeout: baseRequest.timeout,
            metadata: metadata
        )
    }

    private nonisolated static func requestMetadata(
        sessionID: UUID,
        runID: UUID,
        context: AgentRunViewContext,
        approvalWaitID: UUID? = nil
    ) -> [String: AgentRunMetadataValue] {
        var metadata: [String: AgentRunMetadataValue] = [
            "sessionID": .string(sessionID.uuidString),
            "runID": .string(runID.uuidString),
            "contextTitle": .string(context.title)
        ]
        if let contextID = context.contextID {
            metadata["contextID"] = .string(contextID)
        }
        if let contextKind = context.contextKind {
            metadata["contextKind"] = .string(contextKind)
        }
        if let selectedAction = context.selectedAction {
            metadata["selectedAction"] = .string(selectedAction)
        }
        if let approvalWaitID {
            metadata["approvalWaitID"] = .string(approvalWaitID.uuidString)
        }
        return metadata
    }

    private nonisolated static func modelMessages(
        from visibleMessages: [AgentRunVisibleMessage],
        systemPrompt: String?
    ) -> [AgentKernelMessageV2] {
        var messages: [AgentKernelMessageV2] = []
        if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(AgentKernelMessageV2(role: .system, content: systemPrompt))
        }
        messages.append(
            contentsOf: visibleMessages.map { message in
                AgentKernelMessageV2(
                    id: message.id,
                    role: message.role == .user ? .user : .assistant,
                    content: message.text.text
                )
            }
        )
        return messages
    }
}
