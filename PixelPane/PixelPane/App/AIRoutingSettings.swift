import Foundation

struct AIRoutingSettings: Equatable, Sendable {
    static let cloudBackendBaseURL = URL(string: "https://pixel-pane-api.snehithn5.workers.dev/v1")!
    static let cloudBackendAvailable = true

    var useCloudModels: Bool
    var allowCloudImageContext: Bool
    /// Explicit consent to attach an approximate (city-level) location to
    /// Cloud Mode requests. Off by default; never applies to the local route.
    var allowCloudLocationContext: Bool
    /// When set, Local mode uses exactly this installed model (by repository id)
    /// instead of the automatic router. Nil = automatic routing.
    var pinnedLocalModelID: String?

    /// When on (and configured), every action routes to the user's own provider
    /// account (OpenAI/Anthropic) instead of Local or Cloud. The API key lives
    /// only in the Keychain; this struct carries the non-secret configuration.
    var customProviderEnabled: Bool
    var customProvider: CustomProvider
    var customModelName: String
    /// Optional base-URL override (e.g. an Azure/OpenRouter-style endpoint).
    /// Nil/empty uses the provider's default base URL.
    var customBaseURLOverride: String?

    init(
        useCloudModels: Bool,
        allowCloudImageContext: Bool,
        allowCloudLocationContext: Bool = false,
        pinnedLocalModelID: String? = nil,
        customProviderEnabled: Bool = false,
        customProvider: CustomProvider = .openAI,
        customModelName: String = "",
        customBaseURLOverride: String? = nil
    ) {
        self.useCloudModels = useCloudModels
        self.allowCloudImageContext = allowCloudImageContext
        self.allowCloudLocationContext = allowCloudLocationContext
        self.pinnedLocalModelID = pinnedLocalModelID
        self.customProviderEnabled = customProviderEnabled
        self.customProvider = customProvider
        self.customModelName = customModelName
        self.customBaseURLOverride = customBaseURLOverride
    }

    /// True when the custom route has the minimum non-secret configuration (a
    /// model name). The API key is checked separately at request time because
    /// it lives in the Keychain, not in this struct.
    var isCustomProviderConfigured: Bool {
        customProviderEnabled
            && !customModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var effectiveMode: AIRoutingMode {
        if isCustomProviderConfigured {
            return .custom
        }
        return useCloudModels && Self.cloudBackendAvailable ? .cloud : .local
    }

    var statusLabel: String {
        switch effectiveMode {
        case .local:
            "Local Mode"
        case .cloud:
            "Cloud Mode"
        case .custom:
            "Custom Provider"
        }
    }

    var detail: String {
        switch effectiveMode {
        case .custom:
            return "Every action runs against your own \(customProvider.displayName) account using the model you set below."
        case .cloud:
            return "Cloud-capable actions can use Pixel Pane Cloud, including captured image context when the action supports it."
        case .local:
            if Self.cloudBackendAvailable {
                return "All actions run on this Mac unless Cloud Mode is turned on."
            }
            return "Cloud Mode is prepared but unavailable until the backend and app auth are configured."
        }
    }
}

enum AIRoutingMode: Equatable, Sendable {
    case local
    case cloud
    case custom

    var displayName: String {
        switch self {
        case .local:
            "Local"
        case .cloud:
            "Cloud"
        case .custom:
            "Custom"
        }
    }
}

/// A user-supplied third-party AI provider (bring-your-own-key).
enum CustomProvider: String, CaseIterable, Equatable, Sendable {
    case openAI
    case anthropic

    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .anthropic:
            "Anthropic"
        }
    }

    /// Default API base URL (no trailing path component beyond the version root).
    var defaultBaseURL: URL {
        switch self {
        case .openAI:
            URL(string: "https://api.openai.com/v1")!
        case .anthropic:
            URL(string: "https://api.anthropic.com/v1")!
        }
    }

    /// The models offered in the settings dropdown. Selection is preset-only:
    /// the UI deliberately has no free-text model entry.
    var presetModelNames: [String] {
        switch self {
        case .openAI:
            ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"]
        case .anthropic:
            ["claude-haiku-4-5", "claude-sonnet-4-6", "claude-opus-4-8"]
        }
    }

    /// The model prefilled when a provider is first selected. Not necessarily
    /// the first preset (e.g. Anthropic defaults to Sonnet, the balanced pick).
    var suggestedModelName: String {
        switch self {
        case .openAI:
            "gpt-4o-mini"
        case .anthropic:
            "claude-sonnet-4-6"
        }
    }

    /// Keychain account used to store this provider's API key.
    var keychainAccount: String {
        switch self {
        case .openAI:
            "openai-api-key"
        case .anthropic:
            "anthropic-api-key"
        }
    }
}

enum AIRoutingDefaults {
    static let useCloudModelsKey = "UseCloudModels"
    static let allowCloudImageContextKey = "AllowCloudImageContext"
    static let allowCloudLocationContextKey = "AllowCloudLocationContext"
    static let pinnedLocalModelIDKey = "PinnedLocalModelID"
    static let customProviderEnabledKey = "CustomProviderEnabled"
    static let customProviderKey = "CustomProviderKind"
    static let customModelNameKey = "CustomProviderModelName"
    static let customBaseURLOverrideKey = "CustomProviderBaseURLOverride"
}
