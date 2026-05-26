import Foundation

@main
enum AssistantTerminalHarnessCheck {
    static func main() async {
        let router = AssistantToolRouter()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let repo = FileManager.default.currentDirectoryPath
        let repoGrant = LocalFileGrant(
            id: UUID(),
            path: repo,
            isDirectory: true,
            addedAt: Date()
        )
        let nestedGrantPath = URL(fileURLWithPath: repo)
            .appendingPathComponent("PixelPane")
            .path
        let nestedGrant = LocalFileGrant(
            id: UUID(),
            path: nestedGrantPath,
            isDirectory: true,
            addedAt: Date()
        )
        let localEnvironment = AssistantToolEnvironment(
            hasCaptureContext: false,
            routingMode: .local,
            selectedLocalModelRepositoryID: nil,
            localTextBackendLabel: "MLX Text",
            previousTurnReferencedModel: false
        )
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-harness-site-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
        let packageJSON = """
        {
          "scripts": {
            "dev": "vite --host 127.0.0.1"
          }
        }
        """
        try? packageJSON.write(to: fixtureURL.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let siteGrant = LocalFileGrant(
            id: UUID(),
            path: fixtureURL.path,
            isDirectory: true,
            addedAt: Date()
        )
        let staticSiteURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("snehithnayak.github.io-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: staticSiteURL.appendingPathComponent("stylesheets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try? "<!doctype html><title>Personal Site</title>".write(
            to: staticSiteURL.appendingPathComponent("index.html"),
            atomically: true,
            encoding: .utf8
        )
        try? "snehithn.com".write(
            to: staticSiteURL.appendingPathComponent("CNAME"),
            atomically: true,
            encoding: .utf8
        )
        let staticSiteGrant = LocalFileGrant(
            id: UUID(),
            path: staticSiteURL.path,
            isDirectory: true,
            addedAt: Date()
        )
        let writeFixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: writeFixtureURL, withIntermediateDirectories: true)
        let writeGrant = LocalFileGrant(
            id: UUID(),
            path: writeFixtureURL.path,
            isDirectory: true,
            addedAt: Date()
        )
        defer {
            try? FileManager.default.removeItem(at: fixtureURL)
            try? FileManager.default.removeItem(at: staticSiteURL)
            try? FileManager.default.removeItem(at: writeFixtureURL)
        }
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
            }
        }

        func proposal(
            _ question: String,
            grants: [LocalFileGrant] = [],
            toolState: AssistantToolState = AssistantToolState()
        ) -> AssistantTerminalCommandProposal? {
            switch router.terminalCommandRequest(
                question: question,
                grants: grants,
                toolState: toolState
            ) {
            case .proposal(let proposal):
                return proposal
            case .proposals(let proposals):
                return proposals.first
            case .message(let message):
                failures.append("unexpected message for '\(question)': \(message)")
                return nil
            case nil:
                failures.append("no terminal proposal for '\(question)'")
                return nil
            }
        }

        if let topProcesses = proposal("what are the top running processes on my computer?") {
            expect(topProcesses.command.contains("ps aux"), "top processes should use ps aux")
            expect(topProcesses.intent == .systemInspection, "top processes should use system inspection intent")
            expect(
                topProcesses.workingDirectory == home,
                "top processes should default to the home working directory"
            )
            expect(!topProcesses.requiresConfirmation, "top processes should run without confirmation")
            let result = await router.runTerminalCommand(topProcesses, grants: [])
            expect(
                result.terminalResult?.succeeded == true,
                "top processes command should execute successfully"
            )
            expect(
                result.terminalResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                "top processes should return stdout"
            )
        }

