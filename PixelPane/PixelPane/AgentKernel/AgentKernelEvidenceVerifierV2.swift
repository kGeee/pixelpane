import Foundation

enum AgentKernelEvidenceKindV2: String, Codable, Equatable, Sendable {
    case fileRead = "file.read"
    case fileWriteProposal = "file.write_proposal"
    case fileWrite = "file.write"
    case finiteCommand = "command.finite"
    case managedProcess = "process.managed"
    case localServerProbe = "server.local_probe"
    case visualContext = "visual.context"
    case approvalRequested = "approval.requested"
    case approvalResolved = "approval.resolved"
    case modelStatement = "model.statement"
    case taskLifecycle = "task.lifecycle"
}

enum AgentKernelEvidenceClaimTagV2: String, Codable, Equatable, Hashable, Sendable {
    case buildOrTest = "build_or_test"
}

enum AgentKernelClaimTypeV2: String, Codable, Equatable, Sendable {
    case fileExists = "file_exists"
    case fileChanged = "file_changed"
    case commandRan = "command_ran"
    case commandSucceeded = "command_succeeded"
    case commandFailed = "command_failed"
    case processAlive = "process_alive"
    case portListening = "port_listening"
    case urlResponds = "url_responds"
    case buildOrTestPassed = "build_or_test_passed"
    case taskCanceled = "task_canceled"
    case modelStatement = "model_statement"
    case unsupported
}

struct AgentKernelVerifiableClaimV2: Codable, Equatable, Sendable {
    let type: AgentKernelClaimTypeV2
    let target: String?
    let qualifiers: [String: AgentKernelMetadataValueV2]

    nonisolated init(
        type: AgentKernelClaimTypeV2,
        target: String? = nil,
        qualifiers: [String: AgentKernelMetadataValueV2] = [:]
    ) {
        self.type = type
        self.target = target
        self.qualifiers = qualifiers
    }

    nonisolated static func fileExists(path: String) -> Self {
        Self(type: .fileExists, target: path)
    }

    nonisolated static func fileChanged(path: String) -> Self {
        Self(type: .fileChanged, target: path)
    }

    nonisolated static func commandRan(_ command: String? = nil) -> Self {
        Self(type: .commandRan, target: command)
    }

    nonisolated static func commandSucceeded(_ command: String? = nil) -> Self {
        Self(type: .commandSucceeded, target: command)
    }

    nonisolated static func commandFailed(_ command: String? = nil, exitCode: Int? = nil) -> Self {
        var qualifiers: [String: AgentKernelMetadataValueV2] = [:]
        if let exitCode {
            qualifiers["exitCode"] = .int(exitCode)
        }
        return Self(type: .commandFailed, target: command, qualifiers: qualifiers)
    }

    nonisolated static func processAlive(processID: String? = nil) -> Self {
        Self(type: .processAlive, target: processID)
    }

    nonisolated static func portListening(_ port: Int) -> Self {
        Self(type: .portListening, target: String(port), qualifiers: ["port": .int(port)])
    }

    nonisolated static func urlResponds(_ url: String) -> Self {
        Self(type: .urlResponds, target: url)
    }

    nonisolated static func buildOrTestPassed() -> Self {
        Self(type: .buildOrTestPassed)
    }

    nonisolated static func taskCanceled() -> Self {
        Self(type: .taskCanceled)
    }

    nonisolated static func modelStatement(_ statement: String) -> Self {
        Self(type: .modelStatement, target: statement)
    }

    nonisolated static func unsupported(_ statement: String) -> Self {
        Self(type: .unsupported, target: statement)
    }
}

enum AgentKernelClaimVerificationStatusV2: String, Codable, Equatable, Sendable {
    case verified
    case needsTool
    case blocked
}

struct AgentKernelClaimVerificationV2: Codable, Equatable, Sendable {
    let claim: AgentKernelVerifiableClaimV2
    let status: AgentKernelClaimVerificationStatusV2
    let evidenceIDs: [UUID]
    let reason: AgentKernelTerminalReasonV2?

