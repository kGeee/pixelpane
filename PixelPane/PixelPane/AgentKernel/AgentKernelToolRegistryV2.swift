import Foundation

enum AgentKernelToolArgumentTypeV2: String, Codable, Equatable, Sendable {
    case string
    case integer
    case number
    case boolean
    case jsonString
}

enum AgentKernelToolScopeRequirementV2: String, Codable, Equatable, Hashable, Sendable {
    case none
    case grantedFileRead
    case grantedFileWrite
    case visualContext
    case workingDirectory
    case networkAccess
    case processControl
    case privilegedOperation
}

struct AgentKernelToolArgumentSchemaV2: Codable, Equatable, Sendable {
    let name: String
    let type: AgentKernelToolArgumentTypeV2
    let isRequired: Bool
    let summary: String

    nonisolated init(
        name: String,
        type: AgentKernelToolArgumentTypeV2,
        isRequired: Bool = true,
        summary: String
    ) {
        self.name = name
        self.type = type
        self.isRequired = isRequired
        self.summary = summary
    }
}

struct AgentKernelToolIOTypeV2: Codable, Equatable, Sendable {
    let name: String
    let summary: String

    nonisolated init(name: String, summary: String) {
        self.name = name
        self.summary = summary
    }
}

struct AgentKernelToolDenyRuleV2: Codable, Equatable, Sendable {
    let argumentName: String
    let containsAny: [String]
    let reasonCode: String
    let summary: AgentKernelBoundedTextV2

    nonisolated init(
        argumentName: String,
        containsAny: [String],
        reasonCode: String,
        summary: AgentKernelBoundedTextV2
    ) {
        self.argumentName = argumentName
        self.containsAny = containsAny
        self.reasonCode = reasonCode
        self.summary = summary
    }

    nonisolated func matches(arguments: [String: String]) -> Bool {
        guard let value = arguments[argumentName]?.lowercased() else {
            return false
        }

        return containsAny.contains { blockedValue in
            value.contains(blockedValue.lowercased())
        }
    }
}

struct AgentKernelToolDefinitionV2: Codable, Equatable, Sendable {
    let name: String
    let summary: String
    let inputArguments: [AgentKernelToolArgumentSchemaV2]
    let outputType: AgentKernelToolIOTypeV2
    let risk: AgentKernelToolRiskV2
    let scopeRequirements: [AgentKernelToolScopeRequirementV2]
    let requiresApproval: Bool
    let denyRules: [AgentKernelToolDenyRuleV2]

    nonisolated init(
        name: String,
        summary: String,
        inputArguments: [AgentKernelToolArgumentSchemaV2],
        outputType: AgentKernelToolIOTypeV2,
        risk: AgentKernelToolRiskV2,
        scopeRequirements: [AgentKernelToolScopeRequirementV2] = [.none],
        requiresApproval: Bool,
        denyRules: [AgentKernelToolDenyRuleV2] = []
    ) {
        self.name = name
        self.summary = summary
        self.inputArguments = inputArguments
        self.outputType = outputType
        self.risk = risk
        self.scopeRequirements = scopeRequirements
        self.requiresApproval = requiresApproval
        self.denyRules = denyRules
    }

    nonisolated var modelSchema: AgentKernelToolSchemaV2 {
        AgentKernelToolSchemaV2(
            name: name,
            summary: summary,
            arguments: inputArguments
        )
    }

    nonisolated var policy: AgentKernelToolPolicyV2 {
        AgentKernelToolPolicyV2(
            toolName: name,
            risk: risk,
            requiresApproval: requiresApproval
        )
    }
}

struct AgentKernelGrantedScopesV2: Codable, Equatable, Sendable {
    let scopes: Set<AgentKernelToolScopeRequirementV2>

    nonisolated init(_ scopes: Set<AgentKernelToolScopeRequirementV2> = [.none]) {
        self.scopes = scopes.union([.none])
    }

    nonisolated func allows(_ requirement: AgentKernelToolScopeRequirementV2) -> Bool {
        scopes.contains(requirement)
    }
}

enum AgentKernelToolValidationDecisionV2: Equatable, Sendable {
    case allowed(AgentKernelToolDefinitionV2)
    case approvalRequired(AgentKernelToolDefinitionV2, AgentKernelApprovalRequestV2)
    case blocked(AgentKernelTerminalReasonV2)
}

struct AgentKernelToolRegistryV2: Sendable {
    private let definitionsByName: [String: AgentKernelToolDefinitionV2]
    private let guards: AgentKernelRuntimeGuardsV2

    nonisolated init(
        definitions: [AgentKernelToolDefinitionV2],
        guards: AgentKernelRuntimeGuardsV2 = AgentKernelRuntimeGuardsV2()
    ) {
        var nextDefinitions: [String: AgentKernelToolDefinitionV2] = [:]
        for definition in definitions {
            nextDefinitions[definition.name] = definition
        }
        self.definitionsByName = nextDefinitions
        self.guards = guards
    }

    nonisolated var modelSchemas: [AgentKernelToolSchemaV2] {
        definitionsByName.values
            .sorted { $0.name < $1.name }
            .map(\.modelSchema)
    }

