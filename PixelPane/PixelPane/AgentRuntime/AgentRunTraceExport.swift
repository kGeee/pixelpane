import Foundation

nonisolated struct AgentRunProjectedSession: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let contextID: String?
    let contextKind: String?
    let updatedAt: Date
    let latestRunID: UUID?
    let latestStatus: AgentRunStatus?
    let messageCount: Int

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Chat" : trimmed
    }
}

nonisolated struct AgentRunTraceExporter: Sendable {
    nonisolated init() {}

    nonisolated func export(
        trace: AgentRunTraceProjection,
        visibleMessages: [AgentRunVisibleMessage],
        generatedAt: Date = Date()
    ) -> String {
        var sections: [String] = []
        sections.append(
            """
            # Pixel Pane Agent Trace
            Exported: \(Self.timestamp(generatedAt))
            Session ID: \(trace.run.sessionID.uuidString)
            Run ID: \(trace.run.runID.uuidString)
            Status: \(trace.run.status.rawValue)
            Created: \(Self.timestamp(trace.run.createdAt))
            Updated: \(Self.timestamp(trace.run.updatedAt))
            Private reasoning: omitted
            """
        )

        if let session = trace.session {
            sections.append(
                """
                ## Session
                Title: \(session.title)
                Context ID: \(session.contextID ?? "none")
                Context Kind: \(session.contextKind ?? "none")
                Created: \(Self.timestamp(session.createdAt))
                Updated: \(Self.timestamp(session.updatedAt))
                """
            )
        }

        let conversation = conversationSection(visibleMessages)
        if !conversation.isEmpty {
            sections.append("## Conversation\n\(conversation)")
        }

        if !trace.steps.isEmpty {
            sections.append("## Steps\n\(stepsSection(trace.steps))")
        }

        if !trace.waits.isEmpty {
            sections.append("## Waits\n\(waitsSection(trace.waits))")
        }

        if !trace.sideEffects.isEmpty {
            sections.append("## Side Effects\n\(sideEffectsSection(trace.sideEffects))")
        }

        if !trace.controlRecords.isEmpty {
            sections.append("## Control Records\n\(controlRecordsSection(trace.controlRecords))")
        }

        if !trace.evidence.isEmpty {
            sections.append("## Evidence\n\(evidenceSection(trace.evidence))")
        }

        if !trace.artifacts.isEmpty {
            sections.append("## Artifacts\n\(artifactsSection(trace.artifacts))")
        }

        if !trace.events.isEmpty {
            sections.append("## Events\n\(eventsSection(trace.events))")
        }

        return sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private nonisolated func conversationSection(_ messages: [AgentRunVisibleMessage]) -> String {
        messages
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    lhs.sequence < rhs.sequence
                } else {
                    lhs.createdAt < rhs.createdAt
                }
            }
            .enumerated()
            .map { index, message in
                """
                ### Message \(index + 1) - \(message.role.rawValue)
                \(message.text.text)
                """
            }
            .joined(separator: "\n\n")
    }

    private nonisolated func stepsSection(_ steps: [AgentRunStepRecord]) -> String {
        steps.map { step in
            "- \(step.kind.rawValue) \(step.status.rawValue) step=\(step.stepID.uuidString) updated=\(Self.timestamp(step.updatedAt)) metadata=\(metadataSummary(step.metadata))"
        }
        .joined(separator: "\n")
    }

    private nonisolated func waitsSection(_ waits: [AgentRunWaitRecord]) -> String {
        waits.map { wait in
            "- \(wait.kind.rawValue) \(wait.status.rawValue) wait=\(wait.waitID.uuidString) risk=\(wait.risk ?? "none") prompt=\(wait.prompt.text)"
        }
        .joined(separator: "\n")
    }

    private nonisolated func sideEffectsSection(_ sideEffects: [AgentRunSideEffectRecord]) -> String {
        sideEffects.map { sideEffect in
            let error = sideEffect.errorSummary.map { " error=\(redactFreeText($0.text))" } ?? ""
            return "- \(sideEffect.kind.rawValue) \(sideEffect.status.rawValue) sideEffect=\(sideEffect.sideEffectID.uuidString) wait=\(sideEffect.approvalWaitID?.uuidString ?? "none") proposal=\(sideEffect.proposalHash ?? "none") metadata=\(metadataSummary(sideEffect.metadata))\(error)"
        }
        .joined(separator: "\n")
    }

    private nonisolated func controlRecordsSection(_ records: [AgentRunControlRecord]) -> String {
        records.map { record in
            "- #\(record.sequence) \(record.kind.rawValue) record=\(record.recordID.uuidString) step=\(record.stepID?.uuidString ?? "none") metadata=\(metadataSummary(record.metadata)) payload=\(controlPayloadSummary(record.payload))"
        }
        .joined(separator: "\n")
    }

    private nonisolated func evidenceSection(_ evidence: [AgentRunEvidenceRecord]) -> String {
        evidence.map { record in
            "- \(record.kind) evidence=\(record.evidenceID.uuidString) source=\(record.sourceID) artifact=\(record.artifactID?.uuidString ?? "none") summary=\(record.summary.text) metadata=\(metadataSummary(record.metadata))"
        }
        .joined(separator: "\n")
    }

    private nonisolated func artifactsSection(_ artifacts: [AgentRunArtifactRecord]) -> String {
        artifacts.map { artifact in
            "- \(artifact.kind) artifact=\(artifact.artifactID.uuidString) mime=\(artifact.mimeType) bytes=\(artifact.byteCount) path=\(artifact.relativePath) summary=\(artifact.summary?.text ?? "none")"
        }
        .joined(separator: "\n")
    }

    private nonisolated func eventsSection(_ events: [AgentRunEventRecord]) -> String {
        events.map { event in
            "- #\(event.sequence) \(event.kind.rawValue) event=\(event.eventID.uuidString) step=\(event.stepID?.uuidString ?? "none") payload=\(payloadSummary(event.payload))"
        }
        .joined(separator: "\n")
    }

    private nonisolated func payloadSummary(_ payload: AgentRunEventPayload) -> String {
        switch payload {
        case .text(let text), .progress(let text), .diagnostic(let text):
            return redactFreeText(text.text)
        case .status(let status, let reason):
            return "\(status.rawValue) reason=\(reason.map { redactFreeText($0.text) } ?? "none")"
        case .step(let step):
            return "step \(step.kind.rawValue) \(step.status.rawValue)"
        case .wait(let wait):
            return "wait \(wait.kind.rawValue) \(wait.status.rawValue)"
        case .artifact(let artifact):
            return "artifact \(artifact.kind) \(artifact.artifactID.uuidString)"
        case .evidence(let evidence):
            return "evidence \(evidence.kind) \(evidence.evidenceID.uuidString)"
        case .sideEffect(let sideEffect):
            return "sideEffect \(sideEffect.kind.rawValue) \(sideEffect.status.rawValue)"
        case .metadata(let metadata):
            return metadataSummary(metadata)
        case .runConfiguration(let configuration):
            return "runConfiguration adapter=\(configuration.adapterDescriptor.id) mode=\(configuration.request.mode.rawValue) tools=\(configuration.request.tools.count)"
        }
    }

    private nonisolated func controlPayloadSummary(_ payload: AgentRunControlPayload) -> String {
        switch payload {
        case .modelRequest(let request):
            return "modelRequest id=\(request.id.uuidString) mode=\(request.mode.rawValue) messages=\(request.messages.count) tools=\(request.tools.count)"
        case .modelResponse(let response):
            return "modelResponse request=\(response.requestID.uuidString) adapter=\(response.adapterID) tier=\(response.tier.rawValue) format=\(response.responseFormat.rawValue) events=\(response.events.count)"
        case .modelFailure(let failure):
            // Include the failure's own metadata (e.g. rawOutput with the
            // underlying transport error) so exports stay debuggable.
            var summary = "modelFailure adapter=\(failure.adapterID) kind=\(failure.kind.rawValue) message=\(redactFreeText(failure.message.text))"
            if !failure.metadata.isEmpty {
                summary += " metadata=\(metadataSummary(failure.metadata))"
            }
            return summary
        case .modelMessage(let message):
            return "message role=\(message.role.rawValue) content=\(redactFreeText(message.content))"
        case .toolCall(let call):
            return "toolCall name=\(call.name) arguments=\(call.arguments.keys.sorted().joined(separator: ","))"
        case .toolResult(let result):
            return "toolResult name=\(result.toolName) status=\(result.status) evidence=\(result.evidenceIDs.count) artifacts=\(result.artifactIDs.count) wait=\(result.waitID?.uuidString ?? "none") sideEffect=\(result.sideEffectID?.uuidString ?? "none") summary=\(redactFreeText(result.summary.text))"
        case .metadata(let metadata):
            return metadataSummary(metadata)
        }
    }

    private nonisolated func metadataSummary(_ metadata: [String: AgentRunMetadataValue]) -> String {
        guard !metadata.isEmpty else { return "none" }
        return metadata.keys.sorted().map { key in
            "\(key)=\(redactedValue(metadata[key], key: key))"
        }
        .joined(separator: ", ")
    }

    private nonisolated func redactedValue(_ value: AgentRunMetadataValue?, key: String) -> String {
        guard let value else { return "" }
        if shouldRedact(key: key) {
            return "[redacted]"
        }
        switch value {
        case .string(let string):
            return redactFreeText(string)
        case .int(let int):
            return "\(int)"
        case .double(let double):
            return "\(double)"
        case .bool(let bool):
            return bool ? "true" : "false"
        }
    }

    private nonisolated func redactFreeText(_ text: String) -> String {
        let bounded = AgentRunText(text, characterLimit: 2_000).text
        var redacted = bounded
        let patterns = [
            #"(?i)(api[_-]?key|token|secret|password)\s*[:=]\s*[^ \n]+"#,
            #"(?i)(bearer)\s+[A-Za-z0-9._~+/=-]+"#
        ]
        for pattern in patterns {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: "$1=[redacted]",
                options: .regularExpression
            )
        }
        return redacted
    }

    private nonisolated func shouldRedact(key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.contains("token")
            || normalized.contains("secret")
            || normalized.contains("password")
            || normalized.contains("apikey")
            || normalized.contains("api_key")
            || normalized.contains("authorization")
            || normalized.contains("auth")
    }

    private nonisolated static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
