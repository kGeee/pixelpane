import Foundation

enum AgentKernelEvidenceNeedKindV2: String, Codable, Equatable, Sendable {
    case localGrants = "local_grants"
    case folderListing = "folder_listing"
    case fileSearch = "file_search"
    case fileRead = "file_read"
    case visualContext = "visual_context"
    case finiteCommand = "finite_command"
    case processStatus = "process_status"
    case processTail = "process_tail"
    case localServerProbe = "local_server_probe"
    case writeProposal = "write_proposal"
}

struct AgentKernelEvidenceNeedV2: Codable, Equatable, Sendable {
    let kind: AgentKernelEvidenceNeedKindV2
    let target: String?
    let arguments: [String: String]
    let rationale: String?

    nonisolated init(
        kind: AgentKernelEvidenceNeedKindV2,
        target: String? = nil,
        arguments: [String: String] = [:],
        rationale: String? = nil
    ) {
        self.kind = kind
        self.target = target
        self.arguments = arguments
        self.rationale = rationale
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(AgentKernelEvidenceNeedKindV2.self, forKey: .kind)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        arguments = try container.decodeIfPresent([String: String].self, forKey: .arguments) ?? [:]
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
    }
}

struct AgentKernelFinalClaimDeclarationV2: Codable, Equatable, Sendable {
    let type: AgentKernelClaimTypeV2
    let target: String?
    let qualifiers: [String: AgentKernelMetadataValueV2]

    nonisolated init(
        type: AgentKernelClaimTypeV2,
        target: String? = nil,
        qualifiers: [String: AgentKernelMetadataValueV2] = [:]
    ) {
        self.type = type
        self.target = target
        self.qualifiers = qualifiers
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(AgentKernelClaimTypeV2.self, forKey: .type)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        qualifiers = try container.decodeIfPresent([String: AgentKernelMetadataValueV2].self, forKey: .qualifiers) ?? [:]
    }

    nonisolated var claim: AgentKernelVerifiableClaimV2 {
        AgentKernelVerifiableClaimV2(
            type: type,
            target: target,
            qualifiers: qualifiers
        )
    }
}

struct AgentKernelEvidencePlannerV2: Sendable {
    nonisolated static let declareEvidenceNeedsToolName = "declare_evidence_needs"
    nonisolated static let declareFinalClaimsToolName = "declare_final_claims"

    nonisolated static var evidencePlanningToolSchema: AgentKernelToolSchemaV2 {
        AgentKernelToolSchemaV2(
            name: declareEvidenceNeedsToolName,
            summary: "Declare deterministic evidence needs as JSON before the runtime maps them to app capabilities.",
            requiredArguments: ["needs"]
        )
    }

    nonisolated static var finalClaimsToolSchema: AgentKernelToolSchemaV2 {
        AgentKernelToolSchemaV2(
            name: declareFinalClaimsToolName,
            summary: "Declare verifiable local-state claims made by a final answer as JSON.",
            requiredArguments: ["claims"]
        )
    }

    nonisolated init() {}

    nonisolated func planningInstructionMessage(
        availableTools: [AgentKernelToolSchemaV2]
    ) -> AgentKernelMessageV2 {
        let toolLines = availableTools
            .sorted { $0.name < $1.name }
            .map { "- \($0.name): \($0.summary)" }
            .joined(separator: "\n")
        return AgentKernelMessageV2(
            role: .system,
            content: """
            evidence_planning_request:
            Decide whether the user task needs deterministic local evidence before final synthesis.
            If local evidence is needed, call \(Self.declareEvidenceNeedsToolName) with argument needs as a JSON array.
            Each item must use kind, optional target, optional arguments, and optional rationale.
            Supported need kinds: \(AgentKernelEvidenceNeedKindV2.allCasesList).
            Available runtime capabilities:
            \(toolLines)
            If no deterministic local evidence is needed, return a short final answer saying no evidence is needed. Do not answer the user task in this planning step.
            """
        )
    }

    nonisolated func finalClaimsInstructionMessage(
        finalAnswer: String
    ) -> AgentKernelMessageV2 {
        AgentKernelMessageV2(
            role: .system,
            content: """
            final_claim_verification_request:
            Inspect the candidate final answer and declare only claims that require deterministic local evidence.
            Candidate final answer:
            \(finalAnswer)

            If it makes claims about file existence or writes, commands, running processes, ports, URLs, build/test success, cancellation, or task completion, call \(Self.declareFinalClaimsToolName) with claims as a JSON array.
            Supported claim types: \(AgentKernelClaimTypeV2.allCasesList).
            If the answer makes no local-state claim, return a short final answer saying no verifiable claims.
            """
        )
    }

    nonisolated func parseNeeds(from call: AgentKernelToolCallV2) -> Result<[AgentKernelEvidenceNeedV2], AgentKernelTerminalReasonV2> {
        guard call.name == Self.declareEvidenceNeedsToolName else {
            return .failure(
                reason(
                    code: "unexpected_evidence_plan_tool",
                    summary: "The planning response used an unexpected tool."
                )
            )
        }
        return decode(argument: call.arguments["needs"], code: "malformed_evidence_needs")
    }

    nonisolated func parseClaims(from call: AgentKernelToolCallV2) -> Result<[AgentKernelVerifiableClaimV2], AgentKernelTerminalReasonV2> {
        guard call.name == Self.declareFinalClaimsToolName else {
            return .failure(
                reason(
                    code: "unexpected_final_claim_tool",
                    summary: "The final-claim response used an unexpected tool."
                )
            )
        }
        let decoded: Result<[AgentKernelFinalClaimDeclarationV2], AgentKernelTerminalReasonV2> = decode(
            argument: call.arguments["claims"],
            code: "malformed_final_claims"
        )
        return decoded.map { declarations in declarations.map(\.claim) }
    }

