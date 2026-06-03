//
//  AgentEvidenceController.swift
//  PixelPane
//
//  AgentEvidenceController: evidence-claim verification and final-answer support decisions.
//

import CryptoKit
import Foundation

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

