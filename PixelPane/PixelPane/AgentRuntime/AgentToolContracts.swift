import Foundation

nonisolated enum AgentToolExecutorBinding: String, Codable, Equatable, Sendable {
    case localRuntime
    case visualContext
    case managedProcess
}

nonisolated enum AgentToolPathRole: String, Codable, Equatable, Sendable {
    case readPath
    case searchRoot
    case writeTarget
    case preferredDirectory
    case workingDirectory
    case commandText
}

nonisolated enum AgentToolArgumentRangeBehavior: String, Codable, Equatable, Sendable {
    case reject
    case clamp
}

nonisolated struct AgentToolArgumentConstraints: Codable, Equatable, Sendable {
    let integerRange: ClosedRange<Int>?
    let rangeBehavior: AgentToolArgumentRangeBehavior

    init(
        integerRange: ClosedRange<Int>? = nil,
        rangeBehavior: AgentToolArgumentRangeBehavior = .reject
    ) {
        self.integerRange = integerRange
        self.rangeBehavior = rangeBehavior
    }

    private enum CodingKeys: String, CodingKey {
        case integerMin
        case integerMax
        case rangeBehavior
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lower = try container.decodeIfPresent(Int.self, forKey: .integerMin)
        let upper = try container.decodeIfPresent(Int.self, forKey: .integerMax)
        if let lower, let upper {
            integerRange = lower...upper
        } else {
            integerRange = nil
        }
        rangeBehavior = try container.decodeIfPresent(AgentToolArgumentRangeBehavior.self, forKey: .rangeBehavior) ?? .reject
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(integerRange?.lowerBound, forKey: .integerMin)
        try container.encodeIfPresent(integerRange?.upperBound, forKey: .integerMax)
        try container.encode(rangeBehavior, forKey: .rangeBehavior)
    }
}

nonisolated enum AgentToolArgumentValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case jsonString(String)

    var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .integer(let value):
            return "\(value)"
        case .number(let value):
            return "\(value)"
        case .bool(let value):
            return value ? "true" : "false"
        case .jsonString(let value):
            return value
        }
    }

    var intValue: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

nonisolated struct AgentToolArgumentContract: Codable, Equatable, Sendable {
    let name: String
    let type: AgentKernelToolArgumentType
    let isRequired: Bool
    let summary: String
    let aliases: [String]
    let defaultValue: AgentToolArgumentValue?
    let constraints: AgentToolArgumentConstraints
    let pathRole: AgentToolPathRole?

    init(
        _ name: String,
        type: AgentKernelToolArgumentType = .string,
        isRequired: Bool = true,
        summary: String,
        aliases: [String] = [],
        defaultValue: AgentToolArgumentValue? = nil,
        constraints: AgentToolArgumentConstraints = AgentToolArgumentConstraints(),
        pathRole: AgentToolPathRole? = nil
    ) {
        self.name = name
        self.type = type
        self.isRequired = isRequired
        self.summary = summary
        self.aliases = aliases
        self.defaultValue = defaultValue
        self.constraints = constraints
        self.pathRole = pathRole
    }

    var schema: AgentKernelToolArgumentSchema {
        AgentKernelToolArgumentSchema(
            name: name,
            type: type,
            isRequired: isRequired,
            summary: summary
        )
    }
}

nonisolated enum AgentToolContractError: Error, Equatable, CustomStringConvertible, Sendable {
    case unknownTool(String)
    case unknownArgument(String)
    case missingRequiredArgument(String)
    case malformedArgument(name: String, type: AgentKernelToolArgumentType, value: String)
    case constraintViolation(name: String, summary: String)

    var description: String {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool: \(name)."
        case .unknownArgument(let name):
            return "Unknown tool argument: \(name)."
        case .missingRequiredArgument(let name):
            return "Missing required tool argument: \(name)."
        case .malformedArgument(let name, let type, _):
            return "Tool argument \(name) does not match declared type \(type.rawValue)."
        case .constraintViolation(_, let summary):
            return summary
        }
    }

    var argumentName: String {
        switch self {
        case .unknownTool(let name):
            return name
        case .unknownArgument(let name),
             .missingRequiredArgument(let name),
             .malformedArgument(let name, _, _),
             .constraintViolation(let name, _):
            return name
        }
    }
}

