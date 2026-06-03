import Foundation

nonisolated struct AgentLocalEvidencePlan: Equatable, Sendable {
    let requirements: [AgentLocalEvidenceRequirement]
    let toolCalls: [AgentKernelToolCall]
    // True only when the plan targets a confidently resolved local entity
    // (explicit absolute path, quoted grant reference, or existing referenced child).
    // The orchestrator uses this to decide whether deterministic preflight discovery should run,
    // instead of force-reading guessed files on every request.
    let isConfident: Bool

    init(
        requirements: [AgentLocalEvidenceRequirement],
        toolCalls: [AgentKernelToolCall],
        isConfident: Bool = false
    ) {
        self.requirements = requirements
        self.toolCalls = toolCalls
        self.isConfident = isConfident
    }

    static let empty = AgentLocalEvidencePlan(requirements: [], toolCalls: [], isConfident: false)
}

nonisolated struct AgentResolvedLocalEntity: Equatable, Sendable {
    let path: String
    let isDirectory: Bool
    let source: String
}

nonisolated struct AgentLocalEvidencePlanner: Sendable {
    private let maxResolvedEntities = 2

    init() {}

    func plan(
        messages: [AgentKernelMessage],
        tools: [AgentKernelToolSchema],
        context: AgentToolRunContext,
        taskFrame: AgentTaskFrame? = nil,
        existingEvidence: [AgentRunEvidenceRecord] = []
    ) -> AgentLocalEvidencePlan {
        guard context.runMode != .plainChat, !context.localGrants.isEmpty else {
            return .empty
        }
        let toolByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        guard !toolByName.isEmpty else { return .empty }

        let latestUserMessage = Self.latestUserMessage(from: messages)
        let frame = taskFrame ?? AgentTaskFrame.build(
            userMessage: latestUserMessage,
            tools: tools,
            context: context
        )
        let entities = entitiesReferenced(in: frame, grants: context.localGrants)
        let searchQueries = frame.exactSearchQueries
        var requirements: [AgentLocalEvidenceRequirement] = []
        var calls: [AgentKernelToolCall] = []

        if toolByName["search_files"] != nil, !searchQueries.isEmpty {
            let scopedDirectories = entities.filter(\.isDirectory)
            if scopedDirectories.isEmpty, entities.isEmpty {
                for query in searchQueries.prefix(4) {
                    requirements.append(
                        AgentLocalEvidenceRequirement(
                            kind: .searchDiscovery,
                            query: query
                        )
                    )
                    calls.append(
                        AgentKernelToolCall(
                            name: "search_files",
                            arguments: ["query": query],
                            reason: "Search granted local roots for the exact query recorded in the task frame."
                        )
                    )
                }
            } else {
                for entity in scopedDirectories.prefix(maxResolvedEntities) {
                    for query in searchQueries.prefix(4) {
                        requirements.append(
                            AgentLocalEvidenceRequirement(
                                kind: .searchDiscovery,
                                targetPath: entity.path,
                                targetIsDirectory: true,
                                query: query
                            )
                        )
                        calls.append(
                            AgentKernelToolCall(
                                name: "search_files",
                                arguments: [
                                    "query": query,
                                    "rootPath": entity.path
                                ],
                                reason: "Search the resolved local directory for the exact query recorded in the task frame."
                            )
                        )
                    }
                }
            }
        }

        for entity in entities.prefix(maxResolvedEntities) {
            if entity.isDirectory {
                if toolByName["list_folder"] != nil {
                    requirements.append(
                        AgentLocalEvidenceRequirement(
                            kind: .directoryListing,
                            targetPath: entity.path,
                            targetIsDirectory: true,
                            query: latestUserMessage
                        )
                    )
                    calls.append(
                        AgentKernelToolCall(
                            name: "list_folder",
                            arguments: ["path": entity.path],
                            reason: "Resolve local directory evidence for the current answer."
                        )
                    )
                }
            } else if AgentPermissionPolicy().referencesSensitivePath(entity.path),
                      toolByName["search_files"] != nil {
                let query = URL(fileURLWithPath: entity.path).lastPathComponent
                requirements.append(
                    AgentLocalEvidenceRequirement(
                        kind: .searchDiscovery,
                        query: query
                    )
                )
                calls.append(
                    AgentKernelToolCall(
                        name: "search_files",
                        arguments: [
                            "query": query,
                            "filenameOnly": "true"
                        ],
                        reason: "Search by filename for the sensitive local reference without reading file contents."
                    )
                )
            } else if toolByName["read_file"] != nil {
                requirements.append(
                    AgentLocalEvidenceRequirement(
                        kind: .fileContent,
                        targetPath: entity.path,
                        query: latestUserMessage
                    )
                )
                calls.append(
                    AgentKernelToolCall(
                        name: "read_file",
                        arguments: ["path": entity.path],
                        reason: "Read resolved local file evidence for the current answer."
                    )
                )
            }
        }

        return AgentLocalEvidencePlan(
            requirements: uniqueRequirements(requirements),
            toolCalls: uniqueToolCalls(calls),
            isConfident: !requirements.isEmpty
        )
    }

    private func entitiesReferenced(
        in frame: AgentTaskFrame,
        grants: [AgentLocalFileGrant]
    ) -> [AgentResolvedLocalEntity] {
        let entities = frame.localReferences.compactMap { reference -> AgentResolvedLocalEntity? in
            guard reference.source != .explicitWriteTarget else { return nil }
            guard grants.contains(where: { $0.allowsRead(reference.path) }) else { return nil }
            guard let isDirectory = reference.isDirectory else { return nil }
            return AgentResolvedLocalEntity(
                path: URL(fileURLWithPath: reference.path).standardizedFileURL.path,
                isDirectory: isDirectory,
                source: reference.source.rawValue
            )
        }
        return uniqueEntities(entities)
    }

    private func uniqueRequirements(_ requirements: [AgentLocalEvidenceRequirement]) -> [AgentLocalEvidenceRequirement] {
        var seen = Set<String>()
        return requirements.filter { seen.insert($0.id).inserted }
    }

    private func uniqueToolCalls(_ calls: [AgentKernelToolCall]) -> [AgentKernelToolCall] {
        var seen = Set<String>()
        return calls.filter { call in
            let key = "\(call.name):\(call.arguments.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&"))"
            return seen.insert(key).inserted
        }
    }

    private func uniqueEntities(_ entities: [AgentResolvedLocalEntity]) -> [AgentResolvedLocalEntity] {
        var seen = Set<String>()
        return entities.filter { seen.insert($0.path).inserted }
    }

    static func latestUserMessage(from messages: [AgentKernelMessage]) -> String {
        messages.reversed().first { $0.role == .user }?.content ?? ""
    }

    static func terms(from text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "_" && $0 != "-" }
            .map(String.init)
            .filter { $0.count >= 3 }
    }
}

