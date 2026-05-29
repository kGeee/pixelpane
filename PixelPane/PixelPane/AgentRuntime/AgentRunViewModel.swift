import Combine
import Foundation

nonisolated struct AgentRunViewContext: Codable, Equatable, Sendable {
    let title: String
    let contextID: String?
    let contextKind: String?

    init(title: String, contextID: String? = nil, contextKind: String? = nil) {
        self.title = title
        self.contextID = contextID
        self.contextKind = contextKind
    }
}

nonisolated struct AgentRunProjectedMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let runID: UUID
    let sequence: Int
    let role: AgentRunVisibleMessage.Role
    let text: AgentRunText
    let createdAt: Date

    init(_ message: AgentRunVisibleMessage) {
        id = message.id
        runID = message.runID
        sequence = message.sequence
        role = message.role
        text = message.text
        createdAt = message.createdAt
    }
}

nonisolated enum AgentRunProjectedApprovalKind: String, Codable, Equatable, Sendable {
    case fileWrite
    case command
    case processStart
    case processStop
    case approval
}

nonisolated struct AgentRunProjectedApproval: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { waitID }

    let waitID: UUID
    let runID: UUID
    let sideEffectID: UUID?
    let kind: AgentRunProjectedApprovalKind
    let title: String
    let prompt: String
    let primaryText: String
    let secondaryText: String?
    let risk: String?
    let approveTitle: String
    let denyTitle: String
    let createdAt: Date

    init(wait: AgentRunWaitRecord, sideEffect: AgentRunSideEffectRecord?) {
        waitID = wait.waitID
        runID = wait.runID
        sideEffectID = sideEffect?.sideEffectID
        risk = wait.risk
        prompt = wait.prompt.text
        createdAt = wait.createdAt

        switch sideEffect?.kind {
        case .fileWrite:
            kind = .fileWrite
            let operation = sideEffect?.metadata.projectedString("operation") ?? "write"
            let path = sideEffect?.metadata.projectedString("targetPath") ?? wait.prompt.text
            title = "\(operation.capitalized) file"
            primaryText = path
            secondaryText = wait.prompt.text
            approveTitle = "Confirm"
            denyTitle = "Cancel"
        case .command:
            kind = .command
            title = "Allow terminal"
            primaryText = sideEffect?.metadata.projectedString("command") ?? wait.prompt.text
            secondaryText = sideEffect?.metadata.projectedString("workingDirectory")
            approveTitle = "Allow"
            denyTitle = "Cancel"
        case .processStart:
            kind = .processStart
            title = "Start process"
            primaryText = sideEffect?.metadata.projectedString("command") ?? wait.prompt.text
            secondaryText = sideEffect?.metadata.projectedString("workingDirectory")
            approveTitle = "Start"
            denyTitle = "Cancel"
        case .processStop:
            kind = .processStop
            title = "Stop process"
            primaryText = sideEffect?.metadata.projectedString("processID") ?? wait.prompt.text
            secondaryText = nil
            approveTitle = "Stop"
            denyTitle = "Cancel"
        case .custom, .none:
            kind = .approval
            title = "Approval required"
            primaryText = wait.prompt.text
            secondaryText = nil
            approveTitle = "Approve"
            denyTitle = "Deny"
        }
    }
}

nonisolated struct AgentRunRecoveryProjection: Codable, Equatable, Sendable {
    let interruptedRunIDs: [UUID]
    let pendingWaitIDs: [UUID]

    init(result: AgentRunnerLaunchRecoveryResult) {
        interruptedRunIDs = result.interruptedRuns.map(\.runID)
        pendingWaitIDs = result.pendingWaits.map(\.waitID)
    }
}

