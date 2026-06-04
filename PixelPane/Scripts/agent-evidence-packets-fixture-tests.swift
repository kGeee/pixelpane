import Foundation

enum AgentEvidencePacketsFixtureHarness {
    struct HarnessError: Error, CustomStringConvertible {
        let description: String
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw HarnessError(description: message)
        }
    }

    static func run() async throws {
        try await testFileSearchEvidenceSupportsExactPath()
        try await testFolderListEvidenceSupportsListingClaims()
        try await testTemporalContextClaimsAcceptEchoedTargets()
        try await testLocationContextClaimsVerifyByRecordedEvidence()
        try await testFileGrantInventoryEvidenceIsDiscoveryOnly()
        try await testLocalServerEvidenceSupportsFinalAnswerWithoutModelVerifier()
        try await testLocalListenerSnapshotEvidenceSupportsOnlyListenerClaims()
        try await testCommandAndTerminalSupport()
        try await testProcessSnapshotEvidenceSupportsProcessClaims()
        try await testSideEffectEvidenceSupportsWriteClaims()
        try await testContextSelectionAvoidsStaleRuns()
        try await testUnsupportedAndMissingEvidence()
    }

    private static func testFileSearchEvidenceSupportsExactPath() async throws {
        let harness = try await makeHarness()
        let targetPath = "/Users/nayak/Documents/random-tests/counter.py"
        let evidence = try await harness.recorder.recordFileSearch(
            runID: harness.run.runID,
            query: "counter.py",
            matches: [
                AgentFileSearchMatch(
                    path: targetPath,
                    preview: AgentRunText("print(count)"),
                    score: 42
                )
            ]
        )

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let decision = harness.controller.verify(.fileSearchFound(targetPath), evidence: records)
        let packets = harness.controller.contextPackets(from: records, query: "counter.py")

        try expect(decision.status == .supported, "file search claim should be supported by exact path evidence")
        try expect(decision.evidenceIDs == [evidence.evidenceID], "support should point to search evidence")
        try expect(packets.first?.keyFields["topPath"] == .string(targetPath), "context packet should expose answer-critical path")
        try expect(packets.first?.artifactID != nil, "search detail should be artifact-backed")
    }

    private static func testTemporalContextClaimsAcceptEchoedTargets() async throws {
        // Replays the cloud weather failure: the model echoed the recorded
        // context block as its claim target ("currentDate: …, timeZone: …")
        // and the exact-date predicate rejected an honest declaration.
        // Temporal context is app-owned singleton evidence: existence is the
        // verification; targets carry no extra signal.
        let harness = try await makeHarness()
        let context = AgentTemporalContext()
        _ = try await harness.recorder.recordTemporalContext(
            runID: harness.run.runID,
            context: context
        )

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let echoed = harness.controller.verify(
            AgentEvidenceClaim(
                type: .temporalContextRecorded,
                target: "currentDate: \(context.currentDate), timeZone: \(context.timeZoneIdentifier)"
            ),
            evidence: records
        )
        let bareDate = harness.controller.verify(
            AgentEvidenceClaim(type: .temporalContextRecorded, target: context.currentDate),
            evidence: records
        )
        let untargeted = harness.controller.verify(
            AgentEvidenceClaim(type: .temporalContextRecorded),
            evidence: records
        )
        let withoutEvidence = harness.controller.verify(
            AgentEvidenceClaim(type: .temporalContextRecorded),
            evidence: records.filter { $0.kind != AgentEvidenceKind.temporalContext.rawValue }
        )

        try expect(echoed.status == .supported, "echoed context-block targets should be supported")
        try expect(bareDate.status == .supported, "bare current-date targets should be supported")
        try expect(untargeted.status == .supported, "untargeted temporal claims should be supported")
        try expect(withoutEvidence.status != .supported, "temporal claims still require recorded temporal evidence")
    }

    private static func testLocationContextClaimsVerifyByRecordedEvidence() async throws {
        // App-owned singleton evidence like temporal context: claims verify by
        // existence of the recorded approximate location, not target echoes.
        let harness = try await makeHarness()
        _ = try await harness.recorder.recordLocationContext(
            runID: harness.run.runID,
            context: AgentLocationContext(city: "Los Angeles", region: "CA", countryCode: "US")
        )

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let untargeted = harness.controller.verify(
            AgentEvidenceClaim(type: .locationContextRecorded),
            evidence: records
        )
        let echoed = harness.controller.verify(
            AgentEvidenceClaim(type: .locationContextRecorded, target: "Los Angeles, CA, US"),
            evidence: records
        )
        let withoutEvidence = harness.controller.verify(
            AgentEvidenceClaim(type: .locationContextRecorded),
            evidence: records.filter { $0.kind != AgentEvidenceKind.locationContext.rawValue }
        )

        try expect(untargeted.status == .supported, "location claims should be supported by recorded location evidence")
        try expect(echoed.status == .supported, "echoed location targets should be supported")
        try expect(withoutEvidence.status != .supported, "location claims still require recorded location evidence")
    }

    private static func testFolderListEvidenceSupportsListingClaims() async throws {
        let harness = try await makeHarness()
        let folderPath = "/Users/nayak/Documents/random-tests"
        let filePath = "\(folderPath)/short_story.txt"
        let evidence = try await harness.recorder.recordFolderList(
            runID: harness.run.runID,
            folderPath: folderPath,
            entries: [
                AgentFolderEntry(path: filePath, displayName: "short_story.txt", isDirectory: false, byteCount: 1_346)
            ]
        )

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let byFolder = harness.controller.verify(.folderListed(folderPath), evidence: records)
        let byEntry = harness.controller.verify(.folderListed(filePath), evidence: records)
        let untargeted = harness.controller.verify(.folderListed(), evidence: records)
        let wrongFolder = harness.controller.verify(.folderListed("/Users/nayak/Documents/other"), evidence: records)
        // A listing observation says what exists, not what files contain.
        let contentClaim = harness.controller.verify(
            AgentEvidenceClaim(type: .localFileObserved, target: filePath),
            evidence: records
        )

        try expect(byFolder.status == .supported, "folder-listing claim should be supported by listing evidence for the folder")
        try expect(byFolder.evidenceIDs == [evidence.evidenceID], "support should point to the folder-list evidence")
        try expect(byEntry.status == .supported, "folder-listing claim should be supported when targeting a listed entry")
        try expect(untargeted.status == .supported, "untargeted listing claim should accept any recorded listing")
        try expect(wrongFolder.status != .supported, "listing claim for an unlisted folder must not be supported")
        try expect(contentClaim.status != .supported, "file-content claims must still require file-read evidence (GROUND-1)")
    }

    private static func testFileGrantInventoryEvidenceIsDiscoveryOnly() async throws {
        let harness = try await makeHarness()
        let grant = AgentLocalFileGrant(path: harness.workspace.path, isDirectory: true)
        let evidence = try await harness.recorder.recordFileGrants(
            runID: harness.run.runID,
            grants: [grant]
        )

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let pathDecision = harness.controller.verify(
            AgentEvidenceClaim(type: .fileGrantListed, target: grant.path),
            evidence: records
        )
        let nameDecision = harness.controller.verify(
            AgentEvidenceClaim(type: .fileGrantListed, target: grant.url.lastPathComponent),
            evidence: records
        )
        let contentDecision = harness.controller.verify(.fileExists(grant.path), evidence: records)
        let packets = harness.controller.contextPackets(from: records, query: grant.url.lastPathComponent)

        try expect(evidence.artifactID != nil, "grant inventory should keep the full grant snapshot as an artifact")
        try expect(pathDecision.status == .supported, "grant inventory should support path-based grant claims")
        try expect(nameDecision.status == .supported, "grant inventory should support display-name grant claims")
        try expect(contentDecision.status == .needsEvidence, "grant inventory must not satisfy file-content claims")
        try expect(packets.first?.kind == .fileGrant, "grant inventory should be selected as grant context")
        try expect(packets.first?.keyFields["paths"] == .string(grant.path), "grant context should expose granted paths")
        try expect(packets.first?.keyFields["displayNames"] == .string(grant.url.lastPathComponent), "grant context should expose display names")
        try expect(packets.first?.keyFields["accessModes"] == nil, "grant context should not expose access modes")
        try expect(packets.first?.keyFields["grantIDs"] != nil, "grant context should expose grant IDs")
        try expect(packets.first?.keyFields["kinds"] == .string("\(grant.path)=folder"), "grant context should expose item kinds")
    }

    private static func testLocalServerEvidenceSupportsFinalAnswerWithoutModelVerifier() async throws {
        let harness = try await makeHarness()
        let server = AgentLocalServerEvidence(
            url: "http://localhost:59620",
            port: 59620,
            isListening: true,
            httpStatusCode: 200,
            processID: "python-site",
            workingDirectory: "/Users/nayak/Documents/snehithnayak.github.io"
        )
        _ = try await harness.recorder.recordLocalServer(runID: harness.run.runID, server: server)

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let portDecision = harness.controller.verify(.portListening(59620), evidence: records)
        let urlDecision = harness.controller.verify(.urlResponds("http://localhost:59620"), evidence: records)
        let final = try await harness.finalSupport.recordSupport(
            runID: harness.run.runID,
            answer: AgentRunText("Your site is responding on http://localhost:59620."),
            claims: [.portListening(59620), .urlResponds("http://localhost:59620")]
        )

        try expect(portDecision.status == .supported, "port-listening claim should be deterministic")
        try expect(urlDecision.status == .supported, "URL response claim should be deterministic")
        try expect(final.canAnswer, "final answer should be accepted from deterministic evidence")
        try expect(final.supportEvidenceID != nil, "final answer support should be recorded as evidence")
    }

    private static func testLocalListenerSnapshotEvidenceSupportsOnlyListenerClaims() async throws {
        let harness = try await makeHarness()
        let evidence = try await harness.recorder.recordLocalListenerSnapshot(
            runID: harness.run.runID,
            snapshot: AgentLocalListenerSnapshotEvidence(
                rows: [
                    AgentLocalListenerSnapshotRow(
                        port: 4317,
                        listenAddress: "127.0.0.1",
                        pid: 700,
                        executableName: "fixture-server",
                        workingDirectory: "/Users/test/project"
                    )
                ],
                requestedLimit: 5,
                requestedPort: 4317,
                requestedRootPath: "/Users/test/project"
            )
        )
        _ = try await harness.recorder.recordLocalListenerSnapshot(
            runID: harness.run.runID,
            snapshot: AgentLocalListenerSnapshotEvidence(
                rows: [],
                requestedLimit: 5,
                requestedPort: 9876
            )
        )

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let listenerDecision = harness.controller.verify(
            AgentEvidenceClaim(type: .localListenerSnapshotRecorded, target: "4317"),
            evidence: records
        )
        let listeningDecision = harness.controller.verify(.portListening(4317), evidence: records)
        let absentListeningDecision = harness.controller.verify(.portListening(9876), evidence: records)
        let packets = harness.controller.contextPackets(from: records, query: "4317")

        try expect(evidence.artifactID != nil, "listener snapshot should keep full rows as an artifact")
        try expect(listenerDecision.status == .supported, "listener snapshot claim should be supported by server evidence")
        try expect(listeningDecision.status == .supported, "positive listener rows should support port-listening claims")
        try expect(absentListeningDecision.status == .needsEvidence, "negative listener snapshots must not support positive port-listening claims")
        try expect(packets.first?.kind == .localServer, "listener evidence should be selected as local server context")
        try expect(packets.first?.keyFields["rowCount"] == .int(1), "context packet should expose listener row count")
    }

    private static func testCommandAndTerminalSupport() async throws {
        let harness = try await makeHarness()
        let output = AgentCommandExecutionOutput(
            command: "swift test",
            workingDirectory: "/tmp/project",
            exitCode: 0,
            stdout: AgentRunText("ok"),
            stderr: AgentRunText(""),
            durationSeconds: 1.2,
            didTimeOut: false
        )
        _ = try await harness.recorder.recordCommandOutput(runID: harness.run.runID, output: output)
        _ = try await harness.recorder.recordTerminalState(runID: harness.run.runID, status: .completed)

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let commandDecision = harness.controller.verify(.commandSucceeded("swift test"), evidence: records)
        let terminalDecision = harness.controller.verify(AgentEvidenceClaim(type: .taskCompleted), evidence: records)

        try expect(commandDecision.status == .supported, "command success should be supported by exit code 0")
        try expect(terminalDecision.status == .supported, "task completion should be supported by terminal evidence")
    }

    private static func testProcessSnapshotEvidenceSupportsProcessClaims() async throws {
        let harness = try await makeHarness()
        let evidence = try await harness.recorder.recordProcessSnapshot(
            runID: harness.run.runID,
            snapshot: AgentProcessSnapshotEvidence(
                rows: [
                    AgentProcessSnapshotRow(pid: 123, cpuPercent: 42.5, memoryPercent: 3.2, executableName: "swift"),
                    AgentProcessSnapshotRow(pid: 456, cpuPercent: 2.0, memoryPercent: 1.1, executableName: "launchd")
                ],
                requestedLimit: 2
            )
        )

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let executableDecision = harness.controller.verify(
            AgentEvidenceClaim(type: .processRunning, target: "swift"),
            evidence: records
        )
        let pidDecision = harness.controller.verify(
            AgentEvidenceClaim(type: .processRunning, target: "123"),
            evidence: records
        )
        let packets = harness.controller.contextPackets(from: records, query: "swift process")

        try expect(evidence.artifactID != nil, "process snapshot should keep full rows as an artifact")
        try expect(executableDecision.status == .supported, "process snapshot should support top executable process claims")
        try expect(pidDecision.status == .supported, "process snapshot should support top PID process claims")
        try expect(packets.first?.kind == .processSnapshot, "process snapshot should be selected as relevant context")
        try expect(packets.first?.keyFields["topExecutable"] == .string("swift"), "context packet should expose top executable")
        try expect(packets.first?.keyFields["rowCount"] == .int(2), "context packet should expose row count")
    }

    private static func testSideEffectEvidenceSupportsWriteClaims() async throws {
        let harness = try await makeHarness()
        let target = harness.workspace.appendingPathComponent("result.txt")
        try Data("old".utf8).write(to: target)

        let stage = try await harness.sideEffects.stage(
            runID: harness.run.runID,
            draft: .fileWrite(
                AgentFileWriteDraft(
                    operation: .replace,
                    targetPath: target.path,
                    content: "new"
                )
            )
        )
        _ = try await harness.sideEffects.resolveApproval(sideEffectID: stage.sideEffect.sideEffectID, decision: .approved)
        let completed = try await harness.sideEffects.executeApproved(sideEffectID: stage.sideEffect.sideEffectID)
        let sideEffectEvidence = try await harness.recorder.recordSideEffect(runID: harness.run.runID, sideEffect: completed)

        let records = await harness.store.evidenceArtifactSummary(runID: harness.run.runID).evidence
        let changedDecision = harness.controller.verify(.fileChanged(target.path), evidence: records)
        let effectDecision = harness.controller.verify(
            AgentEvidenceClaim(type: .sideEffectCompleted, target: completed.sideEffectID.uuidString),
            evidence: records
        )

        try expect(sideEffectEvidence.artifactID != nil, "side-effect evidence should keep full record as artifact")
        try expect(changedDecision.status == .supported, "file changed claim should be supported by completed side effect")
        try expect(effectDecision.status == .supported, "side-effect completion should be supported by side-effect evidence")
    }

    private static func testContextSelectionAvoidsStaleRuns() async throws {
        let root = try makeTemporaryRoot(prefix: "store")
        let store = try AgentRunStore(rootDirectory: root)
        let recorder = AgentEvidenceRecorder(store: store)
        let controller = AgentEvidenceController()
        let session = try await store.createSession(title: "Stale Context")
        let oldRun = try await store.createRun(sessionID: session.id, status: .completed)
        let currentRun = try await store.createRun(sessionID: session.id, status: .queued)

        _ = try await recorder.recordFileSearch(
            runID: oldRun.runID,
            query: "counter.py",
            matches: [
                AgentFileSearchMatch(
                    path: "/Users/nayak/Documents/old/counter.py",
                    preview: AgentRunText("old"),
                    score: 99
                )
            ]
        )
        _ = try await recorder.recordFileSearch(
            runID: currentRun.runID,
            query: "counter.py",
            matches: [
                AgentFileSearchMatch(
                    path: "/Users/nayak/Documents/current/counter.py",
                    preview: AgentRunText("current"),
                    score: 10
                )
            ]
        )

        let currentEvidence = await store.evidenceArtifactSummary(runID: currentRun.runID).evidence
        let packets = controller.contextPackets(from: currentEvidence, query: "counter.py")
        let pathFields = packets.compactMap { packet -> String? in
            guard case .string(let paths) = packet.keyFields["paths"] else { return nil }
            return paths
        }.joined(separator: "\n")

        try expect(pathFields.contains("/Users/nayak/Documents/current/counter.py"), "current run evidence should be selected")
        try expect(!pathFields.contains("/Users/nayak/Documents/old/counter.py"), "old run evidence should not leak into current context")
    }

    private static func testUnsupportedAndMissingEvidence() async throws {
        let harness = try await makeHarness()
        let missing = harness.controller.verify(.fileExists("/tmp/missing.txt"), evidence: [])
        let unsupported = harness.controller.verify(
            AgentEvidenceClaim(type: .unsupported, target: "unverifiable prose"),
            evidence: []
        )

        try expect(missing.status == .needsEvidence, "missing deterministic evidence should request evidence")
        try expect(unsupported.status == .unsupported, "unsupported claims should not be treated as supported")
    }

    private static func makeHarness() async throws -> Harness {
        let root = try makeTemporaryRoot(prefix: "store")
        let workspace = try makeTemporaryRoot(prefix: "workspace")
        let store = try AgentRunStore(rootDirectory: root)
        let session = try await store.createSession(title: "Evidence")
        let run = try await store.createRun(sessionID: session.id, status: .queued)
        let recorder = AgentEvidenceRecorder(store: store)
        let controller = AgentEvidenceController()
        let finalSupport = AgentFinalAnswerSupportRecorder(
            store: store,
            evidenceRecorder: recorder,
            controller: controller
        )
        let sideEffects = AgentSideEffectController(store: store)
        return Harness(
            store: store,
            recorder: recorder,
            controller: controller,
            finalSupport: finalSupport,
            sideEffects: sideEffects,
            run: run,
            workspace: workspace
        )
    }

    private static func makeTemporaryRoot(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-evidence-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    struct Harness {
        let store: AgentRunStore
        let recorder: AgentEvidenceRecorder
        let controller: AgentEvidenceController
        let finalSupport: AgentFinalAnswerSupportRecorder
        let sideEffects: AgentSideEffectController
        let run: AgentRunRecord
        let workspace: URL
    }
}

@main
struct AgentEvidencePacketsFixtureMain {
    static func main() async {
        do {
            try await AgentEvidencePacketsFixtureHarness.run()
            print("Agent evidence packet fixture tests passed")
        } catch {
            fputs("Agent evidence packet fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