    nonisolated init(
        claim: AgentKernelVerifiableClaimV2,
        status: AgentKernelClaimVerificationStatusV2,
        evidenceIDs: [UUID] = [],
        reason: AgentKernelTerminalReasonV2? = nil
    ) {
        self.claim = claim
        self.status = status
        self.evidenceIDs = evidenceIDs
        self.reason = reason
    }
}

struct AgentKernelFinalAnswerVerificationV2: Codable, Equatable, Sendable {
    let decisions: [AgentKernelClaimVerificationV2]

    nonisolated var canAnswer: Bool {
        decisions.allSatisfy { $0.status == .verified }
    }

    nonisolated var blockingReasons: [AgentKernelTerminalReasonV2] {
        decisions.compactMap(\.reason)
    }
}

struct AgentKernelEvidenceFactoryV2: Sendable {
    nonisolated static func fileRead(
        _ output: AgentKernelFileReadOutputV2,
        relatedToolCallID: UUID? = nil
    ) -> AgentKernelEvidenceRecordV2 {
        AgentKernelEvidenceRecordV2(
            sourceID: output.sources.first?.id ?? "file-read:\(output.path)",
            kind: AgentKernelEvidenceKindV2.fileRead.rawValue,
            summary: output.summary,
            body: output.content,
            metadata: [
                "path": .string(output.path),
                "byteCount": .int(output.byteCount),
                "exists": .bool(true)
            ],
            privacyClass: "local-file",
            trustClass: "tool-observation",
            isTruncated: output.content.isTruncated || output.sources.contains(where: \.isTruncated),
            relatedToolCallID: relatedToolCallID
        )
    }

    nonisolated static func writeProposal(
        _ output: AgentKernelWriteProposalOutputV2,
        relatedToolCallID: UUID? = nil
    ) -> AgentKernelEvidenceRecordV2 {
        AgentKernelEvidenceRecordV2(
            sourceID: output.sources.first?.id ?? "file-write-proposal:\(output.proposal.targetPath)",
            kind: AgentKernelEvidenceKindV2.fileWriteProposal.rawValue,
            summary: output.summary,
            metadata: [
                "path": .string(output.proposal.targetPath),
                "requiresApproval": .bool(output.requiresApproval),
                "fileWritten": .bool(false),
                "action": .string(output.proposal.actionLabel)
            ],
            privacyClass: "local-file",
            trustClass: "tool-observation",
            relatedToolCallID: relatedToolCallID
        )
    }

    nonisolated static func fileWrite(
        path: String,
        byteCount: Int? = nil,
        contentHash: String? = nil,
        relatedToolCallID: UUID? = nil
    ) -> AgentKernelEvidenceRecordV2 {
        var metadata: [String: AgentKernelMetadataValueV2] = [
            "path": .string(path),
            "exists": .bool(true),
            "fileWritten": .bool(true)
        ]
        if let byteCount {
            metadata["byteCount"] = .int(byteCount)
        }
        if let contentHash {
            metadata["contentHash"] = .string(contentHash)
        }
        return AgentKernelEvidenceRecordV2(
            sourceID: "file-write:\(path)",
            kind: AgentKernelEvidenceKindV2.fileWrite.rawValue,
            summary: AgentKernelBoundedTextV2("File write completed for \(path)."),
            metadata: metadata,
            privacyClass: "local-file",
            trustClass: "tool-observation",
            relatedToolCallID: relatedToolCallID
        )
    }

    nonisolated static func finiteCommand(
        _ output: AgentKernelFiniteCommandOutputV2,
        claimTags: Set<AgentKernelEvidenceClaimTagV2> = [],
        relatedToolCallID: UUID? = nil
    ) -> AgentKernelEvidenceRecordV2 {
        AgentKernelEvidenceRecordV2(
            sourceID: output.sources.first?.id ?? "finite-command:\(UUID().uuidString)",
            kind: AgentKernelEvidenceKindV2.finiteCommand.rawValue,
            summary: output.summary,
            body: AgentKernelBoundedTextV2([output.stdout.text, output.stderr.text].joined(separator: "\n")),
            metadata: [
                "command": .string(output.command),
                "workingDirectory": .string(output.workingDirectory),
                "observationKind": .string(output.observationKind.rawValue),
                "exitCode": .int(Int(output.exitCode ?? -1)),
                "didTimeOut": .bool(output.didTimeOut),
                "claimTags": .string(claimTags.map(\.rawValue).sorted().joined(separator: ","))
            ],
            privacyClass: "terminal-output",
            trustClass: "tool-observation",
            isTruncated: output.wasOutputTruncated,
            relatedToolCallID: relatedToolCallID
        )
    }

