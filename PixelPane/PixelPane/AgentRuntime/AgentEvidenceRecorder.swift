//
//  AgentEvidenceRecorder.swift
//  PixelPane
//
//  The AgentEvidenceRecorder actor and the AgentEvidenceHasher used to dedupe evidence.
//

import CryptoKit
import Foundation

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

    func recordLocationContext(
        runID: UUID,
        stepID: UUID? = nil,
        context: AgentLocationContext
    ) async throws -> AgentRunEvidenceRecord {
        var metadata: [String: AgentRunMetadataValue] = [
            "city": .string(context.city),
            "source": .string(context.source)
        ]
        if let region = context.region {
            metadata["region"] = .string(region)
        }
        if let countryCode = context.countryCode {
            metadata["countryCode"] = .string(countryCode)
        }
        return try await record(
            AgentEvidencePacket(
                sourceID: "location-context:\(runID.uuidString)",
                kind: .locationContext,
                summary: AgentRunText("Recorded app-owned approximate location context."),
                body: AgentRunText(context.modelObservation),
                artifactMimeType: "text/plain",
                artifactFileExtension: "txt",
                privacyClass: .controlPlane,
                trustClass: .appControl,
                metadata: metadata
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

