import CoreGraphics
import Foundation

enum AIActionKind: String, Sendable {
    case translate
    case explain
    case simplify
    case ask
    case chat
    case debug
}

struct AIBackendRequest: Sendable {
    let actionKind: AIActionKind
    let prompt: String
    let capturedImage: CGImage?
    let maxOutputTokens: Int
    let preferredProvider: AIBackendProvider?
    let cloudOCRText: String?
    let cloudDetectedLanguage: String?
    let cloudTargetLanguage: String?
    let cloudQuestion: String?
    let cloudConversation: [AIBackendConversationTurn]

    init(
        actionKind: AIActionKind,
        prompt: String,
        capturedImage: CGImage? = nil,
        maxOutputTokens: Int = AIModelLimits.defaultMaxOutputTokens,
        preferredProvider: AIBackendProvider? = nil,
        cloudOCRText: String? = nil,
        cloudDetectedLanguage: String? = nil,
        cloudTargetLanguage: String? = nil,
        cloudQuestion: String? = nil,
        cloudConversation: [AIBackendConversationTurn] = []
    ) {
        self.actionKind = actionKind
        self.prompt = prompt
        self.capturedImage = capturedImage
        self.maxOutputTokens = maxOutputTokens
        self.preferredProvider = preferredProvider
        self.cloudOCRText = cloudOCRText
        self.cloudDetectedLanguage = cloudDetectedLanguage
        self.cloudTargetLanguage = cloudTargetLanguage
        self.cloudQuestion = cloudQuestion
        self.cloudConversation = cloudConversation
    }
}

enum AIBackendStreamEvent: Sendable {
    case metadata([AIModelOutputStatistic])
    case snapshot(String)
    case output(AIModelOutput)
    case completed
}

struct AIBackendConversationTurn: Equatable, Sendable {
    let role: AIBackendConversationRole
    let content: String
}

enum AIBackendConversationRole: String, Sendable {
    case user
    case assistant
}

struct AIModelOutput: Equatable, Sendable {
    let finalText: String
    let reasoningText: String?
    let statistics: [AIModelOutputStatistic]
}

struct AIModelOutputStatistic: Equatable, Identifiable, Sendable {
    let label: String
    let value: String
    let detail: String?

    var id: String {
        "\(label)-\(value)-\(detail ?? "")"
    }
}

protocol AIBackend: Sendable {
    var id: String { get }
    var displayName: String { get }

    func capabilities() async -> AIBackendCapabilities
    func streamResponse(for request: AIBackendRequest) -> AsyncThrowingStream<AIBackendStreamEvent, Error>
}

struct AIBackendCapabilities: Sendable {
    let text: AIBackendCapabilityStatus
    let image: AIBackendCapabilityStatus
    let contextWindowTokens: Int?
    let maxPromptCharacters: Int
    let maxOutputTokens: Int

    static let unknown = AIBackendCapabilities(
        text: .unavailable(.unknown),
        image: .unavailable(.unknown),
        contextWindowTokens: nil,
        maxPromptCharacters: AIModelLimits.maxPromptCharacters,
        maxOutputTokens: AIModelLimits.defaultMaxOutputTokens
    )
}

enum AIBackendCapabilityStatus: Sendable {
    case available(AIBackendProvider)
    case installing(AIBackendProvider, detail: String)
    case unavailable(AIBackendUnavailableReason)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .available(let provider):
            "\(provider.displayName) available"
        case .installing(let provider, let detail):
            "\(provider.displayName) setup: \(detail)"
        case .unavailable(let reason):
            reason.label
        }
    }

    var detail: String {
        switch self {
        case .available(let provider):
            provider.availableDetail
        case .installing(_, let detail):
            detail
        case .unavailable(let reason):
            reason.detail
        }
    }
}

enum AIBackendProvider: String, Sendable {
    case appleFoundationModels
    case mlxText
    case mlxVision
    case pixelPaneCloud

    var displayName: String {
        switch self {
        case .appleFoundationModels:
            "Apple Foundation Models"
        case .mlxText:
            "MLX Text"
        case .mlxVision:
            "MLX Vision"
        case .pixelPaneCloud:
            "Pixel Pane Cloud"
        }
    }

