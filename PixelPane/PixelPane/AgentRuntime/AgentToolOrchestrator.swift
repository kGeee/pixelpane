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

nonisolated struct AgentTaskFrame: Codable, Equatable, Sendable {
    nonisolated enum StructuralSource: String, Codable, Equatable, Sendable {
        case appContext
        case selectedAction
        case providerCapability
        case permissionContext
        case explicitAbsolutePath
        case explicitRelativePath
        case exactGrantReference
        case explicitWriteTarget
        case explicitCommandSyntax
        case quotedSearchTerm
        case attachment
        case durableWait
        case durableSideEffect
        case deterministicController
        case temporalExpression
    }

    nonisolated struct LocalReference: Codable, Equatable, Sendable {
        let path: String
        let isDirectory: Bool?
        let access: AgentLocalFileGrantAccess?
        let source: StructuralSource
        let exists: Bool?
        let grantPath: String?
    }

    nonisolated struct WriteRequest: Codable, Equatable, Sendable {
        let operation: AgentFileWriteOperation
        let targetPath: String
        let preferredDirectoryPath: String?
        let source: StructuralSource
    }

    nonisolated struct ExplicitCommandDraft: Codable, Equatable, Sendable {
        let command: String
        let workingDirectory: String?
        let source: StructuralSource

        init(
            command: String,
            workingDirectory: String?,
            source: StructuralSource = .explicitCommandSyntax
        ) {
            self.command = command
            self.workingDirectory = workingDirectory
            self.source = source
        }
    }

    nonisolated struct VisualContextSnapshot: Codable, Equatable, Sendable {
        let attachmentIDs: [UUID]
        let labels: [String]
        let sources: [String]
        let hasImageInput: Bool
        let hasOCRText: Bool
    }

    nonisolated struct PendingWaitSnapshot: Codable, Equatable, Sendable {
        let waitID: UUID
        let kind: AgentRunWaitKind
        let status: AgentRunWaitStatus
        let risk: String?
        let source: StructuralSource
    }

    nonisolated struct SideEffectSnapshot: Codable, Equatable, Sendable {
        let sideEffectID: UUID
        let kind: AgentRunSideEffectKind
        let status: AgentRunSideEffectStatus
        let targetPath: String?
        let command: String?
        let source: StructuralSource
    }

    nonisolated struct EvidenceRequest: Codable, Equatable, Sendable {
        nonisolated enum Kind: String, Codable, Equatable, Sendable {
            case writeProposal
            case commandEvidence
            case processSnapshot
            case visualContext
            case temporalContext
            case exactSearch
        }

        let kind: Kind
        let source: StructuralSource
        let requiredToolName: String?
        let targetPath: String?
        let query: String?
    }

    let userMessage: String
    let selectedAction: String?
    let contextID: String?
    let contextKind: String?
    let runMode: AgentRunPermissionMode
    let providerTier: AgentModelCapabilityTier?
    let availableToolNames: [String]
    let supportedOperations: [AgentToolOperationKind]
    let grantedScopes: [AgentPermissionScope]
    let deniedScopes: [AgentPermissionScope]
    let localGrants: [AgentLocalFileGrant]
    let localReferences: [LocalReference]
    let writeRequest: WriteRequest?
    let explicitCommandDraft: ExplicitCommandDraft?
    let processSnapshotCommand: ExplicitCommandDraft?
    let quotedSearchTerms: [String]
    let temporalDayOffset: Int?
    let visualContext: VisualContextSnapshot?
    let pendingWaits: [PendingWaitSnapshot]
    let completedSideEffects: [SideEffectSnapshot]
    let evidenceRequests: [EvidenceRequest]
    let diagnostics: [String]

    var writeTargetPath: String? {
        writeRequest?.targetPath
    }

    var hasVisualAttachment: Bool {
        visualContext != nil
    }

    var requiresWriteProposal: Bool {
        evidenceRequests.contains { $0.kind == .writeProposal }
            && availableToolNames.contains("stage_write_proposal")
    }

    var requiresCommandEvidence: Bool {
        evidenceRequests.contains { $0.kind == .commandEvidence }
            && availableToolNames.contains("run_finite_command")
    }

    var requiresProcessSnapshotEvidence: Bool {
        evidenceRequests.contains { $0.kind == .processSnapshot }
            && availableToolNames.contains("run_finite_command")
    }

    var requiredSideEffectToolNames: [String] {
        var required: [String] = []
        if requiresWriteProposal {
            required.append("stage_write_proposal")
        }
        if requiresCommandEvidence {
            required.append("run_finite_command")
        }
        return required
    }

    var exactSearchQueries: [String] {
        evidenceRequests.compactMap { request in
            request.kind == .exactSearch ? request.query : nil
        }
    }

    var hasStructuralLocalReference: Bool {
        localReferences.contains { $0.source != .explicitWriteTarget }
    }

    var hasVisualEvidenceRequest: Bool {
        evidenceRequests.contains { $0.kind == .visualContext }
    }

    static func build(
        userMessage: String,
        tools: [AgentKernelToolSchemaV2],
        context: AgentToolRunContext,
        providerTier: AgentModelCapabilityTier? = nil,
        attachments: [AgentKernelModelAttachmentV2] = [],
        selectedAction: String? = nil,
        contextID: String? = nil,
        contextKind: String? = nil,
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations,
        pendingWaits: [AgentRunWaitRecord] = [],
        completedSideEffects: [AgentRunSideEffectRecord] = []
    ) -> AgentTaskFrame {
        let toolNames = tools.map(\.name).sorted()
        let operations = supportedOperations.sorted { $0.rawValue < $1.rawValue }
        let grantedScopes = context.grantedScopes.sorted { $0.rawValue < $1.rawValue }
        let deniedScopes = context.deniedScopes.sorted { $0.rawValue < $1.rawValue }
        let writeRequest = explicitWriteRequest(from: userMessage, grants: context.localGrants)
        let commandDraft = explicitCommandDraft(from: userMessage)
        let processSnapshotCommand = processSnapshotCommand(from: userMessage)
        let quotedTerms = quotedTerms(in: userMessage)
        let temporalDayOffset = temporalDayOffset(from: userMessage)
        let visualContext = visualContext(from: attachments)
        let localReferences = localReferences(
            from: userMessage,
            grants: context.localGrants,
            writeRequest: writeRequest
        )
        let pendingWaitSnapshots = pendingWaits.map {
            PendingWaitSnapshot(
                waitID: $0.waitID,
                kind: $0.kind,
                status: $0.status,
                risk: $0.risk,
                source: .durableWait
            )
        }
        let completedSideEffectSnapshots = completedSideEffects
            .filter { $0.status == .completed }
            .map {
                SideEffectSnapshot(
                    sideEffectID: $0.sideEffectID,
                    kind: $0.kind,
                    status: $0.status,
                    targetPath: $0.metadata["targetPath"]?.stringValue,
                    command: $0.metadata["command"]?.stringValue,
                    source: .durableSideEffect
                )
            }
        let evidenceRequests = evidenceRequests(
            availableToolNames: toolNames,
            writeRequest: writeRequest,
            commandDraft: commandDraft,
            processSnapshotCommand: processSnapshotCommand,
            quotedSearchTerms: quotedTerms,
            visualContext: visualContext,
            temporalDayOffset: temporalDayOffset
        )
        return AgentTaskFrame(
            userMessage: userMessage,
            selectedAction: selectedAction,
            contextID: contextID,
            contextKind: contextKind,
            runMode: context.runMode,
            providerTier: providerTier,
            availableToolNames: toolNames,
            supportedOperations: operations,
            grantedScopes: grantedScopes,
            deniedScopes: deniedScopes,
            localGrants: context.localGrants,
            localReferences: localReferences,
            writeRequest: writeRequest,
            explicitCommandDraft: commandDraft,
            processSnapshotCommand: processSnapshotCommand,
            quotedSearchTerms: quotedTerms,
            temporalDayOffset: temporalDayOffset,
            visualContext: visualContext,
            pendingWaits: pendingWaitSnapshots,
            completedSideEffects: completedSideEffectSnapshots,
            evidenceRequests: evidenceRequests,
            diagnostics: diagnostics(
                selectedAction: selectedAction,
                contextKind: contextKind,
                runMode: context.runMode,
                providerTier: providerTier,
                availableToolNames: toolNames,
                supportedOperations: operations,
                grantedScopes: grantedScopes,
                deniedScopes: deniedScopes,
                localGrantCount: context.localGrants.count,
                localReferenceCount: localReferences.count,
                writeRequest: writeRequest,
                commandDraft: commandDraft,
                processSnapshotCommand: processSnapshotCommand,
                quotedSearchTermCount: quotedTerms.count,
                temporalDayOffset: temporalDayOffset,
                visualContext: visualContext,
                pendingWaitCount: pendingWaitSnapshots.count,
                completedSideEffectCount: completedSideEffectSnapshots.count,
                evidenceRequestCount: evidenceRequests.count,
                toolVisibilityDiagnostics: providerTier.map { tier in
                    AgentToolCatalog().visibilityDiagnostics(
                        providerTier: tier,
                        runMode: context.runMode,
                        localGrants: context.localGrants,
                        grantedScopes: context.grantedScopes,
                        deniedScopes: context.deniedScopes,
                        supportedOperations: supportedOperations
                    )
                } ?? []
            )
        )
    }

    private static func explicitWriteRequest(from text: String, grants: [AgentLocalFileGrant]) -> WriteRequest? {
        guard let operationValue = structuralField("operation", in: text),
              let operation = AgentFileWriteOperation(rawValue: operationValue.lowercased()),
              let targetPath = structuralField("targetPath", in: text)?.trimmingCharacters(in: pathTrailingPunctuation),
              !targetPath.isEmpty else {
            return nil
        }
        let preferredDirectoryPath = structuralField("preferredDirectoryPath", in: text)
            .map(expandedHomePath)
        return WriteRequest(
            operation: operation,
            targetPath: targetPath,
            preferredDirectoryPath: preferredWritableDirectory(
                explicitPath: preferredDirectoryPath,
                grants: grants
            ),
            source: .explicitWriteTarget
        )
    }

    private static func structuralField(_ name: String, in text: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?im)^\s*\#(escapedName)\s*[:=]\s*(.+?)\s*$"#
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let value = String(text[valueRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        return value.isEmpty ? nil : value
    }

    private static func preferredWritableDirectory(
        explicitPath: String?,
        grants: [AgentLocalFileGrant]
    ) -> String? {
        if let explicitPath {
            let standardized = URL(fileURLWithPath: explicitPath).standardizedFileURL.path
            if grants.contains(where: { $0.isDirectory && $0.access == .readWrite && $0.allowsWrite(standardized) }) {
                return standardized
            }
        }
        return nil
    }

    private static func explicitCommandDraft(from text: String) -> ExplicitCommandDraft? {
        let allowed = supportedCommandNames.sorted().joined(separator: "|")
        let patterns = [
            #"`\s*((?:\#(allowed))\b[^`]*)`"#,
            #"(?m)(?:^|\n)\s*((?:\#(allowed))\b[^\n]*)$"#,
            #"\bcommand\s*:\s*((?:\#(allowed))\b[^\n.]*)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let commandRange = Range(match.range(at: 1), in: text) else { continue }
            let command = String(text[commandRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !command.isEmpty else { continue }
            return ExplicitCommandDraft(command: command, workingDirectory: explicitWorkingDirectory(in: text))
        }
        return nil
    }

    private static func processSnapshotCommand(from text: String) -> ExplicitCommandDraft? {
        let lowercased = text.lowercased()
        let processRequestPatterns = [
            #"\b(?:top|highest|running|active)\b.{0,48}\bprocess(?:es)?\b"#,
            #"\bprocess(?:es)?\b.{0,48}\b(?:top|highest|running|active)\b"#
        ]
        let isProcessSnapshotRequest = processRequestPatterns.contains { pattern in
            lowercased.range(of: pattern, options: .regularExpression) != nil
        }
        guard isProcessSnapshotRequest else {
            return nil
        }
        return ExplicitCommandDraft(
            command: "ps -axo pid,pcpu,pmem,comm -r",
            workingDirectory: nil,
            source: .deterministicController
        )
    }

    private static func explicitWorkingDirectory(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\bin\s+((?:~)?/[^\s"'`]+)"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange]).trimmingCharacters(in: Self.pathTrailingPunctuation)
    }

    static func quotedTerms(in text: String) -> [String] {
        let patterns = [
            #""([^"]{2,120})""#,
            #"'([^']{2,120})'"#,
            #"`([^`]{2,120})`"#
        ]
        var values: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
                let value = String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if value.count >= 2 {
                    values.append(value)
                }
            }
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func temporalDayOffset(from text: String) -> Int? {
        let patterns = [
            #"(?i)\b(\d{1,4})\s+days?\s+(?:from|after)\s+today\b"#,
            #"(?i)\b(\d{1,4})\s+days?\s+before\s+today\b"#
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let valueRange = Range(match.range(at: 1), in: text),
                  let days = Int(text[valueRange]) else { continue }
            return index == 0 ? days : -days
        }
        guard containsRelativeDayToken(text) else {
            return nil
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let date = detector.matches(in: text, range: range)
            .compactMap(\.date)
            .first else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: target).day
    }

    private static func containsRelativeDayToken(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(today(?:'s)?|tomorrow|yesterday)\b"#
        ) else {
            return false
        }
        return regex.firstMatch(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        ) != nil
    }

    private static func visualContext(from attachments: [AgentKernelModelAttachmentV2]) -> VisualContextSnapshot? {
        let visualAttachments = attachments.filter { attachment in
            attachment.modality == .image
                || attachment.metadata["ocrText"] != nil
                || attachment.metadata["hasImageInput"]?.boolValue == true
                || attachment.metadata["hasOCRText"]?.boolValue == true
        }
        guard !visualAttachments.isEmpty else { return nil }
        var seenSources = Set<String>()
        let sources = visualAttachments
            .compactMap { $0.metadata["source"]?.stringValue }
            .filter { seenSources.insert($0).inserted }
        return VisualContextSnapshot(
            attachmentIDs: visualAttachments.map(\.id),
            labels: visualAttachments.map(\.label),
            sources: sources,
            hasImageInput: visualAttachments.contains {
                $0.modality == .image || $0.metadata["hasImageInput"]?.boolValue == true
            },
            hasOCRText: visualAttachments.contains {
                let ocrText = $0.metadata["ocrText"]?.stringValue ?? ""
                return !ocrText.isEmpty || $0.metadata["hasOCRText"]?.boolValue == true
            }
        )
    }

    private static func localReferences(
        from text: String,
        grants: [AgentLocalFileGrant],
        writeRequest: WriteRequest?
    ) -> [LocalReference] {
        var references: [LocalReference] = []
        for path in absolutePathCandidates(in: text) {
            references.append(localReference(for: path, grants: grants, source: .explicitAbsolutePath))
        }
        for rawPath in relativePathCandidates(in: text) {
            let matches = grants
                .filter(\.isDirectory)
                .compactMap { grant -> LocalReference? in
                    let candidate = grant.url.appendingPathComponent(rawPath).standardizedFileURL.path
                    guard grant.allowsRead(candidate) else { return nil }
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory) else {
                        return nil
                    }
                    return LocalReference(
                        path: candidate,
                        isDirectory: isDirectory.boolValue,
                        access: grant.access,
                        source: .explicitRelativePath,
                        exists: true,
                        grantPath: grant.path
                    )
                }
            if matches.count == 1 {
                references.append(contentsOf: matches)
            }
        }
        let quoted = Set(quotedTerms(in: text).map { $0.lowercased() })
        for grant in grants {
            let displayName = grant.url.lastPathComponent.lowercased()
            if quoted.contains(grant.path.lowercased())
                || (!displayName.isEmpty && quoted.contains(displayName)) {
                references.append(
                    LocalReference(
                        path: grant.path,
                        isDirectory: grant.isDirectory,
                        access: grant.access,
                        source: .exactGrantReference,
                        exists: true,
                        grantPath: grant.path
                    )
                )
            }
        }
        if let writeRequest {
            references.append(writeTargetReference(writeRequest, grants: grants))
        }
        return uniqueReferences(references)
    }

    private static func localReference(
        for rawPath: String,
        grants: [AgentLocalFileGrant],
        source: StructuralSource
    ) -> LocalReference {
        let standardized = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        let grant = grants.first { $0.allowsRead(standardized) || $0.allowsWrite(standardized) }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory)
        return LocalReference(
            path: standardized,
            isDirectory: exists ? isDirectory.boolValue : nil,
            access: grant?.access,
            source: source,
            exists: exists,
            grantPath: grant?.path
        )
    }

    private static func writeTargetReference(_ writeRequest: WriteRequest, grants: [AgentLocalFileGrant]) -> LocalReference {
        if writeRequest.targetPath.hasPrefix("/") || writeRequest.targetPath.hasPrefix("~/") {
            return localReference(for: expandedHomePath(writeRequest.targetPath), grants: grants, source: .explicitWriteTarget)
        }
        let preferredGrant = writeRequest.preferredDirectoryPath.flatMap { preferred in
            grants.first { $0.path == preferred }
        }
        let grant = preferredGrant ?? grants.first { $0.isDirectory && $0.access == .readWrite }
        let candidate = grant?.url.appendingPathComponent(writeRequest.targetPath).standardizedFileURL.path ?? writeRequest.targetPath
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory)
        return LocalReference(
            path: candidate,
            isDirectory: exists ? isDirectory.boolValue : nil,
            access: grant?.access,
            source: .explicitWriteTarget,
            exists: exists,
            grantPath: grant?.path
        )
    }

    private static func evidenceRequests(
        availableToolNames: [String],
        writeRequest: WriteRequest?,
        commandDraft: ExplicitCommandDraft?,
        processSnapshotCommand: ExplicitCommandDraft?,
        quotedSearchTerms: [String],
        visualContext: VisualContextSnapshot?,
        temporalDayOffset: Int?
    ) -> [EvidenceRequest] {
        var requests: [EvidenceRequest] = []
        if let writeRequest, availableToolNames.contains("stage_write_proposal") {
            requests.append(
                EvidenceRequest(
                    kind: .writeProposal,
                    source: writeRequest.source,
                    requiredToolName: "stage_write_proposal",
                    targetPath: writeRequest.targetPath,
                    query: nil
                )
            )
        }
        if let commandDraft, availableToolNames.contains("run_finite_command") {
            requests.append(
                EvidenceRequest(
                    kind: .commandEvidence,
                    source: commandDraft.source,
                    requiredToolName: "run_finite_command",
                    targetPath: nil,
                    query: commandDraft.command
                )
            )
        }
        if let processSnapshotCommand,
           commandDraft == nil,
           availableToolNames.contains("run_finite_command") {
            requests.append(
                EvidenceRequest(
                    kind: .processSnapshot,
                    source: processSnapshotCommand.source,
                    requiredToolName: "run_finite_command",
                    targetPath: nil,
                    query: processSnapshotCommand.command
                )
            )
        }
        if let visualContext {
            requests.append(
                EvidenceRequest(
                    kind: .visualContext,
                    source: .attachment,
                    requiredToolName: availableToolNames.contains("describe_visual_context") ? "describe_visual_context" : nil,
                    targetPath: nil,
                    query: visualContext.labels.first
                )
            )
        }
        if let temporalDayOffset {
            requests.append(
                EvidenceRequest(
                    kind: .temporalContext,
                    source: .temporalExpression,
                    requiredToolName: nil,
                    targetPath: nil,
                    query: String(temporalDayOffset)
                )
            )
        }
        if availableToolNames.contains("search_files") {
            for term in quotedSearchTerms {
                requests.append(
                    EvidenceRequest(
                        kind: .exactSearch,
                        source: .quotedSearchTerm,
                        requiredToolName: "search_files",
                        targetPath: nil,
                        query: term
                    )
                )
            }
        }
        return requests
    }

    private static func diagnostics(
        selectedAction: String?,
        contextKind: String?,
        runMode: AgentRunPermissionMode,
        providerTier: AgentModelCapabilityTier?,
        availableToolNames: [String],
        supportedOperations: [AgentToolOperationKind],
        grantedScopes: [AgentPermissionScope],
        deniedScopes: [AgentPermissionScope],
        localGrantCount: Int,
        localReferenceCount: Int,
        writeRequest: WriteRequest?,
        commandDraft: ExplicitCommandDraft?,
        processSnapshotCommand: ExplicitCommandDraft?,
        quotedSearchTermCount: Int,
        temporalDayOffset: Int?,
        visualContext: VisualContextSnapshot?,
        pendingWaitCount: Int,
        completedSideEffectCount: Int,
        evidenceRequestCount: Int,
        toolVisibilityDiagnostics: [String]
    ) -> [String] {
        var lines: [String] = [
            "runMode=\(runMode.rawValue)",
            "tools=\(availableToolNames.count)",
            "supportedOperations=\(supportedOperations.count)",
            "grantedScopes=\(grantedScopes.map(\.rawValue).joined(separator: ","))",
            "deniedScopes=\(deniedScopes.map(\.rawValue).joined(separator: ","))",
            "localGrants=\(localGrantCount)",
            "localReferences=\(localReferenceCount)",
            "evidenceRequests=\(evidenceRequestCount)"
        ]
        if let selectedAction {
            lines.append("selectedAction=\(selectedAction)")
        }
        if let contextKind {
            lines.append("contextKind=\(contextKind)")
        }
        if let providerTier {
            lines.append("providerTier=\(providerTier.rawValue)")
        }
        if let writeRequest {
            lines.append("writeRequest=\(writeRequest.operation.rawValue):\(writeRequest.source.rawValue)")
        }
        if let commandDraft {
            lines.append("commandDraft=\(commandDraft.source.rawValue)")
        }
        if let processSnapshotCommand {
            lines.append("processSnapshot=\(processSnapshotCommand.source.rawValue)")
        }
        if quotedSearchTermCount > 0 {
            lines.append("quotedSearchTerms=\(quotedSearchTermCount)")
        }
        if let temporalDayOffset {
            lines.append("temporalDayOffset=\(temporalDayOffset)")
        }
        if let visualContext {
            lines.append("visualContext=image:\(visualContext.hasImageInput),ocr:\(visualContext.hasOCRText)")
        }
        if pendingWaitCount > 0 {
            lines.append("pendingWaits=\(pendingWaitCount)")
        }
        if completedSideEffectCount > 0 {
            lines.append("completedSideEffects=\(completedSideEffectCount)")
        }
        lines.append(contentsOf: toolVisibilityDiagnostics)
        return lines
    }

    private static func absolutePathCandidates(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?:~)?/[^\s"'`]+"#) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range, in: text) else { return nil }
            return expandedHomePath(
                String(text[valueRange]).trimmingCharacters(in: Self.pathTrailingPunctuation)
            )
        }
    }

    private static func relativePathCandidates(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b[\w.-]+(?:/[\w.-]+)*\.(?:txt|md|markdown|json|csv|tsv|html|htm|log|swift|py|js|ts|tsx|jsx|css|sh|zsh|bash)\b"#,
            options: [.caseInsensitive]
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range, in: text) else { return nil }
            return String(text[valueRange]).trimmingCharacters(in: Self.pathTrailingPunctuation)
        }
    }

    private static func expandedHomePath(_ rawPath: String) -> String {
        if rawPath == "~" {
            return NSHomeDirectory()
        }
        if rawPath.hasPrefix("~/") {
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(String(rawPath.dropFirst(2)))
                .standardizedFileURL
                .path
        }
        return rawPath
    }

    private static func uniqueReferences(_ references: [LocalReference]) -> [LocalReference] {
        var seen = Set<String>()
        return references.filter { seen.insert("\($0.path):\($0.source.rawValue)").inserted }
    }

    private static let supportedCommandNames: Set<String> = [
        "date", "git", "grep", "head", "lsof", "netstat", "pgrep", "ps", "rg", "tail", "top", "wc"
    ]

    private static let pathTrailingPunctuation = CharacterSet(charactersIn: ".,;:?!)]}")
}

