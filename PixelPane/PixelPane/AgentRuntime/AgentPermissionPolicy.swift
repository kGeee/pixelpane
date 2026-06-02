import Foundation

nonisolated enum AgentRunPermissionMode: String, Codable, Equatable, Sendable {
    case plainChat
    case readOnly
    case proposalOnly
    case fullAgent
}

nonisolated enum AgentPermissionDecisionKind: String, Codable, Equatable, Sendable {
    case allow
    case ask
    case deny
}

nonisolated enum AgentPermissionScope: String, Codable, Equatable, Sendable {
    case fileRead
    case fileWrite
    case visualContext
    case workingDirectory
    case network
    case processControl
    case localServer
    case privileged
}

nonisolated enum AgentToolOperationKind: String, Codable, Equatable, Hashable, Sendable {
    case fileGrantList
    case fileList
    case fileSearch
    case fileRead
    case fileWriteDraft
    case visualContext
    case finiteCommand
    case processSnapshot
    case processStart
    case processStatus
    case processStop
    case processOutput
    case localServerProbe
    case localServerDiscovery
    case custom
}

nonisolated enum AgentToolRisk: String, Codable, Equatable, Sendable {
    case readOnly
    case localRead
    case localWriteDraft
    case command
    case network
    case processControl
    case privileged
}

nonisolated enum AgentPermissionReason: String, Codable, Equatable, Sendable {
    case allowed
    case approvalGrantMatched
    case unknownTool
    case providerTierDisallowsTool
    case runModeDisallowsTool
    case unsupportedOperation
    case missingRequiredArgument
    case malformedArgument
    case deniedScope
    case missingFileGrant
    // Legacy persisted value from the old read-only/read-write grant split. New policy emits missingFileGrant.
    case missingWriteGrant
    case sensitivePathDenied
    case approvalRequired
    case rawShellRequiresApproval
    case fileMutationRequiresApproval
    case installRequiresApproval
    case networkRequiresApproval
    case processControlRequiresApproval
    case privilegedCommandRequiresApproval
    case unsafeCommandDenied
}

nonisolated struct AgentLocalFileGrant: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let path: String
    let isDirectory: Bool

    init(
        id: UUID = UUID(),
        path: String,
        isDirectory: Bool
    ) {
        self.id = id
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.isDirectory = isDirectory
    }

    var url: URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    func allowsRead(_ candidatePath: String) -> Bool {
        allows(candidatePath)
    }

    func allowsWrite(_ candidatePath: String) -> Bool {
        allows(candidatePath)
    }

    private func allows(_ candidatePath: String) -> Bool {
        let candidate = URL(fileURLWithPath: candidatePath).standardizedFileURL.path
        if isDirectory {
            let root = path.hasSuffix("/") ? path : path + "/"
            return candidate == path || candidate.hasPrefix(root)
        }
        return candidate == path
    }
}

nonisolated enum AgentLocalPathAccessIntent: String, Equatable, Sendable {
    case read
    case write
}

nonisolated enum AgentLocalPathTargetIntent: Equatable, Sendable {
    case any
    case existingFile
    case existingDirectory
    case writeTarget(requiresExistingParent: Bool)
}

nonisolated enum AgentLocalPathResolutionFailureCode: String, Equatable, Sendable {
    case emptyPath
    case noMatchingGrant
    case ambiguousRelativePath
    case pathDoesNotExist
    case pathIsNotFile
    case pathIsNotDirectory
    case targetIsDirectory
    case parentDirectoryMissing
}

nonisolated struct AgentLocalPathResolutionFailure: Equatable, Sendable {
    let code: AgentLocalPathResolutionFailureCode
    let summary: AgentRunText
    let candidates: [String]
}

nonisolated struct AgentLocalPathResolution: Equatable, Sendable {
    let path: String
    let grant: AgentLocalFileGrant
    let source: String

    var url: URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }
}

nonisolated enum AgentLocalPathResolutionResult: Equatable, Sendable {
    case resolved(AgentLocalPathResolution)
    case failed(AgentLocalPathResolutionFailure)

    var resolution: AgentLocalPathResolution? {
        guard case .resolved(let resolution) = self else { return nil }
        return resolution
    }

    var failure: AgentLocalPathResolutionFailure? {
        guard case .failed(let failure) = self else { return nil }
        return failure
    }
}

