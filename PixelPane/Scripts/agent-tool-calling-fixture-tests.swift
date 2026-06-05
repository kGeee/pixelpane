import Foundation

enum AgentToolCallingFixtureHarness {
    struct HarnessError: Error, CustomStringConvertible {
        let description: String
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw HarnessError(description: message)
        }
    }

    // Phase A: behavior-preserving extraction of the loop-control decisions.
    // Pins the current no-progress semantics so Phase B can change them deliberately.
    static func testToolLoopControllerNoProgressDecisions() async throws {
        var controller = AgentToolLoopController(maxIterations: 12)

        // registerToolCall returns the count seen before this call and increments.
        try expect(controller.registerToolCall(signature: "read_file:path=a") == 0, "first registration should report 0 prior")
        try expect(controller.registerToolCall(signature: "read_file:path=a") == 1, "second registration should report 1 prior")
        try expect(controller.registerToolCall(signature: "read_file:path=b") == 0, "distinct signature should report 0 prior")

        // A succeeded result is never a repeated failing call, regardless of priors.
        try expect(controller.isRepeatedFailingCall(status: .succeeded, priorCount: 5) == false, "succeeded is never repeated-failing")
        // A first-time failure is not yet "repeated".
        try expect(controller.isRepeatedFailingCall(status: .failed, priorCount: 0) == false, "first failure is not repeated")
        try expect(controller.isRepeatedFailingCall(status: .failed, priorCount: 1) == true, "failure after a prior call is repeated")

        // No-progress guard halts once the same call signature is issued a third
        // time, regardless of success/failure: re-issuing an identical call makes
        // no progress (chat1/chat2 repeated-read loop).
        try expect(controller.noProgressDecision(status: .failed, priorCount: 0) == .continue(repeatedFailingCall: false), "first failure continues")
        try expect(controller.noProgressDecision(status: .failed, priorCount: 1) == .continue(repeatedFailingCall: true), "second failure continues but flags repeat")
        try expect(controller.noProgressDecision(status: .failed, priorCount: 2) == .halt, "third repeated failure halts")
        try expect(controller.noProgressDecision(status: .succeeded, priorCount: 0) == .continue(repeatedFailingCall: false), "first success continues")
        try expect(controller.noProgressDecision(status: .succeeded, priorCount: 1) == .continue(repeatedFailingCall: false), "second identical success continues")
        try expect(controller.noProgressDecision(status: .succeeded, priorCount: 2) == .halt, "third identical successful call halts (no new information)")

        // Terminal-block reason reflects the configured cap.
        try expect(controller.maxIterationsBlockReason().contains("12"), "max-iterations reason names the cap")
        try expect(controller.noProgressBlockReason(summary: "boom").contains("boom"), "no-progress reason includes the result summary")
    }

    @MainActor
    static func run() async throws {
        try await testToolLoopControllerNoProgressDecisions()
        try await testTaskProfileClassifiesOperationIntent()
        try await testTaskFrameBuilderUsesStructuralSources()
        try await testModelRequestedProcessSnapshotRecordsEvidence()
        try await testTierBGeneralGroundingCompletesWithoutEvidence()
        try await testNativeTierBFinalAnswerDoesNotRequireTextProtocolGrounding()
        try await testCurrentTimeQuestionRecordsTemporalContextForNativeTools()
        try await testTierBUngroundedAnswerWithoutEvidenceBlocksAfterRepair()
        try await testDeclaredProcessGroundingNeedsSnapshotEvidence()
        try await testFolderEvidenceCannotSupportListenerGrounding()
        try await testModelRequestedListenerSnapshotRecordsEvidence()
        try await testToolLoopListsGrantedFolderAndContinues()
        try await testFileListingClaimGroundsFolderAnswer()
        try await testApproximateLocationContextGroundsLocationClaims()
        try await testEmptyLocalEvidenceClaimsRepairToListingClaim()
        try await testEvidenceBackfillReadsCitedPathAndRecovers()
        try await testEvidenceBackfillRunsListenerSnapshotForFabricatedClaim()
        try await testEmbeddedToolCallInAnswerTextIsExecuted()
        try await testGrantNameReferencesClassifyAsLocalState()
        try await testSearchAndReadToolsRecordEvidence()
        try await testQuotedSearchUsesPreciseQuery()
        try await testMultipleQuotedSearchesCreateSeparateEvidence()
        try await testSensitiveSearchFallsBackToFilenameOnly()
        try await testVisualAttachmentRecordsEvidenceAndPromptContext()
        try await testEvidencePlannerReadsScopedContentForReferencedEntity()
        try await testEmptyResolvedDirectoryListingIsAnswerEvidence()
        try await testGrantDiscoveryUsesInventoryEvidenceWithoutReadingFiles()
        try await testRuntimeCapabilityQuestionDoesNotSearchLocalFiles()
        try await testModelRequestedSearchAcrossAllGrants()
        try await testFollowUpReferenceIsModelToolResolved()
        try await testConversationHistoryQuestionDoesNotSearchLocalFiles()
        try await testLargestHTMLSelectionDoesNotRequireCommandEvidence()
        try await testSelectedDirectoryContentNeedsReadEvidence()
        try await testReadOnlyExperienceQuestionIsNotSideEffectGated()
        try await testFolderListingObservationIncludesByteCounts()
        try await testBlindLocalFinalAnswerIsRejectedUntilEvidenceExists()
        try await testNoTargetQuestionDoesNotGatherBlindEvidence()
        try await testLocalFileAnswerMustUseRecordedContent()
        try await testLargeReadObservationIsBudgeted()
        try await testBroadSearchObservationIsBudgeted()
        try await testContextOverflowRepackagesBeforeFailure()
        try await testWriteProposalApprovalExecutesAndContinues()
        try await testApprovalContinuationUsesDurableReplayContext()
        try await testWriteRequestCannotCompleteFromReadEvidenceOnly()
        try await testRequiredWriteToolNonAdherenceBlocksBeforeIterationCap()
        try await testWriteProposalCanStillBeStagedWithoutPreclassifiedEditIntent()
        try await testStructuredOutputFailureBlocksWithRecoveryGuidance()
        try await testInvalidToolCallRetriesBeforeEvidence()
        try await testInvalidToolCallAfterEvidenceRecoversToFinalAnswer()
        try await testUnobservedFinalAnswerPathsRepairThroughTools()
        try await testSpecificGrantBeatsBroadGrantForRandomTests()
        try await testMissingWriteParentIsRejectedBeforeApproval()
        try await testApprovedWriteFailureContinuesWithObservation()
        try await testDeniedWriteDoesNotExecute()
        try await testDeniedCommandUsesGenericSideEffectProjection()
        try await testApprovedFiniteCommandExecutesAndContinues()
        try await testApprovedFiniteCommandFailureContinuesWithObservation()
    }

    @MainActor
    private static func testTaskProfileClassifiesOperationIntent() async throws {
        let harness = try await makeHarness(prefix: "task-profile")
        let adapter = FixtureAgentKernelAdapter(responses: [])
        let readOnly = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)
        let proposal = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        let broadInspect = AgentRunTaskProfile.classify(
            userMessage: "can you inspect the local portfolio?",
            tools: readOnly.tools,
            context: readOnly.context
        )
        try expect(!broadInspect.isLocalStateRequest, "broad local wording alone should not require local evidence")
        try expect(!broadInspect.isSideEffectRequest, "broad local wording should not be side-effect gated")
        try expect(!broadInspect.requiredSideEffectToolNames.contains("run_finite_command"), "local wording alone should not require command evidence")

        let explicitInspect = AgentRunTaskProfile.classify(
            userMessage: "can you inspect \(harness.workspace.path)?",
            tools: readOnly.tools,
            context: readOnly.context
        )
        try expect(explicitInspect.isLocalStateRequest, "explicit granted path should be recognized as local-state work")
        try expect(!explicitInspect.isSideEffectRequest, "explicit local inspection should not be side-effect gated")

        let write = AgentRunTaskProfile.classify(
            userMessage: "create notes.txt in this folder",
            tools: proposal.tools,
            context: proposal.context
        )
        try expect(!write.isSideEffectRequest, "free-form write wording alone should not be side-effect gated")
        try expect(!write.isEditRequest, "free-form write wording alone should not create edit preflight")
        try expect(write.requiredSideEffectToolNames.isEmpty, "free-form write wording alone should not require a write proposal")

        let structuralWrite = AgentRunTaskProfile.classify(
            userMessage: """
            operation: create
            targetPath: \(harness.workspace.appendingPathComponent("notes.txt").path)
            """,
            tools: proposal.tools,
            context: proposal.context
        )
        try expect(structuralWrite.isSideEffectRequest, "structural write constraints should be side-effect gated")
        try expect(structuralWrite.isEditRequest, "structural write constraints should create edit preflight")
        try expect(structuralWrite.requiredSideEffectToolNames == ["stage_write_proposal"], "structural write constraints should require the write proposal tool")

        let processAndSave = AgentRunTaskProfile.classify(
            userMessage: "collect a process inventory and save it to processes.txt",
            tools: proposal.tools,
            context: proposal.context
        )
        try expect(!processAndSave.isLocalStateRequest, "free-form process wording should reach the model before any local system-state tool runs")
        try expect(!processAndSave.isSideEffectRequest, "free-form observation-and-save wording alone should not be mutating side-effect gated")
        try expect(processAndSave.requiredSideEffectToolNames.isEmpty, "free-form observation-and-save wording alone should not require write or shell side-effect tools")
        try expect(processAndSave.taskFrame.evidenceRequests.isEmpty, "free-form process wording should not create deterministic process snapshot preflight")
    }

    @MainActor
    private static func testTaskFrameBuilderUsesStructuralSources() async throws {
        let harness = try await makeHarness(prefix: "task-frame-builder")
        let adapter = FixtureAgentKernelAdapter(responses: [])
        let readOnly = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)
        let proposal = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)
        let noteURL = harness.workspace.appendingPathComponent("note.txt")
        try "needle from the granted note".write(to: noteURL, atomically: true, encoding: .utf8)
        let sessionID = UUID()
        let runID = UUID()
        let pendingWait = AgentRunWaitRecord(
            sessionID: sessionID,
            runID: runID,
            kind: .approval,
            prompt: AgentRunText("Approve file write.")
        )
        let completedSideEffect = AgentRunSideEffectRecord(
            sessionID: sessionID,
            runID: runID,
            kind: .fileWrite,
            status: .completed,
            metadata: ["targetPath": .string(noteURL.path)]
        )
        let attachment = AgentKernelModelAttachment(
            modality: .text,
            label: "Captured OCR",
            metadata: [
                "source": .string("capture"),
                "hasOCRText": .bool(true),
                "ocrText": .string("Visible OCR text")
            ]
        )

        let frame = AgentTaskFrame.build(
            userMessage: #"Please summarize \#(noteURL.path) and search for "needle""#,
            tools: readOnly.tools,
            context: readOnly.context,
            providerTier: .tierAFullAgent,
            attachments: [attachment],
            selectedAction: "ask",
            contextID: "task-frame-builder",
            contextKind: "assistant",
            pendingWaits: [pendingWait],
            completedSideEffects: [completedSideEffect]
        )

        try expect(frame.selectedAction == "ask", "task frame should preserve selected action")
        try expect(frame.contextKind == "assistant", "task frame should preserve app context kind")
        try expect(frame.localGrants == [harness.grant], "task frame should snapshot local grants")
        try expect(frame.localReferences.contains(where: { reference in
            reference.path == noteURL.path
                && reference.source == .explicitAbsolutePath
                && reference.exists == true
        }), "absolute granted path should become a structural local reference")
        try expect(frame.quotedSearchTerms == ["needle"], "quoted search terms should be preserved exactly")
        try expect(frame.visualContext?.hasOCRText == true, "OCR attachment metadata should become visual context")
        try expect(frame.pendingWaits.map(\.waitID) == [pendingWait.waitID], "pending waits should be included in the task frame")
        try expect(frame.completedSideEffects.map(\.sideEffectID) == [completedSideEffect.sideEffectID], "completed side effects should be included in the task frame")
        try expect(frame.evidenceRequests.contains(where: { $0.kind == .exactSearch && $0.query == "needle" }), "exact quoted search should be a typed evidence request")
        try expect(frame.diagnostics.contains(where: { $0 == "selectedAction=ask" }), "task frame diagnostics should explain structural sources")

        let broadPromptFrame = AgentTaskFrame.build(
            userMessage: "Please save a summary about local files and terminal commands.",
            tools: proposal.tools,
            context: proposal.context
        )
        try expect(broadPromptFrame.writeRequest == nil, "broad write wording without a target should not create a write request")
        try expect(broadPromptFrame.explicitCommandDraft == nil, "broad terminal wording without command syntax should not create a command draft")
        try expect(broadPromptFrame.localReferences.isEmpty, "broad local wording should not create structural local references")
        try expect(!broadPromptFrame.requiresWriteProposal, "broad write wording should not require a write proposal")
        try expect(!broadPromptFrame.requiresCommandEvidence, "broad command wording should not require command evidence")

        let writeFrame = AgentTaskFrame.build(
            userMessage: """
            operation: create
            targetPath: \(harness.workspace.appendingPathComponent("notes.txt").path)
            """,
            tools: proposal.tools,
            context: proposal.context
        )
        try expect(writeFrame.writeRequest?.operation == .create, "explicit create target should preserve write operation")
        try expect(writeFrame.writeRequest?.targetPath == harness.workspace.appendingPathComponent("notes.txt").path, "explicit create target should preserve target path")
        try expect(writeFrame.localReferences.contains(where: { $0.source == .explicitWriteTarget }), "write target should be a structural local reference")
    }

    @MainActor
    private static func testModelRequestedProcessSnapshotRecordsEvidence() async throws {
        let harness = try await makeHarness(prefix: "tool-process-snapshot")
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(name: "get_process_snapshot", arguments: ["limit": "5"], reason: nil),
                .finalAnswer("The process snapshot was collected.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "Use the process snapshot capability.",
            context: AgentRunViewContext(title: "Process Snapshot", contextID: "tool-process-snapshot", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let requests = await adapter.requests()
        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(requests.count >= 2, "process snapshot should return an observation to the model before final answer")
        try expect(requests.first?.messages.contains(where: { $0.role == .observation && $0.content.contains("Process snapshot") }) == false, "process snapshot should not run before the first model request")
        try expect(requests.first?.tools.contains(where: { $0.name == "get_process_snapshot" }) == true, "typed process snapshot should be model-visible")
        try expect(requests.first?.tools.contains(where: { $0.name == "run_finite_command" }) == false, "raw shell should not be model-visible in read-only process questions")
        try expect(requests.last?.messages.contains(where: { $0.role == .observation && $0.content.contains("Process snapshot") }) == true, "model continuation should receive process snapshot observation")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.processSnapshot.rawValue && ($0.metadata["rowCount"]?.intValue ?? 0) > 0 }), "process snapshot evidence should be recorded with rows")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.commandOutput.rawValue }), "typed process snapshot should not record command-output evidence")
        try expect(harness.viewModel.state.activeStatus == .completed, "process snapshot run should complete")
    }

    @MainActor
    private static func testTierBGeneralGroundingCompletesWithoutEvidence() async throws {
        let harness = try await makeHarness(prefix: "grounding-general")
        let adapter = tierBFixtureAdapter(
            responses: [
                groundedFinalAnswer(
                    "This response does not depend on recorded local evidence.",
                    basis: .generalKnowledge
                )
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "Give a general answer.",
            context: AgentRunViewContext(title: "Grounding General", contextID: "grounding-general", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use the structured protocol.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(harness.viewModel.state.activeStatus == .completed, "general grounding should complete without local evidence")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.finalAnswerSupport.rawValue }), "general answer should not fabricate local support evidence")
    }

    @MainActor
    private static func testNativeTierBFinalAnswerDoesNotRequireTextProtocolGrounding() async throws {
        let harness = try await makeHarness(prefix: "native-grounding")
        let target = nativeMLXConformanceTarget(
            modelID: "fixture/native-mlx-grounding",
            modelPath: "/tmp/native-mlx-grounding"
        )
        let profile = nativeMLXConformanceProfile(target: target)
        let adapter = nativeMLXFixtureAdapter(
            target: target,
            responses: [
                .finalAnswer("I can answer using the native tool protocol without a text-protocol grounding envelope.")
            ]
        )
        let config = toolConfig(
            grant: harness.grant,
            runMode: .readOnly,
            adapter: adapter,
            modelConformanceProfile: profile
        )

        let runID = try await harness.viewModel.startRun(
            userMessage: "Give a normal answer.",
            context: AgentRunViewContext(title: "Native Grounding", contextID: "native-grounding", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            modelConformanceProfile: profile,
            systemPrompt: "Use tools when available.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let requests = await adapter.requests()
        let trace = try await harness.store.traceProjection(runID: runID)
        let diagnostics = trace.events.compactMap { event -> String? in
            guard event.kind == .providerDiagnostic,
                  case .diagnostic(let text) = event.payload else { return nil }
            return text.text
        }.joined(separator: "\n")

        try expect(harness.viewModel.state.activeStatus == .completed, "native Tier B final answer should complete without text-protocol grounding metadata")
        try expect(requests.count == 1, "native answer should not get a text-protocol grounding repair attempt")
        try expect(requests.first?.responseFormat == .native, "profile-backed local MLX should use native tool protocol")
        try expect(!diagnostics.contains("Tool-capable final answers without local evidence"), "native tool protocol should not require text-protocol grounding fields")
    }

    @MainActor
    private static func testCurrentTimeQuestionRecordsTemporalContextForNativeTools() async throws {
        let harness = try await makeHarness(prefix: "native-time-context")
        let target = nativeMLXConformanceTarget(
            modelID: "fixture/native-mlx-time",
            modelPath: "/tmp/native-mlx-time"
        )
        let profile = nativeMLXConformanceProfile(target: target)
        let adapter = nativeMLXFixtureAdapter(
            target: target,
            responses: [
                .finalAnswer("The current time is available from the app-owned temporal context.")
            ]
        )
        let config = toolConfig(
            grant: harness.grant,
            runMode: .readOnly,
            adapter: adapter,
            modelConformanceProfile: profile
        )

        let runID = try await harness.viewModel.startRun(
            userMessage: "whats the time",
            context: AgentRunViewContext(title: "Native Time", contextID: "native-time-context", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            modelConformanceProfile: profile,
            systemPrompt: "Use app-owned temporal context for current time.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let firstRequest = await adapter.requests().first
        let observations = firstRequest?.messages.filter { $0.role == .observation }.map(\.content).joined(separator: "\n") ?? ""

        try expect(harness.viewModel.state.activeStatus == .completed, "current-time question should complete with temporal evidence")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.temporalContext.rawValue }), "current-time question should record temporal.context evidence")
        try expect(observations.contains("App-owned temporal context"), "model should receive temporal context before answering")
        try expect(observations.contains("localTime:"), "temporal observation should include local time")
    }

    @MainActor
    private static func testTierBUngroundedAnswerWithoutEvidenceBlocksAfterRepair() async throws {
        let harness = try await makeHarness(prefix: "grounding-missing")
        let adapter = tierBFixtureAdapter(
            responses: [
                .finalAnswer("Unsupported first answer."),
                .finalAnswer("Unsupported second answer.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        _ = try await harness.viewModel.startRun(
            userMessage: "Answer with the available protocol.",
            context: AgentRunViewContext(title: "Grounding Missing", contextID: "grounding-missing", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use the structured protocol.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let requests = await adapter.requests()
        try expect(requests.count == 2, "ungrounded Tier B answer should get one repair attempt")
        try expect(harness.viewModel.state.activeStatus == .blocked, "ungrounded Tier B answer should block after bounded repair")
    }

    @MainActor
    private static func testDeclaredProcessGroundingNeedsSnapshotEvidence() async throws {
        let harness = try await makeHarness(prefix: "grounding-process")
        let processGrounding = AgentKernelAnswerGrounding(
            basis: .localEvidence,
            claims: [AgentKernelAnswerClaim(kind: .processSnapshot)]
        )
        let adapter = tierBFixtureAdapter(
            responses: [
                groundedFinalAnswer("Unsupported before evidence.", grounding: processGrounding),
                .toolCall(name: "get_process_snapshot", arguments: ["limit": "3"], reason: nil),
                groundedFinalAnswer("Supported after evidence.", grounding: processGrounding)
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "Use recorded state to answer.",
            context: AgentRunViewContext(title: "Grounding Process", contextID: "grounding-process", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use the structured protocol.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let requests = await adapter.requests()
        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(requests.count >= 3, "unsupported process grounding should return to the model before tool use")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.processSnapshot.rawValue }), "process grounding should be satisfied by process snapshot evidence")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.finalAnswerSupport.rawValue }), "supported declared process grounding should record final-answer support")
        try expect(harness.viewModel.state.activeStatus == .completed, "declared process grounding should complete after matching evidence")
    }

    @MainActor
    private static func testFolderEvidenceCannotSupportListenerGrounding() async throws {
        let harness = try await makeHarness(prefix: "grounding-listener-relevance")
        try "fixture".write(to: harness.workspace.appendingPathComponent("fixture.txt"), atomically: true, encoding: .utf8)
        let listenerGrounding = AgentKernelAnswerGrounding(
            basis: .localEvidence,
            claims: [AgentKernelAnswerClaim(kind: .localListeners)]
        )
        let adapter = tierBFixtureAdapter(
            responses: [
                .toolCall(name: "list_folder", arguments: ["path": harness.workspace.path], reason: nil),
                groundedFinalAnswer("Unsupported by folder evidence.", grounding: listenerGrounding),
                groundedFinalAnswer("Still unsupported by folder evidence.", grounding: listenerGrounding)
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "Use recorded state to answer.",
            context: AgentRunViewContext(title: "Grounding Listener Relevance", contextID: "grounding-listener-relevance", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use the structured protocol.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.folderList.rawValue }), "folder evidence should be recorded")
        // The invariant: folder evidence alone never supports listener
        // claims. With claim-kind backfill the runtime now takes a REAL
        // listener snapshot for the unverifiable claim and the run recovers —
        // any listener evidence must come from that backfill, never from
        // reinterpreting folder evidence.
        let listenerEvidence = trace.evidence.filter { $0.kind == AgentEvidenceKind.localServer.rawValue }
        let backfillObservations = trace.controlRecords.filter { record in
            record.kind == .toolObservation && record.metadata["source"]?.stringValue == "evidence_backfill"
        }
        try expect(!listenerEvidence.isEmpty, "backfill should record a real listener snapshot for the unverifiable claim")
        try expect(!backfillObservations.isEmpty, "the listener snapshot must come from marked runtime backfill, not folder evidence")
        try expect(harness.viewModel.state.activeStatus == .completed, "the re-declared claim should verify against the backfilled snapshot")
    }

    @MainActor
    private static func testFileListingClaimGroundsFolderAnswer() async throws {
        // A "what is in my folder?" answer is a discovery claim: it must be
        // groundable by folder-list evidence via the file_listing claim kind.
        let harness = try await makeHarness(prefix: "grounding-file-listing")
        try "fixture".write(to: harness.workspace.appendingPathComponent("fixture.txt"), atomically: true, encoding: .utf8)
        let listingGrounding = AgentKernelAnswerGrounding(
            basis: .localEvidence,
            claims: [AgentKernelAnswerClaim(kind: .fileListing, target: harness.workspace.path)]
        )
        let adapter = tierBFixtureAdapter(
            responses: [
                .toolCall(name: "list_folder", arguments: ["path": harness.workspace.path], reason: nil),
                groundedFinalAnswer("The folder contains fixture.txt.", grounding: listingGrounding)
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "What is in my folder?",
            context: AgentRunViewContext(title: "Grounding File Listing", contextID: "grounding-file-listing", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use the structured protocol.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.folderList.rawValue }), "folder evidence should be recorded")
        try expect(harness.viewModel.state.activeStatus == .completed, "file_listing claim backed by folder-list evidence should complete")
    }

    @MainActor
    private static func testApproximateLocationContextGroundsLocationClaims() async throws {
        // When the app provides consented approximate location, the runtime
        // must record it as evidence, surface it to the model as a preflight
        // observation, and accept location_context grounding claims.
        let harness = try await makeHarness(prefix: "grounding-location")
        let adapter = tierBFixtureAdapter(
            responses: [
                groundedFinalAnswer(
                    "Tomorrow in Los Angeles should be sunny.",
                    grounding: AgentKernelAnswerGrounding(
                        basis: .localEvidence,
                        claims: [AgentKernelAnswerClaim(kind: .locationContext)]
                    )
                )
            ]
        )
        let config = toolConfig(
            grants: [harness.grant],
            runMode: .readOnly,
            adapter: adapter,
            approximateLocation: AgentLocationContext(city: "Los Angeles", region: "CA", countryCode: "US")
        )

        let runID = try await harness.viewModel.startRun(
            userMessage: "What is the weather tomorrow?",
            context: AgentRunViewContext(title: "Grounding Location", contextID: "grounding-location", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use the structured protocol.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let requests = await adapter.requests()
        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(
            trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.locationContext.rawValue && $0.metadata["city"] == .string("Los Angeles") }),
            "consented approximate location should be recorded as evidence"
        )
        try expect(
            requests.first?.messages.contains(where: { $0.role == .observation && $0.content.contains("App-owned approximate location") }) == true,
            "model should receive the approximate-location observation"
        )
        try expect(harness.viewModel.state.activeStatus == .completed, "location_context claim backed by recorded location evidence should complete")
    }

    @MainActor
    private static func testEmptyLocalEvidenceClaimsRepairToListingClaim() async throws {
        // Replays the cloud chat1 failure: local_evidence with claims:[] is
        // rejected, but the repair observation must teach the claim
        // vocabulary so a compliant model can fix its declaration and finish.
        let harness = try await makeHarness(prefix: "grounding-empty-claims")
        try "fixture".write(to: harness.workspace.appendingPathComponent("fixture.txt"), atomically: true, encoding: .utf8)
        let adapter = tierBFixtureAdapter(
            responses: [
                .toolCall(name: "list_folder", arguments: ["path": harness.workspace.path], reason: nil),
                groundedFinalAnswer("The folder contains fixture.txt.", basis: .localEvidence),
                groundedFinalAnswer(
                    "The folder contains fixture.txt.",
                    grounding: AgentKernelAnswerGrounding(
                        basis: .localEvidence,
                        claims: [AgentKernelAnswerClaim(kind: .fileListing, target: harness.workspace.path)]
                    )
                )
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "What is in my folder?",
            context: AgentRunViewContext(title: "Grounding Empty Claims", contextID: "grounding-empty-claims", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use the structured protocol.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let repairMessages = trace.controlRecords.compactMap { record -> String? in
            guard record.kind == .finalAnswerRepairObservation,
                  case .modelMessage(let message) = record.payload else { return nil }
            return message.content
        }
        try expect(repairMessages.contains(where: { $0.contains("file_listing") }), "repair observation should name the claim kind vocabulary")
        try expect(harness.viewModel.state.activeStatus == .completed, "declaring file_listing after the repair observation should complete the run")
    }

    @MainActor
    private static func testEvidenceBackfillRunsListenerSnapshotForFabricatedClaim() async throws {
        // Replays the cloud listener fabrication: the model declared
        // local_listeners without ever calling the snapshot tool. The claim
        // kind maps deterministically to a read-only tool, so the runtime
        // takes the snapshot itself and retries instead of blocking.
        let harness = try await makeHarness(prefix: "backfill-listener")
        let listenerClaim = AgentKernelAnswerGrounding(
            basis: .localEvidence,
            claims: [AgentKernelAnswerClaim(kind: .localListeners)]
        )
        let adapter = tierBFixtureAdapter(
            responses: [
                groundedFinalAnswer("Your site is not running on any localhost port.", grounding: listenerClaim),
                groundedFinalAnswer("Your site is not running on any localhost port.", grounding: listenerClaim)
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "Is my site running on a localhost port?",
            context: AgentRunViewContext(title: "Backfill Listener", contextID: "backfill-listener", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use the structured protocol.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let backfillObservations = trace.controlRecords.filter { record in
            record.kind == .toolObservation && record.metadata["source"]?.stringValue == "evidence_backfill"
        }
        try expect(
            trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.localServer.rawValue }),
            "backfill should record a listener snapshot for the fabricated claim"
        )
        try expect(!backfillObservations.isEmpty, "backfill snapshot observation should be durable with its source marked")
        try expect(harness.viewModel.state.activeStatus == .completed, "the re-declared claim should verify against the backfilled snapshot")
    }

    @MainActor
    private static func testEmbeddedToolCallInAnswerTextIsExecuted() async throws {
        // Replays the Hermes deflection: the model wrote the read_file
        // tool-call JSON inside its answer text and told the user to run it.
        // A schema-valid call to an available read-only tool is a protocol
        // message in the wrong channel; the runtime executes it as the
        // intended action instead of accepting a non-answer.
        let harness = try await makeHarness(prefix: "embedded-tool-call")
        let cited = harness.workspace.appendingPathComponent("styles.css")
        try ":root { --ink: #0b0b0c; }".write(to: cited, atomically: true, encoding: .utf8)
        let citedPath = cited.path

        let deflection = """
        To view the colors, you can use the read_file tool. Here's how:

        ```json
        {
          "name": "read_file",
          "arguments": {
            "path": "\(citedPath)"
          }
        }
        ```

        This will return the content of the file.
        """
        let adapter = tierBFixtureAdapter(
            responses: [
                .finalAnswer(deflection),
                groundedFinalAnswer(
                    "The background color is #0b0b0c.",
                    grounding: AgentKernelAnswerGrounding(
                        basis: .localEvidence,
                        claims: [AgentKernelAnswerClaim(kind: .localFile, target: citedPath)]
                    )
                )
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "What is the background color?",
            context: AgentRunViewContext(title: "Embedded Tool Call", contextID: "embedded-tool-call", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use the structured protocol.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(
            trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue && $0.metadata["path"]?.stringValue == citedPath }),
            "the embedded read_file call should be executed and recorded as evidence"
        )
        try expect(
            harness.viewModel.state.messages.last?.text.text.contains("#0b0b0c") == true,
            "the follow-up answer should use the read content, not the deflection"
        )
        try expect(harness.viewModel.state.activeStatus == .completed, "the run should complete after executing the embedded call")
    }

    @MainActor
    private static func testGrantNameReferencesClassifyAsLocalState() async throws {
        // Replays chat1 (7B): "whats the color scheme of the pixelpane site?"
        // referenced the user's "pixel-pane-site" grant, but exact-string
        // matching missed it, so the question was never classified as
        // local-state and a fabricated answer completed. Grant names match
        // normalized (case/separator-folded) token runs — identifiers the
        // user declared, never shipped vocabulary.
        let harness = try await makeHarness(prefix: "grant-name-classify")
        let site = harness.workspace.appendingPathComponent("pixel-pane-site", isDirectory: true)
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        let siteGrant = AgentLocalFileGrant(path: site.path, isDirectory: true)
        let adapter = FixtureAgentKernelAdapter(responses: [])
        let config = toolConfig(grants: [siteGrant], runMode: .readOnly, adapter: adapter)

        let fuzzyReference = AgentRunTaskProfile.classify(
            userMessage: "whats the color scheme of the pixelpane site?",
            tools: config.tools,
            context: config.context
        )
        try expect(fuzzyReference.isLocalStateRequest, "separator-folded grant name references should classify as local-state")
        try expect(
            fuzzyReference.taskFrame.localReferences.contains(where: { $0.path == site.path }),
            "the fuzzy reference should resolve to the named grant"
        )

        let spacedReference = AgentRunTaskProfile.classify(
            userMessage: "describe my pixel pane site for me",
            tools: config.tools,
            context: config.context
        )
        try expect(spacedReference.isLocalStateRequest, "spaced grant name references should classify as local-state")

        let unrelated = AgentRunTaskProfile.classify(
            userMessage: "what is the latest news about swift concurrency?",
            tools: config.tools,
            context: config.context
        )
        try expect(!unrelated.isLocalStateRequest, "questions that never reference a grant must stay unclassified (no blind evidence)")
        try expect(unrelated.taskFrame.localReferences.isEmpty, "no grant reference should be fabricated from unrelated wording")
    }

    @MainActor
    private static func testEvidenceBackfillReadsCitedPathAndRecovers() async throws {
        // Replays chat2 (Hermes): the model cites a granted file it never
        // read. Instead of rejecting twice and blocking, the runtime reads
        // the cited path itself (grant-covered, read-only), records the
        // evidence, and retries once — turning the block into an answer.
        let harness = try await makeHarness(prefix: "evidence-backfill")
        let cited = harness.workspace.appendingPathComponent("style.css")
        try "body { background: #0b0b0c; }".write(to: cited, atomically: true, encoding: .utf8)
        let citedPath = cited.path

        let adapter = tierBFixtureAdapter(
            responses: [
                groundedFinalAnswer(
                    "Check \(citedPath) for the colors.",
                    basis: .localEvidence,
                    claims: [AgentKernelAnswerClaim(kind: .localFile, target: citedPath)]
                ),
                groundedFinalAnswer(
                    "The background color is #0b0b0c, per \(citedPath).",
                    grounding: AgentKernelAnswerGrounding(
                        basis: .localEvidence,
                        claims: [AgentKernelAnswerClaim(kind: .localFile, target: citedPath)]
                    )
                )
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "What is the background color?",
            context: AgentRunViewContext(title: "Evidence Backfill", contextID: "evidence-backfill", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use the structured protocol.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let backfillObservations = trace.controlRecords.filter { record in
            record.kind == .toolObservation && record.metadata["source"]?.stringValue == "evidence_backfill"
        }
        try expect(
            trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue && $0.metadata["path"]?.stringValue == citedPath }),
            "backfill should record file-read evidence for the cited path"
        )
        try expect(!backfillObservations.isEmpty, "backfill observation should be durable with its source marked")
        try expect(harness.viewModel.state.activeStatus == .completed, "backfilled evidence should let the corrected answer complete")
    }

    @MainActor
    private static func testModelRequestedListenerSnapshotRecordsEvidence() async throws {
        let harness = try await makeHarness(prefix: "tool-listener-snapshot")
        let listenerGrounding = AgentKernelAnswerGrounding(
            basis: .localEvidence,
            claims: [AgentKernelAnswerClaim(kind: .localListeners, target: "1")]
        )
        let adapter = tierBFixtureAdapter(
            responses: [
                .toolCall(name: "get_local_listener_snapshot", arguments: ["port": "1", "limit": "5"], reason: nil),
                groundedFinalAnswer("Listener snapshot was recorded.", grounding: listenerGrounding)
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "Use recorded state to answer.",
            context: AgentRunViewContext(title: "Listener Snapshot", contextID: "tool-listener-snapshot", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use the structured protocol.",
            timeout: 4
        )
        try await harness.viewModel.waitForIdle(timeout: 6)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.localServer.rawValue && $0.metadata["requestedPort"] == .int(1) }), "listener snapshot should record server.local evidence")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.finalAnswerSupport.rawValue }), "listener grounding should record final-answer support")
        try expect(harness.viewModel.state.activeStatus == .completed, "listener snapshot run should complete")
    }

    @MainActor
    private static func testToolLoopListsGrantedFolderAndContinues() async throws {
        let harness = try await makeHarness(prefix: "tool-list")
        try "alpha".write(to: harness.workspace.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: harness.workspace.appendingPathComponent("beta.txt"), atomically: true, encoding: .utf8)
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(name: "list_folder", arguments: ["path": harness.workspace.path], reason: "Need folder contents."),
                .finalAnswer("The folder contains alpha.txt and beta.txt.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "what is inside the folder?",
            context: AgentRunViewContext(title: "Tool List", contextID: "tool-list", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        try expect(harness.viewModel.state.activeStatus == .completed, "folder listing run should complete")
        try expect(harness.viewModel.state.messages.map(\.text.text).contains("The folder contains alpha.txt and beta.txt."), "final answer should project")
        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(trace.steps.contains(where: { $0.kind == .toolRequest }), "trace should include tool request step")
        try expect(trace.steps.contains(where: { $0.kind == .toolResult }), "trace should include tool result step")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.folderList.rawValue }), "folder listing should record evidence")
        let lastRequest = await adapter.lastRequest()
        try expect(lastRequest?.messages.contains(where: { $0.role == .observation && $0.content.contains("alpha.txt") }) == true, "second model request should include tool observation")
    }

    @MainActor
    private static func testSearchAndReadToolsRecordEvidence() async throws {
        let harness = try await makeHarness(prefix: "tool-search")
        let profile = harness.workspace.appendingPathComponent("index.html")
        try """
        <html>
        <body>
        <h1>Snehith Nayak</h1>
        <p>Experience: AI engineering, Swift apps, and agent tooling.</p>
        </body>
        </html>
        """.write(to: profile, atomically: true, encoding: .utf8)
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(name: "search_files", arguments: ["query": "experience"], reason: nil),
                .toolCall(name: "read_file", arguments: ["path": "index.html"], reason: nil),
                .finalAnswer("The page says the experience includes AI engineering, Swift apps, and agent tooling.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "what experience is described in the granted site files?",
            context: AgentRunViewContext(title: "Tool Search", contextID: "tool-search", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(harness.viewModel.state.activeStatus == .completed, "search/read run should complete")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileSearch.rawValue }), "search should record evidence")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue }), "read should record evidence")
        try expect(harness.viewModel.state.messages.last?.text.text.contains("AI engineering") == true, "final answer should use file evidence")
    }

    @MainActor
    private static func testQuotedSearchUsesPreciseQuery() async throws {
        let harness = try await makeHarness(prefix: "tool-quoted-search")
        try "Experience: focused search term.".write(
            to: harness.workspace.appendingPathComponent("profile.txt"),
            atomically: true,
            encoding: .utf8
        )
        let adapter = FixtureAgentKernelAdapter(
            responses: [.finalAnswer("I found the quoted term.")]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: #"search every granted folder for "Experience""#,
            context: AgentRunViewContext(title: "Quoted Search", contextID: "tool-quoted-search", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(harness.viewModel.state.activeStatus == .completed, "quoted search should complete")
        try expect(trace.evidence.contains(where: { record in
            record.kind == AgentEvidenceKind.fileSearch.rawValue
                && record.metadata["query"]?.stringValue == "Experience"
        }), "search evidence should use the quoted query, not the whole instruction")
    }

    @MainActor
    private static func testMultipleQuotedSearchesCreateSeparateEvidence() async throws {
        let harness = try await makeHarness(prefix: "tool-multi-quoted-search")
        try "AlphaToken appears here.".write(
            to: harness.workspace.appendingPathComponent("alpha.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "BetaToken appears here.".write(
            to: harness.workspace.appendingPathComponent("beta.txt"),
            atomically: true,
            encoding: .utf8
        )
        let adapter = FixtureAgentKernelAdapter(
            responses: [.finalAnswer("I found AlphaToken and BetaToken.")]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: #"search every granted folder for "AlphaToken" and "BetaToken""#,
            context: AgentRunViewContext(title: "Multi Quoted Search", contextID: "tool-multi-quoted-search", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let queries = try await harness.store.traceProjection(runID: runID).evidence
            .filter { $0.kind == AgentEvidenceKind.fileSearch.rawValue }
            .compactMap { $0.metadata["query"]?.stringValue }
        try expect(harness.viewModel.state.activeStatus == .completed, "multi-quoted search should complete")
        try expect(queries.contains("AlphaToken"), "first quoted search term should be searched independently")
        try expect(queries.contains("BetaToken"), "second quoted search term should be searched independently")
    }

    @MainActor
    private static func testSensitiveSearchFallsBackToFilenameOnly() async throws {
        let harness = try await makeHarness(prefix: "tool-sensitive-filename-search")
        try "do-not-read-sensitive-token".write(
            to: harness.workspace.appendingPathComponent("credentials.json"),
            atomically: true,
            encoding: .utf8
        )
        let adapter = FixtureAgentKernelAdapter(
            responses: [.finalAnswer("I found a filename/path match for credentials.json.")]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "search every granted folder for credentials.json",
            context: AgentRunViewContext(title: "Sensitive Filename Search", contextID: "tool-sensitive-filename-search", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let searchEvidenceRecords = trace.evidence.filter { $0.kind == AgentEvidenceKind.fileSearch.rawValue }
        let progressText = trace.events.compactMap { event -> String? in
            switch event.payload {
            case .progress(let text), .diagnostic(let text), .text(let text):
                return text.text
            default:
                return nil
            }
        }.joined(separator: " | ")
        try expect(
            !searchEvidenceRecords.isEmpty,
            "sensitive filename search should record search evidence; saw evidence kinds \(trace.evidence.map(\.kind).joined(separator: ", ")); progress \(progressText)"
        )
        let searchEvidence = searchEvidenceRecords[0]
        let artifact: String
        if let artifactID = searchEvidence.artifactID {
            let data = try await harness.store.readArtifact(artifactID)
            artifact = String(data: data, encoding: .utf8) ?? ""
        } else {
            artifact = ""
        }
        try expect(searchEvidence.metadata["filenameOnly"]?.boolValue == true, "sensitive search should be downgraded to filename-only")
        try expect(artifact.contains("credentials.json"), "filename-only search should still return matching paths")
        try expect(!artifact.contains("do-not-read-sensitive-token"), "filename-only search must not record file contents")
    }

    @MainActor
    private static func testVisualAttachmentRecordsEvidenceAndPromptContext() async throws {
        let harness = try await makeHarness(prefix: "tool-visual-context")
        let attachment = AgentKernelModelAttachment(
            modality: .text,
            label: "Screen region",
            metadata: [
                "source": .string("capture"),
                "ocrText": .string("Build failed at Step 2")
            ]
        )
        let adapter = FixtureAgentKernelAdapter(
            responses: [.finalAnswer("The visual context says the build failed at Step 2.")]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "what does the current visual context show?",
            context: AgentRunViewContext(title: "Visual Context", contextID: "tool-visual-context", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            attachments: [attachment],
            systemPrompt: "Use available visual context.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let firstRequest = await adapter.requests().first
        let prompt = AgentKernelTextProtocolPromptBuilder().prompt(
            for: AgentKernelModelAdapterRequest(
                messages: [AgentKernelMessage(role: .user, content: "what does the current visual context show?")],
                attachments: [attachment]
            )
        )
        try expect(harness.viewModel.state.activeStatus == .completed, "visual context run should complete")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.visualContext.rawValue }), "visual context should be recorded as evidence")
        try expect(firstRequest?.attachments.contains(attachment) == true, "model request should carry visual attachment metadata")
        try expect(prompt.contains("Build failed at Step 2"), "text-protocol prompt should include OCR attachment text")
    }

    // RELY-001: when the user explicitly references a granted entity by path, the planner
    // scopes content reads to that entity and does not pull in unrelated broad-grant files.
    // (Replaces the old prior-entity test that depended on fuzzy whole-grant profile guessing.)
    @MainActor
    private static func testEvidencePlannerReadsScopedContentForReferencedEntity() async throws {
        let root = try makeTemporaryRoot(prefix: "tool-evidence-planner")
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let broadProject = documents.appendingPathComponent("pixel-pane", isDirectory: true)
        let siteProject = documents.appendingPathComponent("example-site", isDirectory: true)
        try FileManager.default.createDirectory(at: broadProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: siteProject, withIntermediateDirectories: true)
        try "Architecture notes about agent systems.".write(
            to: broadProject.appendingPathComponent("architecture.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Portfolio for the local site project.".write(
            to: siteProject.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        <html><body><section><h2>Experience</h2><p>Organizations: Applied Materials, KLA, and Synopsys.</p></section></body></html>
        """.write(to: siteProject.appendingPathComponent("whoami.html"), atomically: true, encoding: .utf8)

        let store = try AgentRunStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let viewModel = AgentRunViewModel(store: store)
        let grants = [
            AgentLocalFileGrant(path: broadProject.path, isDirectory: true),
            AgentLocalFileGrant(path: siteProject.path, isDirectory: true)
        ]
        let context = AgentRunViewContext(title: "Evidence Planner", contextID: "tool-evidence-planner", contextKind: "assistant")
        let firstAdapter = FixtureAgentKernelAdapter(responses: [.finalAnswer("Yes, I can see the local site project.")])
        let firstConfig = toolConfig(grants: grants, runMode: .readOnly, adapter: firstAdapter)

        _ = try await viewModel.startRun(
            userMessage: "can you inspect the local portfolio?",
            context: context,
            adapter: firstAdapter,
            mode: firstConfig.mode,
            tools: firstConfig.tools,
            toolContext: firstConfig.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()
        try expect(viewModel.state.activeStatus == .completed, "first local entity run should complete")

        // Preflight scopes discovery to the referenced entity and the
        // model reads the specific file it needs; preflight does not blind-read files itself.
        let secondAdapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(name: "read_file", arguments: ["path": siteProject.appendingPathComponent("whoami.html").path], reason: nil),
                .finalAnswer("You have worked for Applied Materials, KLA, and Synopsys.")
            ]
        )
        let secondConfig = toolConfig(grants: grants, runMode: .readOnly, adapter: secondAdapter)
        let runID = try await viewModel.startRun(
            userMessage: "which organizations are listed in \(siteProject.path)?",
            context: context,
            adapter: secondAdapter,
            mode: secondConfig.mode,
            tools: secondConfig.tools,
            toolContext: secondConfig.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let trace = try await store.traceProjection(runID: runID)
        let listedPaths = trace.evidence
            .filter { $0.kind == AgentEvidenceKind.folderList.rawValue }
            .compactMap { $0.metadata["path"]?.stringValue }
        let readPaths = trace.evidence
            .filter { $0.kind == AgentEvidenceKind.fileRead.rawValue }
            .compactMap { $0.metadata["path"]?.stringValue }
        try expect(viewModel.state.activeStatus == .completed, "follow-up local content run should complete")
        try expect(listedPaths.contains(siteProject.path), "preflight should scope discovery to the referenced entity")
        try expect(!listedPaths.contains(broadProject.path), "preflight should not list the unrelated broad grant")
        try expect(readPaths.contains(siteProject.appendingPathComponent("whoami.html").path), "the model should read the referenced file the planner surfaced")
        try expect(!readPaths.contains(broadProject.appendingPathComponent("architecture.md").path), "the run should not read unrelated broad-grant content")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.evidenceRequirement.rawValue }), "planner should persist evidence requirements")
    }

    @MainActor
    private static func testEmptyResolvedDirectoryListingIsAnswerEvidence() async throws {
        let root = try makeTemporaryRoot(prefix: "tool-empty-folder")
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let emptyFolder = workspace.appendingPathComponent("empty-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
        let store = try AgentRunStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let viewModel = AgentRunViewModel(store: store)
        let grant = AgentLocalFileGrant(path: emptyFolder.path, isDirectory: true)
        let adapter = FixtureAgentKernelAdapter(responses: [.finalAnswer("The folder has no entries.")])
        let config = toolConfig(grant: grant, runMode: .readOnly, adapter: adapter)

        let runID = try await viewModel.startRun(
            userMessage: "what is inside \(emptyFolder.path)?",
            context: AgentRunViewContext(title: "Empty Folder", contextID: "tool-empty-folder", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let trace = try await store.traceProjection(runID: runID)
        try expect(viewModel.state.activeStatus == .completed, "empty directory listing should still be answer evidence")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.folderList.rawValue && $0.metadata["entryCount"]?.intValue == 0 }), "empty folder listing evidence should be recorded")
    }

    @MainActor
    private static func testGrantDiscoveryUsesInventoryEvidenceWithoutReadingFiles() async throws {
        let harness = try await makeHarness(prefix: "tool-grant-discovery")
        try "private content should not be read".write(
            to: harness.workspace.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )
        let adapter = FixtureAgentKernelAdapter(
            responses: [.finalAnswer("I can access the granted workspace folder.")]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "which local folders have been granted access?",
            context: AgentRunViewContext(title: "Grant Discovery", contextID: "tool-grant-discovery", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let firstRequest = await adapter.requests().first
        let firstObservation = firstRequest?.messages.first(where: { $0.role == .observation })?.content ?? ""
        try expect(harness.viewModel.state.activeStatus == .completed, "grant discovery run should complete")
        try expect(firstObservation.contains(harness.workspace.path), "first model request should receive the granted path inventory")
        try expect(firstObservation.contains("entryCount"), "first model request should receive inventory metadata")
        try expect(trace.evidence.contains(where: { record in
            record.kind == AgentEvidenceKind.fileGrant.rawValue
                && record.metadata["paths"]?.stringValue?.contains(harness.workspace.path) == true
                && record.artifactID != nil
        }), "grant discovery should record artifact-backed grant inventory evidence")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.finalAnswerSupport.rawValue }), "grant inventory alone should not fabricate final-answer support")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.folderList.rawValue }), "grant discovery should not list an arbitrary folder")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileSearch.rawValue }), "grant discovery should not search files")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue }), "grant discovery should not read files")
    }

    @MainActor
    private static func testRuntimeCapabilityQuestionDoesNotSearchLocalFiles() async throws {
        let harness = try await makeHarness(prefix: "tool-capability")
        try "tool words in local content should not attract capability questions".write(
            to: harness.workspace.appendingPathComponent("tool-notes.txt"),
            atomically: true,
            encoding: .utf8
        )
        let adapter = FixtureAgentKernelAdapter(
            responses: [.finalAnswer("I can use the visible local tools and will ask for approval for risky actions.")]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "What can you do on this Mac right now? List every tool and whether it needs approval.",
            context: AgentRunViewContext(title: "Capability", contextID: "tool-capability", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(harness.viewModel.state.activeStatus == .completed, "capability question should complete")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.folderList.rawValue }), "capability question should not list local files")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileSearch.rawValue }), "capability question should not search local files")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue }), "capability question should not read local files")
    }

    @MainActor
    private static func testModelRequestedSearchAcrossAllGrants() async throws {
        let root = try makeTemporaryRoot(prefix: "tool-broad-grant-search")
        let first = root.appendingPathComponent("first-grant", isDirectory: true)
        let second = root.appendingPathComponent("second-grant", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try "Experience: first grant evidence.".write(to: first.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        try "Experience: second grant evidence.".write(to: second.appendingPathComponent("two.txt"), atomically: true, encoding: .utf8)
        let store = try AgentRunStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let viewModel = AgentRunViewModel(store: store)
        let grants = [
            AgentLocalFileGrant(path: first.path, isDirectory: true),
            AgentLocalFileGrant(path: second.path, isDirectory: true)
        ]
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(name: "search_files", arguments: ["query": "experience"], reason: nil),
                .finalAnswer("I found experience references in both granted folders.")
            ]
        )
        let config = toolConfig(grants: grants, runMode: .readOnly, adapter: adapter)

        let runID = try await viewModel.startRun(
            userMessage: "search every granted folder for experience",
            context: AgentRunViewContext(title: "Broad Search", contextID: "tool-broad-grant-search", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let trace = try await store.traceProjection(runID: runID)
        let searchPaths = trace.evidence
            .filter { $0.kind == AgentEvidenceKind.fileSearch.rawValue }
            .compactMap { $0.metadata["paths"]?.stringValue }
            .joined(separator: "\n")
        try expect(viewModel.state.activeStatus == .completed, "broad search should complete")
        try expect(searchPaths.contains(first.appendingPathComponent("one.txt").path), "broad search should include first grant")
        try expect(searchPaths.contains(second.appendingPathComponent("two.txt").path), "broad search should include second grant")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.evidenceRequirement.rawValue && $0.metadata["requirementKinds"]?.stringValue?.contains("search_discovery") == true }), "unquoted broad search should be model-tool driven, not a preflight evidence requirement")
    }

    @MainActor
    private static func testFollowUpReferenceIsModelToolResolved() async throws {
        let root = try makeTemporaryRoot(prefix: "tool-followup-reference")
        let site = root.appendingPathComponent("personal-site", isDirectory: true)
        let other = root.appendingPathComponent("other-grant", isDirectory: true)
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let index = site.appendingPathComponent("index.html")
        try "<html><body>Main page about local apps.</body></html>".write(to: index, atomically: true, encoding: .utf8)
        try "unrelated".write(to: other.appendingPathComponent("notes.html"), atomically: true, encoding: .utf8)
        let store = try AgentRunStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let viewModel = AgentRunViewModel(store: store)
        let grants = [
            AgentLocalFileGrant(path: site.path, isDirectory: true),
            AgentLocalFileGrant(path: other.path, isDirectory: true)
        ]
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .finalAnswer("The folder contains index.html."),
                .toolCall(name: "read_file", arguments: ["path": index.path], reason: nil),
                .finalAnswer("The main page is about local apps.")
            ]
        )
        let config = toolConfig(grants: grants, runMode: .readOnly, adapter: adapter)
        let context = AgentRunViewContext(title: "Followup", contextID: "tool-followup-reference", contextKind: "assistant")

        _ = try await viewModel.startRun(
            userMessage: "List the files in \(site.path) and tell me what this folder is.",
            context: context,
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let runID = try await viewModel.startRun(
            userMessage: "Open the main HTML file in that folder and summarize what the page is about.",
            context: context,
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let trace = try await store.traceProjection(runID: runID)
        try expect(viewModel.state.activeStatus == .completed, "follow-up should complete")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.folderList.rawValue && $0.metadata["path"]?.stringValue == site.path }), "phrase-only follow-up references should not create deterministic folder-list preflight")
        try expect(!trace.evidence.contains(where: { record in
            guard record.kind == AgentEvidenceKind.fileSearch.rawValue else { return false }
            let rootPath = record.metadata["rootPath"]?.stringValue
            return rootPath == nil || rootPath == ""
        }), "follow-up should not run unscoped broad search")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue && $0.metadata["path"]?.stringValue == index.path }), "follow-up should read the selected main page")
    }

    @MainActor
    private static func testConversationHistoryQuestionDoesNotSearchLocalFiles() async throws {
        let harness = try await makeHarness(prefix: "tool-history-question")
        try "previous sessions should not be inferred from local files".write(
            to: harness.workspace.appendingPathComponent("history.txt"),
            atomically: true,
            encoding: .utf8
        )
        let adapter = FixtureAgentKernelAdapter(
            responses: [.finalAnswer("No previous chat context is available in this chat.")]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "What did we work on in our previous sessions?",
            context: AgentRunViewContext(title: "History", contextID: "tool-history-question", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(harness.viewModel.state.activeStatus == .completed, "history question should complete")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.folderList.rawValue }), "history question should not list local files")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileSearch.rawValue }), "history question should not search local files")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue }), "history question should not read local files")
    }

    @MainActor
    private static func testLargestHTMLSelectionDoesNotRequireCommandEvidence() async throws {
        let root = try makeTemporaryRoot(prefix: "tool-largest-html")
        let site = root.appendingPathComponent("site", isDirectory: true)
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        let small = site.appendingPathComponent("small.html")
        let large = site.appendingPathComponent("large.html")
        try "<html>small</html>".write(to: small, atomically: true, encoding: .utf8)
        try String(repeating: "<p>large</p>", count: 20).write(to: large, atomically: true, encoding: .utf8)
        let store = try AgentRunStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let viewModel = AgentRunViewModel(store: store)
        let grant = AgentLocalFileGrant(path: site.path, isDirectory: true)
        let adapter = FixtureAgentKernelAdapter(
            responses: [.finalAnswer("large.html is the largest HTML file.")]
        )
        let config = toolConfig(grant: grant, runMode: .readOnly, adapter: adapter)

        let runID = try await viewModel.startRun(
            userMessage: "find the largest HTML file in \(site.path)",
            context: AgentRunViewContext(title: "Largest HTML", contextID: "tool-largest-html", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let trace = try await store.traceProjection(runID: runID)
        try expect(viewModel.state.activeStatus == .completed, "largest HTML selector should complete")
        try expect(trace.evidence.contains(where: { record in
            record.kind == AgentEvidenceKind.folderList.rawValue
                && record.metadata["topFilePath_html"]?.stringValue == large.path
        }), "folder evidence should expose the largest HTML candidate")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.commandOutput.rawValue }), "largest-file selector should not require command evidence")
    }

    @MainActor
    private static func testSelectedDirectoryContentNeedsReadEvidence() async throws {
        let root = try makeTemporaryRoot(prefix: "tool-selected-content")
        let site = root.appendingPathComponent("local-site", isDirectory: true)
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        let page = site.appendingPathComponent("profile.html")
        try "<html><body><section>Experience: durable runtime design.</section></body></html>".write(
            to: page,
            atomically: true,
            encoding: .utf8
        )
        let store = try AgentRunStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let viewModel = AgentRunViewModel(store: store)
        let grant = AgentLocalFileGrant(path: site.path, isDirectory: true)
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(name: "read_file", arguments: ["path": page.path], reason: nil),
                .finalAnswer("The site lists durable runtime design.")
            ]
        )
        let config = toolConfig(grant: grant, runMode: .readOnly, adapter: adapter)

        let runID = try await viewModel.startRun(
            userMessage: "summarize the experience section in \(site.path)",
            context: AgentRunViewContext(title: "Selected Content", contextID: "tool-selected-content", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let trace = try await store.traceProjection(runID: runID)
        try expect(viewModel.state.activeStatus == .completed, "content task should complete after model-requested file read")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.folderList.rawValue && $0.metadata["path"]?.stringValue == site.path }), "exact grant reference should surface directory evidence")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue && $0.metadata["path"]?.stringValue == page.path }), "the model should read the relevant file before answering")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.evidenceRequirement.rawValue && $0.metadata["requirementKinds"]?.stringValue?.contains("file_content") == true }), "content words alone should not create a file-content preflight requirement")
    }

    @MainActor
    private static func testReadOnlyExperienceQuestionIsNotSideEffectGated() async throws {
        let root = try makeTemporaryRoot(prefix: "tool-readonly-no-sideeffect")
        let site = root.appendingPathComponent("portfolio-site", isDirectory: true)
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        let page = site.appendingPathComponent("whoami.html")
        try "<html><body>Experience: Swift, local AI, and agent runtime work.</body></html>".write(
            to: page,
            atomically: true,
            encoding: .utf8
        )
        let store = try AgentRunStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let viewModel = AgentRunViewModel(store: store)
        let grant = AgentLocalFileGrant(path: site.path, isDirectory: true)
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(name: "read_file", arguments: ["path": page.path], reason: nil),
                .finalAnswer("The site lists Swift, local AI, and agent runtime work.")
            ]
        )
        let config = toolConfig(grant: grant, runMode: .proposalOnly, adapter: adapter)

        let runID = try await viewModel.startRun(
            userMessage: "Based only on the files you can access in \(site.path), give me a bulleted list of the work experience listed on the site.",
            context: AgentRunViewContext(title: "Read Only", contextID: "tool-readonly-no-sideeffect", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let trace = try await store.traceProjection(runID: runID)
        try expect(viewModel.state.activeStatus == .completed, "read-only content task should complete after read evidence")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue }), "read-only content task should gather read evidence")
        try expect(!trace.events.contains(where: { event in
            guard event.kind == .providerDiagnostic,
                  case .diagnostic(let text) = event.payload else { return false }
            return text.text.contains("local change request")
        }), "read-only content task should not be side-effect gated")
        try expect(!trace.sideEffects.contains(where: { _ in true }), "read-only content task should not create side effects")
    }

    @MainActor
    private static func testFolderListingObservationIncludesByteCounts() async throws {
        let root = try makeTemporaryRoot(prefix: "tool-folder-metadata")
        let workspace = root.appendingPathComponent("metadata-site", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try "short".write(to: workspace.appendingPathComponent("short.txt"), atomically: true, encoding: .utf8)
        try "this is longer".write(to: workspace.appendingPathComponent("long.txt"), atomically: true, encoding: .utf8)
        let store = try AgentRunStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let viewModel = AgentRunViewModel(store: store)
        let grant = AgentLocalFileGrant(path: workspace.path, isDirectory: true)
        let adapter = FixtureAgentKernelAdapter(
            responses: [.finalAnswer("long.txt is larger.")]
        )
        let config = toolConfig(grant: grant, runMode: .readOnly, adapter: adapter)

        _ = try await viewModel.startRun(
            userMessage: "which file is largest in \(workspace.path)?",
            context: AgentRunViewContext(title: "Folder Metadata", contextID: "tool-folder-metadata", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let firstRequest = await adapter.requests().first
        let observationText = firstRequest?.messages.filter { $0.role == .observation }.map(\.content).joined(separator: "\n") ?? ""
        try expect(viewModel.state.activeStatus == .completed, "folder metadata run should complete")
        try expect(observationText.contains("short.txt") && observationText.contains("bytes: 5"), "folder observation should include short file byte count")
        try expect(observationText.contains("long.txt") && observationText.contains("bytes: 14"), "folder observation should include long file byte count")
    }

    @MainActor
    private static func testBlindLocalFinalAnswerIsRejectedUntilEvidenceExists() async throws {
        let harness = try await makeHarness(prefix: "tool-blind-answer")
        try """
        <html><body><h1>Experience</h1><p>Experience: AI systems, Swift, and agent runtime design.</p></body></html>
        """.write(to: harness.workspace.appendingPathComponent("whoami.html"), atomically: true, encoding: .utf8)
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .finalAnswer(#"{"answer":"I would need terminal access to inspect the website."}"#),
                .toolCall(name: "search_files", arguments: ["query": "experience"], reason: nil),
                .toolCall(name: "read_file", arguments: ["path": "whoami.html"], reason: nil),
                .finalAnswer("- AI systems\n- Swift\n- Agent runtime design")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "give me a bulleted list of my experience according to my website",
            context: AgentRunViewContext(title: "Blind Answer", contextID: "tool-blind-answer", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(harness.viewModel.state.activeStatus == .completed, "blind local answer should recover after evidence")
        try expect(harness.viewModel.state.messages.last?.text.text.contains("Agent runtime design") == true, "final answer should be the evidence-backed answer")
        try expect(trace.events.contains(where: { $0.kind == .providerDiagnostic }), "rejected blind final answer should leave a diagnostic")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.finalAnswerSupport.rawValue }), "accepted local answer should record final-answer support")
    }

    // RELY-001 regression: a question that names no specific local target must not trigger a
    // blind preflight sweep that reads/searches/lists files. The model drives tool use instead.
    @MainActor
    private static func testNoTargetQuestionDoesNotGatherBlindEvidence() async throws {
        let harness = try await makeHarness(prefix: "tool-no-target")
        try String(repeating: "irrelevant filler content. ", count: 4_000)
            .write(to: harness.workspace.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
        let adapter = FixtureAgentKernelAdapter(
            responses: [.finalAnswer("I can list folders, search and read files, and run bounded commands when you grant access.")]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "hey, what can you help me with?",
            context: AgentRunViewContext(title: "No Target", contextID: "tool-no-target", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        try expect(harness.viewModel.state.activeStatus == .completed, "no-target question should complete")
        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue }), "no-target question must not read files blindly")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileSearch.rawValue }), "no-target question must not search files blindly")
        try expect(!trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.folderList.rawValue }), "no-target question must not list folders blindly")
    }

    @MainActor
    private static func testLocalFileAnswerMustUseRecordedContent() async throws {
        let harness = try await makeHarness(prefix: "tool-refusal")
        try "Experience: Mac apps and local-first agent tooling.".write(
            to: harness.workspace.appendingPathComponent("index.html"),
            atomically: true,
            encoding: .utf8
        )
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .finalAnswer("This answer ignores the recorded local file evidence."),
                .toolCall(name: "read_file", arguments: ["path": "index.html"], reason: nil),
                .finalAnswer("Your website lists Mac apps and local-first agent tooling.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        _ = try await harness.viewModel.startRun(
            userMessage: "what is my experience according to index.html?",
            context: AgentRunViewContext(title: "Refusal", contextID: "tool-refusal", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        try expect(harness.viewModel.state.activeStatus == .completed, "ungrounded local-file answer should recover through tools")
        try expect(harness.viewModel.state.messages.last?.text.text.contains("local-first agent tooling") == true, "final answer should use recorded file content")
    }

    @MainActor
    private static func testLargeReadObservationIsBudgeted() async throws {
        let harness = try await makeHarness(prefix: "tool-large-read")
        let repeated = Array(repeating: "<section><h2>Experience</h2><p>AI engineering and Swift apps.</p></section>", count: 420).joined()
        try "<html><body>\(repeated)</body></html>".write(
            to: harness.workspace.appendingPathComponent("whoami.html"),
            atomically: true,
            encoding: .utf8
        )
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(name: "read_file", arguments: ["path": "whoami.html"], reason: nil),
                .finalAnswer("The page mentions AI engineering and Swift apps.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        _ = try await harness.viewModel.startRun(
            userMessage: "read the website and summarize my experience",
            context: AgentRunViewContext(title: "Large Read", contextID: "tool-large-read", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let lastRequest = await adapter.lastRequest()
        let observations = lastRequest?.messages.filter { $0.role == .observation }.map(\.content) ?? []
        try expect(observations.contains(where: { $0.contains("Artifact ID:") }), "large read observation should cite artifact")
        try expect(observations.allSatisfy { $0.count < 6_000 }, "large read observations should stay budgeted")
    }

    @MainActor
    private static func testBroadSearchObservationIsBudgeted() async throws {
        let harness = try await makeHarness(prefix: "tool-broad-search")
        for index in 0..<30 {
            let content = Array(repeating: "Bicycle Prestige Blue card size specifications \(index). ", count: 80).joined()
            try content.write(to: harness.workspace.appendingPathComponent("card-\(index).txt"), atomically: true, encoding: .utf8)
        }
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(name: "search_files", arguments: ["query": "Bicycle Prestige Blue card size specifications"], reason: nil),
                .finalAnswer("I found matching card specification files.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        _ = try await harness.viewModel.startRun(
            userMessage: "check Bicycle Prestige Blue card size specifications",
            context: AgentRunViewContext(title: "Broad Search", contextID: "tool-broad-search", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let lastRequest = await adapter.lastRequest()
        let observations = lastRequest?.messages.filter { $0.role == .observation }.map(\.content) ?? []
        try expect(observations.allSatisfy { $0.count < 6_000 }, "search observations should stay budgeted")
        try expect(observations.joined(separator: "\n").contains("artifactIDs:"), "search observation should cite artifacts")
    }

    @MainActor
    private static func testContextOverflowRepackagesBeforeFailure() async throws {
        let harness = try await makeHarness(prefix: "tool-context-repack")
        let descriptor = AgentKernelModelDescriptor(
            id: "fixture.small-context-repack",
            providerKind: .fixture,
            route: .local,
            displayName: "Fixture Small Context"
        )
        let adapter = FixtureAgentKernelAdapter(
            descriptor: descriptor,
            capabilities: AgentKernelModelAdapterCapabilities(
                descriptor: descriptor,
                toolCallingMode: .native,
                structuredOutputReliability: .strict,
                streamingMode: .events,
                limits: AgentKernelModelLimits(maxPromptCharacters: 1_000)
            ),
            responses: [.finalAnswer("Recovered after repacking.")]
        )
        let systemPrompt = String(repeating: "long system context ", count: 400)

        _ = try await harness.viewModel.startRun(
            userMessage: "hello",
            context: AgentRunViewContext(title: "Context Repack", contextID: "tool-context-repack", contextKind: "assistant"),
            adapter: adapter,
            mode: .plainChat,
            tools: [],
            toolContext: .plainChat,
            systemPrompt: systemPrompt,
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        try expect(harness.viewModel.state.activeStatus == .completed, "context overflow should retry with compacted context")
        try expect(harness.viewModel.state.messages.last?.text.text == "Recovered after repacking.", "compacted retry should produce final answer")
    }

    @MainActor
    private static func testWriteProposalApprovalExecutesAndContinues() async throws {
        let harness = try await makeHarness(prefix: "tool-write")
        let target = harness.workspace.appendingPathComponent("story.txt")
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": target.path,
                        "content": "A short story."
                    ],
                    reason: "Write requested file."
                ),
                .finalAnswer("Done. I created story.txt in the granted folder.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "write a short story in txt format within the folder.",
            context: AgentRunViewContext(title: "Tool Write", contextID: "tool-write", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let approval = try expectOne(harness.viewModel.state.pendingApprovals, "write proposal should create one approval")
        try expect(harness.viewModel.state.activeStatus == .waitingForApproval, "write run should wait for approval")

        try await harness.viewModel.approveWait(
            approval.waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Tool Write", contextID: "tool-write", contextKind: "assistant"),
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let content = try String(contentsOf: target, encoding: .utf8)
        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(content == "A short story.", "approved write should create file exactly once")
        try expect(harness.viewModel.state.activeStatus == .completed, "approved write should continue to final answer")
        try expect(trace.sideEffects.contains(where: { $0.status == .completed }), "completed side effect should be recorded")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.sideEffect.rawValue }), "side-effect evidence should be recorded")
    }

    @MainActor
    private static func testApprovalContinuationUsesDurableReplayContext() async throws {
        let harness = try await makeHarness(prefix: "tool-approval-replay")
        try "alpha".write(to: harness.workspace.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
        let target = harness.workspace.appendingPathComponent("notes.txt")
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(
                    name: "list_folder",
                    arguments: ["path": harness.workspace.path],
                    reason: "Inspect the folder before writing."
                ),
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": target.path,
                        "content": "noted"
                    ],
                    reason: "Create the requested notes file."
                ),
                .finalAnswer("Done after inspecting alpha.txt and creating notes.txt.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "Inspect the folder, then create a notes file.",
            context: AgentRunViewContext(title: "Approval Replay", contextID: "tool-approval-replay", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let approval = try expectOne(harness.viewModel.state.pendingApprovals, "write proposal should create one approval after folder inspection")
        try await harness.viewModel.approveWait(
            approval.waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Approval Replay", contextID: "tool-approval-replay", contextKind: "assistant"),
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let requests = await adapter.requests()
        let finalRequest = requests.last
        let finalObservations = finalRequest?.messages.filter { $0.role == .observation }.map(\.content).joined(separator: "\n") ?? ""
        let trace = try await harness.store.traceProjection(runID: runID)
        let modelRequests = trace.controlRecords.compactMap { record -> AgentModelGatewayRequest? in
            guard case .modelRequest(let request) = record.payload else { return nil }
            return request
        }

        try expect(harness.viewModel.state.activeStatus == .completed, "approved write should complete after replay continuation")
        try expect(requests.count >= 3, "approval continuation should issue a post-approval model request")
        try expect(finalObservations.contains("alpha.txt"), "post-approval request should keep the pre-approval folder observation")
        try expect(finalObservations.contains("stage_write_proposal") && finalObservations.contains("status: succeeded"), "post-approval request should include the approved write result observation")
        try expect(trace.controlRecords.contains(where: { $0.kind == .approvalResultObservation }), "approval result observation should be durable")
        try expect(trace.controlRecords.contains(where: { $0.kind == .toolResult && $0.metadata["source"] == .string("approval_continuation") }), "approval continuation should record a durable tool result")
        try expect(modelRequests.last?.messages.contains(where: { $0.role == .observation && $0.content.contains("alpha.txt") }) == true, "latest durable model request should preserve hidden replay context")
    }

    @MainActor
    private static func testWriteRequestCannotCompleteFromReadEvidenceOnly() async throws {
        let harness = try await makeHarness(prefix: "tool-write-skip")
        let target = harness.workspace.appendingPathComponent("report.txt")
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .finalAnswer("Failed to create report.txt because no matching files were found."),
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": target.path,
                        "content": "hello"
                    ],
                    reason: nil
                )
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: """
            operation: create
            targetPath: \(target.path)
            content: hello
            """,
            context: AgentRunViewContext(title: "Write Skip", contextID: "tool-write-skip", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(harness.viewModel.state.activeStatus == .waitingForApproval, "write request should continue to staged approval after rejected no-write answer")
        try expect(harness.viewModel.state.pendingApprovals.count == 1, "write request should create one approval")
        try expect(trace.events.contains(where: { event in
            guard event.kind == .providerDiagnostic,
                  case .diagnostic(let text) = event.payload else { return false }
            return text.text.contains("local change request needs stage_write_proposal")
        }), "skipped write answer should leave an evidence-gating diagnostic")
        try expect(!trace.events.contains(where: { event in
            guard event.kind == .assistantMessage,
                  case .text(let text) = event.payload else { return false }
            return text.text.contains("Failed to create")
        }), "rejected no-write answer should not be projected")
        try expect(!FileManager.default.fileExists(atPath: target.path), "file should not be written before approval")
    }

    @MainActor
    private static func testRequiredWriteToolNonAdherenceBlocksBeforeIterationCap() async throws {
        let harness = try await makeHarness(prefix: "tool-write-nonadherence")
        let target = harness.workspace.appendingPathComponent("notes.txt")
        try "existing note\n".write(to: target, atomically: true, encoding: .utf8)
        let adapter = tierBFixtureAdapter(
            responses: [
                .finalAnswer("Done. I appended today's date to notes.txt."),
                .finalAnswer("Done. I appended today's date to notes.txt.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: """
            operation: append
            targetPath: \(target.path)
            """,
            context: AgentRunViewContext(title: "Write Nonadherence", contextID: "tool-write-nonadherence", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let modelRequestCount = trace.steps.filter { $0.kind == .modelRequest }.count
        let content = try String(contentsOf: target, encoding: .utf8)
        try expect(harness.viewModel.state.activeStatus == .blocked, "write tool non-adherence should block the run")
        try expect(modelRequestCount == 2, "side-effect non-adherence should block after one repair attempt, before the global iteration cap")
        try expect(harness.viewModel.state.statusSummary.contains("required side-effect tool call"), "blocked status should identify the side-effect contract failure")
        try expect(harness.viewModel.state.statusSummary.contains("stage_write_proposal"), "blocked status should name the missing required tool")
        try expect(!harness.viewModel.state.messages.contains(where: { $0.role == .assistant }), "false completion should not be projected")
        try expect(!trace.events.contains(where: { event in
            guard event.kind == .failure,
                  case .diagnostic(let text) = event.payload else { return false }
            return text.text.contains("maximum tool iteration")
        }), "side-effect non-adherence should not fall through to max-iteration failure")
        try expect(content == "existing note\n", "file should not be changed without an approved side effect")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.sideEffect.rawValue }) == false, "no side-effect evidence should be fabricated")
    }

    @MainActor
    private static func testWriteProposalCanStillBeStagedWithoutPreclassifiedEditIntent() async throws {
        let harness = try await makeHarness(prefix: "tool-edit-preflight")
        let target = harness.workspace.appendingPathComponent("profile.md")
        try """
        # Profile

        Experience: Swift apps and local agent tooling.
        """.write(to: target, atomically: true, encoding: .utf8)
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "replace",
                        "targetPath": target.path,
                        "content": "# Profile\n\nExperience: Swift apps, local agent tooling, and durable runtime design.\n"
                    ],
                    reason: "Update the profile."
                )
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "modify profile.md to mention durable runtime design",
            context: AgentRunViewContext(title: "Edit Preflight", contextID: "tool-edit-preflight", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let requests = await adapter.requests()
        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(harness.viewModel.state.activeStatus == .waitingForApproval, "write proposal should still stage an approval")
        try expect(
            requests.first?.messages.contains {
                $0.role == .observation && $0.content.contains("This local change request needs")
            } != true,
            "write proposal should not depend on lexical preclassification diagnostics"
        )
        try expect(trace.sideEffects.contains(where: { $0.status == .proposed }), "write proposal should record a proposed side effect")
    }

    @MainActor
    private static func testStructuredOutputFailureBlocksWithRecoveryGuidance() async throws {
        let harness = try await makeHarness(prefix: "tool-structured-failure")
        let adapter = FixtureAgentKernelAdapter(responses: [.malformedOutput("{not-valid-json")])
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        _ = try await harness.viewModel.startRun(
            userMessage: "modify README.md to add a short introduction",
            context: AgentRunViewContext(title: "Structured Failure", contextID: "tool-structured-failure", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        try expect(harness.viewModel.state.activeStatus == .blocked, "structured-output failures should block with recovery guidance")
        try expect(
            harness.viewModel.state.statusSummary.contains("read-only inspection") ||
            harness.viewModel.state.statusSummary.contains("reliable tool/JSON support"),
            "blocked status should include provider or read-only recovery guidance"
        )
        try expect(
            !harness.viewModel.state.messages.contains(where: { $0.role == .assistant }),
            "structured-output failure should not project malformed output as assistant chat"
        )
    }

    @MainActor
    private static func testInvalidToolCallRetriesBeforeEvidence() async throws {
        let harness = try await makeHarness(prefix: "tool-invalid-call-before-evidence")
        try "Recoverable note content.".write(
            to: harness.workspace.appendingPathComponent("note.txt"),
            atomically: true,
            encoding: .utf8
        )
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(name: "read_file", arguments: [:], reason: nil),
                .toolCall(name: "read_file", arguments: ["path": "note.txt"], reason: nil),
                .finalAnswer("The note says Recoverable note content.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "Use local tools to inspect the accessible note and summarize it.",
            context: AgentRunViewContext(title: "Invalid Tool Call", contextID: "tool-invalid-call-before-evidence", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let recoveryRecords = trace.controlRecords.filter { $0.kind == .toolCallInvalidRecoveryObservation }
        let recoveryRequests = trace.controlRecords.compactMap { record -> AgentModelGatewayRequest? in
            guard record.metadata["phase"]?.stringValue == "tool_call_invalid_recovery",
                  case .modelRequest(let request) = record.payload else {
                return nil
            }
            return request
        }
        try expect(harness.viewModel.state.activeStatus == .completed, "invalid tool call should recover before evidence exists")
        try expect(harness.viewModel.state.messages.last?.text.text.contains("Recoverable note content") == true, "final answer should come from the repaired tool path")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue }), "repaired tool call should record file-read evidence")
        try expect(recoveryRecords.contains(where: { $0.metadata["hasRecordedEvidence"]?.boolValue == false }), "recovery should record that no substantive evidence existed yet")
        try expect(recoveryRequests.contains(where: { !$0.tools.isEmpty && $0.mode == config.mode }), "no-evidence recovery should keep the tool catalog available")
        try expect(!harness.viewModel.state.statusSummary.contains("missing required arguments"), "validation error should not be the completed user-facing answer")
    }

    @MainActor
    private static func testInvalidToolCallAfterEvidenceRecoversToFinalAnswer() async throws {
        let harness = try await makeHarness(prefix: "tool-invalid-call-after-evidence")
        try "Recorded evidence can answer this request.".write(
            to: harness.workspace.appendingPathComponent("note.txt"),
            atomically: true,
            encoding: .utf8
        )
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(name: "read_file", arguments: ["path": "note.txt"], reason: nil),
                .toolCall(name: "read_file", arguments: [:], reason: nil),
                .finalAnswer("The note says Recorded evidence can answer this request.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "Use local tools to inspect the accessible note and summarize it.",
            context: AgentRunViewContext(title: "Invalid Tool Call After Evidence", contextID: "tool-invalid-call-after-evidence", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let recoveryRecords = trace.controlRecords.filter { $0.kind == .toolCallInvalidRecoveryObservation }
        let recoveryRequests = trace.controlRecords.compactMap { record -> AgentModelGatewayRequest? in
            guard record.metadata["phase"]?.stringValue == "tool_call_invalid_recovery",
                  case .modelRequest(let request) = record.payload else {
                return nil
            }
            return request
        }
        try expect(harness.viewModel.state.activeStatus == .completed, "invalid tool call should recover after evidence exists")
        try expect(harness.viewModel.state.messages.last?.text.text.contains("Recorded evidence") == true, "final answer should be synthesized from recorded evidence")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.fileRead.rawValue }), "initial tool call should record file-read evidence")
        try expect(recoveryRecords.contains(where: { $0.metadata["hasRecordedEvidence"]?.boolValue == true }), "recovery should record that substantive evidence existed")
        try expect(recoveryRecords.contains(where: { $0.metadata["toolsDisabled"]?.boolValue == false }), "partial evidence should not close the tool catalog")
        try expect(recoveryRequests.contains(where: { !$0.tools.isEmpty && $0.mode == config.mode }), "partial-evidence recovery should keep tools available unless requirements are satisfied")
        try expect(!harness.viewModel.state.statusSummary.contains("missing required arguments"), "validation error should not be projected after successful recovery")
    }

    @MainActor
    private static func testUnobservedFinalAnswerPathsRepairThroughTools() async throws {
        let harness = try await makeHarness(prefix: "tool-unobserved-answer-paths")
        let details = harness.workspace.appendingPathComponent("details", isDirectory: true)
        try FileManager.default.createDirectory(at: details, withIntermediateDirectories: true)
        let first = details.appendingPathComponent("first.txt")
        let second = details.appendingPathComponent("second.txt")
        let instructions = harness.workspace.appendingPathComponent("instructions.md")
        try "Alpha value.".write(to: first, atomically: true, encoding: .utf8)
        try "Beta value.".write(to: second, atomically: true, encoding: .utf8)
        try "Use details/first.txt and details/second.txt for the answer.".write(
            to: instructions,
            atomically: true,
            encoding: .utf8
        )
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(name: "list_folder", arguments: ["path": harness.workspace.path], reason: nil),
                .toolCall(name: "read_file", arguments: ["path": "instructions.md"], reason: nil),
                .toolCall(name: "read_file", arguments: [:], reason: nil),
                .finalAnswer("I still need details/first.txt and details/second.txt."),
                .toolCall(name: "read_file", arguments: ["path": "details/first.txt"], reason: nil),
                .toolCall(name: "read_file", arguments: ["path": "details/second.txt"], reason: nil),
                .finalAnswer("Alpha value. Beta value.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .readOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "Use local tools to follow the workspace instructions and summarize the result.",
            context: AgentRunViewContext(title: "Unobserved Answer Paths", contextID: "tool-unobserved-answer-paths", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let readPaths = Set(
            trace.evidence
                .filter { $0.kind == AgentEvidenceKind.fileRead.rawValue }
                .compactMap { $0.metadata["path"]?.stringValue }
                .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        )
        let repairRecords = trace.controlRecords.filter { $0.kind == .finalAnswerRepairObservation }
        let recoveryRequests = trace.controlRecords.compactMap { record -> AgentModelGatewayRequest? in
            guard record.metadata["phase"]?.stringValue == "tool_call_invalid_recovery",
                  case .modelRequest(let request) = record.payload else {
                return nil
            }
            return request
        }
        let assistantMessages = harness.viewModel.state.messages.filter { $0.role == .assistant }.map(\.text.text)

        try expect(harness.viewModel.state.activeStatus == .completed, "run should complete after observing referenced local paths")
        try expect(harness.viewModel.state.messages.last?.text.text.contains("Alpha value. Beta value.") == true, "final answer should use the observed file contents")
        try expect(readPaths.contains(URL(fileURLWithPath: instructions.path).standardizedFileURL.path), "instructions file should be read")
        try expect(readPaths.contains(URL(fileURLWithPath: first.path).standardizedFileURL.path), "first referenced file should be read after repair")
        try expect(readPaths.contains(URL(fileURLWithPath: second.path).standardizedFileURL.path), "second referenced file should be read after repair")
        try expect(recoveryRequests.contains(where: { !$0.tools.isEmpty && $0.mode == config.mode }), "invalid-tool recovery should keep tools available while evidence is incomplete")
        try expect(
            repairRecords.contains(where: { $0.metadata["rejectionKind"]?.stringValue == "unsupportedLocalReferences" }),
            "premature final answer should be repaired because referenced paths lacked evidence"
        )
        try expect(
            !assistantMessages.contains(where: { $0.contains("I still need details/first.txt") }),
            "premature unsupported answer should not be projected to chat"
        )
    }

    @MainActor
    private static func testSpecificGrantBeatsBroadGrantForRandomTests() async throws {
        let root = try makeTemporaryRoot(prefix: "tool-random-tests")
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let pixelPane = documents.appendingPathComponent("pixel-pane", isDirectory: true)
        let randomTests = documents.appendingPathComponent("random-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: pixelPane, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: randomTests, withIntermediateDirectories: true)
        let store = try AgentRunStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let viewModel = AgentRunViewModel(store: store)
        let grants = [
            AgentLocalFileGrant(path: pixelPane.path, isDirectory: true),
            AgentLocalFileGrant(path: randomTests.path, isDirectory: true)
        ]
        let target = randomTests.appendingPathComponent("short_story.txt")
        let shadowTarget = pixelPane.appendingPathComponent("random-tests/short_story.txt")
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": "random-tests/short_story.txt",
                        "content": "The correct folder wins."
                    ],
                    reason: nil
                ),
                .finalAnswer("Done. I created short_story.txt in random-tests.")
            ]
        )
        let config = toolConfig(grants: grants, runMode: .proposalOnly, adapter: adapter)

        _ = try await viewModel.startRun(
            userMessage: "write a short story in a txt file in random-tests",
            context: AgentRunViewContext(title: "Random Tests", contextID: "tool-random-tests", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let approval = try expectOne(viewModel.state.pendingApprovals, "specific random-tests write should create one approval")
        try expect(approval.primaryText == target.path, "approval target should resolve to the explicit random-tests grant")
        try await viewModel.approveWait(
            approval.waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Random Tests", contextID: "tool-random-tests", contextKind: "assistant"),
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await viewModel.waitForIdle(timeout: 3)
        await viewModel.refresh()

        let writtenContent = try String(contentsOf: target, encoding: .utf8)
        try expect(writtenContent == "The correct folder wins.", "write should land in the explicit random-tests grant")
        try expect(!FileManager.default.fileExists(atPath: shadowTarget.path), "write should not create a shadow path under the broad grant")
        try expect(viewModel.state.activeStatus == .completed, "specific grant write should complete")
    }

    @MainActor
    private static func testMissingWriteParentIsRejectedBeforeApproval() async throws {
        let harness = try await makeHarness(prefix: "tool-missing-parent")
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": "missing/short_story.txt",
                        "content": "This should not reach approval."
                    ],
                    reason: nil
                ),
                .finalAnswer("I could not stage that write because the parent folder does not exist.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "write a story under a missing folder",
            context: AgentRunViewContext(title: "Missing Parent", contextID: "tool-missing-parent", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(harness.viewModel.state.pendingApprovals.isEmpty, "missing parent write should not create an approval")
        try expect(trace.sideEffects.isEmpty, "missing parent write should not stage a side effect")
        try expect(trace.steps.contains(where: { $0.kind == .toolResult }), "missing parent write should still produce a tool result")
    }

    @MainActor
    private static func testApprovedWriteFailureContinuesWithObservation() async throws {
        let harness = try await makeHarness(prefix: "tool-approved-fail")
        let missingTarget = harness.workspace.appendingPathComponent("missing-replace.txt")
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "replace",
                        "targetPath": missingTarget.path,
                        "content": "replace should fail"
                    ],
                    reason: nil
                ),
                .finalAnswer("I could not replace the file because the approved write failed before creating anything.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "replace a missing file",
            context: AgentRunViewContext(title: "Approved Failure", contextID: "tool-approved-fail", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let approval = try expectOne(harness.viewModel.state.pendingApprovals, "replace missing file should still require approval before execution")
        try await harness.viewModel.approveWait(
            approval.waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Approved Failure", contextID: "tool-approved-fail", contextKind: "assistant"),
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let visible = await harness.store.visibleMessages(sessionID: nil).filter { $0.runID == runID }
        let export = AgentRunTraceExporter().export(trace: trace, visibleMessages: visible)
        let lastRequest = await adapter.lastRequest()

        try expect(harness.viewModel.state.activeStatus == .completed, "failed approved write should return to the model for a final answer")
        try expect(harness.viewModel.state.messages.last?.text.text.contains("approved write failed") == true, "user-visible message should use the failed tool observation")
        try expect(trace.sideEffects.contains(where: { $0.status == .failed && $0.errorSummary != nil }), "failed side effect should record error summary")
        try expect(export.contains("error=Side-effect execution failed"), "trace export should include side-effect error summary")
        try expect(lastRequest?.messages.contains(where: { $0.role == .observation && $0.content.contains("status: failed") }) == true, "model continuation should receive failed side-effect observation")
        try expect(!FileManager.default.fileExists(atPath: missingTarget.path), "failed replace should not create the missing target")
    }

    @MainActor
    private static func testDeniedWriteDoesNotExecute() async throws {
        let harness = try await makeHarness(prefix: "tool-deny")
        let target = harness.workspace.appendingPathComponent("denied.txt")
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": target.path,
                        "content": "Should not be written."
                    ],
                    reason: nil
                )
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .proposalOnly, adapter: adapter)

        _ = try await harness.viewModel.startRun(
            userMessage: "write a denied file.",
            context: AgentRunViewContext(title: "Tool Deny", contextID: "tool-deny", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let approval = try expectOne(harness.viewModel.state.pendingApprovals, "denied write should create one approval")
        try await harness.viewModel.denyWait(
            approval.waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Tool Deny", contextID: "tool-deny", contextKind: "assistant"),
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        await harness.viewModel.refresh()

        try expect(!FileManager.default.fileExists(atPath: target.path), "denied write should not create file")
        try expect(harness.viewModel.state.activeStatus == .blocked, "denied write should block the run")
        try expect(harness.viewModel.state.messages.last?.text.text == "User denied the proposed file write.", "denied write should use typed side-effect denial text")
        try expect(!harness.viewModel.state.messages.contains(where: { $0.text.text.contains("proposed file change") }), "denied write should not project the old file-specific canned answer")
    }

    @MainActor
    private static func testDeniedCommandUsesGenericSideEffectProjection() async throws {
        let harness = try await makeHarness(prefix: "tool-command-deny")
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(
                    name: "run_finite_command",
                    arguments: [
                        "command": "echo no",
                        "workingDirectory": harness.workspace.path,
                        "timeoutSeconds": "5"
                    ],
                    reason: nil
                )
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .fullAgent, adapter: adapter)

        _ = try await harness.viewModel.startRun(
            userMessage: "run a command I will deny",
            context: AgentRunViewContext(title: "Tool Command Deny", contextID: "tool-command-deny", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let approval = try expectOne(harness.viewModel.state.pendingApprovals, "command denial should create one approval")
        try expect(approval.kind == .command, "command denial fixture should stage a command approval")

        try await harness.viewModel.denyWait(
            approval.waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Tool Command Deny", contextID: "tool-command-deny", contextKind: "assistant"),
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        await harness.viewModel.refresh()

        try expect(harness.viewModel.state.activeStatus == .blocked, "denied command should block the run")
        try expect(harness.viewModel.state.messages.last?.text.text == "User denied the proposed command.", "denied command should project command-specific denial text")
        try expect(!harness.viewModel.state.messages.contains(where: { $0.text.text.contains("proposed file change") }), "denied command should not use file-write denial wording")
    }

    @MainActor
    private static func testApprovedFiniteCommandExecutesAndContinues() async throws {
        let harness = try await makeHarness(prefix: "tool-command")
        let script = harness.workspace.appendingPathComponent("hello_world.sh")
        try """
        #!/usr/bin/env bash
        echo hello from script
        """.write(to: script, atomically: true, encoding: .utf8)

        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(
                    name: "run_finite_command",
                    arguments: [
                        "command": "bash \(script.path)",
                        "workingDirectory": harness.workspace.path,
                        "timeoutSeconds": "5"
                    ],
                    reason: nil
                ),
                .finalAnswer("The script ran and printed hello from script.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .fullAgent, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "run the script",
            context: AgentRunViewContext(title: "Tool Command", contextID: "tool-command", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let approval = try expectOne(harness.viewModel.state.pendingApprovals, "raw script command should create one approval")
        try expect(approval.kind == .command, "script command should project as a command approval")

        try await harness.viewModel.approveWait(
            approval.waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Tool Command", contextID: "tool-command", contextKind: "assistant"),
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        try expect(harness.viewModel.state.activeStatus == .completed, "approved command should continue to final answer")
        try expect(trace.sideEffects.contains(where: { $0.kind == .command && $0.status == .completed }), "completed command side effect should be recorded")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.commandOutput.rawValue }), "command output evidence should be recorded")
        let lastRequest = await adapter.lastRequest()
        try expect(lastRequest?.messages.contains(where: { $0.role == .observation && $0.content.contains("hello from script") }) == true, "model continuation should receive command stdout observation")
    }

    @MainActor
    private static func testApprovedFiniteCommandFailureContinuesWithObservation() async throws {
        let harness = try await makeHarness(prefix: "tool-command-fail")
        let adapter = FixtureAgentKernelAdapter(
            responses: [
                .toolCall(
                    name: "run_finite_command",
                    arguments: [
                        "command": "false | cat",
                        "workingDirectory": harness.workspace.path,
                        "timeoutSeconds": "5"
                    ],
                    reason: nil
                ),
                .finalAnswer("The command failed with exit code 1, so I could not use its output.")
            ]
        )
        let config = toolConfig(grant: harness.grant, runMode: .fullAgent, adapter: adapter)

        let runID = try await harness.viewModel.startRun(
            userMessage: "run a command that may fail",
            context: AgentRunViewContext(title: "Tool Command Failure", contextID: "tool-command-fail", contextKind: "assistant"),
            adapter: adapter,
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let approval = try expectOne(harness.viewModel.state.pendingApprovals, "raw failing command should create one approval")
        try await harness.viewModel.approveWait(
            approval.waitID,
            adapter: adapter,
            context: AgentRunViewContext(title: "Tool Command Failure", contextID: "tool-command-fail", contextKind: "assistant"),
            mode: config.mode,
            tools: config.tools,
            toolContext: config.context,
            systemPrompt: "Use tools when available.",
            timeout: 2
        )
        try await harness.viewModel.waitForIdle(timeout: 3)
        await harness.viewModel.refresh()

        let trace = try await harness.store.traceProjection(runID: runID)
        let lastRequest = await adapter.lastRequest()
        try expect(harness.viewModel.state.activeStatus == .completed, "failed approved command should return to the model for a final answer")
        try expect(trace.sideEffects.contains(where: { $0.kind == .command && $0.status == .failed && $0.errorSummary?.text.contains("non-zero status") == true }), "non-zero command should record a failed command side effect")
        try expect(trace.evidence.contains(where: { $0.kind == AgentEvidenceKind.commandOutput.rawValue }), "failed command output evidence should be recorded")
        try expect(lastRequest?.messages.contains(where: { $0.role == .observation && $0.content.contains("status: failed") && $0.content.contains("Exit code: 1") }) == true, "model continuation should receive failed command output observation")
    }

    private static func expectOne<T>(_ values: [T], _ message: String) throws -> T {
        guard values.count == 1, let value = values.first else {
            throw HarnessError(description: message)
        }
        return value
    }

    private static func groundedFinalAnswer(
        _ text: String,
        basis: AgentKernelAnswerGroundingBasis,
        claims: [AgentKernelAnswerClaim] = []
    ) -> FixtureAgentKernelAdapter.ScriptedResponse {
        groundedFinalAnswer(
            text,
            grounding: AgentKernelAnswerGrounding(
                basis: basis,
                claims: claims
            )
        )
    }

    private static func groundedFinalAnswer(
        _ text: String,
        grounding: AgentKernelAnswerGrounding
    ) -> FixtureAgentKernelAdapter.ScriptedResponse {
        .events([
            .finalAnswer(
                AgentKernelFinalAnswer(
                    text: text,
                    grounding: grounding
                )
            )
        ])
    }

    private static func toolConfig(
        grant: AgentLocalFileGrant,
        runMode: AgentRunPermissionMode,
        adapter: any AgentKernelModelAdapter,
        modelConformanceProfile: AgentModelConformanceProfile? = nil
    ) -> (mode: AgentModelGatewayMode, tools: [AgentKernelToolSchema], context: AgentToolRunContext) {
        toolConfig(
            grants: [grant],
            runMode: runMode,
            adapter: adapter,
            modelConformanceProfile: modelConformanceProfile
        )
    }

    private static func toolConfig(
        grants: [AgentLocalFileGrant],
        runMode: AgentRunPermissionMode,
        adapter: any AgentKernelModelAdapter,
        modelConformanceProfile: AgentModelConformanceProfile? = nil,
        approximateLocation: AgentLocationContext? = nil
    ) -> (mode: AgentModelGatewayMode, tools: [AgentKernelToolSchema], context: AgentToolRunContext) {
        let tier = AgentModelGateway.tier(
            for: adapter.capabilities,
            conformanceProfile: modelConformanceProfile
        )
        let context = AgentToolRunContext(
            runMode: runMode,
            localGrants: grants,
            deniedScopes: [.network, .processControl, .privileged],
            approximateLocation: approximateLocation
        )
        let tools = AgentToolCatalog().visibleModelSchemas(
            providerTier: tier,
            runMode: runMode,
            localGrants: grants,
            deniedScopes: context.deniedScopes,
            supportedOperations: context.supportedOperations
        )
        let mode: AgentModelGatewayMode = tier == .tierAFullAgent ? .fullAgent : .constrainedStructuredText
        return (mode, tools, context)
    }

    private static func nativeMLXFixtureAdapter(
        target: AgentModelConformanceTarget,
        responses: [FixtureAgentKernelAdapter.ScriptedResponse]
    ) -> FixtureAgentKernelAdapter {
        let descriptor = AgentKernelModelDescriptor(
            id: target.adapterID,
            providerKind: target.providerKind,
            route: target.route,
            displayName: "Fixture Native MLX",
            modelName: target.modelID
        )
        return FixtureAgentKernelAdapter(
            descriptor: descriptor,
            capabilities: AgentKernelModelAdapterCapabilities(
                descriptor: descriptor,
                toolCallingMode: .native,
                structuredOutputReliability: .bestEffort,
                streamingMode: .events,
                limits: AgentKernelModelLimits(contextWindowTokens: 4_096)
            ),
            responses: responses
        )
    }

    private static func nativeMLXConformanceTarget(
        modelID: String,
        modelPath: String
    ) -> AgentModelConformanceTarget {
        AgentModelConformanceTarget(
            providerKind: .mlxLocal,
            route: .local,
            adapterID: AgentModelConformanceTarget.localMLXChatAdapterID,
            modelID: modelID,
            modelPath: modelPath,
            runtimeExecutablePath: "/usr/local/bin/mlx_lm.server",
            runtimeVersion: nil
        )
    }

    private static func nativeMLXConformanceProfile(
        target: AgentModelConformanceTarget
    ) -> AgentModelConformanceProfile {
        let pass = AgentModelConformanceProbeResult.passed("pass")
        return AgentModelConformanceProfile(
            target: target,
            plainChat: pass,
            structuredJSON: .failed("diagnostic JSON probe failed"),
            toolCall: pass,
            toolResultFollowUp: pass,
            latency: pass,
            derivedTier: .tierB
        )
    }

    private static func tierBFixtureAdapter(
        responses: [FixtureAgentKernelAdapter.ScriptedResponse]
    ) -> FixtureAgentKernelAdapter {
        let descriptor = AgentKernelModelDescriptor(
            id: "fixture.tier-b-text-protocol",
            providerKind: .fixture,
            route: .local,
            displayName: "Fixture Tier B Text Protocol"
        )
        return FixtureAgentKernelAdapter(
            descriptor: descriptor,
            capabilities: AgentKernelModelAdapterCapabilities(
                descriptor: descriptor,
                toolCallingMode: .textProtocol,
                structuredOutputReliability: .bestEffort,
                streamingMode: .snapshots,
                limits: AgentKernelModelLimits(contextWindowTokens: 4_096)
            ),
            responses: responses
        )
    }

    @MainActor
    private static func makeHarness(prefix: String) async throws -> Harness {
        let root = try makeTemporaryRoot(prefix: prefix)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let store = try AgentRunStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        return Harness(
            store: store,
            viewModel: AgentRunViewModel(store: store),
            workspace: workspace,
            grant: AgentLocalFileGrant(path: workspace.path, isDirectory: true)
        )
    }

    private static func makeTemporaryRoot(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    struct Harness {
        let store: AgentRunStore
        let viewModel: AgentRunViewModel
        let workspace: URL
        let grant: AgentLocalFileGrant
    }
}

@main
struct AgentToolCallingFixtureMain {
    static func main() async {
        do {
            try await AgentToolCallingFixtureHarness.run()
            print("Agent tool-calling fixture tests passed")
        } catch {
            fputs("Agent tool-calling fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
