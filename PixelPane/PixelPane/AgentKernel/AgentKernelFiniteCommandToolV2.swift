import Foundation

enum AgentKernelFiniteCommandObservationKindV2: String, Codable, Equatable, Sendable {
    case succeeded
    case emptyOutput
    case nonZeroExit
    case timedOut
    case failedToStart
}

enum AgentKernelCommandPolicyActionV2: String, Codable, Equatable, Sendable {
    case allow
    case requireApproval
    case block
}

struct AgentKernelCommandPolicyRuleV2: Codable, Equatable, Sendable {
    let id: String
    let action: AgentKernelCommandPolicyActionV2
    let risk: AgentKernelToolRiskV2
    let patterns: [String]
    let summary: AgentKernelBoundedTextV2

    nonisolated init(
        id: String,
        action: AgentKernelCommandPolicyActionV2,
        risk: AgentKernelToolRiskV2,
        patterns: [String],
        summary: AgentKernelBoundedTextV2
    ) {
        self.id = id
        self.action = action
        self.risk = risk
        self.patterns = patterns
        self.summary = summary
    }

    nonisolated func matches(_ command: String) -> Bool {
        patterns.contains { pattern in
            command.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

struct AgentKernelCommandPolicyDecisionV2: Codable, Equatable, Sendable {
    let action: AgentKernelCommandPolicyActionV2
    let risk: AgentKernelToolRiskV2
    let reasonCode: String
    let summary: AgentKernelBoundedTextV2

    nonisolated init(
        action: AgentKernelCommandPolicyActionV2,
        risk: AgentKernelToolRiskV2,
        reasonCode: String,
        summary: AgentKernelBoundedTextV2
    ) {
        self.action = action
        self.risk = risk
        self.reasonCode = reasonCode
        self.summary = summary
    }
}

struct AgentKernelFiniteCommandOutputV2: Codable, Equatable, Sendable {
    let summary: AgentKernelBoundedTextV2
    let observationKind: AgentKernelFiniteCommandObservationKindV2
    let command: String
    let workingDirectory: String
    let exitCode: Int32?
    let stdout: AgentKernelBoundedTextV2
    let stderr: AgentKernelBoundedTextV2
    let durationSeconds: Double
    let didTimeOut: Bool
    let wasOutputTruncated: Bool
    let sources: [AgentKernelToolSourceRecordV2]
}

struct AgentKernelFiniteCommandToolV2: Sendable {
    let maxOutputBytes: Int
    let defaultTimeoutSeconds: Int
    let maxTimeoutSeconds: Int
    let policyRules: [AgentKernelCommandPolicyRuleV2]

    nonisolated init(
        maxOutputBytes: Int = 48_000,
        defaultTimeoutSeconds: Int = 30,
        maxTimeoutSeconds: Int = 120,
        policyRules: [AgentKernelCommandPolicyRuleV2] = AgentKernelFiniteCommandToolV2.defaultPolicyRules
    ) {
        self.maxOutputBytes = max(1, maxOutputBytes)
        self.defaultTimeoutSeconds = max(1, defaultTimeoutSeconds)
        self.maxTimeoutSeconds = max(1, maxTimeoutSeconds)
        self.policyRules = policyRules
    }

    nonisolated static var definition: AgentKernelToolDefinitionV2 {
        AgentKernelToolDefinitionV2(
            name: "run_finite_command",
            summary: "Run a bounded terminal command that is expected to finish.",
            inputArguments: [
                AgentKernelToolArgumentSchemaV2(
                    name: "command",
                    type: .string,
                    summary: "Shell command to run."
                ),
                AgentKernelToolArgumentSchemaV2(
                    name: "workingDirectory",
                    type: .string,
                    summary: "Validated working directory."
                ),
                AgentKernelToolArgumentSchemaV2(
                    name: "timeoutSeconds",
                    type: .integer,
                    isRequired: false,
                    summary: "Optional timeout in seconds."
                )
            ],
            outputType: AgentKernelToolIOTypeV2(
                name: "finite_command_result",
                summary: "Exit status, bounded output, duration, and source record."
            ),
            risk: .readOnly,
            scopeRequirements: [.workingDirectory],
            requiresApproval: false
        )
    }

    nonisolated static var defaultPolicyRules: [AgentKernelCommandPolicyRuleV2] {
        [
            AgentKernelCommandPolicyRuleV2(
                id: "block-destructive-root-removal",
                action: .block,
                risk: .privileged,
                patterns: [
                    #"(^|[;&|]\s*)rm\s+(-[^\s]*[rR][fF][^\s]*|-rf|-fr)\s+(/|~|\$HOME|\*)($|\s)"#,
                    #"\bdd\s+.*\bof=/dev/"#
                ],
                summary: AgentKernelBoundedTextV2("The command matches a destructive blocked-command rule.")
            ),
            AgentKernelCommandPolicyRuleV2(
                id: "approval-privileged",
                action: .requireApproval,
                risk: .privileged,
                patterns: [#"\bsudo\b"#],
                summary: AgentKernelBoundedTextV2("Privileged commands require approval.")
            ),
            AgentKernelCommandPolicyRuleV2(
                id: "approval-install",
                action: .requireApproval,
                risk: .sideEffect,
                patterns: [
                    #"\b(npm|pnpm|yarn|brew|pip3?|gem|cargo)\s+(install|add|upgrade|update)\b"#,
                    #"\bnpx\b"#
                ],
                summary: AgentKernelBoundedTextV2("Install and package-execution commands require approval.")
            ),
            AgentKernelCommandPolicyRuleV2(
                id: "approval-network",
                action: .requireApproval,
                risk: .sideEffect,
                patterns: [#"\b(curl|wget|ssh|scp|rsync|nc|telnet)\b"#],
                summary: AgentKernelBoundedTextV2("Network commands require approval.")
            ),
            AgentKernelCommandPolicyRuleV2(
                id: "approval-process-control",
                action: .requireApproval,
                risk: .sideEffect,
                patterns: [#"\b(kill|killall|pkill|launchctl)\b"#],
                summary: AgentKernelBoundedTextV2("Process-control commands require approval.")
            ),
            AgentKernelCommandPolicyRuleV2(
                id: "approval-file-mutation",
                action: .requireApproval,
                risk: .sideEffect,
                patterns: [
                    #"\b(rm|mv|cp|mkdir|touch|chmod|chown|tee)\b"#,
                    #"(?:^|[^2])>{1,2}\s*[^\s&]"#
                ],
                summary: AgentKernelBoundedTextV2("File mutation commands require approval.")
            )
        ]
    }

    nonisolated func validate(
        call: AgentKernelToolCallV2,
        grantedScopes: AgentKernelGrantedScopesV2,
        ledger: AgentKernelSessionLedgerV2
    ) -> AgentKernelToolValidationDecisionV2 {
        let registry = AgentKernelToolRegistryV2(definitions: [Self.definition])
        let baseDecision = registry.validate(
            call: call,
            grantedScopes: grantedScopes,
            ledger: ledger
        )
        guard case .allowed(let definition) = baseDecision else {
            return baseDecision
        }

        let command = call.arguments["command"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !command.isEmpty else {
            return .blocked(
                reason(
                    code: "empty_command",
                    summary: "Command cannot be empty."
                )
            )
        }

        let timeoutSeconds = parsedTimeoutSeconds(call.arguments["timeoutSeconds"])
        guard timeoutSeconds <= maxTimeoutSeconds else {
            return .blocked(
                reason(
                    code: "command_timeout_too_large",
                    summary: "The requested timeout exceeds the finite command limit.",
                    metadata: ["timeoutSeconds": .int(timeoutSeconds), "limit": .int(maxTimeoutSeconds)]
                )
            )
        }

        let policyDecision = classify(command: command)
        switch policyDecision.action {
        case .allow:
            return .allowed(definition)
        case .requireApproval:
            return .approvalRequired(
                definition,
                AgentKernelApprovalRequestV2(
                    toolCallID: call.id,
                    toolName: call.name,
                    riskClass: policyDecision.risk.rawValue,
                    reason: policyDecision.summary,
                    displaySummary: AgentKernelBoundedTextV2("Run finite command"),
                    operationPreview: AgentKernelBoundedTextV2(command)
                )
            )
        case .block:
            return .blocked(
                reason(
                    code: policyDecision.reasonCode,
                    summary: policyDecision.summary.text,
                    metadata: ["command": .string(command)]
                )
            )
        }
    }

    nonisolated func classify(command: String) -> AgentKernelCommandPolicyDecisionV2 {
        let cleanedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        for rule in policyRules where rule.matches(cleanedCommand) {
            return AgentKernelCommandPolicyDecisionV2(
                action: rule.action,
                risk: rule.risk,
                reasonCode: rule.id,
                summary: rule.summary
            )
        }
        return AgentKernelCommandPolicyDecisionV2(
            action: .allow,
            risk: .readOnly,
            reasonCode: "low_risk_command",
            summary: AgentKernelBoundedTextV2("The command does not match a risky command policy rule.")
        )
    }

    nonisolated func run(
        command: String,
        workingDirectory: String,
        allowedWorkingDirectories: [String],
        timeoutSeconds requestedTimeoutSeconds: Int? = nil
    ) -> Result<AgentKernelFiniteCommandOutputV2, AgentKernelTerminalReasonV2> {
        let timeoutSeconds = min(max(1, requestedTimeoutSeconds ?? defaultTimeoutSeconds), maxTimeoutSeconds)
        switch validatedWorkingDirectory(
            workingDirectory,
            allowedWorkingDirectories: allowedWorkingDirectories
        ) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let cwd):
            return runValidated(
                command: command,
                workingDirectory: cwd,
                timeoutSeconds: timeoutSeconds
            )
        }
    }

    private nonisolated func runValidated(
        command: String,
        workingDirectory: URL,
        timeoutSeconds: Int
    ) -> Result<AgentKernelFiniteCommandOutputV2, AgentKernelTerminalReasonV2> {
        let cleanedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedCommand.isEmpty else {
            return .failure(reason(code: "empty_command", summary: "Command cannot be empty."))
        }

        let startedAt = Date()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let collector = AgentKernelCommandOutputCollectorV2(maxBytes: maxOutputBytes)

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", cleanedCommand]
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendStdout(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.appendStderr(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return .success(
                output(
                    kind: .failedToStart,
                    command: cleanedCommand,
                    workingDirectory: workingDirectory.path,
                    exitCode: nil,
                    stdout: "",
                    stderr: error.localizedDescription,
                    durationSeconds: Date().timeIntervalSince(startedAt),
                    didTimeOut: false,
                    wasOutputTruncated: false
                )
            )
        }

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            finished.signal()
        }

        let didTimeOut = finished.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut
        if didTimeOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + .milliseconds(750))
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        collector.appendStdout((try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data())
        collector.appendStderr((try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data())

        let duration = Date().timeIntervalSince(startedAt)
        let stdout = collector.stdoutText
        let stderr = collector.stderrText
        let kind: AgentKernelFiniteCommandObservationKindV2
        if didTimeOut {
            kind = .timedOut
        } else if process.terminationStatus != 0 {
            kind = .nonZeroExit
        } else if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kind = .emptyOutput
        } else {
            kind = .succeeded
        }

        return .success(
            output(
                kind: kind,
                command: cleanedCommand,
                workingDirectory: workingDirectory.path,
                exitCode: didTimeOut ? nil : process.terminationStatus,
                stdout: stdout,
                stderr: stderr,
                durationSeconds: duration,
                didTimeOut: didTimeOut,
                wasOutputTruncated: collector.wasTruncated
            )
        )
    }

    private nonisolated func output(
        kind: AgentKernelFiniteCommandObservationKindV2,
        command: String,
        workingDirectory: String,
        exitCode: Int32?,
        stdout: String,
        stderr: String,
        durationSeconds: Double,
        didTimeOut: Bool,
        wasOutputTruncated: Bool
    ) -> AgentKernelFiniteCommandOutputV2 {
        let summaryText: String
        switch kind {
        case .succeeded:
            summaryText = "Finite command succeeded."
        case .emptyOutput:
            summaryText = "Finite command succeeded with empty output."
        case .nonZeroExit:
            summaryText = "Finite command exited with code \(exitCode ?? -1)."
        case .timedOut:
            summaryText = "Finite command timed out."
        case .failedToStart:
            summaryText = "Finite command failed to start."
        }

        return AgentKernelFiniteCommandOutputV2(
            summary: AgentKernelBoundedTextV2(summaryText),
            observationKind: kind,
            command: command,
            workingDirectory: workingDirectory,
            exitCode: exitCode,
            stdout: AgentKernelBoundedTextV2(stdout),
            stderr: AgentKernelBoundedTextV2(stderr),
            durationSeconds: durationSeconds,
            didTimeOut: didTimeOut,
            wasOutputTruncated: wasOutputTruncated,
            sources: [
                AgentKernelToolSourceRecordV2(
                    id: "finite-command:\(UUID().uuidString)",
                    kind: "finite_command",
                    path: workingDirectory,
                    displayName: "Terminal Output",
                    summary: AgentKernelBoundedTextV2(summaryText),
                    isTruncated: wasOutputTruncated,
                    metadata: [
                        "observationKind": .string(kind.rawValue),
                        "exitCode": .int(Int(exitCode ?? -1)),
                        "didTimeOut": .bool(didTimeOut)
                    ]
                )
            ]
        )
    }

    private nonisolated func validatedWorkingDirectory(
        _ workingDirectory: String,
        allowedWorkingDirectories: [String]
    ) -> Result<URL, AgentKernelTerminalReasonV2> {
        let cleanedPath = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPath.isEmpty else {
            return .failure(reason(code: "empty_working_directory", summary: "Working directory cannot be empty."))
        }
        let candidate = URL(fileURLWithPath: cleanedPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(
                reason(
                    code: "working_directory_not_found",
                    summary: "Working directory does not exist.",
                    metadata: ["workingDirectory": .string(candidate.path)]
                )
            )
        }

        let allowedRoots = allowedWorkingDirectories
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { !$0.isEmpty }
        guard !allowedRoots.isEmpty else {
            return .failure(
                reason(
                    code: "working_directory_scope_denied",
                    summary: "No working directory roots are available for command execution."
                )
            )
        }
        guard allowedRoots.contains(where: { root in
            candidate.path == root || candidate.path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }) else {
            return .failure(
                reason(
                    code: "working_directory_scope_denied",
                    summary: "The working directory is outside the allowed roots.",
                    metadata: ["workingDirectory": .string(candidate.path)]
                )
            )
        }
        return .success(candidate)
    }

    private nonisolated func parsedTimeoutSeconds(_ raw: String?) -> Int {
        guard let raw, let value = Int(raw) else {
            return defaultTimeoutSeconds
        }
        return max(1, value)
    }

    private nonisolated func reason(
        code: String,
        summary: String,
        metadata: [String: AgentKernelMetadataValueV2] = [:]
    ) -> AgentKernelTerminalReasonV2 {
        AgentKernelTerminalReasonV2(
            code: code,
            summary: AgentKernelBoundedTextV2(summary),
            metadata: metadata
        )
    }
}

private final class AgentKernelCommandOutputCollectorV2: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private nonisolated(unsafe) var stdoutData = Data()
    private nonisolated(unsafe) var stderrData = Data()
    private(set) nonisolated(unsafe) var wasTruncated = false

    nonisolated init(maxBytes: Int) {
        self.maxBytes = max(1, maxBytes)
    }

    nonisolated func appendStdout(_ data: Data) {
        append(data, to: &stdoutData)
    }

    nonisolated func appendStderr(_ data: Data) {
        append(data, to: &stderrData)
    }

    nonisolated var stdoutText: String {
        text(from: stdoutData)
    }

    nonisolated var stderrText: String {
        text(from: stderrData)
    }

    private nonisolated func append(_ data: Data, to target: inout Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let remaining = max(0, maxBytes - target.count)
        if data.count > remaining {
            target.append(data.prefix(remaining))
            wasTruncated = true
        } else {
            target.append(data)
        }
    }

    private nonisolated func text(from data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? String(decoding: data, as: UTF8.self)
    }
}
