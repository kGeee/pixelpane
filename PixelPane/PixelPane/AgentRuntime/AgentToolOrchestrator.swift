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

nonisolated struct AgentToolRunContext: Codable, Equatable, Sendable {
    let runMode: AgentRunPermissionMode
    let localGrants: [AgentLocalFileGrant]
    let grantedScopes: [AgentPermissionScope]
    let deniedScopes: [AgentPermissionScope]

    init(
        runMode: AgentRunPermissionMode,
        localGrants: [AgentLocalFileGrant] = [],
        grantedScopes: [AgentPermissionScope] = [],
        deniedScopes: [AgentPermissionScope] = []
    ) {
        self.runMode = runMode
        self.localGrants = localGrants
        self.grantedScopes = grantedScopes
        self.deniedScopes = deniedScopes
    }

    static let plainChat = AgentToolRunContext(runMode: .plainChat)
}

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
    let waitID: UUID?
    let sideEffectID: UUID?

    init(
        status: AgentToolExecutionStatus,
        toolName: String,
        summary: AgentRunText,
        observation: AgentRunText,
        evidenceIDs: [UUID] = [],
        waitID: UUID? = nil,
        sideEffectID: UUID? = nil
    ) {
        self.status = status
        self.toolName = toolName
        self.summary = summary
        self.observation = observation
        self.evidenceIDs = evidenceIDs
        self.waitID = waitID
        self.sideEffectID = sideEffectID
    }

    var modelObservationText: String {
        var lines = [
            "Tool result",
            "name: \(toolName)",
            "status: \(status.rawValue)",
            "summary: \(summary.text)"
        ]
        if !evidenceIDs.isEmpty {
            lines.append("evidenceIDs: \(evidenceIDs.map(\.uuidString).joined(separator: ", "))")
        }
        if let waitID {
            lines.append("waitID: \(waitID.uuidString)")
        }
        if let sideEffectID {
            lines.append("sideEffectID: \(sideEffectID.uuidString)")
        }
        lines.append("observation:")
        lines.append(observation.text)
        return lines.joined(separator: "\n")
    }
}

