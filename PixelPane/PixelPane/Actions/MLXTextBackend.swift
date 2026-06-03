import Foundation

final class MLXTextBackend: AIBackend, @unchecked Sendable {
    let id = "mlx-text"
    let displayName = "MLX Text"

    private let detector: MLXVisionRuntimeDetector
    private let store: MLXVisionModelStore
    private let modelSelectionOverride: MLXVisionModelSelection?
    private let timeoutSeconds: TimeInterval
    private let runtimeCache = MLXTextRuntimeCache()

    nonisolated init(
        detector: MLXVisionRuntimeDetector = MLXVisionRuntimeDetector(),
        store: MLXVisionModelStore = MLXVisionModelStore(),
        modelSelectionOverride: MLXVisionModelSelection? = nil,
        timeoutSeconds: TimeInterval = 120
    ) {
        self.detector = detector
        self.store = store
        self.modelSelectionOverride = modelSelectionOverride
        self.timeoutSeconds = timeoutSeconds
    }

    /// The model this backend will run: an explicit router-chosen model when provided,
    /// otherwise the user/store's current selection.
    private nonisolated var activeSelection: MLXVisionModelSelection? {
        modelSelectionOverride ?? store.selectedModel
    }

    nonisolated func capabilities() async -> AIBackendCapabilities {
        AIBackendCapabilities(
            text: detector.textCapabilityStatus(),
            image: .unavailable(.imageInputUnsupported),
            contextWindowTokens: nil,
            maxPromptCharacters: AIModelLimits.maxPromptCharacters,
            maxOutputTokens: AIModelLimits.defaultMaxOutputTokens
        )
    }