nonisolated enum AgentRunTaskClass: String, Codable, Equatable, Sendable {
    case plainChat
    case temporalQuery
    case grantQuestion
    case sessionMemoryQuestion
    case localListing
    case localSearch
    case localFileRead
    case fileSelection
    case writeProposal
    case commandObservation
    case commandPlusWrite
    case visualContext

    var usesLocalEvidencePlanner: Bool {
        switch self {
        case .grantQuestion, .localListing, .localSearch, .localFileRead, .fileSelection, .writeProposal:
            true
        case .plainChat, .temporalQuery, .sessionMemoryQuestion, .commandObservation, .commandPlusWrite, .visualContext:
            false
        }
    }

    var isLocalStateRequest: Bool {
        switch self {
        case .grantQuestion, .localListing, .localSearch, .localFileRead, .fileSelection, .commandObservation, .commandPlusWrite, .visualContext:
            true
        case .plainChat, .temporalQuery, .sessionMemoryQuestion, .writeProposal:
            false
        }
    }

    var requiresTemporalContext: Bool {
        self == .temporalQuery
    }
}

nonisolated struct AgentRunTaskClassifier: Sendable {
    static func classify(
        userMessage: String,
        tools: [AgentKernelToolSchemaV2],
        context: AgentToolRunContext,
        taskFrame: AgentTaskFrame? = nil
    ) -> AgentRunTaskClass {
        let taskFrame = taskFrame ?? AgentTaskFrame.build(
            userMessage: userMessage,
            tools: tools,
            context: context
        )

        if taskFrame.temporalDayOffset != nil {
            return .temporalQuery
        }
        if taskFrame.hasVisualAttachment {
            return .visualContext
        }

        let write = taskFrame.requiresWriteProposal
        let command = taskFrame.requiresCommandEvidence
        if write && command {
            return .commandPlusWrite
        }
        if command {
            return .commandObservation
        }
        if taskFrame.requiresProcessSnapshotEvidence {
            return .commandObservation
        }
        if write {
            return .writeProposal
        }
        if !taskFrame.exactSearchQueries.isEmpty {
            return .localSearch
        }
        if taskFrame.hasStructuralLocalReference {
            return taskFrame.localReferences.contains(where: { $0.isDirectory == false && $0.source != .explicitWriteTarget })
                ? .localFileRead
                : .localListing
        }

        return .plainChat
    }

    static func writeTargetPath(from userMessage: String) -> String? {
        AgentTaskFrame.build(
            userMessage: userMessage,
            tools: [AgentKernelToolSchemaV2(name: "stage_write_proposal", summary: "", arguments: [])],
            context: .plainChat
        ).writeTargetPath
    }
}

