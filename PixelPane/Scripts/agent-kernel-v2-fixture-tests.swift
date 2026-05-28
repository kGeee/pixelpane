import Foundation

enum AgentKernelFixtureHarness {
    struct HarnessError: Error, CustomStringConvertible {
        let description: String
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw HarnessError(description: message)
        }
    }

    static func json<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw HarnessError(description: "encoded JSON should be UTF-8")
        }
        return text
    }

    static func run() async throws {
        try testSessionLedger()
        try testTaskStateTransitions()
        try testBoundedPersistence()
        try testTranscriptControlPlaneSeparation()
        try testApprovalCancelResumeAndProgressGuards()
        try testToolRegistryAndSafetyPolicy()
        try testFileAndVisualContextTools()
        try testFiniteCommandTool()
        try await testProcessLifecycleTool()
        try testEvidenceVerifier()
        try testModelOutputNormalizer()
        try await testModelAdapterContract()
        try await testProtocolAdapters()
        try await testProviderAdapters()
        try await testChatRuntimeIntegration()
        try await testFixtureModels()
    }

    private static func testSessionLedger() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
        var firstLedger = AgentKernelSessionLedgerV2(sessionID: UUID())
        var secondLedger = AgentKernelSessionLedgerV2(sessionID: UUID())

        let firstEvent = firstLedger.append(
            .userMessage(AgentKernelBoundedTextV2("hello")),
            createdAt: fixedDate
        )
        let secondEvent = secondLedger.append(
            .assistantMessage(AgentKernelBoundedTextV2("other session")),
            createdAt: fixedDate
        )

        try expect(firstEvent.sequence == 0, "first session should start at sequence zero")
        try expect(secondEvent.sequence == 0, "second session should start at sequence zero")
        try expect(firstEvent.sessionID != secondEvent.sessionID, "session IDs should isolate ledgers")
        try expect(firstLedger.events.count == 1, "first ledger should store only its own event")
        try expect(secondLedger.events.count == 1, "second ledger should store only its own event")
    }

    private static func testTaskStateTransitions() throws {
        let toolCall = AgentKernelToolCallV2(name: "read_file", arguments: ["path": "README.md"])
        let approval = AgentKernelApprovalRequestV2(
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            riskClass: "read-only",
            reason: AgentKernelBoundedTextV2("Need file context."),
            displaySummary: AgentKernelBoundedTextV2("Read README.md")
        )
        var ledger = AgentKernelSessionLedgerV2()

        ledger.append(.userMessage(AgentKernelBoundedTextV2("Read README.md")))
        try expect(ledger.state == .planning, "user message should move task into planning")

        ledger.append(.modelCall(modelID: "fixture", messageCount: 1, toolNames: ["read_file"]))
        try expect(ledger.state == .callingModel, "model call should move task into callingModel")

        ledger.append(.modelResponse(modelID: "fixture", events: [.toolCall(toolCall)]))
        try expect(ledger.state == .observing, "valid model response should move task into observing")

        ledger.append(.toolProposal(toolCall))
        try expect(ledger.state == .validatingTool, "tool proposal should move task into validatingTool")

        ledger.append(.approvalRequested(approval))
        try expect(ledger.state == .awaitingApproval, "approval request should move task into awaitingApproval")

        ledger.append(
            .approvalResolved(
                AgentKernelApprovalResolutionV2(
                    approvalID: approval.id,
                    decision: .approved
                )
            )
        )
        try expect(ledger.state == .runningTool, "approved operation should move task into runningTool")

        ledger.append(
            .toolResult(
                AgentKernelToolResultV2(
                    toolCallID: toolCall.id,
                    toolName: toolCall.name,
                    status: .succeeded,
                    summary: AgentKernelBoundedTextV2("Read 10 lines.")
                )
            )
        )
        try expect(ledger.state == .observing, "tool result should move task into observing")

        ledger.append(
            .evidenceRecorded(
                AgentKernelEvidenceRecordV2(
                    sourceID: "tool.read_file",
                    kind: "file",
                    summary: AgentKernelBoundedTextV2("README.md"),
                    privacyClass: "local-file",
                    trustClass: "tool"
                )
            )
        )
        try expect(ledger.state == .verifying, "evidence should move task into verifying")

        ledger.append(
            .modelResponse(modelID: "fixture", events: [.malformedOutput("{")])
        )
        try expect(ledger.state == .repairing, "malformed model output should move task into repairing")

        ledger.append(
            .taskCompleted(
                AgentKernelTerminalReasonV2(
                    code: "answered",
                    summary: AgentKernelBoundedTextV2("Answered with evidence.")
                )
            )
        )
        try expect(ledger.state == .completed, "completion event should move task into completed")
    }

    private static func testBoundedPersistence() throws {
        let longText = String(repeating: "x", count: 32)
        var ledger = AgentKernelSessionLedgerV2(maxTextCharacters: 8)
        let bounded = ledger.boundedText(longText)
        ledger.append(.userMessage(bounded))
        ledger.append(
            .processStatus(
                AgentKernelProcessStatusV2(
                    processID: "process-1",
                    kind: .running,
                    summary: ledger.boundedText(longText),
                    metadata: ["pid": .int(123)]
                )
            )
        )

        try expect(bounded.text == "xxxxxxxx", "ledger should truncate persisted text")
        try expect(bounded.isTruncated, "ledger should record truncation")
        try expect(ledger.transcriptMessages.count == 1, "control-plane events should not enter transcript")
        try expect(ledger.transcriptMessages[0].content == "xxxxxxxx", "transcript should use bounded text")
    }

    private static func testTranscriptControlPlaneSeparation() throws {
        let toolCall = AgentKernelToolCallV2(
            name: "run_terminal_command",
            arguments: ["command": "npx serve . -l 3000"]
        )
        let approval = AgentKernelApprovalRequestV2(
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            riskClass: "side-effect",
            reason: AgentKernelBoundedTextV2("Run a local static server."),
            displaySummary: AgentKernelBoundedTextV2("Allow terminal in snehithnayak.github.io")
        )
        var ledger = AgentKernelSessionLedgerV2()

        ledger.append(.userMessage(AgentKernelBoundedTextV2("run the website")))
        ledger.append(.toolProposal(toolCall))
        ledger.append(.approvalRequested(approval))
        ledger.append(
            .approvalResolved(
                AgentKernelApprovalResolutionV2(
                    approvalID: approval.id,
                    decision: .approved,
                    reason: AgentKernelBoundedTextV2("User approved terminal.")
                )
            )
        )
        ledger.append(
            .processStatus(
                AgentKernelProcessStatusV2(
                    processID: "server-1",
                    kind: .running,
                    summary: AgentKernelBoundedTextV2("Accepting connections at http://localhost:3000")
                )
            )
        )
        ledger.append(
            .toolResult(
                AgentKernelToolResultV2(
                    toolCallID: toolCall.id,
                    toolName: toolCall.name,
                    status: .succeeded,
                    summary: AgentKernelBoundedTextV2("Server is listening on localhost:3000.")
                )
            )
        )
        ledger.append(.assistantMessage(AgentKernelBoundedTextV2("It is running on localhost:3000.")))

        let transcript = ledger.transcriptMessages
        let context = ledger.contextSnapshot()
        try expect(transcript.map(\.role) == [.user, .assistant], "transcript should contain only chat messages")
        try expect(ledger.controlEvents.count == 5, "control events should stay outside transcript")
        try expect(
            !transcript.contains { $0.content.contains("Allow terminal") },
            "approval UI text should not become a transcript turn"
        )
        try expect(
            context.observationMessages.allSatisfy { $0.role == .observation },
            "packed control context should use observation role"
        )
        try expect(
            !context.modelMessages.contains { $0.role == .user && $0.content.contains("Allow terminal") },
            "previous approval loop text must not be packed as a user message"
        )
        try expect(
            context.observationMessages.contains { $0.content.contains("localhost:3000") },
            "structured observations should still carry relevant tool/process results"
        )

        var packedLedger = AgentKernelSessionLedgerV2()
        packedLedger.append(.userMessage(AgentKernelBoundedTextV2("old question")))
        packedLedger.append(.toolResult(AgentKernelToolResultV2(toolName: "read_file", status: .succeeded, summary: AgentKernelBoundedTextV2("old file content should not be repacked"))))
        packedLedger.append(.assistantMessage(AgentKernelBoundedTextV2("old answer")))
        packedLedger.append(.userMessage(AgentKernelBoundedTextV2("current question")))
        packedLedger.append(.toolResult(AgentKernelToolResultV2(toolName: "list_folder", status: .succeeded, summary: AgentKernelBoundedTextV2("current folder evidence"))))
        let packedContext = packedLedger.packedContextSnapshot()
        try expect(
            packedContext.transcriptMessages.map(\.content).suffix(2) == ["old answer", "current question"],
            "packed context should preserve recent transcript continuity"
        )
        try expect(
            packedContext.observationMessages.contains { $0.content.contains("current folder evidence") },
            "packed context should include current-turn observations"
        )
        try expect(
            !packedContext.observationMessages.contains { $0.content.contains("old file content") },
            "packed context should not keep replaying old tool observations into new turns"
        )

        let projection = AgentKernelExportProjectionV2()
        let turns = projection.conversationTurns(from: ledger)
        try expect(turns.count == 1, "export projection should pair typed transcript turns")
        try expect(turns[0].question.text == "run the website", "export projection should preserve user text")
        try expect(turns[0].answer?.text == "It is running on localhost:3000.", "export projection should preserve assistant final text")

        let leakedProtocol = #"{"type":"tool_call","name":"stage_write_proposal","arguments":{"path":"short_story.txt"}}"#
        var failedLedger = AgentKernelSessionLedgerV2()
        failedLedger.append(.userMessage(AgentKernelBoundedTextV2("create a file")))
        failedLedger.append(.modelResponse(modelID: "fixture", events: [.malformedOutput(leakedProtocol)]))
        failedLedger.append(
            .taskFailed(
                AgentKernelTerminalReasonV2(
                    code: "malformed_model_output",
                    summary: AgentKernelBoundedTextV2("The model returned an invalid tool or control response.")
                )
            )
        )
        let failedTurns = projection.conversationTurns(from: failedLedger)
        let failedControl = projection.controlEventRecords(from: failedLedger)
        try expect(failedTurns.count == 1, "failed export projection should keep the user turn")
        try expect(failedTurns[0].answer == nil, "failed export projection should not invent assistant prose from control events")
        try expect(
            !failedControl.contains { $0.summary.text.contains(#""type":"tool_call""#) },
            "control export projection should summarize malformed model responses without raw protocol payloads"
        )
    }

    private static func testApprovalCancelResumeAndProgressGuards() throws {
        let guards = AgentKernelRuntimeGuardsV2(repeatedModelResponseLimit: 2)
        let sideEffectCall = AgentKernelToolCallV2(
            name: "run_terminal_command",
            arguments: ["command": "npm start"]
        )
        let readOnlyCall = AgentKernelToolCallV2(
            name: "read_file",
            arguments: ["path": "README.md"]
        )

        let approvalDecision = guards.approvalDecision(
            for: sideEffectCall,
            policy: AgentKernelToolPolicyV2(
                toolName: sideEffectCall.name,
                risk: .sideEffect,
                requiresApproval: true
            ),
            reason: AgentKernelBoundedTextV2("Starts a local process.")
        )
        guard case .requestApproval(let approval) = approvalDecision else {
            throw HarnessError(description: "side-effect tools should require approval")
        }

        let readOnlyDecision = guards.approvalDecision(
            for: readOnlyCall,
            policy: AgentKernelToolPolicyV2(
                toolName: readOnlyCall.name,
                risk: .readOnly,
                requiresApproval: false
            ),
            reason: AgentKernelBoundedTextV2("Read project context.")
        )
        try expect(readOnlyDecision == .proceed, "read-only tools should proceed without approval")

        var lifecycleLedger = AgentKernelSessionLedgerV2()
        lifecycleLedger.append(.userMessage(AgentKernelBoundedTextV2("start the server")))
        lifecycleLedger.append(.approvalRequested(approval))
        let resumeDecision = guards.resume(ledger: &lifecycleLedger, approvalID: approval.id)
        try expect(resumeDecision == .resumed, "resume should return resumed decision")
        try expect(lifecycleLedger.state == .runningTool, "resume should continue the approved operation")
        try expect(lifecycleLedger.transcriptMessages.count == 1, "resume should not add a chat turn")

        let cancelReason = AgentKernelTerminalReasonV2(
            code: "user_cancelled",
            summary: AgentKernelBoundedTextV2("User canceled the operation.")
        )
        let cancelDecision = guards.cancel(ledger: &lifecycleLedger, reason: cancelReason)
        try expect(cancelDecision == .canceled(cancelReason), "cancel should return canceled decision")
        try expect(lifecycleLedger.state == .canceled, "cancel should move task to canceled")
        try expect(lifecycleLedger.transcriptMessages.count == 1, "cancel should not add a chat turn")

        var duplicateLedger = AgentKernelSessionLedgerV2()
        duplicateLedger.append(.toolProposal(sideEffectCall))
        duplicateLedger.append(
            .toolResult(
                AgentKernelToolResultV2(
                    toolCallID: sideEffectCall.id,
                    toolName: sideEffectCall.name,
                    status: .succeeded,
                    summary: AgentKernelBoundedTextV2("Server is running.")
                )
            )
        )
        let repeatedSideEffect = AgentKernelToolCallV2(
            name: sideEffectCall.name,
            arguments: sideEffectCall.arguments
        )
        let duplicateDecision = guards.toolProposalDecision(
            for: repeatedSideEffect,
            ledger: duplicateLedger
        )
        guard case .block(let duplicateReason) = duplicateDecision else {
            throw HarnessError(description: "duplicate tool call after same result should block")
        }
        try expect(
            duplicateReason.code == "duplicate_tool_call_after_same_result",
            "duplicate block should use stable reason code"
        )

        let synthesisDecision = guards.modelResponseDecision(
            events: [.toolCall(repeatedSideEffect)],
            ledger: duplicateLedger
        )
        guard case .forceSynthesis(let synthesisReason) = synthesisDecision else {
            throw HarnessError(description: "repeated observed tool call should force synthesis")
        }
        try expect(
            synthesisReason.code == "repeated_observed_step",
            "synthesis guard should use stable reason code"
        )

        var timeoutLedger = AgentKernelSessionLedgerV2()
        timeoutLedger.append(.modelResponse(modelID: "fixture", events: [.timedOut]))
        let timeoutDecision = guards.modelResponseDecision(
            events: [.timedOut],
            ledger: timeoutLedger
        )
        guard case .block(let timeoutReason) = timeoutDecision else {
            throw HarnessError(description: "repeated timeout should block")
        }
        try expect(timeoutReason.code == "no_progress_model_loop", "timeout loop should use no-progress code")

        var emptyLedger = AgentKernelSessionLedgerV2()
        emptyLedger.append(.modelResponse(modelID: "fixture", events: [.emptyOutput]))
        let emptyDecision = guards.modelResponseDecision(
            events: [.emptyOutput],
            ledger: emptyLedger
        )
        guard case .block(let emptyReason) = emptyDecision else {
            throw HarnessError(description: "repeated empty output should block")
        }
        try expect(emptyReason.code == "no_progress_model_loop", "empty loop should use no-progress code")
    }

    private static func testToolRegistryAndSafetyPolicy() throws {
        let readFile = AgentKernelToolDefinitionV2(
            name: "read_file",
            summary: "Read a granted file.",
            inputArguments: [
                AgentKernelToolArgumentSchemaV2(
                    name: "path",
                    type: .string,
                    summary: "Granted file path."
                )
            ],
            outputType: AgentKernelToolIOTypeV2(
                name: "file_contents",
                summary: "Bounded file text and metadata."
            ),
            risk: .readOnly,
            scopeRequirements: [.grantedFileRead],
            requiresApproval: false
        )
        let finiteCommand = AgentKernelToolDefinitionV2(
            name: "run_finite_command",
            summary: "Run a finite command in a validated working directory.",
            inputArguments: [
                AgentKernelToolArgumentSchemaV2(
                    name: "command",
                    type: .string,
                    summary: "Command to run."
                ),
                AgentKernelToolArgumentSchemaV2(
                    name: "timeoutSeconds",
                    type: .integer,
                    summary: "Maximum runtime in seconds."
                )
            ],
            outputType: AgentKernelToolIOTypeV2(
                name: "command_result",
                summary: "Exit status and bounded output."
            ),
            risk: .sideEffect,
            scopeRequirements: [.workingDirectory],
            requiresApproval: true,
            denyRules: [
                AgentKernelToolDenyRuleV2(
                    argumentName: "command",
                    containsAny: ["sudo ", "rm -rf", "curl | sh"],
                    reasonCode: "blocked_command",
                    summary: AgentKernelBoundedTextV2("The command matches a blocked safety rule.")
                )
            ]
        )
        let registry = AgentKernelToolRegistryV2(definitions: [finiteCommand, readFile])
        let emptyLedger = AgentKernelSessionLedgerV2()

        try expect(
            registry.modelSchemas.map(\.name) == ["read_file", "run_finite_command"],
            "registry should expose deterministic model schemas"
        )

        let validRead = registry.validate(
            call: AgentKernelToolCallV2(
                name: "read_file",
                arguments: ["path": "/tmp/README.md"]
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.grantedFileRead]),
            ledger: emptyLedger
        )
        guard case .allowed(let allowedReadDefinition) = validRead else {
            throw HarnessError(description: "granted read-only tool should be allowed")
        }
        try expect(allowedReadDefinition.name == "read_file", "allowed decision should include definition")

        let malformedCommand = registry.validate(
            call: AgentKernelToolCallV2(
                name: "run_finite_command",
                arguments: ["command": "echo hi", "timeoutSeconds": "soon"]
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.workingDirectory]),
            ledger: emptyLedger
        )
        guard case .blocked(let malformedReason) = malformedCommand else {
            throw HarnessError(description: "malformed arguments should be blocked")
        }
        try expect(
            malformedReason.code == "malformed_tool_argument",
            "malformed arguments should use stable reason code"
        )

        let deniedScope = registry.validate(
            call: AgentKernelToolCallV2(
                name: "read_file",
                arguments: ["path": "/tmp/README.md"]
            ),
            grantedScopes: AgentKernelGrantedScopesV2(),
            ledger: emptyLedger
        )
        guard case .blocked(let deniedScopeReason) = deniedScope else {
            throw HarnessError(description: "missing scope should be blocked")
        }
        try expect(
            deniedScopeReason.code == "tool_scope_denied",
            "denied scope should use stable reason code"
        )

        let blockedCommand = registry.validate(
            call: AgentKernelToolCallV2(
                name: "run_finite_command",
                arguments: ["command": "sudo rm -rf /", "timeoutSeconds": "10"]
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.workingDirectory]),
            ledger: emptyLedger
        )
        guard case .blocked(let blockedCommandReason) = blockedCommand else {
            throw HarnessError(description: "blocked command should stay blocked")
        }
        try expect(
            blockedCommandReason.code == "blocked_command",
            "blocked commands should use policy reason code"
        )

        let approvalRequired = registry.validate(
            call: AgentKernelToolCallV2(
                name: "run_finite_command",
                arguments: ["command": "npm test", "timeoutSeconds": "120"],
                reason: "Run the project tests."
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.workingDirectory]),
            ledger: emptyLedger
        )
        guard case .approvalRequired(let approvalDefinition, let approvalRequest) = approvalRequired else {
            throw HarnessError(description: "side-effect command should require approval")
        }
        try expect(
            approvalDefinition.name == "run_finite_command",
            "approval decision should include definition"
        )
        try expect(
            approvalRequest.riskClass == AgentKernelToolRiskV2.sideEffect.rawValue,
            "approval request should include risk class"
        )

        let unknownTool = registry.validate(
            call: AgentKernelToolCallV2(name: "invented_tool", arguments: [:]),
            grantedScopes: AgentKernelGrantedScopesV2(),
            ledger: emptyLedger
        )
        guard case .blocked(let unknownToolReason) = unknownTool else {
            throw HarnessError(description: "unknown tools should be blocked")
        }
        try expect(
            unknownToolReason.code == "unknown_tool",
            "unknown tools should not be repairable proposals"
        )
    }

    private static func testFileAndVisualContextTools() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("pixel-pane-agent-kernel-v2-\(UUID().uuidString)")
        let subfolder = root.appendingPathComponent("notes")
        let grantedFile = root.appendingPathComponent("story.txt")
        let nestedFile = subfolder.appendingPathComponent("hat.md")
        let outsideFile = fileManager.temporaryDirectory
            .appendingPathComponent("pixel-pane-agent-kernel-v2-outside-\(UUID().uuidString).txt")
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.removeItem(at: outsideFile)
        }

        try fileManager.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try "A short story about a man with a blue hat.\n".write(to: grantedFile, atomically: true, encoding: .utf8)
        try "The fedora was hidden in the workshop.\n".write(to: nestedFile, atomically: true, encoding: .utf8)
        try "outside grant\n".write(to: outsideFile, atomically: true, encoding: .utf8)

        let grants = [
            LocalFileGrant(
                id: UUID(),
                path: root.standardizedFileURL.path,
                isDirectory: true,
                addedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ]
        let tools = AgentKernelLocalContextToolsV2(maxDirectoryEntries: 20, maxReadCharacters: 64)
        let registry = AgentKernelToolRegistryV2(definitions: AgentKernelLocalContextToolsV2.definitions)
        let ledger = AgentKernelSessionLedgerV2()

        let readValidation = registry.validate(
            call: AgentKernelToolCallV2(name: "read_file", arguments: ["path": grantedFile.path]),
            grantedScopes: AgentKernelGrantedScopesV2([.grantedFileRead]),
            ledger: ledger
        )
        guard case .allowed(let readDefinition) = readValidation else {
            throw HarnessError(description: "granted read_file should validate")
        }
        try expect(readDefinition.risk == .readOnly, "read_file should be read-only")

        let writeValidation = registry.validate(
            call: AgentKernelToolCallV2(
                name: "stage_write_proposal",
                arguments: [
                    "operation": "create",
                    "targetPath": "draft.txt",
                    "content": "A staged draft."
                ]
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.grantedFileWrite]),
            ledger: ledger
        )
        guard case .approvalRequired(let writeDefinition, let writeApproval) = writeValidation else {
            throw HarnessError(description: "stage_write_proposal should require approval")
        }
        try expect(writeDefinition.risk == .sideEffect, "write proposals should be side-effect tools")
        try expect(writeApproval.toolName == "stage_write_proposal", "write approval should carry tool name")

        let visualValidation = registry.validate(
            call: AgentKernelToolCallV2(name: "describe_visual_context"),
            grantedScopes: AgentKernelGrantedScopesV2([.visualContext]),
            ledger: ledger
        )
        guard case .allowed(let visualDefinition) = visualValidation else {
            throw HarnessError(description: "describe_visual_context should validate with visual scope")
        }
        try expect(visualDefinition.risk == .readOnly, "visual context should be read-only")

        guard case .success(let grantsOutput) = tools.listGrants(grants: grants) else {
            throw HarnessError(description: "listGrants should succeed with active grants")
        }
        try expect(grantsOutput.entries.count == 1, "listGrants should include active grant")
        try expect(!grantsOutput.sources.isEmpty, "listGrants should include source records")

        guard case .success(let folderOutput) = tools.listFolder(path: root.path, grants: grants) else {
            throw HarnessError(description: "listFolder should succeed for granted folder")
        }
        try expect(
            folderOutput.entries.contains { $0.displayName == "story.txt" },
            "listFolder should include granted folder entries"
        )
        try expect(!folderOutput.sources.isEmpty, "listFolder should include source records")

        guard case .success(let searchOutput) = tools.searchFiles(query: "hat", grants: grants) else {
            throw HarnessError(description: "searchFiles should succeed")
        }
        try expect(
            searchOutput.snippets.contains { $0.path.hasSuffix("/notes/hat.md") || $0.path.hasSuffix("/story.txt") },
            "searchFiles should find matching granted text, got \(searchOutput.snippets.map(\.path))"
        )
        try expect(!searchOutput.sources.isEmpty, "searchFiles should include source records")

        guard case .success(let readOutput) = tools.readFile(path: grantedFile.path, grants: grants) else {
            throw HarnessError(description: "readFile should succeed for a granted file")
        }
        try expect(readOutput.content.text.contains("blue hat"), "readFile should return bounded file text")
        try expect(!readOutput.sources.isEmpty, "readFile should include source records")

        guard case .failure(let outsideReadReason) = tools.readFile(path: outsideFile.path, grants: grants) else {
            throw HarnessError(description: "readFile should reject files outside grants")
        }
        try expect(outsideReadReason.code == "path_not_granted", "outside read should use path_not_granted")

        let stagedTarget = root.appendingPathComponent("draft.txt")
        guard case .success(let writeOutput) = tools.stageWriteProposal(
            operation: "create",
            targetPath: "draft.txt",
            content: "A staged draft about a hat.",
            grants: grants
        ) else {
            throw HarnessError(description: "stageWriteProposal should produce a staged proposal")
        }
        try expect(writeOutput.requiresApproval, "write proposals should remain approval-gated")
        try expect(writeOutput.proposal.targetPath == stagedTarget.standardizedFileURL.path, "write proposal should resolve inside grant")
        try expect(!fileManager.fileExists(atPath: stagedTarget.path), "stageWriteProposal must not write to disk")
        try expect(!writeOutput.sources.isEmpty, "stageWriteProposal should include source records")

        let visualState = AssistantVisualContextState(
            source: .capture,
            label: "Screen region",
            hasImageInput: true,
            ocrText: "Visible OCR text from the active capture.",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )
        guard case .success(let visualOutput) = tools.describeVisualContext(state: visualState) else {
            throw HarnessError(description: "describeVisualContext should return active visual state")
        }
        try expect(visualOutput.hasTransientImageInput, "visual context should report transient image input")
        try expect(visualOutput.imagePixelsPersisted == false, "visual context should not persist pixels")
        try expect(visualOutput.ocrExcerpt?.text.contains("Visible OCR") == true, "visual context should include bounded OCR")
        try expect(!visualOutput.sources.isEmpty, "visual context should include source records")
    }

    private static func testFiniteCommandTool() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("pixel-pane-finite-command-\(UUID().uuidString)")
        defer {
            try? fileManager.removeItem(at: root)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let commandTool = AgentKernelFiniteCommandToolV2(
            maxOutputBytes: 128,
            defaultTimeoutSeconds: 5,
            maxTimeoutSeconds: 10
        )
        let ledger = AgentKernelSessionLedgerV2()

        let allowedValidation = commandTool.validate(
            call: AgentKernelToolCallV2(
                name: "run_finite_command",
                arguments: [
                    "command": "printf hello",
                    "workingDirectory": root.path,
                    "timeoutSeconds": "5"
                ]
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.workingDirectory]),
            ledger: ledger
        )
        guard case .allowed(let finiteDefinition) = allowedValidation else {
            throw HarnessError(description: "low-risk finite command should validate")
        }
        try expect(finiteDefinition.name == "run_finite_command", "finite command definition should round-trip")

        let riskyValidation = commandTool.validate(
            call: AgentKernelToolCallV2(
                name: "run_finite_command",
                arguments: [
                    "command": "curl https://example.com",
                    "workingDirectory": root.path
                ]
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.workingDirectory]),
            ledger: ledger
        )
        guard case .approvalRequired(_, let riskyApproval) = riskyValidation else {
            throw HarnessError(description: "network finite command should require approval")
        }
        try expect(riskyApproval.riskClass == AgentKernelToolRiskV2.sideEffect.rawValue, "network approval should be side-effect risk")

        let installValidation = commandTool.validate(
            call: AgentKernelToolCallV2(
                name: "run_finite_command",
                arguments: [
                    "command": "npm install",
                    "workingDirectory": root.path
                ]
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.workingDirectory]),
            ledger: ledger
        )
        guard case .approvalRequired = installValidation else {
            throw HarnessError(description: "install finite command should require approval")
        }

        let privilegedValidation = commandTool.validate(
            call: AgentKernelToolCallV2(
                name: "run_finite_command",
                arguments: [
                    "command": "sudo whoami",
                    "workingDirectory": root.path
                ]
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.workingDirectory]),
            ledger: ledger
        )
        guard case .approvalRequired(_, let privilegedApproval) = privilegedValidation else {
            throw HarnessError(description: "privileged finite command should require approval")
        }
        try expect(privilegedApproval.riskClass == AgentKernelToolRiskV2.privileged.rawValue, "sudo approval should be privileged risk")

        let blockedValidation = commandTool.validate(
            call: AgentKernelToolCallV2(
                name: "run_finite_command",
                arguments: [
                    "command": "rm -rf /",
                    "workingDirectory": root.path
                ]
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.workingDirectory]),
            ledger: ledger
        )
        guard case .blocked(let blockedReason) = blockedValidation else {
            throw HarnessError(description: "destructive finite command should be blocked")
        }
        try expect(blockedReason.code == "block-destructive-root-removal", "blocked command should use policy rule id")

        let deniedScopeValidation = commandTool.validate(
            call: AgentKernelToolCallV2(
                name: "run_finite_command",
                arguments: [
                    "command": "pwd",
                    "workingDirectory": root.path
                ]
            ),
            grantedScopes: AgentKernelGrantedScopesV2(),
            ledger: ledger
        )
        guard case .blocked(let deniedScopeReason) = deniedScopeValidation else {
            throw HarnessError(description: "finite command without workingDirectory scope should block")
        }
        try expect(deniedScopeReason.code == "tool_scope_denied", "denied command scope should use registry reason")

        guard case .success(let successOutput) = commandTool.run(
            command: "printf hello",
            workingDirectory: root.path,
            allowedWorkingDirectories: [root.path],
            timeoutSeconds: 5
        ) else {
            throw HarnessError(description: "low-risk finite command should execute")
        }
        try expect(successOutput.observationKind == .succeeded, "successful command should be distinct")
        try expect(successOutput.stdout.text == "hello", "successful command should capture stdout")
        try expect(!successOutput.sources.isEmpty, "successful command should include source records")

        guard case .success(let emptyOutput) = commandTool.run(
            command: "true",
            workingDirectory: root.path,
            allowedWorkingDirectories: [root.path],
            timeoutSeconds: 5
        ) else {
            throw HarnessError(description: "empty finite command should execute")
        }
        try expect(emptyOutput.observationKind == .emptyOutput, "empty command output should be distinct")

        guard case .success(let nonZeroOutput) = commandTool.run(
            command: "echo nope >&2; exit 7",
            workingDirectory: root.path,
            allowedWorkingDirectories: [root.path],
            timeoutSeconds: 5
        ) else {
            throw HarnessError(description: "non-zero finite command should execute")
        }
        try expect(nonZeroOutput.observationKind == .nonZeroExit, "non-zero exit should be distinct")
        try expect(nonZeroOutput.exitCode == 7, "non-zero exit should preserve exit code")
        try expect(nonZeroOutput.stderr.text.contains("nope"), "non-zero exit should capture stderr")

        guard case .success(let timeoutOutput) = commandTool.run(
            command: "sleep 2",
            workingDirectory: root.path,
            allowedWorkingDirectories: [root.path],
            timeoutSeconds: 1
        ) else {
            throw HarnessError(description: "timeout finite command should return an observation")
        }
        try expect(timeoutOutput.observationKind == .timedOut, "timeout should be distinct")
        try expect(timeoutOutput.didTimeOut, "timeout output should mark didTimeOut")

        guard case .failure(let cwdReason) = commandTool.run(
            command: "pwd",
            workingDirectory: root.path,
            allowedWorkingDirectories: [root.appendingPathComponent("other").path],
            timeoutSeconds: 1
        ) else {
            throw HarnessError(description: "command outside allowed cwd roots should fail")
        }
        try expect(cwdReason.code == "working_directory_scope_denied", "cwd validation should use stable reason")
    }

    private static func testProcessLifecycleTool() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("pixel-pane-process-lifecycle-\(UUID().uuidString)")
        defer {
            try? fileManager.removeItem(at: root)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let lifecycle = AgentKernelProcessLifecycleToolV2(
            maxTailBytes: 2_000,
            initialOutputWaitMilliseconds: 250
        )
        let registry = AgentKernelToolRegistryV2(definitions: AgentKernelProcessLifecycleToolV2.definitions)
        let ledger = AgentKernelSessionLedgerV2()
        let sessionID = UUID()

        let startValidation = registry.validate(
            call: AgentKernelToolCallV2(
                name: "start_process",
                arguments: [
                    "command": "while true; do sleep 1; done",
                    "workingDirectory": root.path
                ]
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.workingDirectory, .processControl]),
            ledger: ledger
        )
        guard case .approvalRequired(_, let startApproval) = startValidation else {
            throw HarnessError(description: "start_process should require approval")
        }
        try expect(startApproval.toolName == "start_process", "start approval should carry process tool name")

        let statusValidation = registry.validate(
            call: AgentKernelToolCallV2(
                name: "process_status",
                arguments: ["processID": "generic-process"]
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.processControl]),
            ledger: ledger
        )
        guard case .allowed = statusValidation else {
            throw HarnessError(description: "process_status should be read-only when process scope is granted")
        }

        let serverCommand = """
        python3 - <<'PY'
        import http.server
        import socketserver
        import sys

        with socketserver.TCPServer(("127.0.0.1", 0), http.server.SimpleHTTPRequestHandler) as httpd:
            port = httpd.server_address[1]
            print(f"Serving at http://127.0.0.1:{port}", flush=True)
            httpd.serve_forever()
        PY
        """
        let startResult = await lifecycle.startProcess(
            command: serverCommand,
            workingDirectory: root.path,
            allowedWorkingDirectories: [root.path],
            ownerSessionID: sessionID,
            processID: "generic-server"
        )
        guard case .success(let started) = startResult else {
            throw HarnessError(description: "startProcess should start a generic long-running process")
        }
        try expect(started.status == .running, "started process should remain running")
        try expect(started.pid != nil, "started process should expose pid")
        try expect(started.detectedServer?.url?.hasPrefix("http://127.0.0.1:") == true, "server URL should be detected from output")
        try expect(started.detectedServer?.port != nil, "server port should be detected from output")
        try expect(!started.sources.isEmpty, "started process should include source records")

        let duplicateStart = await lifecycle.startProcess(
            command: serverCommand,
            workingDirectory: root.path,
            allowedWorkingDirectories: [root.path],
            ownerSessionID: sessionID,
            processID: "duplicate-server"
        )
        guard case .failure(let duplicateReason) = duplicateStart else {
            throw HarnessError(description: "duplicate running process should be rejected")
        }
        try expect(duplicateReason.code == "duplicate_process_start", "duplicate process starts should use stable reason")

        let statusResult = await lifecycle.status(processID: "generic-server")
        guard case .success(let status) = statusResult else {
            throw HarnessError(description: "status should return a managed process record")
        }
        try expect(status.status == .running, "status should preserve running state")
        try expect(status.detectedServer?.port == started.detectedServer?.port, "status should keep detected server metadata")

        let tailResult = await lifecycle.tailOutput(processID: "generic-server")
        guard case .success(let tail) = tailResult else {
            throw HarnessError(description: "tailOutput should return process output")
        }
        try expect(tail.stdoutTail.text.contains("http://127.0.0.1:"), "tailOutput should include bounded stdout")

        let stopValidation = registry.validate(
            call: AgentKernelToolCallV2(
                name: "stop_process",
                arguments: ["processID": "generic-server"]
            ),
            grantedScopes: AgentKernelGrantedScopesV2([.processControl]),
            ledger: ledger
        )
        guard case .approvalRequired(_, let stopApproval) = stopValidation else {
            throw HarnessError(description: "stop_process should require approval")
        }
        try expect(stopApproval.toolName == "stop_process", "stop approval should carry process tool name")

        let stopResult = await lifecycle.stopProcess(processID: "generic-server")
        guard case .success(let stopped) = stopResult else {
            throw HarnessError(description: "stopProcess should stop managed process")
        }
        try expect(stopped.status == .stopped, "stopped process should report stopped status")

        let deniedCwd = await lifecycle.startProcess(
            command: "while true; do sleep 1; done",
            workingDirectory: root.path,
            allowedWorkingDirectories: [root.appendingPathComponent("other").path],
            ownerSessionID: sessionID,
            processID: "denied-cwd"
        )
        guard case .failure(let cwdReason) = deniedCwd else {
            throw HarnessError(description: "process start outside allowed roots should fail")
        }
        try expect(cwdReason.code == "working_directory_scope_denied", "process cwd validation should use stable reason")
    }

    private static func testEvidenceVerifier() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("pixel-pane-evidence-\(UUID().uuidString)")
        let sourceFile = root.appendingPathComponent("source.txt")
        let proposedFile = root.appendingPathComponent("proposal.txt")
        defer {
            try? fileManager.removeItem(at: root)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try "Evidence source text.\n".write(to: sourceFile, atomically: true, encoding: .utf8)

        let grants = [
            LocalFileGrant(
                id: UUID(),
                path: root.standardizedFileURL.path,
                isDirectory: true,
                addedAt: Date(timeIntervalSince1970: 1_800_000_010)
            )
        ]
        let contextTools = AgentKernelLocalContextToolsV2(maxReadCharacters: 256)
        var ledger = AgentKernelSessionLedgerV2()
        let verifier = AgentKernelEvidenceVerifierV2()

        guard case .success(let readOutput) = contextTools.readFile(path: sourceFile.path, grants: grants) else {
            throw HarnessError(description: "evidence read setup should succeed")
        }
        ledger.append(.evidenceRecorded(AgentKernelEvidenceFactoryV2.fileRead(readOutput)))

        let fileExists = verifier.verify(.fileExists(path: sourceFile.path), ledger: ledger)
        try expect(fileExists.status == .verified, "file read evidence should verify file exists")
        try expect(!fileExists.evidenceIDs.isEmpty, "verified file claim should carry evidence IDs")

        guard case .success(let writeProposal) = contextTools.stageWriteProposal(
            operation: "create",
            targetPath: proposedFile.lastPathComponent,
            content: "Proposed content.",
            grants: grants
        ) else {
            throw HarnessError(description: "evidence write proposal setup should succeed")
        }
        ledger.append(.evidenceRecorded(AgentKernelEvidenceFactoryV2.writeProposal(writeProposal)))
        let stagedWriteClaim = verifier.verify(.fileChanged(path: writeProposal.proposal.targetPath), ledger: ledger)
        try expect(
            stagedWriteClaim.status == .needsTool,
            "staged write proposal should not verify an actual file change"
        )
        try expect(
            stagedWriteClaim.reason?.code == "file_changed_needs_write_evidence",
            "missing write evidence should use stable reason"
        )

        ledger.append(
            .evidenceRecorded(
                AgentKernelEvidenceFactoryV2.fileWrite(
                    path: writeProposal.proposal.targetPath,
                    byteCount: 17,
                    contentHash: "fixture-hash"
                )
            )
        )
        let completedWriteClaim = verifier.verify(.fileChanged(path: writeProposal.proposal.targetPath), ledger: ledger)
        try expect(completedWriteClaim.status == .verified, "completed write evidence should verify file changed")

        let commandTool = AgentKernelFiniteCommandToolV2(defaultTimeoutSeconds: 5, maxTimeoutSeconds: 10)
        guard case .success(let failedCommand) = commandTool.run(
            command: "echo failure >&2; exit 9",
            workingDirectory: root.path,
            allowedWorkingDirectories: [root.path],
            timeoutSeconds: 5
        ) else {
            throw HarnessError(description: "failed command evidence setup should execute")
        }
        ledger.append(.evidenceRecorded(AgentKernelEvidenceFactoryV2.finiteCommand(failedCommand)))
        let commandFailed = verifier.verify(.commandFailed("echo failure >&2; exit 9", exitCode: 9), ledger: ledger)
        try expect(commandFailed.status == .verified, "failed command evidence should verify failure diagnosis")
        let commandSucceeded = verifier.verify(.commandSucceeded("echo failure >&2; exit 9"), ledger: ledger)
        try expect(commandSucceeded.status == .needsTool, "failed command evidence should not verify success")

        guard case .success(let taggedBuild) = commandTool.run(
            command: "printf build-ok",
            workingDirectory: root.path,
            allowedWorkingDirectories: [root.path],
            timeoutSeconds: 5
        ) else {
            throw HarnessError(description: "tagged build evidence setup should execute")
        }
        ledger.append(
            .evidenceRecorded(
                AgentKernelEvidenceFactoryV2.finiteCommand(
                    taggedBuild,
                    claimTags: [.buildOrTest]
                )
            )
        )
        let buildPassed = verifier.verify(.buildOrTestPassed(), ledger: ledger)
        try expect(buildPassed.status == .verified, "tagged successful build/test command should verify build/test passed")

        let processRecord = AgentKernelManagedProcessRecordV2(
            processID: "server-fixture",
            command: "fixture server",
            workingDirectory: root.path,
            ownerSessionID: ledger.sessionID,
            pid: 12345,
            startedAt: Date(timeIntervalSince1970: 1_800_000_011),
            status: .running,
            exitCode: nil,
            detectedServer: AgentKernelLocalServerProbeV2(
                url: "http://127.0.0.1:49152",
                port: 49152,
                isListening: nil,
                httpStatusCode: nil
            ),
            stdoutTail: AgentKernelBoundedTextV2("Serving at http://127.0.0.1:49152"),
            stderrTail: AgentKernelBoundedTextV2(""),
            sources: [
                AgentKernelToolSourceRecordV2(
                    id: "managed-process:server-fixture",
                    kind: "managed_process",
                    path: root.path,
                    displayName: "server-fixture",
                    summary: AgentKernelBoundedTextV2("Managed process is running.")
                )
            ]
        )
        ledger.append(.evidenceRecorded(AgentKernelEvidenceFactoryV2.managedProcess(processRecord)))
        let processAlive = verifier.verify(.processAlive(processID: "server-fixture"), ledger: ledger)
        try expect(processAlive.status == .verified, "running process evidence should verify process alive")
        let portBeforeProbe = verifier.verify(.portListening(49152), ledger: ledger)
        try expect(portBeforeProbe.status == .needsTool, "detected port without listener probe should not verify listening")

        ledger.append(
            .evidenceRecorded(
                AgentKernelEvidenceFactoryV2.localServerProbe(
                    AgentKernelLocalServerProbeV2(
                        url: "http://127.0.0.1:49152",
                        port: 49152,
                        isListening: true,
                        httpStatusCode: 200
                    )
                )
            )
        )
        let portListening = verifier.verify(.portListening(49152), ledger: ledger)
        try expect(portListening.status == .verified, "listener probe evidence should verify port listening")
        let urlResponds = verifier.verify(.urlResponds("http://127.0.0.1:49152"), ledger: ledger)
        try expect(urlResponds.status == .verified, "HTTP probe evidence should verify URL responds")

        ledger.append(.taskCanceled(AgentKernelTerminalReasonV2(code: "user_cancelled", summary: AgentKernelBoundedTextV2("Canceled."))))
        let taskCanceled = verifier.verify(.taskCanceled(), ledger: ledger)
        try expect(taskCanceled.status == .verified, "task canceled event should verify cancellation")

        ledger.append(.evidenceRecorded(AgentKernelEvidenceFactoryV2.modelStatement("The site is running.")))
        let modelStatement = verifier.verify(.modelStatement("The site is running."), ledger: ledger)
        try expect(modelStatement.status == .blocked, "model statements should not verify factual final claims")
        try expect(
            modelStatement.reason?.code == "model_statement_not_deterministic_evidence",
            "model statement block should use stable reason"
        )

        let unsupported = verifier.verify(.unsupported("The task is complete for an untyped reason."), ledger: ledger)
        try expect(unsupported.status == .blocked, "unsupported claims should block final answer")

        let finalVerification = verifier.verifyFinalClaims(
            [
                .fileExists(path: sourceFile.path),
                .processAlive(processID: "server-fixture"),
                .portListening(49152),
                .urlResponds("http://127.0.0.1:49152")
            ],
            ledger: ledger
        )
        try expect(finalVerification.canAnswer, "final answer should be allowed only when all claims verify")
        let blockedFinalVerification = verifier.verifyFinalClaims(
            [
                .fileExists(path: sourceFile.path),
                .unsupported("Unsupported final claim.")
            ],
            ledger: ledger
        )
        try expect(!blockedFinalVerification.canAnswer, "unsupported final claims should block final answer")
        try expect(!blockedFinalVerification.blockingReasons.isEmpty, "blocked final answer should expose reasons")
    }

    private static func testModelOutputNormalizer() throws {
        let normalizer = AgentKernelModelOutputNormalizerV2()
        let tools = [
            AgentKernelToolSchemaV2(
                name: "probe_local_server",
                summary: "Probe localhost.",
                arguments: [
                    AgentKernelToolArgumentSchemaV2(
                        name: "url",
                        type: .string,
                        isRequired: false,
                        summary: "Optional loopback URL."
                    ),
                    AgentKernelToolArgumentSchemaV2(
                        name: "port",
                        type: .integer,
                        isRequired: false,
                        summary: "Optional loopback port."
                    )
                ]
            )
        ]

        let toolEvent = normalizer.normalize(
            event: .finalAnswer(#"{"type":"tool_call","name":"probe_local_server","arguments":{"url":"http://localhost:8000"},"reason":"Check port 8000."}"#),
            tools: tools
        )
        guard case .toolCall(let call) = toolEvent else {
            throw HarnessError(description: "protocol-shaped tool-call text should normalize to a tool call")
        }
        try expect(call.name == "probe_local_server", "normalized tool call should preserve tool name")
        try expect(call.arguments["url"] == "http://localhost:8000", "normalized tool call should preserve string arguments")

        let finalEvent = normalizer.normalize(
            event: .finalAnswer(#"{"type":"final_answer","text":"Done."}"#),
            tools: tools
        )
        try expect(finalEvent == .finalAnswer("Done."), "protocol-shaped final answer should normalize to prose")

        let legitimateJSON = #"{"status":"ok","items":[1,2,3]}"#
        let jsonEvent = normalizer.normalize(event: .finalAnswer(legitimateJSON), tools: tools)
        try expect(jsonEvent == .finalAnswer(legitimateJSON), "non-protocol JSON answers should remain user-facing prose")

        let unknownTool = normalizer.normalize(
            event: .finalAnswer(#"{"type":"tool_call","name":"unknown_tool","arguments":{}}"#),
            tools: tools
        )
        guard case .malformedOutput = unknownTool else {
            throw HarnessError(description: "unknown protocol tool calls should be rejected")
        }

        let unknownArgument = normalizer.normalize(
            event: .finalAnswer(#"{"type":"tool_call","name":"probe_local_server","arguments":{"path":"README.md"}}"#),
            tools: tools
        )
        guard case .malformedOutput = unknownArgument else {
            throw HarnessError(description: "unknown protocol tool arguments should be rejected")
        }

        let wrongType = normalizer.normalize(
            event: .finalAnswer(#"{"type":"tool_call","name":"probe_local_server","arguments":{"port":"not-a-number"}}"#),
            tools: tools
        )
        guard case .malformedOutput = wrongType else {
            throw HarnessError(description: "malformed protocol tool argument types should be rejected")
        }

        let writeTools = [
            AgentKernelToolSchemaV2(
                name: "stage_write_proposal",
                summary: "Stage write.",
                arguments: [
                    AgentKernelToolArgumentSchemaV2(
                        name: "operation",
                        type: .string,
                        summary: "One of create, replace, or append."
                    ),
                    AgentKernelToolArgumentSchemaV2(
                        name: "targetPath",
                        type: .string,
                        summary: "Target file path."
                    ),
                    AgentKernelToolArgumentSchemaV2(
                        name: "content",
                        type: .string,
                        summary: "Proposed content."
                    )
                ]
            )
        ]
        let repairedWrite = normalizer.normalize(
            event: .finalAnswer(#"{"type":"tool_call","name":"stage_write_proposal","arguments":{"path":"short_story.txt","content":"The Last Light"},"reason":"The user wants a text file."}"#),
            tools: writeTools
        )
        guard case .toolCall(let repairedWriteCall) = repairedWrite else {
            throw HarnessError(description: "safe staged-write argument aliases should be repaired")
        }
        try expect(repairedWriteCall.arguments["targetPath"] == "short_story.txt", "staged-write path alias should repair to targetPath")
        try expect(repairedWriteCall.arguments["operation"] == "create", "staged-write missing operation should default to create")
        try expect(repairedWriteCall.arguments["path"] == nil, "repaired staged-write call should not keep the alias argument")
    }

    private static func testModelAdapterContract() async throws {
        let descriptor = AgentKernelModelDescriptorV2(
            id: "fixture.native",
            providerKind: .fixture,
            route: .local,
            displayName: "Fixture Native",
            modelName: "scripted"
        )
        let capabilities = AgentKernelModelAdapterCapabilitiesV2(
            descriptor: descriptor,
            inputModalities: [.text, .image],
            outputModalities: [.text],
            toolCallingMode: .native,
            structuredOutputReliability: .strict,
            streamingMode: .events,
            limits: AgentKernelModelLimitsV2(
                contextWindowTokens: 16_384,
                maxPromptCharacters: 64_000,
                maxOutputTokens: 2_048
            )
        )
        let adapter = FixtureAgentKernelAdapterV2(
            descriptor: descriptor,
            capabilities: capabilities,
            responses: [
                .events([
                    AgentKernelModelAdapterEventV2.snapshot("Working"),
                    AgentKernelModelAdapterEventV2.toolCall(
                        AgentKernelToolCallV2(
                            name: "read_file",
                            arguments: ["path": "README.md"],
                            reason: "Need source."
                        )
                    )
                ])
            ]
        )
        let requestID = UUID()
        let toolSchema = AgentKernelToolSchemaV2(
            name: "read_file",
            summary: "Read a granted local file.",
            requiredArguments: ["path"]
        )
        let request = AgentKernelModelAdapterRequestV2(
            id: requestID,
            messages: [
                AgentKernelMessageV2(role: .user, content: "Read README.md")
            ],
            tools: [toolSchema],
            attachments: [
                AgentKernelModelAttachmentV2(
                    modality: .image,
                    label: "Transient capture",
                    transientOnly: true,
                    metadata: ["pixelsPersisted": .bool(false)]
                )
            ],
            requestedMaxOutputTokens: 512,
            responseFormat: .native
        )

        let response = await adapter.response(for: request)
        let received = await adapter.lastRequest()
        try expect(response.requestID == requestID, "adapter response should preserve request ID")
        try expect(response.descriptor == descriptor, "adapter response should carry provider-neutral descriptor")
        try expect(response.events.count == 2, "adapter response should preserve streaming-capable events")
        try expect(response.modelEvents.count == 1, "snapshots should not become final model events")
        guard case .toolCall(let call) = response.modelEvents[0] else {
            throw HarnessError(description: "native adapter should convert tool event")
        }
        try expect(call.name == "read_file", "native adapter should preserve tool call name")
        try expect(call.arguments["path"] == "README.md", "native adapter should preserve tool arguments")
        try expect(received?.tools == [toolSchema], "adapter should receive provider-neutral tool schemas")
        try expect(received?.attachments.first?.transientOnly == true, "adapter request should preserve transient attachments")
        try expect(capabilities.descriptor.route == .local, "capabilities should expose local/cloud route")
        try expect(capabilities.inputModalities.contains(.image), "capabilities should expose image support")
        try expect(capabilities.legacyCapabilities.supportsNativeToolCalling, "adapter capabilities should bridge to legacy kernel model capabilities")
        try expect(capabilities.limits.contextWindowTokens == 16_384, "capabilities should expose context limit")

        let cloudDescriptor = AgentKernelModelDescriptorV2(
            id: "fixture.cloud",
            providerKind: .pixelPaneCloud,
            route: .cloud,
            displayName: "Fixture Cloud"
        )
        let cloudCapabilities = AgentKernelModelAdapterCapabilitiesV2(
            descriptor: cloudDescriptor,
            toolCallingMode: .textProtocol,
            structuredOutputReliability: .bestEffort,
            streamingMode: .snapshots,
            isAvailable: false,
            unavailableReason: AgentKernelBoundedTextV2("Cloud Mode is disabled.")
        )
        try expect(cloudCapabilities.descriptor.route == .cloud, "capabilities should represent cloud route without provider-specific policy")
        try expect(!cloudCapabilities.isAvailable, "capabilities should expose honest availability")
        try expect(
            cloudCapabilities.unavailableReason?.text == "Cloud Mode is disabled.",
            "capabilities should carry bounded unavailable reason"
        )
    }

    private static func testProtocolAdapters() async throws {
        let descriptor = AgentKernelModelDescriptorV2(
            id: "fixture.protocol",
            providerKind: .fixture,
            route: .local,
            displayName: "Fixture Protocol"
        )
        let request = AgentKernelModelAdapterRequestV2(
            messages: [
                AgentKernelMessageV2(role: .user, content: "Read README.md")
            ],
            tools: [
                AgentKernelToolSchemaV2(
                    name: "read_file",
                    summary: "Read a granted local file.",
                    requiredArguments: ["path"]
                )
            ],
            requestedMaxOutputTokens: 256
        )

        let nativeUpstream = FixtureAgentKernelAdapterV2(
            descriptor: descriptor,
            responses: [
                .toolCall(name: "read_file", arguments: ["path": "README.md"], reason: "Need context.")
            ]
        )
        let native = AgentKernelNativeToolCallAdapterV2(upstream: nativeUpstream)
        let nativeResponse = await native.response(for: request)
        let nativeRequest = await nativeUpstream.lastRequest()
        try expect(native.capabilities.toolCallingMode == .native, "native wrapper should force native tool mode")
        try expect(nativeRequest?.responseFormat == .native, "native wrapper should request native format upstream")
        guard case .toolCall(let nativeCall) = nativeResponse.modelEvents.first else {
            throw HarnessError(description: "native wrapper should preserve tool calls")
        }
        try expect(nativeCall.arguments["path"] == "README.md", "native wrapper should preserve arguments")

        let parser = AgentKernelTextProtocolParserV2()
        let finalParse = parser.parse(
            #"{"type":"final_answer","text":"Done."}"#,
            tools: request.tools
        )
        guard case .success(.finalAnswer(let finalText)) = finalParse else {
            throw HarnessError(description: "text protocol parser should parse final answer")
        }
        try expect(finalText == "Done.", "text protocol parser should preserve final answer")

        let toolParse = parser.parse(
            #"{"type":"tool_call","name":"read_file","arguments":{"path":"README.md"},"reason":"Need context."}"#,
            tools: request.tools
        )
        guard case .success(.toolCall(let parsedCall)) = toolParse else {
            throw HarnessError(description: "text protocol parser should parse tool call")
        }
        try expect(parsedCall.name == "read_file", "text protocol parser should preserve tool name")
        try expect(parsedCall.arguments["path"] == "README.md", "text protocol parser should preserve tool arguments")

        let missingArgument = parser.parse(
            #"{"type":"tool_call","name":"read_file","arguments":{}}"#,
            tools: request.tools
        )
        guard case .failure(let missingArgumentReason) = missingArgument else {
            throw HarnessError(description: "text protocol parser should reject missing required arguments")
        }
        try expect(
            missingArgumentReason.code == "text_protocol_missing_tool_argument",
            "missing arguments should use stable parser reason"
        )
        let partialMissingArgumentCall = parser.partialToolCallForValidation(
            #"{"type":"tool_call","name":"read_file","arguments":{}}"#,
            tools: request.tools
        )
        try expect(partialMissingArgumentCall?.name == "read_file", "adapter recovery should preserve known partial tool calls for runtime validation")
        try expect(partialMissingArgumentCall?.arguments.isEmpty == true, "partial tool-call recovery should preserve missing arguments as missing")

        let extraArgument = parser.parse(
            #"{"type":"tool_call","name":"read_file","arguments":{"path":"README.md","targetPath":"note.txt"}}"#,
            tools: request.tools
        )
        guard case .failure(let extraArgumentReason) = extraArgument else {
            throw HarnessError(description: "text protocol parser should reject unknown tool arguments")
        }
        try expect(
            extraArgumentReason.code == "text_protocol_unknown_tool_argument",
            "unknown arguments should use stable parser reason"
        )

        let typedTools = [
            AgentKernelToolSchemaV2(
                name: "probe_local_server",
                summary: "Probe localhost.",
                arguments: [
                    AgentKernelToolArgumentSchemaV2(
                        name: "port",
                        type: .integer,
                        isRequired: false,
                        summary: "Optional localhost port."
                    )
                ]
            )
        ]
        let malformedTypedArgument = parser.parse(
            #"{"type":"tool_call","name":"probe_local_server","arguments":{"port":"not-a-number"}}"#,
            tools: typedTools
        )
        guard case .failure(let malformedTypedArgumentReason) = malformedTypedArgument else {
            throw HarnessError(description: "text protocol parser should reject malformed typed arguments")
        }
        try expect(
            malformedTypedArgumentReason.code == "text_protocol_malformed_tool_argument",
            "malformed typed arguments should use stable parser reason"
        )

        let bareJSONAnswer = parser.parse(
            #"{"status":"ok","items":[1,2,3]}"#,
            tools: request.tools
        )
        guard case .failure(let bareJSONReason) = bareJSONAnswer else {
            throw HarnessError(description: "text protocol parser should reject protocol-mode JSON without an envelope")
        }
        try expect(
            bareJSONReason.code == "text_protocol_missing_type",
            "protocol-mode bare JSON should fail with a stable missing-type reason"
        )

        let finalTransport = FixtureTextProtocolTransportV2(
            responses: [.text(#"{"type":"final_answer","text":"All set."}"#)]
        )
        let textAdapter = AgentKernelTextProtocolAdapterV2(
            descriptor: descriptor,
            transport: finalTransport
        )
        let finalResponse = await textAdapter.response(for: request)
        let finalPrompts = await finalTransport.receivedPrompts()
        guard case .finalAnswer(let answer) = finalResponse.modelEvents.first else {
            throw HarnessError(description: "text protocol adapter should emit final answer")
        }
        try expect(answer == "All set.", "text protocol adapter should preserve final answer")
        try expect(finalResponse.descriptor == descriptor, "text protocol adapter should carry descriptor")
        try expect(textAdapter.capabilities.toolCallingMode == .textProtocol, "text protocol adapter should report text protocol mode")
        try expect(finalPrompts.count == 1, "valid text protocol response should not need repair")
        try expect(finalPrompts[0].contains("Return exactly one JSON object"), "text protocol prompt should describe output format")
        try expect(finalPrompts[0].contains("path: string, required"), "text protocol prompt should expose full argument schemas")
        try expect(!finalPrompts[0].contains("run terminal"), "text protocol prompt should not encode product workflow policy")

        let partialToolTransport = FixtureTextProtocolTransportV2(
            responses: [
                .text(#"{"type":"tool_call","name":"read_file","arguments":{}}"#)
            ]
        )
        let partialToolAdapter = AgentKernelTextProtocolAdapterV2(
            descriptor: descriptor,
            transport: partialToolTransport
        )
        let partialToolResponse = await partialToolAdapter.response(for: request)
        let partialToolPrompts = await partialToolTransport.receivedPrompts()
        guard case .toolCall(let partialToolCall) = partialToolResponse.modelEvents.first else {
            throw HarnessError(description: "text protocol adapter should pass known partial tool calls to runtime validation")
        }
        try expect(partialToolCall.name == "read_file", "partial text protocol tool call should preserve the tool name")
        try expect(partialToolCall.arguments.isEmpty, "partial text protocol tool call should preserve missing arguments")
        try expect(partialToolPrompts.count == 1, "partial known tool calls should not need a repair model call before runtime validation")
        try expect(partialToolResponse.diagnostics?.text.isEmpty == false, "partial known tool calls should preserve diagnostics")

        let repairTransport = FixtureTextProtocolTransportV2(
            responses: [
                .text("not json"),
                .text(#"{"type":"tool_call","name":"read_file","arguments":{"path":"README.md"}}"#)
            ]
        )
        let repairAdapter = AgentKernelTextProtocolAdapterV2(
            descriptor: descriptor,
            transport: repairTransport
        )
        let repairedResponse = await repairAdapter.response(for: request)
        let repairPrompts = await repairTransport.receivedPrompts()
        guard case .toolCall(let repairedCall) = repairedResponse.modelEvents.first else {
            throw HarnessError(description: "text protocol adapter should repair one malformed response")
        }
        try expect(repairedCall.arguments["path"] == "README.md", "repair boundary should return parsed tool call")
        try expect(repairPrompts.count == 2, "text protocol adapter should make one bounded repair attempt")
        try expect(
            repairedResponse.diagnostics?.text.isEmpty == false,
            "repaired response should keep bounded diagnostics"
        )

        let malformedTransport = FixtureTextProtocolTransportV2(
            responses: [
                .text("not json"),
                .text("{still bad")
            ]
        )
        let malformedAdapter = AgentKernelTextProtocolAdapterV2(
            descriptor: descriptor,
            transport: malformedTransport
        )
        let malformedResponse = await malformedAdapter.response(for: request)
        guard case .malformedOutput = malformedResponse.modelEvents.first else {
            throw HarnessError(description: "text protocol adapter should report malformed output after bounded repair")
        }

        let timeoutTransport = FixtureTextProtocolTransportV2(responses: [.timedOut])
        let timeoutAdapter = AgentKernelTextProtocolAdapterV2(
            descriptor: descriptor,
            transport: timeoutTransport
        )
        let timeoutResponse = await timeoutAdapter.response(for: request)
        try expect(timeoutResponse.modelEvents == [.timedOut], "text protocol adapter should preserve timeout")

        let repeatedTransport = FixtureTextProtocolTransportV2(
            responses: [
                .text(#"{"type":"tool_call","name":"read_file","arguments":{"path":"README.md"}}"#),
                .text(#"{"type":"tool_call","name":"read_file","arguments":{"path":"README.md"}}"#)
            ]
        )
        let repeatedAdapter = AgentKernelTextProtocolAdapterV2(
            descriptor: descriptor,
            transport: repeatedTransport
        )
        let firstRepeated = await repeatedAdapter.response(for: request)
        let secondRepeated = await repeatedAdapter.response(for: request)
        guard
            case .toolCall(let firstRepeatedCall) = firstRepeated.modelEvents.first,
            case .toolCall(let secondRepeatedCall) = secondRepeated.modelEvents.first
        else {
            throw HarnessError(description: "repeated text protocol responses should emit tool calls")
        }
        try expect(
            firstRepeatedCall.name == secondRepeatedCall.name
                && firstRepeatedCall.arguments == secondRepeatedCall.arguments
                && firstRepeatedCall.reason == secondRepeatedCall.reason,
            "text protocol adapter should preserve repeated calls so runtime guards can block them"
        )
    }

    private static func testProviderAdapters() async throws {
        let descriptor = AgentKernelModelDescriptorV2(
            id: "fixture-backend.v2",
            providerKind: .mlxLocal,
            route: .local,
            displayName: "Fixture Backend"
        )
        let backend = FixtureAIBackendV2(
            id: "fixture-backend",
            displayName: "Fixture Backend",
            capabilities: AIBackendCapabilities(
                text: .available(.mlxText),
                image: .unavailable(.imageInputUnsupported),
                contextWindowTokens: 4_096,
                maxPromptCharacters: 12_000,
                maxOutputTokens: 1_024
            ),
            responses: [
                [.snapshot("Plain response."), .completed],
                [.snapshot(#"{"type":"tool_call","name":"read_file","arguments":{"path":"README.md"}}"#), .completed]
            ]
        )
        let capabilities = AgentKernelModelAdapterCapabilitiesV2.aiBackendBridge(
            descriptor: descriptor,
            backendCapabilities: await backend.capabilities()
        )
        let adapter = AgentKernelAIBackendAdapterV2(
            descriptor: descriptor,
            backend: backend,
            capabilities: capabilities,
            preferredProvider: .mlxText
        )
        try expect(adapter.capabilities.descriptor.providerKind == .mlxLocal, "AIBackend bridge should keep provider kind")
        try expect(adapter.capabilities.descriptor.route == .local, "AIBackend bridge should preserve local route")
        try expect(adapter.capabilities.inputModalities == [.text], "AIBackend bridge should map text/image capabilities")
        try expect(adapter.capabilities.toolCallingMode == .textProtocol, "AIBackend bridge should expose text protocol mode")

        let plainRequest = AgentKernelModelAdapterRequestV2(
            messages: [AgentKernelMessageV2(role: .user, content: "Say hi")],
            requestedMaxOutputTokens: 128
        )
        let plainResponse = await adapter.response(for: plainRequest)
        guard case .finalAnswer(let plainAnswer) = plainResponse.modelEvents.first else {
            throw HarnessError(description: "AIBackend bridge should return plain final answer")
        }
        try expect(plainAnswer == "Plain response.", "AIBackend bridge should preserve plain backend text")

        let toolRequest = AgentKernelModelAdapterRequestV2(
            messages: [AgentKernelMessageV2(role: .user, content: "Read README.md")],
            tools: [
                AgentKernelToolSchemaV2(
                    name: "read_file",
                    summary: "Read a granted local file.",
                    requiredArguments: ["path"]
                )
            ],
            requestedMaxOutputTokens: 128,
            responseFormat: .textProtocol
        )
        let toolResponse = await adapter.response(for: toolRequest)
        guard case .toolCall(let bridgeCall) = toolResponse.modelEvents.first else {
            throw HarnessError(description: "AIBackend bridge should parse text protocol tool call")
        }
        try expect(bridgeCall.name == "read_file", "AIBackend bridge should preserve tool call name")
        try expect(bridgeCall.arguments["path"] == "README.md", "AIBackend bridge should preserve tool arguments")

        let backendRequests = await backend.requests()
        try expect(backendRequests.count == 2, "AIBackend bridge should call backend for each request")
        try expect(backendRequests[0].preferredProvider == .mlxText, "AIBackend bridge should preserve preferred provider")
        try expect(
            backendRequests[1].prompt.contains("Return exactly one JSON object"),
            "AIBackend bridge should use minimal text protocol prompt for tool requests"
        )

        let unavailableDescriptor = AgentKernelModelDescriptorV2(
            id: "unavailable.v2",
            providerKind: .appleLocal,
            route: .local,
            displayName: "Unavailable"
        )
        let unavailable = AgentKernelModelAdapterCapabilitiesV2.aiBackendBridge(
            descriptor: unavailableDescriptor,
            backendCapabilities: AIBackendCapabilities(
                text: .unavailable(.appleModelNotReady),
                image: .unavailable(.imageInputUnsupported),
                contextWindowTokens: nil,
                maxPromptCharacters: 12_000,
                maxOutputTokens: 1_024
            )
        )
        try expect(!unavailable.isAvailable, "provider adapter should honestly report unavailable providers")
        try expect(unavailable.unavailableReason?.text.isEmpty == false, "unavailable providers should carry a reason")

        let openAIDescriptor = AgentKernelModelDescriptorV2(
            id: "openai-compatible.local.test",
            providerKind: .openAICompatible,
            route: .local,
            displayName: "OpenAI-Compatible Local",
            modelName: "llama-test"
        )
        let openAIAdapter = AgentKernelOpenAICompatibleAdapterV2(
            descriptor: openAIDescriptor,
            endpoint: URL(string: "http://127.0.0.1:11434/v1/chat/completions")!,
            apiKey: "test-key",
            capabilities: AgentKernelModelAdapterCapabilitiesV2(
                descriptor: openAIDescriptor,
                toolCallingMode: .textProtocol,
                structuredOutputReliability: .bestEffort,
                streamingMode: .unsupported,
                isAvailable: true
            )
        )
        let urlRequest = try openAIAdapter.requestForTesting(prompt: "hello", maxOutputTokens: 64)
        try expect(urlRequest.url?.absoluteString == "http://127.0.0.1:11434/v1/chat/completions", "OpenAI-compatible adapter should preserve endpoint")
        try expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "OpenAI-compatible adapter should attach provided API key")
        try expect(urlRequest.httpBody != nil, "OpenAI-compatible adapter should encode request body")
        try expect(openAIAdapter.capabilities.descriptor.route == .local, "OpenAI-compatible local adapter should preserve local route")
    }

    private static func testChatRuntimeIntegration() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("pixel-pane-agent-kernel-runtime-\(UUID().uuidString)")
        let grantedFile = root.appendingPathComponent("README.md")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try "Pixel Pane runtime fixture.\n".write(to: grantedFile, atomically: true, encoding: .utf8)

        let grants = [
            LocalFileGrant(
                id: UUID(),
                path: root.standardizedFileURL.path,
                isDirectory: true,
                addedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ]

        let runtime = AgentKernelChatRuntimeV2(
            localTools: AgentKernelLocalContextToolsV2(maxDirectoryEntries: 20, maxReadCharacters: 120),
            finiteCommandTool: AgentKernelFiniteCommandToolV2(defaultTimeoutSeconds: 2, maxTimeoutSeconds: 5)
        )

        let finalModel = FixtureAgentKernelAdapterV2(
            responses: [
                .finalAnswer("No deterministic local evidence needed."),
                .finalAnswer("Plain chat works."),
                .finalAnswer("No verifiable local claims.")
            ]
        )
        let final = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "hello",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: finalModel
        )
        try expect(final.primaryChatEvent?.kind == .finalMessage, "runtime should return final answers as typed UI events")
        try expect(final.primaryChatEvent?.summary.text == "Plain chat works.", "runtime should return model final answers")
        try expect(final.ledger.transcriptMessages.map(\.role) == [.user, .assistant], "runtime transcript should contain only user and assistant messages")
        let finalRequest = await finalModel.lastRequest()
        let contextInventory = finalRequest?.messages.first(where: { $0.role == .system && $0.content.contains("app_context_inventory") })
        try expect(contextInventory?.content.contains(root.standardizedFileURL.path) == true, "runtime should include granted local context in model request inventory")
        try expect(contextInventory?.content.contains("available_local_grants") == true, "runtime should label granted local context for all providers")

        let timeoutRuntime = AgentKernelChatRuntimeV2(modelCallTimeoutSeconds: 0.05)
        let timeoutModel = FixtureAgentKernelAdapterV2(
            responses: [
                .finalAnswer("No deterministic local evidence needed."),
                .delayedFinalAnswer("This answer should arrive too late.", nanoseconds: 1_000_000_000)
            ]
        )
        let timedOut = await timeoutRuntime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "hello slowly",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: timeoutModel
        )
        try expect(timedOut.primaryChatEvent?.kind == .failed, "runtime should fail visibly when a model call exceeds the deadline")
        try expect(timedOut.terminalReason?.code == "model_timed_out", "model call deadlines should produce a stable timeout reason")
        try expect(
            !timedOut.ledger.transcriptMessages.contains { $0.role == .assistant && $0.content.contains("too late") },
            "late model output should not be appended after a runtime timeout"
        )

        let readNeeds = try json([
            AgentKernelEvidenceNeedV2(
                kind: .fileRead,
                target: "README.md",
                rationale: "Need file evidence from the granted project."
            )
        ])
        let readClaims = try json([
            AgentKernelFinalClaimDeclarationV2(type: .fileExists, target: grantedFile.path)
        ])
        let readModel = FixtureAgentKernelAdapterV2(
            responses: [
                .toolCall(
                    name: AgentKernelEvidencePlannerV2.declareEvidenceNeedsToolName,
                    arguments: ["needs": readNeeds],
                    reason: "Plan evidence."
                ),
                .finalAnswer("The file says Pixel Pane runtime fixture."),
                .toolCall(
                    name: AgentKernelEvidencePlannerV2.declareFinalClaimsToolName,
                    arguments: ["claims": readClaims],
                    reason: "Declare final claims."
                )
            ]
        )
        let read = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "read README",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: readModel
        )
        try expect(read.primaryChatEvent?.summary.text.contains("Pixel Pane runtime fixture") == true, "runtime should continue after read-only tools")
        try expect(read.statePatch.lastFileSources.first?.path == grantedFile.path, "runtime should expose file source state")
        try expect(read.ledger.controlEvents.contains { event in
            if case .toolResult = event.payload { return true }
            return false
        }, "runtime should keep tool results in control events")
        try expect(
            !read.ledger.transcriptMessages.contains { $0.content.contains("tool_result") },
            "tool observations should not pollute transcript"
        )
        try expect(
            !read.ledger.transcriptMessages.contains { $0.content.contains(AgentKernelEvidencePlannerV2.declareEvidenceNeedsToolName) || $0.content.contains(AgentKernelEvidencePlannerV2.declareFinalClaimsToolName) },
            "evidence planning tool declarations should not render as assistant transcript text"
        )

        let malformedPlanningModel = FixtureAgentKernelAdapterV2(
            responses: [
                .malformedOutput("not valid planning JSON"),
                .toolCall(
                    name: "list_grants",
                    arguments: [:],
                    reason: "Inspect granted local locations."
                ),
                .finalAnswer("Yes, I can see a granted local folder."),
                .finalAnswer("No verifiable local claims.")
            ]
        )
        let malformedPlanning = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "do you see my personal website?",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: malformedPlanningModel
        )
        try expect(malformedPlanning.primaryChatEvent?.kind == .finalMessage, "malformed evidence planning should degrade into normal tool handling")
        try expect(malformedPlanning.primaryChatEvent?.summary.text.contains("granted local folder") == true, "malformed evidence planning should not become the user-visible answer")
        try expect(
            malformedPlanning.ledger.controlEvents.contains { event in
                if case .toolResult(let result) = event.payload {
                    return result.toolName == AgentKernelEvidencePlannerV2.declareEvidenceNeedsToolName
                        && result.status == .failed
                }
                return false
            },
            "malformed evidence planning should be recorded as a control-plane failure"
        )
        try expect(
            !malformedPlanning.ledger.transcriptMessages.contains { $0.content.contains("malformed evidence plan") || $0.content.contains("not valid planning JSON") },
            "malformed evidence planning details should stay out of transcript"
        )

        let commandModel = FixtureAgentKernelAdapterV2(
            responses: [
                .finalAnswer("No deterministic local evidence needed."),
                .toolCall(
                    name: "run_finite_command",
                    arguments: [
                        "command": "echo runtime-ok",
                        "workingDirectory": root.path,
                        "timeoutSeconds": "2"
                    ],
                    reason: "Check the shell."
                ),
                .finalAnswer("The command printed runtime-ok."),
                .toolCall(
                    name: AgentKernelEvidencePlannerV2.declareFinalClaimsToolName,
                    arguments: [
                        "claims": try json([
                            AgentKernelFinalClaimDeclarationV2(type: .commandSucceeded, target: "echo runtime-ok")
                        ])
                    ],
                    reason: "Declare final claims."
                )
            ]
        )
        let command = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "run echo",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: commandModel
        )
        try expect(command.primaryChatEvent?.summary.text == "The command printed runtime-ok.", "runtime should execute low-risk finite commands")
        try expect(command.statePatch.recentToolResults.first?.terminalStdout?.contains("runtime-ok") == true, "runtime should expose terminal result state")

        let writeModel = FixtureAgentKernelAdapterV2(
            responses: [
                .finalAnswer("No deterministic local evidence needed."),
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": "note.txt",
                        "content": "approved later"
                    ],
                    reason: "Create the requested file."
                )
            ]
        )
        let write = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "create note",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: writeModel
        )
        try expect(write.pendingApproval?.toolCall.name == "stage_write_proposal", "write proposals should produce pending approval")
        try expect(write.pendingWriteProposal?.targetPath.hasSuffix("note.txt") == true, "write approval should include staged proposal")
        try expect(write.primaryChatEvent == nil, "pending approvals should not synthesize a fake assistant answer")
        try expect(write.uiEvents.contains { $0.kind == .approvalRequested }, "pending approvals should be exposed as typed UI events")
        try expect(
            !write.ledger.transcriptMessages.contains { $0.content.contains("Create file") },
            "approval display text should stay out of transcript"
        )

        let approvedWriteClaims = try json([
            AgentKernelFinalClaimDeclarationV2(type: .fileChanged, target: root.appendingPathComponent("note.txt").path)
        ])
        let approvedWriteModel = FixtureAgentKernelAdapterV2(
            responses: [
                .finalAnswer("Created note.txt."),
                .toolCall(
                    name: AgentKernelEvidencePlannerV2.declareFinalClaimsToolName,
                    arguments: ["claims": approvedWriteClaims],
                    reason: "Declare completed write."
                )
            ]
        )
        guard let writeApproval = write.pendingApproval else {
            throw HarnessError(description: "write proposal should keep pending approval for resolution")
        }
        let approvedWrite = await runtime.resolveApproval(
            context: AgentKernelChatContextV2(
                ledger: write.ledger,
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path],
                recentWriteTargetPaths: [root.appendingPathComponent("note.txt").path]
            ),
            approval: writeApproval,
            decision: .approved,
            model: approvedWriteModel
        )
        let approvedNote = try String(contentsOf: root.appendingPathComponent("note.txt"), encoding: .utf8)
        try expect(approvedNote == "approved later", "approved write resolution should execute the staged file write")
        try expect(approvedWrite.primaryChatEvent?.summary.text == "Created note.txt.", "approved writes should resume the model loop after execution")
        try expect(
            approvedWrite.ledger.evidenceRecords.contains { record in
                record.kind == AgentKernelEvidenceKindV2.fileWrite.rawValue
                    && record.metadata["path"] == .string(root.appendingPathComponent("note.txt").path)
            },
            "approved writes should record completed file-write evidence in the kernel ledger"
        )

        let badPythonScript = """
        #!/usr/bin/env python3
        def main():
            print("hello")
        if name == "main":
            main()
        """
        let goodPythonScript = """
        #!/usr/bin/env python3
        def main():
            print("hello")
        if __name__ == "__main__":
            main()
        """
        let preflightWriteModel = FixtureAgentKernelAdapterV2(
            responses: [
                .finalAnswer("No deterministic local evidence needed."),
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": "script.py",
                        "content": badPythonScript
                    ],
                    reason: "Stage the requested script."
                ),
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": "script.py",
                        "content": goodPythonScript
                    ],
                    reason: "Retry with a valid Python script."
                )
            ]
        )
        let preflightWrite = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "create a python script",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: preflightWriteModel
        )
        try expect(preflightWrite.pendingApproval?.toolCall.name == "stage_write_proposal", "script preflight failures should let the model retry into a valid pending write")
        try expect(preflightWrite.pendingWriteProposal?.targetPath.hasSuffix("script.py") == true, "script preflight retry should stage the corrected script")
        try expect(
            preflightWrite.ledger.controlEvents.contains { event in
                if case .toolResult(let result) = event.payload {
                    return result.toolName == "stage_write_proposal"
                        && result.status == .failed
                        && result.metadata["code"] == .string("write_preflight_failed")
                }
                return false
            },
            "script preflight failures should be model-visible control observations, not approvals"
        )

        let localServerNeeds = try json([
            AgentKernelEvidenceNeedV2(
                kind: .localServerProbe,
                target: "1",
                rationale: "Check the local site status from the runtime."
            )
        ])
        let localServerClaims = try json([
            AgentKernelFinalClaimDeclarationV2(type: .portListening, target: "1", qualifiers: ["port": .int(1)])
        ])
        let vagueLocalStateModel = FixtureAgentKernelAdapterV2(
            responses: [
                .toolCall(
                    name: AgentKernelEvidencePlannerV2.declareEvidenceNeedsToolName,
                    arguments: ["needs": localServerNeeds],
                    reason: "Plan local site evidence."
                ),
                .finalAnswer("The local site is alive."),
                .toolCall(
                    name: AgentKernelEvidencePlannerV2.declareFinalClaimsToolName,
                    arguments: ["claims": localServerClaims],
                    reason: "Declare local site claim."
                )
            ]
        )
        let vagueLocalState = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "is the local site alive?",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: vagueLocalStateModel
        )
        try expect(vagueLocalState.terminalReason?.code == "port_listening_needs_probe", "unsupported local-state final claims should be blocked by evidence gating")
        try expect(vagueLocalState.primaryChatEvent?.kind == .blocked, "blocked final answers should be typed control events")
        try expect(vagueLocalState.primaryChatEvent?.summary.text.contains("port-listening claim requires") == true, "blocked final answer should explain missing evidence")
        try expect(
            vagueLocalState.ledger.evidenceRecords.contains { $0.kind == AgentKernelEvidenceKindV2.localServerProbe.rawValue },
            "vague local-state planning should auto-run a safe localhost probe"
        )
        try expect(
            !vagueLocalState.ledger.transcriptMessages.contains { $0.content.contains(AgentKernelEvidencePlannerV2.declareEvidenceNeedsToolName) || $0.content.contains(AgentKernelEvidencePlannerV2.declareFinalClaimsToolName) },
            "blocked evidence-planning control events should stay out of transcript"
        )

        let explicitPortProbeModel = FixtureAgentKernelAdapterV2(
            responses: [
                .toolCall(
                    name: AgentKernelEvidencePlannerV2.declareEvidenceNeedsToolName,
                    arguments: ["needs": localServerNeeds],
                    reason: "Plan explicit port evidence."
                ),
                .finalAnswer("I checked localhost port 1."),
                .finalAnswer("No verifiable local claims.")
            ]
        )
        let explicitPortProbe = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "port 1?",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: explicitPortProbeModel
        )
        try expect(explicitPortProbe.primaryChatEvent?.kind == .finalMessage, "explicit port probe should complete through a typed final-message event")
        try expect(
            explicitPortProbe.ledger.evidenceRecords.contains { $0.kind == AgentKernelEvidenceKindV2.localServerProbe.rawValue },
            "explicit port probe should record typed local-server evidence"
        )
        try expect(
            !explicitPortProbe.ledger.transcriptMessages.contains { $0.content.contains("declare_") || $0.content.contains(#""type":"tool_call""#) },
            "explicit port probe transcript should not contain planning or protocol control text"
        )

        let deferredLocalServerModel = FixtureAgentKernelAdapterV2(
            responses: [
                .finalAnswer("No deterministic local evidence needed."),
                .finalAnswer("I cannot confirm if your website is currently running on a localhost port. To check this, I would need to probe the local server or check running processes."),
                .toolCall(
                    name: "run_finite_command",
                    arguments: [
                        "command": "lsof -nP -iTCP -sTCP:LISTEN",
                        "workingDirectory": root.path,
                        "timeoutSeconds": "5"
                    ],
                    reason: "Use a safe local command to inspect listening ports."
                ),
                .finalAnswer("I checked local listening ports."),
                .finalAnswer("No verifiable local claims.")
            ]
        )
        let deferredLocalServer = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "is it currently running on a localhost port on my computer?",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: deferredLocalServerModel
        )
        try expect(deferredLocalServer.primaryChatEvent?.summary.text == "I checked local listening ports.", "answerability guard should force deferred local-state answers back into the tool loop")
        try expect(
            deferredLocalServer.ledger.controlEvents.contains { event in
                if case .toolResult(let result) = event.payload {
                    return result.toolName == "answerability_guard"
                        && result.metadata["code"] == .string("answerability_deferred_with_available_tools")
                }
                return false
            },
            "answerability guard should record a control-plane retry observation"
        )
        try expect(
            deferredLocalServer.ledger.controlEvents.contains { event in
                if case .toolProposal(let call) = event.payload {
                    return call.name == "run_finite_command"
                }
                return false
            },
            "deferred localhost status should lead to a typed runtime capability"
        )
        try expect(
            !deferredLocalServer.ledger.transcriptMessages.contains { $0.content.contains("cannot confirm") },
            "deferred local-state text should not become assistant transcript content"
        )

        let leakedToolJSON = #"{"type":"tool_call","name":"probe_local_server","arguments":{"url":"http://localhost:8000"},"reason":"The user is asking specifically about port 8000, so I need to probe that port to determine if the website is running there."}"#
        let protocolLeakModel = FixtureAgentKernelAdapterV2(
            responses: [
                .finalAnswer("No deterministic local evidence needed."),
                .finalAnswer(leakedToolJSON),
                .finalAnswer("I checked localhost port 8000."),
                .finalAnswer("No verifiable local claims.")
            ]
        )
        let protocolLeak = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "port 8000 ?",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: protocolLeakModel
        )
        try expect(protocolLeak.primaryChatEvent?.summary.text == "I checked localhost port 8000.", "protocol-shaped final text should be normalized before it reaches chat")
        try expect(
            !protocolLeak.ledger.transcriptMessages.contains { $0.content.contains(#""type":"tool_call""#) },
            "tool-call protocol JSON should never be appended as assistant transcript text"
        )
        try expect(
            protocolLeak.ledger.controlEvents.contains { event in
                if case .toolProposal(let call) = event.payload {
                    return call.name == "probe_local_server" && call.arguments["url"] == "http://localhost:8000"
                }
                return false
            },
            "protocol-shaped text should recover as a typed localhost probe tool call"
        )

        let repairedWriteJSON = #"{"type":"tool_call","name":"stage_write_proposal","arguments":{"path":"short_story.txt","content":"The Last Light"},"reason":"The user wants a text file."}"#
        let repairedWriteModel = FixtureAgentKernelAdapterV2(
            responses: [
                .finalAnswer("No deterministic local evidence needed."),
                .finalAnswer(repairedWriteJSON)
            ]
        )
        let repairedWrite = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "create the txt file",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: repairedWriteModel
        )
        try expect(repairedWrite.pendingApproval?.toolCall.name == "stage_write_proposal", "observed staged-write protocol shape should repair into a pending approval")
        try expect(repairedWrite.pendingWriteProposal?.targetPath.hasSuffix("short_story.txt") == true, "repaired staged-write alias should resolve the target path")
        try expect(repairedWrite.primaryChatEvent == nil, "repaired staged-write approval should not synthesize chat text")
        try expect(
            !repairedWrite.uiEvents.contains { $0.summary.text.contains(#""type":"tool_call""#) },
            "repaired protocol JSON should not become visible UI event text"
        )
        try expect(
            !repairedWrite.ledger.transcriptMessages.contains { $0.content.contains(#""type":"tool_call""#) },
            "repaired protocol JSON should never be appended as assistant transcript text"
        )

        let incompleteWriteModel = FixtureAgentKernelAdapterV2(
            responses: [
                .finalAnswer("No deterministic local evidence needed."),
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: ["targetPath": "short_story.txt"],
                    reason: "Create the requested story file."
                ),
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": "short_story.txt",
                        "content": "A short man found a tall door and built a smaller one beside it."
                    ],
                    reason: "Retry with all required write arguments."
                )
            ]
        )
        let incompleteWrite = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "create a short story txt file within random-tests containing a story about a short man",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: incompleteWriteModel
        )
        try expect(incompleteWrite.pendingApproval?.toolCall.name == "stage_write_proposal", "incomplete staged writes should recover into a pending approval after retry")
        try expect(incompleteWrite.pendingWriteProposal?.targetPath.hasSuffix("short_story.txt") == true, "recovered incomplete staged write should stage the requested file")
        try expect(incompleteWrite.primaryChatEvent == nil, "recoverable write validation failures should not become visible assistant answers")
        try expect(
            incompleteWrite.ledger.controlEvents.contains { event in
                if case .toolResult(let result) = event.payload {
                    return result.toolName == "stage_write_proposal"
                        && result.status == .failed
                        && result.summary.text.contains("missing required argument")
                }
                return false
            },
            "incomplete staged writes should be recorded as recoverable control-plane validation failures"
        )

        let deferredScriptModel = FixtureAgentKernelAdapterV2(
            responses: [
                .finalAnswer("No deterministic local evidence needed."),
                .finalAnswer("I have not yet created the script that prints 'hello world'. Would you like me to proceed with creating that script now?"),
                .toolCall(
                    name: "stage_write_proposal",
                    arguments: [
                        "operation": "create",
                        "targetPath": "hello_world.py",
                        "content": #"print("hello world")"#
                    ],
                    reason: "Stage the requested script."
                )
            ]
        )
        let deferredScript = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: #"write me a script in that same folder which prints "hello world""#,
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path],
                recentWriteTargetPaths: [root.appendingPathComponent("short_story.txt").path]
            ),
            model: deferredScriptModel
        )
        try expect(deferredScript.pendingApproval?.toolCall.name == "stage_write_proposal", "answerability guard should route deferred file actions back to staged write")
        try expect(deferredScript.pendingWriteProposal?.targetPath.hasSuffix("hello_world.py") == true, "deferred file action should produce a concrete write proposal")
        try expect(
            deferredScript.ledger.controlEvents.contains { event in
                if case .toolResult(let result) = event.payload {
                    return result.toolName == "answerability_guard"
                }
                return false
            },
            "pre-confirmation file deferral should be recorded as a control-plane retry observation"
        )
        try expect(
            !deferredScript.ledger.transcriptMessages.contains { $0.content.contains("Would you like me to proceed") },
            "pre-confirmation deferral should stay out of assistant transcript content"
        )

        let malformedWriteModel = FixtureAgentKernelAdapterV2(
            responses: [
                .finalAnswer("No deterministic local evidence needed."),
                .finalAnswer(#"{"type":"tool_call","name":"stage_write_proposal","arguments":{"path":"short_story.txt"},"reason":"Missing content."}"#)
            ]
        )
        let malformedWrite = await runtime.runTurn(
            context: AgentKernelChatContextV2(
                ledger: AgentKernelSessionLedgerV2(),
                userMessage: "create the txt file",
                grants: grants,
                visualContext: nil,
                allowedWorkingDirectories: [root.path]
            ),
            model: malformedWriteModel
        )
        try expect(malformedWrite.primaryChatEvent?.kind == .failed, "unrepaired malformed protocol output should become a typed failure event")
        try expect(
            malformedWrite.primaryChatEvent?.summary.text.contains(#""type":"tool_call""#) == false,
            "unrepaired malformed protocol JSON should not become visible chat text"
        )
    }

    private static func testFixtureModels() async throws {
        let tools = [
            AgentKernelToolSchemaV2(
                name: "read_file",
                summary: "Read a granted file.",
                requiredArguments: ["path"]
            )
        ]
        let request = AgentKernelModelRequestV2(
            messages: [
                AgentKernelMessageV2(role: .user, content: "Read README.md")
            ],
            tools: tools,
            maxOutputTokens: 512
        )

        let answerModel = FixtureAgentKernelModelV2(
            id: "fixture.final",
            responses: [.finalAnswer("Done.")]
        )
        let answerEvents = await answerModel.events(for: request)
        let answerRequest = await answerModel.lastRequest()
        try expect(
            answerEvents == [.finalAnswer("Done.")],
            "fixture final answer should be deterministic"
        )
        try expect(
            answerRequest?.tools == tools,
            "fixture model should record received tool schemas"
        )

        let toolModel = FixtureAgentKernelModelV2(
            id: "fixture.tool",
            responses: [
                .toolCall(
                    name: "read_file",
                    arguments: ["path": "README.md"],
                    reason: "Need project context."
                )
            ]
        )
        let toolEvents = await toolModel.events(for: request)
        try expect(toolEvents.count == 1, "tool fixture should emit one event")
        guard case .toolCall(let call) = toolEvents[0] else {
            throw HarnessError(description: "tool fixture should emit a tool call")
        }
        try expect(call.name == "read_file", "tool call name should round-trip")
        try expect(call.arguments["path"] == "README.md", "tool arguments should round-trip")

        let malformedModel = FixtureAgentKernelModelV2(
            id: "fixture.malformed",
            responses: [.malformedOutput("{not json")]
        )
        let malformedEvents = await malformedModel.events(for: request)
        try expect(
            malformedEvents == [.malformedOutput("{not json")],
            "malformed output should be representable"
        )

        let emptyModel = FixtureAgentKernelModelV2(
            id: "fixture.empty",
            responses: [.emptyOutput]
        )
        let emptyEvents = await emptyModel.events(for: request)
        try expect(
            emptyEvents == [.emptyOutput],
            "empty output should be representable"
        )

        let repeatedModel = FixtureAgentKernelModelV2(
            id: "fixture.repeated",
            responses: [
                .toolCall(name: "read_file", arguments: ["path": "README.md"], reason: nil),
                .toolCall(name: "read_file", arguments: ["path": "README.md"], reason: nil)
            ]
        )
        let firstRepeated = await repeatedModel.events(for: request)
        let secondRepeated = await repeatedModel.events(for: request)
        guard
            case .toolCall(let firstRepeatedCall) = firstRepeated.first,
            case .toolCall(let secondRepeatedCall) = secondRepeated.first
        else {
            throw HarnessError(description: "repeated fixture should emit tool calls")
        }
        try expect(
            firstRepeatedCall.name == secondRepeatedCall.name
                && firstRepeatedCall.arguments == secondRepeatedCall.arguments
                && firstRepeatedCall.reason == secondRepeatedCall.reason,
            "repeated tool calls should be scriptable"
        )

        let timeoutModel = FixtureAgentKernelModelV2(
            id: "fixture.timeout",
            responses: [.timeout]
        )
        let timeoutEvents = await timeoutModel.events(for: request)
        try expect(
            timeoutEvents == [.timedOut],
            "timeout should be representable as a model event"
        )
    }
}

