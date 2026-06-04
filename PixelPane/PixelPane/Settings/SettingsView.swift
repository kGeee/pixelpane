import AppKit
import SwiftUI

private let noMLXModelSelectionID = "__pixelpane_no_mlx_model__"

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedMLXModelID: String?

    var body: some View {
        TabView {
            captureSettings
                .tabItem {
                    Label("Capture", systemImage: "viewfinder")
                }

            permissionsSettings
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }

            localAISettings
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            localFilesSettings
                .tabItem {
                    Label("Files", systemImage: "folder")
                }

            chatHistorySettings
                .tabItem {
                    Label("History", systemImage: "clock")
                }
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .onAppear {
            appState.refreshSystemStatus()
            appState.refreshLocalAIStatus()
            selectedMLXModelID = appState.mlxVisionSetupSnapshot.selectedModel?.id
                ?? noMLXModelSelectionID
        }
        .background(SettingsWindowAccessor())
        .onChange(of: appState.mlxVisionSetupSnapshot.installedModels) { _, installedModels in
            if selectedMLXModelID != noMLXModelSelectionID,
               selectedMLXModelID == nil || selectedMLXModel == nil {
                selectedMLXModelID = appState.mlxVisionSetupSnapshot.selectedModel?.id
                    ?? installedModels.first?.id
                    ?? appState.mlxVisionSetupSnapshot.recommendedModel.id
            }
        }
        .onChange(of: appState.mlxVisionSetupSnapshot.selectedModel?.id) { _, selectedID in
            selectedMLXModelID = selectedID ?? noMLXModelSelectionID
        }
    }

    private var captureSettings: some View {
        Form {
            Section("Capture") {
                LabeledContent("Default shortcut", value: "Command + Shift + Space")
                LabeledContent("Hotkey") {
                    StatusPill(
                        title: appState.hotkeyRegistrationStatus.label,
                        systemImage: hotkeyStatusImage,
                        tint: hotkeyStatusTint
                    )
                }

                HStack {
                    Button {
                        appState.startCapture()
                    } label: {
                        Label("Start Capture", systemImage: "viewfinder")
                    }

                    Button(appState.isHotkeyPaused ? "Resume Hotkey" : "Pause Hotkey") {
                        appState.togglePauseHotkey()
                    }
                    .disabled(!appState.canTogglePauseHotkey)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var permissionsSettings: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    StatusPill(
                        title: appState.screenRecordingStatus.label,
                        systemImage: appState.screenRecordingStatus.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: appState.screenRecordingStatus.isGranted ? .green : .orange
                    )
                }

                Text(appState.screenRecordingStatus.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(appState.screenRecordingStatus.recoverySteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .trailing)

                            Text(step)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    Button {
                        appState.requestScreenRecordingAccess()
                    } label: {
                        Label("Request Access", systemImage: "lock.open")
                    }
                    .disabled(appState.screenRecordingStatus.isGranted)

                    Button {
                        appState.openScreenRecordingSettings()
                    } label: {
                        Label("Open Settings", systemImage: "gearshape")
                    }

                    Button {
                        appState.refreshSystemStatus()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }

            LocationPermissionSection(provider: appState.locationProvider)

            Section("Privacy Introduction") {
                Text("Show the first-run privacy introduction again without changing captures, chats, or model settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    appState.resetPrivacyOnboardingForQA()
                } label: {
                    Label("View Privacy Introduction Again", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var localAISettings: some View {
        Form {
            routingModeSection

            modelRouterSection
        }
        .formStyle(.grouped)
    }

    private static let autoRoutingSelectionID = "__pixelpane_auto_routing__"

    private var installedTextModels: [MLXVisionModel] {
        appState.mlxVisionSetupSnapshot.installedModels.filter { $0.isTextCompatible && $0.isInstalled }
    }

    /// Models shown in the router list: all installed models under automatic
    /// routing, or just the pinned one when the user pinned a model. Falls back
    /// to the full list if the pinned model is no longer installed.
    private var routerListModels: [MLXVisionModel] {
        guard let pinnedID = appState.aiRoutingSettings.pinnedLocalModelID else {
            return installedTextModels
        }
        let pinned = installedTextModels.filter { $0.repositoryID == pinnedID }
        return pinned.isEmpty ? installedTextModels : pinned
    }

    /// Binds the model picker: the sentinel means automatic routing; any other value
    /// pins Local mode to that installed model.
    private var pinnedModelBinding: Binding<String> {
        Binding(
            get: { appState.aiRoutingSettings.pinnedLocalModelID ?? Self.autoRoutingSelectionID },
            set: { appState.setPinnedLocalModel($0 == Self.autoRoutingSelectionID ? nil : $0) }
        )
    }

    @ViewBuilder
    private var modelRouterSection: some View {
        if appState.aiRoutingSettings.effectiveMode == .cloud {
            // Cloud Mode is an explicit single route: no routing, no local model list.
            Section("Cloud Model") {
                localAISectionContent
            }
        } else {
            Section("Model Router") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Automatic model routing", systemImage: "arrow.triangle.branch")
                        .font(.headline)
                    Text("In Local mode, Pixel Pane picks the strongest agent-ready on-device model for each request — or always uses one specific model if you choose it below. Check a model to measure its agent-tool readiness. Cloud Mode (above) bypasses routing and uses Pixel Pane Cloud directly.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                Picker("Model", selection: pinnedModelBinding) {
                    Text("Automatic (recommended)").tag(Self.autoRoutingSelectionID)
                    ForEach(installedTextModels) { model in
                        Text(model.repositoryID).tag(model.repositoryID)
                    }
                }
                .help("Automatic lets the router pick the strongest agent-ready model per request; choosing a model always uses that one.")

                if installedTextModels.isEmpty {
                    Text("No local models detected. Download an MLX text model so the router has something to route to.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(routerListModels) { model in
                        ModelRouterRow(
                            model: model,
                            tier: appState.agentReadinessTier(for: model),
                            isChecking: appState.isRunningAgentModelConformanceCheck
                        ) {
                            appState.checkAgentReadiness(for: model)
                        }
                    }
                }

                DisclosureGroup("Advanced · base model setup") {
                    localAISectionContent
                }
            }
        }
    }

    @ViewBuilder
    private var localAISectionContent: some View {
        if appState.aiRoutingSettings.effectiveMode == .cloud && hasActiveMLXModel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Cloud Mode is active", systemImage: "cloud")
                    .font(.headline)
                    .foregroundStyle(.blue)

                Text("Local model setup is hidden while Pixel Pane routes AI through Cloud.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    appState.setAIRoutingMode(.local)
                } label: {
                    Label("Switch to Local", systemImage: "lock.shield")
                }
                .disabled(!hasActiveMLXModel)
                .help(hasActiveMLXModel ? "Route AI through the selected local MLX model." : "Select and validate an MLX model before using Local.")
            }
            .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    LocalAIStatusTile(
                        title: "Text",
                        detail: compactCapabilityLabel(appState.localAICapabilities.text),
                        systemImage: appState.localAICapabilities.text.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: appState.localAICapabilities.text.isAvailable ? .green : .orange
                    )

                    LocalAIStatusTile(
                        title: "Vision",
                        detail: compactCapabilityLabel(appState.localAICapabilities.image),
                        systemImage: appState.localAICapabilities.image.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: appState.localAICapabilities.image.isAvailable ? .green : .orange
                    )

                    LocalAIStatusTile(
                        title: "Agent Tools",
                        detail: agentToolsStatus.detail,
                        systemImage: agentToolsStatus.systemImage,
                        tint: agentToolsStatus.tint
                    )
                }

                Text(mlxSetupDetailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            Picker("Model", selection: selectedModelBinding) {
                Text("No MLX model selected")
                    .tag(noMLXModelSelectionID)
                ForEach(mlxModelChoices) { model in
                    Text(model.displayName).tag(model.id)
                }
            }

            HStack(spacing: 8) {
                Button {
                    applySelectedMLXModel()
                } label: {
                    Label(primaryMLXActionTitle, systemImage: "checkmark.shield")
                }
                .disabled(!canApplySelectedMLXModel)
                .help(primaryMLXActionHelp)

                Button {
                    appState.chooseMLXModelFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder")
                }
                .disabled(appState.isRunningMLXSetupCheck)

                if appState.isRunningMLXSetupCheck {
                    Button {
                        appState.cancelMLXSetupCheck()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                }

                Menu {
                    Button {
                        appState.refreshLocalAIStatus()
                    } label: {
                        Label("Refresh Status", systemImage: "arrow.clockwise")
                    }

                    Button {
                        copyFullMLXSetupCommand()
                    } label: {
                        Label("Copy Setup Command", systemImage: "doc.on.doc")
                    }

                    Button {
                        appState.openRecommendedMLXModelPage()
                    } label: {
                        Label("Open Recommended Model", systemImage: "safari")
                    }

                    Divider()

                    Button(role: .destructive) {
                        clearSelectedMLXModel()
                    } label: {
                        Label("Clear Selection", systemImage: "xmark.circle")
                    }
                    .disabled(selectedMLXModelID == noMLXModelSelectionID && appState.mlxVisionSetupSnapshot.selectedModel == nil)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(appState.isRunningMLXSetupCheck)
            }

            DisclosureGroup("Details") {
                Text(runtimePathText.isEmpty ? "No MLX command-line tools found yet." : runtimePathText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let model = selectedMLXModel {
                    MLXModelDetailView(model: model)
                } else {
                    MLXModelDetailView(model: appState.mlxVisionSetupSnapshot.recommendedModel)
                }

                Text(agentToolsDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var localFilesSettings: some View {
        LocalFilesSettingsView(store: appState.localFileAccess)
    }

    private var chatHistorySettings: some View {
        ChatHistorySettingsView()
    }

    private var routingModeSection: some View {
        Section("AI Mode") {
            Picker(
                "Mode",
                selection: Binding(
                    get: { appState.aiRoutingSettings.effectiveMode },
                    set: { mode in
                        if mode == .local && !hasActiveMLXModel {
                            appState.setAIRoutingMode(.cloud)
                        } else {
                            appState.setAIRoutingMode(mode)
                        }
                    }
                )
            ) {
                Label("Local", systemImage: "lock.shield")
                    .tag(AIRoutingMode.local)
                    .disabled(!hasActiveMLXModel)
                Label("Cloud", systemImage: "cloud").tag(AIRoutingMode.cloud)
            }
            .pickerStyle(.segmented)

            LabeledContent("Current routing") {
                StatusPill(
                    title: appState.aiRoutingSettings.statusLabel,
                    systemImage: appState.aiRoutingSettings.effectiveMode == .local ? "lock.shield" : "cloud",
                    tint: appState.aiRoutingSettings.effectiveMode == .local ? .green : .blue
                )
            }

            Text(appState.aiRoutingSettings.detail)
                .font(.callout)
                .foregroundStyle(.secondary)

            if appState.aiRoutingSettings.effectiveMode == .cloud {
                Toggle(
                    "Share approximate location with Cloud",
                    isOn: Binding(
                        get: { appState.aiRoutingSettings.allowCloudLocationContext },
                        set: { appState.setAllowCloudLocationContext($0) }
                    )
                )
                Text("City-level only, never precise coordinates. Lets Cloud answer location-aware questions like weather or sunrise. Requires Location permission (see Permissions).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !hasActiveMLXModel {
                Text("Choose and validate an MLX model before using Local.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hasActiveMLXModel: Bool {
        appState.mlxVisionSetupSnapshot.selectedModel != nil
    }

    private var mlxModelChoices: [MLXVisionModel] {
        var choices = appState.mlxVisionSetupSnapshot.installedModels
        if let selectedModel = appState.mlxVisionSetupSnapshot.selectedModel,
           !choices.contains(where: { $0.id == selectedModel.id }) {
            choices.insert(selectedModel, at: 0)
        }
        if !choices.contains(where: { $0.id == appState.mlxVisionSetupSnapshot.recommendedModel.id }) {
            choices.append(appState.mlxVisionSetupSnapshot.recommendedModel)
        }
        return choices
    }

    private var selectedMLXModel: MLXVisionModel? {
        guard let selectedID = selectedMLXModelID, selectedID != noMLXModelSelectionID else {
            return nil
        }
        return mlxModelChoices.first { $0.id == selectedID }
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { selectedMLXModelID ?? noMLXModelSelectionID },
            set: { selectionID in
                if selectionID == noMLXModelSelectionID {
                    clearSelectedMLXModel()
                } else {
                    selectedMLXModelID = selectionID
                }
            }
        )
    }

    private var hasStagedMLXModelSelection: Bool {
        guard let selectedMLXModel else { return false }
        return selectedMLXModel.id != appState.mlxVisionSetupSnapshot.selectedModel?.id
    }

    private var mlxSetupDetailText: String {
        if selectedMLXModelID == noMLXModelSelectionID {
            return "No MLX model selected. Pixel Pane will stay in Cloud Mode until you validate a local model."
        }

        guard hasStagedMLXModelSelection, let model = selectedMLXModel else {
            return appState.mlxVisionSetupSnapshot.setupDetail
        }

        return "Selected \(model.repositoryID) for \(model.capability.displayName). Use this model to make it active."
    }

    private var runtimePathText: String {
        [
            appState.mlxVisionSetupSnapshot.textRuntimeURL.map { "Text runtime: \($0.path)" },
            appState.mlxVisionSetupSnapshot.runtimeURL.map { "Vision runtime: \($0.path)" }
        ]
        .compactMap { $0 }
            .joined(separator: "\n")
    }

    private var agentToolsStatus: (detail: String, systemImage: String, tint: Color) {
        if appState.isRunningAgentModelConformanceCheck {
            return ("Checking", "hourglass", .blue)
        }
        guard appState.localAICapabilities.text.isAvailable else {
            return ("Unavailable", "exclamationmark.triangle.fill", .orange)
        }
        guard let profile = appState.agentModelConformanceProfile else {
            return ("Plain chat", "text.bubble", .secondary)
        }
        switch profile.derivedTier {
        case .tierA:
            return ("Full agent", "checkmark.circle.fill", .green)
        case .tierB:
            return ("Tools ready", "checkmark.circle.fill", .green)
        case .tierC:
            return ("Plain chat", "text.bubble", .secondary)
        case .unavailable:
            return ("Probe failed", "exclamationmark.triangle.fill", .orange)
        }
    }

    private var agentToolsDetailText: String {
        guard let profile = appState.agentModelConformanceProfile else {
            return "Agent Tools: not checked for the active text model. Local MLX chat stays available, but agent tools remain disabled until the model passes conformance."
        }
        let tested = ISO8601DateFormatter().string(from: profile.testedAt)
        return """
        Agent Tools: \(profile.derivedTier.rawValue), tested \(tested)
        Plain: \(profile.plainChat.status.rawValue); JSON: \(profile.structuredJSON.status.rawValue); Tool: \(profile.toolCall.status.rawValue); Follow-up: \(profile.toolResultFollowUp.status.rawValue)
        """
    }

    private func applySelectedMLXModel() {
        guard let model = selectedMLXModel, model.isInstalled else {
            appState.refreshLocalAIStatus()
            return
        }
        appState.runMLXSetupCheck(for: model)
    }

    private var canApplySelectedMLXModel: Bool {
        guard let model = selectedMLXModel else { return false }
        return model.isInstalled && !appState.isRunningMLXSetupCheck
    }

    private var primaryMLXActionTitle: String {
        if selectedMLXModel == nil {
            return "Use Model"
        }
        if appState.isRunningMLXSetupCheck {
            return "Checking"
        }
        return hasStagedMLXModelSelection ? "Use Model" : "Recheck"
    }

    private var primaryMLXActionHelp: String {
        guard let model = selectedMLXModel else {
            return "Select an installed MLX model first."
        }
        if !model.isInstalled {
            return "Download this model or choose a local folder first."
        }
        if model.capability == .unsupported {
            return "This model is visible for clarity, but Pixel Pane cannot use it for local MLX chat or vision."
        }
        return "Validate this model and make it the active local MLX model."
    }

    private func compactCapabilityLabel(_ status: AIBackendCapabilityStatus) -> String {
        switch status {
        case .available(.appleFoundationModels):
            return "Apple ready"
        case .available(.mlxText):
            return "MLX ready"
        case .available(.mlxVision):
            return "MLX ready"
        case .available(.pixelPaneCloud):
            return "Cloud ready"
        case .installing(_, let detail):
            return detail
        case .unavailable(let reason):
            return reason.label
        }
    }

    private func copyFullMLXSetupCommand() {
        let model = selectedMLXModel ?? appState.mlxVisionSetupSnapshot.recommendedModel
        copyInstallCommand(
            [
                "python3 -m pip install -U mlx-lm mlx-vlm huggingface_hub",
                model.installCommand
            ]
            .joined(separator: "\n")
        )
    }

    private func clearSelectedMLXModel() {
        selectedMLXModelID = noMLXModelSelectionID
        appState.clearMLXModelSelection()
    }

    private func copyInstallCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    private var hotkeyStatusImage: String {
        switch appState.hotkeyRegistrationStatus {
        case .notRegistered:
            "minus.circle.fill"
        case .registered:
            "checkmark.circle.fill"
        case .paused:
            "pause.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var hotkeyStatusTint: Color {
        switch appState.hotkeyRegistrationStatus {
        case .notRegistered:
            .secondary
        case .registered:
            .green
        case .paused:
            .yellow
        case .failed:
            .orange
        }
    }
}

private struct ModelRouterRow: View {
    let model: MLXVisionModel
    let tier: AgentModelConformanceDerivedTier?
    let isChecking: Bool
    let onCheck: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.repositoryID)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.approximateDiskSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            readinessBadge
            Button("Check", action: onCheck)
                .disabled(isChecking)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var readinessBadge: some View {
        switch tier {
        case .tierA, .tierB:
            Label("Agent-ready", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .tierC:
            Label("Chat only", systemImage: "bubble.left")
                .font(.caption)
                .foregroundStyle(.orange)
        case .unavailable:
            Label("Check failed", systemImage: "xmark.seal")
                .font(.caption)
                .foregroundStyle(.red)
        case .none:
            Label("Not checked", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(tint)
    }
}

private struct LocalAIStatusTile: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(detail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LocalFilesSettingsView: View {
    @ObservedObject var store: LocalFileAccessStore

    var body: some View {
        Form {
            Section("Local File Access") {
                Text("Pixel Pane can read and search only the files and folders you grant here. Terminal commands run only from granted folders, and risky commands require explicit confirmation before they run.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        store.grantFolder()
                    } label: {
                        Label("Grant Folder", systemImage: "folder.badge.plus")
                    }

                    Button {
                        store.grantFile()
                    } label: {
                        Label("Grant File", systemImage: "doc.badge.plus")
                    }
                }

                if store.grants.isEmpty {
                    Text("No local file access granted yet.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }

            if !store.grants.isEmpty {
                Section("Granted Locations") {
                    ForEach(store.grants) { grant in
                        HStack(spacing: 10) {
                            Image(systemName: grant.isDirectory ? "folder" : "doc.text")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(grant.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                Text("\(grant.kindLabel): \(grant.path)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Button {
                                store.removeGrant(grant)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove access")
                        }
                    }
                }
            }

            Section("Privacy") {
                Text("In Local mode, file snippets, confirmed file writes, and terminal output stay on this Mac. In Cloud mode, relevant snippets may be sent to Pixel Pane Cloud because you selected cloud routing; file writes and terminal commands still run locally only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Observes the location provider directly so permission and resolved-city
/// changes update the row without routing through AppState.
private struct LocationPermissionSection: View {
    @ObservedObject var provider: LocationContextProvider

    var body: some View {
        Section("Location") {
            LabeledContent("Location") {
                StatusPill(
                    title: provider.permissionStatus.label,
                    systemImage: provider.permissionStatus.isGranted ? "checkmark.circle.fill" : "location.slash",
                    tint: provider.permissionStatus.isGranted ? .green : .orange
                )
            }

            Text(provider.permissionStatus.detail)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let location = provider.approximateLocation {
                LabeledContent("Approximate location", value: location.displayLabel)
            }

            HStack {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }

                Button {
                    provider.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

/// Backed by the durable agent run store — the single place chats persist.
private struct ChatHistorySettingsView: View {
    @State private var viewModel: AgentRunViewModel?
    @State private var summaries: [AgentRunSessionSummary] = []
    @State private var didLoad = false

    var body: some View {
        Form {
            Section("Local Chat History") {
                Text("Pixel Pane stores chat text locally on this Mac. Screenshots are not saved in history; capture chats keep only their transcript.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    LabeledContent("Saved chats", value: didLoad ? "\(summaries.count)" : "…")

                    Spacer()

                    Button(role: .destructive) {
                        Task {
                            try? await viewModel?.clearHistory()
                            await reload()
                        }
                    } label: {
                        Label("Clear Chat History", systemImage: "trash")
                    }
                    .disabled(summaries.isEmpty)
                }
            }

            if !summaries.isEmpty {
                Section("Recent") {
                    ForEach(summaries.prefix(12)) { session in
                        HStack(spacing: 10) {
                            Image(systemName: contextDisplay(session).icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayTitle(session))
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Text("\(contextDisplay(session).name) - \(session.userMessageCount) message\(session.userMessageCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                Task {
                                    try? await viewModel?.deleteSession(sessionID: session.id)
                                    await reload()
                                }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete chat")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            if viewModel == nil {
                viewModel = AgentRunViewModel.makeDefault()
            }
            await reload()
        }
    }

    private func reload() async {
        summaries = await viewModel?.sessionSummaries() ?? []
        didLoad = true
    }

    private func displayTitle(_ session: AgentRunSessionSummary) -> String {
        let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? contextDisplay(session).name : trimmed
    }

    private func contextDisplay(_ session: AgentRunSessionSummary) -> (name: String, icon: String) {
        if let kind = session.contextKind.flatMap(ChatSessionContextKind.init(rawValue:)) {
            return (kind.displayName, kind == .capture ? "viewfinder" : "bubble.left.and.bubble.right")
        }
        return (ChatSessionContextKind.assistant.displayName, "bubble.left.and.bubble.right")
    }
}

enum SettingsWindowActivation {
    static let notification = Notification.Name("PixelPaneBringSettingsWindowForward")

    @MainActor
    static func request() {
        NSApp.activate()
        NotificationCenter.default.post(name: notification, object: nil)
        DispatchQueue.main.async {
            NSApp.activate()
            NotificationCenter.default.post(name: notification, object: nil)
        }
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.captureWindow(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.captureWindow(from: nsView)
        }
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var observer: NSObjectProtocol?

        init() {
            observer = NotificationCenter.default.addObserver(
                forName: SettingsWindowActivation.notification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.bringForward()
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func captureWindow(from view: NSView) {
            window = view.window
            bringForward()
        }

        private func bringForward() {
            guard let window else { return }
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}

private struct MLXModelDetailView: View {
    let model: MLXVisionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Source repo", value: model.repositoryID)
            LabeledContent("Disk size", value: model.approximateDiskSize)
            LabeledContent("License", value: model.license)
            LabeledContent("Capability", value: model.capability.displayName)
            LabeledContent("Destination", value: model.destinationPath)
            LabeledContent("Hardware note", value: "Large local models need substantial unified memory and free disk space.")

            if model.isInstalled && model.capability == .text {
                Text("This text-only model can power local chat, but it cannot inspect screenshots directly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if model.isInstalled && model.capability == .unsupported {
                Text("This model is downloaded, but Pixel Pane could not identify usable MLX text or vision metadata.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if !model.isInstalled {
                Text("This model is not installed at the expected cache path yet.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .font(.callout)
    }
}
