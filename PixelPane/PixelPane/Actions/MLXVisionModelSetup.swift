import AppKit
import Foundation

enum MLXVisionSetupConstants {
    static let preferredModelRepositoryID = "mlx-community/Qwen3.6-35B-A3B-6bit"
    static let preferredModelApproximateDiskSize = "29.1 GB"
    static let preferredModelLicense = "See Hugging Face model card"
    static let preferredModelURL = URL(string: "https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-6bit")!
}

enum MLXModelCapability: String, Codable, Sendable {
    case text
    case vision
    case textAndVision
    case unsupported

    var supportsText: Bool {
        self == .text || self == .textAndVision
    }

    var supportsVision: Bool {
        self == .vision || self == .textAndVision
    }

    var displayName: String {
        switch self {
        case .text:
            "Text"
        case .vision:
            "Vision"
        case .textAndVision:
            "Text + Vision"
        case .unsupported:
            "Unsupported"
        }
    }
}

struct MLXVisionModel: Identifiable, Hashable, Sendable {
    let repositoryID: String
    let localURL: URL?
    let approximateDiskSize: String
    let license: String
    let isPreferred: Bool
    let capability: MLXModelCapability

    var id: String { repositoryID }
    var isInstalled: Bool { localURL != nil }
    var isTextCompatible: Bool { capability.supportsText }
    var isVisionCompatible: Bool { capability.supportsVision }
    var displayName: String {
        isInstalled ? "\(repositoryID) (\(capability.displayName))" : repositoryID
    }
    var destinationPath: String {
        localURL?.path ?? MLXVisionModelStore.defaultCacheURL(for: repositoryID).path
    }
    var installCommand: String {
        "huggingface-cli download \(repositoryID)"
    }

    static func customDirectory(_ url: URL) -> MLXVisionModel {
        MLXVisionModel(
            repositoryID: "Local folder: \(url.lastPathComponent)",
            localURL: url,
            approximateDiskSize: "Already installed",
            license: "User-selected local model",
            isPreferred: false,
            capability: .unsupported
        )
    }
}

enum MLXVisionSetupState: String, Sendable {
    case notConfigured
    case runtimeMissing
    case modelMissing
    case ready
    case smokeTestFailed

    var capabilityStatus: AIBackendCapabilityStatus {
        switch self {
        case .ready:
            .available(.mlxVision)
        case .runtimeMissing:
            .unavailable(.mlxRuntimeMissing)
        case .modelMissing:
            .unavailable(.mlxModelMissing)
        case .notConfigured:
            .unavailable(.mlxSmokeTestMissing)
        case .smokeTestFailed:
            .unavailable(.mlxSmokeTestMissing)
        }
    }
}

struct MLXVisionSetupSnapshot: Sendable {
    let runtimeURL: URL?
    let textRuntimeURL: URL?
    let installedModels: [MLXVisionModel]
    let recommendedModel: MLXVisionModel
    let selectedModel: MLXVisionModel?
    let setupState: MLXVisionSetupState
    let setupDetail: String

    var textCapabilityStatus: AIBackendCapabilityStatus {
        guard textRuntimeURL != nil else {
            return .unavailable(.mlxRuntimeMissing)
        }
        guard setupState == .ready, let selectedModel, selectedModel.isTextCompatible else {
            return .unavailable(.mlxSmokeTestMissing)
        }
        return .available(.mlxText)
    }

    var imageCapabilityStatus: AIBackendCapabilityStatus {
        guard runtimeURL != nil else {
            return .unavailable(.mlxRuntimeMissing)
        }
        guard setupState == .ready, let selectedModel, selectedModel.isVisionCompatible else {
            return setupState == .runtimeMissing ? .unavailable(.mlxRuntimeMissing) : .unavailable(.mlxSmokeTestMissing)
        }
        return .available(.mlxVision)
    }
}

struct MLXVisionModelSelection: Codable, Sendable {
    let repositoryID: String
    let localPath: String
    let smokeTestedAt: Date
}

