import CryptoKit
import Foundation

nonisolated enum AgentEvidenceKind: String, Codable, Equatable, Sendable {
    case fileGrant = "file.grant"
    case folderList = "file.folder_list"
    case fileSearch = "file.search"
    case fileRead = "file.read"
    case commandOutput = "command.output"
    case localServer = "server.local"
    case processSnapshot = "process.snapshot"
    case processState = "process.state"
    case temporalContext = "temporal.context"
    case visualContext = "visual.context"
    case approval = "approval"
    case sideEffect = "side_effect"
    case terminalState = "terminal.state"
    case evidenceRequirement = "evidence.requirement"
    case finalAnswerSupport = "final_answer.support"
}

nonisolated enum AgentLocalEvidenceRequirementKind: String, Codable, Equatable, Sendable {
    case grantDiscovery = "grant_discovery"
    case directoryListing = "directory_listing"
    case fileContent = "file_content"
    case searchDiscovery = "search_discovery"
}

nonisolated struct AgentLocalEvidenceRequirement: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: AgentLocalEvidenceRequirementKind
    let targetPath: String?
    let targetIsDirectory: Bool
    let query: String?

    init(
        kind: AgentLocalEvidenceRequirementKind,
        targetPath: String? = nil,
        targetIsDirectory: Bool = false,
        query: String? = nil
    ) {
        let normalizedTarget = targetPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        self.kind = kind
        self.targetPath = normalizedTarget
        self.targetIsDirectory = targetIsDirectory
        self.query = query
        id = [
            kind.rawValue,
            normalizedTarget ?? "none",
            query ?? "none"
        ].joined(separator: ":")
    }
}

nonisolated enum AgentEvidenceTrustClass: String, Codable, Equatable, Sendable {
    case appControl = "app-control"
    case toolObservation = "tool-observation"
    case artifact = "artifact"
    case model = "model"
}

nonisolated enum AgentEvidencePrivacyClass: String, Codable, Equatable, Sendable {
    case controlPlane = "control-plane"
    case localFile = "local-file"
    case terminalOutput = "terminal-output"
    case localNetwork = "local-network"
    case visualContext = "visual-context"
    case modelOutput = "model-output"
}

nonisolated struct AgentEvidencePacket: Codable, Equatable, Identifiable, Sendable {
    var id: String { sourceID }

    let sourceID: String
    let kind: AgentEvidenceKind
    let summary: AgentRunText
    let body: AgentRunText?
    let artifactData: Data?
    let artifactMimeType: String
    let artifactFileExtension: String?
    let privacyClass: AgentEvidencePrivacyClass
    let trustClass: AgentEvidenceTrustClass
    let isTruncated: Bool
    let metadata: [String: AgentRunMetadataValue]

    init(
        sourceID: String,
        kind: AgentEvidenceKind,
        summary: AgentRunText,
        body: AgentRunText? = nil,
        artifactData: Data? = nil,
        artifactMimeType: String = "application/json",
        artifactFileExtension: String? = "json",
        privacyClass: AgentEvidencePrivacyClass,
        trustClass: AgentEvidenceTrustClass,
        isTruncated: Bool = false,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) {
        self.sourceID = sourceID
        self.kind = kind
        self.summary = summary
        self.body = body
        self.artifactData = artifactData
        self.artifactMimeType = artifactMimeType
        self.artifactFileExtension = artifactFileExtension
        self.privacyClass = privacyClass
        self.trustClass = trustClass
        self.isTruncated = isTruncated
        self.metadata = metadata
    }
}

nonisolated struct AgentFileSearchMatch: Codable, Equatable, Sendable {
    let path: String
    let preview: AgentRunText
    let score: Int

    init(path: String, preview: AgentRunText, score: Int) {
        self.path = path
        self.preview = preview
        self.score = score
    }
}

nonisolated struct AgentFolderEntry: Codable, Equatable, Sendable {
    let path: String
    let displayName: String
    let isDirectory: Bool
    let byteCount: Int?

    init(path: String, displayName: String, isDirectory: Bool, byteCount: Int? = nil) {
        self.path = path
        self.displayName = displayName
        self.isDirectory = isDirectory
        self.byteCount = byteCount
    }
}

nonisolated struct AgentLocalServerEvidence: Codable, Equatable, Sendable {
    let url: String?
    let port: Int?
    let isListening: Bool
    let httpStatusCode: Int?
    let processID: String?
    let workingDirectory: String?

    init(
        url: String? = nil,
        port: Int? = nil,
        isListening: Bool,
        httpStatusCode: Int? = nil,
        processID: String? = nil,
        workingDirectory: String? = nil
    ) {
        self.url = url
        self.port = port
        self.isListening = isListening
        self.httpStatusCode = httpStatusCode
        self.processID = processID
        self.workingDirectory = workingDirectory
    }
}

nonisolated struct AgentLocalListenerSnapshotRow: Codable, Equatable, Sendable {
    let port: Int
    let listenAddress: String?
    let pid: Int
    let executableName: String
    let workingDirectory: String?

    init(
        port: Int,
        listenAddress: String? = nil,
        pid: Int,
        executableName: String,
        workingDirectory: String? = nil
    ) {
        self.port = port
        self.listenAddress = listenAddress
        self.pid = pid
        self.executableName = executableName
        self.workingDirectory = workingDirectory
    }
}

nonisolated struct AgentLocalListenerSnapshotEvidence: Codable, Equatable, Sendable {
    let rows: [AgentLocalListenerSnapshotRow]
    let requestedLimit: Int
    let requestedPort: Int?
    let requestedRootPath: String?
    let source: String

    init(
        rows: [AgentLocalListenerSnapshotRow],
        requestedLimit: Int,
        requestedPort: Int? = nil,
        requestedRootPath: String? = nil,
        source: String = "/usr/sbin/lsof"
    ) {
        self.rows = rows
        self.requestedLimit = requestedLimit
        self.requestedPort = requestedPort
        self.requestedRootPath = requestedRootPath
        self.source = source
    }
}