    nonisolated static func managedProcess(
        _ record: AgentKernelManagedProcessRecordV2,
        relatedToolCallID: UUID? = nil
    ) -> AgentKernelEvidenceRecordV2 {
        var metadata: [String: AgentKernelMetadataValueV2] = [
            "processID": .string(record.processID),
            "command": .string(record.command),
            "workingDirectory": .string(record.workingDirectory),
            "status": .string(record.status.rawValue),
            "pid": .int(Int(record.pid ?? -1)),
            "exitCode": .int(Int(record.exitCode ?? -1))
        ]
        if let url = record.detectedServer?.url {
            metadata["url"] = .string(url)
        }
        if let port = record.detectedServer?.port {
            metadata["port"] = .int(port)
        }
        if let isListening = record.detectedServer?.isListening {
            metadata["isListening"] = .bool(isListening)
        }
        if let httpStatusCode = record.detectedServer?.httpStatusCode {
            metadata["httpStatusCode"] = .int(httpStatusCode)
        }

        return AgentKernelEvidenceRecordV2(
            sourceID: record.sources.first?.id ?? "managed-process:\(record.processID)",
            kind: AgentKernelEvidenceKindV2.managedProcess.rawValue,
            summary: record.sources.first?.summary ?? AgentKernelBoundedTextV2("Managed process \(record.processID)."),
            body: AgentKernelBoundedTextV2([record.stdoutTail.text, record.stderrTail.text].joined(separator: "\n")),
            metadata: metadata,
            privacyClass: "terminal-output",
            trustClass: "tool-observation",
            isTruncated: record.stdoutTail.isTruncated || record.stderrTail.isTruncated || record.sources.contains(where: \.isTruncated),
            relatedToolCallID: relatedToolCallID
        )
    }

    nonisolated static func localServerProbe(
        _ probe: AgentKernelLocalServerProbeV2,
        relatedToolCallID: UUID? = nil
    ) -> AgentKernelEvidenceRecordV2 {
        var metadata: [String: AgentKernelMetadataValueV2] = [:]
        if let url = probe.url {
            metadata["url"] = .string(url)
        }
        if let port = probe.port {
            metadata["port"] = .int(port)
        }
        if let isListening = probe.isListening {
            metadata["isListening"] = .bool(isListening)
        }
        if let httpStatusCode = probe.httpStatusCode {
            metadata["httpStatusCode"] = .int(httpStatusCode)
        }
        let sourceID = probe.url.map { "local-server:\($0)" }
            ?? probe.port.map { "local-server-port:\($0)" }
            ?? "local-server:\(UUID().uuidString)"
        return AgentKernelEvidenceRecordV2(
            sourceID: sourceID,
            kind: AgentKernelEvidenceKindV2.localServerProbe.rawValue,
            summary: AgentKernelBoundedTextV2("Local server probe recorded."),
            metadata: metadata,
            privacyClass: "local-network",
            trustClass: "tool-observation",
            relatedToolCallID: relatedToolCallID
        )
    }