actor AgentLocalToolExecutor {
    private let store: AgentRunStore
    private let policy: AgentPermissionPolicy
    private let evidenceRecorder: AgentEvidenceRecorder
    private let sideEffects: AgentSideEffectController
    private let pathResolver: AgentLocalPathResolver
    private let maxFolderEntries = 200
    private let maxSearchFiles = 800
    private let maxSearchMatches = 20
    private let maxReadBytes = 700_000
    private let maxReadCharacters = 24_000
    private let snippetRadius = 360

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
        let decision = policy.decision(
            for: AgentPermissionRequest(
                runMode: context.runMode,
                providerTier: providerTier,
                toolName: call.name,
                arguments: call.arguments,
                localGrants: context.localGrants,
                grantedScopes: context.grantedScopes,
                deniedScopes: context.deniedScopes
            )
        )

        switch decision.kind {
        case .deny:
            return failedResult(call.name, "Denied by policy: \(decision.summary.text)")
        case .ask:
            guard call.name == "stage_write_proposal", decision.reason == .approvalRequired else {
                return failedResult(call.name, "Tool requires unavailable approval or grant: \(decision.summary.text)")
            }
            return try await stageWriteProposal(
                call: call,
                runID: runID,
                stepID: stepID,
                context: context
            )
        case .allow:
            break
        }

        switch call.name {
        case "list_grants":
            return try await listGrants(call: call, runID: runID, stepID: stepID, grants: context.localGrants)
        case "list_folder":
            return try await listFolder(call: call, runID: runID, stepID: stepID, grants: context.localGrants)
        case "search_files":
            return try await searchFiles(call: call, runID: runID, stepID: stepID, grants: context.localGrants)
        case "read_file":
            return try await readFile(call: call, runID: runID, stepID: stepID, grants: context.localGrants)
        case "stage_write_proposal":
            return try await stageWriteProposal(call: call, runID: runID, stepID: stepID, context: context)
        default:
            return failedResult(call.name, "Tool \(call.name) is registered but has no executor in this runtime.")
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
        let evidence = try await evidenceRecorder.recordSideEffect(
            runID: runID,
            stepID: stepID,
            sideEffect: completed
        )
        let didComplete = completed.status == .completed
        let errorText = completed.errorSummary?.text
        return AgentToolExecutionResult(
            status: didComplete ? .succeeded : .failed,
            toolName: "stage_write_proposal",
            summary: AgentRunText(
                didComplete
                    ? "Approved side effect executed."
                    : "Approved side effect failed: \(errorText ?? "No error summary was recorded.")"
            ),
            observation: AgentRunText("The approved \(completed.kind.rawValue) side effect completed with status \(completed.status.rawValue). Target: \(completed.metadata["targetPath"]?.stringValue ?? "unknown").\(errorText.map { " Error: \($0)" } ?? "")"),
            evidenceIDs: [evidence.evidenceID],
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
            toolName: "stage_write_proposal",
            summary: AgentRunText("User denied the side effect."),
            observation: AgentRunText("The proposed \(denied.kind.rawValue) side effect was denied and did not execute."),
            evidenceIDs: [evidence.evidenceID],
            sideEffectID: denied.sideEffectID
        )
    }

    private func listGrants(
        call: AgentKernelToolCallV2,
        runID: UUID,
        stepID: UUID?,
        grants: [AgentLocalFileGrant]
    ) async throws -> AgentToolExecutionResult {
        let body = grants.isEmpty
            ? "No local files or folders have been granted."
            : grants.map { grant in
                "- \(grant.isDirectory ? "Folder" : "File"): \(grant.path) (\(grant.access.rawValue))"
            }.joined(separator: "\n")
        let evidence = try await evidenceRecorder.record(
            AgentEvidencePacket(
                sourceID: "file-grants:\(runID.uuidString)",
                kind: .fileGrant,
                summary: AgentRunText("Listed \(grants.count) granted local location(s)."),
                body: AgentRunText(body),
                artifactMimeType: "text/plain",
                artifactFileExtension: "txt",
                privacyClass: .localFile,
                trustClass: .appControl,
                metadata: ["grantCount": .int(grants.count)]
            ),
            runID: runID,
            stepID: stepID
        )
        return AgentToolExecutionResult(
            status: .succeeded,
            toolName: call.name,
            summary: AgentRunText("Listed \(grants.count) granted location(s)."),
            observation: AgentRunText(body),
            evidenceIDs: [evidence.evidenceID]
        )
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
                "- \(entry.isDirectory ? "Folder" : "File"): \(entry.path)"
            }.joined(separator: "\n")
        return AgentToolExecutionResult(
            status: .succeeded,
            toolName: call.name,
            summary: AgentRunText("Listed \(entries.count) item(s)."),
            observation: AgentRunText(body),
            evidenceIDs: [evidence.evidenceID]
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
        let terms = searchTerms(from: query)
        guard !terms.isEmpty else {
            return failedResult(call.name, "Search query has no searchable terms.")
        }

        var matches: [AgentFileSearchMatch] = []
        var visited = 0
        for url in readableFileURLs(grants: grants) {
            guard visited < maxSearchFiles else { break }
            visited += 1
            let pathScore = score(text: url.lastPathComponent, terms: terms) * 3
            guard let content = readText(url, maxCharacters: maxReadCharacters) else { continue }
            let contentScore = score(text: content.text, terms: terms)
            let totalScore = pathScore + contentScore
            guard totalScore > 0 else { continue }
            matches.append(
                AgentFileSearchMatch(
                    path: url.path,
                    preview: AgentRunText(snippet(from: content.text, terms: terms)),
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
            isTruncated: sorted.count > limited.count || visited >= maxSearchFiles
        )
        let body = limited.isEmpty
            ? "No matching files found."
            : limited.map { "- \($0.path)\n  \($0.preview.text)" }.joined(separator: "\n")
        return AgentToolExecutionResult(
            status: .succeeded,
            toolName: call.name,
            summary: AgentRunText("Found \(limited.count) matching file(s)."),
            observation: AgentRunText(body),
            evidenceIDs: [evidence.evidenceID]
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
        return AgentToolExecutionResult(
            status: .succeeded,
            toolName: call.name,
            summary: AgentRunText("Read \(fileURL.path)."),
            observation: AgentRunText("Path: \(fileURL.path)\nContent:\n\(content.text)", characterLimit: maxReadCharacters + 512),
            evidenceIDs: [evidence.evidenceID]
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
            return failedResult(call.name, resolution.failure?.summary.text ?? "The requested write target is outside granted writable local access.")
        }
        let targetURL = resolved.url
        let content = call.arguments["content"] ?? ""
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

    private func failedResult(_ toolName: String, _ message: String) -> AgentToolExecutionResult {
        AgentToolExecutionResult(
            status: .failed,
            toolName: toolName,
            summary: AgentRunText(message),
            observation: AgentRunText(message)
        )
    }

    private func readableFileURLs(grants: [AgentLocalFileGrant]) -> [URL] {
        var urls: [URL] = []
        for grant in grants {
            if grant.isDirectory {
                guard let enumerator = FileManager.default.enumerator(
                    at: grant.url,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let url as URL in enumerator {
                    guard urls.count < maxSearchFiles else { break }
                    if shouldSkip(url) {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard isTextLikeFile(url), fileSize(url) <= maxReadBytes else { continue }
                    urls.append(url.standardizedFileURL)
                }
            } else if isTextLikeFile(grant.url), fileSize(grant.url) <= maxReadBytes {
                urls.append(grant.url.standardizedFileURL)
            }
        }
        return urls.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
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

    private func shouldSkip(_ url: URL) -> Bool {
        let skipped = Set([".git", "node_modules", "DerivedData", ".build", "build", "dist", ".next"])
        return url.pathComponents.contains { skipped.contains($0) }
    }

    private func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private func searchTerms(from query: String) -> [String] {
        let stopwords: Set<String> = [
            "about", "after", "again", "also", "could", "file", "files", "find",
            "from", "have", "inside", "into", "local", "read", "search", "show",
            "tell", "that", "the", "their", "there", "this", "what", "whats",
            "where", "which", "with", "within", "write", "folder"
        ]
        return query
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9/._ -]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && !stopwords.contains($0) }
    }

    private func score(text: String, terms: [String]) -> Int {
        let lowercased = text.lowercased()
        return terms.reduce(0) { total, term in
            total + (lowercased.contains(term) ? max(1, term.count) : 0)
        }
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
}

actor AgentToolOrchestrator {
    private let store: AgentRunStore
    private let gateway: AgentModelGateway
    private let adapterID: String
    private let executor: AgentLocalToolExecutor
    private let maxIterations: Int

    init(
        store: AgentRunStore,
        gateway: AgentModelGateway,
        adapterID: String,
        executor: AgentLocalToolExecutor? = nil,
        maxIterations: Int = 8
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
        var messages = baseRequest.messages

        for iteration in 1...maxIterations {
            try Task.checkCancellation()
            let response = try await modelResponse(
                runID: runID,
                baseRequest: baseRequest,
                messages: messages,
                iteration: iteration
            )

            if let finalAnswer = Self.finalAnswer(from: response.events) {
                try await store.appendEvent(
                    runID: runID,
                    kind: .assistantMessage,
                    payload: .text(AgentRunText(finalAnswer))
                )
                _ = try? await AgentEvidenceRecorder(store: store).recordTerminalState(
                    runID: runID,
                    status: .completed,
                    reason: AgentRunText("Final answer produced.")
                )
                try await store.updateRunStatus(
                    runID: runID,
                    status: .completed,
                    reason: AgentRunText("Final answer produced.")
                )
                return
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

            messages.append(
                AgentKernelMessageV2(
                    role: .observation,
                    content: result.modelObservationText
                )
            )
        }

        try await failRun(
            runID: runID,
            reason: AgentRunText(AgentToolOrchestratorError.maxIterationsExceeded(maxIterations).description),
            status: .blocked
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
        messages.append(AgentKernelMessageV2(role: .observation, content: result.modelObservationText))
        let resumedRequest = AgentModelGatewayRequest(
            mode: baseRequest.mode,
            messages: messages,
            tools: baseRequest.tools,
            attachments: baseRequest.attachments,
            requestedMaxOutputTokens: baseRequest.requestedMaxOutputTokens,
            timeout: baseRequest.timeout,
            metadata: baseRequest.metadata
        )

        if approved {
            guard result.status == .succeeded else {
                try await store.appendEvent(
                    runID: runID,
                    kind: .assistantMessage,
                    payload: .text(result.summary)
                )
                try await store.updateRunStatus(
                    runID: runID,
                    status: .failed,
                    reason: result.summary
                )
                return
            }
            try await run(runID: runID, request: resumedRequest, context: context)
        } else {
            try await store.appendEvent(
                runID: runID,
                kind: .assistantMessage,
                payload: .text(AgentRunText("Canceled. I did not make the proposed file change."))
            )
            try await store.updateRunStatus(
                runID: runID,
                status: .blocked,
                reason: AgentRunText("User denied the side effect.")
            )
        }
    }

    private func modelResponse(
        runID: UUID,
        baseRequest: AgentModelGatewayRequest,
        messages: [AgentKernelMessageV2],
        iteration: Int
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
            let result = await gateway.response(adapterID: adapterID, request: request)
            switch result {
            case .success(let response):
                _ = try await store.finishStep(stepID: step.stepID, status: .completed)
                return response
            case .failure(let failure):
                _ = try await store.finishStep(stepID: step.stepID, status: .failed)
                try await failRun(runID: runID, reason: failure.message)
                throw failure
            }
        } catch {
            _ = try? await store.finishStep(stepID: step.stepID, status: .failed)
            throw error
        }
    }

    private func executeToolCall(
        _ call: AgentKernelToolCallV2,
        runID: UUID,
        providerTier: AgentModelCapabilityTier,
        context: AgentToolRunContext,
        iteration: Int
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
        _ = try? await AgentEvidenceRecorder(store: store).recordTerminalState(
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

private extension AgentRunMetadataValue {
    nonisolated var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}