nonisolated struct AgentLocalPathResolver: Sendable {
    private struct Candidate: Equatable {
        let path: String
        let grant: AgentLocalFileGrant
        let source: String
    }

    nonisolated init() {}

    nonisolated func resolve(
        _ rawPath: String,
        grants: [AgentLocalFileGrant],
        access: AgentLocalPathAccessIntent,
        target: AgentLocalPathTargetIntent = .any,
        preferredDirectoryPath: String? = nil
    ) -> AgentLocalPathResolutionResult {
        let cleaned = expandUserHome(rawPath.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !cleaned.isEmpty else {
            return failure(.emptyPath, "The local path is empty.")
        }

        guard !grants.isEmpty else {
            return failure(.noMatchingGrant, "No matching local file grant is available for this request.")
        }

        if cleaned.hasPrefix("/") {
            let candidatePath = URL(fileURLWithPath: cleaned).standardizedFileURL.path
            let candidates = grants.compactMap { grant -> Candidate? in
                isAllowed(candidatePath, by: grant, access: access)
                    ? Candidate(path: candidatePath, grant: grant, source: "absolute")
                    : nil
            }
            return select(candidates, rawPath: cleaned, access: access, target: target, allowsFallback: false)
        }

        for group in relativeCandidateGroups(
            cleaned,
            grants: grants,
            preferredDirectoryPath: preferredDirectoryPath
        ) {
            let result = select(group.candidates, rawPath: cleaned, access: access, target: target, allowsFallback: group.allowsFallback)
            switch result {
            case .resolved:
                return result
            case .failed(let resolutionFailure):
                if !group.allowsFallback || resolutionFailure.code == .ambiguousRelativePath {
                    return result
                }
            }
        }

        return failure(
            .noMatchingGrant,
            "The requested path is outside granted local file access.",
            candidates: []
        )
    }

    private nonisolated func expandUserHome(_ path: String) -> String {
        if path == "~" {
            return NSHomeDirectory()
        }
        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(String(path.dropFirst(2)))
                .standardizedFileURL
                .path
        }
        return path
    }

    private nonisolated func relativeCandidateGroups(
        _ cleaned: String,
        grants: [AgentLocalFileGrant],
        preferredDirectoryPath: String?
    ) -> [(candidates: [Candidate], allowsFallback: Bool)] {
        var groups: [(candidates: [Candidate], allowsFallback: Bool)] = []
        let directories = grants.filter(\.isDirectory)

        let exact = exactGrantReferenceCandidates(cleaned, grants: directories)
        if !exact.isEmpty {
            groups.append((unique(exact), false))
        }

        if let preferred = preferredDirectoryGrant(preferredDirectoryPath, grants: directories) {
            groups.append((unique([candidate(cleaned, in: preferred, source: "preferred-directory")]), false))
        }

        let fileGrantMatches = grants
            .filter { !$0.isDirectory }
            .compactMap { grant -> Candidate? in
                URL(fileURLWithPath: grant.path).lastPathComponent.localizedCaseInsensitiveCompare(cleaned) == .orderedSame
                    ? Candidate(path: grant.path, grant: grant, source: "file-grant-name")
                    : nil
            }
        if !fileGrantMatches.isEmpty {
            groups.append((unique(fileGrantMatches), false))
        }

        let existing = directories
            .map { candidate(cleaned, in: $0, source: "existing-relative") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !existing.isEmpty {
            groups.append((unique(existing), false))
        }

        let fallback = directories.map { candidate(cleaned, in: $0, source: "relative-fallback") }
        if !fallback.isEmpty {
            groups.append((unique(fallback), true))
        }

        return groups
    }

    private nonisolated func exactGrantReferenceCandidates(
        _ cleaned: String,
        grants: [AgentLocalFileGrant]
    ) -> [Candidate] {
        let parts = cleaned.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first else { return [] }
        let remainder = parts.dropFirst().joined(separator: "/")
        return grants.compactMap { grant in
            guard grant.url.lastPathComponent.localizedCaseInsensitiveCompare(first) == .orderedSame else {
                return nil
            }
            let path = remainder.isEmpty
                ? grant.path
                : grant.url.appendingPathComponent(remainder).standardizedFileURL.path
            return Candidate(path: path, grant: grant, source: "grant-name")
        }
    }

    private nonisolated func preferredDirectoryGrant(
        _ preferredDirectoryPath: String?,
        grants: [AgentLocalFileGrant]
    ) -> AgentLocalFileGrant? {
        guard let preferredDirectoryPath else { return nil }
        let preferredPath = URL(fileURLWithPath: preferredDirectoryPath).standardizedFileURL.path
        return grants.first { grant in
            grant.isDirectory && grant.path == preferredPath
        }
    }

    private nonisolated func candidate(
        _ cleaned: String,
        in grant: AgentLocalFileGrant,
        source: String
    ) -> Candidate {
        Candidate(
            path: grant.url.appendingPathComponent(cleaned).standardizedFileURL.path,
            grant: grant,
            source: source
        )
    }

    private nonisolated func select(
        _ rawCandidates: [Candidate],
        rawPath: String,
        access: AgentLocalPathAccessIntent,
        target: AgentLocalPathTargetIntent,
        allowsFallback: Bool
    ) -> AgentLocalPathResolutionResult {
        let candidates = unique(rawCandidates)
        guard !candidates.isEmpty else {
            return failure(.noMatchingGrant, "The requested path is outside granted local file access.")
        }

        var resolved: [AgentLocalPathResolution] = []
        var failures: [AgentLocalPathResolutionFailure] = []

        for candidate in candidates {
            guard isAllowed(candidate.path, by: candidate.grant, access: access) else {
                failures.append(
                    AgentLocalPathResolutionFailure(
                        code: .noMatchingGrant,
                        summary: AgentRunText("The requested path escapes its granted local folder: \(candidate.path)"),
                        candidates: [candidate.path]
                    )
                )
                continue
            }
            switch validate(candidate, target: target) {
            case .resolved(let resolution):
                resolved.append(resolution)
            case .failed(let failure):
                failures.append(failure)
            }
        }

        if resolved.count == 1, let value = resolved.first {
            return .resolved(value)
        }
        if resolved.count > 1 {
            let paths = resolved.map(\.path).sorted()
            return failure(
                .ambiguousRelativePath,
                "The relative path matches multiple granted locations. Name the exact granted folder.",
                candidates: paths
            )
        }
        if let failure = failures.first, !allowsFallback || failures.count == candidates.count {
            return .failed(failure)
        }
        return failure(.noMatchingGrant, "The requested path is outside granted local file access.")
    }

    private nonisolated func validate(
        _ candidate: Candidate,
        target: AgentLocalPathTargetIntent
    ) -> AgentLocalPathResolutionResult {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)

        switch target {
        case .any:
            return .resolved(resolution(from: candidate))
        case .existingFile:
            guard exists else {
                return failure(.pathDoesNotExist, "The requested file does not exist: \(candidate.path)", candidates: [candidate.path])
            }
            guard !isDirectory.boolValue else {
                return failure(.pathIsNotFile, "The requested path is a folder, not a file: \(candidate.path)", candidates: [candidate.path])
            }
            return .resolved(resolution(from: candidate))
        case .existingDirectory:
            guard exists else {
                return failure(.pathDoesNotExist, "The requested folder does not exist: \(candidate.path)", candidates: [candidate.path])
            }
            guard isDirectory.boolValue else {
                return failure(.pathIsNotDirectory, "The requested path is not a folder: \(candidate.path)", candidates: [candidate.path])
            }
            return .resolved(resolution(from: candidate))
        case .writeTarget(let requiresExistingParent):
            guard !exists || !isDirectory.boolValue else {
                return failure(.targetIsDirectory, "The write target is a folder, not a file: \(candidate.path)", candidates: [candidate.path])
            }
            if requiresExistingParent {
                let parent = URL(fileURLWithPath: candidate.path).deletingLastPathComponent().standardizedFileURL.path
                var parentIsDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: parent, isDirectory: &parentIsDirectory),
                      parentIsDirectory.boolValue else {
                    return failure(.parentDirectoryMissing, "The write target parent directory does not exist: \(parent)", candidates: [candidate.path])
                }
            }
            return .resolved(resolution(from: candidate))
        }
    }

    private nonisolated func resolution(from candidate: Candidate) -> AgentLocalPathResolution {
        AgentLocalPathResolution(path: candidate.path, grant: candidate.grant, source: candidate.source)
    }

    private nonisolated func isAllowed(
        _ candidatePath: String,
        by grant: AgentLocalFileGrant,
        access: AgentLocalPathAccessIntent
    ) -> Bool {
        access == .write ? grant.allowsWrite(candidatePath) : grant.allowsRead(candidatePath)
    }

    private nonisolated func unique(_ candidates: [Candidate]) -> [Candidate] {
        var seen = Set<String>()
        var result: [Candidate] = []
        for candidate in candidates {
            let key = "\(candidate.path)|\(candidate.grant.path)|\(candidate.source)"
            guard seen.insert(key).inserted else { continue }
            result.append(candidate)
        }
        return result
    }

    private nonisolated func failure(
        _ code: AgentLocalPathResolutionFailureCode,
        _ summary: String,
        candidates: [String] = []
    ) -> AgentLocalPathResolutionResult {
        .failed(
            AgentLocalPathResolutionFailure(
                code: code,
                summary: AgentRunText(summary),
                candidates: candidates
            )
        )
    }
}

