//
//  AgentLocalToolExecutor.swift
//  PixelPane
//
//  App-owned local tool executor and its bounded process-output collector.
//

import Foundation

nonisolated enum AgentToolExecutionStatus: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
    case waitingForApproval
}

nonisolated struct AgentToolExecutionResult: Codable, Equatable, Sendable {
    let status: AgentToolExecutionStatus
    let toolName: String
    let summary: AgentRunText
    let observation: AgentRunText
    let evidenceIDs: [UUID]
    let artifactIDs: [UUID]
    let waitID: UUID?
    let sideEffectID: UUID?

    init(
        status: AgentToolExecutionStatus,
        toolName: String,
        summary: AgentRunText,
        observation: AgentRunText,
        evidenceIDs: [UUID] = [],
        artifactIDs: [UUID] = [],
        waitID: UUID? = nil,
        sideEffectID: UUID? = nil
    ) {
        self.status = status
        self.toolName = toolName
        self.summary = summary
        self.observation = observation
        self.evidenceIDs = evidenceIDs
        self.artifactIDs = artifactIDs
        self.waitID = waitID
        self.sideEffectID = sideEffectID
    }

    var modelObservationText: String {
        modelObservationText()
    }

    func modelObservationText(observationCharacterLimit: Int? = nil) -> String {
        var lines = [
            "Tool result",
            "name: \(toolName)",
            "status: \(status.rawValue)",
            "summary: \(summary.text)"
        ]
        if !evidenceIDs.isEmpty {
            lines.append("evidenceIDs: \(evidenceIDs.map(\.uuidString).joined(separator: ", "))")
        }
        if !artifactIDs.isEmpty {
            lines.append("artifactIDs: \(artifactIDs.map(\.uuidString).joined(separator: ", "))")
        }
        if let waitID {
            lines.append("waitID: \(waitID.uuidString)")
        }
        if let sideEffectID {
            lines.append("sideEffectID: \(sideEffectID.uuidString)")
        }
        lines.append("observation:")
        let observationText = observationCharacterLimit.map {
            AgentRunText(observation.text, characterLimit: $0).text
        } ?? observation.text
        lines.append(observationText)
        return lines.joined(separator: "\n")
    }
}

