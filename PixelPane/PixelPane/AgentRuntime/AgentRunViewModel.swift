import Combine
import Foundation

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

    init(interruptedRunIDs: [UUID], pendingWaitIDs: [UUID]) {
        self.interruptedRunIDs = interruptedRunIDs
        self.pendingWaitIDs = pendingWaitIDs
    }
}

nonisolated struct AgentRunViewState: Codable, Equatable, Sendable {
    let sessionID: UUID?
    let activeRunID: UUID?
    let activeStatus: AgentRunStatus?
    let latestProgress: AgentRunText?
    let terminalSummary: AgentRunText?
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
        terminalSummary: nil,
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
        if activeStatus?.isTerminal == true,
           let terminalSummary,
           !terminalSummary.text.isEmpty {
            return terminalSummary.text
        }

        if activeStatus?.isTerminal != true,
           let latestProgress,
           !latestProgress.text.isEmpty {
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

nonisolated enum AgentRunViewModelError: Error, CustomStringConvertible {
    case activeRunInProgress(UUID)
    case missingActiveRun
    case missingRunConfiguration(UUID)
    case adapterChanged(expected: AgentKernelModelDescriptor, actual: AgentKernelModelDescriptor)

    var description: String {
        switch self {
        case .activeRunInProgress(let runID):
            return "Agent run \(runID) is already active."
        case .missingActiveRun:
            return "No active agent run is loaded."
        case .missingRunConfiguration(let runID):
            return "Agent run \(runID) is missing its saved model and tool configuration."
        case .adapterChanged(let expected, let actual):
            return "Agent run was staged with \(expected.displayName), but the current adapter is \(actual.displayName)."
        }
    }
}

@MainActor
final class AgentRunViewModel: ObservableObject {
    private nonisolated static let projectionRefreshIntervalNanoseconds: UInt64 = 100_000_000

    @Published private(set) var state: AgentRunViewState

    private let store: AgentRunStore
    private let runtime: AgentRuntime
    private var sessionID: UUID?
    private var activeRunID: UUID?
    private var projectionRefreshTask: Task<Void, Never>?

    init(store: AgentRunStore, runtime: AgentRuntime? = nil, runner: AgentRunner? = nil, initialState: AgentRunViewState = .empty) {
        self.store = store
        self.runtime = runtime ?? AgentRuntime(store: store, runner: runner)
        self.state = initialState
        self.sessionID = initialState.sessionID
        self.activeRunID = initialState.activeRunID
    }

    deinit {
        projectionRefreshTask?.cancel()
    }

    static func makeDefault() -> AgentRunViewModel {
        do {
            let store = try AgentRunStore()
            return AgentRunViewModel(store: store)
        } catch {
            // The durable store exists but could not be read (schema drift or
            // disk damage). Quarantine the unreadable snapshot and reopen
            // fresh in the same durable location, so new history persists.
            // Silently degrading to a throwaway temp store loses every
            // subsequent chat; that stays a true last resort only.
            NSLog("AgentRunStore failed to open; attempting quarantine-recover: \(error)")
            if let recovered = try? AgentRunStore.quarantiningUnreadableStore() {
                return AgentRunViewModel(store: recovered)
            }
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
        await runtime.cancelRun(runID: state.activeRunID ?? activeRunID)
        let session = try await store.createSession(
            title: context.title,
            contextID: context.contextID,
            contextKind: context.contextKind
        )
        sessionID = session.id
        activeRunID = nil
        await refresh()
    }

    @discardableResult
    func startRun(
        userMessage: String,
        context: AgentRunViewContext,
        adapter: any AgentKernelModelAdapter,
        mode: AgentModelGatewayMode = .plainChat,
        tools: [AgentKernelToolSchema] = [],
        toolContext: AgentToolRunContext = .plainChat,
        modelConformanceProfile: AgentModelConformanceProfile? = nil,
        attachments: [AgentKernelModelAttachment] = [],
        systemPrompt: String? = nil,
        maxOutputTokens: Int = 1_024,
        timeout: TimeInterval? = 90
    ) async throws -> UUID {
        do {
            let result = try await runtime.startRun(
                AgentRuntimeStartRunRequest(
                    currentSessionID: sessionID,
                    userMessage: userMessage,
                    context: context,
                    adapter: adapter,
                    mode: mode,
                    tools: tools,
                    toolContext: toolContext,
                    modelConformanceProfile: modelConformanceProfile,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    maxOutputTokens: maxOutputTokens,
                    timeout: timeout
                )
            )
            sessionID = result.sessionID
            activeRunID = result.runID
            await self.refresh()
            startProjectionRefreshLoop(runID: result.runID)
            return result.runID
        } catch {
            throw Self.viewModelError(from: error)
        }
    }

    func cancelRun() async {
        stopProjectionRefreshLoop()
        await runtime.cancelRun(runID: state.activeRunID ?? activeRunID)
        await refresh()
    }

    func approveWait(_ waitID: UUID) async throws {
        let result = try await runtime.approveWaitWithoutContinuation(waitID)
        sessionID = result.sessionID
        activeRunID = result.runID
        await refresh()
    }

    func approveWait(
        _ waitID: UUID,
        adapter: any AgentKernelModelAdapter,
        modelConformanceProfile: AgentModelConformanceProfile? = nil
    ) async throws {
        try await approveWait(
            waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Assistant"),
            mode: .plainChat,
            tools: [],
            toolContext: .plainChat,
            modelConformanceProfile: modelConformanceProfile
        )
    }

    func approveWait(
        _ waitID: UUID,
        adapter: any AgentKernelModelAdapter,
        context: AgentRunViewContext,
        mode: AgentModelGatewayMode,
        tools: [AgentKernelToolSchema],
        toolContext: AgentToolRunContext,
        modelConformanceProfile: AgentModelConformanceProfile? = nil,
        attachments: [AgentKernelModelAttachment] = [],
        systemPrompt: String? = nil,
        maxOutputTokens: Int = 1_024,
        timeout: TimeInterval? = 90
    ) async throws {
        do {
            let request = AgentRuntimeApprovalRequest(
                waitID: waitID,
                adapter: adapter,
                context: context,
                mode: mode,
                tools: tools,
                toolContext: toolContext,
                modelConformanceProfile: modelConformanceProfile,
                attachments: attachments,
                systemPrompt: systemPrompt,
                maxOutputTokens: maxOutputTokens,
                timeout: timeout
            )
            let result = try await runtime.approveWait(
                request,
                didProjectDecision: { [weak self] result in
                    await self?.applyRuntimeResult(result)
                }
            )
            sessionID = result.sessionID
            activeRunID = result.runID
            await refresh()
        } catch {
            throw Self.viewModelError(from: error)
        }
    }

    func denyWait(_ waitID: UUID) async throws {
        let result = try await runtime.denyWaitWithoutContinuation(waitID)
        sessionID = result.sessionID
        activeRunID = result.runID
        await refresh()
    }

    func denyWait(
        _ waitID: UUID,
        adapter: any AgentKernelModelAdapter,
        modelConformanceProfile: AgentModelConformanceProfile? = nil
    ) async throws {
        try await denyWait(
            waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Assistant"),
            mode: .plainChat,
            tools: [],
            toolContext: .plainChat,
            modelConformanceProfile: modelConformanceProfile
        )
    }

    func denyWait(
        _ waitID: UUID,
        adapter: any AgentKernelModelAdapter,
        context: AgentRunViewContext,
        mode: AgentModelGatewayMode,
        tools: [AgentKernelToolSchema],
        toolContext: AgentToolRunContext,
        modelConformanceProfile: AgentModelConformanceProfile? = nil,
        attachments: [AgentKernelModelAttachment] = [],
        systemPrompt: String? = nil,
        maxOutputTokens: Int = 1_024,
        timeout: TimeInterval? = 90
    ) async throws {
        do {
            let request = AgentRuntimeApprovalRequest(
                waitID: waitID,
                adapter: adapter,
                context: context,
                mode: mode,
                tools: tools,
                toolContext: toolContext,
                modelConformanceProfile: modelConformanceProfile,
                attachments: attachments,
                systemPrompt: systemPrompt,
                maxOutputTokens: maxOutputTokens,
                timeout: timeout
            )
            let result = try await runtime.denyWait(
                request,
                didProjectDecision: { [weak self] result in
                    await self?.applyRuntimeResult(result)
                }
            )
            sessionID = result.sessionID
            activeRunID = result.runID
            await refresh()
        } catch {
            throw Self.viewModelError(from: error)
        }
    }

    private nonisolated static func viewModelError(from error: Error) -> Error {
        guard let runtimeError = error as? AgentRuntimeError else {
            return error
        }
        switch runtimeError {
        case .activeRunInProgress(let runID):
            return AgentRunViewModelError.activeRunInProgress(runID)
        case .missingActiveRun:
            return AgentRunViewModelError.missingActiveRun
        case .missingRunConfiguration(let runID):
            return AgentRunViewModelError.missingRunConfiguration(runID)
        case .adapterChanged(let expected, let actual):
            return AgentRunViewModelError.adapterChanged(
                expected: expected,
                actual: actual
            )
        }
    }

    private func applyRuntimeResult(_ result: AgentRuntimeRunResult) async {
        sessionID = result.sessionID
        activeRunID = result.runID
        await refresh()
    }

    private func startProjectionRefreshLoop(runID: UUID) {
        stopProjectionRefreshLoop()
        projectionRefreshTask = Task { [weak self] in
            await self?.refreshProjectionUntilSettled(runID: runID)
        }
    }

    private func stopProjectionRefreshLoop() {
        projectionRefreshTask?.cancel()
        projectionRefreshTask = nil
    }

    private func refreshProjectionUntilSettled(runID: UUID) async {
        while !Task.isCancelled {
            guard activeRunID == runID else { return }
            await refresh()

            let run = try? await store.runRecord(runID: runID)
            let runtimeActive = await runtime.isRunActive(runID)
            guard shouldContinueProjectionRefresh(status: run?.status, runtimeActive: runtimeActive) else {
                break
            }

            do {
                try await Task.sleep(nanoseconds: Self.projectionRefreshIntervalNanoseconds)
            } catch {
                return
            }
        }

        guard !Task.isCancelled, activeRunID == runID else { return }
        await refresh()
        projectionRefreshTask = nil
    }

    private nonisolated func shouldContinueProjectionRefresh(
        status: AgentRunStatus?,
        runtimeActive: Bool
    ) -> Bool {
        runtimeActive || status == .queued || status == .running
    }

#if DEBUG
    func debugTraceExportsForCurrentSession() async -> [String] {
        guard let currentSessionID = state.sessionID ?? sessionID else { return [] }
        let runs = await store.runs(sessionID: currentSessionID)
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    lhs.runID.uuidString < rhs.runID.uuidString
                } else {
                    lhs.createdAt < rhs.createdAt
                }
            }
        let visibleMessages = await store.visibleMessages(sessionID: currentSessionID)
        let exporter = AgentRunTraceExporter()

        var exports: [String] = []
        for run in runs {
            guard let trace = try? await store.traceProjection(runID: run.runID) else { continue }
            exports.append(
                exporter.export(
                    trace: trace,
                    visibleMessages: visibleMessages.filter { $0.runID == run.runID }
                )
            )
        }
        return exports
    }
#endif

    func retryInterruptedRun() async throws {
        do {
            let result = try await runtime.retryInterruptedRun(runID: state.activeRunID ?? activeRunID)
            sessionID = result.sessionID
            activeRunID = result.runID
            await refresh()
        } catch {
            throw Self.viewModelError(from: error)
        }
    }

    func clearHistory() async throws {
        try await runtime.clearAll()
        sessionID = nil
        activeRunID = nil
        await refresh(recovery: nil)
    }

    /// Saved-chat summaries for history UI (sessions with ≥1 user message).
    func sessionSummaries(limit: Int? = nil) async -> [AgentRunSessionSummary] {
        await store.sessionSummaries(limit: limit)
    }

    func deleteSession(sessionID: UUID) async throws {
        try await store.deleteSession(sessionID: sessionID)
        if self.sessionID == sessionID {
            self.sessionID = nil
            activeRunID = nil
        }
        await refresh(recovery: nil)
    }

    @discardableResult
    func recoverOnLaunch() async throws -> AgentRunnerLaunchRecoveryResult {
        let result = try await runtime.recoverOnLaunch()
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

    private func refresh(recovery: AgentRunRecoveryProjection?) async {
        let session = await currentSession()
        let run = await currentRun(sessionID: session?.id)
        let rawMessages: [AgentRunVisibleMessage]
        if let session {
            rawMessages = await store.visibleMessages(sessionID: session.id)
        } else {
            rawMessages = []
        }
        let messages = rawMessages.map(AgentRunProjectedMessage.init)

        let latestProgress: AgentRunText?
        let terminalSummary: AgentRunText?
        let pendingApprovals: [AgentRunProjectedApproval]
        let traceExport: String?
        if let run {
            latestProgress = await store.latestProgress(runID: run.runID)
            terminalSummary = await store.latestTerminalSummary(runID: run.runID)
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
            terminalSummary = nil
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
            terminalSummary: terminalSummary,
            messages: messages,
            pendingApprovals: pendingApprovals,
            recentSessions: [],
            traceExport: traceExport,
            recovery: await filteredRecovery(recovery),
            updatedAt: run?.updatedAt ?? session?.updatedAt
        )
    }

    private func filteredRecovery(_ recovery: AgentRunRecoveryProjection?) async -> AgentRunRecoveryProjection? {
        guard let recovery else { return nil }
        var interrupted: [UUID] = []
        for runID in recovery.interruptedRunIDs {
            guard let run = try? await store.runRecord(runID: runID),
                  run.status == .interrupted || !run.status.isTerminal else { continue }
            interrupted.append(runID)
        }
        var waits: [UUID] = []
        for waitID in recovery.pendingWaitIDs {
            guard let wait = try? await store.waitRecord(waitID: waitID),
                  wait.status == .pending else { continue }
            waits.append(waitID)
        }
        guard !interrupted.isEmpty || !waits.isEmpty else { return nil }
        return AgentRunRecoveryProjection(interruptedRunIDs: interrupted, pendingWaitIDs: waits)
    }

    private func currentSession() async -> AgentRunSessionRecord? {
        if let sessionID, let session = try? await store.sessionRecord(sessionID: sessionID) {
            return session
        }
        return nil
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