nonisolated struct AgentProcessStateEvidence: Codable, Equatable, Sendable {
    let processID: String
    let status: String
    let command: String?
    let workingDirectory: String?
    let pid: Int?
    let exitCode: Int?

    init(
        processID: String,
        status: String,
        command: String? = nil,
        workingDirectory: String? = nil,
        pid: Int? = nil,
        exitCode: Int? = nil
    ) {
        self.processID = processID
        self.status = status
        self.command = command
        self.workingDirectory = workingDirectory
        self.pid = pid
        self.exitCode = exitCode
    }
}

nonisolated struct AgentProcessSnapshotRow: Codable, Equatable, Sendable {
    let pid: Int
    let cpuPercent: Double
    let memoryPercent: Double
    let executableName: String

    init(pid: Int, cpuPercent: Double, memoryPercent: Double, executableName: String) {
        self.pid = pid
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.executableName = executableName
    }
}

nonisolated struct AgentProcessSnapshotEvidence: Codable, Equatable, Sendable {
    let rows: [AgentProcessSnapshotRow]
    let requestedLimit: Int
    let source: String

    init(rows: [AgentProcessSnapshotRow], requestedLimit: Int, source: String = "/bin/ps") {
        self.rows = rows
        self.requestedLimit = requestedLimit
        self.source = source
    }
}

nonisolated struct AgentGrantInventoryEntry: Codable, Equatable, Sendable {
    let grantID: String
    let path: String
    let displayName: String
    let isDirectory: Bool

    init(grantID: String, path: String, displayName: String, isDirectory: Bool) {
        self.grantID = grantID
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.displayName = displayName
        self.isDirectory = isDirectory
    }
}

nonisolated struct AgentGrantInventorySnapshot: Codable, Equatable, Sendable {
    let entries: [AgentGrantInventoryEntry]
    let source: String

    init(entries: [AgentGrantInventoryEntry], source: String = "app-runtime") {
        self.entries = entries
        self.source = source
    }
}

nonisolated struct AgentGrantInventoryProvider: Sendable {
    init() {}

    func snapshot(grants: [AgentLocalFileGrant]) -> AgentGrantInventorySnapshot {
        AgentGrantInventorySnapshot(
            entries: grants
                .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
                .map { grant in
                    AgentGrantInventoryEntry(
                        grantID: grant.id.uuidString,
                        path: grant.path,
                        displayName: grant.url.lastPathComponent,
                        isDirectory: grant.isDirectory
                    )
                }
        )
    }

    static func sourceID(runID: UUID) -> String {
        "file-grants:\(runID.uuidString)"
    }

    func observation(
        snapshot: AgentGrantInventorySnapshot,
        evidenceID: UUID,
        artifactID: UUID? = nil,
        characterLimit: Int
    ) -> AgentRunText {
        var lines = [
            "Grant inventory",
            "source: \(snapshot.source)",
            "evidenceID: \(evidenceID.uuidString)"
        ]
        if let artifactID {
            lines.append("artifactID: \(artifactID.uuidString)")
        }
        lines.append("entryCount: \(snapshot.entries.count)")
        if snapshot.entries.isEmpty {
            lines.append("No local files or folders have been granted.")
        } else {
            for entry in snapshot.entries {
                let kind = entry.isDirectory ? "Folder" : "File"
                lines.append("- \(kind): \(entry.path)")
            }
        }
        return AgentRunText(lines.joined(separator: "\n"), characterLimit: characterLimit)
    }
}

nonisolated enum AgentEvidenceClaimType: String, Codable, Equatable, Sendable {
    case fileGrantListed = "file_grant_listed"
    case processSnapshotRecorded = "process_snapshot_recorded"
    case localListenerSnapshotRecorded = "local_listener_snapshot_recorded"
    case localFileObserved = "local_file_observed"
    case commandOutputRecorded = "command_output_recorded"
    case sideEffectRecorded = "side_effect_recorded"
    case temporalContextRecorded = "temporal_context_recorded"
    case visualContextRecorded = "visual_context_recorded"
    case fileExists = "file_exists"
    case fileSearchFound = "file_search_found"
    case fileChanged = "file_changed"
    case commandRan = "command_ran"
    case commandSucceeded = "command_succeeded"
    case commandFailed = "command_failed"
    case processRunning = "process_running"
    case portListening = "port_listening"
    case urlResponds = "url_responds"
    case approvalResolved = "approval_resolved"
    case sideEffectCompleted = "side_effect_completed"
    case taskCompleted = "task_completed"
    case taskCanceled = "task_canceled"
    case unsupported
}

nonisolated struct AgentEvidenceClaim: Codable, Equatable, Sendable {
    let type: AgentEvidenceClaimType
    let target: String?
    let qualifiers: [String: AgentRunMetadataValue]

    init(
        type: AgentEvidenceClaimType,
        target: String? = nil,
        qualifiers: [String: AgentRunMetadataValue] = [:]
    ) {
        self.type = type
        self.target = target
        self.qualifiers = qualifiers
    }

    static func fileExists(_ path: String) -> Self {
        Self(type: .fileExists, target: path)
    }

    static func fileSearchFound(_ path: String) -> Self {
        Self(type: .fileSearchFound, target: path)
    }

    static func fileChanged(_ path: String) -> Self {
        Self(type: .fileChanged, target: path)
    }

    static func commandSucceeded(_ command: String? = nil) -> Self {
        Self(type: .commandSucceeded, target: command)
    }

    static func portListening(_ port: Int) -> Self {
        Self(type: .portListening, target: String(port), qualifiers: ["port": .int(port)])
    }

    static func urlResponds(_ url: String) -> Self {
        Self(type: .urlResponds, target: url)
    }
}

