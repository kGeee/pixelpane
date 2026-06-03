import Foundation

nonisolated struct AgentPermissionPolicy: Sendable {
    let catalog: AgentToolCatalog
    let sensitivePathRules: [AgentSensitivePathRule]
    let commandClassifier: AgentCommandClassifier
    let pathResolver: AgentLocalPathResolver

    init(
        catalog: AgentToolCatalog = AgentToolCatalog(),
        sensitivePathRules: [AgentSensitivePathRule] = AgentPermissionPolicy.defaultSensitivePathRules,
        commandClassifier: AgentCommandClassifier = AgentCommandClassifier(),
        pathResolver: AgentLocalPathResolver = AgentLocalPathResolver()
    ) {
        self.catalog = catalog
        self.sensitivePathRules = sensitivePathRules
        self.commandClassifier = commandClassifier
        self.pathResolver = pathResolver
    }

    func decision(for rawRequest: AgentPermissionRequest) -> AgentPermissionDecision {
        guard let spec = catalog.spec(named: rawRequest.toolName) else {
            return deny(
                reason: .unknownTool,
                summary: "The requested tool is not registered.",
                toolName: rawRequest.toolName
            )
        }

        guard rawRequest.supportedOperations.contains(spec.operationKind) else {
            return deny(
                reason: .unsupportedOperation,
                summary: "The active runtime does not support this tool operation.",
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["operation": .string(spec.operationKind.rawValue)]
            )
        }

        guard spec.visibleProviderTiers.contains(rawRequest.providerTier) else {
            return deny(
                reason: .providerTierDisallowsTool,
                summary: "The selected provider tier cannot use this tool.",
                toolName: spec.name,
                risk: spec.risk
            )
        }
        guard spec.isVisible(providerTier: rawRequest.providerTier, runMode: rawRequest.runMode) else {
            return deny(
                reason: .runModeDisallowsTool,
                summary: "The current run mode cannot use this tool.",
                toolName: spec.name,
                risk: spec.risk
            )
        }

        let invocation: AgentToolInvocation
        do {
            invocation = try spec.contract.normalizedInvocation(rawArguments: rawRequest.arguments)
        } catch let error as AgentToolContractError {
            return argumentFailure(spec: spec, error: error)
        } catch {
            return deny(
                reason: .malformedArgument,
                summary: "The tool call arguments could not be normalized.",
                toolName: spec.name,
                risk: spec.risk
            )
        }
        let request = rawRequest.replacingArguments(invocation.normalizedArguments)

        if let deniedScope = spec.requiredScopes.first(where: { request.deniedScopes.contains($0) }) {
            return deny(
                reason: .deniedScope,
                summary: "A required permission scope is explicitly denied.",
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["scope": .string(deniedScope.rawValue)]
            )
        }
        if let sensitive = sensitivePathFailure(spec: spec, arguments: request.arguments) {
            return sensitive
        }
        if let grantFailure = localGrantFailure(spec: spec, request: request) {
            return grantFailure
        }
        if let scopeFailure = missingScopeFailure(spec: spec, request: request) {
            return scopeFailure
        }

        if spec.operationKind == .finiteCommand {
            return commandDecision(spec: spec, request: request)
        }

        if spec.requiresApproval {
            if hasApprovalGrant(for: request) {
                return allow(
                    reason: .approvalGrantMatched,
                    summary: "A matching approval grant allows this tool request.",
                    toolName: spec.name,
                    risk: spec.risk
                )
            }
            return ask(
                reason: .approvalRequired,
                summary: "This tool request requires app-owned user approval.",
                toolName: spec.name,
                risk: spec.risk
            )
        }

        return allow(
            reason: .allowed,
            summary: "The tool request is allowed by policy.",
            toolName: spec.name,
            risk: spec.risk
        )
    }

    func referencesSensitivePath(_ value: String) -> Bool {
        sensitivePathRules.contains { $0.matches(value) }
    }

    static func approvalDigest(toolName: String, arguments: [String: String]) -> String {
        let serialized = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(toolName):\(serialized)"
    }

    private func argumentFailure(spec: AgentToolSpec, error: AgentToolContractError) -> AgentPermissionDecision {
        switch error {
        case .unknownTool(let tool):
            return deny(
                reason: .unknownTool,
                summary: "The requested tool is not registered.",
                toolName: tool,
                risk: spec.risk
            )
        case .unknownArgument(let argument):
            return deny(
                reason: .malformedArgument,
                summary: "The tool call included an argument that is not in the schema.",
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["argument": .string(argument)]
            )
        case .missingRequiredArgument(let argument):
            return deny(
                reason: .missingRequiredArgument,
                summary: "The tool call is missing a required argument.",
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["argument": .string(argument)]
            )
        case .malformedArgument(let argument, let type, _):
            return deny(
                reason: .malformedArgument,
                summary: "The tool call argument does not match its declared type.",
                toolName: spec.name,
                risk: spec.risk,
                metadata: [
                    "argument": .string(argument),
                    "type": .string(type.rawValue)
                ]
            )
        case .constraintViolation(let argument, let summary):
            return deny(
                reason: .malformedArgument,
                summary: summary,
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["argument": .string(argument)]
            )
        }
    }

    private func sensitivePathFailure(
        spec: AgentToolSpec,
        arguments: [String: String]
    ) -> AgentPermissionDecision? {
        let valuesToCheck = pathLikeArgumentValues(for: spec, arguments: arguments)
        guard let matchedValue = valuesToCheck.first(where: { value in
            sensitivePathRules.contains(where: { $0.matches(value) })
        }) else {
            return nil
        }
        return deny(
            reason: .sensitivePathDenied,
            summary: "The request references a sensitive credential or key path.",
            toolName: spec.name,
            risk: spec.risk,
            metadata: ["path": .string(matchedValue)]
        )
    }

    private func localGrantFailure(
        spec: AgentToolSpec,
        request: AgentPermissionRequest
    ) -> AgentPermissionDecision? {
        if spec.requiredScopes.contains(.fileRead) {
            guard let rawPath = primaryPathArgument(for: spec, arguments: request.arguments) else {
                return nil
            }
            let resolution = pathResolver.resolve(
                rawPath,
                grants: request.localGrants,
                access: .read,
                target: .any,
                preferredDirectoryPath: request.arguments["preferredDirectoryPath"]
            )
            if let failure = resolution.failure {
                return localPathFailureDecision(
                    failure,
                    rawPath: rawPath,
                    spec: spec
                )
            }
        }

        if spec.requiredScopes.contains(.fileWrite) {
            guard let rawPath = primaryPathArgument(for: spec, arguments: request.arguments) else {
                return nil
            }
            let resolution = pathResolver.resolve(
                rawPath,
                grants: request.localGrants,
                access: .write,
                target: .any,
                preferredDirectoryPath: request.arguments["preferredDirectoryPath"]
            )
            if let failure = resolution.failure {
                return localPathFailureDecision(
                    failure,
                    rawPath: rawPath,
                    spec: spec
                )
            }
        }

        if spec.requiredScopes.contains(.workingDirectory) {
            guard let workingDirectory = request.arguments["workingDirectory"] else {
                return nil
            }
            let resolution = pathResolver.resolve(
                workingDirectory,
                grants: request.localGrants,
                access: .read,
                target: .any
            )
            if let failure = resolution.failure {
                return localPathFailureDecision(
                    failure,
                    rawPath: workingDirectory,
                    spec: spec
                )
            }
        }

        return nil
    }

    private func localPathFailureDecision(
        _ failure: AgentLocalPathResolutionFailure,
        rawPath: String,
        spec: AgentToolSpec
    ) -> AgentPermissionDecision {
        switch failure.code {
        case .noMatchingGrant:
            return ask(
                reason: .missingFileGrant,
                summary: failure.summary.text,
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["path": .string(rawPath)]
            )
        case .emptyPath:
            return deny(
                reason: .missingRequiredArgument,
                summary: failure.summary.text,
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["path": .string(rawPath)]
            )
        case .ambiguousRelativePath,
             .pathDoesNotExist,
             .pathIsNotFile,
             .pathIsNotDirectory,
             .targetIsDirectory,
             .parentDirectoryMissing:
            return deny(
                reason: .malformedArgument,
                summary: failure.summary.text,
                toolName: spec.name,
                risk: spec.risk,
                metadata: ["path": .string(rawPath)]
            )
        }
    }

    private func missingScopeFailure(
        spec: AgentToolSpec,
        request: AgentPermissionRequest
    ) -> AgentPermissionDecision? {
        for scope in spec.requiredScopes {
            switch scope {
            case .fileRead, .fileWrite, .workingDirectory, .localServer:
                continue
            case .visualContext, .network, .processControl, .privileged:
                guard request.grantedScopes.contains(scope) else {
                    return ask(
                        reason: .approvalRequired,
                        summary: "The tool needs a permission scope that has not been granted for this run.",
                        toolName: spec.name,
                        risk: spec.risk,
                        metadata: ["scope": .string(scope.rawValue)]
                    )
                }
            }
        }
        return nil
    }

    private func commandDecision(
        spec: AgentToolSpec,
        request: AgentPermissionRequest
    ) -> AgentPermissionDecision {
        let command = request.arguments["command"] ?? ""
        let classification = commandClassifier.classify(command, sensitivePathRules: sensitivePathRules)

        switch classification.commandClass {
        case .destructive:
            return deny(
                reason: classification.reason,
                summary: classification.summary.text,
                toolName: spec.name,
                risk: .privileged,
                metadata: ["command": .string(command)]
            )
        case .rawShell:
            guard request.runMode == .fullAgent else {
                return deny(
                    reason: .rawShellRequiresApproval,
                    summary: "Raw shell commands are denied outside full-agent mode.",
                    toolName: spec.name,
                    risk: spec.risk,
                    metadata: ["command": .string(command)]
                )
            }
            return approvalOrAsk(spec: spec, request: request, reason: classification.reason, summary: classification.summary)
        case .fileMutation:
            guard request.runMode == .fullAgent else {
                return deny(
                    reason: .fileMutationRequiresApproval,
                    summary: "File mutation commands are denied outside full-agent mode.",
                    toolName: spec.name,
                    risk: spec.risk,
                    metadata: ["command": .string(command)]
                )
            }
            return approvalOrAsk(spec: spec, request: request, reason: classification.reason, summary: classification.summary)
        case .install:
            guard request.runMode == .fullAgent else {
                return deny(
                    reason: .installRequiresApproval,
                    summary: "Install commands are denied outside full-agent mode.",
                    toolName: spec.name,
                    risk: spec.risk,
                    metadata: ["command": .string(command)]
                )
            }
            return approvalOrAsk(spec: spec, request: request, reason: classification.reason, summary: classification.summary)
        case .network:
            guard !request.deniedScopes.contains(.network) else {
                return deny(
                    reason: .deniedScope,
                    summary: "Network commands are denied by scope policy.",
                    toolName: spec.name,
                    risk: .network,
                    metadata: ["scope": .string(AgentPermissionScope.network.rawValue)]
                )
            }
            guard request.runMode == .fullAgent else {
                return deny(
                    reason: .networkRequiresApproval,
                    summary: "Network commands are denied outside full-agent mode.",
                    toolName: spec.name,
                    risk: .network,
                    metadata: ["command": .string(command)]
                )
            }
            return approvalOrAsk(spec: spec, request: request, reason: classification.reason, summary: classification.summary)
        case .processControl:
            guard !request.deniedScopes.contains(.processControl) else {
                return deny(
                    reason: .deniedScope,
                    summary: "Process-control commands are denied by scope policy.",
                    toolName: spec.name,
                    risk: .processControl,
                    metadata: ["scope": .string(AgentPermissionScope.processControl.rawValue)]
                )
            }
            guard request.runMode == .fullAgent else {
                return deny(
                    reason: .processControlRequiresApproval,
                    summary: "Process-control commands are denied outside full-agent mode.",
                    toolName: spec.name,
                    risk: .processControl,
                    metadata: ["command": .string(command)]
                )
            }
            return approvalOrAsk(spec: spec, request: request, reason: classification.reason, summary: classification.summary)
        case .privileged:
            guard !request.deniedScopes.contains(.privileged) else {
                return deny(
                    reason: .deniedScope,
                    summary: "Privileged commands are denied by scope policy.",
                    toolName: spec.name,
                    risk: .privileged,
                    metadata: ["scope": .string(AgentPermissionScope.privileged.rawValue)]
                )
            }
            guard request.runMode == .fullAgent else {
                return deny(
                    reason: .privilegedCommandRequiresApproval,
                    summary: "Privileged commands are denied outside full-agent mode.",
                    toolName: spec.name,
                    risk: .privileged,
                    metadata: ["command": .string(command)]
                )
            }
            return approvalOrAsk(spec: spec, request: request, reason: classification.reason, summary: classification.summary)
        }
    }

    private func approvalOrAsk(
        spec: AgentToolSpec,
        request: AgentPermissionRequest,
        reason: AgentPermissionReason,
        summary: AgentRunText
    ) -> AgentPermissionDecision {
        if hasApprovalGrant(for: request) {
            return allow(
                reason: .approvalGrantMatched,
                summary: "A matching approval grant allows this tool request.",
                toolName: spec.name,
                risk: spec.risk
            )
        }
        return ask(
            reason: reason,
            summary: summary.text,
            toolName: spec.name,
            risk: spec.risk
        )
    }

    private func hasApprovalGrant(for request: AgentPermissionRequest) -> Bool {
        let digest = Self.approvalDigest(toolName: request.toolName, arguments: request.arguments)
        return request.approvalGrants.contains { grant in
            grant.matches(toolName: request.toolName, argumentDigest: digest, now: request.now)
        }
    }

    private func primaryPathArgument(for spec: AgentToolSpec, arguments: [String: String]) -> String? {
        switch spec.operationKind {
        case .fileRead, .fileList:
            return arguments["path"]
        case .fileSearch:
            return arguments["rootPath"]
        case .fileWriteDraft:
            return arguments["targetPath"]
        case .finiteCommand, .processStart:
            return arguments["workingDirectory"]
        default:
            return nil
        }
    }

    private func pathLikeArgumentValues(for spec: AgentToolSpec, arguments: [String: String]) -> [String] {
        spec.contract.pathLikeArgumentValues(in: arguments)
    }

    private func allow(
        reason: AgentPermissionReason,
        summary: String,
        toolName: String,
        risk: AgentToolRisk? = nil,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) -> AgentPermissionDecision {
        AgentPermissionDecision(
            kind: .allow,
            reason: reason,
            summary: AgentRunText(summary),
            toolName: toolName,
            risk: risk,
            metadata: metadata
        )
    }

    private func ask(
        reason: AgentPermissionReason,
        summary: String,
        toolName: String,
        risk: AgentToolRisk? = nil,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) -> AgentPermissionDecision {
        AgentPermissionDecision(
            kind: .ask,
            reason: reason,
            summary: AgentRunText(summary),
            toolName: toolName,
            risk: risk,
            metadata: metadata
        )
    }

    private func deny(
        reason: AgentPermissionReason,
        summary: String,
        toolName: String,
        risk: AgentToolRisk? = nil,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) -> AgentPermissionDecision {
        AgentPermissionDecision(
            kind: .deny,
            reason: reason,
            summary: AgentRunText(summary),
            toolName: toolName,
            risk: risk,
            metadata: metadata
        )
    }
}