        let repoSource = AssistantLocalFileToolSource(
            id: repo,
            path: repo,
            displayName: URL(fileURLWithPath: repo).lastPathComponent,
            kindLabel: "Folder",
            snippetCount: 0,
            isTruncated: false
        )
        let repoToolState = AssistantToolState(
            grantedSourcesUsed: [AssistantToolSourceState(source: repoSource)],
            lastListedFolder: AssistantToolSourceState(source: repoSource)
        )
        if let topProcessesWithRepoContext = proposal(
            "what are the top running processes on my computer?",
            grants: [repoGrant],
            toolState: repoToolState
        ) {
            expect(
                topProcessesWithRepoContext.workingDirectory == home,
                "system inspection should not inherit recent repo working directory"
            )
        }

        if let explicit = proposal("run ps aux | head -n 5") {
            expect(explicit.command == "ps aux | head -n 5", "explicit run prompt should preserve command")
            expect(
                explicit.workingDirectory == home,
                "explicit command should default to the home working directory"
            )
            expect(!explicit.requiresConfirmation, "read-only ps command should not require confirmation")
        }

        if let bare = proposal("echo harness-ok") {
            expect(bare.command == "echo harness-ok", "bare shell command should be detected")
            expect(
                bare.workingDirectory == home,
                "bare shell command should default to the home working directory"
            )
            expect(!bare.requiresConfirmation, "bare read-only shell command should not require confirmation")
            let result = await router.runTerminalCommand(bare, grants: [])
            expect(
                result.terminalResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "harness-ok",
                "bare shell command should execute and capture stdout"
            )
        }

        if let mkdir = proposal("create a folder named pixel-pane-agent-check") {
            expect(mkdir.command == "mkdir -p 'pixel-pane-agent-check'", "folder creation should plan mkdir -p")
            expect(mkdir.requiresConfirmation, "folder creation should require confirmation")
            expect(mkdir.riskLevel == .high, "folder creation should be high risk")
        }