    nonisolated static func visualContext(
        _ output: AgentKernelVisualContextOutputV2,
        relatedToolCallID: UUID? = nil
    ) -> AgentKernelEvidenceRecordV2 {
        AgentKernelEvidenceRecordV2(
            sourceID: output.sources.first?.id ?? "visual-context:\(output.source):\(output.label)",
            kind: AgentKernelEvidenceKindV2.visualContext.rawValue,
            summary: output.summary,
            body: output.ocrExcerpt,
            metadata: [
                "source": .string(output.source),
                "label": .string(output.label),
                "hasTransientImageInput": .bool(output.hasTransientImageInput),
                "hasOCRText": .bool(output.hasOCRText),
                "imagePixelsPersisted": .bool(output.imagePixelsPersisted)
            ],
            privacyClass: "visual-context",
            trustClass: "tool-observation",
            isTruncated: output.ocrExcerpt?.isTruncated ?? false,
            relatedToolCallID: relatedToolCallID
        )
    }

    nonisolated static func approvalRequested(
        _ request: AgentKernelApprovalRequestV2
    ) -> AgentKernelEvidenceRecordV2 {
        AgentKernelEvidenceRecordV2(
            sourceID: "approval-request:\(request.id.uuidString)",
            kind: AgentKernelEvidenceKindV2.approvalRequested.rawValue,
            summary: request.displaySummary,
            body: request.operationPreview,
            metadata: [
                "approvalID": .string(request.id.uuidString),
                "toolCallID": .string(request.toolCallID.uuidString),
                "toolName": .string(request.toolName),
                "riskClass": .string(request.riskClass)
            ],
            privacyClass: "control-plane",
            trustClass: "app-control",
            relatedToolCallID: request.toolCallID
        )
    }

    nonisolated static func approvalResolved(
        _ resolution: AgentKernelApprovalResolutionV2
    ) -> AgentKernelEvidenceRecordV2 {
        AgentKernelEvidenceRecordV2(
            sourceID: "approval-resolution:\(resolution.approvalID.uuidString)",
            kind: AgentKernelEvidenceKindV2.approvalResolved.rawValue,
            summary: AgentKernelBoundedTextV2("Approval \(resolution.decision.rawValue)."),
            body: resolution.reason,
            metadata: [
                "approvalID": .string(resolution.approvalID.uuidString),
                "decision": .string(resolution.decision.rawValue)
            ],
            privacyClass: "control-plane",
            trustClass: "app-control"
        )
    }

    nonisolated static func modelStatement(
        _ statement: String,
        relatedToolCallID: UUID? = nil
    ) -> AgentKernelEvidenceRecordV2 {
        AgentKernelEvidenceRecordV2(
            sourceID: "model-statement:\(UUID().uuidString)",
            kind: AgentKernelEvidenceKindV2.modelStatement.rawValue,
            summary: AgentKernelBoundedTextV2(statement),
            metadata: ["deterministic": .bool(false)],
            privacyClass: "model-output",
            trustClass: "model",
            relatedToolCallID: relatedToolCallID
        )
    }

    nonisolated static func taskLifecycle(
        code: String,
        summary: String,
        state: AgentKernelTaskStateV2
    ) -> AgentKernelEvidenceRecordV2 {
        AgentKernelEvidenceRecordV2(
            sourceID: "task:\(code)",
            kind: AgentKernelEvidenceKindV2.taskLifecycle.rawValue,
            summary: AgentKernelBoundedTextV2(summary),
            metadata: [
                "code": .string(code),
                "state": .string(state.rawValue)
            ],
            privacyClass: "control-plane",
            trustClass: "app-control"
        )
    }
}

struct AgentKernelEvidenceVerifierV2: Sendable {
    nonisolated init() {}

    nonisolated func verifyFinalClaims(
        _ claims: [AgentKernelVerifiableClaimV2],
        ledger: AgentKernelSessionLedgerV2
    ) -> AgentKernelFinalAnswerVerificationV2 {
        AgentKernelFinalAnswerVerificationV2(
            decisions: claims.map { verify($0, ledger: ledger) }
        )
    }

