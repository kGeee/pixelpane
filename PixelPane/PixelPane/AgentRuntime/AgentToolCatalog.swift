//
//  AgentToolCatalog.swift
//  PixelPane
//
//  Tool specs, executor capabilities, command classification, and the model-visible tool catalog.
//

import Foundation

nonisolated struct AgentToolSpec: Identifiable, Sendable {
    var id: String { schema.name }

    let schema: AgentKernelToolSchema
    let contract: AgentToolContract
    let operationKind: AgentToolOperationKind
    let risk: AgentToolRisk
    let requiredScopes: [AgentPermissionScope]
    let visibleRunModes: [AgentRunPermissionMode]
    let visibleProviderTiers: [AgentModelCapabilityTier]
    let requiresApproval: Bool

    init(
        schema: AgentKernelToolSchema,
        operationKind: AgentToolOperationKind,
        risk: AgentToolRisk,
        requiredScopes: [AgentPermissionScope] = [],
        visibleRunModes: [AgentRunPermissionMode],
        visibleProviderTiers: [AgentModelCapabilityTier],
        requiresApproval: Bool = false
    ) {
        self.schema = schema
        self.contract = AgentToolContract(
            name: schema.name,
            summary: schema.summary,
            operationKind: operationKind,
            risk: risk,
            requiredScopes: requiredScopes,
            visibleRunModes: visibleRunModes,
            visibleProviderTiers: visibleProviderTiers,
            requiresApproval: requiresApproval,
            executorBinding: .localRuntime,
            arguments: schema.arguments.map {
                AgentToolArgumentContract(
                    $0.name,
                    type: $0.type,
                    isRequired: $0.isRequired,
                    summary: $0.summary
                )
            }
        )
        self.operationKind = operationKind
        self.risk = risk
        self.requiredScopes = requiredScopes
        self.visibleRunModes = visibleRunModes
        self.visibleProviderTiers = visibleProviderTiers
        self.requiresApproval = requiresApproval
    }

    var name: String {
        schema.name
    }

    init(contract: AgentToolContract) {
        self.schema = contract.schema
        self.contract = contract
        self.operationKind = contract.operationKind
        self.risk = contract.risk
        self.requiredScopes = contract.requiredScopes
        self.visibleRunModes = contract.visibleRunModes
        self.visibleProviderTiers = contract.visibleProviderTiers
        self.requiresApproval = contract.requiresApproval
    }

    func isVisible(providerTier: AgentModelCapabilityTier, runMode: AgentRunPermissionMode) -> Bool {
        if providerTier == .tierBConstrainedStructuredText,
           operationKind == .fileWriteDraft,
           runMode != .proposalOnly {
            return false
        }
        return visibleProviderTiers.contains(providerTier) && visibleRunModes.contains(runMode)
    }
}

nonisolated enum AgentToolExecutionCapabilities {
    static let activeLocalRuntimeOperations: Set<AgentToolOperationKind> = [
        .fileGrantList,
        .fileList,
        .fileSearch,
        .fileRead,
        .fileWriteDraft,
        .finiteCommand,
        .processSnapshot,
        .localServerDiscovery
    ]
}

nonisolated enum AgentCommandClass: String, Codable, Equatable, Sendable {
    case rawShell
    case fileMutation
    case install
    case network
    case processControl
    case privileged
    case destructive
}

nonisolated struct AgentCommandClassification: Codable, Equatable, Sendable {
    let commandClass: AgentCommandClass
    let reason: AgentPermissionReason
    let summary: AgentRunText

    init(commandClass: AgentCommandClass, reason: AgentPermissionReason, summary: AgentRunText) {
        self.commandClass = commandClass
        self.reason = reason
        self.summary = summary
    }
}

