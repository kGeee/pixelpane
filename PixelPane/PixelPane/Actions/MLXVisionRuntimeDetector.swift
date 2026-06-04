import Foundation

nonisolated struct MLXVisionRuntimeDetector: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectory: URL
    private let store: MLXVisionModelStore

    nonisolated init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        store: MLXVisionModelStore = MLXVisionModelStore()
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.store = store
    }

    nonisolated func imageCapabilityStatus() -> AIBackendCapabilityStatus {
        setupSnapshot().imageCapabilityStatus
    }

    nonisolated func textCapabilityStatus() -> AIBackendCapabilityStatus {
        setupSnapshot().textCapabilityStatus
    }

    nonisolated func setupSnapshot() -> MLXVisionSetupSnapshot {
        let runtimeURL = mlxGenerateExecutableURL()
        let textRuntimeURL = mlxTextGenerateExecutableURL()
        let installedModels = cachedModels()
        let recommendedModel = recommendedModel(installedModels: installedModels)
        let selectedModel = selectedModel(from: installedModels)

        let state: MLXVisionSetupState
        let detail: String

        if runtimeURL == nil, textRuntimeURL == nil {
            state = .runtimeMissing
            detail = "Install MLX-LM or MLX-VLM so Pixel Pane can find a local MLX generation runtime."
        } else if let selectedModel,
                  let selectedURL = selectedModel.localURL,
                  store.setupState == .ready,
                  modelCapability(in: selectedURL) != .unsupported {
            state = .ready
            detail = "Using \(selectedModel.repositoryID) for \(selectedModel.capability.displayName) at \(selectedModel.destinationPath)."
        } else if store.setupState == .ready {
            state = .smokeTestFailed
            detail = "The selected local model is not a usable MLX text or vision model. Choose a folder with config, tokenizer metadata, and weights."
        } else if store.setupState == .smokeTestFailed {
            state = .smokeTestFailed
            detail = store.setupFailure ?? "The selected MLX model did not pass setup."
        } else if installedModels.isEmpty {
            state = .modelMissing
            detail = "No compatible MLX model was found automatically. Choose a local model folder if you already downloaded one elsewhere."
        } else {
            state = .notConfigured
            detail = "Choose an installed model and run setup before enabling local MLX chat or image-aware actions."
        }

        return MLXVisionSetupSnapshot(
            runtimeURL: runtimeURL,
            textRuntimeURL: textRuntimeURL,
            installedModels: installedModels,
            recommendedModel: recommendedModel,
            selectedModel: selectedModel,
            setupState: state,
            setupDetail: detail
        )
    }

    nonisolated func mlxGenerateExecutableURL() -> URL? {
        let candidates = pathCandidates(named: "mlx_vlm.generate") + userPythonBinCandidates(named: "mlx_vlm.generate") + [
            "/opt/homebrew/bin/mlx_vlm.generate",
            "/usr/local/bin/mlx_vlm.generate"
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    nonisolated func mlxTextGenerateExecutableURL() -> URL? {
        let candidates = pathCandidates(named: "mlx_lm.generate") + userPythonBinCandidates(named: "mlx_lm.generate") + [
            "/opt/homebrew/bin/mlx_lm.generate",
            "/usr/local/bin/mlx_lm.generate"
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    nonisolated func mlxTextServerExecutableURL() -> URL? {
        let candidates = pathCandidates(named: "mlx_lm.server") + userPythonBinCandidates(named: "mlx_lm.server") + [
            "/opt/homebrew/bin/mlx_lm.server",
            "/usr/local/bin/mlx_lm.server"
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    nonisolated func compatibleCachedModelURL() -> URL? {
        cachedModels().first { $0.isVisionCompatible }?.localURL
    }

    nonisolated func cachedModels() -> [MLXVisionModel] {
        let preferredURL = MLXVisionModelStore.defaultCacheURL(
            for: MLXVisionSetupConstants.preferredModelRepositoryID,
            homeDirectory: homeDirectory
        )
        let hubDirectory = preferredURL.deletingLastPathComponent()

        guard let contents = try? fileManager.contentsOfDirectory(
            at: hubDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { isCacheModelDirectory($0) }
            .map { model(forCachedDirectory: $0) }
            .sorted { lhs, rhs in
                if lhs.isPreferred != rhs.isPreferred {
                    return lhs.isPreferred
                }
                if lhs.isVisionCompatible != rhs.isVisionCompatible {
                    return lhs.isVisionCompatible
                }
                return lhs.repositoryID.localizedCaseInsensitiveCompare(rhs.repositoryID) == .orderedAscending
            }
    }

    nonisolated func hasUsableVisionSnapshot(in modelURL: URL) -> Bool {
        usableVisionSnapshotURL(in: modelURL) != nil
    }

    nonisolated func modelCapability(in modelURL: URL) -> MLXModelCapability {
        let hasText = usableTextSnapshotURL(in: modelURL) != nil
        let hasVision = usableVisionSnapshotURL(in: modelURL) != nil

        switch (hasText, hasVision) {
        case (true, true):
            return .textAndVision
        case (true, false):
            return .text
        case (false, true):
            return .vision
        case (false, false):
            return .unsupported
        }
    }

    nonisolated func usableTextSnapshotURL(in modelURL: URL) -> URL? {
        if isUsableTextModelDirectory(modelURL) {
            return modelURL
        }

        let snapshotsURL = modelURL.appendingPathComponent("snapshots")
        guard let snapshots = try? fileManager.contentsOfDirectory(
            at: snapshotsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return snapshots.first { snapshotURL in
            isUsableTextModelDirectory(snapshotURL)
        }
    }

    nonisolated func usableVisionSnapshotURL(in modelURL: URL) -> URL? {
        if isUsableVisionModelDirectory(modelURL) {
            return modelURL
        }

        let snapshotsURL = modelURL.appendingPathComponent("snapshots")
        guard let snapshots = try? fileManager.contentsOfDirectory(
            at: snapshotsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return snapshots.first { snapshotURL in
            isUsableVisionModelDirectory(snapshotURL)
        }
    }

    private nonisolated func recommendedModel(installedModels: [MLXVisionModel]) -> MLXVisionModel {
        installedModels.first { $0.repositoryID == MLXVisionSetupConstants.preferredModelRepositoryID }
            ?? MLXVisionModel(
                repositoryID: MLXVisionSetupConstants.preferredModelRepositoryID,
                localURL: fileManager.fileExists(
                    atPath: MLXVisionModelStore.defaultCacheURL(
                        for: MLXVisionSetupConstants.preferredModelRepositoryID,
                        homeDirectory: homeDirectory
                    ).path
                )
                    ? MLXVisionModelStore.defaultCacheURL(
                        for: MLXVisionSetupConstants.preferredModelRepositoryID,
                        homeDirectory: homeDirectory
                    )
                    : nil,
                approximateDiskSize: MLXVisionSetupConstants.preferredModelApproximateDiskSize,
                license: MLXVisionSetupConstants.preferredModelLicense,
                isPreferred: true,
                capability: .textAndVision
            )
    }

    private nonisolated func selectedModel(from installedModels: [MLXVisionModel]) -> MLXVisionModel? {
        guard let selection = store.selectedModel else { return nil }
        let selectedURL = URL(fileURLWithPath: selection.localPath)
        guard fileManager.fileExists(atPath: selectedURL.path) else { return nil }

        return installedModels.first { $0.repositoryID == selection.repositoryID }
            ?? MLXVisionModel(
                repositoryID: selection.repositoryID,
                localURL: selectedURL,
                approximateDiskSize: formattedDirectorySize(selectedURL) ?? "Size unknown",
                license: "See model card",
                isPreferred: selection.repositoryID == MLXVisionSetupConstants.preferredModelRepositoryID,
                capability: modelCapability(in: selectedURL)
            )
    }

    private nonisolated func model(forCachedDirectory url: URL) -> MLXVisionModel {
        let repositoryID = repositoryID(forCacheDirectoryName: url.lastPathComponent)
        let capability = modelCapability(in: url)
        return MLXVisionModel(
            repositoryID: repositoryID,
            localURL: url,
            approximateDiskSize: formattedDirectorySize(url) ?? "Size unknown",
            license: repositoryID == MLXVisionSetupConstants.preferredModelRepositoryID
                ? MLXVisionSetupConstants.preferredModelLicense
                : "See model card",
            isPreferred: repositoryID == MLXVisionSetupConstants.preferredModelRepositoryID,
            capability: capability
        )
    }

    /// The model vision captures use: the strongest installed vision-capable
    /// model, ranked by parameter count. There is no user-facing "default
    /// model" concept — text routing is the router's job and vision follows
    /// this deterministic policy.
    nonisolated func bestInstalledVisionModel() -> MLXVisionModel? {
        cachedModels()
            .filter { $0.isInstalled && $0.isVisionCompatible }
            .max { lhs, rhs in
                (AgentModelRouter.parameterCountHint(fromModelID: lhs.repositoryID) ?? 0)
                    < (AgentModelRouter.parameterCountHint(fromModelID: rhs.repositoryID) ?? 0)
            }
    }

    /// Measured on-disk size of an installed model directory (allocated
    /// bytes, symlinks not followed so HF cache blobs count once).
    private nonisolated func formattedDirectorySize(_ url: URL) -> String? {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [],
            errorHandler: nil
        ) else {
            return nil
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard total > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    private nonisolated func isCacheModelDirectory(_ url: URL) -> Bool {
        isDirectory(url) && url.lastPathComponent.hasPrefix("models--")
    }

    private nonisolated func isUsableVisionModelDirectory(_ url: URL) -> Bool {
        guard isUsableTextModelDirectory(url) else { return false }

        let configURL = url.appendingPathComponent("config.json")
        let processorURL = url.appendingPathComponent("processor_config.json")
        let preprocessorURL = url.appendingPathComponent("preprocessor_config.json")

        let metadata = [
            contentsOfTextFile(at: configURL),
            contentsOfTextFile(at: processorURL),
            contentsOfTextFile(at: preprocessorURL)
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        .lowercased()

        let visionMarkers = [
            "\"image_token_id\"",
            "\"vision_config\"",
            "\"image_processor_type\"",
            "\"processor_class\"",
            "vlprocessor",
            "vision",
            "llava",
            "pixtral",
            "internvl",
            "molmo",
            "idefics",
            "paligemma"
        ]

        return visionMarkers.contains { metadata.contains($0) }
    }

    private nonisolated func isUsableTextModelDirectory(_ url: URL) -> Bool {
        guard isDirectory(url) else { return false }

        let configURL = url.appendingPathComponent("config.json")
        guard fileManager.fileExists(atPath: configURL.path) else { return false }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        let hasIndexedWeights = fileManager.fileExists(atPath: url.appendingPathComponent("model.safetensors.index.json").path)
        let hasSafetensors = contents.contains { $0.pathExtension == "safetensors" }
        let hasTokenizer = fileManager.fileExists(atPath: url.appendingPathComponent("tokenizer.json").path)
            || fileManager.fileExists(atPath: url.appendingPathComponent("tokenizer_config.json").path)

        return hasTokenizer && (hasIndexedWeights || hasSafetensors)
    }

    private nonisolated func contentsOfTextFile(at url: URL) -> String? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private nonisolated func repositoryID(forCacheDirectoryName name: String) -> String {
        let trimmed = name.replacingOccurrences(of: "models--", with: "")
        let parts = trimmed.components(separatedBy: "--")
        guard parts.count >= 2 else { return trimmed }
        return parts[0] + "/" + parts.dropFirst().joined(separator: "--")
    }

    private nonisolated func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private nonisolated func pathCandidates(named executableName: String) -> [String] {
        let path = environment["PATH"] ?? ""
        return path
            .split(separator: ":")
            .map(String.init)
            .map { URL(fileURLWithPath: $0).appendingPathComponent(executableName).path }
    }

    private nonisolated func userPythonBinCandidates(named executableName: String) -> [String] {
        let pythonDirectory = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Python")

        guard let versions = try? fileManager.contentsOfDirectory(
            at: pythonDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return versions
            .filter { isDirectory($0) }
            .map { $0.appendingPathComponent("bin").appendingPathComponent(executableName).path }
    }
}