actor FixtureAIBackendV2: AIBackend {
    let id: String
    let displayName: String
    private let backendCapabilities: AIBackendCapabilities
    private var scriptedResponses: [[AIBackendStreamEvent]]
    private var receivedRequests: [AIBackendRequest] = []

    init(
        id: String,
        displayName: String,
        capabilities: AIBackendCapabilities,
        responses: [[AIBackendStreamEvent]]
    ) {
        self.id = id
        self.displayName = displayName
        self.backendCapabilities = capabilities
        self.scriptedResponses = responses
    }

    func capabilities() async -> AIBackendCapabilities {
        backendCapabilities
    }

    nonisolated func streamResponse(
        for request: AIBackendRequest
    ) -> AsyncThrowingStream<AIBackendStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let events = await self.nextEvents(for: request)
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func requests() -> [AIBackendRequest] {
        receivedRequests
    }

    private func nextEvents(for request: AIBackendRequest) -> [AIBackendStreamEvent] {
        receivedRequests.append(request)
        guard !scriptedResponses.isEmpty else {
            return [.completed]
        }
        return scriptedResponses.removeFirst()
    }
}

@main
enum AgentKernelFixtureHarnessMain {
    static func main() async {
        do {
            try await AgentKernelFixtureHarness.run()
            print("AgentKernel V2 fixture harness passed")
        } catch {
            fputs("AgentKernel V2 fixture harness failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}