nonisolated enum AgentEvidenceSupportStatus: String, Codable, Equatable, Sendable {
    case supported
    case needsEvidence
    case contradicted
    case unsupported
}

nonisolated struct AgentEvidenceSupportDecision: Codable, Equatable, Sendable {
    let claim: AgentEvidenceClaim
    let status: AgentEvidenceSupportStatus
    let evidenceIDs: [UUID]
    let summary: AgentRunText

    init(
        claim: AgentEvidenceClaim,
        status: AgentEvidenceSupportStatus,
        evidenceIDs: [UUID] = [],
        summary: AgentRunText
    ) {
        self.claim = claim
        self.status = status
        self.evidenceIDs = evidenceIDs
        self.summary = summary
    }
}

nonisolated struct AgentFinalAnswerSupportRecord: Codable, Equatable, Sendable {
    let answer: AgentRunText
    let answerHash: String
    let decisions: [AgentEvidenceSupportDecision]
    let evidenceIDs: [UUID]
    let supportEvidenceID: UUID?

    var canAnswer: Bool {
        decisions.allSatisfy { $0.status == .supported }
    }
}

nonisolated struct AgentEvidenceContextPacket: Codable, Equatable, Sendable {
    let evidenceID: UUID
    let sourceID: String
    let kind: AgentEvidenceKind
    let summary: AgentRunText
    let artifactID: UUID?
    let keyFields: [String: AgentRunMetadataValue]
}