extension AgentLocalEvidenceRequirement {
    nonisolated func isSatisfied(by evidence: [AgentRunEvidenceRecord]) -> Bool {
        evidence.contains { record in
            guard let kind = AgentEvidenceKind(rawValue: record.kind) else { return false }
            switch self.kind {
            case .grantDiscovery:
                return kind == .fileGrant
            case .directoryListing:
                guard kind == .folderList else { return false }
                return targetMatches(record.stringMetadata("path"))
            case .fileContent:
                guard kind == .fileRead else { return false }
                return targetMatches(record.stringMetadata("path"))
            case .searchDiscovery:
                guard kind == .fileSearch else { return false }
                if targetPath != nil {
                    return targetMatches(record.stringMetadata("rootPath"))
                        || record.stringMetadata("paths")?.split(separator: "\n").map(String.init).contains(where: targetMatches) == true
                }
                guard let query else {
                    return record.stringMetadata("query") != nil
                }
                return record.stringMetadata("query") == query
            }
        }
    }

    private nonisolated func targetMatches(_ candidate: String?) -> Bool {
        guard let targetPath else { return candidate != nil }
        guard let candidate else { return false }
        let target = URL(fileURLWithPath: targetPath).standardizedFileURL.path
        let value = URL(fileURLWithPath: candidate).standardizedFileURL.path
        return value == target || value.hasPrefix(target + "/")
    }
}