nonisolated struct AgentPermissionApprovalGrant: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let toolName: String
    let argumentDigest: String
    let expiresAt: Date?

    init(
        id: UUID = UUID(),
        toolName: String,
        argumentDigest: String,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.argumentDigest = argumentDigest
        self.expiresAt = expiresAt
    }

    func matches(toolName: String, argumentDigest: String, now: Date) -> Bool {
        self.toolName == toolName
            && self.argumentDigest == argumentDigest
            && (expiresAt.map { $0 >= now } ?? true)
    }
}

nonisolated struct AgentSensitivePathRule: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let exactFilenames: [String]
    let filenameSuffixes: [String]
    let pathComponents: [String]
    let substrings: [String]
    let summary: AgentRunText

    init(
        id: String,
        exactFilenames: [String] = [],
        filenameSuffixes: [String] = [],
        pathComponents: [String] = [],
        substrings: [String] = [],
        summary: AgentRunText
    ) {
        self.id = id
        self.exactFilenames = exactFilenames.map { $0.lowercased() }
        self.filenameSuffixes = filenameSuffixes.map { $0.lowercased() }
        self.pathComponents = pathComponents.map { $0.lowercased() }
        self.substrings = substrings.map { $0.lowercased() }
        self.summary = summary
    }

    func matches(_ rawValue: String) -> Bool {
        let lowercased = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return false }

        if substrings.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let components = lowercased
            .split { character in
                character == "/" || character == "\\" || character == " " || character == "\t" || character == "\n"
            }
            .map(String.init)
        if components.contains(where: { exactFilenames.contains($0) }) {
            return true
        }
        if components.contains(where: { component in filenameSuffixes.contains { component.hasSuffix($0) } }) {
            return true
        }
        return components.contains(where: { pathComponents.contains($0) })
    }
}

nonisolated struct AgentToolSpec: Identifiable, Sendable {
    var id: String { schema.name }

    let schema: AgentKernelToolSchemaV2
    let contract: AgentToolContract
    let operationKind: AgentToolOperationKind
    let risk: AgentToolRisk
    let requiredScopes: [AgentPermissionScope]
    let visibleRunModes: [AgentRunPermissionMode]
    let visibleProviderTiers: [AgentModelCapabilityTier]
    let requiresApproval: Bool

    init(
        schema: AgentKernelToolSchemaV2,
        operationKind: AgentToolOperationKind,
        risk: AgentToolRisk,
        requiredScopes: [AgentPermissionScope] = [],
        visibleRunModes: [AgentRunPermissionMode],
        visibleProviderTiers: [AgentModelCapabilityTier],
        requiresApproval: Bool = false
    ) {
        self.schema = schema
        self.contract = AgentToolContract(
            name: schema.name,
            summary: schema.summary,
            operationKind: operationKind,
            risk: risk,
            requiredScopes: requiredScopes,
            visibleRunModes: visibleRunModes,
            visibleProviderTiers: visibleProviderTiers,
            requiresApproval: requiresApproval,
            executorBinding: .localRuntime,
            arguments: schema.arguments.map {
                AgentToolArgumentContract(
                    $0.name,
                    type: $0.type,
                    isRequired: $0.isRequired,
                    summary: $0.summary
                )
            }
        )
        self.operationKind = operationKind
        self.risk = risk
        self.requiredScopes = requiredScopes
        self.visibleRunModes = visibleRunModes
        self.visibleProviderTiers = visibleProviderTiers
        self.requiresApproval = requiresApproval
    }

    var name: String {
        schema.name
    }

    init(contract: AgentToolContract) {
        self.schema = contract.schema
        self.contract = contract
        self.operationKind = contract.operationKind
        self.risk = contract.risk
        self.requiredScopes = contract.requiredScopes
        self.visibleRunModes = contract.visibleRunModes
        self.visibleProviderTiers = contract.visibleProviderTiers
        self.requiresApproval = contract.requiresApproval
    }

    func isVisible(providerTier: AgentModelCapabilityTier, runMode: AgentRunPermissionMode) -> Bool {
        if providerTier == .tierBConstrainedStructuredText,
           operationKind == .fileWriteDraft,
           runMode != .proposalOnly {
            return false
        }
        return visibleProviderTiers.contains(providerTier) && visibleRunModes.contains(runMode)
    }
}