    var availableDetail: String {
        switch self {
        case .appleFoundationModels:
            "Text-only local generation can run on this Mac."
        case .mlxText:
            "Text-only local generation has a selected MLX model and passed setup."
        case .mlxVision:
            "Image-aware local generation has a selected model and passed setup."
        case .pixelPaneCloud:
            "Cloud generation is available when Cloud Mode is enabled."
        }
    }
}

enum AIBackendUnavailableReason: Sendable {
    case appleFrameworkUnavailable
    case appleIntelligenceDisabled
    case appleModelNotReady
    case hardwareUnsupported
    case imageInputUnsupported
    case mlxRuntimeMissing
    case mlxModelMissing
    case mlxModelTooLarge
    case mlxSmokeTestMissing
    case mlxGenerationTimeout
    case cloudModeDisabled
    case cloudImageConsentMissing
    case promptTooLarge(maxCharacters: Int)
    case generationFailed
    case cancelled
    case unknown

    var label: String {
        switch self {
        case .appleFrameworkUnavailable:
            "Apple local AI unavailable"
        case .appleIntelligenceDisabled:
            "Apple Intelligence disabled"
        case .appleModelNotReady:
            "Apple model not ready"
        case .hardwareUnsupported:
            "Hardware unsupported"
        case .imageInputUnsupported:
            "Image input unavailable"
        case .mlxRuntimeMissing:
            "MLX runtime missing"
        case .mlxModelMissing:
            "MLX model missing"
        case .mlxModelTooLarge:
            "MLX model too large"
        case .mlxSmokeTestMissing:
            "MLX setup needed"
        case .mlxGenerationTimeout:
            "MLX timed out"
        case .cloudModeDisabled:
            "Cloud Mode off"
        case .cloudImageConsentMissing:
            "Cloud image consent needed"
        case .promptTooLarge:
            "Prompt too large"
        case .generationFailed:
            "Generation failed"
        case .cancelled:
            "Cancelled"
        case .unknown:
            "Unknown"
        }
    }

    var detail: String {
        switch self {
        case .appleFrameworkUnavailable:
            "Apple Foundation Models requires macOS 26 or later."
        case .appleIntelligenceDisabled:
            "Enable Apple Intelligence in System Settings before using text-only local AI."
        case .appleModelNotReady:
            "The on-device Apple model is downloading or otherwise not ready yet."
        case .hardwareUnsupported:
            "This Mac is not eligible for the requested local model."
        case .imageInputUnsupported:
            "Apple Foundation Models is text-only here; image-aware local actions require MLX setup."
        case .mlxRuntimeMissing:
            "Install the supported MLX runtime before enabling local MLX chat or image-aware actions."
        case .mlxModelMissing:
            "No compatible local MLX model was found."
        case .mlxModelTooLarge:
            "The selected MLX model could not fit in available memory."
        case .mlxSmokeTestMissing:
            "A compatible MLX model was found, but setup has not accepted it yet."
        case .mlxGenerationTimeout:
            "The MLX model did not respond before the local timeout."
        case .cloudModeDisabled:
            "Cloud Mode is off. Run this action locally instead."
        case .cloudImageConsentMissing:
            "Sending captured images to cloud requires a separate per-action opt-in."
        case .promptTooLarge(let maxCharacters):
            "Keep local prompts under \(maxCharacters) characters."
        case .generationFailed:
            "The local model did not produce a response."
        case .cancelled:
            "The request was cancelled."
        case .unknown:
            "Local AI status has not been checked yet."
        }
    }
}

enum AIBackendError: LocalizedError, Sendable {
    case unavailable(AIBackendUnavailableReason)
    case promptTooLarge(maxCharacters: Int)
    case generationFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            reason.detail
        case .promptTooLarge(let maxCharacters):
            "Prompt exceeds the local limit of \(maxCharacters) characters."
        case .generationFailed(let message):
            message
        case .cancelled:
            AIBackendUnavailableReason.cancelled.detail
        }
    }
}

enum AIModelLimits {
    static let maxPromptCharacters = 12_000
    static let defaultMaxOutputTokens = 4_096
}
