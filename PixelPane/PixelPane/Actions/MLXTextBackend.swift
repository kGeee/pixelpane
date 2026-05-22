import Foundation

final class MLXTextBackend: AIBackend, @unchecked Sendable {
    let id = "mlx-text"
    let displayName = "MLX Text"

    private let detector: MLXVisionRuntimeDetector
    private let store: MLXVisionModelStore
    private let timeoutSeconds: TimeInterval

    init(
        detector: MLXVisionRuntimeDetector = MLXVisionRuntimeDetector(),
        store: MLXVisionModelStore = MLXVisionModelStore(),
        timeoutSeconds: TimeInterval = 120
    ) {
        self.detector = detector
        self.store = store
        self.timeoutSeconds = timeoutSeconds
    }

    func capabilities() async -> AIBackendCapabilities {
        AIBackendCapabilities(
            text: detector.textCapabilityStatus(),
            image: .unavailable(.imageInputUnsupported),
            contextWindowTokens: nil,
            maxPromptCharacters: AIModelLimits.maxPromptCharacters,
            maxOutputTokens: AIModelLimits.defaultMaxOutputTokens
        )
    }

    func streamResponse(for request: AIBackendRequest) -> AsyncThrowingStream<AIBackendStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let state = MLXProcessStreamState(continuation: continuation)

            guard request.prompt.count <= AIModelLimits.maxPromptCharacters else {
                continuation.finish(throwing: AIBackendError.promptTooLarge(maxCharacters: AIModelLimits.maxPromptCharacters))
                return
            }

            guard let executableURL = detector.mlxTextGenerateExecutableURL() else {
                continuation.finish(throwing: AIBackendError.unavailable(.mlxRuntimeMissing))
                return
            }

            guard let selection = store.selectedModel else {
                continuation.finish(throwing: AIBackendError.unavailable(.mlxModelMissing))
                return
            }

            let modelURL = URL(fileURLWithPath: selection.localPath)
            guard let snapshotURL = detector.usableTextSnapshotURL(in: modelURL) else {
                continuation.finish(throwing: AIBackendError.unavailable(.mlxSmokeTestMissing))
                return
            }

            do {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = [
                    "--model", snapshotURL.path,
                    "--prompt", request.prompt,
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
    }

    private func reason(for diagnostics: String) -> AIBackendUnavailableReason {
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
