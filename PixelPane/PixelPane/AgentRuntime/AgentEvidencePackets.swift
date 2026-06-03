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

