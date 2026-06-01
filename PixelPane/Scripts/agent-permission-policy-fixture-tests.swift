import Foundation

enum AgentPermissionPolicyFixtureHarness {
    struct HarnessError: Error, CustomStringConvertible {
        let description: String
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw HarnessError(description: message)
        }
    }

    static func run() throws {
        try testCatalogFiltering()
        try testCanonicalPathResolverPrioritizesSpecificGrants()
        try testPathResolverExpandsUserHome()
        try testFileReadAndSensitivePathPolicy()
        try testWriteProposalApprovalPolicy()
        try testCommandPolicy()
        try testProcessAndLocalServerPolicy()
        try testArgumentAndScopeFailures()
    }

    private static func testCatalogFiltering() throws {
        let catalog = AgentToolCatalog()
        let grants = [grant("/Users/test/project", isDirectory: true, access: .readWrite)]

        let tierCNames = catalog.visibleModelSchemas(
            providerTier: .tierCPlainChat,
            runMode: .fullAgent,
            localGrants: grants,
            grantedScopes: [.visualContext, .processControl]
        ).map(\.name)
        try expect(tierCNames.isEmpty, "Tier C should expose no agent tools")

        let tierBNames = catalog.visibleModelSchemas(
            providerTier: .tierBConstrainedStructuredText,
            runMode: .fullAgent,
            localGrants: grants,
            grantedScopes: [.visualContext]
        ).map(\.name)
        try expect(tierBNames.contains("read_file"), "Tier B full-agent mode should expose read tools")
        try expect(!tierBNames.contains("stage_write_proposal"), "Tier B full-agent mode should not expose write proposal staging")
        try expect(tierBNames.contains("run_finite_command"), "Tier B full-agent mode should expose the generic finite command tool")

        let tierBProposalNames = catalog.visibleModelSchemas(
            providerTier: .tierBConstrainedStructuredText,
            runMode: .proposalOnly,
            localGrants: grants,
            grantedScopes: [.visualContext]
        ).map(\.name)
        try expect(tierBProposalNames.contains("stage_write_proposal"), "Tier B proposal mode should expose write proposal staging")

        let readOnlyGrantNames = catalog.visibleModelSchemas(
            providerTier: .tierBConstrainedStructuredText,
            runMode: .proposalOnly,
            localGrants: [grant("/Users/test/read-only-project", isDirectory: true, access: .readOnly)],
            grantedScopes: [.visualContext]
        ).map(\.name)
        try expect(readOnlyGrantNames.contains("read_file"), "read-only folder grants should expose read tools")
        try expect(!readOnlyGrantNames.contains("stage_write_proposal"), "read-only folder grants should not expose write proposal staging")

        let tierANames = catalog.visibleModelSchemas(
            providerTier: .tierAFullAgent,
            runMode: .fullAgent,
            localGrants: grants,
            grantedScopes: [.processControl, .visualContext]
        ).map(\.name)
        try expect(tierANames.contains("run_finite_command"), "Tier A full agent should expose finite commands")

        let deniedProcessNames = catalog.visibleModelSchemas(
            providerTier: .tierAFullAgent,
            runMode: .fullAgent,
            localGrants: grants,
            grantedScopes: [.processControl],
            deniedScopes: [.processControl]
        ).map(\.name)
        try expect(!deniedProcessNames.contains("start_process"), "denied process scope should filter process tools")

        let executableNames = catalog.visibleModelSchemas(
            providerTier: .tierAFullAgent,
            runMode: .fullAgent,
            localGrants: grants,
            grantedScopes: [.processControl, .visualContext],
            supportedOperations: AgentToolExecutionCapabilities.activeLocalRuntimeOperations
        ).map(\.name)
        try expect(!executableNames.contains("start_process"), "unsupported process start should not be model-visible")
        try expect(!executableNames.contains("describe_visual_context"), "unsupported visual context should not be model-visible")
        try expect(executableNames.contains("run_finite_command"), "supported command executor should remain model-visible")

        let noWriteOperationNames = catalog.visibleModelSchemas(
            providerTier: .tierBConstrainedStructuredText,
            runMode: .proposalOnly,
            localGrants: grants,
            supportedOperations: [.fileGrantList, .fileList, .fileSearch, .fileRead, .finiteCommand]
        ).map(\.name)
        try expect(!noWriteOperationNames.contains("stage_write_proposal"), "missing write executor support should withhold write proposal staging")

        let visibilityDiagnostics = catalog.visibilityDiagnostics(
            providerTier: .tierBConstrainedStructuredText,
            runMode: .proposalOnly,
            localGrants: [grant("/Users/test/read-only-project", isDirectory: true, access: .readOnly)]
        )
        try expect(
            visibilityDiagnostics.contains("tool.stage_write_proposal=withheld:missingWriteGrant"),
            "tool visibility diagnostics should explain why write staging was withheld"
        )
    }

    private static func testCanonicalPathResolverPrioritizesSpecificGrants() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-policy-resolver-\(UUID().uuidString)", isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let broad = documents.appendingPathComponent("pixel-pane", isDirectory: true)
        let specific = documents.appendingPathComponent("random-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: broad, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: specific, withIntermediateDirectories: true)

        let grants = [
            grant(broad.path, isDirectory: true, access: .readWrite),
            grant(specific.path, isDirectory: true, access: .readWrite)
        ]
        let resolver = AgentLocalPathResolver()

        let named = resolver.resolve(
            "random-tests/short_story.txt",
            grants: grants,
            access: .write,
            target: .writeTarget(requiresExistingParent: true)
        )
        try expect(named.resolution?.path == specific.appendingPathComponent("short_story.txt").path, "explicit grant-name path should resolve to the specific grant")

        let preferred = resolver.resolve(
            "print_snehith.sh",
            grants: grants,
            access: .write,
            target: .writeTarget(requiresExistingParent: true),
            preferredDirectoryPath: specific.path
        )
        try expect(preferred.resolution?.path == specific.appendingPathComponent("print_snehith.sh").path, "preferred directory should beat broad fallback")

        let ambiguous = resolver.resolve(
            "short_story.txt",
            grants: grants,
            access: .write,
            target: .writeTarget(requiresExistingParent: true)
        )
        try expect(ambiguous.failure?.code == .ambiguousRelativePath, "bare relative write target should be ambiguous across multiple writable grants")
    }

    private static func testPathResolverExpandsUserHome() throws {
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
        let workspace = home.appendingPathComponent("Documents/random-tests", isDirectory: true)
        let resolver = AgentLocalPathResolver()
        let result = resolver.resolve(
            "~/Documents/random-tests/notes.txt",
            grants: [grant(workspace.path, isDirectory: true, access: .readWrite)],
            access: .read,
            target: .any
        )

        try expect(result.resolution?.path == workspace.appendingPathComponent("notes.txt").path, "tilde paths should resolve against the user home before grant checks")
    }

    private static func testFileReadAndSensitivePathPolicy() throws {
        let policy = AgentPermissionPolicy()
        let grants = [grant("/Users/test/project", isDirectory: true)]

        let allowedRead = policy.decision(
            for: request(
                toolName: "read_file",
                arguments: ["path": "/Users/test/project/README.md"],
                localGrants: grants
            )
        )
        try expect(allowedRead.kind == .allow, "read inside grant should be allowed")

        let missingGrant = policy.decision(
            for: request(
                toolName: "read_file",
                arguments: ["path": "/Users/test/other/README.md"],
                localGrants: grants
            )
        )
        try expect(missingGrant.kind == .ask && missingGrant.reason == .missingFileGrant, "read outside grant should ask for file grant")

        let sensitiveRead = policy.decision(
            for: request(
                toolName: "read_file",
                arguments: ["path": "/Users/test/project/.env"],
                localGrants: grants
            )
        )
        try expect(sensitiveRead.kind == .deny && sensitiveRead.reason == .sensitivePathDenied, ".env read should be denied")

        let sshRead = policy.decision(
            for: request(
                toolName: "read_file",
                arguments: ["path": "/Users/test/project/.ssh/id_ed25519"],
                localGrants: grants
            )
        )
        try expect(sshRead.kind == .deny && sshRead.reason == .sensitivePathDenied, "SSH private key read should be denied")
    }

    private static func testWriteProposalApprovalPolicy() throws {
        let policy = AgentPermissionPolicy()
        let grants = [grant("/Users/test/project", isDirectory: true, access: .readWrite)]
        let arguments = [
            "operation": "replace",
            "targetPath": "/Users/test/project/notes.md",
            "content": "updated"
        ]

        let stagedWrite = policy.decision(
            for: request(
                runMode: .proposalOnly,
                providerTier: .tierBConstrainedStructuredText,
                toolName: "stage_write_proposal",
                arguments: arguments,
                localGrants: grants
            )
        )
        try expect(stagedWrite.kind == .ask && stagedWrite.reason == .approvalRequired, "write proposal should ask for approval")

        let digest = AgentPermissionPolicy.approvalDigest(toolName: "stage_write_proposal", arguments: arguments)
        let approvedWrite = policy.decision(
            for: request(
                runMode: .proposalOnly,
                providerTier: .tierBConstrainedStructuredText,
                toolName: "stage_write_proposal",
                arguments: arguments,
                localGrants: grants,
                approvalGrants: [
                    AgentPermissionApprovalGrant(toolName: "stage_write_proposal", argumentDigest: digest)
                ]
            )
        )
        try expect(approvedWrite.kind == .allow && approvedWrite.reason == .approvalGrantMatched, "matching approval should allow staged write")

        let sensitiveWrite = policy.decision(
            for: request(
                runMode: .proposalOnly,
                providerTier: .tierBConstrainedStructuredText,
                toolName: "stage_write_proposal",
                arguments: [
                    "operation": "replace",
                    "targetPath": "/Users/test/project/.npmrc",
                    "content": "//registry.npmjs.org/:_authToken=secret"
                ],
                localGrants: grants
            )
        )
        try expect(sensitiveWrite.kind == .deny && sensitiveWrite.reason == .sensitivePathDenied, "package auth writes should be denied")
    }

    private static func testCommandPolicy() throws {
        let policy = AgentPermissionPolicy()
        let grants = [grant("/Users/test/project", isDirectory: true, access: .readWrite)]

        let safeCommand = policy.decision(
            for: request(
                toolName: "run_finite_command",
                arguments: ["command": "git status --short", "workingDirectory": "/Users/test/project"],
                localGrants: grants
            )
        )
        try expect(safeCommand.kind == .deny && safeCommand.reason == .rawShellRequiresApproval, "with no read-only allowlist, git status is a raw shell command and is denied in read-only mode")

        let rawCommand = policy.decision(
            for: request(
                runMode: .fullAgent,
                toolName: "run_finite_command",
                arguments: ["command": "python scripts/do_work.py", "workingDirectory": "/Users/test/project"],
                localGrants: grants
            )
        )
        try expect(rawCommand.kind == .ask && rawCommand.reason == .rawShellRequiresApproval, "raw shell should ask in full-agent mode")

        let rawReadOnly = policy.decision(
            for: request(
                runMode: .readOnly,
                toolName: "run_finite_command",
                arguments: ["command": "python scripts/do_work.py", "workingDirectory": "/Users/test/project"],
                localGrants: grants
            )
        )
        try expect(rawReadOnly.kind == .deny && rawReadOnly.reason == .rawShellRequiresApproval, "raw shell should be denied in read-only mode")

        let installCommand = policy.decision(
            for: request(
                runMode: .fullAgent,
                toolName: "run_finite_command",
                arguments: ["command": "npm install", "workingDirectory": "/Users/test/project"],
                localGrants: grants
            )
        )
        try expect(installCommand.kind == .ask && installCommand.reason == .installRequiresApproval, "install command should ask")

        let networkCommand = policy.decision(
            for: request(
                runMode: .fullAgent,
                toolName: "run_finite_command",
                arguments: ["command": "curl https://example.com", "workingDirectory": "/Users/test/project"],
                localGrants: grants
            )
        )
        try expect(networkCommand.kind == .ask && networkCommand.reason == .networkRequiresApproval, "network command should ask")

        let processCommand = policy.decision(
            for: request(
                runMode: .fullAgent,
                toolName: "run_finite_command",
                arguments: ["command": "kill 123", "workingDirectory": "/Users/test/project"],
                localGrants: grants
            )
        )
        try expect(processCommand.kind == .ask && processCommand.reason == .processControlRequiresApproval, "process-control command should ask")

        let destructiveCommand = policy.decision(
            for: request(
                runMode: .fullAgent,
                toolName: "run_finite_command",
                arguments: ["command": "rm -rf /", "workingDirectory": "/Users/test/project"],
                localGrants: grants
            )
        )
        try expect(destructiveCommand.kind == .deny && destructiveCommand.reason == .unsafeCommandDenied, "destructive command should be denied")

        let sensitiveCommand = policy.decision(
            for: request(
                runMode: .fullAgent,
                toolName: "run_finite_command",
                arguments: ["command": "cat .env", "workingDirectory": "/Users/test/project"],
                localGrants: grants
            )
        )
        try expect(sensitiveCommand.kind == .deny && sensitiveCommand.reason == .sensitivePathDenied, "commands referencing secrets should be denied")
    }

    private static func testProcessAndLocalServerPolicy() throws {
        let policy = AgentPermissionPolicy()
        let grants = [grant("/Users/test/project", isDirectory: true, access: .readWrite)]

        let topProcesses = policy.decision(
            for: request(
                providerTier: .tierBConstrainedStructuredText,
                toolName: "run_finite_command",
                arguments: ["command": "ps -axo pid,pcpu,pmem,comm -r"],
                localGrants: []
            )
        )
        try expect(topProcesses.kind == .deny && topProcesses.reason == .rawShellRequiresApproval, "with no read-only allowlist, ps is a raw shell command and is denied in read-only mode")

        let localhostListeners = policy.decision(
            for: request(
                providerTier: .tierBConstrainedStructuredText,
                toolName: "run_finite_command",
                arguments: ["command": "lsof -nP -iTCP -sTCP:LISTEN"],
                localGrants: []
            )
        )
        try expect(localhostListeners.kind == .deny && localhostListeners.reason == .rawShellRequiresApproval, "with no read-only allowlist, lsof is a raw shell command and is denied in read-only mode")

        let startProcess = policy.decision(
            for: request(
                runMode: .fullAgent,
                toolName: "start_process",
                arguments: [
                    "command": "npm run dev",
                    "workingDirectory": "/Users/test/project"
                ],
                localGrants: grants,
                grantedScopes: [.processControl],
                supportedOperations: AgentToolExecutionCapabilities.activeLocalRuntimeOperations.union([.processStart])
            )
        )
        try expect(startProcess.kind == .ask && startProcess.reason == .approvalRequired, "process start should ask for approval")
    }

    private static func testArgumentAndScopeFailures() throws {
        let policy = AgentPermissionPolicy()
        let grants = [grant("/Users/test/project", isDirectory: true)]

        let missingArgument = policy.decision(
            for: request(toolName: "read_file", arguments: [:], localGrants: grants)
        )
        try expect(missingArgument.kind == .deny && missingArgument.reason == .missingRequiredArgument, "missing required args should deny")

        let malformedInteger = policy.decision(
            for: request(
                providerTier: .tierBConstrainedStructuredText,
                toolName: "run_finite_command",
                arguments: ["command": "ps -axo pid,pcpu,pmem,comm -r", "timeoutSeconds": "not-a-timeout"],
                localGrants: grants
            )
        )
        try expect(malformedInteger.kind == .deny && malformedInteger.reason == .malformedArgument, "malformed integer arg should deny")

        let tierDenied = policy.decision(
            for: request(
                providerTier: .tierCPlainChat,
                toolName: "read_file",
                arguments: ["path": "/Users/test/project/README.md"],
                localGrants: grants
            )
        )
        try expect(tierDenied.kind == .deny && tierDenied.reason == .providerTierDisallowsTool, "Tier C should deny tool calls")

        let visualMissingScope = policy.decision(
            for: request(
                toolName: "describe_visual_context",
                arguments: [:],
                localGrants: grants,
                supportedOperations: AgentToolExecutionCapabilities.activeLocalRuntimeOperations.union([.visualContext])
            )
        )
        try expect(visualMissingScope.kind == .ask && visualMissingScope.reason == .approvalRequired, "visual context without scope should ask")

        let unsupportedOperation = policy.decision(
            for: request(
                runMode: .proposalOnly,
                providerTier: .tierBConstrainedStructuredText,
                toolName: "stage_write_proposal",
                arguments: [
                    "operation": "create",
                    "targetPath": "/Users/test/project/new.md",
                    "content": "hello"
                ],
                localGrants: [grant("/Users/test/project", isDirectory: true, access: .readWrite)],
                supportedOperations: [.fileGrantList, .fileList, .fileSearch, .fileRead, .finiteCommand]
            )
        )
        try expect(
            unsupportedOperation.kind == .deny && unsupportedOperation.reason == .unsupportedOperation,
            "permission policy should deny tool calls whose operation is not supported by the active executor"
        )
    }

    private static func request(
        runMode: AgentRunPermissionMode = .readOnly,
        providerTier: AgentModelCapabilityTier = .tierAFullAgent,
        toolName: String,
        arguments: [String: String],
        localGrants: [AgentLocalFileGrant],
        grantedScopes: [AgentPermissionScope] = [],
        deniedScopes: [AgentPermissionScope] = [],
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations,
        approvalGrants: [AgentPermissionApprovalGrant] = []
    ) -> AgentPermissionRequest {
        AgentPermissionRequest(
            runMode: runMode,
            providerTier: providerTier,
            toolName: toolName,
            arguments: arguments,
            localGrants: localGrants,
            grantedScopes: grantedScopes,
            deniedScopes: deniedScopes,
            supportedOperations: supportedOperations,
            approvalGrants: approvalGrants,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static func grant(
        _ path: String,
        isDirectory: Bool,
        access: AgentLocalFileGrantAccess = .readOnly
    ) -> AgentLocalFileGrant {
        AgentLocalFileGrant(path: path, isDirectory: isDirectory, access: access)
    }
}

@main
struct AgentPermissionPolicyFixtureMain {
    static func main() {
        do {
            try AgentPermissionPolicyFixtureHarness.run()
            print("Agent permission policy fixture tests passed")
        } catch {
            fputs("Agent permission policy fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