nonisolated struct AgentCommandClassifier: Sendable {
    init() {}

    func classify(_ command: String, sensitivePathRules: [AgentSensitivePathRule]) -> AgentCommandClassification {
        let cleaned = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = cleaned.lowercased()

        if sensitivePathRules.contains(where: { $0.matches(cleaned) }) {
            return AgentCommandClassification(
                commandClass: .destructive,
                reason: .sensitivePathDenied,
                summary: AgentRunText("The command references a sensitive credential or key path.")
            )
        }

        if lowercased.range(of: #"(^|[;&|]\s*)rm\s+(-[^\s]*[rR][fF][^\s]*|-rf|-fr)\s+(/|~|\$HOME|\*)($|\s)"#, options: .regularExpression) != nil
            || lowercased.range(of: #"\bdd\s+.*\bof=/dev/"#, options: .regularExpression) != nil {
            return AgentCommandClassification(
                commandClass: .destructive,
                reason: .unsafeCommandDenied,
                summary: AgentRunText("The command matches a destructive deny rule.")
            )
        }

        if lowercased.range(of: #"\bsudo\b"#, options: .regularExpression) != nil {
            return AgentCommandClassification(
                commandClass: .privileged,
                reason: .privilegedCommandRequiresApproval,
                summary: AgentRunText("Privileged commands require approval.")
            )
        }

        if lowercased.range(of: #"\b(npm|pnpm|yarn|brew|pip3?|gem|cargo)\s+(install|add|upgrade|update)\b"#, options: .regularExpression) != nil
            || lowercased.range(of: #"\bnpx\b"#, options: .regularExpression) != nil {
            return AgentCommandClassification(
                commandClass: .install,
                reason: .installRequiresApproval,
                summary: AgentRunText("Install and package-execution commands require approval.")
            )
        }

        if lowercased.range(of: #"\b(curl|wget|ssh|scp|rsync|nc|telnet)\b"#, options: .regularExpression) != nil {
            return AgentCommandClassification(
                commandClass: .network,
                reason: .networkRequiresApproval,
                summary: AgentRunText("Network commands require approval.")
            )
        }

        if lowercased.range(of: #"\b(kill|killall|pkill|launchctl)\b"#, options: .regularExpression) != nil {
            return AgentCommandClassification(
                commandClass: .processControl,
                reason: .processControlRequiresApproval,
                summary: AgentRunText("Process-control commands require approval.")
            )
        }

        if lowercased.range(of: #"\b(rm|mv|cp|mkdir|touch|chmod|chown|tee)\b"#, options: .regularExpression) != nil
            || lowercased.range(of: #"(?:^|[^2])>{1,2}\s*[^\s&]"#, options: .regularExpression) != nil {
            return AgentCommandClassification(
                commandClass: .fileMutation,
                reason: .fileMutationRequiresApproval,
                summary: AgentRunText("File mutation commands require approval.")
            )
        }

        return AgentCommandClassification(
            commandClass: .rawShell,
            reason: .rawShellRequiresApproval,
            summary: AgentRunText("Raw shell commands require approval.")
        )
    }

}

nonisolated struct AgentToolCatalog: Sendable {
    private let specsByName: [String: AgentToolSpec]

    init(specs: [AgentToolSpec] = AgentToolCatalog.defaultSpecs) {
        self.specsByName = Dictionary(uniqueKeysWithValues: specs.map { ($0.name, $0) })
    }

    func spec(named name: String) -> AgentToolSpec? {
        specsByName[name]
    }

    func visibleToolSpecs(
        providerTier: AgentModelCapabilityTier,
        runMode: AgentRunPermissionMode,
        localGrants: [AgentLocalFileGrant] = [],
        grantedScopes: [AgentPermissionScope] = [],
        deniedScopes: [AgentPermissionScope] = [],
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations
    ) -> [AgentToolSpec] {
        specsByName.values
            .filter { spec in
                spec.isVisible(providerTier: providerTier, runMode: runMode)
                    && supportedOperations.contains(spec.operationKind)
                    && !spec.requiredScopes.contains(where: { deniedScopes.contains($0) })
                    && hasRequiredVisibilityGrants(for: spec, localGrants: localGrants, grantedScopes: grantedScopes)
            }
            .sorted { $0.name < $1.name }
    }

    func visibleModelSchemas(
        providerTier: AgentModelCapabilityTier,
        runMode: AgentRunPermissionMode,
        localGrants: [AgentLocalFileGrant] = [],
        grantedScopes: [AgentPermissionScope] = [],
        deniedScopes: [AgentPermissionScope] = [],
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations
    ) -> [AgentKernelToolSchema] {
        visibleToolSpecs(
            providerTier: providerTier,
            runMode: runMode,
            localGrants: localGrants,
            grantedScopes: grantedScopes,
            deniedScopes: deniedScopes,
            supportedOperations: supportedOperations
        ).map(\.schema)
    }

    func visibilityDiagnostics(
        providerTier: AgentModelCapabilityTier,
        runMode: AgentRunPermissionMode,
        localGrants: [AgentLocalFileGrant] = [],
        grantedScopes: [AgentPermissionScope] = [],
        deniedScopes: [AgentPermissionScope] = [],
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations
    ) -> [String] {
        specsByName.values
            .sorted { $0.name < $1.name }
            .map { spec in
                let reason: String
                if !spec.visibleProviderTiers.contains(providerTier) {
                    reason = "withheld:providerTier"
                } else if !spec.isVisible(providerTier: providerTier, runMode: runMode) {
                    reason = "withheld:runMode"
                } else if !supportedOperations.contains(spec.operationKind) {
                    reason = "withheld:unsupportedOperation"
                } else if let deniedScope = spec.requiredScopes.first(where: { deniedScopes.contains($0) }) {
                    reason = "withheld:deniedScope:\(deniedScope.rawValue)"
                } else if spec.requiredScopes.contains(.fileRead), localGrants.isEmpty {
                    reason = "withheld:missingReadGrant"
                } else if spec.requiredScopes.contains(.fileWrite), localGrants.isEmpty {
                    reason = "withheld:missingFileGrant"
                } else if let missingScope = spec.requiredScopes.first(where: { scope in
                    scope != .fileRead
                        && scope != .fileWrite
                        && scope != .workingDirectory
                        && scope != .localServer
                        && !grantedScopes.contains(scope)
                }) {
                    reason = "withheld:missingScope:\(missingScope.rawValue)"
                } else {
                    reason = "visible"
                }
                return "tool.\(spec.name)=\(reason)"
            }
    }

    private func hasRequiredVisibilityGrants(
        for spec: AgentToolSpec,
        localGrants: [AgentLocalFileGrant],
        grantedScopes: [AgentPermissionScope]
    ) -> Bool {
        if spec.operationKind == .fileGrantList {
            return true
        }
        if spec.requiredScopes.contains(.fileRead), localGrants.isEmpty {
            return false
        }
        if spec.requiredScopes.contains(.fileWrite), localGrants.isEmpty {
            return false
        }
        let nonGrantScopes = spec.requiredScopes.filter { scope in
            scope != .fileRead
                && scope != .fileWrite
                && scope != .workingDirectory
                && scope != .localServer
        }
        return nonGrantScopes.allSatisfy { grantedScopes.contains($0) }
    }
}

extension AgentToolCatalog {
    nonisolated static var defaultSpecs: [AgentToolSpec] {
        AgentToolContractLibrary.defaultContracts.map(AgentToolSpec.init(contract:))
    }
}