nonisolated enum AgentToolExecutionCapabilities {
    static let activeLocalRuntimeOperations: Set<AgentToolOperationKind> = [
        .fileGrantList,
        .fileList,
        .fileSearch,
        .fileRead,
        .fileWriteDraft,
        .finiteCommand,
        .processSnapshot,
        .localServerDiscovery
    ]
}

nonisolated struct AgentPermissionRequest: Codable, Equatable, Sendable {
    let runMode: AgentRunPermissionMode
    let providerTier: AgentModelCapabilityTier
    let toolName: String
    let arguments: [String: String]
    let localGrants: [AgentLocalFileGrant]
    let grantedScopes: [AgentPermissionScope]
    let deniedScopes: [AgentPermissionScope]
    let supportedOperations: Set<AgentToolOperationKind>
    let approvalGrants: [AgentPermissionApprovalGrant]
    let now: Date

    init(
        runMode: AgentRunPermissionMode,
        providerTier: AgentModelCapabilityTier,
        toolName: String,
        arguments: [String: String] = [:],
        localGrants: [AgentLocalFileGrant] = [],
        grantedScopes: [AgentPermissionScope] = [],
        deniedScopes: [AgentPermissionScope] = [],
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations,
        approvalGrants: [AgentPermissionApprovalGrant] = [],
        now: Date = Date()
    ) {
        self.runMode = runMode
        self.providerTier = providerTier
        self.toolName = toolName
        self.arguments = arguments
        self.localGrants = localGrants
        self.grantedScopes = grantedScopes
        self.deniedScopes = deniedScopes
        self.supportedOperations = supportedOperations
        self.approvalGrants = approvalGrants
        self.now = now
    }

    func replacingArguments(_ arguments: [String: String]) -> AgentPermissionRequest {
        AgentPermissionRequest(
            runMode: runMode,
            providerTier: providerTier,
            toolName: toolName,
            arguments: arguments,
            localGrants: localGrants,
            grantedScopes: grantedScopes,
            deniedScopes: deniedScopes,
            supportedOperations: supportedOperations,
            approvalGrants: approvalGrants,
            now: now
        )
    }
}

nonisolated struct AgentPermissionDecision: Codable, Equatable, Sendable {
    let kind: AgentPermissionDecisionKind
    let reason: AgentPermissionReason
    let summary: AgentRunText
    let toolName: String
    let risk: AgentToolRisk?
    let metadata: [String: AgentRunMetadataValue]

    init(
        kind: AgentPermissionDecisionKind,
        reason: AgentPermissionReason,
        summary: AgentRunText,
        toolName: String,
        risk: AgentToolRisk? = nil,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) {
        self.kind = kind
        self.reason = reason
        self.summary = summary
        self.toolName = toolName
        self.risk = risk
        self.metadata = metadata
    }

    var isAllowed: Bool {
        kind == .allow
    }
}

nonisolated enum AgentCommandClass: String, Codable, Equatable, Sendable {
    case rawShell
    case fileMutation
    case install
    case network
    case processControl
    case privileged
    case destructive
}

nonisolated struct AgentCommandClassification: Codable, Equatable, Sendable {
    let commandClass: AgentCommandClass
    let reason: AgentPermissionReason
    let summary: AgentRunText

    init(commandClass: AgentCommandClass, reason: AgentPermissionReason, summary: AgentRunText) {
        self.commandClass = commandClass
        self.reason = reason
        self.summary = summary
    }
}