extension AgentPermissionPolicy {
    nonisolated static var defaultSensitivePathRules: [AgentSensitivePathRule] {
        [
            AgentSensitivePathRule(
                id: "env-files",
                exactFilenames: [".env", ".env.local", ".env.development", ".env.production", ".env.test"],
                substrings: ["/.env."],
                summary: AgentRunText("Environment files often contain secrets.")
            ),
            AgentSensitivePathRule(
                id: "private-keys",
                exactFilenames: ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"],
                filenameSuffixes: [".pem", ".key", ".p12", ".pfx"],
                pathComponents: [".ssh"],
                summary: AgentRunText("Private keys and SSH material are sensitive.")
            ),
            AgentSensitivePathRule(
                id: "cloud-credentials",
                exactFilenames: ["credentials", "credentials.json", "service-account.json"],
                pathComponents: [".aws", ".azure", "gcloud"],
                substrings: ["service-account", "google_application_credentials"],
                summary: AgentRunText("Cloud credential files are sensitive.")
            ),
            AgentSensitivePathRule(
                id: "signing-keychains",
                filenameSuffixes: [".keychain", ".keychain-db", ".mobileprovision", ".cer", ".crt"],
                pathComponents: ["keychains"],
                summary: AgentRunText("Signing credentials and keychains are sensitive.")
            ),
            AgentSensitivePathRule(
                id: "package-auth",
                exactFilenames: [".npmrc", ".pypirc", ".netrc", "auth.json"],
                pathComponents: [".docker", ".cargo", ".gem", ".kube"],
                substrings: [".cargo/credentials", ".docker/config.json", ".kube/config"],
                summary: AgentRunText("Package-manager and service auth files are sensitive.")
            ),
            AgentSensitivePathRule(
                id: "hidden-credential-stores",
                pathComponents: [".gnupg", ".password-store", ".1password", "keyrings"],
                summary: AgentRunText("Hidden credential stores are sensitive.")
            )
        ]
    }
}