    nonisolated func streamResponse(for request: AIBackendRequest) -> AsyncThrowingStream<AIBackendStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let state = MLXProcessStreamState(continuation: continuation)
            let task = Task.detached(priority: .userInitiated) { [self] in
                guard request.prompt.count <= AIModelLimits.maxPromptCharacters else {
                    state.fail(error: AIBackendError.promptTooLarge(maxCharacters: AIModelLimits.maxPromptCharacters))
                    return
                }

                let runtime: MLXTextResolvedRuntime
                do {
                    runtime = try self.resolveRuntime()
                } catch {
                    state.fail(error: error)
                    return
                }

                if let serverExecutableURL = runtime.serverExecutableURL {
                    await self.runServerResponse(
                        request: request,
                        runtime: runtime,
                        serverExecutableURL: serverExecutableURL,
                        state: state
                    )
                    return
                }

                self.runOneShot(
                    executableURL: runtime.generateExecutableURL,
                    snapshotURL: runtime.snapshotURL,
                    request: request,
                    state: state,
                    continuation: continuation,
                    onSuccessfulCompletion: nil
                )
            }
            continuation.onTermination = { _ in
                state.cancel()
                task.cancel()
            }
        }
    }

    nonisolated func completeResponse(for request: AIBackendRequest) async throws -> AIModelOutput {
        guard request.prompt.count <= AIModelLimits.maxPromptCharacters else {
            throw AIBackendError.promptTooLarge(maxCharacters: AIModelLimits.maxPromptCharacters)
        }

        let runtime = try resolveRuntime()

        if let serverExecutableURL = runtime.serverExecutableURL {
            return try await MLXTextServerManager.shared.response(
                prompt: request.prompt,
                maxOutputTokens: request.maxOutputTokens,
                modelURL: runtime.snapshotURL,
                executableURL: serverExecutableURL
            )
        }

        return try await completeOneShot(
            executableURL: runtime.generateExecutableURL,
            snapshotURL: runtime.snapshotURL,
            request: request
        )
    }

    nonisolated func nativeToolResponse(
        for request: AgentKernelModelAdapterRequest
    ) async throws -> [AgentKernelModelAdapterEvent] {
        let promptCharacters = request.messages.reduce(0) { $0 + $1.content.count }
        guard promptCharacters <= AIModelLimits.maxPromptCharacters else {
            throw AIBackendError.promptTooLarge(maxCharacters: AIModelLimits.maxPromptCharacters)
        }

        let runtime = try resolveRuntime()
        guard let serverExecutableURL = runtime.serverExecutableURL else {
            throw AIBackendError.unavailable(.mlxRuntimeMissing)
        }

        return try await MLXTextServerManager.shared.nativeToolResponse(
            request: request,
            modelURL: runtime.snapshotURL,
            executableURL: serverExecutableURL
        )
    }

    private nonisolated func resolveRuntime() throws -> MLXTextResolvedRuntime {
        guard let selection = activeSelection else {
            throw AIBackendError.unavailable(.mlxModelMissing)
        }

        let modelURL = URL(fileURLWithPath: selection.localPath)
        let cacheKey = [
            selection.repositoryID,
            selection.localPath,
            "\(selection.smokeTestedAt.timeIntervalSinceReferenceDate)"
        ].joined(separator: "|")

        return try runtimeCache.resolved(cacheKey: cacheKey) {
            guard let generateExecutableURL = detector.mlxTextGenerateExecutableURL() else {
                throw AIBackendError.unavailable(.mlxRuntimeMissing)
            }

            guard let snapshotURL = detector.usableTextSnapshotURL(in: modelURL) else {
                throw AIBackendError.unavailable(.mlxSmokeTestMissing)
            }

            return MLXTextResolvedRuntime(
                generateExecutableURL: generateExecutableURL,
                serverExecutableURL: detector.mlxTextServerExecutableURL(),
                snapshotURL: snapshotURL
            )
        }
    }

    private nonisolated func completeOneShot(
        executableURL: URL,
        snapshotURL: URL,
        request: AIBackendRequest
    ) async throws -> AIModelOutput {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = executableURL
                process.arguments = [
                    "--model", snapshotURL.path,
                    "--prompt", request.prompt,
                    "--chat-template-config", "{\"enable_thinking\":false}",
                    "--verbose", "False",
                    "--max-tokens", "\(min(request.maxOutputTokens, AIModelLimits.defaultMaxOutputTokens))"
                ]

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                final class Box: @unchecked Sendable {
                    var didResume = false
                    let lock = NSLock()
                    func resumeOnce(_ body: () -> Void) {
                        lock.withLock {
                            guard !didResume else { return }
                            didResume = true
                            body()
                        }
                    }
                }

                let box = Box()
                process.terminationHandler = { finishedProcess in
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let diagnostics = String(data: errorData, encoding: .utf8) ?? ""
                    box.resumeOnce {
                        if finishedProcess.terminationStatus == 0 {
                            continuation.resume(returning: ModelOutputFormatter().format(output))
                        } else {
                            continuation.resume(throwing: AIBackendError.unavailable(self.reason(for: diagnostics)))
                        }
                    }
                }

                do {
                    try process.run()
                } catch {
                    box.resumeOnce {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                Task.detached { [timeoutSeconds] in
                    try? await Task.sleep(for: .seconds(timeoutSeconds))
                    if process.isRunning {
                        process.terminate()
                        box.resumeOnce {
                            continuation.resume(throwing: AIBackendError.unavailable(.mlxGenerationTimeout))
                        }
                    }
                }
            }
        } onCancel: {
            Task {
                await MLXTextServerManager.shared.stop()
            }
        }
    }

    private nonisolated func runServerResponse(
        request: AIBackendRequest,
        runtime: MLXTextResolvedRuntime,
        serverExecutableURL: URL,
        state: MLXProcessStreamState
    ) async {
        do {
            let output = try await MLXTextServerManager.shared.response(
                prompt: request.prompt,
                maxOutputTokens: request.maxOutputTokens,
                modelURL: runtime.snapshotURL,
                executableURL: serverExecutableURL
            )
            state.finish(output: output)
        } catch {
            state.fail(error: error)
        }
    }

    private nonisolated func runOneShot(
        executableURL: URL,
        snapshotURL: URL,
        request: AIBackendRequest,
        state: MLXProcessStreamState,
        continuation: AsyncThrowingStream<AIBackendStreamEvent, Error>.Continuation,
        onSuccessfulCompletion: (@Sendable () -> Void)?
    ) {
        do {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = [
                "--model", snapshotURL.path,
                "--prompt", request.prompt,
                "--chat-template-config", "{\"enable_thinking\":false}",
                "--verbose", "False",
                "--max-tokens", "\(min(request.maxOutputTokens, AIModelLimits.defaultMaxOutputTokens))"
            ]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                state.append(chunk)
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                state.appendDiagnostics(chunk)
            }

            process.terminationHandler = { finishedProcess in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                if finishedProcess.terminationStatus == 0 {
                    state.complete()
                    onSuccessfulCompletion?()
                } else {
                    state.fail(reason: self.reason(for: state.diagnostics))
                }
            }

            try process.run()

            let timeoutTask = Task.detached { [timeoutSeconds] in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                if process.isRunning {
                    process.terminate()
                    state.fail(reason: .mlxGenerationTimeout)
                }
            }

            continuation.onTermination = { _ in
                state.cancel()
                timeoutTask.cancel()
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                if process.isRunning {
                    process.terminate()
                }
            }
        } catch {
            state.fail(error: error)
        }
    }

    private nonisolated func reason(for diagnostics: String) -> AIBackendUnavailableReason {
        let lowercased = diagnostics.lowercased()
        if lowercased.contains("out of memory") || lowercased.contains("memory") {
            return .mlxModelTooLarge
        }
        if lowercased.contains("no such file") || lowercased.contains("not found") {
            return .mlxModelMissing
        }
        return .generationFailed
    }
}