nonisolated struct AgentToolInvocation: Codable, Equatable, Sendable {
    let id: UUID
    let toolName: String
    let arguments: [String: AgentToolArgumentValue]
    let normalizedArguments: [String: String]
    let reason: String?

    init(
        id: UUID = UUID(),
        toolName: String,
        arguments: [String: AgentToolArgumentValue],
        reason: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.normalizedArguments = arguments.mapValues(\.stringValue)
        self.reason = reason
    }

    func string(_ name: String) -> String? {
        arguments[name]?.stringValue
    }

    func int(_ name: String) -> Int? {
        arguments[name]?.intValue
    }

    func bool(_ name: String) -> Bool? {
        arguments[name]?.boolValue
    }

    var kernelToolCall: AgentKernelToolCall {
        AgentKernelToolCall(
            id: id,
            name: toolName,
            arguments: normalizedArguments,
            reason: reason
        )
    }
}

nonisolated struct AgentToolContract: Identifiable, Codable, Equatable, Sendable {
    var id: String { name }

    let name: String
    let summary: String
    let operationKind: AgentToolOperationKind
    let risk: AgentToolRisk
    let requiredScopes: [AgentPermissionScope]
    let visibleRunModes: [AgentRunPermissionMode]
    let visibleProviderTiers: [AgentModelCapabilityTier]
    let requiresApproval: Bool
    let executorBinding: AgentToolExecutorBinding
    let arguments: [AgentToolArgumentContract]

    init(
        name: String,
        summary: String,
        operationKind: AgentToolOperationKind,
        risk: AgentToolRisk,
        requiredScopes: [AgentPermissionScope] = [],
        visibleRunModes: [AgentRunPermissionMode],
        visibleProviderTiers: [AgentModelCapabilityTier],
        requiresApproval: Bool = false,
        executorBinding: AgentToolExecutorBinding,
        arguments: [AgentToolArgumentContract] = []
    ) {
        self.name = name
        self.summary = summary
        self.operationKind = operationKind
        self.risk = risk
        self.requiredScopes = requiredScopes
        self.visibleRunModes = visibleRunModes
        self.visibleProviderTiers = visibleProviderTiers
        self.requiresApproval = requiresApproval
        self.executorBinding = executorBinding
        self.arguments = arguments
    }

    var schema: AgentKernelToolSchema {
        AgentKernelToolSchema(
            name: name,
            summary: summary,
            arguments: arguments.map(\.schema)
        )
    }

    func normalizedInvocation(
        id: UUID = UUID(),
        rawArguments: [String: String],
        reason: String? = nil
    ) throws -> AgentToolInvocation {
        let normalized = try normalizedArgumentValues(rawArguments)
        return AgentToolInvocation(
            id: id,
            toolName: name,
            arguments: normalized,
            reason: reason
        )
    }

    func pathLikeArgumentValues(in normalizedArguments: [String: String]) -> [String] {
        arguments.compactMap { argument in
            guard argument.pathRole != nil else { return nil }
            return normalizedArguments[argument.name]
        }
    }

    private func normalizedArgumentValues(_ rawArguments: [String: String]) throws -> [String: AgentToolArgumentValue] {
        let contractsByInputName = argumentContractsByInputName()
        var canonicalRaw: [String: String] = [:]

        for (rawName, rawValue) in rawArguments {
            guard let argument = contractsByInputName[rawName] else {
                throw AgentToolContractError.unknownArgument(rawName)
            }
            if canonicalRaw[argument.name] == nil || (canonicalRaw[argument.name] ?? "").isEmpty {
                canonicalRaw[argument.name] = rawValue
            }
        }

        var normalized: [String: AgentToolArgumentValue] = [:]
        for argument in arguments {
            let rawValue = canonicalRaw[argument.name]
            let value = try normalizedValue(rawValue, for: argument)
            if let value {
                normalized[argument.name] = value
            }
        }
        return normalized
    }

    private func argumentContractsByInputName() -> [String: AgentToolArgumentContract] {
        var values: [String: AgentToolArgumentContract] = [:]
        for argument in arguments {
            values[argument.name] = argument
            for alias in argument.aliases {
                values[alias] = argument
            }
        }
        return values
    }

    private func normalizedValue(
        _ rawValue: String?,
        for argument: AgentToolArgumentContract
    ) throws -> AgentToolArgumentValue? {
        let resolvedRaw: String?
        if let rawValue, !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedRaw = rawValue
        } else {
            resolvedRaw = argument.defaultValue?.stringValue
        }

        guard let resolvedRaw else {
            if argument.isRequired {
                throw AgentToolContractError.missingRequiredArgument(argument.name)
            }
            return nil
        }

        guard !resolvedRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if argument.isRequired {
                throw AgentToolContractError.missingRequiredArgument(argument.name)
            }
            return nil
        }

        return try typedValue(resolvedRaw, for: argument)
    }

    private func typedValue(
        _ rawValue: String,
        for argument: AgentToolArgumentContract
    ) throws -> AgentToolArgumentValue {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch argument.type {
        case .string:
            return .string(rawValue)
        case .integer:
            guard var value = Int(trimmed) else {
                throw AgentToolContractError.malformedArgument(name: argument.name, type: argument.type, value: rawValue)
            }
            if let range = argument.constraints.integerRange, !range.contains(value) {
                switch argument.constraints.rangeBehavior {
                case .reject:
                    throw AgentToolContractError.constraintViolation(
                        name: argument.name,
                        summary: "Tool argument \(argument.name) must be between \(range.lowerBound) and \(range.upperBound)."
                    )
                case .clamp:
                    value = min(max(value, range.lowerBound), range.upperBound)
                }
            }
            return .integer(value)
        case .number:
            guard let value = Double(trimmed) else {
                throw AgentToolContractError.malformedArgument(name: argument.name, type: argument.type, value: rawValue)
            }
            return .number(value)
        case .boolean:
            guard let value = Self.booleanValue(trimmed) else {
                throw AgentToolContractError.malformedArgument(name: argument.name, type: argument.type, value: rawValue)
            }
            return .bool(value)
        case .jsonString:
            guard let data = rawValue.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) != nil else {
                throw AgentToolContractError.malformedArgument(name: argument.name, type: argument.type, value: rawValue)
            }
            return .jsonString(rawValue)
        }
    }

    private static func booleanValue(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "1", "true", "yes", "y":
            return true
        case "0", "false", "no", "n":
            return false
        default:
            return nil
        }
    }
}