        let writeSource = AssistantLocalFileToolSource(
            id: writeGrant.path,
            path: writeGrant.path,
            displayName: writeFixtureURL.lastPathComponent,
            kindLabel: "Folder",
            snippetCount: 0,
            isTruncated: false
        )
        let writeToolState = AssistantToolState(
            grantedSourcesUsed: [AssistantToolSourceState(source: writeSource)],
            lastListedFolder: AssistantToolSourceState(source: writeSource)
        )
        let delegatedWritePrompt = "create a txt file inside this folder containing a short story. you can pick what the story is about."
        let delegatedPreflight = router.preflight(
            question: delegatedWritePrompt,
            grants: [writeGrant],
            environment: localEnvironment,
            toolState: writeToolState
        )
        if case nil = delegatedPreflight {
            expect(true, "delegated write prompt should continue to selected-model write planning")
        } else {
            failures.append("delegated write prompt should not be stopped by the old path/content parser")
        }
        expect(
            router.shouldPlanWriteWithModel(
                question: delegatedWritePrompt,
                grants: [writeGrant],
                toolState: writeToolState
            ),
            "delegated write prompt should route to selected-model write planning"
        )
        let naturalWriteTerminalRequest = router.terminalCommandRequest(
            question: "just write \"this is a test\" inside the text file.",
            grants: [writeGrant],
            toolState: writeToolState
        )
        if case nil = naturalWriteTerminalRequest {
            expect(true, "natural write prompt should stay out of terminal routing")
        } else {
            failures.append("natural file-write prompts should not be misrouted as terminal/test commands")
        }
        let processResultAnswer = """
        Top running processes by CPU:
        - xcodebuild (PID 82414, nayak): 50.8% CPU, 0.2% MEM
        - SWBBuildService (PID 82425, nayak): 38.3% CPU, 0.0% MEM
        - PixelPane (PID 82337, nayak): 25.4% CPU, 0.2% MEM

        Ran `ps aux | sort -nrk 3 | head -n 15` locally.
        """
        let groundedWritePrompt = AssistantWritePlanningPromptBuilder().prompt(
            question: "create a txt file within pixel-pane-test with these results.",
            grants: [writeGrant],
            toolState: writeToolState,
            priorTurns: [
                AssistantContextPriorTurn(
                    question: "what are the top running processes on my computer?",
                    answer: processResultAnswer
                )
            ]
        )
        expect(
            groundedWritePrompt.contains("xcodebuild")
                && groundedWritePrompt.contains("SWBBuildService")
                && groundedWritePrompt.contains("these results"),
            "model-planned writes should receive current-chat result context for deictic references"
        )
        expect(
            groundedWritePrompt.contains("Do not assume any hidden or global chat history"),
            "write-planning prompt should explicitly avoid hidden global history"
        )
        let cleanWritePrompt = AssistantWritePlanningPromptBuilder().prompt(
            question: "create a txt file within pixel-pane-test with these results.",
            grants: [writeGrant],
            toolState: writeToolState,
            priorTurns: []
        )
        expect(
            !cleanWritePrompt.contains("xcodebuild")
                && cleanWritePrompt.contains("Relevant prior turns from this chat only:"),
            "new write-planning prompts should not carry prior result text without current session turns"
        )
        let generatedDraft = AssistantGeneratedWriteDraft(
            operation: .create,
            targetPath: "story.txt",
            content: "This is a tiny model-planned story."
        )
        let generatedWriteResult = router.generatedWriteProposal(
            from: generatedDraft,
            grants: [writeGrant],
            toolState: writeToolState
        )
        var recentWriteToolState = writeToolState
        if case .proposal(let plannedWrite)? = generatedWriteResult.writeProposalResult {
            expect(
                plannedWrite.targetPath == writeFixtureURL.appendingPathComponent("story.txt").path,
                "model-planned relative write should resolve inside the selected folder"
            )
            if case .create(let content) = plannedWrite.operation {
                expect(
                    content.contains("model-planned story"),
                    "model-planned write should preserve selected-model content"
                )
            } else {
                failures.append("model-planned new file should stage a create operation")
            }
        } else {
            failures.append("model-planned write should stage a confirmed local file proposal")
        }
        recentWriteToolState.record(generatedWriteResult)
        expect(
            recentWriteToolState.lastFileSources.contains { $0.path == writeFixtureURL.appendingPathComponent("story.txt").path },
            "staged write proposals should record the target as recent file context"
        )
        expect(
            router.shouldPlanWriteWithModel(
                question: "its formatted poorly. please format it nicer.",
                grants: [writeGrant],
                toolState: recentWriteToolState
            ),
            "formatting follow-ups for a recent file should route to selected-model write planning"
        )
        let generatedResultDraft = AssistantGeneratedWriteDraft(
            operation: .create,
            targetPath: "results.txt",
            content: processResultAnswer
        )
        let generatedResultWrite = router.generatedWriteProposal(
            from: generatedResultDraft,
            grants: [writeGrant],
            toolState: writeToolState
        )
        if case .proposal(let plannedResultWrite)? = generatedResultWrite.writeProposalResult {
            if case .create(let content) = plannedResultWrite.operation {
                expect(
                    content.contains("xcodebuild") && content.contains("SWBBuildService"),
                    "model-planned result writes should preserve referenced prior output"
                )
            } else {
                failures.append("model-planned result write should stage a create operation")
            }
        } else {
            failures.append("model-planned result write should stage a confirmed local file proposal")
        }
        let newlineArtifactDraft = AssistantGeneratedWriteDraft(
            operation: .create,
            targetPath: "artifact.txt",
            content: "Header n- One n- Two n\nRan ps locally."
        )
        let newlineArtifactWrite = router.generatedWriteProposal(
            from: newlineArtifactDraft,
            grants: [writeGrant],
            toolState: writeToolState
        )
        if case .proposal(let artifactProposal)? = newlineArtifactWrite.writeProposalResult,
           case .create(let artifactContent) = artifactProposal.operation {
            expect(
                artifactContent.contains("\n- One")
                    && artifactContent.contains("\n- Two")
                    && !artifactContent.contains(" n-"),
                "generated write proposals should normalize common literal newline artifacts"
            )
        } else {
            failures.append("newline artifact write should stage a create operation")
        }
        let typoGrantParentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-grant-\(UUID().uuidString)", isDirectory: true)
        let typoGrantURL = typoGrantParentURL.appendingPathComponent("pixel-pane-test", isDirectory: true)
        try? FileManager.default.createDirectory(at: typoGrantURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: typoGrantParentURL)
        }
        let typoGrant = LocalFileGrant(
            id: UUID(),
            path: typoGrantURL.path,
            isDirectory: true,
            addedAt: Date()
        )
        let typoTextFileURL = typoGrantURL.appendingPathComponent("top_processes.txt")
        try? "Top running processes by CPU:\n- PixelPane\n- WindowServer".write(
            to: typoTextFileURL,
            atomically: true,
            encoding: .utf8
        )
        let typoTextFilePath = typoTextFileURL.standardizedFileURL.path
        let wrongGrantDraft = AssistantGeneratedWriteDraft(
            operation: .create,
            targetPath: URL(fileURLWithPath: repo).appendingPathComponent("top_processes.txt").path,
            content: processResultAnswer
        )
        let correctedGrantWrite = router.generatedWriteProposal(
            from: wrongGrantDraft,
            question: "create a file in pixel-pane-texts which has this information. text file",
            grants: [repoGrant, typoGrant],
            toolState: AssistantToolState()
        )
        if case .proposal(let correctedProposal)? = correctedGrantWrite.writeProposalResult {
            expect(
                correctedProposal.targetPath == typoGrantURL.appendingPathComponent("top_processes.txt").path,
                "model-selected absolute targets should be constrained to the app-resolved named granted folder"
            )
        } else {
            failures.append("typo-corrected named grant write should stage a proposal")
        }
        let staleListedRepoState = AssistantToolState(
            lastListedFolder: AssistantToolSourceState(source: repoSource)
        )
        let typoNamedFolderList = router.preflight(
            question: "whats in the pixel=pane-tests folder?",
            grants: [repoGrant, typoGrant],
            environment: localEnvironment,
            toolState: staleListedRepoState
        )
        if case .directAnswer(_, let backendLabel, let toolResult)? = typoNamedFolderList {
            expect(backendLabel == "Local Files", "typo named folder listing should route to Local Files")
            expect(
                toolResult?.sources.first?.path == typoGrantURL.path,
                "typo named folder listing should choose the closest explicit granted folder"
            )
            expect(
                toolResult?.sources.contains(where: {
                    URL(fileURLWithPath: $0.path).standardizedFileURL.path == typoTextFilePath
                }) == true,
                "folder listing should carry visible readable files as follow-up sources"
            )
        } else {
            failures.append("typo named folder listing should return a direct local-file answer")
        }
        let exactNamedFolderList = router.preflight(
            question: "yes pixel-pane-test what is in this folder?",
            grants: [repoGrant, typoGrant],
            environment: localEnvironment,
            toolState: staleListedRepoState
        )
        if case .directAnswer(_, let backendLabel, let toolResult)? = exactNamedFolderList {
            expect(backendLabel == "Local Files", "exact named folder listing should route to Local Files")
            expect(
                toolResult?.sources.first?.path == typoGrantURL.path,
                "exact named folder listing should prefer the longer explicit grant over a prefix grant"
            )
        } else {
            failures.append("exact named folder listing should return a direct local-file answer")
        }
        var listedFolderState = staleListedRepoState
        if case .directAnswer(_, _, let toolResult)? = typoNamedFolderList,
           let toolResult {
            listedFolderState.record(toolResult)
        }
        expect(
            listedFolderState.lastFileSources.first.map {
                URL(fileURLWithPath: $0.path).standardizedFileURL.path
            } == typoTextFilePath,
            "recording a folder listing should make visible readable files recent file sources"
        )
        let sourceSummary = router.preflight(
            question: "what are these files?",
            grants: [repoGrant, typoGrant],
            environment: localEnvironment,
            toolState: listedFolderState
        )
        if case .directAnswer(let answer, let backendLabel, let toolResult)? = sourceSummary {
            expect(backendLabel == "Local Files", "recent source references should route to Local Files")
            expect(toolResult?.toolName == .listFolder, "recent source references should be source summaries")
            expect(answer.contains("top_processes.txt"), "recent source summaries should describe listed files")
            expect(!answer.contains("I can read and search only"), "recent source summaries should not fall back to grants")
        } else {
            failures.append("recent source reference should return a direct local-file answer")
        }
        let harnessFileSource = AssistantLocalFileToolSource(
            id: URL(fileURLWithPath: repo)
                .appendingPathComponent("PixelPane/PixelPane/Actions/AssistantHarness.swift")
                .path,
            path: URL(fileURLWithPath: repo)
                .appendingPathComponent("PixelPane/PixelPane/Actions/AssistantHarness.swift")
                .path,
            displayName: "AssistantHarness.swift",
            kindLabel: "File",
            snippetCount: 1,
            isTruncated: false
        )
        var pollutedSourceState = listedFolderState
        pollutedSourceState.lastFileSources = [AssistantToolSourceState(source: harnessFileSource)]
        let sourceSummaryAfterSearch = router.preflight(
            question: "what are these files?",
            grants: [repoGrant, typoGrant],
            environment: localEnvironment,
            toolState: pollutedSourceState
        )
        if case .directAnswer(let answer, let backendLabel, _)? = sourceSummaryAfterSearch {
            expect(backendLabel == "Local Files", "recent list-folder sources should survive later file search state")
            expect(answer.contains("top_processes.txt"), "source summaries should prefer the latest folder listing")
            expect(!answer.contains("AssistantHarness.swift"), "source summaries should not use unrelated search snippets")
        } else {
            failures.append("recent list-folder source reference should survive polluted lastFileSources")
        }
        let implicitTxtRead = router.preflight(
            question: "yeah whats inside that txt file?",
            grants: [repoGrant, typoGrant],
            environment: localEnvironment,
            toolState: listedFolderState
        )
        if case .directAnswer(let answer, let backendLabel, let toolResult)? = implicitTxtRead {
            expect(backendLabel == "Local Files", "implicit txt follow-up should route to Local Files")
            expect(toolResult?.toolName == .readFile, "implicit txt follow-up should read the file")
            expect(answer.contains("PixelPane"), "implicit txt follow-up should include file content")
        } else {
            failures.append("implicit txt follow-up should return a direct local-file read")
        }
        let confirmReadFollowUp = router.preflight(
            question: "sure do it",
            grants: [repoGrant, typoGrant],
            environment: localEnvironment,
            toolState: listedFolderState
        )
        if case .directAnswer(let answer, let backendLabel, let toolResult)? = confirmReadFollowUp {
            expect(backendLabel == "Local Files", "read confirmation follow-up should route to Local Files")
            expect(toolResult?.toolName == .readFile, "read confirmation follow-up should read the recent file")
            expect(answer.contains("WindowServer"), "read confirmation follow-up should include file content")
        } else {
            failures.append("read confirmation follow-up should return a direct local-file read")
        }
        let poorFormatURL = writeFixtureURL.appendingPathComponent("top_processes.txt")
        try? "Top running processes by CPU:\n- PixelPane n- WindowServer".write(
            to: poorFormatURL,
            atomically: true,
            encoding: .utf8
        )
        let processSource = AssistantLocalFileToolSource(
            id: poorFormatURL.path,
            path: poorFormatURL.path,
            displayName: poorFormatURL.lastPathComponent,
            kindLabel: "File",
            snippetCount: 0,
            isTruncated: false
        )
        let processToolState = AssistantToolState(
            grantedSourcesUsed: [AssistantToolSourceState(source: processSource)],
            lastFileSources: [AssistantToolSourceState(source: processSource)]
        )
        let formatRead = router.contextualFileReadResult(
            question: "its formatted poorly. please format it nicer.",
            grants: [writeGrant],
            toolState: processToolState
        )
        expect(
            formatRead?.context?.snippets.first?.preview.contains("PixelPane") == true,
            "formatting follow-ups should read the recent file before selected-model rewriting"
        )
        let rawPathPreflight = router.preflight(
            question: poorFormatURL.path,
            grants: [writeGrant],
            environment: localEnvironment,
            toolState: processToolState
        )
        if case .directAnswer(let answer, let backendLabel, _)? = rawPathPreflight {
            expect(backendLabel == "Local Files", "raw granted file paths should route to Local Files")
            expect(answer.contains("PixelPane"), "raw granted file path reads should include file content")
        } else {
            failures.append("raw granted file path should read the file instead of routing to terminal")
        }
        let rawPathTerminalRequest = router.terminalCommandRequest(
            question: poorFormatURL.path,
            grants: [writeGrant],
            toolState: processToolState
        )
        if case nil = rawPathTerminalRequest {
            expect(true, "raw granted non-executable file paths should not be terminal commands")
        } else {
            failures.append("raw granted non-executable file paths should stay out of terminal routing")
        }

        if let build = proposal("build this project", grants: [repoGrant]) {
            expect(
                build.command.contains("xcodebuild") || build.command.contains("verify-debug-build.sh"),
                "build should discover a real repo build command"
            )
            expect(
                build.workingDirectory == repo || build.workingDirectory.hasPrefix(repo + "/"),
                "build should run from the granted repo or a discovered nested workspace"
            )
            expect(build.requiresConfirmation, "build or script command should require confirmation")
        }

        if let sudo = proposal("run sudo ls /var/root") {
            expect(sudo.requiresConfirmation, "sudo command should require confirmation")
            expect(sudo.riskLevel == .high, "sudo command should be high risk")
        }

        if let portCheck = proposal(
            "http://localhost:3000 doesnt work. is it another port?",
            grants: [repoGrant]
        ) {
            expect(portCheck.command.hasPrefix("lsof -nP"), "localhost troubleshooting should inspect listening ports")
            expect(portCheck.intent == .systemInspection, "localhost troubleshooting should use system inspection")
            expect(!portCheck.requiresConfirmation, "listening-port inspection should not require confirmation")
            expect(
                portCheck.command != "http://localhost:3000 doesnt work. is it another port?",
                "natural localhost troubleshooting should not be executed as a shell command"
            )
        }

        if let serveSite = proposal("can you build my site so i can view it locally?", grants: [siteGrant]) {
            expect(serveSite.command.contains("npm run dev"), "site local-view prompt should discover the dev script")
            expect(serveSite.command.contains("Verified URL:"), "site local-view command should verify a local URL")
            expect(serveSite.requiresConfirmation, "starting a dev server should require confirmation")
        }

        if let personalSite = proposal(
            "can you build my personal website so i can view it locally?",
            grants: [repoGrant, staticSiteGrant]
        ) {
            expect(
                personalSite.workingDirectory == staticSiteGrant.path,
                "personal website prompt should select the static website grant over unrelated app/backend packages"
            )
            expect(
                personalSite.command.contains("python3 -m http.server"),
                "static website prompt should use a generic local static server"
            )
            expect(
                !personalSite.command.contains("PixelPane/Backend"),
                "personal website prompt should not serve an unrelated nested backend package"
            )
            expect(personalSite.command.contains("Verified URL:"), "static site server should report a verified URL")
            expect(personalSite.requiresConfirmation, "static site server startup should require confirmation")
        }

        let staticSiteSource = AssistantLocalFileToolSource(
            id: staticSiteGrant.path,
            path: staticSiteGrant.path,
            displayName: staticSiteURL.lastPathComponent,
            kindLabel: "Folder",
            snippetCount: 0,
            isTruncated: false
        )
        let staticSiteToolState = AssistantToolState(
            grantedSourcesUsed: [AssistantToolSourceState(source: staticSiteSource)],
            lastListedFolder: AssistantToolSourceState(source: staticSiteSource)
        )
        let priorServerResult = AssistantLocalFileToolResult(
            toolName: .runTerminalCommand,
            summary: "Terminal command completed successfully.",
            sources: [
                AssistantLocalFileToolSource(
                    id: staticSiteGrant.path,
                    path: staticSiteGrant.path,
                    displayName: staticSiteURL.lastPathComponent,
                    kindLabel: "Terminal",
                    snippetCount: 0,
                    isTruncated: false
                )
            ],
            context: nil,
            writeProposalResult: nil,
            metadata: AssistantToolResultMetadata(
                for: .runTerminalCommand,
                itemCount: 1,
                sourceCount: 1
            ),
            terminalResult: AssistantTerminalCommandResult(
                intent: .systemInspection,
                command: "python3 -m http.server 0 --bind 127.0.0.1",
                workingDirectory: staticSiteGrant.path,
                exitCode: 0,
                stdout: "PID: 2132\nVerified URL: http://localhost:59784/",
                stderr: "",
                durationSeconds: 2,
                didTimeOut: false,
                wasOutputTruncated: false
            )
        )
        var priorServerState = staticSiteToolState
        priorServerState.record(priorServerResult)
        let actionPlanningPrompt = AssistantActionPlanningPromptBuilder().prompt(
            question: "end that process.",
            grants: [staticSiteGrant],
            toolState: priorServerState
        )
        expect(
            actionPlanningPrompt.contains("PID: 2132")
                && actionPlanningPrompt.contains("kill <pid>"),
            "selected-model action planning should expose recent terminal PIDs and process-stop guidance"
        )
        let parsedActionPlan = AssistantActionPlanParser().parse(
            """
            {"action":"run_terminal_command","arguments":{"command":"kill 2132","working_directory":"\(staticSiteGrant.path)","reason":"Stop the previously started local server.","intent":"generic","timeout_seconds":"15"}}
            """
        )
        expect(
            parsedActionPlan?.action.kind == .runTerminalCommand
                && parsedActionPlan?.action.arguments["command"] == "kill 2132",
            "action plan parser should parse model-planned terminal JSON"
        )
        switch router.terminalCommandRequest(
            command: "kill 2132",
            workingDirectory: staticSiteGrant.path,
            reason: "Stop the previously started local server.",
            timeoutSeconds: 15,
            intent: .generic
        ) {
        case .proposal(let killProposal):
            expect(killProposal.requiresConfirmation, "model-planned process control should require confirmation")
            expect(killProposal.riskLevel == .high, "model-planned kill should be high risk")
        case .message(let message):
            failures.append("model-planned kill should produce a confirmation proposal, got message: \(message)")
        case .proposals:
            failures.append("model-planned kill should produce one terminal proposal")
        }

        if let contextualSite = proposal(
            "build this site and tell me what port its running on locally.",
            grants: [repoGrant, staticSiteGrant],
            toolState: staticSiteToolState
        ) {
            expect(
                contextualSite.workingDirectory == staticSiteGrant.path,
                "contextual site prompt should use the last listed static website folder"
            )
            expect(
                contextualSite.command.contains("python3 -m http.server"),
                "contextual static site prompt should serve the site instead of scanning all ports"
            )
            expect(
                !contextualSite.command.hasPrefix("lsof -nP"),
                "workspace execution should outrank generic listening-port inspection"
            )
            expect(
                contextualSite.command.contains("Verified URL:"),
                "contextual static site prompt should report a verified localhost URL"
            )
            expect(contextualSite.requiresConfirmation, "contextual static site server startup should require confirmation")
        }

        let contextualProjectSearch = router.localFileSearchResult(
            question: "what is this project though?",
            grants: [repoGrant, staticSiteGrant],
            toolState: staticSiteToolState
        )
        let contextualProjectPaths = contextualProjectSearch.context?.snippets.map(\.path) ?? []
        expect(
            !contextualProjectPaths.isEmpty,
            "contextual project question should gather project snippets"
        )
        expect(
            contextualProjectPaths.allSatisfy { $0.hasPrefix(staticSiteGrant.path) },
            "contextual project search should stay anchored to the last listed folder"
        )
        expect(
            contextualProjectPaths.contains { $0.hasSuffix("index.html") || $0.hasSuffix("whoami.html") },
            "contextual project search should include files from the selected website"
        )

        if let backend = proposal("start backend locally", grants: [repoGrant, staticSiteGrant]) {
            expect(
                backend.workingDirectory.hasSuffix("PixelPane/Backend"),
                "backend prompt should select the nested backend workspace"
            )
            expect(backend.command.contains("npm run dev"), "backend prompt should discover the backend dev script")
        }

        let siteSource = AssistantLocalFileToolSource(
            id: siteGrant.path,
            path: siteGrant.path,
            displayName: fixtureURL.lastPathComponent,
            kindLabel: "Folder",
            snippetCount: 0,
            isTruncated: false
        )
        let siteToolState = AssistantToolState(
            grantedSourcesUsed: [AssistantToolSourceState(source: siteSource)],
            lastListedFolder: AssistantToolSourceState(source: siteSource)
        )
        if let startIt = proposal("yes start it", grants: [siteGrant], toolState: siteToolState) {
            expect(startIt.command.contains("npm run dev"), "start follow-up should discover the dev script")
            expect(startIt.requiresConfirmation, "start follow-up should require confirmation")
        }

        var sourceSelectionState = AssistantToolState()
        if case .directAnswer(let answer, _, let toolResult)? = router.preflight(
            question: "what is in this folder?",
            grants: [repoGrant, nestedGrant],
            environment: localEnvironment,
            toolState: sourceSelectionState
        ) {
            expect(
                answer.contains("Which one should I inspect?"),
                "ambiguous folder overview should ask which folder to inspect"
            )
            if let toolResult {
                sourceSelectionState.record(toolResult)
            }
            expect(
                sourceSelectionState.pendingContinuation?.kind == .selectFolderToList,
                "ambiguous folder overview should record a pending folder-selection continuation"
            )
        } else {
            failures.append("ambiguous folder overview should return a direct local-file answer")
        }

        if case .directAnswer(let answer, _, let toolResult)? = router.preflight(
            question: "1st one",
            grants: [repoGrant, nestedGrant],
            environment: localEnvironment,
            toolState: sourceSelectionState
        ) {
            expect(
                answer.contains("Top-level contents:"),
                "ordinal folder selection should list top-level contents"
            )
            expect(
                !answer.hasPrefix("Inspect "),
                "ordinal folder selection should not return an inspect placeholder"
            )
            expect(toolResult?.toolName == .listFolder, "ordinal folder selection should be a list_folder result")
            expect(
                toolResult?.sources.first?.path == repo,
                "ordinal folder selection should select the first granted folder"
            )
            if let toolResult {
                sourceSelectionState.record(toolResult)
            }
            expect(
                sourceSelectionState.pendingContinuation == nil,
                "ordinal folder selection should resolve the pending folder-selection continuation"
            )
        } else {
            failures.append("ordinal folder selection should return a direct local-file answer")
        }

        if failures.isEmpty {
            print("PASS terminal harness checks")
        } else {
            print("FAIL terminal harness checks")
            for failure in failures {
                print("- \(failure)")
            }
            exit(1)
        }
    }
}
