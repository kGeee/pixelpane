import Foundation
import Network

enum AgentKernelManagedProcessKindV2: String, Codable, Equatable, Sendable {
    case running
    case exited
    case stopped
    case failed
}

struct AgentKernelLocalServerProbeV2: Codable, Equatable, Sendable {
    let url: String?
    let port: Int?
    let isListening: Bool?
    let httpStatusCode: Int?

    nonisolated init(
        url: String? = nil,
        port: Int? = nil,
        isListening: Bool? = nil,
        httpStatusCode: Int? = nil
    ) {
        self.url = url
        self.port = port
        self.isListening = isListening
        self.httpStatusCode = httpStatusCode
    }
}

struct AgentKernelManagedProcessRecordV2: Codable, Equatable, Sendable {
    let processID: String
    let command: String
    let workingDirectory: String
    let ownerSessionID: UUID
    let pid: Int32?
    let startedAt: Date
    let status: AgentKernelManagedProcessKindV2
    let exitCode: Int32?
    let detectedServer: AgentKernelLocalServerProbeV2?
    let stdoutTail: AgentKernelBoundedTextV2
    let stderrTail: AgentKernelBoundedTextV2
    let sources: [AgentKernelToolSourceRecordV2]
}

actor AgentKernelProcessLifecycleToolV2 {
    let maxTailBytes: Int
    let initialOutputWaitMilliseconds: Int
    private var processes: [String: AgentKernelManagedProcessV2] = [:]

    init(
        maxTailBytes: Int = 32_000,
        initialOutputWaitMilliseconds: Int = 150
    ) {
        self.maxTailBytes = max(1, maxTailBytes)
        self.initialOutputWaitMilliseconds = max(0, initialOutputWaitMilliseconds)
    }

    nonisolated static var definitions: [AgentKernelToolDefinitionV2] {
        [
            AgentKernelToolDefinitionV2(
                name: "start_process",
                summary: "Start a long-running local process with lifecycle tracking.",
                inputArguments: [
                    AgentKernelToolArgumentSchemaV2(
                        name: "command",
                        type: .string,
                        summary: "Shell command to start."
                    ),
                    AgentKernelToolArgumentSchemaV2(
                        name: "workingDirectory",
                        type: .string,
                        summary: "Validated working directory."
                    ),
                    AgentKernelToolArgumentSchemaV2(
                        name: "processID",
                        type: .string,
                        isRequired: false,
                        summary: "Optional stable process ID."
                    )
                ],
                outputType: AgentKernelToolIOTypeV2(
                    name: "managed_process",
                    summary: "Managed process status, output tail, and detected local server URL."
                ),
                risk: .sideEffect,
                scopeRequirements: [.workingDirectory, .processControl],
                requiresApproval: true
            ),
            AgentKernelToolDefinitionV2(
                name: "process_status",
                summary: "Read the current status of a managed process.",
                inputArguments: [
                    AgentKernelToolArgumentSchemaV2(
                        name: "processID",
                        type: .string,
                        summary: "Managed process ID."
                    )
                ],
                outputType: AgentKernelToolIOTypeV2(
                    name: "managed_process",
                    summary: "Managed process status and source records."
                ),
                risk: .readOnly,
                scopeRequirements: [.processControl],
                requiresApproval: false
            ),
            AgentKernelToolDefinitionV2(
                name: "stop_process",
                summary: "Stop a managed long-running process.",
                inputArguments: [
                    AgentKernelToolArgumentSchemaV2(
                        name: "processID",
                        type: .string,
                        summary: "Managed process ID."
                    )
                ],
                outputType: AgentKernelToolIOTypeV2(
                    name: "managed_process",
                    summary: "Stopped managed process status and source records."
                ),
                risk: .sideEffect,
                scopeRequirements: [.processControl],
                requiresApproval: true
            ),
            AgentKernelToolDefinitionV2(
                name: "tail_process_output",
                summary: "Read the bounded stdout and stderr tail for a managed process.",
                inputArguments: [
                    AgentKernelToolArgumentSchemaV2(
                        name: "processID",
                        type: .string,
                        summary: "Managed process ID."
                    )
                ],
                outputType: AgentKernelToolIOTypeV2(
                    name: "process_output_tail",
                    summary: "Bounded stdout and stderr tail with source records."
                ),
                risk: .readOnly,
                scopeRequirements: [.processControl],
                requiresApproval: false
            ),
            AgentKernelToolDefinitionV2(
                name: "probe_local_server",
                summary: "Probe a localhost URL or port for listener and HTTP-response evidence.",
                inputArguments: [
                    AgentKernelToolArgumentSchemaV2(
                        name: "url",
                        type: .string,
                        isRequired: false,
                        summary: "Optional http://localhost, http://127.0.0.1, or loopback URL."
                    ),
                    AgentKernelToolArgumentSchemaV2(
                        name: "port",
                        type: .integer,
                        isRequired: false,
                        summary: "Optional localhost TCP port."
                    )
                ],
                outputType: AgentKernelToolIOTypeV2(
                    name: "local_server_probe",
                    summary: "Local listener and HTTP response evidence."
                ),
                risk: .readOnly,
                scopeRequirements: [.none],
                requiresApproval: false
            )
        ]
    }

    func startProcess(
        command: String,
        workingDirectory: String,
        allowedWorkingDirectories: [String],
        ownerSessionID: UUID,
        processID requestedProcessID: String? = nil,
        startedAt: Date = Date()
    ) -> Result<AgentKernelManagedProcessRecordV2, AgentKernelTerminalReasonV2> {
        let cleanedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedCommand.isEmpty else {
            return .failure(reason(code: "empty_process_command", summary: "Process command cannot be empty."))
        }

        switch validatedWorkingDirectory(workingDirectory, allowedWorkingDirectories: allowedWorkingDirectories) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let cwd):
            if processes.values.contains(where: { managed in
                managed.command == cleanedCommand
                    && managed.workingDirectory == cwd.path
                    && managed.isRunning
            }) {
                return .failure(
                    reason(
                        code: "duplicate_process_start",
                        summary: "An identical managed process is already running.",
                        metadata: ["command": .string(cleanedCommand), "workingDirectory": .string(cwd.path)]
                    )
                )
            }

            let requestedID = requestedProcessID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let processID = requestedID.isEmpty ? "process-\(UUID().uuidString)" : requestedID
            if let existing = processes[processID], existing.isRunning {
                return .failure(
                    reason(
                        code: "process_id_already_running",
                        summary: "A managed process with this ID is already running.",
                        metadata: ["processID": .string(processID)]
                    )
                )
            }

            let managed = AgentKernelManagedProcessV2(
                processID: processID,
                command: cleanedCommand,
                workingDirectory: cwd.path,
                ownerSessionID: ownerSessionID,
                startedAt: startedAt,
                maxTailBytes: maxTailBytes
            )

            do {
                try managed.start()
            } catch {
                return .failure(
                    reason(
                        code: "process_start_failed",
                        summary: error.localizedDescription,
                        metadata: ["command": .string(cleanedCommand)]
                    )
                )
            }

            processes[processID] = managed
            if initialOutputWaitMilliseconds > 0 {
                Thread.sleep(forTimeInterval: Double(initialOutputWaitMilliseconds) / 1_000)
            }
            return .success(record(for: managed))
        }
    }

    func status(
        processID: String
    ) -> Result<AgentKernelManagedProcessRecordV2, AgentKernelTerminalReasonV2> {
        guard let managed = processes[processID] else {
            return .failure(reason(code: "unknown_process", summary: "No managed process exists with that ID."))
        }
        return .success(record(for: managed))
    }

    func tailOutput(
        processID: String
    ) -> Result<AgentKernelManagedProcessRecordV2, AgentKernelTerminalReasonV2> {
        status(processID: processID)
    }

    nonisolated func probeLocalServer(
        url rawURL: String?,
        port rawPort: String?
    ) -> Result<AgentKernelLocalServerProbeV2, AgentKernelTerminalReasonV2> {
        let cleanedURL = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedPort = rawPort?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !cleanedURL.isEmpty {
            guard let url = URL(string: cleanedURL),
                  let host = url.host,
                  Self.isLoopbackHost(host) else {
                return .failure(reason(code: "local_server_probe_not_loopback", summary: "Local server probes are limited to localhost and loopback URLs."))
            }
            guard url.scheme == "http" || url.scheme == "https" else {
                return .failure(reason(code: "local_server_probe_bad_scheme", summary: "Local server probes require an HTTP or HTTPS URL."))
            }
            let port = url.port ?? (url.scheme == "https" ? 443 : 80)
            return .success(
                AgentKernelLocalServerProbeV2(
                    url: url.absoluteString,
                    port: port,
                    isListening: Self.isListening(host: host, port: port),
                    httpStatusCode: Self.httpStatusCode(for: url)
                )
            )
        }

        guard let port = Int(cleanedPort), port > 0, port <= 65_535 else {
            return .failure(reason(code: "local_server_probe_missing_target", summary: "Local server probes require a localhost URL or valid TCP port."))
        }
        return .success(
            AgentKernelLocalServerProbeV2(
                url: nil,
                port: port,
                isListening: Self.isListening(host: "127.0.0.1", port: port),
                httpStatusCode: nil
            )
        )
    }

    func stopProcess(
        processID: String,
        timeoutMilliseconds: Int = 1_500
    ) -> Result<AgentKernelManagedProcessRecordV2, AgentKernelTerminalReasonV2> {
        guard let managed = processes[processID] else {
            return .failure(reason(code: "unknown_process", summary: "No managed process exists with that ID."))
        }
        managed.stop(timeoutMilliseconds: timeoutMilliseconds)
        return .success(record(for: managed, forcedStatus: .stopped))
    }

    nonisolated func detectedServer(
        in text: String,
        probe: Bool = false
    ) -> AgentKernelLocalServerProbeV2? {
        guard let match = firstURLMatch(in: text) else {
            return nil
        }

        let isListening = probe && match.port != nil
            ? Self.isListening(host: "127.0.0.1", port: match.port!)
            : nil
        let httpStatus = probe ? Self.httpStatusCode(for: match.url) : nil
        return AgentKernelLocalServerProbeV2(
            url: match.url.absoluteString,
            port: match.port,
            isListening: isListening,
            httpStatusCode: httpStatus
        )
    }

    private func record(
        for managed: AgentKernelManagedProcessV2,
        forcedStatus: AgentKernelManagedProcessKindV2? = nil
    ) -> AgentKernelManagedProcessRecordV2 {
        let stdout = managed.stdoutTail
        let stderr = managed.stderrTail
        let combined = [stdout, stderr].joined(separator: "\n")
        let detected = detectedServer(in: combined, probe: false)
        let status = forcedStatus ?? managed.status
        let summaryText: String
        switch status {
        case .running:
            if let url = detected?.url {
                summaryText = "Managed process is running. Detected local URL: \(url)."
            } else {
                summaryText = "Managed process is running."
            }
        case .exited:
            summaryText = "Managed process exited with code \(managed.exitCode ?? -1)."
        case .stopped:
            summaryText = "Managed process was stopped."
        case .failed:
            summaryText = "Managed process failed."
        }

        return AgentKernelManagedProcessRecordV2(
            processID: managed.processID,
            command: managed.command,
            workingDirectory: managed.workingDirectory,
            ownerSessionID: managed.ownerSessionID,
            pid: managed.pid,
            startedAt: managed.startedAt,
            status: status,
            exitCode: managed.exitCode,
            detectedServer: detected,
            stdoutTail: AgentKernelBoundedTextV2(stdout),
            stderrTail: AgentKernelBoundedTextV2(stderr),
            sources: [
                AgentKernelToolSourceRecordV2(
                    id: "managed-process:\(managed.processID)",
                    kind: "managed_process",
                    path: managed.workingDirectory,
                    displayName: managed.processID,
                    summary: AgentKernelBoundedTextV2(summaryText),
                    isTruncated: managed.wasOutputTruncated,
                    metadata: [
                        "status": .string(status.rawValue),
                        "pid": .int(Int(managed.pid ?? -1)),
                        "exitCode": .int(Int(managed.exitCode ?? -1))
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

    private nonisolated func firstURLMatch(in text: String) -> (url: URL, port: Int?)? {
        let pattern = #"https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(?::(\d+))?(?:/[^\s]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        let rawURL = nsText.substring(with: match.range)
            .replacingOccurrences(of: "0.0.0.0", with: "127.0.0.1")
            .replacingOccurrences(of: "[::1]", with: "localhost")
        guard let url = URL(string: rawURL) else {
            return nil
        }
        let port: Int?
        if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
            port = Int(nsText.substring(with: match.range(at: 1)))
        } else {
            port = url.port
        }
        return (url, port)
    }

    private nonisolated static func isListening(
        host: String,
        port: Int,
        timeoutSeconds: Double = 0.4
    ) -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return false
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        let ready = AgentKernelLockedValueV2(false)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.set(true)
                semaphore.signal()
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue.global(qos: .utility))
        _ = semaphore.wait(timeout: .now() + timeoutSeconds)
        connection.cancel()
        return ready.value
    }

    private nonisolated static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return normalized == "localhost"
            || normalized == "127.0.0.1"
            || normalized == "::1"
    }

    private nonisolated static func httpStatusCode(
        for url: URL,
        timeoutSeconds: TimeInterval = 0.8
    ) -> Int? {
        let semaphore = DispatchSemaphore(value: 0)
        let statusCode = AgentKernelLockedValueV2<Int?>(nil)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSeconds
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            statusCode.set((response as? HTTPURLResponse)?.statusCode)
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeoutSeconds + 0.2)
        task.cancel()
        return statusCode.value
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

private final class AgentKernelManagedProcessV2: @unchecked Sendable {
    let processID: String
    let command: String
    let workingDirectory: String
    let ownerSessionID: UUID
    let startedAt: Date
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let collector: AgentKernelProcessTailCollectorV2

    nonisolated init(
        processID: String,
        command: String,
        workingDirectory: String,
        ownerSessionID: UUID,
        startedAt: Date,
        maxTailBytes: Int
    ) {
        self.processID = processID
        self.command = command
        self.workingDirectory = workingDirectory
        self.ownerSessionID = ownerSessionID
        self.startedAt = startedAt
        self.collector = AgentKernelProcessTailCollectorV2(maxBytes: maxTailBytes)
    }

    nonisolated var isRunning: Bool {
        process.isRunning
    }

    nonisolated var pid: Int32? {
        process.processIdentifier == 0 ? nil : process.processIdentifier
    }

    nonisolated var exitCode: Int32? {
        process.isRunning ? nil : process.terminationStatus
    }

    nonisolated var status: AgentKernelManagedProcessKindV2 {
        if process.isRunning {
            return .running
        }
        if process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGTERM {
            return .stopped
        }
        return .exited
    }

    nonisolated var stdoutTail: String {
        collector.stdoutText
    }

    nonisolated var stderrTail: String {
        collector.stderrText
    }

    nonisolated var wasOutputTruncated: Bool {
        collector.wasTruncated
    }

    nonisolated func start() throws {
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { [collector] handle in
            collector.appendStdout(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [collector] handle in
            collector.appendStderr(handle.availableData)
        }
        try process.run()
    }

    nonisolated func stop(timeoutMilliseconds: Int) {
        guard process.isRunning else {
            cleanupHandlers()
            return
        }
        process.terminate()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async { [process] in
            process.waitUntilExit()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + .milliseconds(max(1, timeoutMilliseconds)))
        cleanupHandlers()
    }

    private nonisolated func cleanupHandlers() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        collector.appendStdout((try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data())
        collector.appendStderr((try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data())
    }
}

private final class AgentKernelProcessTailCollectorV2: @unchecked Sendable {
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

        target.append(data)
        if target.count > maxBytes {
            target.removeFirst(target.count - maxBytes)
            wasTruncated = true
        }
    }

    private nonisolated func text(from data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? String(decoding: data, as: UTF8.self)
    }
}

private final class AgentKernelLockedValueV2<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var storedValue: Value

    nonisolated init(_ value: Value) {
        self.storedValue = value
    }

    nonisolated var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    nonisolated func set(_ value: Value) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}