    nonisolated func verify(
        _ claim: AgentKernelVerifiableClaimV2,
        ledger: AgentKernelSessionLedgerV2
    ) -> AgentKernelClaimVerificationV2 {
        let evidence = ledger.evidenceRecords
        switch claim.type {
        case .fileExists:
            return verifyMatchingEvidence(
                claim,
                evidence: evidence,
                kinds: [.fileRead, .fileWrite],
                predicate: { record in
                    matchesTarget(record.stringMetadata("path"), claim.target)
                },
                missingCode: "file_exists_needs_evidence",
                missingSummary: "A file-exists claim requires file read or file write evidence."
            )
        case .fileChanged:
            return verifyMatchingEvidence(
                claim,
                evidence: evidence,
                kinds: [.fileWrite],
                predicate: { record in
                    matchesTarget(record.stringMetadata("path"), claim.target)
                        && record.boolMetadata("fileWritten") == true
                },
                missingCode: "file_changed_needs_write_evidence",
                missingSummary: "A file-changed claim requires completed write evidence, not only a staged proposal."
            )
        case .commandRan:
            return verifyMatchingEvidence(
                claim,
                evidence: evidence,
                kinds: [.finiteCommand],
                predicate: { record in
                    matchesTarget(record.stringMetadata("command"), claim.target)
                },
                missingCode: "command_ran_needs_evidence",
                missingSummary: "A command claim requires finite command evidence."
            )
        case .commandSucceeded:
            return verifyMatchingEvidence(
                claim,
                evidence: evidence,
                kinds: [.finiteCommand],
                predicate: { record in
                    matchesTarget(record.stringMetadata("command"), claim.target)
                        && record.boolMetadata("didTimeOut") != true
                        && record.intMetadata("exitCode") == 0
                },
                missingCode: "command_success_needs_evidence",
                missingSummary: "A command-success claim requires finite command evidence with exit code 0."
            )
        case .commandFailed:
            return verifyMatchingEvidence(
                claim,
                evidence: evidence,
                kinds: [.finiteCommand],
                predicate: { record in
                    let exitCode = record.intMetadata("exitCode")
                    let requestedExitCode = claim.qualifiers["exitCode"]?.intValue
                    return matchesTarget(record.stringMetadata("command"), claim.target)
                        && (
                            record.boolMetadata("didTimeOut") == true
                                || exitCode == nil
                                || exitCode != 0
                        )
                        && (requestedExitCode == nil || exitCode == requestedExitCode)
                },
                missingCode: "command_failure_needs_evidence",
                missingSummary: "A command-failure claim requires finite command failure, timeout, or failed-start evidence."
            )
        case .processAlive:
            return verifyMatchingEvidence(
                claim,
                evidence: evidence,
                kinds: [.managedProcess],
                predicate: { record in
                    matchesTarget(record.stringMetadata("processID"), claim.target)
                        && record.stringMetadata("status") == AgentKernelManagedProcessKindV2.running.rawValue
                },
                missingCode: "process_alive_needs_evidence",
                missingSummary: "A process-alive claim requires managed process evidence with running status."
            )
        case .portListening:
            let port = claim.qualifiers["port"]?.intValue ?? claim.target.flatMap(Int.init)
            return verifyMatchingEvidence(
                claim,
                evidence: evidence,
                kinds: [.localServerProbe, .managedProcess],
                predicate: { record in
                    guard record.intMetadata("port") == port else { return false }
                    return record.boolMetadata("isListening") == true
                },
                missingCode: "port_listening_needs_probe",
                missingSummary: "A port-listening claim requires local server probe evidence with a successful listener check."
            )
        case .urlResponds:
            return verifyMatchingEvidence(
                claim,
                evidence: evidence,
                kinds: [.localServerProbe, .managedProcess],
                predicate: { record in
                    matchesTarget(record.stringMetadata("url"), claim.target)
                        && record.intMetadata("httpStatusCode") != nil
                },
                missingCode: "url_responds_needs_probe",
                missingSummary: "A URL-response claim requires local server probe evidence with an HTTP response."
            )
        case .buildOrTestPassed:
            return verifyMatchingEvidence(
                claim,
                evidence: evidence,
                kinds: [.finiteCommand],
                predicate: { record in
                    record.hasClaimTag(.buildOrTest)
                        && record.boolMetadata("didTimeOut") != true
                        && record.intMetadata("exitCode") == 0
                },
                missingCode: "build_or_test_passed_needs_tagged_command",
                missingSummary: "A build/test success claim requires successful finite command evidence tagged as build-or-test."
            )
        case .taskCanceled:
            if ledger.state == .canceled || ledger.events.contains(where: \.isTaskCanceledEvent) {
                return AgentKernelClaimVerificationV2(claim: claim, status: .verified)
            }
            return verifyMatchingEvidence(
                claim,
                evidence: evidence,
                kinds: [.taskLifecycle],
                predicate: { record in
                    record.stringMetadata("state") == AgentKernelTaskStateV2.canceled.rawValue
                },
                missingCode: "task_canceled_needs_evidence",
                missingSummary: "A cancellation claim requires task-canceled state or task lifecycle evidence."
            )
        case .modelStatement:
            return AgentKernelClaimVerificationV2(
                claim: claim,
                status: .blocked,
                reason: reason(
                    code: "model_statement_not_deterministic_evidence",
                    summary: "Model statements are not deterministic evidence for final factual claims."
                )
            )
        case .unsupported:
            return AgentKernelClaimVerificationV2(
                claim: claim,
                status: .blocked,
                reason: reason(
                    code: "unsupported_claim",
                    summary: "The final answer contains a claim that is not covered by a deterministic verification hook."
                )
            )
        }
    }