actor AgentLocalToolExecutor {
    nonisolated static let supportedOperationKinds = AgentToolExecutionCapabilities.activeLocalRuntimeOperations

    private let store: AgentRunStore
    private let policy: AgentPermissionPolicy
    private let evidenceRecorder: AgentEvidenceRecorder
    private let sideEffects: AgentSideEffectController
    private let pathResolver: AgentLocalPathResolver
    private let decoder = JSONDecoder()
    private let maxFolderEntries = 200
    private let maxSearchFiles = 800
    private let maxSearchMatches = 8
    private let maxSearchObservationMatches = 5
    private let maxReadBytes = 700_000
    private let maxReadCharacters = 24_000
    private let maxObservationCharacters = 4_000
    private let maxReadObservationCharacters = 3_200
    private let maxSearchSnippetCharacters = 260
    private let snippetRadius = 220
    private let defaultProcessSnapshotLimit = 8
    private let maxProcessSnapshotLimit = 20
    private let defaultLocalListenerSnapshotLimit = 8
    private let maxLocalListenerSnapshotLimit = 20

    init(
        store: AgentRunStore,
        policy: AgentPermissionPolicy = AgentPermissionPolicy(),
        evidenceRecorder: AgentEvidenceRecorder? = nil,
        sideEffects: AgentSideEffectController? = nil,
        pathResolver: AgentLocalPathResolver = AgentLocalPathResolver()
    ) {
        self.store = store
        self.policy = policy
        self.evidenceRecorder = evidenceRecorder ?? AgentEvidenceRecorder(store: store)
        self.sideEffects = sideEffects ?? AgentSideEffectController(store: store)
        self.pathResolver = pathResolver
    }

    func execute(
        call: AgentKernelToolCallV2,
        runID: UUID,
        stepID: UUID?,
        providerTier: AgentModelCapabilityTier,
        context: AgentToolRunContext
    ) async throws -> AgentToolExecutionResult {
        let normalizedInvocation: AgentToolInvocation
        do {
            normalizedInvocation = try AgentToolContractRegistry.default.normalizedInvocation(for: call)
        } catch {
            return failedResult(call.name, "Malformed tool call arguments: \(error)")
        }
        let normalizedCall = normalizedInvocation.kernelToolCall
        let decision = policy.decision(
            for: AgentPermissionRequest(
                runMode: context.runMode,
                providerTier: providerTier,
                toolName: normalizedCall.name,
                arguments: normalizedCall.arguments,
                localGrants: context.localGrants,
                grantedScopes: context.grantedScopes,
                deniedScopes: context.deniedScopes,
                supportedOperations: context.supportedOperations
            )
        )

        switch decision.kind {
        case .deny:
            return failedResult(normalizedCall.name, "Denied by policy: \(decision.summary.text)")
        case .ask:
            if normalizedCall.name == "stage_write_proposal", decision.reason == .approvalRequired {
                return try await stageWriteProposal(
                    call: normalizedCall,
                    runID: runID,
                    stepID: stepID,
                    context: context
                )
            }
            if normalizedCall.name == "run_finite_command" {
                guard Self.isCommandApprovalReason(decision.reason) else {
                    return failedResult(normalizedCall.name, "Tool requires unavailable approval or grant: \(decision.summary.text)")
                }
                return try await stageCommandProposal(
                    call: normalizedCall,
                    runID: runID,
                    stepID: stepID,
                    context: context,
                    approvalSummary: decision.summary
                )
            }
            return failedResult(normalizedCall.name, "Tool requires unavailable approval or grant: \(decision.summary.text)")
        case .allow:
            break
        }

        switch normalizedCall.name {
        case "list_grants":
            return try await listGrants(call: normalizedCall, runID: runID, stepID: stepID, grants: context.localGrants)
        case "list_folder":
            return try await listFolder(call: normalizedCall, runID: runID, stepID: stepID, grants: context.localGrants)
        case "search_files":
            return try await searchFiles(call: normalizedCall, runID: runID, stepID: stepID, grants: context.localGrants)
        case "read_file":
            return try await readFile(call: normalizedCall, runID: runID, stepID: stepID, grants: context.localGrants)
        case "get_process_snapshot":
            return try await getProcessSnapshot(call: normalizedCall, runID: runID, stepID: stepID)
        case "get_local_listener_snapshot":
            return try await getLocalListenerSnapshot(call: normalizedCall, runID: runID, stepID: stepID, context: context)
        case "stage_write_proposal":
            return try await stageWriteProposal(call: normalizedCall, runID: runID, stepID: stepID, context: context)
        case "run_finite_command":
            return try await runAllowedFiniteCommand(call: normalizedCall, runID: runID, stepID: stepID, context: context)
        default:
            return failedResult(normalizedCall.name, "Tool \(normalizedCall.name) is registered but has no executor in this runtime.")
        }
    }

    private nonisolated static func isCommandApprovalReason(_ reason: AgentPermissionReason) -> Bool {
        switch reason {
        case .approvalRequired,
             .rawShellRequiresApproval,
             .fileMutationRequiresApproval,
             .installRequiresApproval,
             .networkRequiresApproval,
             .processControlRequiresApproval,
             .privilegedCommandRequiresApproval:
            return true
        case .allowed,
             .approvalGrantMatched,
             .unknownTool,
             .providerTierDisallowsTool,
             .runModeDisallowsTool,
             .unsupportedOperation,
             .missingRequiredArgument,
             .malformedArgument,
             .deniedScope,
             .missingFileGrant,
             .missingWriteGrant,
             .sensitivePathDenied,
             .unsafeCommandDenied:
            return false
        }
    }

    func approvedSideEffectResult(
        waitID: UUID,
        runID: UUID,
        stepID: UUID? = nil
    ) async throws -> AgentToolExecutionResult {
        guard let sideEffect = await store.sideEffects(runID: runID).first(where: { $0.approvalWaitID == waitID }) else {
            throw AgentToolOrchestratorError.missingApprovedSideEffect(waitID)
        }
        _ = try await sideEffects.resolveApproval(
            sideEffectID: sideEffect.sideEffectID,
            decision: .approved,
            summary: AgentRunText("Approved by user.")
        )
        let completed = try await sideEffects.executeApproved(sideEffectID: sideEffect.sideEffectID)
        return try await sideEffectExecutionResult(
            sideEffect: completed,
            stepID: stepID,
            fallbackSummary: AgentRunText("Approved side effect executed.")
        )
    }

    private func sideEffectExecutionResult(
        sideEffect completed: AgentRunSideEffectRecord,
        stepID: UUID?,
        fallbackSummary: AgentRunText
    ) async throws -> AgentToolExecutionResult {
        var evidenceIDs: [UUID] = []
        var artifactIDs: [UUID] = []
        let output = await commandOutput(for: completed)
        if completed.kind == .command, let output {
            let commandEvidence = try await evidenceRecorder.recordCommandOutput(
                runID: completed.runID,
                stepID: stepID,
                output: output
            )
            evidenceIDs.append(commandEvidence.evidenceID)
            if let artifactID = commandEvidence.artifactID {
                artifactIDs.append(artifactID)
            }
        }
        let sideEffectEvidence = try await evidenceRecorder.recordSideEffect(
            runID: completed.runID,
            stepID: stepID,
            sideEffect: completed
        )
        evidenceIDs.append(sideEffectEvidence.evidenceID)
        if let artifactID = sideEffectEvidence.artifactID {
            artifactIDs.append(artifactID)
        }
        let didComplete = completed.status == .completed
        let errorText = completed.errorSummary?.text
        let summary = sideEffectSummary(completed, output: output, fallback: fallbackSummary)
        let observation = sideEffectObservation(completed, output: output, errorText: errorText)
        return AgentToolExecutionResult(
            status: didComplete ? .succeeded : .failed,
            toolName: toolName(for: completed.kind),
            summary: summary,
            observation: observation,
            evidenceIDs: evidenceIDs,
            artifactIDs: artifactIDs,
            sideEffectID: completed.sideEffectID
        )
    }

    func deniedSideEffectResult(
        waitID: UUID,
        runID: UUID,
        stepID: UUID? = nil
    ) async throws -> AgentToolExecutionResult {
        guard let sideEffect = await store.sideEffects(runID: runID).first(where: { $0.approvalWaitID == waitID }) else {
            throw AgentToolOrchestratorError.missingApprovedSideEffect(waitID)
        }
        let denied = try await sideEffects.resolveApproval(
            sideEffectID: sideEffect.sideEffectID,
            decision: .denied,
            summary: AgentRunText("Denied by user.")
        )
        let evidence = try await evidenceRecorder.recordSideEffect(
            runID: runID,
            stepID: stepID,
            sideEffect: denied
        )
        return AgentToolExecutionResult(
            status: .failed,
            toolName: toolName(for: denied.kind),
            summary: AgentRunText("User denied the proposed \(sideEffectDisplayName(for: denied.kind))."),
            observation: AgentRunText("The proposed \(sideEffectDisplayName(for: denied.kind)) was denied and did not execute."),
            evidenceIDs: [evidence.evidenceID],
            artifactIDs: evidence.artifactID.map { [$0] } ?? [],
            sideEffectID: denied.sideEffectID
        )
    }

    private func sideEffectDisplayName(for kind: AgentRunSideEffectKind) -> String {
        switch kind {
        case .fileWrite:
            "file write"
        case .command:
            "command"
        case .processStart:
            "process start"
        case .processStop:
            "process stop"
        case .custom:
            "side effect"
        }
    }

    private func toolName(for kind: AgentRunSideEffectKind) -> String {
        switch kind {
        case .fileWrite:
            "stage_write_proposal"
        case .command:
            "run_finite_command"
        case .processStart:
            "start_process"
        case .processStop:
            "stop_process"
        case .custom:
            "custom_side_effect"
        }
    }

    private func commandOutput(for sideEffect: AgentRunSideEffectRecord) async -> AgentCommandExecutionOutput? {
        guard sideEffect.kind == .command, let artifactID = sideEffect.afterArtifactID else {
            return nil
        }
        guard let data = try? await store.readArtifact(artifactID) else {
            return nil
        }
        return try? decoder.decode(AgentCommandExecutionOutput.self, from: data)
    }

    private func sideEffectSummary(
        _ sideEffect: AgentRunSideEffectRecord,
        output: AgentCommandExecutionOutput?,
        fallback: AgentRunText
    ) -> AgentRunText {
        if let output {
            return output.summary
        }
        if sideEffect.status == .completed {
            return fallback
        }
        return AgentRunText("Approved side effect failed: \(sideEffect.errorSummary?.text ?? "No error summary was recorded.")")
    }

    private func sideEffectObservation(
        _ sideEffect: AgentRunSideEffectRecord,
        output: AgentCommandExecutionOutput?,
        errorText: String?
    ) -> AgentRunText {
        if let output {
            return AgentRunText(
                """
                Command: \(output.command)
                Working directory: \(output.workingDirectory)
                Exit code: \(output.exitCode.map(String.init) ?? "timeout")
                Timed out: \(output.didTimeOut ? "true" : "false")
                Stdout:
                \(output.stdout.text)
                Stderr:
                \(output.stderr.text)
                """,
                characterLimit: maxObservationCharacters
            )
        }
        return AgentRunText(
            "The approved \(sideEffect.kind.rawValue) side effect completed with status \(sideEffect.status.rawValue). Target: \(sideEffect.metadata["targetPath"]?.stringValue ?? "unknown").\(errorText.map { " Error: \($0)" } ?? "")",
            characterLimit: maxObservationCharacters
        )
    }

    private func listGrants(
        call: AgentKernelToolCallV2,
        runID: UUID,
        stepID: UUID?,
        grants: [AgentLocalFileGrant]
    ) async throws -> AgentToolExecutionResult {
        let provider = AgentGrantInventoryProvider()
        let snapshot = provider.snapshot(grants: grants)
        let evidence: AgentRunEvidenceRecord
        if let existing = await existingGrantInventoryEvidence(runID: runID) {
            evidence = existing
        } else {
            evidence = try await evidenceRecorder.recordFileGrants(
                runID: runID,
                stepID: stepID,
                grants: grants
            )
        }
        return AgentToolExecutionResult(
            status: .succeeded,
            toolName: call.name,
            summary: AgentRunText("Listed \(grants.count) granted location(s)."),
            observation: provider.observation(
                snapshot: snapshot,
                evidenceID: evidence.evidenceID,
                artifactID: evidence.artifactID,
                characterLimit: maxObservationCharacters
            ),
            evidenceIDs: [evidence.evidenceID],
            artifactIDs: evidence.artifactID.map { [$0] } ?? []
        )
    }

    private func existingGrantInventoryEvidence(runID: UUID) async -> AgentRunEvidenceRecord? {
        await store.evidenceArtifactSummary(runID: runID).evidence.first { record in
            record.kind == AgentEvidenceKind.fileGrant.rawValue
                && record.sourceID == AgentGrantInventoryProvider.sourceID(runID: runID)
        }
    }

    private func listFolder(
        call: AgentKernelToolCallV2,
        runID: UUID,
        stepID: UUID?,
        grants: [AgentLocalFileGrant]
    ) async throws -> AgentToolExecutionResult {
        let rawPath = call.arguments["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let entries: [AgentFolderEntry]
        let folderPath: String
        let isTruncated: Bool

        if rawPath.isEmpty {
            entries = grants.map { grant in
                AgentFolderEntry(
                    path: grant.path,
                    displayName: URL(fileURLWithPath: grant.path).lastPathComponent,
                    isDirectory: grant.isDirectory,
                    byteCount: nil
                )
            }
            folderPath = "granted-roots"
            isTruncated = false
        } else {
            let resolution = pathResolver.resolve(
                rawPath,
                grants: grants,
                access: .read,
                target: .existingDirectory
            )
            guard let resolved = resolution.resolution else {
                return failedResult(call.name, resolution.failure?.summary.text ?? "The requested folder is outside granted local file access.")
            }
            let folder = resolved.url
            let urls = ((try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? [])
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            isTruncated = urls.count > maxFolderEntries
            entries = urls.prefix(maxFolderEntries).map { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                return AgentFolderEntry(
                    path: url.standardizedFileURL.path,
                    displayName: url.lastPathComponent,
                    isDirectory: values?.isDirectory ?? false,
                    byteCount: values?.fileSize
                )
            }
            folderPath = folder.path
        }

        let evidence = try await evidenceRecorder.recordFolderList(
            runID: runID,
            stepID: stepID,
            folderPath: folderPath,
            entries: entries,
            isTruncated: isTruncated
        )
        let body = entries.isEmpty
            ? "No entries."
            : entries.map { entry in
                let type = entry.isDirectory ? "Folder" : "File"
                let size = entry.byteCount.map { " bytes: \($0)" } ?? ""
                return "- \(type): \(entry.path)\(size)"
            }.joined(separator: "\n")
        return AgentToolExecutionResult(
            status: .succeeded,
            toolName: call.name,
            summary: AgentRunText("Listed \(entries.count) item(s)."),
            observation: AgentRunText(body, characterLimit: maxObservationCharacters),
            evidenceIDs: [evidence.evidenceID],
            artifactIDs: evidence.artifactID.map { [$0] } ?? []
        )
    }

    private func searchFiles(
        call: AgentKernelToolCallV2,
        runID: UUID,
        stepID: UUID?,
        grants: [AgentLocalFileGrant]
    ) async throws -> AgentToolExecutionResult {
        let query = call.arguments["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return failedResult(call.name, "Search query is empty.")
        }
        let requestedFilenameOnly = call.arguments["filenameOnly"] == "true"
        let filenameOnly = requestedFilenameOnly || policy.referencesSensitivePath(query)
        let terms = searchTerms(from: query)
        guard !terms.isEmpty else {
            return failedResult(call.name, "Search query has no searchable terms.")
        }
        let searchGrants: [AgentLocalFileGrant]
        let resolvedRootPath: String?
        let rootPath = call.arguments["rootPath"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rootPath, !rootPath.isEmpty {
            let resolution = pathResolver.resolve(
                rootPath,
                grants: grants,
                access: .read,
                target: .existingDirectory
            )
            guard let resolved = resolution.resolution else {
                return failedResult(call.name, resolution.failure?.summary.text ?? "The requested search root is outside granted local file access.")
            }
            searchGrants = [
                AgentLocalFileGrant(
                    path: resolved.path,
                    isDirectory: true
                )
            ]
            resolvedRootPath = resolved.path
        } else {
            searchGrants = grants
            resolvedRootPath = nil
        }

        var matches: [AgentFileSearchMatch] = []
        var visited = 0
        for url in readableFileURLs(grants: searchGrants, query: query, filenameOnly: filenameOnly) {
            guard visited < maxSearchFiles else { break }
            visited += 1
            let searchText: String
            if filenameOnly {
                searchText = "\(url.lastPathComponent)\n\(url.path)"
            } else {
                guard let content = readText(url, maxCharacters: maxReadCharacters) else { continue }
                searchText = searchableText(for: url, content: content.text)
            }
            let pathScore = score(text: url.path, terms: terms) * 4
            let exactScore = queryExactMatchScore(query: query, path: url.path, content: searchText)
            let extensionScore = preferredExtensionScore(url)
            let contentScore = score(text: searchText, terms: terms)
            let totalScore = pathScore + exactScore + extensionScore + contentScore
            guard totalScore > 0 else { continue }
            matches.append(
                AgentFileSearchMatch(
                    path: url.path,
                    preview: AgentRunText(
                        filenameOnly
                            ? "Filename/path match only; file contents were not read."
                            : snippet(from: searchText, terms: terms),
                        characterLimit: maxSearchSnippetCharacters
                    ),
                    score: totalScore
                )
            )
        }

        let sorted = matches.sorted {
            if $0.score == $1.score {
                return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
            return $0.score > $1.score
        }
        let limited = Array(sorted.prefix(maxSearchMatches))
        let evidence = try await evidenceRecorder.recordFileSearch(
            runID: runID,
            stepID: stepID,
            query: query,
            matches: limited,
            isTruncated: sorted.count > limited.count || visited >= maxSearchFiles,
            rootPath: resolvedRootPath,
            filenameOnly: filenameOnly
        )
        let body = limited.isEmpty
            ? "No matching files found."
            : limited.prefix(maxSearchObservationMatches).map {
                "- \($0.path)\n  score: \($0.score)\n  snippet: \($0.preview.text)"
            }.joined(separator: "\n")
        return AgentToolExecutionResult(
            status: .succeeded,
            toolName: call.name,
            summary: AgentRunText("Found \(limited.count) matching file(s)."),
            observation: AgentRunText(body, characterLimit: maxObservationCharacters),
            evidenceIDs: [evidence.evidenceID],
            artifactIDs: evidence.artifactID.map { [$0] } ?? []
        )
    }

    private func readFile(
        call: AgentKernelToolCallV2,
        runID: UUID,
        stepID: UUID?,
        grants: [AgentLocalFileGrant]
    ) async throws -> AgentToolExecutionResult {
        guard let rawPath = call.arguments["path"] else {
            return failedResult(call.name, "The requested file path is missing.")
        }
        let resolution = pathResolver.resolve(
            rawPath,
            grants: grants,
            access: .read,
            target: .existingFile
        )
        guard let resolved = resolution.resolution else {
            return failedResult(call.name, resolution.failure?.summary.text ?? "The requested file is outside granted local file access.")
        }
        let fileURL = resolved.url
        guard let content = readText(fileURL, maxCharacters: maxReadCharacters) else {
            return failedResult(call.name, "The requested file is not a supported bounded text file: \(fileURL.path)")
        }
        let evidence = try await evidenceRecorder.recordFileRead(
            runID: runID,
            stepID: stepID,
            path: fileURL.path,
            content: content.text,
            isTruncated: content.isTruncated
        )
        let displayText = searchableText(for: fileURL, content: content.text)
        let excerpt = bestExcerpt(from: displayText, terms: searchTerms(from: fileURL.lastPathComponent), limit: maxReadObservationCharacters)
        let observation = """
        Path: \(fileURL.path)
        Evidence ID: \(evidence.evidenceID.uuidString)
        Artifact ID: \(evidence.artifactID?.uuidString ?? "none")
        Original content truncated by reader: \(content.isTruncated ? "true" : "false")
        Prompt excerpt:
        \(excerpt)
        """
        return AgentToolExecutionResult(
            status: .succeeded,
            toolName: call.name,
            summary: AgentRunText("Read \(fileURL.path)."),
            observation: AgentRunText(observation, characterLimit: maxObservationCharacters),
            evidenceIDs: [evidence.evidenceID],
            artifactIDs: evidence.artifactID.map { [$0] } ?? []
        )
    }

    private func getProcessSnapshot(
        call: AgentKernelToolCallV2,
        runID: UUID,
        stepID: UUID?
    ) async throws -> AgentToolExecutionResult {
        let limit = Int(call.arguments["limit"] ?? "") ?? defaultProcessSnapshotLimit
        let snapshot = try await Self.collectProcessSnapshot(limit: limit)
        let evidence = try await evidenceRecorder.recordProcessSnapshot(
            runID: runID,
            stepID: stepID,
            snapshot: snapshot
        )
        let rows = snapshot.rows.isEmpty
            ? "No running process rows were returned."
            : snapshot.rows.map { row in
                String(
                    format: "- pid: %d cpu: %.1f%% memory: %.1f%% executable: %@",
                    row.pid,
                    row.cpuPercent,
                    row.memoryPercent,
                    row.executableName
                )
            }.joined(separator: "\n")
        let observation = """
        Process snapshot
        rowCount: \(snapshot.rows.count)
        requestedLimit: \(snapshot.requestedLimit)
        rows:
        \(rows)
        """
        return AgentToolExecutionResult(
            status: .succeeded,
            toolName: call.name,
            summary: AgentRunText("Recorded \(snapshot.rows.count) running process row(s)."),
            observation: AgentRunText(observation, characterLimit: maxObservationCharacters),
            evidenceIDs: [evidence.evidenceID],
            artifactIDs: evidence.artifactID.map { [$0] } ?? []
        )
    }

    private func getLocalListenerSnapshot(
        call: AgentKernelToolCallV2,
        runID: UUID,
        stepID: UUID?,
        context: AgentToolRunContext
    ) async throws -> AgentToolExecutionResult {
        let limit = Int(call.arguments["limit"] ?? "") ?? defaultLocalListenerSnapshotLimit
        let requestedPort = call.arguments["port"].flatMap(Int.init)

        let resolvedRootPath: String?
        if let rawRootPath = call.arguments["rootPath"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawRootPath.isEmpty {
            let resolution = pathResolver.resolve(
                rawRootPath,
                grants: context.localGrants,
                access: .read,
                target: .existingDirectory
            )
            guard let resolved = resolution.resolution else {
                return failedResult(call.name, resolution.failure?.summary.text ?? "The requested root path is outside granted local file access.")
            }
            resolvedRootPath = resolved.path
        } else {
            resolvedRootPath = nil
        }

        let snapshot = try await Self.collectLocalListenerSnapshot(
            limit: limit,
            port: requestedPort,
            rootPath: resolvedRootPath,
            grants: context.localGrants
        )
        let evidence = try await evidenceRecorder.recordLocalListenerSnapshot(
            runID: runID,
            stepID: stepID,
            snapshot: snapshot
        )
        let rows = snapshot.rows.isEmpty
            ? "No local listener rows matched the typed filters."
            : snapshot.rows.map { row in
                [
                    "- port: \(row.port)",
                    "address: \(row.listenAddress ?? "unknown")",
                    "pid: \(row.pid)",
                    "executable: \(row.executableName)",
                    "workingDirectory: \(row.workingDirectory ?? "not-recorded")"
                ].joined(separator: " ")
            }.joined(separator: "\n")
        let observation = """
        Local listener snapshot
        rowCount: \(snapshot.rows.count)
        requestedLimit: \(snapshot.requestedLimit)
        requestedPort: \(snapshot.requestedPort.map(String.init) ?? "none")
        requestedRootPath: \(snapshot.requestedRootPath ?? "none")
        rows:
        \(rows)
        """
        return AgentToolExecutionResult(
            status: .succeeded,
            toolName: call.name,
            summary: AgentRunText("Recorded \(snapshot.rows.count) local listener row(s)."),
            observation: AgentRunText(observation, characterLimit: maxObservationCharacters),
            evidenceIDs: [evidence.evidenceID],
            artifactIDs: evidence.artifactID.map { [$0] } ?? []
        )
    }

    private func stageWriteProposal(
        call: AgentKernelToolCallV2,
        runID: UUID,
        stepID: UUID?,
        context: AgentToolRunContext
    ) async throws -> AgentToolExecutionResult {
        let operation = AgentFileWriteOperation(rawValue: call.arguments["operation"] ?? "create") ?? .create
        guard let rawPath = call.arguments["targetPath"] else {
            return failedResult(call.name, "The requested write target is missing.")
        }
        let resolution = pathResolver.resolve(
                rawPath,
                grants: context.localGrants,
                access: .write,
                target: .writeTarget(requiresExistingParent: true),
                preferredDirectoryPath: call.arguments["preferredDirectoryPath"]
        )
        guard let resolved = resolution.resolution else {
            let baseMessage = resolution.failure?.summary.text ?? "The requested write target is outside granted writable local access."
            return failedResult(call.name, "\(baseMessage) \(writableTargetGuidance(grants: context.localGrants))")
        }
        let targetURL = resolved.url
        let content = call.arguments["content"] ?? ""
        if let duplicate = await existingLiveFileWriteSideEffect(runID: runID, targetPath: targetURL.path, operation: operation) {
            let observation = "A \(duplicate.status.rawValue) file-write side effect already exists for \(targetURL.path); no duplicate proposal was staged."
            return AgentToolExecutionResult(
                status: .succeeded,
                toolName: call.name,
                summary: AgentRunText("Skipped duplicate file-write proposal for \(targetURL.path)."),
                observation: AgentRunText(observation),
                sideEffectID: duplicate.sideEffectID
            )
        }
        let stage = try await sideEffects.stage(
            runID: runID,
            stepID: stepID,
            draft: .fileWrite(
                AgentFileWriteDraft(
                    operation: operation,
                    targetPath: targetURL.path,
                    content: content
                )
            )
        )
        return AgentToolExecutionResult(
            status: .waitingForApproval,
            toolName: call.name,
            summary: AgentRunText("Waiting for approval to \(operation.rawValue) \(targetURL.path)."),
            observation: AgentRunText("A file write proposal was staged and is waiting for user approval. Target: \(targetURL.path)."),
            waitID: stage.wait.waitID,
            sideEffectID: stage.sideEffect.sideEffectID
        )
    }

    private func existingLiveFileWriteSideEffect(
        runID: UUID,
        targetPath: String,
        operation: AgentFileWriteOperation
    ) async -> AgentRunSideEffectRecord? {
        let normalizedTarget = URL(fileURLWithPath: targetPath).standardizedFileURL.path
        return await store.sideEffects(runID: runID).last { sideEffect in
            guard sideEffect.kind == .fileWrite,
                  sideEffect.metadata["targetPath"]?.stringValue.map({
                      URL(fileURLWithPath: $0).standardizedFileURL.path == normalizedTarget
                  }) == true,
                  sideEffect.metadata["operation"]?.stringValue == operation.rawValue else {
                return false
            }
            switch sideEffect.status {
            case .proposed, .approved, .running, .completed:
                return true
            case .denied, .failed, .rolledBack, .canceled:
                return false
            }
        }
    }

    private func stageCommandProposal(
        call: AgentKernelToolCallV2,
        runID: UUID,
        stepID: UUID?,
        context: AgentToolRunContext,
        approvalSummary: AgentRunText
    ) async throws -> AgentToolExecutionResult {
        let draft = try commandDraft(call: call, context: context)
        let stage = try await sideEffects.stage(
            runID: runID,
            stepID: stepID,
            draft: .command(draft)
        )
        return AgentToolExecutionResult(
            status: .waitingForApproval,
            toolName: call.name,
            summary: AgentRunText("Waiting for approval to run command: \(draft.command)"),
            observation: AgentRunText("\(approvalSummary.text)\nA command proposal was staged and is waiting for user approval. Working directory: \(draft.workingDirectory). Command: \(draft.command)"),
            waitID: stage.wait.waitID,
            sideEffectID: stage.sideEffect.sideEffectID
        )
    }

    private func runAllowedFiniteCommand(
        call: AgentKernelToolCallV2,
        runID: UUID,
        stepID: UUID?,
        context: AgentToolRunContext
    ) async throws -> AgentToolExecutionResult {
        let draft = try commandDraft(call: call, context: context)
        let stage = try await sideEffects.stage(
            runID: runID,
            stepID: stepID,
            draft: .command(draft)
        )
        _ = try await sideEffects.resolveApproval(
            sideEffectID: stage.sideEffect.sideEffectID,
            decision: .approved,
            summary: AgentRunText("Allowed by command policy.")
        )
        let completed = try await sideEffects.executeApproved(sideEffectID: stage.sideEffect.sideEffectID)
        return try await sideEffectExecutionResult(
            sideEffect: completed,
            stepID: stepID,
            fallbackSummary: AgentRunText("Allowed command executed.")
        )
    }

    private func commandDraft(
        call: AgentKernelToolCallV2,
        context: AgentToolRunContext
    ) throws -> AgentCommandDraft {
        let command = call.arguments["command"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !command.isEmpty else {
            throw AgentSideEffectError.invalidDraft("Command cannot be empty.")
        }
        let rawWorkingDirectory = call.arguments["workingDirectory"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let workingDirectory: String
        if rawWorkingDirectory.isEmpty {
            throw AgentSideEffectError.invalidDraft("Working directory is required for shell commands.")
        } else {
            let resolution = pathResolver.resolve(
                rawWorkingDirectory,
                grants: context.localGrants,
                access: .read,
                target: .existingDirectory
            )
            guard let resolved = resolution.resolution else {
                throw AgentSideEffectError.invalidDraft(resolution.failure?.summary.text ?? "Working directory is outside granted local file access.")
            }
            workingDirectory = resolved.path
        }
        let timeout = Int(call.arguments["timeoutSeconds"] ?? "") ?? 30
        return AgentCommandDraft(
            command: command,
            workingDirectory: workingDirectory,
            timeoutSeconds: timeout
        )
    }

    /// Tell the model exactly which granted roots exist and how to retarget a denied write,
    /// so an ambiguous/out-of-grant write proposal can recover into a single valid absolute
    /// path instead of looping on bare denial strings (RELY-005 / RC-5).
    private func writableTargetGuidance(grants: [AgentLocalFileGrant]) -> String {
        let writableRoots = grants
            .filter(\.isDirectory)
            .map { $0.path }
        guard !writableRoots.isEmpty else {
            return "No granted folders are available; ask the user to grant a folder before writing."
        }
        return "Granted folders: \(writableRoots.joined(separator: ", ")). Use a single absolute path inside exactly one of these."
    }

    private func failedResult(_ toolName: String, _ message: String) -> AgentToolExecutionResult {
        AgentToolExecutionResult(
            status: .failed,
            toolName: toolName,
            summary: AgentRunText(message),
            observation: AgentRunText(message)
        )
    }

    private func readableFileURLs(
        grants: [AgentLocalFileGrant],
        query: String? = nil,
        filenameOnly: Bool = false
    ) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        let perGrantLimit = grants.count <= 1
            ? maxSearchFiles
            : max(60, maxSearchFiles / max(1, grants.count))
        for grant in grants {
            var grantCount = 0
            if grant.isDirectory {
                guard let enumerator = FileManager.default.enumerator(
                    at: grant.url,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let url as URL in enumerator {
                    guard grantCount < perGrantLimit else { break }
                    if shouldSkip(url) {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard isRegularFile(url) else { continue }
                    if !filenameOnly {
                        guard isTextLikeFile(url), fileSize(url) <= maxReadBytes else { continue }
                    }
                    let standardized = url.standardizedFileURL
                    guard seen.insert(standardized.path).inserted else { continue }
                    urls.append(standardized)
                    grantCount += 1
                }
            } else if isRegularFile(grant.url),
                      filenameOnly || (isTextLikeFile(grant.url) && fileSize(grant.url) <= maxReadBytes) {
                let standardized = grant.url.standardizedFileURL
                if seen.insert(standardized.path).inserted {
                    urls.append(standardized)
                }
            }
        }
        let sorted = urls.sorted { lhs, rhs in
            let lhsScore = sourceScore(lhs, query: query)
            let rhsScore = sourceScore(rhs, query: query)
            if lhsScore == rhsScore {
                return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            }
            return lhsScore > rhsScore
        }
        return Array(sorted.prefix(maxSearchFiles))
    }

    private func readText(_ url: URL, maxCharacters: Int) -> AgentRunText? {
        guard fileSize(url) <= maxReadBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              !data.contains(0) else {
            return nil
        }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? String(decoding: data, as: UTF8.self)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : AgentRunText(trimmed, characterLimit: maxCharacters)
    }

    private func isTextLikeFile(_ url: URL) -> Bool {
        let allowedExtensions: Set<String> = [
            "txt", "md", "markdown", "rst", "json", "yaml", "yml", "toml", "xml",
            "csv", "tsv", "log", "swift", "py", "js", "ts", "tsx", "jsx", "html",
            "css", "scss", "c", "h", "m", "mm", "cpp", "hpp", "java", "kt", "go",
            "rs", "rb", "php", "sh", "zsh", "bash", "sql", "ini", "conf", "env",
            "tex"
        ]
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty || allowedExtensions.contains(ext)
    }

    private func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile ?? false
    }

    private func shouldSkip(_ url: URL) -> Bool {
        let skipped = Set([".git", "node_modules", "DerivedData", ".build", "build", "dist", ".next"])
        return url.pathComponents.contains { skipped.contains($0) }
    }

    private func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private func searchTerms(from query: String) -> [String] {
        var seen = Set<String>()
        return AgentLocalEvidencePlanner.terms(from: query)
            .filter { seen.insert($0).inserted }
    }

    private struct RawLocalListenerRow: Equatable {
        let port: Int
        let listenAddress: String?
        let pid: Int
        let executableName: String
    }

    private nonisolated static func collectLocalListenerSnapshot(
        limit: Int,
        port: Int?,
        rootPath: String?,
        grants: [AgentLocalFileGrant]
    ) async throws -> AgentLocalListenerSnapshotEvidence {
        let clampedLimit = min(max(limit, 1), 20)
        return try await Task.detached(priority: .utility) {
            try collectLocalListenerSnapshotBlocking(
                limit: clampedLimit,
                port: port,
                rootPath: rootPath,
                grants: grants
            )
        }.value
    }

    private nonisolated static func collectLocalListenerSnapshotBlocking(
        limit: Int,
        port: Int?,
        rootPath: String?,
        grants: [AgentLocalFileGrant]
    ) throws -> AgentLocalListenerSnapshotEvidence {
        var arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
        if let port {
            arguments.insert("-iTCP:\(port)", at: 1)
        }
        let output = try runFixedProcess(
            executablePath: "/usr/sbin/lsof",
            arguments: arguments,
            timeoutSeconds: 3,
            maxBytes: 48_000,
            failureLabel: "Local listener snapshot",
            allowNonZeroExit: true
        )
        let rawRows = localListenerRows(from: output.stdout, port: port)
        var rows: [AgentLocalListenerSnapshotRow] = []
        for raw in rawRows {
            let workingDirectory = grantedWorkingDirectory(
                forPID: raw.pid,
                grants: grants,
                rootPath: rootPath
            )
            if rootPath != nil, workingDirectory == nil {
                continue
            }
            rows.append(
                AgentLocalListenerSnapshotRow(
                    port: raw.port,
                    listenAddress: raw.listenAddress,
                    pid: raw.pid,
                    executableName: raw.executableName,
                    workingDirectory: workingDirectory
                )
            )
            if rows.count >= limit {
                break
            }
        }
        return AgentLocalListenerSnapshotEvidence(
            rows: rows,
            requestedLimit: limit,
            requestedPort: port,
            requestedRootPath: rootPath
        )
    }

    private nonisolated static func localListenerRows(from output: String, port requestedPort: Int?) -> [RawLocalListenerRow] {
        var pid: Int?
        var executable: String?
        var rows: [RawLocalListenerRow] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            switch prefix {
            case "p":
                pid = Int(value)
                executable = nil
            case "c":
                executable = sanitizedExecutableName(value)
            case "n":
                guard let pid,
                      let executable,
                      let endpoint = localListenerEndpoint(from: value) else {
                    continue
                }
                if let requestedPort, endpoint.port != requestedPort {
                    continue
                }
                rows.append(
                    RawLocalListenerRow(
                        port: endpoint.port,
                        listenAddress: endpoint.listenAddress,
                        pid: pid,
                        executableName: executable
                    )
                )
            default:
                continue
            }
        }

        var seen = Set<String>()
        return rows
            .filter { seen.insert("\($0.pid):\($0.port):\($0.listenAddress ?? "")").inserted }
            .sorted {
                if $0.port == $1.port {
                    if $0.executableName == $1.executableName {
                        return $0.pid < $1.pid
                    }
                    return $0.executableName < $1.executableName
                }
                return $0.port < $1.port
            }
    }

    private nonisolated static func localListenerEndpoint(from value: String) -> (port: Int, listenAddress: String?)? {
        let cleaned = value
            .replacingOccurrences(of: " (LISTEN)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = cleaned.lastIndex(of: ":") else {
            return nil
        }
        let portText = String(cleaned[cleaned.index(after: colon)...])
        guard let port = Int(portText) else {
            return nil
        }
        let address = String(cleaned[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (port, address.isEmpty ? nil : address)
    }

    private nonisolated static func grantedWorkingDirectory(
        forPID pid: Int,
        grants: [AgentLocalFileGrant],
        rootPath: String?
    ) -> String? {
        guard !grants.isEmpty else { return nil }
        guard let cwd = try? processWorkingDirectory(pid: pid) else { return nil }
        let normalized = URL(fileURLWithPath: cwd).standardizedFileURL.path
        if let rootPath {
            let root = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            guard normalized == rootPath || normalized.hasPrefix(root) else {
                return nil
            }
        }
        return grants.contains { $0.allowsRead(normalized) } ? normalized : nil
    }

    private nonisolated static func processWorkingDirectory(pid: Int) throws -> String? {
        let output = try runFixedProcess(
            executablePath: "/usr/sbin/lsof",
            arguments: ["-a", "-p", String(pid), "-d", "cwd", "-Fn"],
            timeoutSeconds: 1,
            maxBytes: 4_000,
            failureLabel: "Process working-directory snapshot",
            allowNonZeroExit: true
        )
        return output.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .first(where: { $0.hasPrefix("n/") })
            .map { String($0.dropFirst()) }
    }

    private struct FixedProcessOutput {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private nonisolated static func runFixedProcess(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: Int,
        maxBytes: Int,
        failureLabel: String,
        allowNonZeroExit: Bool = false
    ) throws -> FixedProcessOutput {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let collector = AgentProcessSnapshotOutputCollector(maxBytes: maxBytes)

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendStdout(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendStderr(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw AgentSideEffectError.executionFailed("\(failureLabel) failed to start: \(error.localizedDescription)")
        }

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            finished.signal()
        }

        let didTimeOut = finished.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut
        if didTimeOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + .milliseconds(750))
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        collector.appendStdout((try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data())
        collector.appendStderr((try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data())

        guard !didTimeOut else {
            throw AgentSideEffectError.executionFailed("\(failureLabel) timed out.")
        }
        if !allowNonZeroExit && process.terminationStatus != 0 {
            let stderr = AgentRunText(collector.stderrText, characterLimit: 600).text
            throw AgentSideEffectError.executionFailed("\(failureLabel) exited with \(process.terminationStatus). \(stderr)")
        }
        return FixedProcessOutput(
            stdout: collector.stdoutText,
            stderr: collector.stderrText,
            exitCode: process.terminationStatus
        )
    }

    private nonisolated static func collectProcessSnapshot(limit: Int) async throws -> AgentProcessSnapshotEvidence {
        let clampedLimit = min(max(limit, 1), 20)
        return try await Task.detached(priority: .utility) {
            try collectProcessSnapshotBlocking(limit: clampedLimit)
        }.value
    }

    private nonisolated static func collectProcessSnapshotBlocking(limit: Int) throws -> AgentProcessSnapshotEvidence {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let collector = AgentProcessSnapshotOutputCollector(maxBytes: 32_000)

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid,pcpu,pmem,comm", "-r"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendStdout(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendStderr(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw AgentSideEffectError.executionFailed("Process snapshot failed to start: \(error.localizedDescription)")
        }

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            finished.signal()
        }

        let didTimeOut = finished.wait(timeout: .now() + .seconds(3)) == .timedOut
        if didTimeOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + .milliseconds(750))
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        collector.appendStdout((try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data())
        collector.appendStderr((try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data())

        guard !didTimeOut else {
            throw AgentSideEffectError.executionFailed("Process snapshot timed out.")
        }
        guard process.terminationStatus == 0 else {
            let stderr = AgentRunText(collector.stderrText, characterLimit: 600).text
            throw AgentSideEffectError.executionFailed("Process snapshot exited with \(process.terminationStatus). \(stderr)")
        }

        let rows = processSnapshotRows(from: collector.stdoutText, limit: limit)
        return AgentProcessSnapshotEvidence(rows: rows, requestedLimit: limit)
    }

    private nonisolated static func processSnapshotRows(from output: String, limit: Int) -> [AgentProcessSnapshotRow] {
        let parsed = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> AgentProcessSnapshotRow? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      !trimmed.lowercased().hasPrefix("pid") else {
                    return nil
                }
                let parts = trimmed.split(
                    maxSplits: 3,
                    omittingEmptySubsequences: true,
                    whereSeparator: { $0 == " " || $0 == "\t" }
                )
                guard parts.count == 4,
                      let pid = Int(parts[0]),
                      let cpu = Double(parts[1]),
                      let memory = Double(parts[2]) else {
                    return nil
                }
                let executable = sanitizedExecutableName(String(parts[3]))
                return AgentProcessSnapshotRow(
                    pid: pid,
                    cpuPercent: cpu,
                    memoryPercent: memory,
                    executableName: executable
                )
            }
        return Array(
            parsed
                .sorted {
                    if $0.cpuPercent == $1.cpuPercent {
                        if $0.memoryPercent == $1.memoryPercent {
                            return $0.pid < $1.pid
                        }
                        return $0.memoryPercent > $1.memoryPercent
                    }
                    return $0.cpuPercent > $1.cpuPercent
                }
                .prefix(max(1, limit))
        )
    }

    private nonisolated static func sanitizedExecutableName(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        let name = trimmed.contains("/")
            ? URL(fileURLWithPath: trimmed).lastPathComponent
            : trimmed
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "unknown" : sanitized
    }

    private func score(text: String, terms: [String]) -> Int {
        let lowercased = text.lowercased()
        return terms.reduce(0) { total, term in
            total + (lowercased.contains(term) ? max(1, term.count) : 0)
        }
    }

    private func queryExactMatchScore(query: String, path: String, content: String) -> Int {
        let normalizedQuery = query
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= 4 else { return 0 }
        let lowerPath = path.lowercased()
        let lowerContent = content.lowercased()
        var score = 0
        if lowerPath.contains(normalizedQuery) {
            score += normalizedQuery.count * 4
        }
        if lowerContent.contains(normalizedQuery) {
            score += normalizedQuery.count * 3
        }
        return score
    }

    private func preferredExtensionScore(_ url: URL) -> Int {
        switch url.pathExtension.lowercased() {
        case "html", "htm", "md", "markdown", "txt":
            return 8
        case "json", "yaml", "yml", "toml", "csv", "tsv":
            return 4
        default:
            return 0
        }
    }

    private func sourceScore(_ url: URL, query: String?) -> Int {
        guard let query, !query.isEmpty else {
            return preferredExtensionScore(url)
        }
        let lowerQuery = query.lowercased()
        var score = preferredExtensionScore(url)
        for component in url.deletingLastPathComponent().pathComponents {
            let normalized = component.lowercased()
            guard normalized.count >= 3 else { continue }
            if lowerQuery.contains(normalized) {
                score += normalized.count * 4
            }
        }
        return score
    }

    private func searchableText(for url: URL, content: String) -> String {
        switch url.pathExtension.lowercased() {
        case "html", "htm":
            return htmlVisibleText(content)
        default:
            return content
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func htmlVisibleText(_ html: String) -> String {
        var text = html
        let replacements: [(String, String)] = [
            (#"(?is)<script\b[^>]*>.*?</script>"#, " "),
            (#"(?is)<style\b[^>]*>.*?</style>"#, " "),
            (#"(?is)<!--.*?-->"#, " "),
            (#"(?i)</(h[1-6]|p|li|section|article|div|br|tr)>"#, "\n"),
            (#"(?is)<[^>]+>"#, " ")
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'")
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s*\n+"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func snippet(from content: String, terms: [String]) -> String {
        let lowercased = content.lowercased()
        let firstRange = terms.compactMap { lowercased.range(of: $0) }.sorted { $0.lowerBound < $1.lowerBound }.first
        guard let range = firstRange else {
            return String(content.prefix(snippetRadius * 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let startDistance = lowercased.distance(from: lowercased.startIndex, to: range.lowerBound)
        let startOffset = max(0, startDistance - snippetRadius)
        let endOffset = min(content.count, startDistance + snippetRadius)
        let start = content.index(content.startIndex, offsetBy: startOffset)
        let end = content.index(content.startIndex, offsetBy: endOffset)
        return String(content[start..<end])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bestExcerpt(from content: String, terms: [String], limit: Int) -> String {
        let normalized = content
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else {
            return normalized
        }
        let snippetText = snippet(from: normalized, terms: terms)
        if snippetText.count >= min(limit, maxSearchSnippetCharacters) {
            return String(snippetText.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

private final class AgentProcessSnapshotOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private nonisolated(unsafe) var stdoutData = Data()
    private nonisolated(unsafe) var stderrData = Data()

    nonisolated init(maxBytes: Int) {
        self.maxBytes = max(1, maxBytes)
    }

    nonisolated func appendStdout(_ data: Data) {
        append(data, to: &stdoutData)
    }

    nonisolated func appendStderr(_ data: Data) {
        append(data, to: &stderrData)
    }

    nonisolated var stdoutText: String {
        text(from: stdoutData)
    }

    nonisolated var stderrText: String {
        text(from: stderrData)
    }

    private nonisolated func append(_ data: Data, to target: inout Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, maxBytes - target.count)
        target.append(data.prefix(remaining))
    }

    private nonisolated func text(from data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? String(decoding: data, as: UTF8.self)
    }
}
