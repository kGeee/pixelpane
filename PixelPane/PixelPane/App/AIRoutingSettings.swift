import Foundation

struct AIRoutingSettings: Equatable, Sendable {
    static let cloudBackendBaseURL = URL(string: "https://pixel-pane-api.snehithn5.workers.dev/v1")!
    static let cloudBackendAvailable = true

    var useCloudModels: Bool
    var allowCloudImageContext: Bool
    /// When set, Local mode uses exactly this installed model (by repository id)
    /// instead of the automatic router. Nil = automatic routing.
    var pinnedLocalModelID: String?

    init(
        useCloudModels: Bool,
        allowCloudImageContext: Bool,
        pinnedLocalModelID: String? = nil
    ) {
        self.useCloudModels = useCloudModels
        self.allowCloudImageContext = allowCloudImageContext
        self.pinnedLocalModelID = pinnedLocalModelID
    }

    var effectiveMode: AIRoutingMode {
        useCloudModels && Self.cloudBackendAvailable ? .cloud : .local
    }

    var statusLabel: String {
        switch effectiveMode {
        case .local:
            "Local Mode"
        case .cloud:
            "Cloud Mode"
        }
    }

    var detail: String {
        if Self.cloudBackendAvailable {
            return useCloudModels
                ? "Cloud-capable actions can use Pixel Pane Cloud, including captured image context when the action supports it."
                : "All actions run on this Mac unless Cloud Mode is turned on."
        }

        return "Cloud Mode is prepared but unavailable until the backend and app auth are configured."
    }
}

enum AIRoutingMode: Equatable, Sendable {
    case local
    case cloud

    var displayName: String {
        switch self {
        case .local:
            "Local"
        case .cloud:
            "Cloud"
        }
    }
}

enum AIRoutingDefaults {
    static let useCloudModelsKey = "UseCloudModels"
    static let allowCloudImageContextKey = "AllowCloudImageContext"
    static let pinnedLocalModelIDKey = "PinnedLocalModelID"
}