actor AgentEvidenceRecorder {
    private let store: AgentRunStore
    private let encoder: JSONEncoder

    init(store: AgentRunStore) {
        self.store = store
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    @discardableResult
    func record(_ packet: AgentEvidencePacket, runID: UUID, stepID: UUID? = nil, createdAt: Date = Date()) async throws -> AgentRunEvidenceRecord {
        let artifactID: UUID?
        if let artifactData = packet.artifactData ?? packet.body?.text.data(using: .utf8) {
            let artifact = try await store.recordArtifact(
                runID: runID,
                stepID: stepID,
                kind: packet.kind.rawValue,
                mimeType: packet.artifactMimeType,
                fileExtension: packet.artifactFileExtension,
                data: artifactData,
                summary: packet.summary,
                createdAt: createdAt
            )
            artifactID = artifact.artifactID
        } else {
            artifactID = nil
        }

        var metadata = packet.metadata
        metadata["privacyClass"] = .string(packet.privacyClass.rawValue)
        metadata["trustClass"] = .string(packet.trustClass.rawValue)
        metadata["isTruncated"] = .bool(packet.isTruncated)

        return try await store.recordEvidence(
            runID: runID,
            stepID: stepID,
            sourceID: packet.sourceID,
            kind: packet.kind.rawValue,
            summary: packet.summary,
            artifactID: artifactID,
            metadata: metadata,
            createdAt: createdAt
        )
    }

    @discardableResult
    func recordFileGrants(
        runID: UUID,
        stepID: UUID? = nil,
        grants: [AgentLocalFileGrant]
    ) async throws -> AgentRunEvidenceRecord {
        let provider = AgentGrantInventoryProvider()
        let snapshot = provider.snapshot(grants: grants)
        let entries = snapshot.entries
        let paths = entries.map(\.path)
        let displayNames = entries.map(\.displayName)
        let kinds = entries.map { "\($0.path)=\($0.isDirectory ? "folder" : "file")" }
        return try await record(
            AgentEvidencePacket(
                sourceID: AgentGrantInventoryProvider.sourceID(runID: runID),
                kind: .fileGrant,
                summary: AgentRunText("Listed \(entries.count) granted local location(s)."),
                artifactData: try encoder.encode(snapshot),
                privacyClass: .localFile,
                trustClass: .appControl,
                metadata: [
                    "grantCount": .int(entries.count),
                    "entryCount": .int(entries.count),
                    "path": .string(paths.first ?? ""),
                    "paths": .string(paths.joined(separator: "\n")),
                    "displayNames": .string(displayNames.joined(separator: "\n")),
                    "grantIDs": .string(entries.map(\.grantID).joined(separator: "\n")),
                    "kinds": .string(kinds.joined(separator: "\n")),
                    "source": .string(snapshot.source)
                ]
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordFileSearch(
        runID: UUID,
        stepID: UUID? = nil,
        query: String,
        matches: [AgentFileSearchMatch],
        isTruncated: Bool = false,
        rootPath: String? = nil,
        filenameOnly: Bool = false
    ) async throws -> AgentRunEvidenceRecord {
        let sorted = matches.sorted {
            if $0.score == $1.score {
                return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
            return $0.score > $1.score
        }
        let data = try encoder.encode(sorted)
        let paths = sorted.map(\.path)
        return try await record(
            AgentEvidencePacket(
                sourceID: "file-search:\(query)",
                kind: .fileSearch,
                summary: AgentRunText("Found \(matches.count) file search result(s) for \(query)."),
                artifactData: data,
                privacyClass: .localFile,
                trustClass: .toolObservation,
                isTruncated: isTruncated,
                metadata: [
                    "query": .string(query),
                    "matchCount": .int(matches.count),
                    "paths": .string(paths.joined(separator: "\n")),
                    "topPath": .string(paths.first ?? ""),
                    "rootPath": .string(rootPath ?? ""),
                    "filenameOnly": .bool(filenameOnly)
                ]
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordVisualContext(
        runID: UUID,
        stepID: UUID? = nil,
        attachment: AgentKernelModelAttachment
    ) async throws -> AgentRunEvidenceRecord {
        let ocrText = attachment.metadata["ocrText"]?.stringValue ?? ""
        let source = attachment.metadata["source"]?.stringValue ?? "attachment"
        let isTruncated = ocrText.count > AgentKernelBoundedText.defaultLimit
        return try await record(
            AgentEvidencePacket(
                sourceID: "visual-context:\(attachment.id.uuidString)",
                kind: .visualContext,
                summary: AgentRunText("Recorded visual context for \(attachment.label)."),
                body: ocrText.isEmpty ? nil : AgentRunText(ocrText, characterLimit: AgentKernelBoundedText.defaultLimit),
                privacyClass: .visualContext,
                trustClass: .appControl,
                isTruncated: isTruncated,
                metadata: [
                    "attachmentID": .string(attachment.id.uuidString),
                    "label": .string(attachment.label),
                    "source": .string(source),
                    "modality": .string(attachment.modality.rawValue),
                    "hasOCRText": .bool(!ocrText.isEmpty),
                    "hasImageInput": .bool(attachment.modality == .image),
                    "ocrCharacters": .int(ocrText.count)
                ]
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordFolderList(
        runID: UUID,
        stepID: UUID? = nil,
        folderPath: String,
        entries: [AgentFolderEntry],
        isTruncated: Bool = false
    ) async throws -> AgentRunEvidenceRecord {
        let data = try encoder.encode(entries)
        let largestFile = entries
            .filter { !$0.isDirectory }
            .max { lhs, rhs in
                let lhsBytes = lhs.byteCount ?? -1
                let rhsBytes = rhs.byteCount ?? -1
                if lhsBytes == rhsBytes {
                    return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedDescending
                }
                return lhsBytes < rhsBytes
            }
        var metadata: [String: AgentRunMetadataValue] = [
            "path": .string(folderPath),
            "entryCount": .int(entries.count),
            "paths": .string(entries.map(\.path).joined(separator: "\n"))
        ]
        if let largestFile {
            metadata["topFilePath"] = .string(largestFile.path)
            if let byteCount = largestFile.byteCount {
                metadata["topFileByteCount"] = .int(byteCount)
            }
        }
        let largestByExtension = Dictionary(grouping: entries.filter { !$0.isDirectory }) { entry in
            URL(fileURLWithPath: entry.path).pathExtension.lowercased()
        }
        for (ext, candidates) in largestByExtension where !ext.isEmpty {
            guard let largest = candidates.max(by: { lhs, rhs in
                let lhsBytes = lhs.byteCount ?? -1
                let rhsBytes = rhs.byteCount ?? -1
                if lhsBytes == rhsBytes {
                    return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedDescending
                }
                return lhsBytes < rhsBytes
            }) else {
                continue
            }
            let normalizedExt = ext.replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
            metadata["topFilePath_\(normalizedExt)"] = .string(largest.path)
            if let byteCount = largest.byteCount {
                metadata["topFileByteCount_\(normalizedExt)"] = .int(byteCount)
            }
        }
        return try await record(
            AgentEvidencePacket(
                sourceID: "folder-list:\(folderPath)",
                kind: .folderList,
                summary: AgentRunText("Listed \(entries.count) item(s) in \(folderPath)."),
                artifactData: data,
                privacyClass: .localFile,
                trustClass: .toolObservation,
                isTruncated: isTruncated,
                metadata: metadata
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordFileRead(
        runID: UUID,
        stepID: UUID? = nil,
        path: String,
        content: String,
        isTruncated: Bool = false
    ) async throws -> AgentRunEvidenceRecord {
        let data = Data(content.utf8)
        return try await record(
            AgentEvidencePacket(
                sourceID: "file-read:\(path)",
                kind: .fileRead,
                summary: AgentRunText("Read \(path)."),
                body: AgentRunText(content),
                artifactMimeType: "text/plain",
                artifactFileExtension: "txt",
                privacyClass: .localFile,
                trustClass: .toolObservation,
                isTruncated: isTruncated,
                metadata: [
                    "path": .string(path),
                    "exists": .bool(true),
                    "byteCount": .int(data.count),
                    "contentHash": .string(AgentEvidenceHasher.sha256Hex(data))
                ]
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordCommandOutput(
        runID: UUID,
        stepID: UUID? = nil,
        output: AgentCommandExecutionOutput,
        claimTags: [String] = []
    ) async throws -> AgentRunEvidenceRecord {
        let data = try encoder.encode(output)
        return try await record(
            AgentEvidencePacket(
                sourceID: "command:\(AgentEvidenceHasher.sha256Hex(Data(output.command.utf8)).prefix(12))",
                kind: .commandOutput,
                summary: output.summary,
                artifactData: data,
                privacyClass: .terminalOutput,
                trustClass: .toolObservation,
                isTruncated: output.stdout.isTruncated || output.stderr.isTruncated,
                metadata: [
                    "command": .string(output.command),
                    "workingDirectory": .string(output.workingDirectory),
                    "exitCode": .int(Int(output.exitCode ?? -1)),
                    "didTimeOut": .bool(output.didTimeOut),
                    "claimTags": .string(claimTags.sorted().joined(separator: ","))
                ]
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordLocalServer(
        runID: UUID,
        stepID: UUID? = nil,
        server: AgentLocalServerEvidence
    ) async throws -> AgentRunEvidenceRecord {
        let source = server.url.map { "local-server:\($0)" }
            ?? server.port.map { "local-server-port:\($0)" }
            ?? "local-server:\(UUID().uuidString)"
        var metadata: [String: AgentRunMetadataValue] = [
            "isListening": .bool(server.isListening)
        ]
        if let url = server.url { metadata["url"] = .string(url) }
        if let port = server.port { metadata["port"] = .int(port) }
        if let httpStatusCode = server.httpStatusCode { metadata["httpStatusCode"] = .int(httpStatusCode) }
        if let processID = server.processID { metadata["processID"] = .string(processID) }
        if let workingDirectory = server.workingDirectory { metadata["workingDirectory"] = .string(workingDirectory) }

        return try await record(
            AgentEvidencePacket(
                sourceID: source,
                kind: .localServer,
                summary: AgentRunText(server.isListening ? "Local server listener recorded." : "Local server target is not listening."),
                artifactData: try encoder.encode(server),
                privacyClass: .localNetwork,
                trustClass: .toolObservation,
                metadata: metadata
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordLocalListenerSnapshot(
        runID: UUID,
        stepID: UUID? = nil,
        snapshot: AgentLocalListenerSnapshotEvidence
    ) async throws -> AgentRunEvidenceRecord {
        var metadata: [String: AgentRunMetadataValue] = [
            "isListening": .bool(!snapshot.rows.isEmpty),
            "rowCount": .int(snapshot.rows.count),
            "requestedLimit": .int(snapshot.requestedLimit),
            "source": .string(snapshot.source)
        ]
        if let requestedPort = snapshot.requestedPort {
            metadata["requestedPort"] = .int(requestedPort)
            metadata["port"] = .int(requestedPort)
        }
        if let requestedRootPath = snapshot.requestedRootPath {
            metadata["requestedRootPath"] = .string(requestedRootPath)
        }
        if let top = snapshot.rows.first {
            metadata["port"] = .int(top.port)
            metadata["processID"] = .string(String(top.pid))
            metadata["pid"] = .int(top.pid)
            metadata["executableName"] = .string(top.executableName)
            if let listenAddress = top.listenAddress {
                metadata["listenAddress"] = .string(listenAddress)
            }
            if let workingDirectory = top.workingDirectory {
                metadata["workingDirectory"] = .string(workingDirectory)
            }
        }

        let scopedText = snapshot.requestedPort.map { " for port \($0)" } ?? ""
        return try await record(
            AgentEvidencePacket(
                sourceID: "local-listener-snapshot:\(runID.uuidString)",
                kind: .localServer,
                summary: AgentRunText("Recorded \(snapshot.rows.count) local listener row(s)\(scopedText)."),
                artifactData: try encoder.encode(snapshot),
                privacyClass: .localNetwork,
                trustClass: .toolObservation,
                metadata: metadata
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordProcessState(
        runID: UUID,
        stepID: UUID? = nil,
        process: AgentProcessStateEvidence
    ) async throws -> AgentRunEvidenceRecord {
        var metadata: [String: AgentRunMetadataValue] = [
            "processID": .string(process.processID),
            "status": .string(process.status)
        ]
        if let command = process.command { metadata["command"] = .string(command) }
        if let workingDirectory = process.workingDirectory { metadata["workingDirectory"] = .string(workingDirectory) }
        if let pid = process.pid { metadata["pid"] = .int(pid) }
        if let exitCode = process.exitCode { metadata["exitCode"] = .int(exitCode) }

        return try await record(
            AgentEvidencePacket(
                sourceID: "process:\(process.processID)",
                kind: .processState,
                summary: AgentRunText("Process \(process.processID) is \(process.status)."),
                artifactData: try encoder.encode(process),
                privacyClass: .terminalOutput,
                trustClass: .toolObservation,
                metadata: metadata
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordProcessSnapshot(
        runID: UUID,
        stepID: UUID? = nil,
        snapshot: AgentProcessSnapshotEvidence
    ) async throws -> AgentRunEvidenceRecord {
        var metadata: [String: AgentRunMetadataValue] = [
            "rowCount": .int(snapshot.rows.count),
            "requestedLimit": .int(snapshot.requestedLimit),
            "source": .string(snapshot.source)
        ]
        if let top = snapshot.rows.first {
            metadata["topPID"] = .int(top.pid)
            metadata["topExecutable"] = .string(top.executableName)
            metadata["topCPUPercent"] = .double(top.cpuPercent)
            metadata["topMemoryPercent"] = .double(top.memoryPercent)
        }

        return try await record(
            AgentEvidencePacket(
                sourceID: "process-snapshot:\(runID.uuidString)",
                kind: .processSnapshot,
                summary: AgentRunText("Recorded \(snapshot.rows.count) running process snapshot row(s)."),
                artifactData: try encoder.encode(snapshot),
                privacyClass: .terminalOutput,
                trustClass: .toolObservation,
                metadata: metadata
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordTemporalContext(
        runID: UUID,
        stepID: UUID? = nil,
        context: AgentTemporalContext
    ) async throws -> AgentRunEvidenceRecord {
        try await record(
            AgentEvidencePacket(
                sourceID: "temporal-context:\(runID.uuidString)",
                kind: .temporalContext,
                summary: AgentRunText("Recorded app-owned current date/time context."),
                body: AgentRunText(context.modelObservation),
                artifactMimeType: "text/plain",
                artifactFileExtension: "txt",
                privacyClass: .controlPlane,
                trustClass: .appControl,
                metadata: [
                    "currentDate": .string(context.currentDate),
                    "localTime": .string(context.localTime),
                    "weekday": .string(context.weekday),
                    "timeZone": .string(context.timeZoneIdentifier),
                    "utcOffset": .string(context.utcOffset),
                    "source": .string(context.source)
                ]
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordSideEffect(
        runID: UUID,
        stepID: UUID? = nil,
        sideEffect: AgentRunSideEffectRecord
    ) async throws -> AgentRunEvidenceRecord {
        var metadata = sideEffect.metadata
        metadata["sideEffectID"] = .string(sideEffect.sideEffectID.uuidString)
        metadata["status"] = .string(sideEffect.status.rawValue)
        metadata["kind"] = .string(sideEffect.kind.rawValue)
        if let proposalHash = sideEffect.proposalHash {
            metadata["proposalHash"] = .string(proposalHash)
        }
        if let afterArtifactID = sideEffect.afterArtifactID {
            metadata["afterArtifactID"] = .string(afterArtifactID.uuidString)
        }

        return try await record(
            AgentEvidencePacket(
                sourceID: "side-effect:\(sideEffect.sideEffectID.uuidString)",
                kind: .sideEffect,
                summary: AgentRunText("Side effect \(sideEffect.kind.rawValue) is \(sideEffect.status.rawValue)."),
                artifactData: try encoder.encode(sideEffect),
                privacyClass: .controlPlane,
                trustClass: .appControl,
                metadata: metadata
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordTerminalState(
        runID: UUID,
        stepID: UUID? = nil,
        status: AgentRunStatus,
        reason: AgentRunText? = nil
    ) async throws -> AgentRunEvidenceRecord {
        try await record(
            AgentEvidencePacket(
                sourceID: "terminal:\(runID.uuidString):\(status.rawValue)",
                kind: .terminalState,
                summary: reason ?? AgentRunText("Run status is \(status.rawValue)."),
                privacyClass: .controlPlane,
                trustClass: .appControl,
                metadata: ["status": .string(status.rawValue)]
            ),
            runID: runID,
            stepID: stepID
        )
    }

    @discardableResult
    func recordEvidenceRequirements(
        runID: UUID,
        stepID: UUID? = nil,
        requirements: [AgentLocalEvidenceRequirement]
    ) async throws -> AgentRunEvidenceRecord {
        let data = try encoder.encode(requirements)
        let targets = requirements.compactMap(\.targetPath)
        let kinds = requirements.map(\.kind.rawValue)
        return try await record(
            AgentEvidencePacket(
                sourceID: "evidence-requirements:\(runID.uuidString)",
                kind: .evidenceRequirement,
                summary: AgentRunText("Recorded \(requirements.count) local evidence requirement(s)."),
                artifactData: data,
                privacyClass: .controlPlane,
                trustClass: .appControl,
                metadata: [
                    "requirementCount": .int(requirements.count),
                    "requirementKinds": .string(kinds.joined(separator: ",")),
                    "targetPaths": .string(targets.joined(separator: "\n")),
                    "targetPath": .string(targets.first ?? ""),
                    "targetIsDirectory": .bool(requirements.first?.targetIsDirectory ?? false)
                ]
            ),
            runID: runID,
            stepID: stepID
        )
    }
}

nonisolated enum AgentEvidenceHasher {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated struct AgentEvidenceController: Sendable {
    init() {}

    func verify(_ claim: AgentEvidenceClaim, evidence: [AgentRunEvidenceRecord]) -> AgentEvidenceSupportDecision {
        switch claim.type {
        case .fileGrantListed:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.fileGrant],
                predicate: { record in
                    matchesTarget(record.stringMetadata("path"), claim.target)
                        || matchesLine(in: record.stringMetadata("paths"), target: claim.target)
                        || matchesLine(in: record.stringMetadata("displayNames"), target: claim.target)
                },
                missing: "File-grant claims need grant-list evidence."
            )
        case .processSnapshotRecorded:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.processSnapshot],
                predicate: { record in
                    (record.intMetadata("rowCount") ?? -1) >= 0
                        && (matchesTarget(record.stringMetadata("topExecutable"), claim.target)
                            || matchesTarget(record.intMetadata("topPID").map(String.init), claim.target))
                },
                missing: "Process snapshot claims need process snapshot evidence."
            )
        case .localListenerSnapshotRecorded:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.localServer],
                predicate: { record in
                    if let target = claim.target, let port = Int(target) {
                        return record.intMetadata("port") == port
                    }
                    return matchesTarget(record.stringMetadata("url"), claim.target)
                        || matchesTarget(record.intMetadata("port").map(String.init), claim.target)
                },
                missing: "Local listener claims need listener snapshot evidence."
            )
        case .localFileObserved:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.fileRead, .fileSearch, .folderList],
                predicate: { record in
                    guard let target = claim.target, !target.isEmpty else { return true }
                    return record.stringMetadata("path") == target
                        || record.stringMetadata("topPath") == target
                        || record.stringMetadata("paths")?.split(separator: "\n").map(String.init).contains(target) == true
                },
                missing: "Local-file claims need file evidence."
            )
        case .commandOutputRecorded:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.commandOutput],
                predicate: { record in matchesTarget(record.stringMetadata("command"), claim.target) },
                missing: "Command-output claims need command output evidence."
            )
        case .sideEffectRecorded:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.sideEffect],
                predicate: { record in
                    matchesTarget(record.stringMetadata("sideEffectID"), claim.target)
                        || matchesTarget(record.stringMetadata("targetPath"), claim.target)
                },
                missing: "Side-effect claims need side-effect evidence."
            )
        case .temporalContextRecorded:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.temporalContext],
                predicate: { record in matchesTarget(record.stringMetadata("currentDate"), claim.target) },
                missing: "Temporal claims need temporal context evidence."
            )
        case .visualContextRecorded:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.visualContext],
                predicate: { record in matchesTarget(record.stringMetadata("source"), claim.target) },
                missing: "Visual-context claims need visual context evidence."
            )
        case .fileExists:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.fileRead, .sideEffect],
                predicate: { record in
                    matchesTarget(record.stringMetadata("path"), claim.target)
                        && (record.boolMetadata("exists") == true || record.stringMetadata("status") == AgentRunSideEffectStatus.completed.rawValue)
                },
                missing: "File existence needs file-read or completed write evidence."
            )
        case .fileSearchFound:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.fileSearch, .folderList],
                predicate: { record in
                    guard let target = claim.target else { return false }
                    return record.stringMetadata("paths")?.split(separator: "\n").map(String.init).contains(target) == true
                        || record.stringMetadata("topPath") == target
                },
                missing: "File search needs evidence containing the target path."
            )
        case .fileChanged:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.sideEffect],
                predicate: { record in
                    matchesTarget(record.stringMetadata("targetPath") ?? record.stringMetadata("path"), claim.target)
                        && record.stringMetadata("kind") == AgentRunSideEffectKind.fileWrite.rawValue
                        && record.stringMetadata("status") == AgentRunSideEffectStatus.completed.rawValue
                },
                missing: "File change needs completed file-write side-effect evidence."
            )
        case .commandRan:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.commandOutput, .sideEffect],
                predicate: { record in matchesTarget(record.stringMetadata("command"), claim.target) },
                missing: "Command claims need command output evidence."
            )
        case .commandSucceeded:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.commandOutput],
                predicate: { record in
                    matchesTarget(record.stringMetadata("command"), claim.target)
                        && record.boolMetadata("didTimeOut") != true
                        && record.intMetadata("exitCode") == 0
                },
                missing: "Command success needs command evidence with exit code 0."
            )
        case .commandFailed:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.commandOutput],
                predicate: { record in
                    matchesTarget(record.stringMetadata("command"), claim.target)
                        && (record.boolMetadata("didTimeOut") == true || (record.intMetadata("exitCode") ?? 0) != 0)
                },
                missing: "Command failure needs failed or timed-out command evidence."
            )
        case .processRunning:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.processState, .processSnapshot, .sideEffect],
                predicate: { record in
                    if record.kind == AgentEvidenceKind.processSnapshot.rawValue {
                        return (record.intMetadata("rowCount") ?? 0) > 0
                            && (matchesTarget(record.stringMetadata("topExecutable"), claim.target)
                                || matchesTarget(record.intMetadata("topPID").map(String.init), claim.target))
                    }
                    return matchesTarget(record.stringMetadata("processID"), claim.target)
                        && (record.stringMetadata("status") == "running"
                            || record.stringMetadata("status") == AgentRunSideEffectStatus.completed.rawValue)
                },
                missing: "Process-running claims need running process evidence."
            )
        case .portListening:
            let port = claim.qualifiers["port"]?.intValue ?? claim.target.flatMap(Int.init)
            return matching(
                claim,
                evidence: evidence,
                kinds: [.localServer, .processState],
                predicate: { record in
                    record.intMetadata("port") == port && record.boolMetadata("isListening") == true
                },
                missing: "Port-listening claims need localhost listener evidence."
            )
        case .urlResponds:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.localServer],
                predicate: { record in
                    matchesTarget(record.stringMetadata("url"), claim.target)
                        && record.intMetadata("httpStatusCode") != nil
                },
                missing: "URL-response claims need localhost HTTP response evidence."
            )
        case .approvalResolved:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.approval, .sideEffect],
                predicate: { record in
                    matchesTarget(record.stringMetadata("waitID"), claim.target)
                        || matchesTarget(record.stringMetadata("sideEffectID"), claim.target)
                },
                missing: "Approval claims need approval or side-effect evidence."
            )
        case .sideEffectCompleted:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.sideEffect],
                predicate: { record in
                    matchesTarget(record.stringMetadata("sideEffectID"), claim.target)
                        && record.stringMetadata("status") == AgentRunSideEffectStatus.completed.rawValue
                },
                missing: "Side-effect completion claims need completed side-effect evidence."
            )
        case .taskCompleted:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.terminalState],
                predicate: { $0.stringMetadata("status") == AgentRunStatus.completed.rawValue },
                missing: "Task completion needs completed terminal-state evidence."
            )
        case .taskCanceled:
            return matching(
                claim,
                evidence: evidence,
                kinds: [.terminalState],
                predicate: { $0.stringMetadata("status") == AgentRunStatus.canceled.rawValue },
                missing: "Task cancellation needs canceled terminal-state evidence."
            )
        case .unsupported:
            return AgentEvidenceSupportDecision(
                claim: claim,
                status: .unsupported,
                summary: AgentRunText("Unsupported claim type.")
            )
        }
    }

    func verify(_ claims: [AgentEvidenceClaim], evidence: [AgentRunEvidenceRecord]) -> [AgentEvidenceSupportDecision] {
        claims.map { verify($0, evidence: evidence) }
    }

    func contextPackets(
        from evidence: [AgentRunEvidenceRecord],
        query: String? = nil,
        maxPackets: Int = 12
    ) -> [AgentEvidenceContextPacket] {
        let terms = Set((query ?? "")
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "_" && $0 != "-" }
            .map(String.init)
            .filter { $0.count >= 2 })

        let scored = evidence.compactMap { record -> (Int, AgentEvidenceContextPacket)? in
            guard let kind = AgentEvidenceKind(rawValue: record.kind) else { return nil }
            let fieldText = [
                record.sourceID,
                record.summary.text,
                record.stringMetadata("path") ?? "",
                record.stringMetadata("paths") ?? "",
                record.stringMetadata("displayNames") ?? "",
                record.stringMetadata("url") ?? "",
                record.stringMetadata("command") ?? "",
                record.stringMetadata("topExecutable") ?? ""
            ].joined(separator: "\n").lowercased()
            let termScore = terms.isEmpty ? 1 : terms.reduce(0) { partial, term in
                partial + (fieldText.contains(term) ? 1 : 0)
            }
            guard termScore > 0 else { return nil }
            return (
                score(kind: kind) + termScore,
                AgentEvidenceContextPacket(
                    evidenceID: record.evidenceID,
                    sourceID: record.sourceID,
                    kind: kind,
                    summary: record.summary,
                    artifactID: record.artifactID,
                    keyFields: keyFields(record)
                )
            )
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.0 == rhs.0 {
                    return lhs.1.sourceID < rhs.1.sourceID
                }
                return lhs.0 > rhs.0
            }
            .prefix(max(1, maxPackets))
            .map(\.1)
    }

    private func matching(
        _ claim: AgentEvidenceClaim,
        evidence: [AgentRunEvidenceRecord],
        kinds: [AgentEvidenceKind],
        predicate: (AgentRunEvidenceRecord) -> Bool,
        missing: String
    ) -> AgentEvidenceSupportDecision {
        let matches = evidence.filter { record in
            guard let kind = AgentEvidenceKind(rawValue: record.kind), kinds.contains(kind) else {
                return false
            }
            return predicate(record)
        }
        guard !matches.isEmpty else {
            return AgentEvidenceSupportDecision(
                claim: claim,
                status: .needsEvidence,
                summary: AgentRunText(missing)
            )
        }
        return AgentEvidenceSupportDecision(
            claim: claim,
            status: .supported,
            evidenceIDs: matches.map(\.evidenceID),
            summary: AgentRunText("Claim is supported by \(matches.count) evidence record(s).")
        )
    }

    private func matchesTarget(_ value: String?, _ target: String?) -> Bool {
        guard let target, !target.isEmpty else { return true }
        return value == target
    }

    private func matchesLine(in value: String?, target: String?) -> Bool {
        guard let target, !target.isEmpty else { return value != nil }
        guard let value else { return false }
        return value.split(separator: "\n").map(String.init).contains(target)
    }

    private func score(kind: AgentEvidenceKind) -> Int {
        switch kind {
        case .fileRead, .fileSearch, .localServer, .sideEffect:
            100
        case .commandOutput, .processSnapshot, .processState, .temporalContext, .folderList:
            80
        case .terminalState, .approval, .evidenceRequirement:
            60
        case .fileGrant, .visualContext, .finalAnswerSupport:
            40
        }
    }

    private func keyFields(_ record: AgentRunEvidenceRecord) -> [String: AgentRunMetadataValue] {
        var fields: [String: AgentRunMetadataValue] = [:]
        for key in [
            "path", "paths", "topPath", "query", "command", "workingDirectory", "exitCode",
            "didTimeOut", "port", "url", "httpStatusCode", "isListening", "processID",
            "pid", "listenAddress", "requestedPort", "requestedRootPath", "executableName",
            "rowCount", "topPID", "topExecutable", "topCPUPercent", "topMemoryPercent",
            "status", "sideEffectID", "targetPath", "operation", "currentDate", "localTime",
            "weekday", "timeZone", "utcOffset", "source", "grantCount", "entryCount",
            "displayNames", "grantIDs", "kinds"
        ] {
            if let value = record.metadata[key] {
                fields[key] = value
            }
        }
        return fields
    }
}

