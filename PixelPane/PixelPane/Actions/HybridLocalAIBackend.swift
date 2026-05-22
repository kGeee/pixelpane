import Foundation

final class HybridLocalAIBackend: AIBackend {
    let id = "hybrid-local"
    let displayName = "Local AI"

    private let appleBackend: AppleFoundationModelsBackend
    private let mlxTextBackend: MLXTextBackend
    private let mlxBackend: MLXVisionBackend
    private let mlxDetector: MLXVisionRuntimeDetector

    init(
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

    func capabilities() async -> AIBackendCapabilities {
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

    func streamResponse(for request: AIBackendRequest) -> AsyncThrowingStream<AIBackendStreamEvent, Error> {
        if request.preferredProvider == .appleFoundationModels {
            return appleBackend.streamResponse(for: request)
        }

        if request.preferredProvider == .mlxText {
            return mlxTextBackend.streamResponse(for: request)
        }

        if request.capturedImage == nil, request.preferredProvider != .mlxVision {
            let status = mlxDetector.textCapabilityStatus()
            if status.isAvailable {
                return mlxTextBackend.streamResponse(for: request)
            }
            return appleBackend.streamResponse(for: request)
        }

        return AsyncThrowingStream { continuation in
            let status = mlxDetector.imageCapabilityStatus()
            switch status {
            case .available:
                Task {
                    do {
                        for try await event in mlxBackend.streamResponse(for: request) {
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            case .installing:
                continuation.finish(throwing: AIBackendError.unavailable(.mlxSmokeTestMissing))
            case .unavailable(let reason):
                continuation.finish(throwing: AIBackendError.unavailable(reason))
            }
        }
    }
}
