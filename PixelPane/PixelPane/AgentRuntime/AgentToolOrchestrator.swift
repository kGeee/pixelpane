import Foundation

nonisolated enum AgentToolOrchestratorError: Error, Equatable, CustomStringConvertible {
    case noFinalAnswer
    case maxIterationsExceeded(Int)
    case missingApprovedSideEffect(UUID)

    var description: String {
        switch self {
        case .noFinalAnswer:
            "The model response did not contain a final answer or tool call."
        case .maxIterationsExceeded(let limit):
            "The agent exceeded the maximum tool iteration count of \(limit)."
        case .missingApprovedSideEffect(let waitID):
            "No side effect was found for approval wait \(waitID)."
        }
    }
}

actor AgentToolOrchestrator {
    private let store: AgentRunStore
    private let gateway: AgentModelGateway
    private let adapterID: String
    private let executor: AgentLocalToolExecutor
    private let maxIterations: Int
    private let maxRequiredSideEffectFinalAnswerRepairs = 1
    private let maxPreflightObservationCharacters = 5_500
    private let maxPreflightToolObservationCharacters = 1_000

    init(
        store: AgentRunStore,
        gateway: AgentModelGateway,
        adapterID: String,
        executor: AgentLocalToolExecutor? = nil,
        maxIterations: Int = 12
    ) {
        self.store = store
        self.gateway = gateway
        self.adapterID = adapterID
        self.executor = executor ?? AgentLocalToolExecutor(store: store)
        self.maxIterations = max(1, maxIterations)
    }

    func run(
        runID: UUID,
        request baseRequest: AgentModelGatewayRequest,
        context: AgentToolRunContext,
        startedAt: Date = Date()
    ) async throws {
        try await store.updateRunStatus(
            runID: runID,
            status: .running,
            reason: AgentRunText("Tool-capable runner started."),
            createdAt: startedAt
        )

        let tier = await gateway.tier(adapterID: adapterID) ?? .tierCPlainChat
        let pendingWaits = await store.pendingWaits(runID: runID)
        let completedSideEffects = await store.sideEffects(runID: runID).filter { $0.status == .completed }
        let profile = AgentRunTaskProfile.classify(
            userMessage: AgentRunTaskProfile.latestUserMessage(from: baseRequest.messages),
            tools: baseRequest.tools,
            context: context,
            providerTier: tier,
            attachments: baseRequest.attachments,
            selectedAction: baseRequest.metadata["selectedAction"]?.stringValue,
            contextID: baseRequest.metadata["contextID"]?.stringValue,
            contextKind: baseRequest.metadata["contextKind"]?.stringValue,
            supportedOperations: context.supportedOperations,
            pendingWaits: pendingWaits,
            completedSideEffects: completedSideEffects
        )
        if !profile.taskFrame.diagnostics.isEmpty {
            try await store.appendEvent(
                runID: runID,
                kind: .providerDiagnostic,
                payload: .diagnostic(
                    AgentRunText(
                        "Task frame diagnostics: \(profile.taskFrame.diagnostics.joined(separator: "; "))",
                        characterLimit: 2_000
                    )
                )
            )
        }
        var messages = baseRequest.messages
        var observedToolResults = 0
        var observedSideEffectToolResults = 0
        var observedRequiredSideEffectToolNames = Set<String>()
        var toolCallHistory: [String: Int] = [:]
        var finalAnswerRejectionCounts: [FinalAnswerRejectionKind: Int] = [:]
        let shouldRunPreflight = baseRequest.metadata["skipPreflight"]?.boolValue != true
        if shouldRunPreflight,
           let preflight = try await preflightObservation(
            runID: runID,
            baseRequest: baseRequest,
            providerTier: tier,
            context: context,
            profile: profile,
            startedAt: startedAt
        ) {
            try await recordControlMessage(
                preflight,
                runID: runID,
                kind: .preflightObservation
            )
            messages.append(preflight)
            observedToolResults += 1
        }
        let pendingPreflightWaits = await store.pendingWaits(runID: runID)
        if !pendingPreflightWaits.isEmpty {
            return
        }

        for iteration in 1...maxIterations {
            try Task.checkCancellation()
            let response = try await modelResponse(
                runID: runID,
                baseRequest: baseRequest,
                messages: messages,
                iteration: iteration,
                profile: profile
            )
            try Task.checkCancellation()

            if let finalAnswer = Self.finalAnswer(from: response.events) {
                let answerDecision = await finalAnswerDecision(
                    finalAnswer,
                    runID: runID,
                    profile: profile,
                    observedToolResults: observedToolResults,
                    observedSideEffectToolResults: observedSideEffectToolResults,
                    observedRequiredSideEffectToolNames: observedRequiredSideEffectToolNames,
                    requiresGroundingWhenUnevidenced: requiresTextProtocolGrounding(
                        baseRequest: baseRequest,
                        response: response
                    )
                )
                switch answerDecision {
                case .accept:
                    try await acceptFinalAnswer(finalAnswer, runID: runID, profile: profile)
                    return
                case .retry(let rejection):
                    try await store.appendEvent(
                        runID: runID,
                        kind: .providerDiagnostic,
                        payload: .diagnostic(rejection.reason)
                    )
                    let priorRejections = finalAnswerRejectionCounts[rejection.kind, default: 0]
                    finalAnswerRejectionCounts[rejection.kind] = priorRejections + 1
                    if await shouldBlockAfterFinalAnswerRejection(
                        rejection,
                        runID: runID,
                        profile: profile,
                        priorRejections: priorRejections,
                        observedRequiredSideEffectToolNames: observedRequiredSideEffectToolNames
                    ) {
                        let blockReason: AgentRunText
                        if isRequiredSideEffectRejection(rejection.kind) {
                            blockReason = await requiredSideEffectContractBlockReason(
                                runID: runID,
                                profile: profile,
                                observedRequiredSideEffectToolNames: observedRequiredSideEffectToolNames
                            )
                        } else {
                            blockReason = rejection.reason
                        }
                        try await failRun(
                            runID: runID,
                            reason: blockReason,
                            status: .blocked
                        )
                        return
                    }
                    let repairObservation = AgentKernelMessageV2(
                        role: .observation,
                        content: """
                        Runtime rejected the previous final answer.
                        Reason: \(rejection.reason.text)
                        If the answer depends on a local_evidence claim kind, call an available tool. Otherwise return a final answer grounded as general_knowledge or capability_limitation.
                        """
                    )
                    try await recordControlMessage(
                        repairObservation,
                        runID: runID,
                        kind: .finalAnswerRepairObservation,
                        metadata: [
                            "iteration": .int(iteration),
                            "rejectionKind": .string(String(describing: rejection.kind))
                        ]
                    )
                    messages.append(repairObservation)
                    continue
                }
            }

            guard let toolCall = Self.firstToolCall(from: response.events) else {
                try await failRun(runID: runID, reason: AgentRunText(AgentToolOrchestratorError.noFinalAnswer.description))
                return
            }
            let result = try await executeToolCall(
                toolCall,
                runID: runID,
                providerTier: tier,
                context: context,
                iteration: iteration
            )

            if result.status == .waitingForApproval {
                return
            }
            observedToolResults += 1
            if Self.isSideEffectTool(toolCall.name) {
                observedSideEffectToolResults += 1
            }
            if profile.requiredSideEffectToolNames.contains(toolCall.name) {
                observedRequiredSideEffectToolNames.insert(toolCall.name)
            }

            if let stagedWrite = try await autoStageCommandOutputWriteIfNeeded(
                after: result,
                runID: runID,
                providerTier: tier,
                context: context,
                profile: profile,
                observedRequiredSideEffectToolNames: observedRequiredSideEffectToolNames,
                iteration: iteration
            ) {
                if stagedWrite.status == .waitingForApproval {
                    return
                }
                observedToolResults += 1
                observedSideEffectToolResults += 1
                observedRequiredSideEffectToolNames.insert("stage_write_proposal")
                let stagedWriteObservation = AgentKernelMessageV2(role: .observation, content: stagedWrite.modelObservationText)
                try await recordControlMessage(
                    stagedWriteObservation,
                    runID: runID,
                    kind: .toolObservation,
                    metadata: [
                        "iteration": .int(iteration),
                        "toolName": .string(stagedWrite.toolName),
                        "source": .string("auto_stage_command_output_write")
                    ]
                )
                messages.append(stagedWriteObservation)
                continue
            }

            let signature = Self.toolCallSignature(toolCall)
            let priorCount = toolCallHistory[signature, default: 0]
            toolCallHistory[signature] = priorCount + 1
            let repeatedFailingCall = result.status == .failed && priorCount >= 1

            // No-progress guard: the same tool call keeps failing. Stop looping and try a
            // best-effort answer instead of silently burning the whole budget (RELY-004 / RC-4).
            if repeatedFailingCall && priorCount >= 2 {
                if try await attemptBestEffortFinalAnswer(
                    runID: runID,
                    baseRequest: baseRequest,
                    messages: messages,
                    profile: profile,
                    observedToolResults: observedToolResults,
                    observedSideEffectToolResults: observedSideEffectToolResults,
                    observedRequiredSideEffectToolNames: observedRequiredSideEffectToolNames
                ) {
                    return
                }
                try await failRun(
                    runID: runID,
                    reason: AgentRunText("The agent repeated the same failing action without making progress. \(result.summary.text)"),
                    status: .blocked
                )
                return
            }

            let observationText = repeatedFailingCall
                ? """
                You already called \(toolCall.name) with the same arguments and it failed: \(result.summary.text)
                Do not repeat that exact call. Call list_grants to see valid writable targets, choose different arguments or a different tool, or produce your best final answer now.
                """
                : result.modelObservationText
            let observation = AgentKernelMessageV2(
                role: .observation,
                content: observationText
            )
            try await recordControlMessage(
                observation,
                runID: runID,
                kind: .toolObservation,
                metadata: [
                    "iteration": .int(iteration),
                    "toolName": .string(result.toolName),
                    "repeatedFailingCall": .bool(repeatedFailingCall)
                ]
            )
            messages.append(observation)
        }

        if await shouldBlockForMissingRequiredSideEffect(
            runID: runID,
            profile: profile,
            observedRequiredSideEffectToolNames: observedRequiredSideEffectToolNames
        ) {
            try await failRun(
                runID: runID,
                reason: await requiredSideEffectContractBlockReason(
                    runID: runID,
                    profile: profile,
                    observedRequiredSideEffectToolNames: observedRequiredSideEffectToolNames
                ),
                status: .blocked
            )
            return
        }

        if try await attemptBestEffortFinalAnswer(
            runID: runID,
            baseRequest: baseRequest,
            messages: messages,
            profile: profile,
            observedToolResults: observedToolResults,
            observedSideEffectToolResults: observedSideEffectToolResults,
            observedRequiredSideEffectToolNames: observedRequiredSideEffectToolNames
        ) {
            return
        }
        try await failRun(
            runID: runID,
            reason: AgentRunText(AgentToolOrchestratorError.maxIterationsExceeded(maxIterations).description),
            status: .blocked
        )
    }

    private nonisolated static func toolCallSignature(_ call: AgentKernelToolCallV2) -> String {
        let argumentKey = call.arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(call.name):\(argumentKey)"
    }

    private func recordControlMessage(
        _ message: AgentKernelMessageV2,
        runID: UUID,
        stepID: UUID? = nil,
        kind: AgentRunControlRecordKind,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) async throws {
        try await store.recordControl(
            runID: runID,
            stepID: stepID,
            kind: kind,
            payload: .modelMessage(message),
            metadata: metadata
        )
    }

    private func recordModelRequest(
        _ request: AgentModelGatewayRequest,
        runID: UUID,
        stepID: UUID? = nil,
        iteration: Int,
        phase: String
    ) async throws {
        try await store.recordControl(
            runID: runID,
            stepID: stepID,
            kind: .modelRequest,
            payload: .modelRequest(request),
            metadata: [
                "iteration": .int(iteration),
                "phase": .string(phase),
                "requestID": .string(request.id.uuidString)
            ]
        )
    }

    private func recordModelResponse(
        _ response: AgentModelGatewayResponse,
        runID: UUID,
        stepID: UUID? = nil,
        iteration: Int,
        phase: String
    ) async throws {
        try await store.recordControl(
            runID: runID,
            stepID: stepID,
            kind: .modelResponse,
            payload: .modelResponse(AgentRunModelResponseRecord(response: response)),
            metadata: [
                "iteration": .int(iteration),
                "phase": .string(phase),
                "requestID": .string(response.requestID.uuidString)
            ]
        )
    }

    private func recordModelFailure(
        _ failure: AgentModelGatewayFailure,
        runID: UUID,
        stepID: UUID? = nil,
        iteration: Int,
        phase: String,
        requestID: UUID? = nil
    ) async throws {
        var metadata: [String: AgentRunMetadataValue] = [
            "iteration": .int(iteration),
            "phase": .string(phase),
            "failureKind": .string(failure.kind.rawValue)
        ]
        if let requestID {
            metadata["requestID"] = .string(requestID.uuidString)
        }
        try await store.recordControl(
            runID: runID,
            stepID: stepID,
            kind: .modelFailure,
            payload: .modelFailure(failure),
            metadata: metadata
        )
    }

    private func recordToolCall(
        _ call: AgentKernelToolCallV2,
        runID: UUID,
        stepID: UUID? = nil,
        iteration: Int,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) async throws {
        var recordMetadata = metadata
        recordMetadata["iteration"] = .int(iteration)
        recordMetadata["toolName"] = .string(call.name)
        try await store.recordControl(
            runID: runID,
            stepID: stepID,
            kind: .toolCall,
            payload: .toolCall(call),
            metadata: recordMetadata
        )
    }

    private func recordToolResult(
        _ result: AgentToolExecutionResult,
        runID: UUID,
        stepID: UUID? = nil,
        iteration: Int,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) async throws {
        var recordMetadata = metadata
        recordMetadata["iteration"] = .int(iteration)
        recordMetadata["toolName"] = .string(result.toolName)
        try await store.recordControl(
            runID: runID,
            stepID: stepID,
            kind: .toolResult,
            payload: .toolResult(Self.controlToolResult(from: result)),
            metadata: recordMetadata
        )
    }

    private nonisolated static func controlToolResult(from result: AgentToolExecutionResult) -> AgentRunToolResultRecord {
        AgentRunToolResultRecord(
            status: result.status.rawValue,
            toolName: result.toolName,
            summary: result.summary,
            observation: result.observation,
            evidenceIDs: result.evidenceIDs,
            artifactIDs: result.artifactIDs,
            waitID: result.waitID,
            sideEffectID: result.sideEffectID
        )
    }

    private nonisolated static func isSideEffectTool(_ name: String) -> Bool {
        name == "stage_write_proposal" || name == "run_finite_command"
    }

    private func autoStageCommandOutputWriteIfNeeded(
        after result: AgentToolExecutionResult,
        runID: UUID,
        providerTier: AgentModelCapabilityTier,
        context: AgentToolRunContext,
        profile: AgentRunTaskProfile,
        observedRequiredSideEffectToolNames: Set<String>,
        iteration: Int
    ) async throws -> AgentToolExecutionResult? {
        guard result.toolName == "run_finite_command",
              result.status == .succeeded,
              profile.requiredSideEffectToolNames.contains("stage_write_proposal"),
              !observedRequiredSideEffectToolNames.contains("stage_write_proposal"),
              let writeRequest = profile.taskFrame.writeRequest else {
            return nil
        }
        var arguments: [String: String] = [
            "operation": writeRequest.operation.rawValue,
            "targetPath": writeRequest.targetPath,
            "content": commandOutputFileContent(from: result)
        ]
        if let preferredDirectoryPath = writeRequest.preferredDirectoryPath {
            arguments["preferredDirectoryPath"] = preferredDirectoryPath
        }
        let call = AgentKernelToolCallV2(
            name: "stage_write_proposal",
            arguments: arguments,
            reason: "Stage the requested file from the command output already collected by the runtime."
        )
        return try await executeToolCall(
            call,
            runID: runID,
            providerTier: providerTier,
            context: context,
            iteration: iteration,
            controlMetadata: ["source": .string("auto_stage_command_output_write")]
        )
    }

    private nonisolated func commandOutputFileContent(from result: AgentToolExecutionResult) -> String {
        let text = result.observation.text
        if let stdoutRange = text.range(of: "Stdout:\n") {
            let start = stdoutRange.upperBound
            let tail = text[start...]
            if let stderrRange = tail.range(of: "\nStderr:") {
                let stdout = String(tail[..<stderrRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !stdout.isEmpty {
                    return stdout + "\n"
                }
            }
        }
        let fallback = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? result.summary.text : fallback + "\n"
    }

    /// Last-resort synthesis: ask the model once more for a plain final answer from the
    /// evidence already gathered, with no tools, so an exhausted or stuck run degrades into a
    /// useful answer instead of a bare terminal block (RELY-004 / RC-4). Returns true if an
    /// acceptable answer was produced and the run was completed.
    private func attemptBestEffortFinalAnswer(
        runID: UUID,
        baseRequest: AgentModelGatewayRequest,
        messages: [AgentKernelMessageV2],
        profile: AgentRunTaskProfile,
        observedToolResults: Int,
        observedSideEffectToolResults: Int,
        observedRequiredSideEffectToolNames: Set<String>
    ) async throws -> Bool {
        var synthMessages = messages
        let synthesisObservation = AgentKernelMessageV2(
            role: .observation,
            content: """
            Produce your best final answer now using the information already gathered above. \
            Do not call any tools. If you could not fully complete the task, briefly state what you found and what is blocking it.
            """
        )
        try await recordControlMessage(
            synthesisObservation,
            runID: runID,
            kind: .bestEffortSynthesisObservation
        )
        synthMessages.append(synthesisObservation)
        let request = AgentModelGatewayRequest(
            mode: baseRequest.mode,
            messages: synthMessages,
            tools: [],
            attachments: baseRequest.attachments,
            requestedMaxOutputTokens: baseRequest.requestedMaxOutputTokens,
            timeout: baseRequest.timeout,
            metadata: baseRequest.metadata.merging(["bestEffortSynthesis": .bool(true)]) { current, _ in current }
        )
        try await recordModelRequest(request, runID: runID, iteration: 0, phase: "best_effort_synthesis")
        let result = await gateway.response(adapterID: adapterID, request: request)
        try Task.checkCancellation()
        switch result {
        case .success(let response):
            try await recordModelResponse(response, runID: runID, iteration: 0, phase: "best_effort_synthesis")
            guard let answer = Self.finalAnswer(from: response.events),
                  !(isRawJSONShapedAnswer(answer.text) && profile.hasToolPath) else {
                return false
            }
            let decision = await finalAnswerDecision(
                answer,
                runID: runID,
                profile: profile,
                observedToolResults: observedToolResults,
                observedSideEffectToolResults: observedSideEffectToolResults,
                observedRequiredSideEffectToolNames: observedRequiredSideEffectToolNames,
                requiresGroundingWhenUnevidenced: requiresTextProtocolGrounding(
                    baseRequest: request,
                    response: response
                )
            )
            guard case .accept = decision else {
                if case .retry(let rejection) = decision {
                    try await store.appendEvent(
                        runID: runID,
                        kind: .providerDiagnostic,
                        payload: .diagnostic(rejection.reason)
                    )
                }
                return false
            }
            try await acceptFinalAnswer(answer, runID: runID, profile: profile)
            return true
        case .failure(let failure):
            try await recordModelFailure(
                failure,
                runID: runID,
                iteration: 0,
                phase: "best_effort_synthesis",
                requestID: request.id
            )
            return false
        }
    }

    private enum FinalAnswerRejectionKind: Hashable {
        case rawControlJSON
        case staleTemporalAnswer
        case missingTemporalContext
        case missingRequiredSideEffectEvidence
        case missingLocalEvidence
        case unsupportedLocalReferences
        case unsupportedGroundingClaims
        case missingAnswerGrounding
    }

    private struct FinalAnswerRejection {
        let kind: FinalAnswerRejectionKind
        let reason: AgentRunText
    }

    private enum FinalAnswerDecision {
        case accept
        case retry(FinalAnswerRejection)
    }

    private func preflightObservation(
        runID: UUID,
        baseRequest: AgentModelGatewayRequest,
        providerTier: AgentModelCapabilityTier,
        context: AgentToolRunContext,
        profile: AgentRunTaskProfile,
        startedAt: Date
    ) async throws -> AgentKernelMessageV2? {
        let existingEvidence = await store.evidenceArtifactSummary(runID: runID).evidence
        var observations: [String] = []
        if let grantObservation = try await grantInventoryPreflightObservation(
            runID: runID,
            tools: baseRequest.tools,
            context: context,
            existingEvidence: existingEvidence
        ) {
            observations.append(grantObservation)
        }
        observations.append(
            contentsOf: try await visualContextObservations(
                runID: runID,
                attachments: baseRequest.attachments,
                existingEvidence: existingEvidence
            )
        )
        if profile.requiresTemporalContext {
            let temporal = AgentTemporalContext(date: startedAt)
            let hasTemporalEvidence = existingEvidence.contains { record in
                record.kind == AgentEvidenceKind.temporalContext.rawValue
            }
            if !hasTemporalEvidence {
                _ = try await AgentEvidenceRecorder(store: store).recordTemporalContext(
                    runID: runID,
                    context: temporal
                )
            }
            observations.append(temporal.modelObservation)
        }

        if let commandDraft = profile.taskFrame.explicitCommandDraft,
           baseRequest.tools.contains(where: { $0.name == "run_finite_command" }),
           !existingEvidence.contains(where: { $0.kind == AgentEvidenceKind.commandOutput.rawValue }) {
            var arguments = ["command": commandDraft.command]
            if let workingDirectory = commandDraft.workingDirectory {
                arguments["workingDirectory"] = workingDirectory
            }
            let result = try await executeToolCall(
                AgentKernelToolCallV2(
                    name: "run_finite_command",
                    arguments: arguments,
                    reason: "Run the explicit command draft recorded in the task frame."
                ),
                runID: runID,
                providerTier: providerTier,
                context: context,
                iteration: 0
            )
            if result.status == .waitingForApproval {
                return nil
            }
            observations.append(
                result.modelObservationText(
                    observationCharacterLimit: maxPreflightToolObservationCharacters
                )
            )
            if let stagedWrite = try await autoStageCommandOutputWriteIfNeeded(
                after: result,
                runID: runID,
                providerTier: providerTier,
                context: context,
                profile: profile,
                observedRequiredSideEffectToolNames: [],
                iteration: 0
            ) {
                if stagedWrite.status == .waitingForApproval {
                    return nil
                }
                observations.append(
                    stagedWrite.modelObservationText(
                        observationCharacterLimit: maxPreflightToolObservationCharacters
                    )
                )
            }
        }

        let plan = AgentLocalEvidencePlanner().plan(
            messages: baseRequest.messages,
            tools: baseRequest.tools,
            context: context,
            taskFrame: profile.taskFrame,
            existingEvidence: existingEvidence
        )
        guard profile.requiresEvidenceBeforeFinalAnswer || profile.shouldRunEditPreflight || !plan.requirements.isEmpty || !observations.isEmpty else {
            return nil
        }
        let requirements = plan.requirements
        var toolCalls = plan.toolCalls
        toolCalls = uniquePreflightToolCalls(toolCalls)
        guard !toolCalls.isEmpty || !observations.isEmpty else { return nil }
        guard requirements.isEmpty || !hasSubstantiveAnswerEvidence(existingEvidence, requirements: requirements) else {
            return observations.isEmpty ? nil : AgentKernelMessageV2(role: .observation, content: observations.joined(separator: "\n\n"))
        }
        if !requirements.isEmpty {
            _ = try await AgentEvidenceRecorder(store: store).recordEvidenceRequirements(
                runID: runID,
                requirements: requirements
            )
        }

        var executedCalls = toolCalls
        for call in toolCalls.prefix(8) {
            let result = try await executeToolCall(
                call,
                runID: runID,
                providerTier: providerTier,
                context: context,
                iteration: 0
            )
            guard result.status != .waitingForApproval else { continue }
            observations.append(
                result.modelObservationText(
                    observationCharacterLimit: maxPreflightToolObservationCharacters
                )
            )
        }
        let followUpCalls = await contentFollowUpReadCalls(
            runID: runID,
            requirements: requirements,
            tools: baseRequest.tools,
            alreadyPlannedCalls: executedCalls
        )
        for call in followUpCalls.prefix(2) {
            executedCalls.append(call)
            let result = try await executeToolCall(
                call,
                runID: runID,
                providerTier: providerTier,
                context: context,
                iteration: 0
            )
            guard result.status != .waitingForApproval else { continue }
            observations.append(
                result.modelObservationText(
                    observationCharacterLimit: maxPreflightToolObservationCharacters
                )
            )
        }
        guard !observations.isEmpty else { return nil }
        let preflightText = AgentRunText(
            observations.joined(separator: "\n\n"),
            characterLimit: maxPreflightObservationCharacters
        ).text
        return AgentKernelMessageV2(
            role: .observation,
            content: preflightText
        )
    }

    private func grantInventoryPreflightObservation(
        runID: UUID,
        tools: [AgentKernelToolSchemaV2],
        context: AgentToolRunContext,
        existingEvidence: [AgentRunEvidenceRecord]
    ) async throws -> String? {
        guard context.runMode != .plainChat,
              context.supportedOperations.contains(.fileGrantList),
              tools.contains(where: { $0.name == "list_grants" }) || (tools.isEmpty && !context.localGrants.isEmpty) else {
            return nil
        }
        let provider = AgentGrantInventoryProvider()
        let snapshot = provider.snapshot(grants: context.localGrants)
        let sourceID = AgentGrantInventoryProvider.sourceID(runID: runID)
        let evidence: AgentRunEvidenceRecord
        if let existing = existingEvidence.first(where: { $0.kind == AgentEvidenceKind.fileGrant.rawValue && $0.sourceID == sourceID }) {
            evidence = existing
        } else {
            evidence = try await AgentEvidenceRecorder(store: store).recordFileGrants(
                runID: runID,
                grants: context.localGrants
            )
        }
        return provider.observation(
            snapshot: snapshot,
            evidenceID: evidence.evidenceID,
            artifactID: evidence.artifactID,
            characterLimit: maxPreflightToolObservationCharacters
        ).text
    }

    private func visualContextObservations(
        runID: UUID,
        attachments: [AgentKernelModelAttachmentV2],
        existingEvidence: [AgentRunEvidenceRecord]
    ) async throws -> [String] {
        guard !attachments.isEmpty else { return [] }
        let recordedAttachmentIDs = Set(
            existingEvidence
                .filter { $0.kind == AgentEvidenceKind.visualContext.rawValue }
                .compactMap { $0.stringMetadata("attachmentID") }
        )
        var observations: [String] = []
        for attachment in attachments where attachment.modality == .image || attachment.metadata["ocrText"] != nil {
            let ocrText = attachment.metadata["ocrText"]?.stringValue ?? ""
            let source = attachment.metadata["source"]?.stringValue ?? "attachment"
            if !recordedAttachmentIDs.contains(attachment.id.uuidString) {
                _ = try await AgentEvidenceRecorder(store: store).recordVisualContext(
                    runID: runID,
                    attachment: attachment
                )
            }
            var lines = [
                "Active visual context",
                "label: \(attachment.label)",
                "source: \(source)",
                "modality: \(attachment.modality.rawValue)"
            ]
            if !ocrText.isEmpty {
                lines.append("ocrText:")
                lines.append(AgentRunText(ocrText, characterLimit: 6_000).text)
            } else {
                lines.append("ocrText: none")
            }
            observations.append(lines.joined(separator: "\n"))
        }
        return observations
    }

    private func contentFollowUpReadCalls(
        runID: UUID,
        requirements: [AgentLocalEvidenceRequirement],
        tools: [AgentKernelToolSchemaV2],
        alreadyPlannedCalls: [AgentKernelToolCallV2]
    ) async -> [AgentKernelToolCallV2] {
        guard tools.contains(where: { $0.name == "read_file" }),
              requirements.contains(where: { $0.kind == .fileContent && $0.targetIsDirectory }) else {
            return []
        }

        let evidence = await store.evidenceArtifactSummary(runID: runID).evidence
        guard !hasSubstantiveAnswerEvidence(evidence, requirements: requirements) else {
            return []
        }

        let alreadyRead = Set(
            alreadyPlannedCalls
                .filter { $0.name == "read_file" }
                .compactMap { $0.arguments["path"] }
                .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        )
        let candidates = contentCandidatePaths(from: evidence, requirements: requirements)
        return candidates.filter { !alreadyRead.contains($0) }.map { path in
            AgentKernelToolCallV2(
                name: "read_file",
                arguments: ["path": path],
                reason: "Read the selected candidate file needed to satisfy directory content evidence."
            )
        }
    }

    private nonisolated func contentCandidatePaths(
        from evidence: [AgentRunEvidenceRecord],
        requirements: [AgentLocalEvidenceRequirement]
    ) -> [String] {
        let directoryTargets = requirements
            .filter { $0.kind == .fileContent && $0.targetIsDirectory }
            .compactMap(\.targetPath)
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        guard !directoryTargets.isEmpty else { return [] }

        func isInsideTarget(_ path: String) -> Bool {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            return directoryTargets.contains { target in
                standardized == target || standardized.hasPrefix(target + "/")
            }
        }

        var paths: [String] = []
        let selectorExtensions = Set(
            requirements
                .compactMap(\.query)
                .flatMap { AgentLocalEvidencePlanner.terms(from: $0) }
                .compactMap { term -> String? in
                    switch term {
                    case "html", "htm":
                        return "html"
                    case "markdown":
                        return "md"
                    case "txt", "md", "json", "csv", "tsv", "swift", "py", "js", "ts", "css":
                        return term
                    default:
                        return nil
                    }
                }
        )
        for record in evidence {
            guard let kind = AgentEvidenceKind(rawValue: record.kind) else { continue }
            switch kind {
            case .fileSearch:
                if let topPath = record.stringMetadata("topPath"),
                   !topPath.isEmpty,
                   isInsideTarget(topPath) {
                    paths.append(topPath)
                }
                if let rawPaths = record.stringMetadata("paths") {
                    paths.append(
                        contentsOf: rawPaths
                            .split(separator: "\n")
                            .map(String.init)
                            .filter(isInsideTarget)
                    )
                }
            case .folderList:
                for ext in selectorExtensions {
                    if let path = record.stringMetadata("topFilePath_\(ext)"),
                       !path.isEmpty,
                       isInsideTarget(path) {
                        paths.append(path)
                    }
                }
                if let topFilePath = record.stringMetadata("topFilePath"),
                   !topFilePath.isEmpty,
                   isInsideTarget(topFilePath) {
                    paths.append(topFilePath)
                }
            default:
                continue
            }
        }

        var seen = Set<String>()
        return paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { seen.insert($0).inserted }
    }

    private nonisolated func uniquePreflightToolCalls(_ calls: [AgentKernelToolCallV2]) -> [AgentKernelToolCallV2] {
        var seen = Set<String>()
        return calls.filter { call in
            let argumentKey = call.arguments
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
            return seen.insert("\(call.name):\(argumentKey)").inserted
        }
    }

    private func finalAnswerDecision(
        _ answer: AgentKernelFinalAnswerV2,
        runID: UUID,
        profile: AgentRunTaskProfile,
        observedToolResults: Int,
        observedSideEffectToolResults: Int,
        observedRequiredSideEffectToolNames: Set<String>,
        requiresGroundingWhenUnevidenced: Bool
    ) async -> FinalAnswerDecision {
        let evidence = await store.evidenceArtifactSummary(runID: runID).evidence
        let requirements = await evidenceRequirements(from: evidence)
        let hasSubstantiveEvidence = hasSubstantiveAnswerEvidence(evidence, requirements: requirements)
        let temporalEvidence = evidence.first { $0.kind == AgentEvidenceKind.temporalContext.rawValue }

        if isRawJSONShapedAnswer(answer.text), profile.hasToolPath {
            return .retry(
                FinalAnswerRejection(
                    kind: .rawControlJSON,
                    reason: AgentRunText("The answer is shaped like raw control JSON rather than user-facing prose.")
                )
            )
        }
        if profile.requiresTemporalContext {
            guard let temporalEvidence else {
                return .retry(
                    FinalAnswerRejection(
                        kind: .missingTemporalContext,
                        reason: AgentRunText("This temporal answer needs app-owned current date/time context first.")
                    )
                )
            }
            if temporalAnswerContradictsContext(answer.text, temporalEvidence: temporalEvidence) {
                return .retry(
                    FinalAnswerRejection(
                        kind: .staleTemporalAnswer,
                        reason: AgentRunText("The answer appears to use stale temporal knowledge instead of app-owned current date/time context.")
                    )
                )
            }
        }

        let localReferenceRejection = unsupportedLocalReferenceRejection(
            for: unsupportedAnswerLocalReferences(
                in: answer.text,
                evidence: evidence,
                grants: profile.taskFrame.localGrants
            )
        )

        let groundingDecision = finalAnswerGroundingDecision(
            answer,
            evidence: evidence,
            hasSubstantiveEvidence: hasSubstantiveEvidence,
            requiresGroundingWhenUnevidenced: requiresGroundingWhenUnevidenced && profile.hasToolPath
        )
        if case .retry = groundingDecision {
            return groundingDecision
        }

        if profile.requiresSideEffectEvidenceBeforeCompletion {
            let terminalRequiredTools = terminalRequiredSideEffectToolNames(evidence)
            let requiredTools = Set(profile.requiredSideEffectToolNames)
            let missingRequiredTools = requiredTools
                .subtracting(terminalRequiredTools)
                .subtracting(observedRequiredSideEffectToolNames)

            if !missingRequiredTools.isEmpty {
                let requiredToolList = missingRequiredTools.isEmpty
                    ? profile.requiredSideEffectToolNames
                    : missingRequiredTools.sorted()
                let requiredToolsText = requiredToolList.isEmpty
                    ? "an appropriate side-effect tool"
                    : requiredToolList.joined(separator: ", ")
                return .retry(
                    FinalAnswerRejection(
                        kind: .missingRequiredSideEffectEvidence,
                        reason: AgentRunText("This local change request needs \(requiredToolsText) to stage, execute, fail, or be denied before a final answer.")
                    )
                )
            }
            if let localReferenceRejection {
                return .retry(localReferenceRejection)
            }
            return .accept
        }

        if let localReferenceRejection {
            return .retry(localReferenceRejection)
        }

        if profile.requiresEvidenceBeforeFinalAnswer || !requirements.isEmpty {
            if hasSubstantiveEvidence {
                let answerUsesFileContent = await answerUsesRecordedFileContent(answer.text, evidence: evidence)
                if requirements.contains(where: { $0.kind == .fileContent }),
                   !answerUsesFileContent {
                    return .retry(
                        FinalAnswerRejection(
                            kind: .missingLocalEvidence,
                            reason: AgentRunText("This local-file answer needs to use recorded file-read evidence before completion.")
                        )
                    )
                }
                return .accept
            }
            return .retry(
                FinalAnswerRejection(
                    kind: .missingLocalEvidence,
                    reason: AgentRunText("This local-state answer needs relevant file, command, process, or side-effect evidence first.")
                )
            )
        }

        return .accept
    }

    private func finalAnswerGroundingDecision(
        _ answer: AgentKernelFinalAnswerV2,
        evidence: [AgentRunEvidenceRecord],
        hasSubstantiveEvidence: Bool,
        requiresGroundingWhenUnevidenced: Bool
    ) -> FinalAnswerDecision {
        guard let grounding = answer.grounding else {
            if requiresGroundingWhenUnevidenced && !hasSubstantiveEvidence && !hasAnyToolEvidence(evidence) {
                return .retry(
                    FinalAnswerRejection(
                        kind: .missingAnswerGrounding,
                        reason: AgentRunText("Tool-capable final answers without local evidence must declare general_knowledge, capability_limitation, or call a tool before answering.")
                    )
                )
            }
            return .accept
        }

        let claims = grounding.claims.compactMap(Self.evidenceClaim)
        if !claims.isEmpty {
            let decisions = AgentEvidenceController().verify(claims, evidence: evidence)
            let unsupported = decisions.filter { $0.status != .supported }
            if let first = unsupported.first {
                return .retry(
                    FinalAnswerRejection(
                        kind: .unsupportedGroundingClaims,
                        reason: first.summary
                    )
                )
            }
        }

        if grounding.basis == .localEvidence && claims.isEmpty {
            return .retry(
                FinalAnswerRejection(
                    kind: .unsupportedGroundingClaims,
                    reason: AgentRunText("Final answers grounded as local_evidence need declared claim kinds with matching recorded evidence.")
                )
            )
        }

        return .accept
    }

    private nonisolated static func evidenceClaim(
        from claim: AgentKernelAnswerClaimV2
    ) -> AgentEvidenceClaim? {
        switch claim.kind {
        case .fileGrants:
            return AgentEvidenceClaim(type: .fileGrantListed, target: claim.target)
        case .processSnapshot:
            return AgentEvidenceClaim(type: .processSnapshotRecorded, target: claim.target)
        case .localListeners:
            return AgentEvidenceClaim(type: .localListenerSnapshotRecorded, target: claim.target)
        case .localFile:
            return AgentEvidenceClaim(type: .localFileObserved, target: claim.target)
        case .commandOutput:
            return AgentEvidenceClaim(type: .commandOutputRecorded, target: claim.target)
        case .sideEffect:
            return AgentEvidenceClaim(type: .sideEffectRecorded, target: claim.target)
        case .temporalContext:
            return AgentEvidenceClaim(type: .temporalContextRecorded, target: claim.target)
        case .visualContext:
            return AgentEvidenceClaim(type: .visualContextRecorded, target: claim.target)
        }
    }

    private func shouldBlockAfterFinalAnswerRejection(
        _ rejection: FinalAnswerRejection,
        runID: UUID,
        profile: AgentRunTaskProfile,
        priorRejections: Int,
        observedRequiredSideEffectToolNames: Set<String>
    ) async -> Bool {
        if isGroundingRejection(rejection.kind) {
            return priorRejections >= 1
        }
        guard isRequiredSideEffectRejection(rejection.kind),
              priorRejections >= maxRequiredSideEffectFinalAnswerRepairs else {
            return false
        }
        return await shouldBlockForMissingRequiredSideEffect(
            runID: runID,
            profile: profile,
            observedRequiredSideEffectToolNames: observedRequiredSideEffectToolNames
        )
    }

    private nonisolated func isGroundingRejection(_ kind: FinalAnswerRejectionKind) -> Bool {
        switch kind {
        case .unsupportedLocalReferences, .unsupportedGroundingClaims, .missingAnswerGrounding:
            return true
        case .rawControlJSON, .staleTemporalAnswer, .missingTemporalContext, .missingRequiredSideEffectEvidence, .missingLocalEvidence:
            return false
        }
    }

    private nonisolated func isRequiredSideEffectRejection(_ kind: FinalAnswerRejectionKind) -> Bool {
        switch kind {
        case .missingRequiredSideEffectEvidence:
            return true
        case .rawControlJSON, .staleTemporalAnswer, .missingTemporalContext, .missingLocalEvidence, .unsupportedLocalReferences, .unsupportedGroundingClaims, .missingAnswerGrounding:
            return false
        }
    }

    private func shouldBlockForMissingRequiredSideEffect(
        runID: UUID,
        profile: AgentRunTaskProfile,
        observedRequiredSideEffectToolNames: Set<String>
    ) async -> Bool {
        guard profile.requiresSideEffectEvidenceBeforeCompletion else {
            return false
        }
        let evidence = await store.evidenceArtifactSummary(runID: runID).evidence
        let requiredTools = Set(profile.requiredSideEffectToolNames)
        guard !requiredTools.isEmpty else {
            return false
        }
        let terminalRequiredTools = terminalRequiredSideEffectToolNames(evidence)
        let missingRequiredTools = requiredTools
            .subtracting(terminalRequiredTools)
            .subtracting(observedRequiredSideEffectToolNames)
        return !missingRequiredTools.isEmpty
    }

    private func requiredSideEffectContractBlockReason(
        runID: UUID,
        profile: AgentRunTaskProfile,
        observedRequiredSideEffectToolNames: Set<String>
    ) async -> AgentRunText {
        let evidence = await store.evidenceArtifactSummary(runID: runID).evidence
        let requiredTools = Set(profile.requiredSideEffectToolNames)
        let terminalRequiredTools = terminalRequiredSideEffectToolNames(evidence)
        let unattemptedTools = requiredTools
            .subtracting(terminalRequiredTools)
            .subtracting(observedRequiredSideEffectToolNames)
            .sorted()
        let incompleteTools = requiredTools
            .subtracting(completedRequiredSideEffectToolNames(evidence))
            .sorted()
        let toolText = (unattemptedTools.isEmpty ? incompleteTools : unattemptedTools)
            .joined(separator: ", ")
        let requiredText = toolText.isEmpty ? "the required side-effect tool" : toolText
        return AgentRunText(
            "The model did not produce the required side-effect tool call after a bounded runtime repair attempt. Required tool: \(requiredText). No local side effect was completed."
        )
    }

    private func acceptFinalAnswer(
        _ finalAnswer: AgentKernelFinalAnswerV2,
        runID: UUID,
        profile: AgentRunTaskProfile
    ) async throws {
        if profile.hasToolPath {
            try? await recordFinalAnswerSupportIfPossible(runID: runID, answer: finalAnswer)
        }
        try await store.appendEvent(
            runID: runID,
            kind: .assistantMessage,
            payload: .text(AgentRunText(finalAnswer.text))
        )
        try await recordTerminalStateIfNeeded(
            runID: runID,
            status: .completed,
            reason: AgentRunText("Final answer produced.")
        )
        try await store.updateRunStatus(
            runID: runID,
            status: .completed,
            reason: AgentRunText("Final answer produced.")
        )
    }

    func continueAfterApproval(
        waitID: UUID,
        runID: UUID,
        request baseRequest: AgentModelGatewayRequest,
        context: AgentToolRunContext,
        approved: Bool
    ) async throws {
        let step = try await store.beginStep(
            runID: runID,
            kind: .sideEffect,
            metadata: ["waitID": .string(waitID.uuidString)]
        )
        let result: AgentToolExecutionResult
        do {
            result = approved
                ? try await executor.approvedSideEffectResult(waitID: waitID, runID: runID, stepID: step.stepID)
                : try await executor.deniedSideEffectResult(waitID: waitID, runID: runID, stepID: step.stepID)
            try await recordToolResult(
                result,
                runID: runID,
                stepID: step.stepID,
                iteration: 0,
                metadata: [
                    "source": .string("approval_continuation"),
                    "waitID": .string(waitID.uuidString),
                    "approved": .bool(approved)
                ]
            )
            try await store.appendEvent(
                runID: runID,
                stepID: step.stepID,
                kind: .progress,
                payload: .progress(result.summary)
            )
            _ = try await store.finishStep(stepID: step.stepID, status: .completed)
        } catch {
            _ = try? await store.finishStep(stepID: step.stepID, status: .failed)
            throw error
        }

        let replayMessages = await store.replayMessages(runID: runID)
        var messages = replayMessages.isEmpty
            ? await fallbackApprovalContinuationMessages(runID: runID, baseRequest: baseRequest)
            : replayMessages
        let approvalObservation = AgentKernelMessageV2(role: .observation, content: result.modelObservationText)
        try await recordControlMessage(
            approvalObservation,
            runID: runID,
            stepID: step.stepID,
            kind: .approvalResultObservation,
            metadata: [
                "source": .string("approval_continuation"),
                "waitID": .string(waitID.uuidString),
                "approved": .bool(approved),
                "usedDurableReplay": .bool(!replayMessages.isEmpty)
            ]
        )
        messages.append(approvalObservation)
        var resumedMetadata = baseRequest.metadata
        resumedMetadata["approvalContinuation"] = .bool(true)
        resumedMetadata["approvalReplayAvailable"] = .bool(!replayMessages.isEmpty)
        if !replayMessages.isEmpty {
            resumedMetadata["skipPreflight"] = .bool(true)
        }
        let resumedRequest = AgentModelGatewayRequest(
            mode: baseRequest.mode,
            messages: messages,
            tools: baseRequest.tools,
            attachments: baseRequest.attachments,
            requestedMaxOutputTokens: baseRequest.requestedMaxOutputTokens,
            timeout: baseRequest.timeout,
            metadata: resumedMetadata
        )

        if approved {
            try await run(runID: runID, request: resumedRequest, context: context)
        } else {
            try await store.appendEvent(
                runID: runID,
                kind: .assistantMessage,
                payload: .text(result.summary)
            )
            try await store.updateRunStatus(
                runID: runID,
                status: .blocked,
                reason: result.summary
            )
        }
    }

    private func fallbackApprovalContinuationMessages(
        runID: UUID,
        baseRequest: AgentModelGatewayRequest
    ) async -> [AgentKernelMessageV2] {
        let visible = await store.visibleMessages(sessionID: nil).filter { $0.runID == runID }
        var messages = baseRequest.messages.filter { $0.role == .system }
        messages.append(
            contentsOf: visible.map {
                AgentKernelMessageV2(
                    role: $0.role == .user ? .user : .assistant,
                    content: $0.text.text
                )
            }
        )
        return messages
    }

    private func modelResponse(
        runID: UUID,
        baseRequest: AgentModelGatewayRequest,
        messages: [AgentKernelMessageV2],
        iteration: Int,
        profile: AgentRunTaskProfile
    ) async throws -> AgentModelGatewayResponse {
        let step = try await store.beginStep(
            runID: runID,
            kind: .modelRequest,
            metadata: ["iteration": .int(iteration)]
        )
        do {
            try await store.appendEvent(
                runID: runID,
                stepID: step.stepID,
                kind: .progress,
                payload: .progress(AgentRunText("Asking the model."))
            )
            let request = AgentModelGatewayRequest(
                mode: baseRequest.mode,
                messages: messages,
                tools: baseRequest.tools,
                attachments: baseRequest.attachments,
                requestedMaxOutputTokens: baseRequest.requestedMaxOutputTokens,
                timeout: baseRequest.timeout,
                metadata: baseRequest.metadata
            )
            try await recordModelRequest(request, runID: runID, stepID: step.stepID, iteration: iteration, phase: "main")
            let result = await gateway.response(adapterID: adapterID, request: request)
            switch result {
            case .success(let response):
                try await recordModelResponse(response, runID: runID, stepID: step.stepID, iteration: iteration, phase: "main")
                try await store.appendEvent(
                    runID: runID,
                    stepID: step.stepID,
                    kind: .providerDiagnostic,
                    payload: .diagnostic(providerDiagnostic(response: response, request: request))
                )
                if let diagnostics = response.diagnostics,
                   !diagnostics.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try await store.appendEvent(
                        runID: runID,
                        stepID: step.stepID,
                        kind: .providerDiagnostic,
                        payload: .diagnostic(diagnostics)
                    )
                }
                _ = try await store.finishStep(stepID: step.stepID, status: .completed)
                return response
            case .failure(let failure):
                try await recordModelFailure(
                    failure,
                    runID: runID,
                    stepID: step.stepID,
                    iteration: iteration,
                    phase: "main",
                    requestID: request.id
                )
                if failure.kind == .structuredOutputInvalid,
                   let recovered = try await recoverStructuredOutputFailure(
                    runID: runID,
                    stepID: step.stepID,
                    iteration: iteration,
                    baseRequest: baseRequest,
                    messages: messages,
                    profile: profile,
                    failure: failure
                   ) {
                    _ = try await store.finishStep(stepID: step.stepID, status: .completed)
                    return recovered
                }
                if failure.kind == .toolCallInvalid,
                   let recovered = try await recoverInvalidToolCallFailure(
                    runID: runID,
                    stepID: step.stepID,
                    iteration: iteration,
                    baseRequest: baseRequest,
                    messages: messages,
                    profile: profile,
                    failure: failure
                   ) {
                    _ = try await store.finishStep(stepID: step.stepID, status: .completed)
                    return recovered
                }
                if failure.kind == .contextTooLarge,
                   let retryMessages = compactMessagesForRetry(messages, failure: failure) {
                    try await store.appendEvent(
                        runID: runID,
                        stepID: step.stepID,
                        kind: .progress,
                        payload: .progress(AgentRunText("Repacking evidence context to fit the provider limit."))
                    )
                    let retryRequest = AgentModelGatewayRequest(
                        mode: baseRequest.mode,
                        messages: retryMessages,
                        tools: baseRequest.tools,
                        attachments: baseRequest.attachments,
                        requestedMaxOutputTokens: baseRequest.requestedMaxOutputTokens,
                        timeout: baseRequest.timeout,
                        metadata: baseRequest.metadata.merging(["contextRepacked": .bool(true)]) { current, _ in current }
                    )
                    try await store.recordControl(
                        runID: runID,
                        stepID: step.stepID,
                        kind: .contextRepackObservation,
                        payload: .metadata([
                            "iteration": .int(iteration),
                            "failureKind": .string(failure.kind.rawValue),
                            "retryRequestID": .string(retryRequest.id.uuidString)
                        ]),
                        metadata: [
                            "iteration": .int(iteration),
                            "phase": .string("context_repack")
                        ]
                    )
                    try await recordModelRequest(
                        retryRequest,
                        runID: runID,
                        stepID: step.stepID,
                        iteration: iteration,
                        phase: "context_repack"
                    )
                    let retryResult = await gateway.response(adapterID: adapterID, request: retryRequest)
                    switch retryResult {
                    case .success(let response):
                        try await recordModelResponse(
                            response,
                            runID: runID,
                            stepID: step.stepID,
                            iteration: iteration,
                            phase: "context_repack"
                        )
                        _ = try await store.finishStep(stepID: step.stepID, status: .completed)
                        return response
                    case .failure(let retryFailure):
                        try await recordModelFailure(
                            retryFailure,
                            runID: runID,
                            stepID: step.stepID,
                            iteration: iteration,
                            phase: "context_repack",
                            requestID: retryRequest.id
                        )
                        _ = try await store.finishStep(stepID: step.stepID, status: .failed)
                        let reason = contextFailureReason(retryFailure)
                        try await failRun(runID: runID, reason: reason, status: .blocked)
                        throw retryFailure
                    }
                }
                _ = try await store.finishStep(stepID: step.stepID, status: .failed)
                let status: AgentRunStatus = failure.kind == .structuredOutputInvalid ? .blocked : .failed
                let reason = failure.kind == .structuredOutputInvalid
                    ? structuredOutputRecoveryReason(failure)
                    : failure.message
                try await failRun(runID: runID, reason: reason, status: status)
                throw failure
            }
        } catch {
            _ = try? await store.finishStep(stepID: step.stepID, status: .failed)
            throw error
        }
    }

    private nonisolated func compactMessagesForRetry(
        _ messages: [AgentKernelMessageV2],
        failure: AgentModelGatewayFailure
    ) -> [AgentKernelMessageV2]? {
        let maxPromptCharacters = failure.metadata["maxPromptCharacters"]?.intValue ?? 12_000
        let targetCharacters = max(2_000, Int(Double(maxPromptCharacters) * 0.72))
        var compacted: [AgentKernelMessageV2] = []
        let system = messages.first { $0.role == .system }
        if let system {
            compacted.append(
                AgentKernelMessageV2(
                    id: system.id,
                    role: .system,
                    content: AgentRunText(system.content, characterLimit: min(3_000, targetCharacters / 4)).text
                )
            )
        }
        let nonSystem = messages.filter { $0.role != .system }
        let latestUser = nonSystem.reversed().first { $0.role == .user }
        let observations = nonSystem.filter { $0.role == .observation }.suffix(6)
        if let latestUser {
            compacted.append(
                AgentKernelMessageV2(
                    id: latestUser.id,
                    role: .user,
                    content: AgentRunText(latestUser.content, characterLimit: min(2_000, targetCharacters / 4)).text
                )
            )
        }
        for observation in observations {
            compacted.append(
                AgentKernelMessageV2(
                    id: observation.id,
                    role: .observation,
                    content: compactObservation(observation.content, limit: max(700, targetCharacters / 8))
                )
            )
        }
        let total = compacted.reduce(0) { $0 + $1.content.count }
        guard total < messages.reduce(0, { $0 + $1.content.count }) else {
            return nil
        }
        return compacted
    }

    private nonisolated func compactObservation(_ observation: String, limit: Int) -> String {
        let keepPrefixes = [
            "Tool result",
            "name:",
            "status:",
            "summary:",
            "evidenceIDs:",
            "artifactIDs:",
            "Path:",
            "Evidence ID:",
            "Artifact ID:",
            "Original content truncated",
            "Command:",
            "Working directory:",
            "Exit code:",
            "Timed out:"
        ]
        let lines = observation.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var kept = lines.filter { line in
            keepPrefixes.contains { line.hasPrefix($0) }
        }
        if let observationIndex = lines.firstIndex(where: { $0 == "observation:" }) {
            kept.append("observation:")
            kept.append(contentsOf: lines.suffix(from: min(lines.count, observationIndex + 1)).prefix(8))
        }
        let text = kept.isEmpty ? observation : kept.joined(separator: "\n")
        return AgentRunText(text, characterLimit: limit).text
    }

    private nonisolated func contextFailureReason(_ failure: AgentModelGatewayFailure) -> AgentRunText {
        if failure.kind == .contextTooLarge {
            return AgentRunText("The recorded evidence is still too large for the selected provider after repacking. Narrow the request, search a specific file or folder, or switch to a provider with a larger context window.")
        }
        return failure.message
    }

    private nonisolated func structuredOutputRecoveryReason(_ failure: AgentModelGatewayFailure) -> AgentRunText {
        AgentRunText("\(failure.message.text) Retry the request, switch to a provider with stricter tool/JSON support, or ask for read-only inspection before requesting edits.")
    }

    private func recoverInvalidToolCallFailure(
        runID: UUID,
        stepID: UUID,
        iteration: Int,
        baseRequest: AgentModelGatewayRequest,
        messages: [AgentKernelMessageV2],
        profile: AgentRunTaskProfile,
        failure: AgentModelGatewayFailure
    ) async throws -> AgentModelGatewayResponse? {
        let evidence = await store.evidenceArtifactSummary(runID: runID).evidence
        let requirements = await evidenceRequirements(from: evidence)
        let requirementsSatisfied = !requirements.isEmpty
            && hasSubstantiveAnswerEvidence(evidence, requirements: requirements)
        let hasRecordedEvidence = hasSubstantiveAnswerEvidence(evidence, requirements: requirements)
            || (!requirements.isEmpty && hasAnyToolEvidence(evidence))
        let shouldDisableTools = baseRequest.tools.isEmpty || requirementsSatisfied
        let sideEffectReady = !profile.requiresSideEffectEvidenceBeforeCompletion ||
            Set(profile.requiredSideEffectToolNames).isSubset(of: terminalRequiredSideEffectToolNames(evidence))
        guard sideEffectReady else { return nil }

        try await store.appendEvent(
            runID: runID,
            stepID: stepID,
            kind: .providerDiagnostic,
            payload: .diagnostic(
                AgentRunText(
                    shouldDisableTools && hasRecordedEvidence
                        ? "Provider returned an invalid tool call after evidence was recorded. Retrying once as a no-tool evidence-grounded answer."
                        : "Provider returned an invalid tool call. Retrying once with the validation error in the model context."
                )
            )
        )

        var retryMessages = messages
        let recoveryObservation = AgentKernelMessageV2(
            role: .observation,
            content: shouldDisableTools && hasRecordedEvidence
                ? """
                The previous provider response called a tool with invalid arguments.
                Validation error: \(failure.message.text)
                Produce a user-facing final answer from the recorded evidence above. Do not call tools.
                If the evidence is insufficient, state what evidence is missing.
                """
                : shouldDisableTools
                ? """
                The previous provider response called a tool with invalid arguments.
                Validation error: \(failure.message.text)
                Tool calls are not available in this recovery request. Produce a user-facing final answer if possible, or state what evidence is missing.
                """
                : """
                The previous provider response called a tool with invalid arguments.
                Validation error: \(failure.message.text)
                Retry with a valid tool call that includes every required argument, or produce a user-facing final answer if no tool is needed.
                """
        )
        try await recordControlMessage(
            recoveryObservation,
            runID: runID,
            stepID: stepID,
            kind: .toolCallInvalidRecoveryObservation,
            metadata: [
                "iteration": .int(iteration),
                "failureKind": .string(failure.kind.rawValue),
                "hasRecordedEvidence": .bool(hasRecordedEvidence),
                "requirementsSatisfied": .bool(requirementsSatisfied),
                "toolsDisabled": .bool(shouldDisableTools)
            ]
        )
        retryMessages.append(recoveryObservation)

        let retryRequest = AgentModelGatewayRequest(
            mode: shouldDisableTools ? .plainChat : baseRequest.mode,
            messages: retryMessages,
            tools: shouldDisableTools ? [] : baseRequest.tools,
            attachments: baseRequest.attachments,
            requestedMaxOutputTokens: baseRequest.requestedMaxOutputTokens,
            timeout: baseRequest.timeout,
            metadata: baseRequest.metadata.merging(["toolCallInvalidRecovery": .bool(true)]) { current, _ in current }
        )
        try await recordModelRequest(
            retryRequest,
            runID: runID,
            stepID: stepID,
            iteration: iteration,
            phase: "tool_call_invalid_recovery"
        )
        let retry = await gateway.response(adapterID: adapterID, request: retryRequest)
        try Task.checkCancellation()
        switch retry {
        case .success(let response):
            try await recordModelResponse(
                response,
                runID: runID,
                stepID: stepID,
                iteration: iteration,
                phase: "tool_call_invalid_recovery"
            )
            return response
        case .failure(let recoveryFailure):
            try await recordModelFailure(
                recoveryFailure,
                runID: runID,
                stepID: stepID,
                iteration: iteration,
                phase: "tool_call_invalid_recovery",
                requestID: retryRequest.id
            )
            return nil
        }
    }

    private func recoverStructuredOutputFailure(
        runID: UUID,
        stepID: UUID,
        iteration: Int,
        baseRequest: AgentModelGatewayRequest,
        messages: [AgentKernelMessageV2],
        profile: AgentRunTaskProfile,
        failure: AgentModelGatewayFailure
    ) async throws -> AgentModelGatewayResponse? {
        let evidence = await store.evidenceArtifactSummary(runID: runID).evidence
        let requirements = await evidenceRequirements(from: evidence)
        let hasEvidence = hasSubstantiveAnswerEvidence(evidence, requirements: requirements)
            || (!requirements.isEmpty && hasAnyToolEvidence(evidence))
        guard hasEvidence else { return nil }
        guard !profile.requiresSideEffectEvidenceBeforeCompletion ||
                Set(profile.requiredSideEffectToolNames).isSubset(of: terminalRequiredSideEffectToolNames(evidence)) else {
            return nil
        }

        try await store.appendEvent(
            runID: runID,
            stepID: stepID,
            kind: .providerDiagnostic,
            payload: .diagnostic(AgentRunText("Provider returned malformed structured output after evidence was recorded. Retrying once as a no-tool evidence-grounded answer."))
        )

        var retryMessages = messages
        let recoveryObservation = AgentKernelMessageV2(
            role: .observation,
            content: """
            The previous provider response did not satisfy the structured tool protocol.
            Produce a user-facing final answer from the recorded evidence above. Do not call tools.
            If the evidence is insufficient, state what evidence is missing.
            """
        )
        try await recordControlMessage(
            recoveryObservation,
            runID: runID,
            stepID: stepID,
            kind: .structuredOutputRecoveryObservation,
            metadata: [
                "iteration": .int(iteration),
                "failureKind": .string(failure.kind.rawValue)
            ]
        )
        retryMessages.append(recoveryObservation)
        let retryRequest = AgentModelGatewayRequest(
            mode: .plainChat,
            messages: retryMessages,
            tools: [],
            attachments: baseRequest.attachments,
            requestedMaxOutputTokens: baseRequest.requestedMaxOutputTokens,
            timeout: baseRequest.timeout,
            metadata: baseRequest.metadata.merging(["structuredOutputRecovery": .bool(true)]) { current, _ in current }
        )
        try await recordModelRequest(
            retryRequest,
            runID: runID,
            stepID: stepID,
            iteration: iteration,
            phase: "structured_output_recovery"
        )
        let retry = await gateway.response(adapterID: adapterID, request: retryRequest)
        try Task.checkCancellation()
        switch retry {
        case .success(let response):
            try await recordModelResponse(
                response,
                runID: runID,
                stepID: stepID,
                iteration: iteration,
                phase: "structured_output_recovery"
            )
            guard let answer = Self.finalAnswer(from: response.events),
                  !isRawJSONShapedAnswer(answer.text) else {
                try await failRun(
                    runID: runID,
                    reason: AgentRunText("Provider failed the structured tool protocol and the no-tool recovery did not produce user-facing prose. Recorded evidence was preserved for retry."),
                    status: .blocked
                )
                throw failure
            }
            return response
        case .failure(let recoveryFailure):
            try await recordModelFailure(
                recoveryFailure,
                runID: runID,
                stepID: stepID,
                iteration: iteration,
                phase: "structured_output_recovery",
                requestID: retryRequest.id
            )
            try await failRun(
                runID: runID,
                reason: AgentRunText("Provider failed the structured tool protocol and the no-tool recovery request also failed. Recorded evidence was preserved for retry."),
                status: .blocked
            )
            throw failure
        }
    }

    private nonisolated func providerDiagnostic(
        response: AgentModelGatewayResponse,
        request: AgentModelGatewayRequest
    ) -> AgentRunText {
        AgentRunText(
            "Provider route=\(response.descriptor.route.rawValue) adapter=\(response.adapterID) model=\(response.descriptor.modelName ?? response.descriptor.displayName) tier=\(response.tier.rawValue) mode=\(request.mode.rawValue) responseFormat=\(response.responseFormat.rawValue) visibleTools=\(request.tools.map(\.name).sorted().joined(separator: ","))"
        )
    }

    private nonisolated func requiresTextProtocolGrounding(
        baseRequest: AgentModelGatewayRequest,
        response: AgentModelGatewayResponse
    ) -> Bool {
        baseRequest.mode != .plainChat
            && response.tier == .tierBConstrainedStructuredText
            && response.responseFormat == .textProtocol
    }

    private func executeToolCall(
        _ call: AgentKernelToolCallV2,
        runID: UUID,
        providerTier: AgentModelCapabilityTier,
        context: AgentToolRunContext,
        iteration: Int,
        controlMetadata: [String: AgentRunMetadataValue] = [:]
    ) async throws -> AgentToolExecutionResult {
        let requestStep = try await store.beginStep(
            runID: runID,
            kind: .toolRequest,
            metadata: [
                "toolName": .string(call.name),
                "iteration": .int(iteration)
            ]
        )
        try await store.appendEvent(
            runID: runID,
            stepID: requestStep.stepID,
            kind: .custom,
            payload: .metadata(toolMetadata(call))
        )
        try await recordToolCall(
            call,
            runID: runID,
            stepID: requestStep.stepID,
            iteration: iteration,
            metadata: controlMetadata
        )
        _ = try await store.finishStep(stepID: requestStep.stepID, status: .completed)

        let resultStep = try await store.beginStep(
            runID: runID,
            kind: .toolResult,
            metadata: [
                "toolName": .string(call.name),
                "iteration": .int(iteration)
            ]
        )
        do {
            let result = try await executor.execute(
                call: call,
                runID: runID,
                stepID: resultStep.stepID,
                providerTier: providerTier,
                context: context
            )
            try await store.appendEvent(
                runID: runID,
                stepID: resultStep.stepID,
                kind: .progress,
                payload: .progress(result.summary)
            )
            try await recordToolResult(
                result,
                runID: runID,
                stepID: resultStep.stepID,
                iteration: iteration,
                metadata: controlMetadata
            )
            _ = try await store.finishStep(stepID: resultStep.stepID, status: .completed)
            return result
        } catch {
            _ = try? await store.finishStep(stepID: resultStep.stepID, status: .failed)
            throw error
        }
    }

    private func failRun(
        runID: UUID,
        reason: AgentRunText,
        status: AgentRunStatus = .failed
    ) async throws {
        try await recordTerminalStateIfNeeded(
            runID: runID,
            status: status,
            reason: reason
        )
        try await store.updateRunStatus(
            runID: runID,
            status: status,
            reason: reason
        )
        try await store.appendEvent(
            runID: runID,
            kind: .failure,
            payload: .diagnostic(reason)
        )
    }

    private func recordTerminalStateIfNeeded(
        runID: UUID,
        status: AgentRunStatus,
        reason: AgentRunText
    ) async throws {
        let hasMatchingTerminal = await store.evidenceArtifactSummary(runID: runID).evidence.contains { record in
            record.kind == AgentEvidenceKind.terminalState.rawValue
                && record.stringMetadata("status") == status.rawValue
        }
        guard !hasMatchingTerminal else { return }
        _ = try await AgentEvidenceRecorder(store: store).recordTerminalState(
            runID: runID,
            status: status,
            reason: reason
        )
    }

    private func recordFinalAnswerSupportIfPossible(runID: UUID, answer: AgentKernelFinalAnswerV2) async throws {
        let evidence = await store.evidenceArtifactSummary(runID: runID).evidence
        let requirements = await evidenceRequirements(from: evidence)
        let declaredClaims = answer.grounding?.claims.compactMap(Self.evidenceClaim) ?? []
        let claims = declaredClaims.isEmpty ? finalAnswerClaims(from: evidence, requirements: requirements) : declaredClaims
        guard !claims.isEmpty else { return }
        _ = try await AgentFinalAnswerSupportRecorder(
            store: store,
            evidenceRecorder: AgentEvidenceRecorder(store: store)
        ).recordSupport(
            runID: runID,
            answer: AgentRunText(answer.text),
            claims: claims
        )
    }

    private func evidenceRequirements(from evidence: [AgentRunEvidenceRecord]) async -> [AgentLocalEvidenceRequirement] {
        let decoder = JSONDecoder()
        var requirements: [AgentLocalEvidenceRequirement] = []
        for record in evidence where record.kind == AgentEvidenceKind.evidenceRequirement.rawValue {
            if let artifactID = record.artifactID,
               let data = try? await store.readArtifact(artifactID),
               let decoded = try? decoder.decode([AgentLocalEvidenceRequirement].self, from: data) {
                requirements.append(contentsOf: decoded)
                continue
            }
            if let kindValue = record.stringMetadata("requirementKinds")?.split(separator: ",").first,
               let kind = AgentLocalEvidenceRequirementKind(rawValue: String(kindValue)) {
                let targetPath = record.stringMetadata("targetPath").flatMap { $0.isEmpty ? nil : $0 }
                requirements.append(
                    AgentLocalEvidenceRequirement(
                        kind: kind,
                        targetPath: targetPath,
                        targetIsDirectory: record.boolMetadata("targetIsDirectory") ?? false
                    )
                )
            }
        }
        var seen = Set<String>()
        return requirements.filter { seen.insert($0.id).inserted }
    }

    private func finalAnswerClaims(
        from evidence: [AgentRunEvidenceRecord],
        requirements: [AgentLocalEvidenceRequirement] = []
    ) -> [AgentEvidenceClaim] {
        var claims: [AgentEvidenceClaim] = []
        let shouldInferGrantClaims = requirements.contains { $0.kind == .grantDiscovery }
        for record in evidence {
            guard let kind = AgentEvidenceKind(rawValue: record.kind) else { continue }
            switch kind {
            case .fileGrant:
                if shouldInferGrantClaims {
                    if let path = record.stringMetadata("path"), !path.isEmpty {
                        claims.append(AgentEvidenceClaim(type: .fileGrantListed, target: path))
                    } else {
                        claims.append(AgentEvidenceClaim(type: .fileGrantListed))
                    }
                }
            case .fileRead:
                if let path = record.stringMetadata("path") {
                    claims.append(.fileExists(path))
                }
            case .fileSearch:
                continue
            case .folderList:
                if let paths = record.stringMetadata("paths") {
                    for path in paths.split(separator: "\n").map(String.init).prefix(8) where !path.isEmpty {
                        claims.append(.fileSearchFound(path))
                    }
                }
            case .commandOutput:
                if let command = record.stringMetadata("command") {
                    claims.append(AgentEvidenceClaim(type: .commandRan, target: command))
                }
            case .processSnapshot:
                if let topPID = record.intMetadata("topPID") {
                    claims.append(AgentEvidenceClaim(type: .processRunning, target: String(topPID)))
                }
                if let topExecutable = record.stringMetadata("topExecutable") {
                    claims.append(AgentEvidenceClaim(type: .processRunning, target: topExecutable))
                }
            case .sideEffect:
                if record.stringMetadata("status") == AgentRunSideEffectStatus.completed.rawValue {
                    if let targetPath = record.stringMetadata("targetPath") {
                        claims.append(.fileChanged(targetPath))
                    } else if let sideEffectID = record.stringMetadata("sideEffectID") {
                        claims.append(AgentEvidenceClaim(type: .sideEffectCompleted, target: sideEffectID))
                    }
                }
            case .localServer:
                claims.append(AgentEvidenceClaim(type: .localListenerSnapshotRecorded, target: record.intMetadata("port").map(String.init)))
                if record.boolMetadata("isListening") == true,
                   let port = record.intMetadata("port") {
                    claims.append(.portListening(port))
                }
                if let url = record.stringMetadata("url") {
                    claims.append(.urlResponds(url))
                }
            case .processState:
                if let processID = record.stringMetadata("processID") {
                    claims.append(AgentEvidenceClaim(type: .processRunning, target: processID))
                }
            case .temporalContext, .visualContext, .approval, .terminalState, .evidenceRequirement, .finalAnswerSupport:
                continue
            }
        }
        var seen = Set<String>()
        return claims.filter { claim in
            let key = "\(claim.type.rawValue):\(claim.target ?? "")"
            return seen.insert(key).inserted
        }
    }

    private nonisolated func unsupportedAnswerLocalReferences(
        in answer: String,
        evidence: [AgentRunEvidenceRecord],
        grants: [AgentLocalFileGrant]
    ) -> [String] {
        guard !grants.isEmpty else { return [] }
        let resolver = AgentLocalPathResolver()
        var seen = Set<String>()
        var unsupported: [String] = []
        for rawPath in AgentTaskFrame.localPathCandidates(in: answer) {
            guard case .resolved(let resolution) = resolver.resolve(
                rawPath,
                grants: grants,
                access: .read,
                target: .any
            ) else {
                continue
            }
            let path = URL(fileURLWithPath: resolution.path).standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            guard !localReferenceIsBacked(path, by: evidence) else { continue }
            unsupported.append(path)
        }
        return unsupported
    }

    private nonisolated func unsupportedLocalReferenceRejection(
        for unsupportedLocalReferences: [String]
    ) -> FinalAnswerRejection? {
        guard !unsupportedLocalReferences.isEmpty else { return nil }
        let displayed = unsupportedLocalReferences.prefix(4).joined(separator: ", ")
        let suffix = unsupportedLocalReferences.count > 4 ? ", ..." : ""
        return FinalAnswerRejection(
            kind: .unsupportedLocalReferences,
            reason: AgentRunText(
                "The final answer references accessible local path(s) without recorded evidence: \(displayed)\(suffix). Call an available local file tool for those path(s), or answer without unsupported local references."
            )
        )
    }

    private nonisolated func localReferenceIsBacked(
        _ path: String,
        by evidence: [AgentRunEvidenceRecord]
    ) -> Bool {
        evidence.contains { record in
            guard let kind = AgentEvidenceKind(rawValue: record.kind) else { return false }
            switch kind {
            case .fileGrant:
                return pathMatches(record.stringMetadata("path"), path)
                    || pathListContains(record.stringMetadata("paths"), path)
            case .fileRead:
                return pathMatches(record.stringMetadata("path"), path)
            case .fileSearch:
                return pathMatches(record.stringMetadata("topPath"), path)
                    || pathListContains(record.stringMetadata("paths"), path)
            case .folderList:
                return pathMatches(record.stringMetadata("path"), path)
                    || pathListContains(record.stringMetadata("paths"), path)
            case .sideEffect:
                guard record.stringMetadata("status") == AgentRunSideEffectStatus.completed.rawValue else {
                    return false
                }
                return pathMatches(record.stringMetadata("targetPath") ?? record.stringMetadata("path"), path)
            case .commandOutput, .localServer, .processSnapshot, .processState, .temporalContext,
                 .visualContext, .approval, .terminalState, .evidenceRequirement, .finalAnswerSupport:
                return false
            }
        }
    }

    private nonisolated func pathMatches(_ candidate: String?, _ path: String) -> Bool {
        guard let candidate, !candidate.isEmpty else { return false }
        return URL(fileURLWithPath: candidate).standardizedFileURL.path == path
    }

    private nonisolated func pathListContains(_ candidates: String?, _ path: String) -> Bool {
        guard let candidates else { return false }
        return candidates
            .split(separator: "\n")
            .map(String.init)
            .contains { pathMatches($0, path) }
    }

    private func hasSubstantiveAnswerEvidence(
        _ evidence: [AgentRunEvidenceRecord],
        requirements: [AgentLocalEvidenceRequirement] = []
    ) -> Bool {
        if !requirements.isEmpty {
            return requirements.allSatisfy { $0.isSatisfied(by: evidence) }
        }
        return evidence.contains { record in
            guard let kind = AgentEvidenceKind(rawValue: record.kind) else { return false }
            switch kind {
            case .fileRead, .commandOutput, .localServer, .processSnapshot, .processState, .temporalContext, .visualContext:
                return true
            case .fileSearch:
                return (record.intMetadata("matchCount") ?? 0) > 0
            case .folderList:
                return (record.intMetadata("entryCount") ?? 0) > 0
            case .sideEffect:
                return record.stringMetadata("status") != nil
            case .fileGrant, .approval, .terminalState, .evidenceRequirement, .finalAnswerSupport:
                return false
            }
        }
    }

    private func answerUsesRecordedFileContent(
        _ answer: String,
        evidence: [AgentRunEvidenceRecord]
    ) async -> Bool {
        let answerTerms = Set(AgentLocalEvidencePlanner.terms(from: answer))
        guard !answerTerms.isEmpty else { return false }
        var evidenceTerms = Set<String>()
        for record in evidence where record.kind == AgentEvidenceKind.fileRead.rawValue {
            if let artifactID = record.artifactID,
               let data = try? await store.readArtifact(artifactID),
               let text = String(data: data, encoding: .utf8) {
                evidenceTerms.formUnion(AgentLocalEvidencePlanner.terms(from: text))
            }
            evidenceTerms.formUnion(AgentLocalEvidencePlanner.terms(from: record.summary.text))
            for value in record.metadata.values {
                if let text = value.stringValue {
                    evidenceTerms.formUnion(AgentLocalEvidencePlanner.terms(from: text))
                }
            }
        }
        guard !evidenceTerms.isEmpty else { return false }
        let overlap = answerTerms.intersection(evidenceTerms)
        if overlap.count >= min(2, answerTerms.count) {
            return true
        }
        return overlap.reduce(0) { $0 + $1.count } >= 12
    }

    private func hasAnyToolEvidence(_ evidence: [AgentRunEvidenceRecord]) -> Bool {
        evidence.contains { record in
            guard let kind = AgentEvidenceKind(rawValue: record.kind) else { return false }
            switch kind {
            case .fileRead, .fileSearch, .folderList, .commandOutput, .localServer, .processSnapshot, .processState, .temporalContext, .visualContext, .sideEffect:
                return true
            case .fileGrant, .approval, .terminalState, .evidenceRequirement, .finalAnswerSupport:
                return false
            }
        }
    }

    private func completedRequiredSideEffectToolNames(_ evidence: [AgentRunEvidenceRecord]) -> Set<String> {
        Set(evidence.compactMap { record in
            guard let kind = AgentEvidenceKind(rawValue: record.kind) else { return nil }
            switch kind {
            case .sideEffect:
                guard record.stringMetadata("status") == AgentRunSideEffectStatus.completed.rawValue else {
                    return nil
                }
                switch record.stringMetadata("kind") {
                case AgentRunSideEffectKind.fileWrite.rawValue:
                    return "stage_write_proposal"
                case AgentRunSideEffectKind.command.rawValue:
                    return "run_finite_command"
                default:
                    return nil
                }
            case .commandOutput:
                return record.intMetadata("exitCode") == 0 && record.boolMetadata("didTimeOut") != true
                    ? "run_finite_command"
                    : nil
            default:
                return nil
            }
        })
    }

    private func terminalRequiredSideEffectToolNames(_ evidence: [AgentRunEvidenceRecord]) -> Set<String> {
        Set(evidence.compactMap { record in
            guard let kind = AgentEvidenceKind(rawValue: record.kind) else { return nil }
            switch kind {
            case .sideEffect:
                guard let status = record.stringMetadata("status") else { return nil }
                guard [
                    AgentRunSideEffectStatus.denied.rawValue,
                    AgentRunSideEffectStatus.failed.rawValue,
                    AgentRunSideEffectStatus.canceled.rawValue,
                    AgentRunSideEffectStatus.rolledBack.rawValue,
                    AgentRunSideEffectStatus.completed.rawValue
                ].contains(status) else {
                    return nil
                }
                switch record.stringMetadata("kind") {
                case AgentRunSideEffectKind.fileWrite.rawValue:
                    return "stage_write_proposal"
                case AgentRunSideEffectKind.command.rawValue:
                    return "run_finite_command"
                default:
                    return nil
                }
            case .commandOutput:
                return record.intMetadata("exitCode") != nil || record.boolMetadata("didTimeOut") == true
                    ? "run_finite_command"
                    : nil
            default:
                return nil
            }
        })
    }

    private nonisolated func isRawJSONShapedAnswer(_ answer: String) -> Bool {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{")
            && trimmed.hasSuffix("}")
    }

    private nonisolated func temporalAnswerContradictsContext(
        _ answer: String,
        temporalEvidence: AgentRunEvidenceRecord
    ) -> Bool {
        guard let currentDate = temporalEvidence.stringMetadata("currentDate"),
              let currentYear = currentDate.split(separator: "-").first.map(String.init) else {
            return false
        }
        guard let regex = try? NSRegularExpression(pattern: #"\b(19|20)\d{2}\b"#) else {
            return false
        }
        let range = NSRange(answer.startIndex..<answer.endIndex, in: answer)
        let years = regex.matches(in: answer, range: range).compactMap { match -> String? in
            guard let valueRange = Range(match.range, in: answer) else { return nil }
            return String(answer[valueRange])
        }
        return years.contains { $0 != currentYear }
    }

    private nonisolated static func finalAnswer(from events: [AgentKernelModelAdapterEventV2]) -> AgentKernelFinalAnswerV2? {
        for event in events.reversed() {
            switch event {
            case .finalAnswer(let answer):
                let trimmed = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return AgentKernelFinalAnswerV2(text: trimmed, grounding: answer.grounding)
                }
            case .snapshot(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return AgentKernelFinalAnswerV2(text: trimmed)
                }
            case .toolCall, .malformedOutput, .emptyOutput, .timedOut:
                continue
            }
        }
        return nil
    }

    private nonisolated static func firstToolCall(from events: [AgentKernelModelAdapterEventV2]) -> AgentKernelToolCallV2? {
        for event in events {
            if case .toolCall(let call) = event {
                return call
            }
        }
        return nil
    }

    private nonisolated func toolMetadata(_ call: AgentKernelToolCallV2) -> [String: AgentRunMetadataValue] {
        var metadata: [String: AgentRunMetadataValue] = ["toolName": .string(call.name)]
        for (key, value) in call.arguments {
            metadata["argument.\(key)"] = .string(value)
        }
        return metadata
    }
}