nonisolated struct AgentTemporalContext: Codable, Equatable, Sendable {
    let currentDate: String
    let localTime: String
    let timeZoneIdentifier: String
    let utcOffset: String
    let weekday: String
    let source: String

    init(date: Date = Date(), timeZone: TimeZone = .current) {
        let calendar = Calendar(identifier: .gregorian)
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        currentDate = dateFormatter.string(from: date)

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm:ss"
        localTime = timeFormatter.string(from: date)

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.timeZone = timeZone
        weekdayFormatter.dateFormat = "EEEE"
        weekday = weekdayFormatter.string(from: date)

        timeZoneIdentifier = timeZone.identifier
        utcOffset = Self.utcOffsetString(seconds: timeZone.secondsFromGMT(for: date))
        source = "app-runtime"
    }

    var modelObservation: String {
        """
        App-owned temporal context
        source: \(source)
        currentDate: \(currentDate)
        localTime: \(localTime)
        weekday: \(weekday)
        timeZone: \(timeZoneIdentifier)
        utcOffset: \(utcOffset)
        Use this context for current date, current time, today, tomorrow, and yesterday. Do not use model pretraining for current temporal facts.
        """
    }

    private static func utcOffsetString(seconds: Int) -> String {
        let sign = seconds >= 0 ? "+" : "-"
        let absSeconds = abs(seconds)
        let hours = absSeconds / 3_600
        let minutes = (absSeconds % 3_600) / 60
        return String(format: "%@%02d:%02d", sign, hours, minutes)
    }
}

