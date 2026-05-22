import AppKit
import SwiftUI

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
                    Label("Local AI", systemImage: "cpu")
                }

            localFilesSettings
                .tabItem {
                    Label("Files", systemImage: "folder")
                }

            chatHistorySettings
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            aiModeSettings
                .tabItem {
                    Label("AI Mode", systemImage: "switch.2")
                }
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .onAppear {
            appState.refreshSystemStatus()
            appState.refreshLocalAIStatus()
            selectedMLXModelID = appState.mlxVisionSetupSnapshot.selectedModel?.id
                ?? appState.mlxVisionSetupSnapshot.installedModels.first?.id
                ?? appState.mlxVisionSetupSnapshot.recommendedModel.id
        }
        .background(SettingsWindowAccessor())
        .onChange(of: appState.mlxVisionSetupSnapshot.installedModels) { _, installedModels in
            if selectedMLXModelID == nil || selectedMLXModel == nil {
                selectedMLXModelID = appState.mlxVisionSetupSnapshot.selectedModel?.id
                    ?? installedModels.first?.id
                    ?? appState.mlxVisionSetupSnapshot.recommendedModel.id
            }
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
        }
        .formStyle(.grouped)
    }

    private var localAISettings: some View {
        Form {
            routingModeSection

            Section("Response Style") {
                ResponseStyleSlider(
                    level: appState.responseDetailLevel,
                    onChange: { appState.setResponseDetailLevel($0) }
                )
            }

            Section("Local AI") {
                LabeledContent("Text") {
                    StatusPill(
                        title: appState.localAICapabilities.text.label,
                        systemImage: appState.localAICapabilities.text.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: appState.localAICapabilities.text.isAvailable ? .green : .orange
                    )
                }

                LabeledContent("Vision") {
                    StatusPill(
                        title: appState.localAICapabilities.image.label,
                        systemImage: appState.localAICapabilities.image.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: appState.localAICapabilities.image.isAvailable ? .green : .orange
                    )
                }

                Text(appState.mlxVisionSetupSnapshot.setupDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LabeledContent("Runtime") {
                    Text(runtimeStatusText)
                        .foregroundStyle(runtimeStatusTint)
                }

                if !runtimePathText.isEmpty {
                    Text(runtimePathText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !mlxModelChoices.isEmpty {
                    Picker("Model", selection: selectedModelBinding) {
                        ForEach(mlxModelChoices) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }

                    if let model = selectedMLXModel {
                        HStack(spacing: 8) {
                            Button {
                                appState.chooseMLXModelFolder()
                            } label: {
                                Label("Choose Folder", systemImage: "folder")
                            }
                            .disabled(appState.isRunningMLXSetupCheck)

                            Button {
                                appState.runMLXSetupCheck(for: model)
                            } label: {
                                Label("Run Setup Check", systemImage: "checkmark.shield")
                            }
                            .disabled(appState.isRunningMLXSetupCheck || !model.isInstalled)
                            .help(model.capability == .unsupported ? "This model is visible for clarity, but Pixel Pane cannot use it for local MLX chat or vision." : "Validate this MLX model for local chat or vision.")

                            Button {
                                appState.refreshLocalAIStatus()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }

                        HStack(spacing: 8) {
                            Button {
                                appState.openRecommendedMLXModelPage()
                            } label: {
                                Label("Open Model Page", systemImage: "safari")
                            }

                            Button {
                                copyInstallCommand(for: model)
                            } label: {
                                Label("Copy Install Command", systemImage: "doc.on.doc")
                            }

                            Button {
                                appState.clearMLXModelSelection()
                            } label: {
                                Label("Clear Selection", systemImage: "xmark.circle")
                            }
                            .disabled(appState.mlxVisionSetupSnapshot.selectedModel == nil)
                        }

                        DisclosureGroup("Model details") {
                            MLXModelDetailView(model: model)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Button {
                            appState.chooseMLXModelFolder()
                        } label: {
                            Label("Choose Folder", systemImage: "folder")
                        }
                        .disabled(appState.isRunningMLXSetupCheck)

                        Button {
                            appState.openRecommendedMLXModelPage()
                        } label: {
                            Label("Open Model Page", systemImage: "safari")
                        }

                        Button {
                            copyInstallCommand(for: appState.mlxVisionSetupSnapshot.recommendedModel)
                        } label: {
                            Label("Copy Install Command", systemImage: "doc.on.doc")
                        }

                        Button {
                            appState.refreshLocalAIStatus()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }

                    DisclosureGroup("Recommended model") {
                        MLXModelDetailView(model: appState.mlxVisionSetupSnapshot.recommendedModel)
                    }
                }

                Text("Choose any local MLX text or vision model folder, or use a model discovered in the Hugging Face cache. Pixel Pane never downloads large models automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var aiModeSettings: some View {
        Form {
            routingModeSection
        }
        .formStyle(.grouped)
    }

    private var localFilesSettings: some View {
        LocalFilesSettingsView(store: appState.localFileAccess)
    }

    private var chatHistorySettings: some View {
        ChatHistorySettingsView(store: appState.chatHistory)
    }

    private var routingModeSection: some View {
        Section("AI Mode") {
            Picker(
                "Mode",
                selection: Binding(
                    get: { appState.aiRoutingSettings.effectiveMode },
                    set: { appState.setAIRoutingMode($0) }
                )
            ) {
                Label("Local", systemImage: "lock.shield").tag(AIRoutingMode.local)
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
        }
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
        let selectedID = selectedMLXModelID
        return mlxModelChoices.first { $0.id == selectedID } ?? mlxModelChoices.first
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { selectedMLXModelID ?? selectedMLXModel?.id ?? "" },
            set: { selectedMLXModelID = $0 }
        )
    }

    private var runtimeStatusText: String {
        let hasText = appState.mlxVisionSetupSnapshot.textRuntimeURL != nil
        let hasVision = appState.mlxVisionSetupSnapshot.runtimeURL != nil
        switch (hasText, hasVision) {
        case (true, true):
            return "Text + Vision found"
        case (true, false):
            return "Text found"
        case (false, true):
            return "Vision found"
        case (false, false):
            return "Not found"
        }
    }

    private var runtimeStatusTint: Color {
        appState.mlxVisionSetupSnapshot.textRuntimeURL == nil
            && appState.mlxVisionSetupSnapshot.runtimeURL == nil ? .orange : .green
    }

    private var runtimePathText: String {
        [
            appState.mlxVisionSetupSnapshot.textRuntimeURL.map { "Text: \($0.path)" },
            appState.mlxVisionSetupSnapshot.runtimeURL.map { "Vision: \($0.path)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func copyInstallCommand(for model: MLXVisionModel) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.installCommand, forType: .string)
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

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(tint)
    }
}

private struct LocalFilesSettingsView: View {
    @ObservedObject var store: LocalFileAccessStore

    var body: some View {
        Form {
            Section("Local File Access") {
                Text("Pixel Pane can read and search only the files and folders you grant here. Local file changes require an explicit confirmation that names the target path before anything is written.")
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
                                Text(grant.path)
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
                Text("In Local mode, file snippets and confirmed file writes stay on this Mac. In Cloud mode, relevant snippets may be sent to Pixel Pane Cloud because you selected cloud routing; file writes still run locally only after confirmation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ChatHistorySettingsView: View {
    @ObservedObject var store: ChatHistoryStore

    var body: some View {
        Form {
            Section("Local Chat History") {
                Text("Pixel Pane stores chat text locally on this Mac. Screenshots are not saved in history; capture chats keep only their transcript.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    LabeledContent("Saved chats", value: "\(store.sessions.filter { !$0.turns.isEmpty }.count)")

                    Spacer()

                    Button(role: .destructive) {
                        store.clearAll()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
                    .disabled(store.sessions.isEmpty)
                }
            }

            if !store.sessions.isEmpty {
                Section("Recent") {
                    ForEach(store.recentSessions(limit: 12)) { session in
                        HStack(spacing: 10) {
                            Image(systemName: session.contextKind == .capture ? "viewfinder" : "bubble.left.and.bubble.right")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.displayTitle)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Text("\(session.contextKind.displayName) - \(session.turns.count) messages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                store.deleteSession(session)
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
    }
}

private struct ResponseStyleSlider: View {
    let level: ResponseDetailLevel
    let onChange: (ResponseDetailLevel) -> Void

    private let thumbWidth: CGFloat = 18
    private let thumbHeight: CGFloat = 28
    private let trackHeight: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(level.title)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Text("\(level.maxOutputTokens(for: .ask)) chat tokens")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                sliderTrack
                    .frame(height: thumbHeight)

                HStack(spacing: 0) {
                    ForEach(ResponseDetailLevel.allCases) { stop in
                        VStack(alignment: tickHorizontalAlignment(for: stop), spacing: 2) {
                            Text(stop.title)
                                .font(.caption2.weight(stop == level ? .bold : .regular))
                            Text("\(stop.maxOutputTokens(for: .ask))")
                                .font(.system(size: 9, weight: stop == level ? .bold : .regular, design: .rounded))
                        }
                        .foregroundStyle(stop == level ? .primary : .tertiary)
                        .frame(maxWidth: .infinity, alignment: tickAlignment(for: stop))
                    }
                }
                .padding(.horizontal, thumbWidth / 2)
            }

        }
    }

    private var sliderTrack: some View {
        GeometryReader { proxy in
            let trackWidth = max(1, proxy.size.width - thumbWidth)
            let trackStart = thumbWidth / 2
            let centerY = proxy.size.height / 2
            let progress = CGFloat(level.rawValue) / CGFloat(ResponseDetailLevel.allCases.count - 1)
            let thumbCenterX = trackStart + (trackWidth * progress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: trackWidth, height: trackHeight)
                    .position(x: trackStart + trackWidth / 2, y: centerY)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, thumbCenterX - trackStart), height: trackHeight)
                    .position(x: trackStart + max(0, thumbCenterX - trackStart) / 2, y: centerY)

                ForEach(ResponseDetailLevel.allCases) { stop in
                    let stopProgress = CGFloat(stop.rawValue) / CGFloat(ResponseDetailLevel.allCases.count - 1)
                    Circle()
                        .fill(stop == level ? Color.accentColor : Color.secondary.opacity(0.45))
                        .frame(width: 4, height: 4)
                        .position(x: trackStart + trackWidth * stopProgress, y: centerY + 10)
                }

                Capsule()
                    .fill(.primary)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                    .position(x: thumbCenterX, y: centerY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        setLevel(at: value.location.x, trackStart: trackStart, trackWidth: trackWidth)
                    }
            )
        }
    }

    private func tickAlignment(for stop: ResponseDetailLevel) -> Alignment {
        switch stop {
        case .brief:
            .leading
        case .balanced:
            .center
        case .thorough:
            .trailing
        }
    }

    private func tickHorizontalAlignment(for stop: ResponseDetailLevel) -> HorizontalAlignment {
        switch stop {
        case .brief:
            .leading
        case .balanced:
            .center
        case .thorough:
            .trailing
        }
    }

    private func setLevel(at xPosition: CGFloat, trackStart: CGFloat, trackWidth: CGFloat) {
        let progress = min(1, max(0, (xPosition - trackStart) / trackWidth))
        let rawValue = Int((progress * CGFloat(ResponseDetailLevel.allCases.count - 1)).rounded())
        if let next = ResponseDetailLevel(rawValue: rawValue), next != level {
            onChange(next)
        }
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