nonisolated struct AgentCommandClassifier: Sendable {
    init() {}

    func classify(_ command: String, sensitivePathRules: [AgentSensitivePathRule]) -> AgentCommandClassification {
        let cleaned = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = cleaned.lowercased()

        if sensitivePathRules.contains(where: { $0.matches(cleaned) }) {
            return AgentCommandClassification(
                commandClass: .destructive,
                reason: .sensitivePathDenied,
                summary: AgentRunText("The command references a sensitive credential or key path.")
            )
        }

        if lowercased.range(of: #"(^|[;&|]\s*)rm\s+(-[^\s]*[rR][fF][^\s]*|-rf|-fr)\s+(/|~|\$HOME|\*)($|\s)"#, options: .regularExpression) != nil
            || lowercased.range(of: #"\bdd\s+.*\bof=/dev/"#, options: .regularExpression) != nil {
            return AgentCommandClassification(
                commandClass: .destructive,
                reason: .unsafeCommandDenied,
                summary: AgentRunText("The command matches a destructive deny rule.")
            )
        }

        if lowercased.range(of: #"\bsudo\b"#, options: .regularExpression) != nil {
            return AgentCommandClassification(
                commandClass: .privileged,
                reason: .privilegedCommandRequiresApproval,
                summary: AgentRunText("Privileged commands require approval.")
            )
        }

        if lowercased.range(of: #"\b(npm|pnpm|yarn|brew|pip3?|gem|cargo)\s+(install|add|upgrade|update)\b"#, options: .regularExpression) != nil
            || lowercased.range(of: #"\bnpx\b"#, options: .regularExpression) != nil {
            return AgentCommandClassification(
                commandClass: .install,
                reason: .installRequiresApproval,
                summary: AgentRunText("Install and package-execution commands require approval.")
            )
        }

        if lowercased.range(of: #"\b(curl|wget|ssh|scp|rsync|nc|telnet)\b"#, options: .regularExpression) != nil {
            return AgentCommandClassification(
                commandClass: .network,
                reason: .networkRequiresApproval,
                summary: AgentRunText("Network commands require approval.")
            )
        }

        if lowercased.range(of: #"\b(kill|killall|pkill|launchctl)\b"#, options: .regularExpression) != nil {
            return AgentCommandClassification(
                commandClass: .processControl,
                reason: .processControlRequiresApproval,
                summary: AgentRunText("Process-control commands require approval.")
            )
        }

        if lowercased.range(of: #"\b(rm|mv|cp|mkdir|touch|chmod|chown|tee)\b"#, options: .regularExpression) != nil
            || lowercased.range(of: #"(?:^|[^2])>{1,2}\s*[^\s&]"#, options: .regularExpression) != nil {
            return AgentCommandClassification(
                commandClass: .fileMutation,
                reason: .fileMutationRequiresApproval,
                summary: AgentRunText("File mutation commands require approval.")
            )
        }

        return AgentCommandClassification(
            commandClass: .rawShell,
            reason: .rawShellRequiresApproval,
            summary: AgentRunText("Raw shell commands require approval.")
        )
    }

}

nonisolated struct AgentToolCatalog: Sendable {
    private let specsByName: [String: AgentToolSpec]

    init(specs: [AgentToolSpec] = AgentToolCatalog.defaultSpecs) {
        self.specsByName = Dictionary(uniqueKeysWithValues: specs.map { ($0.name, $0) })
    }

    func spec(named name: String) -> AgentToolSpec? {
        specsByName[name]
    }

    func visibleToolSpecs(
        providerTier: AgentModelCapabilityTier,
        runMode: AgentRunPermissionMode,
        localGrants: [AgentLocalFileGrant] = [],
        grantedScopes: [AgentPermissionScope] = [],
        deniedScopes: [AgentPermissionScope] = [],
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations
    ) -> [AgentToolSpec] {
        specsByName.values
            .filter { spec in
                spec.isVisible(providerTier: providerTier, runMode: runMode)
                    && supportedOperations.contains(spec.operationKind)
                    && !spec.requiredScopes.contains(where: { deniedScopes.contains($0) })
                    && hasRequiredVisibilityGrants(for: spec, localGrants: localGrants, grantedScopes: grantedScopes)
            }
            .sorted { $0.name < $1.name }
    }

    func visibleModelSchemas(
        providerTier: AgentModelCapabilityTier,
        runMode: AgentRunPermissionMode,
        localGrants: [AgentLocalFileGrant] = [],
        grantedScopes: [AgentPermissionScope] = [],
        deniedScopes: [AgentPermissionScope] = [],
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations
    ) -> [AgentKernelToolSchemaV2] {
        visibleToolSpecs(
            providerTier: providerTier,
            runMode: runMode,
            localGrants: localGrants,
            grantedScopes: grantedScopes,
            deniedScopes: deniedScopes,
            supportedOperations: supportedOperations
        ).map(\.schema)
    }

    func visibilityDiagnostics(
        providerTier: AgentModelCapabilityTier,
        runMode: AgentRunPermissionMode,
        localGrants: [AgentLocalFileGrant] = [],
        grantedScopes: [AgentPermissionScope] = [],
        deniedScopes: [AgentPermissionScope] = [],
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations
    ) -> [String] {
        specsByName.values
            .sorted { $0.name < $1.name }
            .map { spec in
                let reason: String
                if !spec.visibleProviderTiers.contains(providerTier) {
                    reason = "withheld:providerTier"
                } else if !spec.isVisible(providerTier: providerTier, runMode: runMode) {
                    reason = "withheld:runMode"
                } else if !supportedOperations.contains(spec.operationKind) {
                    reason = "withheld:unsupportedOperation"
                } else if let deniedScope = spec.requiredScopes.first(where: { deniedScopes.contains($0) }) {
                    reason = "withheld:deniedScope:\(deniedScope.rawValue)"
                } else if spec.requiredScopes.contains(.fileRead), localGrants.isEmpty {
                    reason = "withheld:missingReadGrant"
                } else if spec.requiredScopes.contains(.fileWrite), localGrants.isEmpty {
                    reason = "withheld:missingFileGrant"
                } else if let missingScope = spec.requiredScopes.first(where: { scope in
                    scope != .fileRead
                        && scope != .fileWrite
                        && scope != .workingDirectory
                        && scope != .localServer
                        && !grantedScopes.contains(scope)
                }) {
                    reason = "withheld:missingScope:\(missingScope.rawValue)"
                } else {
                    reason = "visible"
                }
                return "tool.\(spec.name)=\(reason)"
            }
    }

    private func hasRequiredVisibilityGrants(
        for spec: AgentToolSpec,
        localGrants: [AgentLocalFileGrant],
        grantedScopes: [AgentPermissionScope]
    ) -> Bool {
        if spec.operationKind == .fileGrantList {
            return true
        }
        if spec.requiredScopes.contains(.fileRead), localGrants.isEmpty {
            return false
        }
        if spec.requiredScopes.contains(.fileWrite), localGrants.isEmpty {
            return false
        }
        let nonGrantScopes = spec.requiredScopes.filter { scope in
            scope != .fileRead
                && scope != .fileWrite
                && scope != .workingDirectory
                && scope != .localServer
        }
        return nonGrantScopes.allSatisfy { grantedScopes.contains($0) }
    }
}

extension AgentToolCatalog {
    nonisolated static var defaultSpecs: [AgentToolSpec] {
        AgentToolContractLibrary.defaultContracts.map(AgentToolSpec.init(contract:))
    }
}

nonisolated struct AgentPermissionPolicy: Sendable {
    let catalog: AgentToolCatalog
    let sensitivePathRules: [AgentSensitivePathRule]
    let commandClassifier: AgentCommandClassifier
    let pathResolver: AgentLocalPathResolver

    init(
        catalog: AgentToolCatalog = AgentToolCatalog(),
        sensitivePathRules: [AgentSensitivePathRule] = AgentPermissionPolicy.defaultSensitivePathRules,
        commandClassifier: AgentCommandClassifier = AgentCommandClassifier(),
        pathResolver: AgentLocalPathResolver = AgentLocalPathResolver()
    ) {
        self.catalog = catalog
        self.sensitivePathRules = sensitivePathRules
        self.commandClassifier = commandClassifier
        self.pathResolver = pathResolver
    }

    func decision(for rawRequest: AgentPermissionRequest) -> AgentPermissionDecision {
        guard let spec = catalog.spec(named: rawRequest.toolName) else {
            return deny(
                reason: .unknownTool,
                summary: "The requested tool is not registered.",
                toolName: rawRequest.toolName
            )
        }

        guard rawRequest.supportedOperations.contains(spec.operationKind) else {
            return deny(
                reason: .unsupportedOperation,
                summary: "The active runtime does not support this tool operation.",
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["operation": .string(spec.operationKind.rawValue)]
            )
        }

        guard spec.visibleProviderTiers.contains(rawRequest.providerTier) else {
            return deny(
                reason: .providerTierDisallowsTool,
                summary: "The selected provider tier cannot use this tool.",
                toolName: spec.name,
                risk: spec.risk
            )
        }
        guard spec.isVisible(providerTier: rawRequest.providerTier, runMode: rawRequest.runMode) else {
            return deny(
                reason: .runModeDisallowsTool,
                summary: "The current run mode cannot use this tool.",
                toolName: spec.name,
                risk: spec.risk
            )
        }

        let invocation: AgentToolInvocation
        do {
            invocation = try spec.contract.normalizedInvocation(rawArguments: rawRequest.arguments)
        } catch let error as AgentToolContractError {
            return argumentFailure(spec: spec, error: error)
        } catch {
            return deny(
                reason: .malformedArgument,
                summary: "The tool call arguments could not be normalized.",
                toolName: spec.name,
                risk: spec.risk
            )
        }
        let request = rawRequest.replacingArguments(invocation.normalizedArguments)

        if let deniedScope = spec.requiredScopes.first(where: { request.deniedScopes.contains($0) }) {
            return deny(
                reason: .deniedScope,
                summary: "A required permission scope is explicitly denied.",
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["scope": .string(deniedScope.rawValue)]
            )
        }
        if let sensitive = sensitivePathFailure(spec: spec, arguments: request.arguments) {
            return sensitive
        }
        if let grantFailure = localGrantFailure(spec: spec, request: request) {
            return grantFailure
        }
        if let scopeFailure = missingScopeFailure(spec: spec, request: request) {
            return scopeFailure
        }

        if spec.operationKind == .finiteCommand {
            return commandDecision(spec: spec, request: request)
        }

        if spec.requiresApproval {
            if hasApprovalGrant(for: request) {
                return allow(
                    reason: .approvalGrantMatched,
                    summary: "A matching approval grant allows this tool request.",
                    toolName: spec.name,
                    risk: spec.risk
                )
            }
            return ask(
                reason: .approvalRequired,
                summary: "This tool request requires app-owned user approval.",
                toolName: spec.name,
                risk: spec.risk
            )
        }

        return allow(
            reason: .allowed,
            summary: "The tool request is allowed by policy.",
            toolName: spec.name,
            risk: spec.risk
        )
    }

    func referencesSensitivePath(_ value: String) -> Bool {
        sensitivePathRules.contains { $0.matches(value) }
    }

    static func approvalDigest(toolName: String, arguments: [String: String]) -> String {
        let serialized = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(toolName):\(serialized)"
    }

    private func argumentFailure(spec: AgentToolSpec, error: AgentToolContractError) -> AgentPermissionDecision {
        switch error {
        case .unknownTool(let tool):
            return deny(
                reason: .unknownTool,
                summary: "The requested tool is not registered.",
                toolName: tool,
                risk: spec.risk
            )
        case .unknownArgument(let argument):
            return deny(
                reason: .malformedArgument,
                summary: "The tool call included an argument that is not in the schema.",
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["argument": .string(argument)]
            )
        case .missingRequiredArgument(let argument):
            return deny(
                reason: .missingRequiredArgument,
                summary: "The tool call is missing a required argument.",
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["argument": .string(argument)]
            )
        case .malformedArgument(let argument, let type, _):
            return deny(
                reason: .malformedArgument,
                summary: "The tool call argument does not match its declared type.",
                toolName: spec.name,
                risk: spec.risk,
                metadata: [
                    "argument": .string(argument),
                    "type": .string(type.rawValue)
                ]
            )
        case .constraintViolation(let argument, let summary):
            return deny(
                reason: .malformedArgument,
                summary: summary,
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["argument": .string(argument)]
            )
        }
    }

    private func sensitivePathFailure(
        spec: AgentToolSpec,
        arguments: [String: String]
    ) -> AgentPermissionDecision? {
        let valuesToCheck = pathLikeArgumentValues(for: spec, arguments: arguments)
        guard let matchedValue = valuesToCheck.first(where: { value in
            sensitivePathRules.contains(where: { $0.matches(value) })
        }) else {
            return nil
        }
        return deny(
            reason: .sensitivePathDenied,
            summary: "The request references a sensitive credential or key path.",
            toolName: spec.name,
            risk: spec.risk,
            metadata: ["path": .string(matchedValue)]
        )
    }

    private func localGrantFailure(
        spec: AgentToolSpec,
        request: AgentPermissionRequest
    ) -> AgentPermissionDecision? {
        if spec.requiredScopes.contains(.fileRead) {
            guard let rawPath = primaryPathArgument(for: spec, arguments: request.arguments) else {
                return nil
            }
            let resolution = pathResolver.resolve(
                rawPath,
                grants: request.localGrants,
                access: .read,
                target: .any,
                preferredDirectoryPath: request.arguments["preferredDirectoryPath"]
            )
            if let failure = resolution.failure {
                return localPathFailureDecision(
                    failure,
                    rawPath: rawPath,
                    spec: spec
                )
            }
        }

        if spec.requiredScopes.contains(.fileWrite) {
            guard let rawPath = primaryPathArgument(for: spec, arguments: request.arguments) else {
                return nil
            }
            let resolution = pathResolver.resolve(
                rawPath,
                grants: request.localGrants,
                access: .write,
                target: .any,
                preferredDirectoryPath: request.arguments["preferredDirectoryPath"]
            )
            if let failure = resolution.failure {
                return localPathFailureDecision(
                    failure,
                    rawPath: rawPath,
                    spec: spec
                )
            }
        }

        if spec.requiredScopes.contains(.workingDirectory) {
            guard let workingDirectory = request.arguments["workingDirectory"] else {
                return nil
            }
            let resolution = pathResolver.resolve(
                workingDirectory,
                grants: request.localGrants,
                access: .read,
                target: .any
            )
            if let failure = resolution.failure {
                return localPathFailureDecision(
                    failure,
                    rawPath: workingDirectory,
                    spec: spec
                )
            }
        }

        return nil
    }

    private func localPathFailureDecision(
        _ failure: AgentLocalPathResolutionFailure,
        rawPath: String,
        spec: AgentToolSpec
    ) -> AgentPermissionDecision {
        switch failure.code {
        case .noMatchingGrant:
            return ask(
                reason: .missingFileGrant,
                summary: failure.summary.text,
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["path": .string(rawPath)]
            )
        case .emptyPath:
            return deny(
                reason: .missingRequiredArgument,
                summary: failure.summary.text,
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["path": .string(rawPath)]
            )
        case .ambiguousRelativePath,
             .pathDoesNotExist,
             .pathIsNotFile,
             .pathIsNotDirectory,
             .targetIsDirectory,
             .parentDirectoryMissing:
            return deny(
                reason: .malformedArgument,
                summary: failure.summary.text,
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["path": .string(rawPath)]
            )
        }
    }

    private func missingScopeFailure(
        spec: AgentToolSpec,
        request: AgentPermissionRequest
    ) -> AgentPermissionDecision? {
        for scope in spec.requiredScopes {
            switch scope {
            case .fileRead, .fileWrite, .workingDirectory, .localServer:
                continue
            case .visualContext, .network, .processControl, .privileged:
                guard request.grantedScopes.contains(scope) else {
                    return ask(
                        reason: .approvalRequired,
                        summary: "The tool needs a permission scope that has not been granted for this run.",
                        toolName: spec.name,
                        risk: spec.risk,
                        metadata: ["scope": .string(scope.rawValue)]
                    )
                }
            }
        }
        return nil
    }

    private func commandDecision(
        spec: AgentToolSpec,
        request: AgentPermissionRequest
    ) -> AgentPermissionDecision {
        let command = request.arguments["command"] ?? ""
        let classification = commandClassifier.classify(command, sensitivePathRules: sensitivePathRules)

        switch classification.commandClass {
        case .destructive:
            return deny(
                reason: classification.reason,
                summary: classification.summary.text,
                toolName: spec.name,
                risk: .privileged,
                metadata: ["command": .string(command)]
            )
        case .rawShell:
            guard request.runMode == .fullAgent else {
                return deny(
                    reason: .rawShellRequiresApproval,
                    summary: "Raw shell commands are denied outside full-agent mode.",
                    toolName: spec.name,
                    risk: spec.risk,
                    metadata: ["command": .string(command)]
                )
            }
            return approvalOrAsk(spec: spec, request: request, reason: classification.reason, summary: classification.summary)
        case .fileMutation:
            guard request.runMode == .fullAgent else {
                return deny(
                    reason: .fileMutationRequiresApproval,
                    summary: "File mutation commands are denied outside full-agent mode.",
                    toolName: spec.name,
                    risk: spec.risk,
                    metadata: ["command": .string(command)]
                )
            }
            return approvalOrAsk(spec: spec, request: request, reason: classification.reason, summary: classification.summary)
        case .install:
            guard request.runMode == .fullAgent else {
                return deny(
                    reason: .installRequiresApproval,
                    summary: "Install commands are denied outside full-agent mode.",
                    toolName: spec.name,
                    risk: spec.risk,
                    metadata: ["command": .string(command)]
                )
            }
            return approvalOrAsk(spec: spec, request: request, reason: classification.reason, summary: classification.summary)
        case .network:
            guard !request.deniedScopes.contains(.network) else {
                return deny(
                    reason: .deniedScope,
                    summary: "Network commands are denied by scope policy.",
                    toolName: spec.name,
                    risk: .network,
                    metadata: ["scope": .string(AgentPermissionScope.network.rawValue)]
                )
            }
            guard request.runMode == .fullAgent else {
                return deny(
                    reason: .networkRequiresApproval,
                    summary: "Network commands are denied outside full-agent mode.",
                    toolName: spec.name,
                    risk: .network,
                    metadata: ["command": .string(command)]
                )
            }
            return approvalOrAsk(spec: spec, request: request, reason: classification.reason, summary: classification.summary)
        case .processControl:
            guard !request.deniedScopes.contains(.processControl) else {
                return deny(
                    reason: .deniedScope,
                    summary: "Process-control commands are denied by scope policy.",
                    toolName: spec.name,
                    risk: .processControl,
                    metadata: ["scope": .string(AgentPermissionScope.processControl.rawValue)]
                )
            }
            guard request.runMode == .fullAgent else {
                return deny(
                    reason: .processControlRequiresApproval,
                    summary: "Process-control commands are denied outside full-agent mode.",
                    toolName: spec.name,
                    risk: .processControl,
                    metadata: ["command": .string(command)]
                )
            }
            return approvalOrAsk(spec: spec, request: request, reason: classification.reason, summary: classification.summary)
        case .privileged:
            guard !request.deniedScopes.contains(.privileged) else {
                return deny(
                    reason: .deniedScope,
                    summary: "Privileged commands are denied by scope policy.",
                    toolName: spec.name,
                    risk: .privileged,
                    metadata: ["scope": .string(AgentPermissionScope.privileged.rawValue)]
                )
            }
            guard request.runMode == .fullAgent else {
                return deny(
                    reason: .privilegedCommandRequiresApproval,
                    summary: "Privileged commands are denied outside full-agent mode.",
                    toolName: spec.name,
                    risk: .privileged,
                    metadata: ["command": .string(command)]
                )
            }
            return approvalOrAsk(spec: spec, request: request, reason: classification.reason, summary: classification.summary)
        }
    }

    private func approvalOrAsk(
        spec: AgentToolSpec,
        request: AgentPermissionRequest,
        reason: AgentPermissionReason,
        summary: AgentRunText
    ) -> AgentPermissionDecision {
        if hasApprovalGrant(for: request) {
            return allow(
                reason: .approvalGrantMatched,
                summary: "A matching approval grant allows this tool request.",
                toolName: spec.name,
                risk: spec.risk
            )
        }
        return ask(
            reason: reason,
            summary: summary.text,
            toolName: spec.name,
            risk: spec.risk
        )
    }

    private func hasApprovalGrant(for request: AgentPermissionRequest) -> Bool {
        let digest = Self.approvalDigest(toolName: request.toolName, arguments: request.arguments)
        return request.approvalGrants.contains { grant in
            grant.matches(toolName: request.toolName, argumentDigest: digest, now: request.now)
        }
    }

    private func primaryPathArgument(for spec: AgentToolSpec, arguments: [String: String]) -> String? {
        switch spec.operationKind {
        case .fileRead, .fileList:
            return arguments["path"]
        case .fileSearch:
            return arguments["rootPath"]
        case .fileWriteDraft:
            return arguments["targetPath"]
        case .finiteCommand, .processStart:
            return arguments["workingDirectory"]
        default:
            return nil
        }
    }

    private func pathLikeArgumentValues(for spec: AgentToolSpec, arguments: [String: String]) -> [String] {
        spec.contract.pathLikeArgumentValues(in: arguments)
    }

    private func allow(
        reason: AgentPermissionReason,
        summary: String,
        toolName: String,
        risk: AgentToolRisk? = nil,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) -> AgentPermissionDecision {
        AgentPermissionDecision(
            kind: .allow,
            reason: reason,
            summary: AgentRunText(summary),
            toolName: toolName,
            risk: risk,
            metadata: metadata
        )
    }

    private func ask(
        reason: AgentPermissionReason,
        summary: String,
        toolName: String,
        risk: AgentToolRisk? = nil,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) -> AgentPermissionDecision {
        AgentPermissionDecision(
            kind: .ask,
            reason: reason,
            summary: AgentRunText(summary),
            toolName: toolName,
            risk: risk,
            metadata: metadata
        )
    }

    private func deny(
        reason: AgentPermissionReason,
        summary: String,
        toolName: String,
        risk: AgentToolRisk? = nil,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) -> AgentPermissionDecision {
        AgentPermissionDecision(
            kind: .deny,
            reason: reason,
            summary: AgentRunText(summary),
            toolName: toolName,
            risk: risk,
            metadata: metadata
        )
    }
}

extension AgentPermissionPolicy {
    nonisolated static var defaultSensitivePathRules: [AgentSensitivePathRule] {
        [
            AgentSensitivePathRule(
                id: "env-files",
                exactFilenames: [".env", ".env.local", ".env.development", ".env.production", ".env.test"],
                substrings: ["/.env."],
                summary: AgentRunText("Environment files often contain secrets.")
            ),
            AgentSensitivePathRule(
                id: "private-keys",
                exactFilenames: ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"],
                filenameSuffixes: [".pem", ".key", ".p12", ".pfx"],
                pathComponents: [".ssh"],
                summary: AgentRunText("Private keys and SSH material are sensitive.")
            ),
            AgentSensitivePathRule(
                id: "cloud-credentials",
                exactFilenames: ["credentials", "credentials.json", "service-account.json"],
                pathComponents: [".aws", ".azure", "gcloud"],
                substrings: ["service-account", "google_application_credentials"],
                summary: AgentRunText("Cloud credential files are sensitive.")
            ),
            AgentSensitivePathRule(
                id: "signing-keychains",
                filenameSuffixes: [".keychain", ".keychain-db", ".mobileprovision", ".cer", ".crt"],
                pathComponents: ["keychains"],
                summary: AgentRunText("Signing credentials and keychains are sensitive.")
            ),
            AgentSensitivePathRule(
                id: "package-auth",
                exactFilenames: [".npmrc", ".pypirc", ".netrc", "auth.json"],
                pathComponents: [".docker", ".cargo", ".gem", ".kube"],
                substrings: [".cargo/credentials", ".docker/config.json", ".kube/config"],
                summary: AgentRunText("Package-manager and service auth files are sensitive.")
            ),
            AgentSensitivePathRule(
                id: "hidden-credential-stores",
                pathComponents: [".gnupg", ".password-store", ".1password", "keyrings"],
                summary: AgentRunText("Hidden credential stores are sensitive.")
            )
        ]
    }
}