nonisolated struct AgentToolContractRegistry: Sendable {
    static let `default` = AgentToolContractRegistry(contracts: AgentToolContractLibrary.defaultContracts)

    private let contractsByName: [String: AgentToolContract]

    init(contracts: [AgentToolContract] = AgentToolContractLibrary.defaultContracts) {
        contractsByName = Dictionary(uniqueKeysWithValues: contracts.map { ($0.name, $0) })
    }

    func contract(named name: String) -> AgentToolContract? {
        contractsByName[name]
    }

    func normalizedInvocation(for call: AgentKernelToolCall) throws -> AgentToolInvocation {
        guard let contract = contract(named: call.name) else {
            throw AgentToolContractError.unknownTool(call.name)
        }
        return try contract.normalizedInvocation(
            id: call.id,
            rawArguments: call.arguments,
            reason: call.reason
        )
    }
}

nonisolated enum AgentToolCallArgumentNormalizer {
    static func normalizedKernelToolCall(
        name: String,
        rawArguments: [String: Any],
        reason: String?,
        tools: [AgentKernelToolSchema]
    ) throws -> AgentKernelToolCall {
        guard let tool = tools.first(where: { $0.name == name }) else {
            throw AgentToolContractError.unknownTool(name)
        }
        let arguments = try normalizedArguments(rawArguments: rawArguments, tool: tool)
        return AgentKernelToolCall(name: name, arguments: arguments, reason: reason)
    }

    static func normalizedArguments(
        rawArguments: [String: Any],
        tool: AgentKernelToolSchema
    ) throws -> [String: String] {
        let stringArguments = rawArguments.mapValues(stringArgument)
        if let contract = AgentToolContractRegistry.default.contract(named: tool.name) {
            return try contract.normalizedInvocation(rawArguments: stringArguments).normalizedArguments
        }
        return try schemaNormalizedArguments(stringArguments, tool: tool)
    }

    static func normalizedArguments(
        rawArguments: [String: String],
        tool: AgentKernelToolSchema
    ) throws -> [String: String] {
        if let contract = AgentToolContractRegistry.default.contract(named: tool.name) {
            return try contract.normalizedInvocation(rawArguments: rawArguments).normalizedArguments
        }
        return try schemaNormalizedArguments(rawArguments, tool: tool)
    }

    private static func schemaNormalizedArguments(
        _ rawArguments: [String: String],
        tool: AgentKernelToolSchema
    ) throws -> [String: String] {
        let knownArguments = tool.knownArgumentNames
        for key in rawArguments.keys where !knownArguments.contains(key) {
            throw AgentToolContractError.unknownArgument(key)
        }

        var normalized: [String: String] = [:]
        for argument in tool.arguments {
            let rawValue = rawArguments[argument.name]
            if argument.isRequired,
               (rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AgentToolContractError.missingRequiredArgument(argument.name)
            }
            guard let rawValue, !rawValue.isEmpty else { continue }
            normalized[argument.name] = try schemaNormalizedValue(rawValue, argument: argument)
        }
        return normalized
    }

    private static func schemaNormalizedValue(
        _ rawValue: String,
        argument: AgentKernelToolArgumentSchema
    ) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch argument.type {
        case .string:
            return rawValue
        case .integer:
            guard let value = Int(trimmed) else {
                throw AgentToolContractError.malformedArgument(name: argument.name, type: argument.type, value: rawValue)
            }
            return "\(value)"
        case .number:
            guard let value = Double(trimmed) else {
                throw AgentToolContractError.malformedArgument(name: argument.name, type: argument.type, value: rawValue)
            }
            return "\(value)"
        case .boolean:
            guard let value = AgentToolContract.booleanValueForSchemaFallback(trimmed) else {
                throw AgentToolContractError.malformedArgument(name: argument.name, type: argument.type, value: rawValue)
            }
            return value ? "true" : "false"
        case .jsonString:
            guard let data = rawValue.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) != nil else {
                throw AgentToolContractError.malformedArgument(name: argument.name, type: argument.type, value: rawValue)
            }
            return rawValue
        }
    }

    private static func stringArgument(from value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let int = value as? Int {
            return "\(int)"
        }
        if let double = value as? Double {
            return "\(double)"
        }
        if JSONSerialization.isValidJSONObject(value),
           let encoded = try? JSONSerialization.data(withJSONObject: value),
           let encodedString = String(data: encoded, encoding: .utf8) {
            return encodedString
        }
        return "\(value)"
    }
}

