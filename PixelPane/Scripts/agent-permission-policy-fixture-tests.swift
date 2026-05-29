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
            runMode: .proposalOnly,
            localGrants: grants,
            grantedScopes: [.visualContext]
        ).map(\.name)
        try expect(tierBNames.contains("read_file"), "Tier B proposal mode should expose read tools")
        try expect(tierBNames.contains("stage_write_proposal"), "Tier B proposal mode should expose write proposal staging")
        try expect(!tierBNames.contains("run_finite_command"), "Tier B should not expose raw command tools")

        let tierANames = catalog.visibleModelSchemas(
            providerTier: .tierAFullAgent,
            runMode: .fullAgent,
            localGrants: grants,
            grantedScopes: [.processControl, .visualContext]
        ).map(\.name)
        try expect(tierANames.contains("run_finite_command"), "Tier A full agent should expose finite commands")
        try expect(tierANames.contains("discover_local_servers"), "Tier A with process scope should expose local server discovery")

        let deniedProcessNames = catalog.visibleModelSchemas(
            providerTier: .tierAFullAgent,
            runMode: .fullAgent,
            localGrants: grants,
            grantedScopes: [.processControl],
            deniedScopes: [.processControl]
        ).map(\.name)
        try expect(!deniedProcessNames.contains("start_process"), "denied process scope should filter process tools")
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
        try expect(safeCommand.kind == .allow, "safe read-only command should be allowed")

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

        let probe = policy.decision(
            for: request(
                providerTier: .tierBConstrainedStructuredText,
                toolName: "probe_local_server",
                arguments: ["port": "3000"],
                localGrants: grants
            )
        )
        try expect(probe.kind == .allow, "localhost probe should be allowed without process scope")

        let discoverDenied = policy.decision(
            for: request(
                toolName: "discover_local_servers",
                arguments: ["maxCandidates": "8"],
                localGrants: grants,
                deniedScopes: [.processControl]
            )
        )
        try expect(discoverDenied.kind == .deny && discoverDenied.reason == .deniedScope, "denied process scope should deny discovery")

        let startProcess = policy.decision(
            for: request(
                runMode: .fullAgent,
                toolName: "start_process",
                arguments: [
                    "command": "npm run dev",
                    "workingDirectory": "/Users/test/project"
                ],
                localGrants: grants,
                grantedScopes: [.processControl]
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
                toolName: "probe_local_server",
                arguments: ["port": "not-a-port"],
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
                localGrants: grants
            )
        )
        try expect(visualMissingScope.kind == .ask && visualMissingScope.reason == .approvalRequired, "visual context without scope should ask")
    }

    private static func request(
        runMode: AgentRunPermissionMode = .readOnly,
        providerTier: AgentModelCapabilityTier = .tierAFullAgent,
        toolName: String,
        arguments: [String: String],
        localGrants: [AgentLocalFileGrant],
        grantedScopes: [AgentPermissionScope] = [],
        deniedScopes: [AgentPermissionScope] = [],
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