nonisolated struct AgentRunViewState: Codable, Equatable, Sendable {
    let sessionID: UUID?
    let activeRunID: UUID?
    let activeStatus: AgentRunStatus?
    let latestProgress: AgentRunText?
    let messages: [AgentRunProjectedMessage]
    let pendingApprovals: [AgentRunProjectedApproval]
    let recentSessions: [AgentRunProjectedSession]
    let traceExport: String?
    let recovery: AgentRunRecoveryProjection?
    let updatedAt: Date?

    static let empty = AgentRunViewState(
        sessionID: nil,
        activeRunID: nil,
        activeStatus: nil,
        latestProgress: nil,
        messages: [],
        pendingApprovals: [],
        recentSessions: [],
        traceExport: nil,
        recovery: nil,
        updatedAt: nil
    )

    var isBusy: Bool {
        switch activeStatus {
        case .queued, .running:
            true
        case .draft, .waitingForApproval, .waitingForUserInput, .interrupted, .completed, .blocked, .failed, .canceled, .none:
            false
        }
    }

    var hasPendingApproval: Bool {
        !pendingApprovals.isEmpty || activeStatus == .waitingForApproval
    }

    var statusSummary: String {
        if let latestProgress, !latestProgress.text.isEmpty {
            return latestProgress.text
        }

        switch activeStatus {
        case .draft:
            return "Draft"
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .waitingForApproval:
            return "Waiting for approval"
        case .waitingForUserInput:
            return "Waiting for input"
        case .interrupted:
            return "Interrupted. Retry or cancel."
        case .completed:
            return "Completed"
        case .blocked:
            return "Blocked"
        case .failed:
            return "Failed"
        case .canceled:
            return "Canceled"
        case .none:
            return "Ready"
        }
    }
}

nonisolated enum AgentRunViewModelError: Error, Equatable, CustomStringConvertible {
    case activeRunInProgress(UUID)
    case missingActiveRun

    var description: String {
        switch self {
        case .activeRunInProgress(let runID):
            return "Agent run \(runID) is already active."
        case .missingActiveRun:
            return "No active agent run is loaded."
        }
    }
}

@MainActor
final class AgentRunViewModel: ObservableObject {
    @Published private(set) var state: AgentRunViewState

    private let store: AgentRunStore
    private let runner: AgentRunner
    private var sessionID: UUID?
    private var activeRunID: UUID?
    private var activeTask: Task<Void, Never>?

    init(store: AgentRunStore, runner: AgentRunner? = nil, initialState: AgentRunViewState = .empty) {
        self.store = store
        self.runner = runner ?? AgentRunner(store: store)
        self.state = initialState
        self.sessionID = initialState.sessionID
        self.activeRunID = initialState.activeRunID
    }

    static func makeDefault() -> AgentRunViewModel {
        do {
            let store = try AgentRunStore()
            return AgentRunViewModel(store: store)
        } catch {
            let fallbackRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("pixel-pane-agent-runs-\(UUID().uuidString)", isDirectory: true)
            let store = try! AgentRunStore(rootDirectory: fallbackRoot)
            return AgentRunViewModel(store: store)
        }
    }

    func loadOrCreateSession(context: AgentRunViewContext) async throws {
        if let existing = await store.sessions(contextID: context.contextID, contextKind: context.contextKind).first {
            sessionID = existing.id
            activeRunID = await store.latestRun(sessionID: existing.id)?.runID
            await refresh()
            return
        }

        let session = try await store.createSession(
            title: context.title,
            contextID: context.contextID,
            contextKind: context.contextKind
        )
        sessionID = session.id
        activeRunID = nil
        await refresh()
    }

    func loadSession(sessionID: UUID) async throws {
        _ = try await store.sessionRecord(sessionID: sessionID)
        self.sessionID = sessionID
        activeRunID = await store.latestRun(sessionID: sessionID)?.runID
        await refresh()
    }

    func startNewSession(context: AgentRunViewContext) async throws {
        activeTask?.cancel()
        activeTask = nil
        let session = try await store.createSession(
            title: context.title,
            contextID: context.contextID,
            contextKind: context.contextKind
        )
        sessionID = session.id
        activeRunID = nil
        await refresh()
    }