struct MLXVisionModelStore: Sendable {
    private static let selectedModelKey = "MLXVisionSelectedModel"
    private static let setupStateKey = "MLXVisionSetupState"
    private static let setupFailureKey = "MLXVisionSetupFailure"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedModel: MLXVisionModelSelection? {
        guard let data = defaults.data(forKey: Self.selectedModelKey) else { return nil }
        return try? JSONDecoder().decode(MLXVisionModelSelection.self, from: data)
    }

    var setupState: MLXVisionSetupState {
        guard let rawValue = defaults.string(forKey: Self.setupStateKey),
              let state = MLXVisionSetupState(rawValue: rawValue) else {
            return .notConfigured
        }
        return state
    }

    var setupFailure: String? {
        defaults.string(forKey: Self.setupFailureKey)
    }

    func saveSuccessfulSelection(repositoryID: String, localURL: URL) {
        let selection = MLXVisionModelSelection(
            repositoryID: repositoryID,
            localPath: localURL.path,
            smokeTestedAt: Date()
        )
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: Self.selectedModelKey)
        }
        defaults.set(MLXVisionSetupState.ready.rawValue, forKey: Self.setupStateKey)
        defaults.removeObject(forKey: Self.setupFailureKey)
    }

    func saveFailure(_ message: String) {
        defaults.set(MLXVisionSetupState.smokeTestFailed.rawValue, forKey: Self.setupStateKey)
        defaults.set(message, forKey: Self.setupFailureKey)
    }

    func clearSelection() {
        defaults.removeObject(forKey: Self.selectedModelKey)
        defaults.set(MLXVisionSetupState.notConfigured.rawValue, forKey: Self.setupStateKey)
        defaults.removeObject(forKey: Self.setupFailureKey)
    }

    static func defaultCacheURL(
        for repositoryID: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let cacheName = "models--" + repositoryID.replacingOccurrences(of: "/", with: "--")
        return homeDirectory
            .appendingPathComponent(".cache")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
            .appendingPathComponent(cacheName)
    }
}

struct MLXVisionSetupRunner: Sendable {
    private let detector: MLXVisionRuntimeDetector
    private let store: MLXVisionModelStore

    init(
        detector: MLXVisionRuntimeDetector = MLXVisionRuntimeDetector(),
        store: MLXVisionModelStore = MLXVisionModelStore()
    ) {
        self.detector = detector
        self.store = store
    }

    func snapshot() -> MLXVisionSetupSnapshot {
        detector.setupSnapshot()
    }

    func runSetupCheck(for model: MLXVisionModel) async -> MLXVisionSetupSnapshot {
        guard let localURL = model.localURL else {
            store.saveFailure("Download or place \(model.repositoryID) at \(model.destinationPath), then run setup again.")
            return detector.setupSnapshot()
        }

        let capability = detector.modelCapability(in: localURL)
        guard capability.supportsText || capability.supportsVision else {
            store.saveFailure("No usable MLX model files were found at \(localURL.path). Choose a model folder with config, tokenizer metadata, and weights.")
            return detector.setupSnapshot()
        }

        if capability.supportsText, detector.mlxTextGenerateExecutableURL() == nil {
            store.saveFailure("Install MLX-LM so Pixel Pane can find mlx_lm.generate for text chat.")
            return detector.setupSnapshot()
        }

        if capability.supportsVision, detector.mlxGenerateExecutableURL() == nil {
            store.saveFailure("Install MLX-VLM so Pixel Pane can find mlx_vlm.generate for image-aware actions.")
            return detector.setupSnapshot()
        }

        store.saveSuccessfulSelection(repositoryID: model.repositoryID, localURL: localURL)
        return detector.setupSnapshot()
    }

    func runSetupCheck(forCustomModelDirectory url: URL) async -> MLXVisionSetupSnapshot {
        await runSetupCheck(for: .customDirectory(url))
    }

    func clearSelection() -> MLXVisionSetupSnapshot {
        store.clearSelection()
        return detector.setupSnapshot()
    }

    @MainActor
    func openRecommendedModelPage() {
        NSWorkspace.shared.open(MLXVisionSetupConstants.preferredModelURL)
    }
}