    nonisolated func toolCall(for need: AgentKernelEvidenceNeedV2, context: AgentKernelChatContextV2) -> Result<AgentKernelToolCallV2, AgentKernelTerminalReasonV2> {
        let callReason = need.rationale ?? "Collect deterministic evidence."
        switch need.kind {
        case .localGrants:
            return .success(AgentKernelToolCallV2(name: "list_grants", reason: callReason))
        case .folderListing:
            return .success(
                AgentKernelToolCallV2(
                    name: "list_folder",
                    arguments: optionalArgument("path", value: need.arguments["path"] ?? need.target),
                    reason: callReason
                )
            )
        case .fileSearch:
            guard let query = nonEmpty(need.arguments["query"] ?? need.target) else {
                return .failure(reason(code: "evidence_need_missing_query", summary: "File-search evidence needs require a query."))
            }
            return .success(AgentKernelToolCallV2(name: "search_files", arguments: ["query": query], reason: callReason))
        case .fileRead:
            guard let path = nonEmpty(need.arguments["path"] ?? need.target) else {
                return .failure(reason(code: "evidence_need_missing_path", summary: "File-read evidence needs require a path."))
            }
            return .success(AgentKernelToolCallV2(name: "read_file", arguments: ["path": path], reason: callReason))
        case .visualContext:
            return .success(AgentKernelToolCallV2(name: "describe_visual_context", reason: callReason))
        case .finiteCommand:
            guard let command = nonEmpty(need.arguments["command"] ?? need.target) else {
                return .failure(reason(code: "evidence_need_missing_command", summary: "Command evidence needs require a command."))
            }
            var arguments = need.arguments
            arguments["command"] = command
            if nonEmpty(arguments["workingDirectory"]) == nil {
                guard let workingDirectory = context.allowedWorkingDirectories.first else {
                    return .failure(reason(code: "evidence_need_missing_working_directory", summary: "Command evidence needs require an allowed working directory."))
                }
                arguments["workingDirectory"] = workingDirectory
            }
            return .success(AgentKernelToolCallV2(name: "run_finite_command", arguments: arguments, reason: callReason))
        case .processStatus:
            guard let processID = nonEmpty(need.arguments["processID"] ?? need.target) else {
                return .failure(reason(code: "evidence_need_missing_process_id", summary: "Process-status evidence needs require a managed process ID."))
            }
            return .success(AgentKernelToolCallV2(name: "process_status", arguments: ["processID": processID], reason: callReason))
        case .processTail:
            guard let processID = nonEmpty(need.arguments["processID"] ?? need.target) else {
                return .failure(reason(code: "evidence_need_missing_process_id", summary: "Process-tail evidence needs require a managed process ID."))
            }
            return .success(AgentKernelToolCallV2(name: "tail_process_output", arguments: ["processID": processID], reason: callReason))
        case .localServerProbe:
            var arguments = need.arguments
            if arguments["url"] == nil, let target = need.target, target.contains("://") {
                arguments["url"] = target
            }
            if arguments["port"] == nil, let target = need.target, Int(target) != nil {
                arguments["port"] = target
            }
            guard arguments["url"] != nil || arguments["port"] != nil else {
                return .failure(reason(code: "evidence_need_missing_local_server_target", summary: "Local-server evidence needs require a localhost URL or port."))
            }
            return .success(AgentKernelToolCallV2(name: "probe_local_server", arguments: arguments, reason: callReason))
        case .writeProposal:
            return .success(AgentKernelToolCallV2(name: "stage_write_proposal", arguments: need.arguments, reason: callReason))
        }
    }

    private nonisolated func decode<T: Decodable>(
        argument: String?,
        code: String
    ) -> Result<T, AgentKernelTerminalReasonV2> {
        guard let argument, let data = argument.data(using: .utf8) else {
            return .failure(reason(code: code, summary: "The structured declaration argument was missing or not UTF-8."))
        }
        do {
            return .success(try JSONDecoder().decode(T.self, from: data))
        } catch {
            return .failure(reason(code: code, summary: error.localizedDescription))
        }
    }

    private nonisolated func optionalArgument(_ key: String, value: String?) -> [String: String] {
        guard let value = nonEmpty(value) else {
            return [:]
        }
        return [key: value]
    }

    private nonisolated func nonEmpty(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? nil : cleaned
    }

    private nonisolated func reason(code: String, summary: String) -> AgentKernelTerminalReasonV2 {
        AgentKernelTerminalReasonV2(code: code, summary: AgentKernelBoundedTextV2(summary))
    }
}

private extension AgentKernelEvidenceNeedKindV2 {
    nonisolated static var allCasesList: String {
        [
            AgentKernelEvidenceNeedKindV2.localGrants,
            .folderListing,
            .fileSearch,
            .fileRead,
            .visualContext,
            .finiteCommand,
            .processStatus,
            .processTail,
            .localServerProbe,
            .writeProposal
        ]
        .map(\.rawValue)
        .joined(separator: ", ")
    }
}

private extension AgentKernelClaimTypeV2 {
    nonisolated static var allCasesList: String {
        [
            AgentKernelClaimTypeV2.fileExists,
            .fileChanged,
            .commandRan,
            .commandSucceeded,
            .commandFailed,
            .processAlive,
            .portListening,
            .urlResponds,
            .buildOrTestPassed,
            .taskCanceled,
            .unsupported
        ]
        .map(\.rawValue)
        .joined(separator: ", ")
    }
}