extension AgentToolContract {
    nonisolated fileprivate static func booleanValueForSchemaFallback(_ value: String) -> Bool? {
        booleanValue(value)
    }
}

nonisolated enum AgentToolContractLibrary {
    static let defaultContracts: [AgentToolContract] = {
        let tierAB: [AgentModelCapabilityTier] = [.tierAFullAgent, .tierBConstrainedStructuredText]
        let tierA: [AgentModelCapabilityTier] = [.tierAFullAgent]
        let readProposalFull: [AgentRunPermissionMode] = [.readOnly, .proposalOnly, .fullAgent]
        let proposalFull: [AgentRunPermissionMode] = [.proposalOnly, .fullAgent]
        let fullOnly: [AgentRunPermissionMode] = [.fullAgent]
        let readFull: [AgentRunPermissionMode] = [.readOnly, .fullAgent]

        return [
            AgentToolContract(
                name: "list_grants",
                summary: "List local files and folders the user has explicitly granted access to.",
                operationKind: .fileGrantList,
                risk: .readOnly,
                visibleRunModes: readProposalFull,
                visibleProviderTiers: tierAB,
                executorBinding: .localRuntime
            ),
            AgentToolContract(
                name: "list_folder",
                summary: "List entries in a granted folder or list granted roots when no path is provided.",
                operationKind: .fileList,
                risk: .localRead,
                requiredScopes: [.fileRead],
                visibleRunModes: readProposalFull,
                visibleProviderTiers: tierAB,
                executorBinding: .localRuntime,
                arguments: [
                    AgentToolArgumentContract("path", isRequired: false, summary: "Granted folder path, grant name, or path relative to a granted folder.", pathRole: .readPath)
                ]
            ),
            AgentToolContract(
                name: "search_files",
                summary: "Search or find text-like files inside granted local folders and locations.",
                operationKind: .fileSearch,
                risk: .localRead,
                requiredScopes: [.fileRead],
                visibleRunModes: readProposalFull,
                visibleProviderTiers: tierAB,
                executorBinding: .localRuntime,
                arguments: [
                    AgentToolArgumentContract("query", summary: "Search query."),
                    AgentToolArgumentContract("rootPath", isRequired: false, summary: "Optional granted folder path or grant name to scope the search.", pathRole: .searchRoot),
                    AgentToolArgumentContract("filenameOnly", type: .boolean, isRequired: false, summary: "When true, match only file names and paths without reading file contents.", defaultValue: .bool(false))
                ]
            ),
            AgentToolContract(
                name: "read_file",
                summary: "Read a bounded text view of a granted local file.",
                operationKind: .fileRead,
                risk: .localRead,
                requiredScopes: [.fileRead],
                visibleRunModes: readProposalFull,
                visibleProviderTiers: tierAB,
                executorBinding: .localRuntime,
                arguments: [
                    AgentToolArgumentContract("path", summary: "Granted file path, grant name, or path relative to a granted folder.", pathRole: .readPath)
                ]
            ),
            AgentToolContract(
                name: "stage_write_proposal",
                summary: "Stage a proposed create, write, save, modify, change, update, edit, replace, or append inside a granted local location without writing it to disk.",
                operationKind: .fileWriteDraft,
                risk: .localWriteDraft,
                requiredScopes: [.fileWrite],
                visibleRunModes: proposalFull,
                visibleProviderTiers: tierAB,
                requiresApproval: true,
                executorBinding: .localRuntime,
                arguments: [
                    AgentToolArgumentContract("operation", summary: "One of create, replace, or append.", defaultValue: .string("create")),
                    AgentToolArgumentContract("targetPath", summary: "Granted target file path or path relative to a granted folder.", aliases: ["path"], pathRole: .writeTarget),
                    AgentToolArgumentContract("content", summary: "Proposed file content."),
                    AgentToolArgumentContract("preferredDirectoryPath", isRequired: false, summary: "Optional granted directory to prefer when resolving relative paths.", pathRole: .preferredDirectory)
                ]
            ),
            AgentToolContract(
                name: "describe_visual_context",
                summary: "Describe active screenshot, attachment, clipboard image, and OCR context without persisting pixels.",
                operationKind: .visualContext,
                risk: .readOnly,
                requiredScopes: [.visualContext],
                visibleRunModes: readProposalFull,
                visibleProviderTiers: tierAB,
                executorBinding: .visualContext
            ),
            AgentToolContract(
                name: "get_process_snapshot",
                summary: "Read a bounded snapshot of currently running local processes, returning PID, CPU, memory, and executable name only.",
                operationKind: .processSnapshot,
                risk: .readOnly,
                visibleRunModes: readProposalFull,
                visibleProviderTiers: tierAB,
                executorBinding: .localRuntime,
                arguments: [
                    AgentToolArgumentContract("limit", type: .integer, isRequired: false, summary: "Optional row limit from 1 to 20. Defaults to 8.", defaultValue: .integer(8), constraints: AgentToolArgumentConstraints(integerRange: 1...20, rangeBehavior: .clamp))
                ]
            ),
            AgentToolContract(
                name: "get_local_listener_snapshot",
                summary: "Read a bounded snapshot of local listening ports, returning port, address, PID, executable name, and granted working directory only.",
                operationKind: .localServerDiscovery,
                risk: .readOnly,
                visibleRunModes: readProposalFull,
                visibleProviderTiers: tierAB,
                executorBinding: .localRuntime,
                arguments: [
                    AgentToolArgumentContract("port", type: .integer, isRequired: false, summary: "Optional port to inspect.", constraints: AgentToolArgumentConstraints(integerRange: 1...65_535, rangeBehavior: .reject)),
                    AgentToolArgumentContract("rootPath", isRequired: false, summary: "Optional granted folder path or grant name used to filter listener working directories.", pathRole: .searchRoot),
                    AgentToolArgumentContract("limit", type: .integer, isRequired: false, summary: "Optional row limit from 1 to 20. Defaults to 8.", defaultValue: .integer(8), constraints: AgentToolArgumentConstraints(integerRange: 1...20, rangeBehavior: .clamp))
                ]
            ),
            AgentToolContract(
                name: "run_finite_command",
                summary: "Request a bounded local shell command for terminal, file, build, or system work. Raw shell is available only in full-agent mode and requires app-owned approval or a matching approval grant.",
                operationKind: .finiteCommand,
                risk: .command,
                requiredScopes: [.workingDirectory],
                visibleRunModes: fullOnly,
                visibleProviderTiers: tierA,
                executorBinding: .localRuntime,
                arguments: [
                    AgentToolArgumentContract("command", summary: "Shell command to run.", pathRole: .commandText),
                    AgentToolArgumentContract("workingDirectory", summary: "Granted working directory for the command.", pathRole: .workingDirectory),
                    AgentToolArgumentContract("timeoutSeconds", type: .integer, isRequired: false, summary: "Optional timeout in seconds.", defaultValue: .integer(30), constraints: AgentToolArgumentConstraints(integerRange: 1...120, rangeBehavior: .clamp))
                ]
            ),
            AgentToolContract(
                name: "start_process",
                summary: "Start a long-running local process with lifecycle tracking.",
                operationKind: .processStart,
                risk: .processControl,
                requiredScopes: [.workingDirectory, .processControl],
                visibleRunModes: [.fullAgent],
                visibleProviderTiers: tierA,
                requiresApproval: true,
                executorBinding: .managedProcess,
                arguments: [
                    AgentToolArgumentContract("command", summary: "Shell command to start.", pathRole: .commandText),
                    AgentToolArgumentContract("workingDirectory", summary: "Validated working directory.", pathRole: .workingDirectory),
                    AgentToolArgumentContract("processID", isRequired: false, summary: "Optional stable process ID.")
                ]
            ),
            AgentToolContract(
                name: "process_status",
                summary: "Read the current status of a managed process.",
                operationKind: .processStatus,
                risk: .readOnly,
                requiredScopes: [.processControl],
                visibleRunModes: readFull,
                visibleProviderTiers: tierA,
                executorBinding: .managedProcess,
                arguments: [
                    AgentToolArgumentContract("processID", summary: "Managed process ID.")
                ]
            ),
            AgentToolContract(
                name: "stop_process",
                summary: "Stop a managed long-running process.",
                operationKind: .processStop,
                risk: .processControl,
                requiredScopes: [.processControl],
                visibleRunModes: [.fullAgent],
                visibleProviderTiers: tierA,
                requiresApproval: true,
                executorBinding: .managedProcess,
                arguments: [
                    AgentToolArgumentContract("processID", summary: "Managed process ID.")
                ]
            ),
            AgentToolContract(
                name: "tail_process_output",
                summary: "Read the bounded stdout and stderr tail for a managed process.",
                operationKind: .processOutput,
                risk: .readOnly,
                requiredScopes: [.processControl],
                visibleRunModes: readFull,
                visibleProviderTiers: tierA,
                executorBinding: .managedProcess,
                arguments: [
                    AgentToolArgumentContract("processID", summary: "Managed process ID.")
                ]
            )
        ]
    }()
}
