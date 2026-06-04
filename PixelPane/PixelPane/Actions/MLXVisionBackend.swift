import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class MLXVisionBackend: AIBackend, @unchecked Sendable {
    let id = "mlx-vision"
    let displayName = "MLX Vision"

    private let detector: MLXVisionRuntimeDetector
    private let store: MLXVisionModelStore
    private let timeoutSeconds: TimeInterval

    nonisolated init(
        detector: MLXVisionRuntimeDetector = MLXVisionRuntimeDetector(),
        store: MLXVisionModelStore = MLXVisionModelStore(),
        timeoutSeconds: TimeInterval = 180
    ) {
        self.detector = detector
        self.store = store
        self.timeoutSeconds = timeoutSeconds
    }

    nonisolated func capabilities() async -> AIBackendCapabilities {
        AIBackendCapabilities(
            text: .unavailable(.imageInputUnsupported),
            image: detector.imageCapabilityStatus(),
            contextWindowTokens: nil,
            maxPromptCharacters: AIModelLimits.maxPromptCharacters,
            maxOutputTokens: AIModelLimits.defaultMaxOutputTokens
        )
    }

    nonisolated func streamResponse(for request: AIBackendRequest) -> AsyncThrowingStream<AIBackendStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let state = ProcessStreamState(continuation: continuation)
            let task = Task.detached(priority: .userInitiated) { [self] in

                guard request.prompt.count <= AIModelLimits.maxPromptCharacters else {
                    state.fail(error: AIBackendError.promptTooLarge(maxCharacters: AIModelLimits.maxPromptCharacters))
                    return
                }

                guard let executableURL = detector.mlxGenerateExecutableURL() else {
                    state.fail(error: AIBackendError.unavailable(.mlxRuntimeMissing))
                    return
                }

                // Vision routes deterministically to the strongest installed
                // vision-capable model; the stored selection is only a
                // fallback for custom-folder models outside the HF cache.
                let candidateURLs: [URL] = [
                    detector.bestInstalledVisionModel()?.localURL,
                    store.selectedModel.map { URL(fileURLWithPath: $0.localPath) }
                ].compactMap { $0 }
                guard !candidateURLs.isEmpty else {
                    state.fail(error: AIBackendError.unavailable(.mlxModelMissing))
                    return
                }
                guard let snapshotURL = candidateURLs.lazy.compactMap(detector.usableVisionSnapshotURL(in:)).first else {
                    // No usable vision snapshot anywhere: distinguish "no
                    // vision-capable model installed" (degrade to OCR-only
                    // flows) from "a vision model exists but is unusable".
                    let hasVisionCapableModel = detector.bestInstalledVisionModel() != nil
                    state.fail(error: AIBackendError.unavailable(hasVisionCapableModel ? .mlxSmokeTestMissing : .mlxModelMissing))
                    return
                }

                var temporaryImageURL: URL?
                do {
                    if let image = request.capturedImage {
                        temporaryImageURL = try writeTemporaryPNG(image)
                    } else {
                        temporaryImageURL = nil
                    }
                    let cleanupImageURL = temporaryImageURL

                    let process = Process()
                    process.executableURL = executableURL
                    var arguments = [
                        "--model", snapshotURL.path,
                        "--prompt", request.prompt,
                        "--max-tokens", "\(min(request.maxOutputTokens, AIModelLimits.defaultMaxOutputTokens))"
                    ]
                    if let cleanupImageURL {
                        arguments.append(contentsOf: ["--image", cleanupImageURL.path])
                    }
                    process.arguments = arguments

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
                        if let cleanupImageURL {
                            try? FileManager.default.removeItem(at: cleanupImageURL)
                        }

                        if finishedProcess.terminationStatus == 0 {
                            state.complete()
                        } else {
                            state.fail(reason: self.reason(for: state.diagnostics))
                        }
                    }

                    try process.run()

                    let timeoutTask = Task.detached { [timeoutSeconds = self.timeoutSeconds] in
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
                        if let cleanupImageURL {
                            try? FileManager.default.removeItem(at: cleanupImageURL)
                        }
                    }
                } catch {
                    if let temporaryImageURL {
                        try? FileManager.default.removeItem(at: temporaryImageURL)
                    }
                    state.fail(error: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                state.cancel()
            }
        }
    }

    private nonisolated func writeTemporaryPNG(_ image: CGImage) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-pane-mlx-\(UUID().uuidString)")
            .appendingPathExtension("png")

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw AIBackendError.generationFailed("Could not create temporary image for MLX.")
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw AIBackendError.generationFailed("Could not write temporary image for MLX.")
        }

        return url
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

private final class ProcessStreamState: @unchecked Sendable {
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