    nonisolated func definition(named name: String) -> AgentKernelToolDefinitionV2? {
        definitionsByName[name]
    }

    nonisolated func validate(
        call: AgentKernelToolCallV2,
        grantedScopes: AgentKernelGrantedScopesV2,
        ledger: AgentKernelSessionLedgerV2
    ) -> AgentKernelToolValidationDecisionV2 {
        guard let definition = definitionsByName[call.name] else {
            return .blocked(
                AgentKernelTerminalReasonV2(
                    code: "unknown_tool",
                    summary: AgentKernelBoundedTextV2("The requested tool is not registered."),
                    metadata: ["tool": .string(call.name)]
                )
            )
        }

        if let argumentFailure = firstArgumentFailure(call: call, definition: definition) {
            return .blocked(argumentFailure)
        }

        if let scopeFailure = firstScopeFailure(definition: definition, grantedScopes: grantedScopes) {
            return .blocked(scopeFailure)
        }

        if let denyRule = definition.denyRules.first(where: { $0.matches(arguments: call.arguments) }) {
            return .blocked(
                AgentKernelTerminalReasonV2(
                    code: denyRule.reasonCode,
                    summary: denyRule.summary,
                    metadata: [
                        "tool": .string(call.name),
                        "argument": .string(denyRule.argumentName)
                    ]
                )
            )
        }

        switch guards.toolProposalDecision(for: call, ledger: ledger) {
        case .block(let reason):
            return .blocked(reason)
        case .forceSynthesis(let reason):
            return .blocked(reason)
        case .proceed, .requestApproval, .canceled, .resumed:
            break
        }

        switch guards.approvalDecision(
            for: call,
            policy: definition.policy,
            reason: AgentKernelBoundedTextV2(call.reason ?? definition.summary)
        ) {
        case .requestApproval(let approval):
            return .approvalRequired(definition, approval)
        case .block(let reason), .forceSynthesis(let reason), .canceled(let reason):
            return .blocked(reason)
        case .proceed, .resumed:
            return .allowed(definition)
        }
    }

    private nonisolated func firstArgumentFailure(
        call: AgentKernelToolCallV2,
        definition: AgentKernelToolDefinitionV2
    ) -> AgentKernelTerminalReasonV2? {
        let knownArguments = Set(definition.inputArguments.map(\.name))
        let unknownArguments = Set(call.arguments.keys).subtracting(knownArguments)
        if let unknown = unknownArguments.sorted().first {
            return AgentKernelTerminalReasonV2(
                code: "unknown_tool_argument",
                summary: AgentKernelBoundedTextV2("The tool call included an argument that is not in the tool schema."),
                metadata: [
                    "tool": .string(call.name),
                    "argument": .string(unknown)
                ]
            )
        }

        let missingArguments = definition.inputArguments
            .filter(\.isRequired)
            .map(\.name)
            .filter { argumentName in
                (call.arguments[argumentName] ?? "").isEmpty
            }
        if !missingArguments.isEmpty {
            return AgentKernelTerminalReasonV2(
                code: "missing_required_tool_argument",
                summary: AgentKernelBoundedTextV2("The tool call is missing required argument(s): \(missingArguments.joined(separator: ", "))."),
                metadata: [
                    "tool": .string(call.name),
                    "argument": .string(missingArguments[0]),
                    "arguments": .string(missingArguments.joined(separator: ","))
                ]
            )
        }

        for argument in definition.inputArguments {
            guard let value = call.arguments[argument.name] else {
                continue
            }
            if !isValid(value: value, for: argument.type) {
                return AgentKernelTerminalReasonV2(
                    code: "malformed_tool_argument",
                    summary: AgentKernelBoundedTextV2("The tool call argument does not match the declared schema type."),
                    metadata: [
                        "tool": .string(call.name),
                        "argument": .string(argument.name),
                        "type": .string(argument.type.rawValue)
                    ]
                )
            }
        }

        return nil
    }

    private nonisolated func firstScopeFailure(
        definition: AgentKernelToolDefinitionV2,
        grantedScopes: AgentKernelGrantedScopesV2
    ) -> AgentKernelTerminalReasonV2? {
        for requirement in definition.scopeRequirements where !grantedScopes.allows(requirement) {
            return AgentKernelTerminalReasonV2(
                code: "tool_scope_denied",
                summary: AgentKernelBoundedTextV2("The tool requires a scope that has not been granted."),
                metadata: [
                    "tool": .string(definition.name),
                    "scope": .string(requirement.rawValue)
                ]
            )
        }

        return nil
    }

    private nonisolated func isValid(
        value: String,
        for type: AgentKernelToolArgumentTypeV2
    ) -> Bool {
        switch type {
        case .string:
            return true
        case .integer:
            return Int(value) != nil
        case .number:
            return Double(value) != nil
        case .boolean:
            return value == "true" || value == "false"
        case .jsonString:
            guard let data = value.data(using: .utf8) else {
                return false
            }
            return (try? JSONSerialization.jsonObject(with: data)) != nil
        }
    }
}