actor AgentFinalAnswerSupportRecorder {
    private let store: AgentRunStore
    private let evidenceRecorder: AgentEvidenceRecorder
    private let controller: AgentEvidenceController
    private let encoder: JSONEncoder

    init(
        store: AgentRunStore,
        evidenceRecorder: AgentEvidenceRecorder,
        controller: AgentEvidenceController = AgentEvidenceController()
    ) {
        self.store = store
        self.evidenceRecorder = evidenceRecorder
        self.controller = controller
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func recordSupport(
        runID: UUID,
        stepID: UUID? = nil,
        answer: AgentRunText,
        claims: [AgentEvidenceClaim]
    ) async throws -> AgentFinalAnswerSupportRecord {
        let evidence = await store.evidenceArtifactSummary(runID: runID).evidence
        let decisions = controller.verify(claims, evidence: evidence)
        let evidenceIDs = Array(Set(decisions.flatMap(\.evidenceIDs))).sorted { $0.uuidString < $1.uuidString }
        let answerHash = AgentEvidenceHasher.sha256Hex(Data(answer.text.utf8))
        let draft = AgentFinalAnswerSupportRecord(
            answer: answer,
            answerHash: answerHash,
            decisions: decisions,
            evidenceIDs: evidenceIDs,
            supportEvidenceID: nil
        )
        let data = try encoder.encode(draft)
        let supportEvidence = try await evidenceRecorder.record(
            AgentEvidencePacket(
                sourceID: "final-answer-support:\(answerHash)",
                kind: .finalAnswerSupport,
                // The support check verifies the answer's cited local sources exist as evidence,
                // not that the answer's content is fully grounded in them. Keep the summary honest
                // about that distinction so traces do not over-promise verification (RELY-006 / RC-6).
                summary: AgentRunText(draft.canAnswer ? "Final answer's cited local sources are backed by recorded evidence." : "Final answer needs more evidence."),
                artifactData: data,
                privacyClass: .controlPlane,
                trustClass: .appControl,
                metadata: [
                    "answerHash": .string(answerHash),
                    "canAnswer": .bool(draft.canAnswer),
                    "evidenceIDs": .string(evidenceIDs.map(\.uuidString).joined(separator: "\n"))
                ]
            ),
            runID: runID,
            stepID: stepID
        )
        return AgentFinalAnswerSupportRecord(
            answer: answer,
            answerHash: answerHash,
            decisions: decisions,
            evidenceIDs: evidenceIDs,
            supportEvidenceID: supportEvidence.evidenceID
        )
    }
}
