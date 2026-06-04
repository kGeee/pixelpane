import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var lastResult: CaptureResult?
    @Published private(set) var screenRecordingStatus: ScreenRecordingPermissionStatus = .notGranted
    @Published private(set) var hotkeyRegistrationStatus: HotkeyRegistrationStatus = .notRegistered
    @Published private(set) var localAICapabilities: AIBackendCapabilities = .unknown
    @Published private(set) var mlxVisionSetupSnapshot = MLXVisionSetupRunner().snapshot()
    @Published private(set) var isRunningMLXSetupCheck = false
    @Published private(set) var isRunningAgentModelConformanceCheck = false
    @Published private(set) var agentModelConformanceProfile: AgentModelConformanceProfile?
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var hasCompletedFirstCaptureTutorial: Bool
    @Published private(set) var aiRoutingSettings: AIRoutingSettings
    let localFileAccess: LocalFileAccessStore
    let locationProvider = LocationContextProvider()

    private lazy var overlayCoordinator = OverlayCoordinator()
    private lazy var panelController = ResultPanelController()
    private lazy var onboardingController = OnboardingWindowController()
    private let permissionManager = SystemPermissionManager()
    private let screenCapturer = ScreenCapturer()
    private let ocrEngine = OCREngine()
    private let languageDetector = LanguageDetector()
    private let technicalContentClassifier = TechnicalContentClassifier()
    private let hotkeyManager = HotkeyManager()
    private let mlxVisionSetupRunner = MLXVisionSetupRunner()
    private let mlxRuntimeDetector = MLXVisionRuntimeDetector()
    private let agentModelConformanceStore: AgentModelConformanceStore
    private let localAIBackend: any AIBackend = HybridLocalAIBackend()
    private let userDefaults: UserDefaults
    private var mlxSetupCheckTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private let onboardingCompletedKey = "PrivacyOnboarding.Completed"
    private let firstCaptureTutorialCompletedKey = "FirstCaptureTutorial.Completed"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        agentModelConformanceStore = AgentModelConformanceStore(defaults: userDefaults)
        localFileAccess = LocalFileAccessStore(userDefaults: userDefaults)
        hasCompletedOnboarding = userDefaults.bool(forKey: onboardingCompletedKey)
        hasCompletedFirstCaptureTutorial = userDefaults.bool(forKey: firstCaptureTutorialCompletedKey)
        let storedUseCloudModels = userDefaults.bool(forKey: AIRoutingDefaults.useCloudModelsKey)
        let storedAllowCloudImageContext = userDefaults.bool(forKey: AIRoutingDefaults.allowCloudImageContextKey)
        aiRoutingSettings = AIRoutingSettings(
            useCloudModels: storedUseCloudModels,
            allowCloudImageContext: storedUseCloudModels
                ? AIRoutingSettings.cloudBackendAvailable
                : storedAllowCloudImageContext,
            allowCloudLocationContext: userDefaults.bool(forKey: AIRoutingDefaults.allowCloudLocationContextKey),
            pinnedLocalModelID: userDefaults.string(forKey: AIRoutingDefaults.pinnedLocalModelIDKey)
        )
        if mlxVisionSetupSnapshot.selectedModel == nil {
            aiRoutingSettings.useCloudModels = AIRoutingSettings.cloudBackendAvailable
            aiRoutingSettings.allowCloudImageContext = AIRoutingSettings.cloudBackendAvailable
        }
        agentModelConformanceProfile = currentAgentModelConformanceProfile(snapshot: mlxVisionSetupSnapshot)
        persistAIRoutingSettings()
        refreshSystemStatus()
        refreshLocalAIStatus()
        registerGlobalHotkey()
        // The geocoder resolves the city asynchronously; refresh the open
        // panel when it lands so cloud runs pick up the location context.
        locationProvider.$approximateLocation
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshPresentedPanel()
            }
            .store(in: &cancellables)
        if aiRoutingSettings.allowCloudLocationContext {
            locationProvider.refresh()
        }
        Task { @MainActor [weak self] in
            self?.showInitialSurface()
        }
    }

    private func showInitialSurface() {
        if hasCompletedOnboarding {
            showAssistant()
        } else {
            showOnboarding()
        }
    }

    func showOnboarding() {
        onboardingController.show(
            screenRecordingStatus: screenRecordingStatus,
            onStartCapture: { [weak self] in
                self?.completeOnboarding()
                self?.startCapture()
            },
            onOpenAssistant: { [weak self] in
                self?.completeOnboarding()
                self?.showAssistant()
            },
            onRequestScreenRecordingAccess: { [weak self] in
                self?.requestScreenRecordingAccess()
                return self?.screenRecordingStatus ?? .notGranted
            },
            onOpenScreenRecordingSettings: { [weak self] in
                self?.openScreenRecordingSettings()
                return self?.screenRecordingStatus ?? .notGranted
            }
        )
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        userDefaults.set(true, forKey: onboardingCompletedKey)
        onboardingController.close()
    }

    func resetPrivacyOnboardingForQA() {
        hasCompletedOnboarding = false
        userDefaults.removeObject(forKey: onboardingCompletedKey)
        showOnboarding()
    }

    func startCapture() {
        guard !isCapturing else { return }
        refreshSystemStatus()

        guard screenRecordingStatus.isGranted else {
            presentScreenRecordingRecovery()
            return
        }

        isCapturing = true

        overlayCoordinator.beginSelection(
            showFirstUseTip: !hasCompletedFirstCaptureTutorial,
            onComplete: { [weak self] selection in
                Task { @MainActor in
                    await self?.process(selection: selection)
                }
            },
            onCancel: { [weak self] in
                self?.isCapturing = false
            }
        )
    }

    func showLastResult() {
        guard let lastResult else { return }
        panelController.show(
            result: lastResult,
            routingSettings: aiRoutingSettings,
            localAICapabilities: localAICapabilities,
            localFileAccess: localFileAccess,
            approximateLocation: cloudRunLocationContext,
            startsInAssistantMode: true,
            onTryAgain: { [weak self] in
                self?.startCapture()
            }
        )
    }

    func showAssistant() {
        panelController.showAssistant(
            routingSettings: aiRoutingSettings,
            localAICapabilities: localAICapabilities,
            localFileAccess: localFileAccess,
            approximateLocation: cloudRunLocationContext,
            onTryAgain: { [weak self] in
                self?.startCapture()
            }
        )
    }

    func setUseCloudModels(_ isEnabled: Bool) {
        let allowedValue = AIRoutingSettings.cloudBackendAvailable && isEnabled
        aiRoutingSettings.useCloudModels = allowedValue
        aiRoutingSettings.allowCloudImageContext = allowedValue
        persistAIRoutingSettings()
        refreshPresentedPanel()
    }

    func setAIRoutingMode(_ mode: AIRoutingMode) {
        if mode == .local && mlxVisionSetupSnapshot.selectedModel == nil {
            setUseCloudModels(true)
            return
        }
        setUseCloudModels(mode == .cloud)
    }

    func setAllowCloudImageContext(_ isEnabled: Bool) {
        let allowedValue = AIRoutingSettings.cloudBackendAvailable
            && aiRoutingSettings.useCloudModels
            && isEnabled
        aiRoutingSettings.allowCloudImageContext = allowedValue
        persistAIRoutingSettings()
    }

    func refreshSystemStatus() {
        screenRecordingStatus = permissionManager.screenRecordingStatus()
    }

    func refreshLocalAIStatus() {
        Task { [weak self] in
            guard let self else { return }
            let capabilities = await localAIBackend.capabilities()
            let mlxSnapshot = mlxVisionSetupRunner.snapshot()
            let conformanceProfile = currentAgentModelConformanceProfile(snapshot: mlxSnapshot)
            await MainActor.run {
                self.localAICapabilities = capabilities
                self.mlxVisionSetupSnapshot = mlxSnapshot
                self.agentModelConformanceProfile = conformanceProfile
            }
        }
    }

    func runMLXSetupCheck(for model: MLXVisionModel) {
        guard !isRunningMLXSetupCheck else { return }
        isRunningMLXSetupCheck = true
        isRunningAgentModelConformanceCheck = false

        mlxSetupCheckTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await mlxVisionSetupRunner.runSetupCheck(for: model)
            let capabilities = await localAIBackend.capabilities()
            let setupProfile = currentAgentModelConformanceProfile(snapshot: snapshot)
            await MainActor.run {
                self.mlxVisionSetupSnapshot = snapshot
                self.localAICapabilities = capabilities
                self.agentModelConformanceProfile = setupProfile
            }

            var conformanceProfile = setupProfile
            if !Task.isCancelled,
               snapshot.textCapabilityStatus.isAvailable,
               let target = AgentModelConformanceTarget.mlxText(snapshot: snapshot) {
                await MainActor.run {
                    self.isRunningAgentModelConformanceCheck = true
                }
                let profile = await self.runAgentModelConformanceCheck(target: target)
                self.agentModelConformanceStore.save(profile)
                conformanceProfile = profile
            }

            await MainActor.run {
                self.mlxVisionSetupSnapshot = snapshot
                self.localAICapabilities = capabilities
                self.agentModelConformanceProfile = conformanceProfile
                self.isRunningAgentModelConformanceCheck = false
                self.isRunningMLXSetupCheck = false
                self.mlxSetupCheckTask = nil
                Task { await MLXTextServerManager.shared.stop() }
                if snapshot.selectedModel != nil {
                    self.setUseCloudModels(false)
                } else {
                    self.refreshPresentedPanel()
                }
            }
        }
    }

    func chooseMLXModelFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose MLX Vision Model Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !isRunningMLXSetupCheck else { return }
        isRunningMLXSetupCheck = true
        isRunningAgentModelConformanceCheck = false

        mlxSetupCheckTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await mlxVisionSetupRunner.runSetupCheck(forCustomModelDirectory: url)
            let capabilities = await localAIBackend.capabilities()
            let setupProfile = currentAgentModelConformanceProfile(snapshot: snapshot)
            await MainActor.run {
                self.mlxVisionSetupSnapshot = snapshot
                self.localAICapabilities = capabilities
                self.agentModelConformanceProfile = setupProfile
            }

            var conformanceProfile = setupProfile
            if !Task.isCancelled,
               snapshot.textCapabilityStatus.isAvailable,
               let target = AgentModelConformanceTarget.mlxText(snapshot: snapshot) {
                await MainActor.run {
                    self.isRunningAgentModelConformanceCheck = true
                }
                let profile = await self.runAgentModelConformanceCheck(target: target)
                self.agentModelConformanceStore.save(profile)
                conformanceProfile = profile
            }

            await MainActor.run {
                self.mlxVisionSetupSnapshot = snapshot
                self.localAICapabilities = capabilities
                self.agentModelConformanceProfile = conformanceProfile
                self.isRunningAgentModelConformanceCheck = false
                self.isRunningMLXSetupCheck = false
                self.mlxSetupCheckTask = nil
                Task { await MLXTextServerManager.shared.stop() }
                if snapshot.selectedModel != nil {
                    self.setUseCloudModels(false)
                } else {
                    self.refreshPresentedPanel()
                }
            }
        }
    }

    func cancelMLXSetupCheck() {
        mlxSetupCheckTask?.cancel()
        mlxSetupCheckTask = nil
        isRunningMLXSetupCheck = false
        isRunningAgentModelConformanceCheck = false
        Task { await MLXTextServerManager.shared.stop() }
        refreshLocalAIStatus()
    }

    func clearMLXModelSelection() {
        mlxSetupCheckTask?.cancel()
        mlxSetupCheckTask = nil
        let snapshot = mlxVisionSetupRunner.clearSelection()
        mlxVisionSetupSnapshot = snapshot
        agentModelConformanceProfile = nil
        isRunningMLXSetupCheck = false
        isRunningAgentModelConformanceCheck = false
        setUseCloudModels(true)
        Task { await MLXTextServerManager.shared.stop() }
        refreshLocalAIStatus()
    }

    func openRecommendedMLXModelPage() {
        mlxVisionSetupRunner.openRecommendedModelPage()
    }

    func requestScreenRecordingAccess() {
        let granted = permissionManager.requestScreenRecordingAccess()
        refreshSystemStatus()

        if granted {
            panelController.close()
        } else {
            permissionManager.openScreenRecordingSettings()
        }
    }

    func openScreenRecordingSettings() {
        permissionManager.openScreenRecordingSettings()
        refreshSystemStatus()
    }

    func updateHotkeyRegistrationStatus(_ status: HotkeyRegistrationStatus) {
        hotkeyRegistrationStatus = status
    }

    func reportHotkeyRegistrationFailure(_ message: String) {
        hotkeyRegistrationStatus = .failed(message: message)
        panelController.show(
            recovery: .hotkeyRegistration(message: message),
            onPrimaryAction: { [weak self] in
                self?.panelController.close()
            }
        )
    }

    var canTogglePauseHotkey: Bool {
        switch hotkeyRegistrationStatus {
        case .registered, .paused:
            return true
        case .notRegistered, .failed:
            return false
        }
    }

    var isHotkeyPaused: Bool {
        if case .paused = hotkeyRegistrationStatus { return true }
        return false
    }

    func togglePauseHotkey() {
        switch hotkeyRegistrationStatus {
        case .registered(let shortcut):
            hotkeyManager.setPaused(true)
            hotkeyRegistrationStatus = .paused(shortcut: shortcut)
        case .paused(let shortcut):
            hotkeyManager.setPaused(false)
            hotkeyRegistrationStatus = .registered(shortcut: shortcut)
        case .notRegistered, .failed:
            break
        }
    }

    private func registerGlobalHotkey() {
        let result = hotkeyManager.register { [weak self] in
            self?.startCapture()
        }

        switch result {
        case .success(let shortcut):
            updateHotkeyRegistrationStatus(.registered(shortcut: shortcut))
        case .failure(let error):
            reportHotkeyRegistrationFailure(error.description)
        }
    }

    private func process(selection: CaptureSelection) async {
        defer { isCapturing = false }

        do {
            let image = try await screenCapturer.capture(selection: selection)
            let recognizedText = try await ocrEngine.recognizeText(in: image)
            let displayText = recognizedText.isEmpty
                ? "No text found. Try a larger region or higher contrast."
                : recognizedText
            let detectedLanguage = recognizedText.isEmpty
                ? DetectedLanguage.unknown
                : languageDetector.detect(in: recognizedText)
            let technicalClassification = technicalContentClassifier.classify(recognizedText)
            let result = CaptureResult(
                image: image,
                text: displayText,
                isEmptyOCRResult: recognizedText.isEmpty,
                selectionFrame: selection.screenRect,
                createdAt: Date(),
                sourceType: .ocr,
                detectedLanguage: detectedLanguage,
                technicalClassification: technicalClassification
            )
            lastResult = result.withoutCapturedImage
            completeFirstCaptureTutorialIfNeeded()
            panelController.show(
                result: result,
                routingSettings: aiRoutingSettings,
                localAICapabilities: localAICapabilities,
                localFileAccess: localFileAccess,
                approximateLocation: cloudRunLocationContext,
                startsInAssistantMode: true,
                onTryAgain: { [weak self] in
                    self?.startCapture()
                }
            )
        } catch CaptureError.screenRecordingPermissionDenied {
            screenRecordingStatus = .notGranted
            presentScreenRecordingRecovery(near: selection.screenRect)
        } catch {
            let result = CaptureResult(
                image: nil,
                text: error.localizedDescription,
                selectionFrame: selection.screenRect,
                createdAt: Date(),
                sourceType: .ocr,
                detectedLanguage: .unknown
            )
            lastResult = result
            panelController.show(
                result: result,
                routingSettings: aiRoutingSettings,
                localAICapabilities: localAICapabilities,
                localFileAccess: localFileAccess,
                approximateLocation: cloudRunLocationContext,
                startsInAssistantMode: true,
                onTryAgain: { [weak self] in
                    self?.startCapture()
                }
            )
        }
    }

    private func completeFirstCaptureTutorialIfNeeded() {
        guard !hasCompletedFirstCaptureTutorial else { return }
        hasCompletedFirstCaptureTutorial = true
        userDefaults.set(true, forKey: firstCaptureTutorialCompletedKey)
    }

    private func presentScreenRecordingRecovery(near selectionFrame: CGRect? = nil) {
        panelController.show(
            recovery: .screenRecording,
            near: selectionFrame,
            onPrimaryAction: { [weak self] in
                self?.requestScreenRecordingAccess()
            },
            onSecondaryAction: { [weak self] in
                self?.openScreenRecordingSettings()
            }
        )
    }

    private func persistAIRoutingSettings() {
        userDefaults.set(aiRoutingSettings.useCloudModels, forKey: AIRoutingDefaults.useCloudModelsKey)
        userDefaults.set(aiRoutingSettings.allowCloudImageContext, forKey: AIRoutingDefaults.allowCloudImageContextKey)
        userDefaults.set(aiRoutingSettings.allowCloudLocationContext, forKey: AIRoutingDefaults.allowCloudLocationContextKey)
        if let pinned = aiRoutingSettings.pinnedLocalModelID {
            userDefaults.set(pinned, forKey: AIRoutingDefaults.pinnedLocalModelIDKey)
        } else {
            userDefaults.removeObject(forKey: AIRoutingDefaults.pinnedLocalModelIDKey)
        }
    }

    /// Explicit consent for attaching approximate (city-level) location to
    /// Cloud Mode requests. Resolves the location eagerly on enable so the
    /// first location-aware question does not race the geocoder.
    func setAllowCloudLocationContext(_ isEnabled: Bool) {
        aiRoutingSettings.allowCloudLocationContext = isEnabled
        persistAIRoutingSettings()
        if isEnabled {
            locationProvider.requestAccess()
            locationProvider.refresh()
        }
        refreshPresentedPanel()
    }

    /// Location context attached to runs: cloud route only, explicit toggle,
    /// macOS permission granted, and a resolved city available.
    var cloudRunLocationContext: AgentLocationContext? {
        guard aiRoutingSettings.effectiveMode == .cloud,
              aiRoutingSettings.allowCloudLocationContext,
              locationProvider.permissionStatus.isGranted else {
            return nil
        }
        return locationProvider.approximateLocation
    }

    /// Pin Local mode to one installed model (nil restores automatic routing).
    func setPinnedLocalModel(_ repositoryID: String?) {
        aiRoutingSettings.pinnedLocalModelID = repositoryID
        persistAIRoutingSettings()
        refreshPresentedPanel()
    }

    private func runAgentModelConformanceCheck(
        target: AgentModelConformanceTarget
    ) async -> AgentModelConformanceProfile {
        // Probe the model named by the target (not just the stored selection), so any
        // installed model can be checked for agent readiness.
        let override: MLXVisionModelSelection? = target.modelPath.map {
            MLXVisionModelSelection(repositoryID: target.modelID, localPath: $0, smokeTestedAt: Date())
        }
        let backend = MLXTextBackend(
            store: MLXVisionModelStore(defaults: userDefaults),
            modelSelectionOverride: override,
            timeoutSeconds: 45
        )
        let descriptor = AgentKernelModelDescriptor(
            id: target.adapterID,
            providerKind: .mlxLocal,
            route: .local,
            displayName: "MLX Text",
            modelName: target.modelID
        )
        let capabilities = AgentKernelModelAdapterCapabilities.aiBackendBridge(
            descriptor: descriptor,
            backendCapabilities: await backend.capabilities()
        )
        let adapter = AgentKernelMLXNativeToolAdapter(
            descriptor: descriptor,
            backend: backend,
            capabilities: capabilities,
            preferredProvider: .mlxText,
            allowsSingleRepairAttempt: false
        )
        return await AgentModelConformanceRunner(perProbeTimeout: 45).run(
            adapter: adapter,
            target: target
        )
    }

    private func currentAgentModelConformanceProfile(
        snapshot: MLXVisionSetupSnapshot
    ) -> AgentModelConformanceProfile? {
        agentModelConformanceStore.profile(for: AgentModelConformanceTarget.mlxText(snapshot: snapshot))
    }

    // MARK: - Model router readiness (per installed model)

    /// The conformance target for an installed model, built the same way the run path looks it
    /// up so the stored profile key matches.
    private func agentReadinessTarget(for model: MLXVisionModel) -> AgentModelConformanceTarget? {
        guard let url = model.localURL else { return nil }
        let selection = MLXVisionModelSelection(
            repositoryID: model.repositoryID,
            localPath: url.path,
            smokeTestedAt: Date()
        )
        return AgentModelConformanceTarget.mlxText(
            selection: selection,
            textRuntimeURL: mlxRuntimeDetector.mlxTextGenerateExecutableURL()
        )
    }

    /// The router's measured agent-readiness tier for an installed model, or nil if it has not
    /// been checked yet.
    func agentReadinessTier(for model: MLXVisionModel) -> AgentModelConformanceDerivedTier? {
        guard let target = agentReadinessTarget(for: model) else { return nil }
        return agentModelConformanceStore.profile(for: target)?.derivedTier
    }

    /// Run the agent-readiness (conformance) probe for a specific installed model and cache its
    /// tier, without changing which model is otherwise selected. Drives the router's candidate set.
    func checkAgentReadiness(for model: MLXVisionModel) {
        guard !isRunningAgentModelConformanceCheck,
              let target = agentReadinessTarget(for: model) else { return }
        isRunningAgentModelConformanceCheck = true
        Task { [weak self] in
            guard let self else { return }
            let profile = await self.runAgentModelConformanceCheck(target: target)
            self.agentModelConformanceStore.save(profile)
            await MainActor.run {
                self.isRunningAgentModelConformanceCheck = false
                Task { await MLXTextServerManager.shared.stop() }
                self.refreshLocalAIStatus()
            }
        }
    }

    private func refreshPresentedPanel() {
        panelController.refreshRoutingSettings(
            aiRoutingSettings,
            localAICapabilities: localAICapabilities,
            localFileAccess: localFileAccess,
            approximateLocation: cloudRunLocationContext
        )
    }
}