    private nonisolated func verifyMatchingEvidence(
        _ claim: AgentKernelVerifiableClaimV2,
        evidence: [AgentKernelEvidenceRecordV2],
        kinds: Set<AgentKernelEvidenceKindV2>,
        predicate: (AgentKernelEvidenceRecordV2) -> Bool,
        missingCode: String,
        missingSummary: String
    ) -> AgentKernelClaimVerificationV2 {
        let matches = evidence.filter { record in
            guard let kind = AgentKernelEvidenceKindV2(rawValue: record.kind), kinds.contains(kind) else {
                return false
            }
            return predicate(record)
        }
        guard !matches.isEmpty else {
            return AgentKernelClaimVerificationV2(
                claim: claim,
                status: .needsTool,
                reason: reason(code: missingCode, summary: missingSummary)
            )
        }
        return AgentKernelClaimVerificationV2(
            claim: claim,
            status: .verified,
            evidenceIDs: matches.map(\.id)
        )
    }

    private nonisolated func matchesTarget(_ value: String?, _ target: String?) -> Bool {
        guard let target, !target.isEmpty else {
            return true
        }
        return value == target
    }

    private nonisolated func reason(code: String, summary: String) -> AgentKernelTerminalReasonV2 {
        AgentKernelTerminalReasonV2(code: code, summary: AgentKernelBoundedTextV2(summary))
    }
}

extension AgentKernelSessionLedgerV2 {
    nonisolated var evidenceRecords: [AgentKernelEvidenceRecordV2] {
        events.compactMap { event in
            guard case .evidenceRecorded(let evidence) = event.payload else {
                return nil
            }
            return evidence
        }
    }
}

private extension AgentKernelSessionEventV2 {
    nonisolated var isTaskCanceledEvent: Bool {
        guard case .taskCanceled = payload else {
            return false
        }
        return true
    }
}

private extension AgentKernelEvidenceRecordV2 {
    nonisolated func stringMetadata(_ key: String) -> String? {
        metadata[key]?.stringValue
    }

    nonisolated func intMetadata(_ key: String) -> Int? {
        metadata[key]?.intValue
    }

    nonisolated func boolMetadata(_ key: String) -> Bool? {
        metadata[key]?.boolValue
    }

    nonisolated func hasClaimTag(_ tag: AgentKernelEvidenceClaimTagV2) -> Bool {
        guard let rawTags = stringMetadata("claimTags") else {
            return false
        }
        return Set(rawTags.split(separator: ",").map(String.init)).contains(tag.rawValue)
    }
}

private extension AgentKernelMetadataValueV2 {
    nonisolated var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    nonisolated var intValue: Int? {
        guard case .int(let value) = self else {
            return nil
        }
        return value
    }

    nonisolated var boolValue: Bool? {
        guard case .bool(let value) = self else {
            return nil
        }
        return value
    }
}
