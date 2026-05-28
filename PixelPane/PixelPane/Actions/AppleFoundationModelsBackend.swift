import Foundation
import FoundationModels

final class AppleFoundationModelsBackend: AIBackend, @unchecked Sendable {
    let id = "apple-foundation-models"
    let displayName = "Apple Foundation Models"

    nonisolated init() {}

    nonisolated func capabilities() async -> AIBackendCapabilities {
        AIBackendCapabilities(
            text: appleTextStatus(),
            image: .unavailable(.imageInputUnsupported),
            contextWindowTokens: appleContextWindowTokens(),
            maxPromptCharacters: AIModelLimits.maxPromptCharacters,
            maxOutputTokens: AIModelLimits.defaultMaxOutputTokens
        )
    }

    nonisolated func streamResponse(for request: AIBackendRequest) -> AsyncThrowingStream<AIBackendStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [self] in
                do {
                    try validate(request: request)
                    try await streamAppleResponse(for: request, continuation: continuation)
                } catch is CancellationError {
                    continuation.finish(throwing: AIBackendError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private nonisolated func validate(request: AIBackendRequest) throws {
        if request.prompt.count > AIModelLimits.maxPromptCharacters {
            throw AIBackendError.promptTooLarge(maxCharacters: AIModelLimits.maxPromptCharacters)
        }

        if request.capturedImage != nil {
            throw AIBackendError.unavailable(.imageInputUnsupported)
        }

        switch appleTextStatus() {
        case .available:
            break
        case .installing:
            throw AIBackendError.unavailable(.appleModelNotReady)
        case .unavailable(let reason):
            throw AIBackendError.unavailable(reason)
        }
    }

    private nonisolated func streamAppleResponse(
        for request: AIBackendRequest,
        continuation: AsyncThrowingStream<AIBackendStreamEvent, Error>.Continuation
    ) async throws {
        guard #available(macOS 26.0, *) else {
            throw AIBackendError.unavailable(.appleFrameworkUnavailable)
        }

        let session = LanguageModelSession(
            model: .default,
            instructions: "You are Pixel Pane's private on-device assistant. Answer concisely and do not claim image access unless image content is provided by another backend."
        )
        let options = GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: min(request.maxOutputTokens, AIModelLimits.defaultMaxOutputTokens)
        )

        for try await snapshot in session.streamResponse(to: request.prompt, options: options) {
            try Task.checkCancellation()
            continuation.yield(.snapshot(snapshot.content))
        }

        continuation.yield(.completed)
        continuation.finish()
    }

    private nonisolated func appleTextStatus() -> AIBackendCapabilityStatus {
        guard #available(macOS 26.0, *) else {
            return .unavailable(.appleFrameworkUnavailable)
        }

        switch SystemLanguageModel.default.availability {
        case .available:
            return .available(.appleFoundationModels)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceDisabled)
        case .unavailable(.modelNotReady):
            return .installing(.appleFoundationModels, detail: AIBackendUnavailableReason.appleModelNotReady.detail)
        case .unavailable(.deviceNotEligible):
            return .unavailable(.hardwareUnsupported)
        @unknown default:
            return .unavailable(.unknown)
        }
    }

    private nonisolated func appleContextWindowTokens() -> Int? {
        guard #available(macOS 26.0, *) else { return nil }
        return SystemLanguageModel.default.contextSize
    }
}