    func importLegacyConversation(
        context: AgentRunViewContext,
        turns: [AgentRunLegacyConversationTurn]
    ) async throws {
        guard !turns.isEmpty else { return }
        if let existing = await store.sessions(contextID: context.contextID, contextKind: context.contextKind).first {
            let messages = await store.visibleMessages(sessionID: existing.id)
            if !messages.isEmpty {
                return
            }
        }

        let session = try await store.createSession(
            title: context.title,
            contextID: context.contextID,
            contextKind: context.contextKind,
            createdAt: turns.first?.createdAt ?? Date()
        )
        let run = try await store.createRun(sessionID: session.id, status: .queued, createdAt: turns.first?.createdAt ?? Date())
        for turn in turns {
            let question = turn.question.trimmingCharacters(in: .whitespacesAndNewlines)
            if !question.isEmpty {
                try await store.appendEvent(
                    runID: run.runID,
                    kind: .userMessage,
                    payload: .text(AgentRunText(question)),
                    createdAt: turn.createdAt
                )
            }
            let answer = turn.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !answer.isEmpty {
                try await store.appendEvent(
                    runID: run.runID,
                    kind: .assistantMessage,
                    payload: .text(AgentRunText(answer)),
                    createdAt: turn.createdAt
                )
            }
            if !turn.backendLabel.isEmpty {
                try await store.appendEvent(
                    runID: run.runID,
                    kind: .providerDiagnostic,
                    payload: .metadata(["legacyBackend": .string(turn.backendLabel)]),
                    createdAt: turn.createdAt
                )
            }
        }
        _ = try await store.updateRunStatus(
            runID: run.runID,
            status: .completed,
            reason: AgentRunText("Imported from legacy chat history.")
        )
        await refresh()
    }

