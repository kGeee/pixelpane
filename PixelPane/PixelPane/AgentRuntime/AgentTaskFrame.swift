//
//  AgentTaskFrame.swift
//  PixelPane
//
//  App-owned task frame built from the active session, action, grants, and
//  references that the runtime uses to classify and execute a run.
//

import Foundation

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
        tools: [AgentKernelToolSchema],
        context: AgentToolRunContext,
        providerTier: AgentModelCapabilityTier? = nil,
        attachments: [AgentKernelModelAttachment] = [],
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
            if grants.contains(where: { $0.isDirectory && $0.allowsWrite(standardized) }) {
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
        if containsRelativeDayToken(text) {
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
        return containsCurrentTemporalQuestion(text) ? 0 : nil
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

    private static func containsCurrentTemporalQuestion(_ text: String) -> Bool {
        let patterns = [
            #"(?i)\bwhat(?:'s|s)\s+(?:the\s+)?(?:(?:current|local)\s+)?(?:time|date)\s*(?:now|right\s+now|here|locally)?\s*(?:[?.!]|$)"#,
            #"(?i)\bwhat\s+is\s+(?:the\s+)?(?:(?:current|local)\s+)?(?:time|date)\s*(?:now|right\s+now|here|locally)?\s*(?:[?.!]|$)"#,
            #"(?i)\bwhat\s+(?:time|date)\s+is\s+it\b"#,
            #"(?i)\b(?:current|local)\s+(?:time|date)\s*(?:now|right\s+now|here|locally)?\s*(?:[?.!]|$)"#,
            #"(?i)\b(?:tell|show|give)\s+me\s+(?:the\s+)?(?:(?:current|local)\s+)?(?:time|date)\s*(?:now|right\s+now|here|locally)?\s*(?:[?.!]|$)"#
        ]
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: text, range: range) != nil
        }
    }

    private static func visualContext(from attachments: [AgentKernelModelAttachment]) -> VisualContextSnapshot? {
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

    static func localPathCandidates(in text: String) -> [String] {
        var seen = Set<String>()
        return (absolutePathCandidates(in: text) + relativePathCandidates(in: text))
            .filter { seen.insert($0).inserted }
    }

    private static func localReference(
        for rawPath: String,
        grants: [AgentLocalFileGrant],
        source: StructuralSource
    ) -> LocalReference {
        let standardized = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        let grant = grants.first { $0.allowsRead(standardized) }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory)
        return LocalReference(
            path: standardized,
            isDirectory: exists ? isDirectory.boolValue : nil,
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
        let grant = preferredGrant ?? grants.first { $0.isDirectory }
        let candidate = grant?.url.appendingPathComponent(writeRequest.targetPath).standardizedFileURL.path ?? writeRequest.targetPath
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory)
        return LocalReference(
            path: candidate,
            isDirectory: exists ? isDirectory.boolValue : nil,
            source: .explicitWriteTarget,
            exists: exists,
            grantPath: grant?.path
        )
    }

    private static func evidenceRequests(
        availableToolNames: [String],
        writeRequest: WriteRequest?,
        commandDraft: ExplicitCommandDraft?,
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
