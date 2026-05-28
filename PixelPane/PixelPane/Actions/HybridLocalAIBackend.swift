import Foundation

final class HybridLocalAIBackend: AIBackend, @unchecked Sendable {
    let id = "hybrid-local"
    let displayName = "Local AI"

    private let appleBackend: AppleFoundationModelsBackend
    private let mlxTextBackend: MLXTextBackend
    private let mlxBackend: MLXVisionBackend
    private let mlxDetector: MLXVisionRuntimeDetector

    nonisolated init(
        appleBackend: AppleFoundationModelsBackend = AppleFoundationModelsBackend(),
        mlxTextBackend: MLXTextBackend = MLXTextBackend(),
        mlxBackend: MLXVisionBackend = MLXVisionBackend(),
        mlxDetector: MLXVisionRuntimeDetector = MLXVisionRuntimeDetector()
    ) {
        self.appleBackend = appleBackend
        self.mlxTextBackend = mlxTextBackend
        self.mlxBackend = mlxBackend
        self.mlxDetector = mlxDetector
    }

    nonisolated func capabilities() async -> AIBackendCapabilities {
        let appleCapabilities = await appleBackend.capabilities()
        let mlxTextStatus = mlxDetector.textCapabilityStatus()
        return AIBackendCapabilities(
            text: mlxTextStatus.isAvailable ? mlxTextStatus : appleCapabilities.text,
            image: mlxDetector.imageCapabilityStatus(),
            contextWindowTokens: appleCapabilities.contextWindowTokens,
            maxPromptCharacters: AIModelLimits.maxPromptCharacters,
            maxOutputTokens: AIModelLimits.defaultMaxOutputTokens
        )
    }

    nonisolated func streamResponse(for request: AIBackendRequest) -> AsyncThrowingStream<AIBackendStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [appleBackend, mlxTextBackend, mlxBackend, mlxDetector] in
                do {
                    let stream: AsyncThrowingStream<AIBackendStreamEvent, Error>
                    if request.preferredProvider == .appleFoundationModels {
                        stream = appleBackend.streamResponse(for: request)
                    } else if request.preferredProvider == .mlxText {
                        stream = mlxTextBackend.streamResponse(for: request)
                    } else if request.capturedImage == nil, request.preferredProvider != .mlxVision {
                        let status = mlxDetector.textCapabilityStatus()
                        stream = status.isAvailable
                            ? mlxTextBackend.streamResponse(for: request)
                            : appleBackend.streamResponse(for: request)
                    } else {
                        let status = mlxDetector.imageCapabilityStatus()
                        switch status {
                        case .available:
                            stream = mlxBackend.streamResponse(for: request)
                        case .installing:
                            throw AIBackendError.unavailable(.mlxSmokeTestMissing)
                        case .unavailable(let reason):
                            throw AIBackendError.unavailable(reason)
                        }
                    }

                    for try await event in stream {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