    @discardableResult
    func startRun(
        userMessage: String,
        context: AgentRunViewContext,
        adapter: any AgentKernelModelAdapterV2,
        mode: AgentModelGatewayMode = .plainChat,
        tools: [AgentKernelToolSchemaV2] = [],
        toolContext: AgentToolRunContext = .plainChat,
        attachments: [AgentKernelModelAttachmentV2] = [],
        systemPrompt: String? = nil,
        maxOutputTokens: Int = 1_024,
        timeout: TimeInterval? = 90
    ) async throws -> UUID {
        if let activeRunID = state.activeRunID, state.isBusy {
            throw AgentRunViewModelError.activeRunInProgress(activeRunID)
        }

        let session = try await ensureSession(context: context)
        let run = try await store.createRun(sessionID: session.id, status: .queued)
        sessionID = session.id
        activeRunID = run.runID

        try await store.appendEvent(
            runID: run.runID,
            kind: .userMessage,
            payload: .text(AgentRunText(userMessage))
        )

        let visibleMessages = await store.visibleMessages(sessionID: session.id)
        let request = AgentModelGatewayRequest(
            mode: mode,
            messages: Self.modelMessages(from: visibleMessages, systemPrompt: systemPrompt),
            tools: tools,
            attachments: attachments,
            requestedMaxOutputTokens: maxOutputTokens,
            timeout: timeout,
            metadata: [
                "sessionID": .string(session.id.uuidString),
                "runID": .string(run.runID.uuidString)
            ]
        )
        let adapterID = adapter.descriptor.id
        let gateway = AgentModelGateway(adapters: [adapter])
        let orchestrator = AgentToolOrchestrator(
            store: store,
            gateway: gateway,
            adapterID: adapterID
        )
        await refresh()

        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await orchestrator.run(
                    runID: run.runID,
                    request: request,
                    context: toolContext
                )
            } catch is CancellationError {
                _ = try? await self.store.updateRunStatus(
                    runID: run.runID,
                    status: .canceled,
                    reason: AgentRunText("Runner canceled.")
                )
            } catch {
                _ = try? await self.store.updateRunStatus(
                    runID: run.runID,
                    status: .failed,
                    reason: AgentRunText(String(describing: error))
                )
                _ = try? await self.store.appendEvent(
                    runID: run.runID,
                    kind: .failure,
                    payload: .diagnostic(AgentRunText(String(describing: error)))
                )
            }
            self.activeTask = nil
            await self.refresh()
        }

        return run.runID
    }

    func cancelRun() async {
        activeTask?.cancel()
        activeTask = nil

        guard let runID = state.activeRunID ?? activeRunID else {
            await refresh()
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
            reason: AgentRunText("User canceled the task.")
        )
        await refresh()
    }

    func approveWait(_ waitID: UUID) async throws {
        let wait = try await store.waitRecord(waitID: waitID)
        if let sideEffect = await store.sideEffects(runID: wait.runID).first(where: { $0.approvalWaitID == waitID }) {
            _ = try await store.updateSideEffect(sideEffectID: sideEffect.sideEffectID, status: .approved)
        }
        _ = try await store.resolveWait(
            waitID: waitID,
            status: .approved,
            summary: AgentRunText("Approved by user.")
        )
        sessionID = wait.sessionID
        activeRunID = wait.runID
        await refresh()
    }

    func approveWait(
        _ waitID: UUID,
        adapter: any AgentKernelModelAdapterV2,
        context: AgentRunViewContext,
        mode: AgentModelGatewayMode,
        tools: [AgentKernelToolSchemaV2],
        toolContext: AgentToolRunContext,
        attachments: [AgentKernelModelAttachmentV2] = [],
        systemPrompt: String? = nil,
        maxOutputTokens: Int = 1_024,
        timeout: TimeInterval? = 90
    ) async throws {
        let wait = try await store.waitRecord(waitID: waitID)
        sessionID = wait.sessionID
        activeRunID = wait.runID
        let request = AgentModelGatewayRequest(
            mode: mode,
            messages: Self.modelMessages(
                from: await store.visibleMessages(sessionID: wait.sessionID),
                systemPrompt: systemPrompt
            ),
            tools: tools,
            attachments: attachments,
            requestedMaxOutputTokens: maxOutputTokens,
            timeout: timeout,
            metadata: [
                "sessionID": .string(wait.sessionID.uuidString),
                "runID": .string(wait.runID.uuidString),
                "approvalWaitID": .string(waitID.uuidString)
            ]
        )
        let gateway = AgentModelGateway(adapters: [adapter])
        let orchestrator = AgentToolOrchestrator(
            store: store,
            gateway: gateway,
            adapterID: adapter.descriptor.id
        )
        try await orchestrator.continueAfterApproval(
            waitID: waitID,
            runID: wait.runID,
            request: request,
            context: toolContext,
            approved: true
        )
        await refresh()
    }

    func denyWait(_ waitID: UUID) async throws {
        let wait = try await store.waitRecord(waitID: waitID)
        if let sideEffect = await store.sideEffects(runID: wait.runID).first(where: { $0.approvalWaitID == waitID }) {
            _ = try await store.updateSideEffect(sideEffectID: sideEffect.sideEffectID, status: .denied)
        }
        _ = try await store.resolveWait(
            waitID: waitID,
            status: .denied,
            summary: AgentRunText("Denied by user.")
        )
        sessionID = wait.sessionID
        activeRunID = wait.runID
        await refresh()
    }

    func denyWait(
        _ waitID: UUID,
        adapter: any AgentKernelModelAdapterV2,
        context: AgentRunViewContext,
        mode: AgentModelGatewayMode,
        tools: [AgentKernelToolSchemaV2],
        toolContext: AgentToolRunContext,
        attachments: [AgentKernelModelAttachmentV2] = [],
        systemPrompt: String? = nil,
        maxOutputTokens: Int = 1_024,
        timeout: TimeInterval? = 90
    ) async throws {
        let wait = try await store.waitRecord(waitID: waitID)
        sessionID = wait.sessionID
        activeRunID = wait.runID
        let request = AgentModelGatewayRequest(
            mode: mode,
            messages: Self.modelMessages(
                from: await store.visibleMessages(sessionID: wait.sessionID),
                systemPrompt: systemPrompt
            ),
            tools: tools,
            attachments: attachments,
            requestedMaxOutputTokens: maxOutputTokens,
            timeout: timeout,
            metadata: [
                "sessionID": .string(wait.sessionID.uuidString),
                "runID": .string(wait.runID.uuidString),
                "approvalWaitID": .string(waitID.uuidString)
            ]
        )
        let gateway = AgentModelGateway(adapters: [adapter])
        let orchestrator = AgentToolOrchestrator(
            store: store,
            gateway: gateway,
            adapterID: adapter.descriptor.id
        )
        try await orchestrator.continueAfterApproval(
            waitID: waitID,
            runID: wait.runID,
            request: request,
            context: toolContext,
            approved: false
        )
        await refresh()
    }

    func retryInterruptedRun() async throws {
        guard let runID = state.activeRunID ?? activeRunID else {
            throw AgentRunViewModelError.missingActiveRun
        }
        try await store.updateRunStatus(
            runID: runID,
            status: .queued,
            reason: AgentRunText("Queued for retry by user.")
        )
        await refresh()
    }

    func clearHistory() async throws {
        activeTask?.cancel()
        activeTask = nil
        try await store.clearAll()
        sessionID = nil
        activeRunID = nil
        await refresh(recovery: nil)
    }

    @discardableResult
    func recoverOnLaunch() async throws -> AgentRunnerLaunchRecoveryResult {
        let result = try await runner.recoverOnLaunch()
        if sessionID == nil {
            if let run = result.interruptedRuns.first {
                sessionID = run.sessionID
                activeRunID = run.runID
            } else if let wait = result.pendingWaits.first {
                sessionID = wait.sessionID
                activeRunID = wait.runID
            }
        }
        await refresh(recovery: AgentRunRecoveryProjection(result: result))
        return result
    }

    func refresh() async {
        await refresh(recovery: state.recovery)
    }

    func waitForIdle(timeout: TimeInterval = 2.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while state.isBusy, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
            await refresh()
        }
    }

    private func ensureSession(context: AgentRunViewContext) async throws -> AgentRunSessionRecord {
        if let sessionID {
            return try await store.sessionRecord(sessionID: sessionID)
        }
        if let existing = await store.sessions(contextID: context.contextID, contextKind: context.contextKind).first {
            sessionID = existing.id
            return existing
        }
        let session = try await store.createSession(
            title: context.title,
            contextID: context.contextID,
            contextKind: context.contextKind
        )
        sessionID = session.id
        return session
    }

    private func refresh(recovery: AgentRunRecoveryProjection?) async {
        let session = await currentSession()
        let run = await currentRun(sessionID: session?.id)
        let rawMessages = await store.visibleMessages(sessionID: session?.id)
        let messages = rawMessages.map(AgentRunProjectedMessage.init)
        let recentSessions = await projectedRecentSessions()

        let latestProgress: AgentRunText?
        let pendingApprovals: [AgentRunProjectedApproval]
        let traceExport: String?
        if let run {
            latestProgress = await store.latestProgress(runID: run.runID)
            let sideEffects = await store.sideEffects(runID: run.runID)
            pendingApprovals = await store.pendingWaits(runID: run.runID).map { wait in
                AgentRunProjectedApproval(
                    wait: wait,
                    sideEffect: sideEffects.first { $0.approvalWaitID == wait.waitID }
                )
            }
            if let trace = try? await store.traceProjection(runID: run.runID) {
                traceExport = AgentRunTraceExporter().export(
                    trace: trace,
                    visibleMessages: rawMessages.filter { $0.runID == run.runID }
                )
            } else {
                traceExport = nil
            }
        } else {
            latestProgress = nil
            let sideEffects = await store.sideEffects()
            pendingApprovals = await store.pendingWaits().map { wait in
                AgentRunProjectedApproval(
                    wait: wait,
                    sideEffect: sideEffects.first { $0.approvalWaitID == wait.waitID }
                )
            }
            traceExport = nil
        }

        state = AgentRunViewState(
            sessionID: session?.id,
            activeRunID: run?.runID,
            activeStatus: run?.status,
            latestProgress: latestProgress,
            messages: messages,
            pendingApprovals: pendingApprovals,
            recentSessions: recentSessions,
            traceExport: traceExport,
            recovery: recovery,
            updatedAt: run?.updatedAt ?? session?.updatedAt
        )
    }

    private func currentSession() async -> AgentRunSessionRecord? {
        if let sessionID, let session = try? await store.sessionRecord(sessionID: sessionID) {
            return session
        }
        let session = await store.allSessions().first
        sessionID = session?.id
        return session
    }

    private func currentRun(sessionID: UUID?) async -> AgentRunRecord? {
        if let activeRunID, let run = try? await store.runRecord(runID: activeRunID) {
            return run
        }
        guard let sessionID else { return nil }
        let run = await store.latestRun(sessionID: sessionID)
        activeRunID = run?.runID
        return run
    }

    private func projectedRecentSessions(limit: Int = 8) async -> [AgentRunProjectedSession] {
        var projected: [AgentRunProjectedSession] = []
        let sessions = await store.allSessions()
        for session in sessions.prefix(limit) {
            let latestRun = await store.latestRun(sessionID: session.id)
            let messageCount = await store.visibleMessages(sessionID: session.id).count
            guard messageCount > 0 || latestRun != nil else { continue }
            projected.append(
                AgentRunProjectedSession(
                    id: session.id,
                    title: session.title,
                    contextID: session.contextID,
                    contextKind: session.contextKind,
                    updatedAt: session.updatedAt,
                    latestRunID: latestRun?.runID,
                    latestStatus: latestRun?.status,
                    messageCount: messageCount
                )
            )
        }
        return projected
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

    private nonisolated static func modelRunSteps(
        gateway: AgentModelGateway,
        adapterID: String,
        request: AgentModelGatewayRequest
    ) -> [AgentRunnerStep] {
        [
            AgentRunnerStep(kind: .route) {
                .progress(AgentRunText("Preparing model route."))
            },
            AgentRunnerStep(kind: .modelRequest, timeout: request.timeout) {
                let result = await gateway.response(adapterID: adapterID, request: request)
                switch result {
                case .success(let response):
                    if let finalAnswer = Self.finalAnswer(from: response.events) {
                        return .event(kind: .assistantMessage, payload: .text(AgentRunText(finalAnswer)))
                    }
                    return .terminal(
                        status: .failed,
                        reason: AgentRunText("Model response did not contain a final answer.")
                    )
                case .failure(let failure):
                    return .terminal(status: .failed, reason: failure.message)
                }
            }
        ]
    }

    private nonisolated static func finalAnswer(from events: [AgentKernelModelAdapterEventV2]) -> String? {
        for event in events.reversed() {
            switch event {
            case .finalAnswer(let text), .snapshot(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            case .toolCall, .malformedOutput, .emptyOutput, .timedOut:
                continue
            }
        }
        return nil
    }
}

private extension Dictionary where Key == String, Value == AgentRunMetadataValue {
    nonisolated func projectedString(_ key: String) -> String? {
        guard let value = self[key] else { return nil }
        switch value {
        case .string(let string):
            return string.isEmpty ? nil : string
        case .int(let int):
            return "\(int)"
        case .double(let double):
            return "\(double)"
        case .bool(let bool):
            return bool ? "true" : "false"
        }
    }
}
