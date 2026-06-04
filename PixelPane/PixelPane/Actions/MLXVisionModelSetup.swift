import AppKit
import Foundation

nonisolated enum MLXVisionSetupConstants {
    static let preferredModelRepositoryID = "mlx-community/Qwen3.6-35B-A3B-6bit"
    static let preferredModelApproximateDiskSize = "29.1 GB"
    static let preferredModelLicense = "See Hugging Face model card"
    static let preferredModelURL = URL(string: "https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-6bit")!
}

nonisolated enum MLXModelCapability: String, Codable, Sendable {
    case text
    case vision
    case textAndVision
    case unsupported

    nonisolated var supportsText: Bool {
        self == .text || self == .textAndVision
    }

    nonisolated var supportsVision: Bool {
        self == .vision || self == .textAndVision
    }

    nonisolated var displayName: String {
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

nonisolated struct MLXVisionModel: Identifiable, Hashable, Sendable {
    let repositoryID: String
    let localURL: URL?
    let approximateDiskSize: String
    let license: String
    let isPreferred: Bool
    let capability: MLXModelCapability

    nonisolated var id: String { repositoryID }
    nonisolated var isInstalled: Bool { localURL != nil }
    nonisolated var isTextCompatible: Bool { capability.supportsText }
    nonisolated var isVisionCompatible: Bool { capability.supportsVision }
    nonisolated var displayName: String {
        isInstalled ? "\(repositoryID) (\(capability.displayName))" : repositoryID
    }
    nonisolated var destinationPath: String {
        localURL?.path ?? MLXVisionModelStore.defaultCacheURL(for: repositoryID).path
    }
    nonisolated var installCommand: String {
        "huggingface-cli download \(repositoryID)"
    }

    nonisolated static func customDirectory(_ url: URL) -> MLXVisionModel {
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

nonisolated enum MLXVisionSetupState: String, Sendable {
    case notConfigured
    case runtimeMissing
    case modelMissing
    case ready
    case smokeTestFailed

    nonisolated var capabilityStatus: AIBackendCapabilityStatus {
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

nonisolated struct MLXVisionSetupSnapshot: Sendable {
    let runtimeURL: URL?
    let textRuntimeURL: URL?
    let installedModels: [MLXVisionModel]
    let recommendedModel: MLXVisionModel
    let selectedModel: MLXVisionModel?
    let setupState: MLXVisionSetupState
    let setupDetail: String

    nonisolated var textCapabilityStatus: AIBackendCapabilityStatus {
        guard textRuntimeURL != nil else {
            return .unavailable(.mlxRuntimeMissing)
        }
        guard setupState == .ready, let selectedModel, selectedModel.isTextCompatible else {
            return .unavailable(.mlxSmokeTestMissing)
        }
        return .available(.mlxText)
    }

    nonisolated var imageCapabilityStatus: AIBackendCapabilityStatus {
        guard runtimeURL != nil else {
            return .unavailable(.mlxRuntimeMissing)
        }
        // Vision routes to the strongest installed vision-capable model, so
        // availability depends on any such model existing — not on which
        // model happens to be selected. With none installed, image-aware
        // actions stay hidden and captures degrade to OCR text gracefully.
        let hasVisionModel = installedModels.contains { $0.isInstalled && $0.isVisionCompatible }
            || selectedModel?.isVisionCompatible == true
        guard hasVisionModel else {
            return .unavailable(.mlxModelMissing)
        }
        return .available(.mlxVision)
    }
}

nonisolated struct MLXVisionModelSelection: Codable, Sendable {
    let repositoryID: String
    let localPath: String
    let smokeTestedAt: Date
}

extension AgentModelConformanceTarget {
    nonisolated static func mlxText(
        selection: MLXVisionModelSelection,
        textRuntimeURL: URL?,
        adapterID: String = AgentModelConformanceTarget.localMLXChatAdapterID
    ) -> AgentModelConformanceTarget {
        AgentModelConformanceTarget(
            providerKind: .mlxLocal,
            route: .local,
            adapterID: adapterID,
            modelID: selection.repositoryID,
            modelPath: selection.localPath,
            runtimeExecutablePath: textRuntimeURL?.path,
            runtimeVersion: nil
        )
    }

    nonisolated static func mlxText(
        snapshot: MLXVisionSetupSnapshot,
        adapterID: String = AgentModelConformanceTarget.localMLXChatAdapterID
    ) -> AgentModelConformanceTarget? {
        guard let selectedModel = snapshot.selectedModel,
              selectedModel.isTextCompatible,
              let selectedURL = selectedModel.localURL else {
            return nil
        }
        return AgentModelConformanceTarget(
            providerKind: .mlxLocal,
            route: .local,
            adapterID: adapterID,
            modelID: selectedModel.repositoryID,
            modelPath: selectedURL.path,
            runtimeExecutablePath: snapshot.textRuntimeURL?.path,
            runtimeVersion: nil
        )
    }
}

nonisolated struct MLXVisionModelStore: @unchecked Sendable {
    private static let selectedModelKey = "MLXVisionSelectedModel"
    private static let setupStateKey = "MLXVisionSetupState"
    private static let setupFailureKey = "MLXVisionSetupFailure"

    private let defaults: UserDefaults

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    nonisolated var selectedModel: MLXVisionModelSelection? {
        guard let data = defaults.data(forKey: Self.selectedModelKey) else { return nil }
        return try? JSONDecoder().decode(MLXVisionModelSelection.self, from: data)
    }

    nonisolated var setupState: MLXVisionSetupState {
        guard let rawValue = defaults.string(forKey: Self.setupStateKey),
              let state = MLXVisionSetupState(rawValue: rawValue) else {
            return .notConfigured
        }
        return state
    }

    nonisolated var setupFailure: String? {
        defaults.string(forKey: Self.setupFailureKey)
    }

    nonisolated func saveSuccessfulSelection(repositoryID: String, localURL: URL) {
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

    nonisolated func saveFailure(_ message: String) {
        defaults.set(MLXVisionSetupState.smokeTestFailed.rawValue, forKey: Self.setupStateKey)
        defaults.set(message, forKey: Self.setupFailureKey)
    }

    nonisolated func clearSelection() {
        defaults.removeObject(forKey: Self.selectedModelKey)
        defaults.set(MLXVisionSetupState.notConfigured.rawValue, forKey: Self.setupStateKey)
        defaults.removeObject(forKey: Self.setupFailureKey)
    }

    nonisolated static func defaultCacheURL(
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