nonisolated struct AgentRunTaskProfile: Codable, Equatable, Sendable {
    let userMessage: String
    let taskFrame: AgentTaskFrame
    let taskClass: AgentRunTaskClass
    let hasToolPath: Bool
    let isLocalStateRequest: Bool
    let isSideEffectRequest: Bool
    let isEditRequest: Bool
    let requiredSideEffectToolNames: [String]

    var requiresEvidenceBeforeFinalAnswer: Bool {
        (hasToolPath && isLocalStateRequest && !isSideEffectRequest) || taskClass.requiresTemporalContext
    }

    var requiresSideEffectEvidenceBeforeCompletion: Bool {
        hasToolPath && isSideEffectRequest
    }

    var shouldRunEditPreflight: Bool {
        hasToolPath && isEditRequest
    }

    var requiresTemporalContext: Bool {
        taskClass.requiresTemporalContext
    }

    static func classify(
        userMessage: String,
        tools: [AgentKernelToolSchemaV2],
        context: AgentToolRunContext,
        providerTier: AgentModelCapabilityTier? = nil,
        attachments: [AgentKernelModelAttachmentV2] = [],
        selectedAction: String? = nil,
        contextID: String? = nil,
        contextKind: String? = nil,
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations,
        pendingWaits: [AgentRunWaitRecord] = [],
        completedSideEffects: [AgentRunSideEffectRecord] = []
    ) -> AgentRunTaskProfile {
        let hasToolPath = context.runMode != .plainChat
            && (!tools.isEmpty || !context.localGrants.isEmpty)
        let taskFrame = AgentTaskFrame.build(
            userMessage: userMessage,
            tools: tools,
            context: context,
            providerTier: providerTier,
            attachments: attachments,
            selectedAction: selectedAction,
            contextID: contextID,
            contextKind: contextKind,
            supportedOperations: supportedOperations,
            pendingWaits: pendingWaits,
            completedSideEffects: completedSideEffects
        )
        let taskClass = AgentRunTaskClassifier.classify(
            userMessage: userMessage,
            tools: tools,
            context: context,
            taskFrame: taskFrame
        )
        let localEvidencePlan = AgentLocalEvidencePlanner().plan(
            messages: [AgentKernelMessageV2(role: .user, content: userMessage)],
            tools: tools,
            context: context,
            taskFrame: taskFrame
        )
        let intent = AgentRunOperationIntent.classify(
            userMessage: userMessage,
            tools: tools,
            taskFrame: taskFrame
        )
        let localState = !localEvidencePlan.requirements.isEmpty
            || intent.requiresCommandEvidence
            || taskFrame.requiresProcessSnapshotEvidence
            || taskFrame.hasVisualEvidenceRequest
        let sideEffectToolNames = intent.requiredSideEffectToolNames
        let sideEffect = !sideEffectToolNames.isEmpty
        let edit = sideEffectToolNames.contains("stage_write_proposal")
        return AgentRunTaskProfile(
            userMessage: userMessage,
            taskFrame: taskFrame,
            taskClass: taskClass,
            hasToolPath: hasToolPath,
            isLocalStateRequest: localState,
            isSideEffectRequest: sideEffect,
            isEditRequest: edit,
            requiredSideEffectToolNames: sideEffectToolNames
        )
    }

    static func latestUserMessage(from messages: [AgentKernelMessageV2]) -> String {
        messages.reversed().first { $0.role == .user }?.content ?? ""
    }
}