private struct MLXTextResolvedRuntime: Sendable {
    let generateExecutableURL: URL
    let serverExecutableURL: URL?
    let snapshotURL: URL
}

private final class MLXTextRuntimeCache: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var cachedKey: String?
    nonisolated(unsafe) private var cachedRuntime: MLXTextResolvedRuntime?

    nonisolated func resolved(
        cacheKey: String,
        _ build: () throws -> MLXTextResolvedRuntime
    ) throws -> MLXTextResolvedRuntime {
        try lock.withLock {
            if cachedKey == cacheKey, let cachedRuntime {
                return cachedRuntime
            }
            let runtime = try build()
            cachedKey = cacheKey
            cachedRuntime = runtime
            return runtime
        }
    }
}

private final class MLXProcessStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncThrowingStream<AIBackendStreamEvent, Error>.Continuation
    private let formatter = ModelOutputFormatter()
    nonisolated(unsafe) private var text = ""
    nonisolated(unsafe) private var didFinish = false
    nonisolated(unsafe) private(set) var diagnostics = ""

    nonisolated init(continuation: AsyncThrowingStream<AIBackendStreamEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    nonisolated func append(_ chunk: String) {
        lock.withLock {
            guard !didFinish else { return }
            text += chunk
            continuation.yield(.output(formatter.format(text)))
        }
    }

    nonisolated func appendDiagnostics(_ chunk: String) {
        lock.withLock {
            diagnostics += chunk
        }
    }

    nonisolated func complete() {
        lock.withLock {
            guard !didFinish else { return }
            didFinish = true
            continuation.yield(.completed)
            continuation.finish()
        }
    }

    nonisolated func finish(output: AIModelOutput) {
        lock.withLock {
            guard !didFinish else { return }
            didFinish = true
            continuation.yield(.output(output))
            continuation.yield(.completed)
            continuation.finish()
        }
    }

    nonisolated func cancel() {
        lock.withLock {
            guard !didFinish else { return }
            didFinish = true
            continuation.finish()
        }
    }

    nonisolated func fail(reason: AIBackendUnavailableReason) {
        fail(error: AIBackendError.unavailable(reason))
    }

    nonisolated func fail(error: Error) {
        lock.withLock {
            guard !didFinish else { return }
            didFinish = true
            continuation.finish(throwing: error)
        }
    }
}
