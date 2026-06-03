//
//  AgentFinalAnswerSupportRecorder.swift
//  PixelPane
//
//  The AgentFinalAnswerSupportRecorder actor for persisting final-answer support records.
//

import CryptoKit
import Foundation

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