nonisolated struct AgentRunOperationIntent: Equatable, Sendable {
    let requiredSideEffectToolNames: [String]
    let requiresCommandEvidence: Bool

    static func classify(
        userMessage: String,
        tools: [AgentKernelToolSchemaV2],
        taskFrame: AgentTaskFrame? = nil
    ) -> AgentRunOperationIntent {
        let frame = taskFrame ?? AgentTaskFrame.build(
            userMessage: userMessage,
            tools: tools,
            context: .plainChat
        )
        let required = frame.requiredSideEffectToolNames
        let commandEvidence = frame.requiresCommandEvidence

        return AgentRunOperationIntent(
            requiredSideEffectToolNames: unique(required),
            requiresCommandEvidence: commandEvidence
        )
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
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
                deniedScopes: context.deniedScopes,
                supportedOperations: context.supportedOperations
            )
        )

        switch decision.kind {
        case .deny:
            return failedResult(call.name, "Denied by policy: \(decision.summary.text)")
        case .ask:
            if call.name == "stage_write_proposal", decision.reason == .approvalRequired {
                return try await stageWriteProposal(
                    call: call,
                    runID: runID,
                    stepID: stepID,
                    context: context
                )
            }
            if call.name == "run_finite_command" {
                guard Self.isCommandApprovalReason(decision.reason) else {
                    return failedResult(call.name, "Tool requires unavailable approval or grant: \(decision.summary.text)")
                }
                return try await stageCommandProposal(
                    call: call,
                    runID: runID,
                    stepID: stepID,
                    context: context,
                    approvalSummary: decision.summary
                )
            }
            return failedResult(call.name, "Tool requires unavailable approval or grant: \(decision.summary.text)")
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
        case "run_finite_command":
            return try await runAllowedFiniteCommand(call: call, runID: runID, stepID: stepID, context: context)
        default:
            return failedResult(call.name, "Tool \(call.name) is registered but has no executor in this runtime.")
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
            summary: AgentRunText("User denied the side effect."),
            observation: AgentRunText("The proposed \(denied.kind.rawValue) side effect was denied and did not execute."),
            evidenceIDs: [evidence.evidenceID],
            artifactIDs: evidence.artifactID.map { [$0] } ?? [],
            sideEffectID: denied.sideEffectID
        )
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
            observation: AgentRunText(body, characterLimit: maxObservationCharacters),
            evidenceIDs: [evidence.evidenceID],
            artifactIDs: evidence.artifactID.map { [$0] } ?? []
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
        let requestedFilenameOnly = Self.booleanArgument(call.arguments["filenameOnly"])
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
                    isDirectory: true,
                    access: .readOnly
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
            workingDirectory = inferredWorkingDirectory(for: command, context: context) ?? NSHomeDirectory()
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
        let timeout = call.arguments["timeoutSeconds"].flatMap(Int.init).map { min(max($0, 1), 120) } ?? 30
        return AgentCommandDraft(
            command: command,
            workingDirectory: workingDirectory,
            timeoutSeconds: timeout
        )
    }

    private func inferredWorkingDirectory(
        for command: String,
        context: AgentToolRunContext
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"((?:~)?/[^\s"'`]+)"#) else {
            return nil
        }
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        for match in regex.matches(in: command, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: command) else { continue }
            let rawPath = String(command[valueRange])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)])}"))
            let resolution = pathResolver.resolve(
                rawPath,
                grants: context.localGrants,
                access: .read,
                target: .existingFile
            )
            if let resolved = resolution.resolution {
                return resolved.url.deletingLastPathComponent().standardizedFileURL.path
            }
        }
        return context.localGrants.first(where: { $0.isDirectory })?.path
    }

    /// Tell the model exactly which writable roots exist and how to retarget a denied write,
    /// so an ambiguous/out-of-grant write proposal can recover into a single valid absolute
    /// path instead of looping on bare denial strings (RELY-005 / RC-5).
    private func writableTargetGuidance(grants: [AgentLocalFileGrant]) -> String {
        let writableRoots = grants
            .filter { $0.isDirectory && $0.access == .readWrite }
            .map { $0.path }
        guard !writableRoots.isEmpty else {
            return "No writable granted folders are available; ask the user to grant a writable folder before writing."
        }
        return "Writable granted folders: \(writableRoots.joined(separator: ", ")). Use a single absolute path inside exactly one of these."
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

    private nonisolated static func booleanArgument(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y":
            return true
        default:
            return false
        }
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

        if let preflight = try await preflightObservation(
            runID: runID,
            baseRequest: baseRequest,
            providerTier: tier,
            context: context,
            profile: profile,
            startedAt: startedAt
        ) {
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

            if let finalAnswer = Self.finalAnswer(from: response.events) {
                let answerDecision = await finalAnswerDecision(
                    finalAnswer,
                    runID: runID,
                    profile: profile,
                    observedToolResults: observedToolResults,
                    observedSideEffectToolResults: observedSideEffectToolResults,
                    observedRequiredSideEffectToolNames: observedRequiredSideEffectToolNames
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
                    messages.append(
                        AgentKernelMessageV2(
                            role: .observation,
                            content: """
                            Runtime rejected the previous final answer.
                            Reason: \(rejection.reason.text)
                            Use the available tools or existing evidence before producing a final answer.
                            """
                        )
                    )
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
                messages.append(AgentKernelMessageV2(role: .observation, content: stagedWrite.modelObservationText))
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
            messages.append(
                AgentKernelMessageV2(
                    role: .observation,
                    content: observationText
                )
            )
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
            iteration: iteration
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
        synthMessages.append(
            AgentKernelMessageV2(
                role: .observation,
                content: """
                Produce your best final answer now using the information already gathered above. \
                Do not call any tools. If you could not fully complete the task, briefly state what you found and what is blocking it.
                """
            )
        )
        let request = AgentModelGatewayRequest(
            mode: baseRequest.mode,
            messages: synthMessages,
            tools: [],
            attachments: baseRequest.attachments,
            requestedMaxOutputTokens: baseRequest.requestedMaxOutputTokens,
            timeout: baseRequest.timeout,
            metadata: baseRequest.metadata.merging(["bestEffortSynthesis": .bool(true)]) { current, _ in current }
        )
        let result = await gateway.response(adapterID: adapterID, request: request)
        guard case .success(let response) = result,
              let answer = Self.finalAnswer(from: response.events),
              !(isRawJSONShapedAnswer(answer) && profile.hasToolPath) else {
            return false
        }
        let decision = await finalAnswerDecision(
            answer,
            runID: runID,
            profile: profile,
            observedToolResults: observedToolResults,
            observedSideEffectToolResults: observedSideEffectToolResults,
            observedRequiredSideEffectToolNames: observedRequiredSideEffectToolNames
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
    }

    private enum FinalAnswerRejectionKind: Hashable {
        case rawControlJSON
        case staleTemporalAnswer
        case missingTemporalContext
        case missingRequiredSideEffectEvidence
        case missingLocalEvidence
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

        if profile.taskFrame.requiresProcessSnapshotEvidence,
           let processSnapshotCommand = profile.taskFrame.processSnapshotCommand,
           baseRequest.tools.contains(where: { $0.name == "run_finite_command" }),
           !existingEvidence.contains(where: { $0.kind == AgentEvidenceKind.commandOutput.rawValue }) {
            let result = try await executeToolCall(
                AgentKernelToolCallV2(
                    name: "run_finite_command",
                    arguments: [
                        "command": processSnapshotCommand.command,
                        "timeoutSeconds": "5"
                    ],
                    reason: "Collect the process snapshot recorded in the task frame."
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
        _ answer: String,
        runID: UUID,
        profile: AgentRunTaskProfile,
        observedToolResults: Int,
        observedSideEffectToolResults: Int,
        observedRequiredSideEffectToolNames: Set<String>
    ) async -> FinalAnswerDecision {
        let evidence = await store.evidenceArtifactSummary(runID: runID).evidence
        let requirements = await evidenceRequirements(from: evidence)
        let hasSubstantiveEvidence = hasSubstantiveAnswerEvidence(evidence, requirements: requirements)
        let temporalEvidence = evidence.first { $0.kind == AgentEvidenceKind.temporalContext.rawValue }

        if isRawJSONShapedAnswer(answer), profile.hasToolPath {
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
            if temporalAnswerContradictsContext(answer, temporalEvidence: temporalEvidence) {
                return .retry(
                    FinalAnswerRejection(
                        kind: .staleTemporalAnswer,
                        reason: AgentRunText("The answer appears to use stale temporal knowledge instead of app-owned current date/time context.")
                    )
                )
            }
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
            return .accept
        }

        if profile.requiresEvidenceBeforeFinalAnswer || !requirements.isEmpty {
            if hasSubstantiveEvidence {
                let answerUsesFileContent = await answerUsesRecordedFileContent(answer, evidence: evidence)
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

    private func shouldBlockAfterFinalAnswerRejection(
        _ rejection: FinalAnswerRejection,
        runID: UUID,
        profile: AgentRunTaskProfile,
        priorRejections: Int,
        observedRequiredSideEffectToolNames: Set<String>
    ) async -> Bool {
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

    private nonisolated func isRequiredSideEffectRejection(_ kind: FinalAnswerRejectionKind) -> Bool {
        switch kind {
        case .missingRequiredSideEffectEvidence:
            return true
        case .rawControlJSON, .staleTemporalAnswer, .missingTemporalContext, .missingLocalEvidence:
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
        _ finalAnswer: String,
        runID: UUID,
        profile: AgentRunTaskProfile
    ) async throws {
        if profile.hasToolPath {
            try? await recordFinalAnswerSupportIfPossible(runID: runID, answer: AgentRunText(finalAnswer))
        }
        try await store.appendEvent(
            runID: runID,
            kind: .assistantMessage,
            payload: .text(AgentRunText(finalAnswer))
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
            let result = await gateway.response(adapterID: adapterID, request: request)
            switch result {
            case .success(let response):
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
                if failure.kind == .structuredOutputInvalid,
                   let recovered = try await recoverStructuredOutputFailure(
                    runID: runID,
                    stepID: step.stepID,
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
                    let retryResult = await gateway.response(adapterID: adapterID, request: retryRequest)
                    switch retryResult {
                    case .success(let response):
                        _ = try await store.finishStep(stepID: step.stepID, status: .completed)
                        return response
                    case .failure(let retryFailure):
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

    private func recoverStructuredOutputFailure(
        runID: UUID,
        stepID: UUID,
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
        retryMessages.append(
            AgentKernelMessageV2(
                role: .observation,
                content: """
                The previous provider response did not satisfy the structured tool protocol.
                Produce a user-facing final answer from the recorded evidence above. Do not call tools.
                If the evidence is insufficient, state what evidence is missing.
                """
            )
        )
        let retryRequest = AgentModelGatewayRequest(
            mode: .plainChat,
            messages: retryMessages,
            tools: [],
            attachments: baseRequest.attachments,
            requestedMaxOutputTokens: baseRequest.requestedMaxOutputTokens,
            timeout: baseRequest.timeout,
            metadata: baseRequest.metadata.merging(["structuredOutputRecovery": .bool(true)]) { current, _ in current }
        )
        let retry = await gateway.response(adapterID: adapterID, request: retryRequest)
        switch retry {
        case .success(let response):
            guard let answer = Self.finalAnswer(from: response.events),
                  !isRawJSONShapedAnswer(answer) else {
                try await failRun(
                    runID: runID,
                    reason: AgentRunText("Provider failed the structured tool protocol and the no-tool recovery did not produce user-facing prose. Recorded evidence was preserved for retry."),
                    status: .blocked
                )
                throw failure
            }
            return response
        case .failure:
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
            "Provider route=\(response.descriptor.route.rawValue) adapter=\(response.adapterID) model=\(response.descriptor.modelName ?? response.descriptor.displayName) tier=\(response.tier.rawValue) mode=\(request.mode.rawValue) visibleTools=\(request.tools.map(\.name).sorted().joined(separator: ","))"
        )
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

    private func recordFinalAnswerSupportIfPossible(runID: UUID, answer: AgentRunText) async throws {
        let evidence = await store.evidenceArtifactSummary(runID: runID).evidence
        let claims = finalAnswerClaims(from: evidence)
        guard !claims.isEmpty else { return }
        _ = try await AgentFinalAnswerSupportRecorder(
            store: store,
            evidenceRecorder: AgentEvidenceRecorder(store: store)
        ).recordSupport(
            runID: runID,
            answer: answer,
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

    private func finalAnswerClaims(from evidence: [AgentRunEvidenceRecord]) -> [AgentEvidenceClaim] {
        var claims: [AgentEvidenceClaim] = []
        for record in evidence {
            guard let kind = AgentEvidenceKind(rawValue: record.kind) else { continue }
            switch kind {
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
            case .sideEffect:
                if record.stringMetadata("status") == AgentRunSideEffectStatus.completed.rawValue {
                    if let targetPath = record.stringMetadata("targetPath") {
                        claims.append(.fileChanged(targetPath))
                    } else if let sideEffectID = record.stringMetadata("sideEffectID") {
                        claims.append(AgentEvidenceClaim(type: .sideEffectCompleted, target: sideEffectID))
                    }
                }
            case .localServer:
                if let port = record.intMetadata("port") {
                    claims.append(.portListening(port))
                }
                if let url = record.stringMetadata("url") {
                    claims.append(.urlResponds(url))
                }
            case .processState:
                if let processID = record.stringMetadata("processID") {
                    claims.append(AgentEvidenceClaim(type: .processRunning, target: processID))
                }
            case .fileGrant, .temporalContext, .visualContext, .approval, .terminalState, .evidenceRequirement, .finalAnswerSupport:
                continue
            }
        }
        var seen = Set<String>()
        return claims.filter { claim in
            let key = "\(claim.type.rawValue):\(claim.target ?? "")"
            return seen.insert(key).inserted
        }
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
            case .fileRead, .commandOutput, .localServer, .processState, .temporalContext, .visualContext:
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
            case .fileRead, .fileSearch, .folderList, .commandOutput, .localServer, .processState, .temporalContext, .visualContext, .sideEffect:
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
            && (trimmed.contains(#""type""#)
                || trimmed.contains(#""answer""#)
                || trimmed.contains(#""text""#)
                || trimmed.contains(#""bullets""#))
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

    nonisolated var intValue: Int? {
        guard case .int(let value) = self else { return nil }
        return value
    }

    nonisolated var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

private extension AgentKernelMetadataValueV2 {
    nonisolated var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    nonisolated var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

private extension AgentRunEvidenceRecord {
    nonisolated func stringMetadata(_ key: String) -> String? {
        guard case .string(let value) = metadata[key] else { return nil }
        return value
    }

    nonisolated func intMetadata(_ key: String) -> Int? {
        metadata[key]?.intValue
    }

    nonisolated func boolMetadata(_ key: String) -> Bool? {
        metadata[key]?.boolValue
    }
}
