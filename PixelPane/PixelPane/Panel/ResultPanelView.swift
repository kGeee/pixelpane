import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ResultPanelView: View {
    @Environment(\.openSettings) private var openSettings
    @FocusState private var isChatInputFocused: Bool

    let result: CaptureResult
    let routingSettings: AIRoutingSettings
    let responseDetail: ResponseDetailLevel
    let localAICapabilities: AIBackendCapabilities
    @ObservedObject var localFileAccess: LocalFileAccessStore
    @ObservedObject var chatHistory: ChatHistoryStore
    let presentationStyle: ResultPanelPresentationStyle
    let startsInAssistantMode: Bool
    let startsExpanded: Bool
    let showsInitialNotchNotification: Bool
    let onPresentationSizeChange: ((CGSize) -> Void)?
    let onTryAgain: () -> Void
    let onClose: () -> Void
    private let smartDefaultSelection: SmartDefaultActionSelection
    private let localAIBackend: any AIBackend = HybridLocalAIBackend()
    private let cloudAIBackend: any AIBackend
    private let mlxDetector = MLXVisionRuntimeDetector()
    private let mlxModelStore = MLXVisionModelStore()
    private let displayTextNormalizer = ModelDisplayTextNormalizer()
    @State private var selectedAction: PanelActionKind = .extractText
    @State private var loadingActions: Set<PanelActionKind> = []
    @State private var activeText: String
    @State private var actionSourceLabel: String?
    @State private var actionTargetLabel: String?
    @State private var actionBackendLabel: String?
    @State private var outputStatistics: [AIModelOutputStatistic] = []
    @State private var hiddenReasoning: String?
    @State private var confirmationMessage: String?
    @State private var confirmationVisible: Bool = false
    @State private var recoveryState: ActionRecoveryState?
    @State private var actionOutputs: [PanelActionKind: PanelActionOutputState]
    @State private var askInput = ""
    @State private var askTurns: [AskConversationTurn] = []
    @State private var pendingLocalFileWriteProposal: LocalFileWriteProposal?
    @State private var pendingTerminalCommandProposal: AssistantTerminalCommandProposal?
    @State private var assistantImageContext: AssistantImageContext?
    @State private var assistantToolState: AssistantToolState
    @State private var isPreparingAssistantImage = false
    @State private var chatContextID: String
    @State private var chatContextKind: ChatSessionContextKind
    @State private var didAppear = false
    @State private var didStartSmartDefault = false
    @State private var isNotchExpanded = false
    @State private var isNotchContentVisible = false
    @State private var notchShellOpacity = 1.0
    @State private var pendingNotchCollapse: DispatchWorkItem?
    @State private var notchHoverCollapseSuppressedUntil = Date.distantPast
    @State private var compactNotchNotification: CompactNotchNotificationState?

    init(
        result: CaptureResult,
        routingSettings: AIRoutingSettings,
        responseDetail: ResponseDetailLevel,
        localAICapabilities: AIBackendCapabilities,
        localFileAccess: LocalFileAccessStore,
        chatHistory: ChatHistoryStore,
        presentationStyle: ResultPanelPresentationStyle = .floatingNearSelection,
        startsInAssistantMode: Bool = false,
        startsExpanded: Bool = false,
        showsInitialNotchNotification: Bool = true,
        onPresentationSizeChange: ((CGSize) -> Void)? = nil,
        onTryAgain: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.result = result
        self.routingSettings = routingSettings
        self.responseDetail = responseDetail
        self.localAICapabilities = localAICapabilities
        self.localFileAccess = localFileAccess
        self.chatHistory = chatHistory
        self.presentationStyle = presentationStyle
        self.startsInAssistantMode = startsInAssistantMode
        self.startsExpanded = startsExpanded
        self.showsInitialNotchNotification = showsInitialNotchNotification
        self.onPresentationSizeChange = onPresentationSizeChange
        self.onTryAgain = onTryAgain
        self.onClose = onClose
        let cloudConfiguration = CloudAIBackendConfiguration(
            baseURL: AIRoutingSettings.cloudBackendBaseURL,
            isCloudModeEnabled: routingSettings.effectiveMode == .cloud,
            allowsImageUpload: routingSettings.effectiveMode == .cloud
        )
        cloudAIBackend = CloudAIBackend(
            configuration: cloudConfiguration,
            tokenProvider: CloudAuthTokenProvider(baseURL: AIRoutingSettings.cloudBackendBaseURL)
        )
        let smartDefaultSelection = SmartDefaultActionSelection(action: .ask, reason: "assistant")
        self.smartDefaultSelection = smartDefaultSelection
        let extractText = ExtractTextAction().run(on: result)
        let extractRecovery = result.isEmptyOCRResult ? ActionRecoveryState.emptyOCR : nil
        let extractState = PanelActionOutputState(
            text: extractText,
            sourceLabel: nil,
            targetLabel: nil,
            backendLabel: nil,
            statistics: [],
            reasoning: nil,
            recovery: extractRecovery
        )
        let initialState: PanelActionOutputState
        if smartDefaultSelection.action == .ask {
            initialState = Self.initialAskOutputState(for: result, routingSettings: routingSettings)
        } else if smartDefaultSelection.action == .extractText {
            initialState = extractState
        } else {
            initialState = Self.initialSmartDefaultOutputState(
                for: smartDefaultSelection.action,
                result: result,
                routingSettings: routingSettings
            )
        }
        var outputStates: [PanelActionKind: PanelActionOutputState] = [.extractText: extractState]
        outputStates[smartDefaultSelection.action] = initialState
        _selectedAction = State(initialValue: smartDefaultSelection.action)
        let restoredSession = Self.restoredChatSession(for: result, in: chatHistory)
        let restoredTurns = restoredSession?.turns.map { AskConversationTurn(storedTurn: $0) } ?? []
        var initialToolState = restoredSession?.toolState ?? Self.initialAssistantToolState(for: result)
        if result.sourceType == .ocr {
            initialToolState.updateVisualContext(Self.captureVisualState(for: result, imageWillBeSent: false))
        }
        _askTurns = State(initialValue: restoredTurns)
        _assistantToolState = State(initialValue: initialToolState)
        _chatContextID = State(initialValue: restoredSession?.contextID ?? Self.defaultChatContextID(for: result))
        _chatContextKind = State(initialValue: restoredSession?.contextKind ?? Self.defaultChatContextKind(for: result))
        _activeText = State(initialValue: initialState.text)
        _actionSourceLabel = State(initialValue: initialState.sourceLabel)
        _actionTargetLabel = State(initialValue: initialState.targetLabel)
        _actionBackendLabel = State(initialValue: initialState.backendLabel)
        _outputStatistics = State(initialValue: initialState.statistics)
        _hiddenReasoning = State(initialValue: initialState.reasoning)
        _recoveryState = State(initialValue: initialState.recovery)
        _actionOutputs = State(initialValue: outputStates)
        _isNotchExpanded = State(initialValue: startsExpanded)
        _isNotchContentVisible = State(initialValue: startsExpanded)
    }

    var body: some View {
        overlayShell
            .background(hiddenShortcuts)
            .scaleEffect(didAppear ? 1 : 0.985)
            .opacity(didAppear ? 1 : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: didAppear)
            .onAppear {
                didAppear = true
                if presentationStyle == .notchAttached,
                   showsInitialNotchNotification,
                   compactNotchNotification == nil {
                    if !loadingActions.isEmpty {
                        compactNotchNotification = .processing
                        onPresentationSizeChange?(ResultPanelPresentationStyle.notchCompactSize)
                    }
                }
                startSmartDefaultActionIfNeeded()
                focusChatInputSoon()
            }
            .onChange(of: loadingActions) { _, newValue in
                updateNotchNotificationState(isProcessing: !newValue.isEmpty)
            }
    }

    private static func restoredChatSession(
        for result: CaptureResult,
        in store: ChatHistoryStore
    ) -> StoredChatSession? {
        switch result.sourceType {
        case .assistant:
            nil
        case .ocr:
            store.session(
                contextID: defaultChatContextID(for: result),
                kind: defaultChatContextKind(for: result)
            )
        }
    }

    private static func defaultChatContextID(for result: CaptureResult) -> String {
        switch result.sourceType {
        case .assistant:
            "assistant-\(UUID().uuidString)"
        case .ocr:
            "capture-\(result.id.uuidString)"
        }
    }

    private static func defaultChatContextKind(for result: CaptureResult) -> ChatSessionContextKind {
        result.sourceType == .assistant ? .assistant : .capture
    }

    private static func initialAssistantToolState(for result: CaptureResult) -> AssistantToolState {
        var state = AssistantToolState()
        if result.sourceType == .ocr {
            state.updateVisualContext(captureVisualState(for: result, imageWillBeSent: false))
        }
        return state
    }

    private static func captureVisualState(
        for result: CaptureResult,
        imageWillBeSent: Bool
    ) -> AssistantVisualContextState? {
        guard result.sourceType == .ocr else { return nil }
        return AssistantVisualContextState(
            source: .capture,
            label: "Screen region",
            hasImageInput: imageWillBeSent && result.image != nil,
            ocrText: result.text
        )
    }

    @ViewBuilder
    private var overlayShell: some View {
        switch presentationStyle {
        case .floatingNearSelection:
            GlassOverlayContainer {
                innerStack
            }
        case .notchAttached:
            NotchResultContainer(
                isExpanded: isNotchExpanded,
                roundsTopCorners: result.sourceType == .assistant
            ) {
                if isNotchExpanded {
                    notchExpandedStack
                        .opacity(isNotchContentVisible ? 1 : 0)
                        .scaleEffect(isNotchContentVisible ? 1 : 0.985, anchor: .top)
                        .animation(.easeOut(duration: 0.20), value: isNotchContentVisible)
                } else {
                    compactNotchStack
                }
            }
            .opacity(isNotchExpanded ? notchShellOpacity : 1)
            .onHover(perform: handleNotchHover)
        }
    }

    private var innerStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            workspaceSection
            recoverySection
            assistantContextSection
            localFileWriteConfirmationSection
            terminalCommandConfirmationSection
            askInputSection
        }
    }

    private var notchExpandedStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: isBlankAssistantChat ? 30 : 40)
            notchAssistantHeaderSection
            if isBlankAssistantChat {
                emptyAssistantWelcomeSection
            }
            if !isBlankAssistantChat {
                workspaceSection
            }
            recoverySection
            assistantContextSection
            localFileWriteConfirmationSection
            terminalCommandConfirmationSection
            askInputSection
        }
    }

    private var compactNotchStack: some View {
        ZStack {
            if let compactNotchNotification {
                CompactNotchNotificationView(state: compactNotchNotification)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func expandNotch() {
        guard presentationStyle == .notchAttached else { return }
        pendingNotchCollapse?.cancel()
        pendingNotchCollapse = nil
        notchShellOpacity = 1
        let targetSize = preferredNotchExpandedSize
        if isNotchExpanded {
            onPresentationSizeChange?(targetSize)
            isNotchContentVisible = true
            focusChatInputSoon()
            return
        }
        isNotchContentVisible = false
        onPresentationSizeChange?(targetSize)
        isNotchExpanded = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            guard isNotchExpanded else { return }
            isNotchContentVisible = true
            focusChatInputSoon()
        }
    }

    private func collapseNotch() {
        guard presentationStyle == .notchAttached, isNotchExpanded else { return }
        pendingNotchCollapse?.cancel()
        pendingNotchCollapse = nil
        isNotchContentVisible = false
        let hasNotification = compactNotchNotification != nil
        if hasNotification {
            onPresentationSizeChange?(ResultPanelPresentationStyle.notchCompactSize)
        } else {
            withAnimation(.easeOut(duration: 0.10)) {
                notchShellOpacity = 0
            }
            onPresentationSizeChange?(ResultPanelPresentationStyle.notchHoverTargetSize)
        }
        let completion = DispatchWorkItem {
            guard isNotchExpanded else { return }
            isNotchExpanded = false
            notchShellOpacity = 1
        }
        pendingNotchCollapse = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: completion)
    }

    private func handleNotchHover(_ isHovering: Bool) {
        guard presentationStyle == .notchAttached else { return }
        if isHovering {
            compactNotchNotification = nil
            expandNotch()
        } else {
            let workItem = DispatchWorkItem {
                guard !isNotchHoverCollapseSuppressed else { return }
                guard !isMouseInsideNotchBounds(size: preferredNotchExpandedSize) else { return }
                collapseNotch()
            }
            pendingNotchCollapse?.cancel()
            pendingNotchCollapse = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
        }
    }

    private func isMouseInsideNotchBounds(size: CGSize) -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            return false
        }

        let bounds = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        ).insetBy(dx: -8, dy: -8)

        return bounds.contains(mouseLocation)
    }

    private func updateNotchNotificationState(isProcessing: Bool) {
        guard presentationStyle == .notchAttached else { return }
        compactNotchNotification = isProcessing ? .processing : nil
        guard !isNotchExpanded else { return }
        onPresentationSizeChange?(
            isProcessing
                ? ResultPanelPresentationStyle.notchCompactSize
                : ResultPanelPresentationStyle.notchHoverTargetSize
        )
    }

    private func focusChatInputSoon() {
        guard selectedAction == .ask else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard selectedAction == .ask else { return }
            guard presentationStyle != .notchAttached || isNotchExpanded else { return }
            isChatInputFocused = true
        }
    }

    private var headerSection: some View {
        header
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)
    }

    private var notchAssistantHeaderSection: some View {
        HStack(spacing: 10) {
            NotchHeaderStatusDot()

            Text("Pixel Pane")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            if loadingActions.contains(.ask) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, isBlankAssistantChat ? 6 : 12)
    }

    private var emptyAssistantWelcomeSection: some View {
        HStack(spacing: 8) {
            Text("Ready")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Circle()
                .fill(.secondary.opacity(0.45))
                .frame(width: 3, height: 3)

            Text(routingSettings.effectiveMode == .cloud ? "Cloud Mode" : "Local Mode")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 10)

            HStack(spacing: 6) {
                EmptyAssistantStatusChip(title: responseDetail.title, systemImage: "text.alignleft")
                EmptyAssistantStatusChip(
                    title: localFileAccess.grants.isEmpty ? "No Files" : "\(localFileAccess.grants.count) Files",
                    systemImage: localFileAccess.grants.isEmpty ? "folder" : "folder.fill"
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private var workspaceSection: some View {
        workspace
            .padding(.horizontal, 20)
            .padding(.bottom, presentationStyle == .notchAttached ? 14 : 12)
    }

    @ViewBuilder
    private var recoverySection: some View {
        if let recoveryState {
            ActionRecoveryView(
                state: recoveryState,
                onPrimaryAction: performRecoveryPrimaryAction,
                onSecondaryAction: secondaryRecoveryAction(for: recoveryState)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private func secondaryRecoveryAction(for state: ActionRecoveryState) -> (() -> Void)? {
        guard state.secondaryTitle != nil else { return nil }
        return performRecoverySecondaryAction
    }

    @ViewBuilder
    private var askInputSection: some View {
        if selectedAction == .ask {
            askInputBar
                .padding(.horizontal, 20)
                .padding(.bottom, presentationStyle == .notchAttached ? 18 : 16)
        }
    }

    @ViewBuilder
    private var assistantContextSection: some View {
        if !assistantContextBadges.isEmpty {
            HStack(spacing: 6) {
                ForEach(assistantContextBadges) { badge in
                    OverlayMetadataChip(badge: badge)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var localFileWriteConfirmationSection: some View {
        if let proposal = pendingLocalFileWriteProposal, selectedAction == .ask {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text(proposal.actionLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()
                }

                Text(proposal.targetPath)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                Text(proposal.detailText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    OverlayPillButton(
                        title: "Confirm",
                        systemImage: "checkmark",
                        style: .accent,
                        action: confirmLocalFileWrite
                    )

                    OverlayPillButton(
                        title: "Cancel",
                        systemImage: "xmark",
                        style: .secondary,
                        action: cancelLocalFileWrite
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.orange.opacity(0.20), lineWidth: 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var terminalCommandConfirmationSection: some View {
        if let proposal = pendingTerminalCommandProposal, selectedAction == .ask {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text("Allow terminal")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()
                }

                Text(proposal.reason)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(URL(fileURLWithPath: proposal.workingDirectory).lastPathComponent)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(proposal.command)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 8) {
                    OverlayPillButton(
                        title: "Allow",
                        systemImage: "play.fill",
                        style: .accent,
                        action: confirmTerminalCommand
                    )

                    OverlayPillButton(
                        title: "Cancel",
                        systemImage: "xmark",
                        style: .secondary,
                        action: cancelTerminalCommand
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.orange.opacity(0.20), lineWidth: 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ActionGradientBadge(systemImage: selectedAction.systemImage)

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedAction.title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(headerSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(result.createdAt, style: .time)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 4)

            if presentationStyle == .notchAttached {
                Button(action: collapseNotch) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Collapse")
            }

            if presentationStyle == .floatingNearSelection {
                OverlayCloseButton(action: onClose)
            }
        }
    }

    private var notchHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    NotchHeaderStatusDot()

                    Text(selectedAction.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Text(headerSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var headerSubtitle: String {
        switch selectedAction {
        case .extractText:
            "Local OCR output from the selected region"
        case .translate:
            "Translate the captured text"
        case .explain:
            result.image == nil ? "Explain the captured text" : "Explain the screenshot and OCR text"
        case .simplify:
            "Rewrite the captured text more clearly"
        case .debug:
            "Inspect technical text and visible screenshot context"
        case .ask:
            hasCaptureContext ? "Chat about the current capture" : "Quick local assistant"
        }
    }

    private var workspace: some View {
        HStack(alignment: .top, spacing: 14) {
            outputPane
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)

            if presentationStyle == .floatingNearSelection, let image = result.image {
                CapturePreviewPane(image: image)
                    .frame(width: 220)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var outputPane: some View {
        outputPaneContent
            .padding(usesFramedNotchOutputPane ? 18 : 0)
            .background {
                if usesFramedNotchOutputPane {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.07), lineWidth: 1)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var usesFramedNotchOutputPane: Bool {
        presentationStyle == .notchAttached && selectedAction != .ask
    }

    private var outputPaneContent: some View {
        VStack(alignment: .leading, spacing: presentationStyle == .notchAttached ? 0 : 10) {
            if presentationStyle != .notchAttached {
                outputHeader
            }
            outputContent
            reasoningDisclosure
        }
    }

    private var outputHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: selectedAction.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(presentationStyle == .notchAttached ? .secondary : Color.accentColor.opacity(0.85))

            Text(outputTitle)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)

            Spacer()

            if loadingActions.contains(selectedAction) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
            }
        }
    }

    @ViewBuilder
    private var outputContent: some View {
        if selectedAction == .ask {
            AskTranscriptView(
                turns: askTurns,
                toolState: assistantToolState,
                emptyText: hasCaptureContext
                    ? "Chat about this capture."
                    : ""
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if loadingActions.contains(selectedAction), isWorkingPlaceholder(activeText) {
                        TypingStatusView(title: activeText)
                            .padding(.vertical, 4)
                    } else {
                        Text(activeText)
                            .font(.system(size: 15, weight: .regular))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }

                    if !outputStatistics.isEmpty {
                        ModelStatisticsView(statistics: outputStatistics)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var outputTitle: String {
        switch selectedAction {
        case .extractText:
            "Extracted Text"
        case .translate:
            "Translation"
        case .explain:
            "Explanation"
        case .simplify:
            "Simplified Text"
        case .debug:
            "Debug Notes"
        case .ask:
            "Conversation"
        }
    }

    private func isWorkingPlaceholder(_ text: String) -> Bool {
        switch text {
        case "Translating with local text AI...", "Translating with Pixel Pane Cloud...", "Simplifying", "Explaining...", "Debugging...":
            true
        default:
            false
        }
    }

    @ViewBuilder
    private var reasoningDisclosure: some View {
        if let hiddenReasoning, !hiddenReasoning.isEmpty {
            DisclosureGroup {
                ScrollView {
                    Text(hiddenReasoning)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .frame(maxHeight: 120)
            } label: {
                Label("Model Thinking", systemImage: "brain")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            OverlayPillButton(title: "Copy", systemImage: "doc.on.doc", style: .primary, action: copyText)
                .keyboardShortcut("c", modifiers: .command)
                .disabled(activeText.isEmpty)

            Spacer(minLength: 8)

            if let confirmationMessage, confirmationVisible {
                Text(confirmationMessage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.06), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            HStack(spacing: 5) {
                ForEach(metadataBadges) { badge in
                    OverlayMetadataChip(badge: badge)
                }
            }
        }
    }

    private var metadataBadges: [MetadataBadge] {
        var badges = [
            MetadataBadge(
                text: result.sourceType.displayName,
                systemImage: "text.viewfinder",
                help: "Text was extracted from this capture with local OCR."
            ),
            MetadataBadge(
                text: routingBadgeText,
                systemImage: routingBadgeSystemImage,
                help: routingSettings.detail
            )
        ]

        if let actionSourceLabel, let actionTargetLabel {
            badges.append(
                MetadataBadge(
                    text: "\(actionSourceLabel) -> \(actionTargetLabel)",
                    systemImage: "globe",
                    help: "Translation language route."
                )
            )
        } else if result.detectedLanguage != .unknown {
            badges.append(
                MetadataBadge(
                    text: result.detectedLanguage.displayName,
                    systemImage: "globe",
                    help: "Detected source language."
                )
            )
        }

        return badges
    }

    private var assistantContextBadges: [MetadataBadge] {
        var badges: [MetadataBadge] = []

        if hasCaptureContext {
            badges.append(
                MetadataBadge(
                    text: "Screen region",
                    systemImage: "viewfinder",
                    help: "The current chat has OCR and screenshot context from the selected region."
                )
            )
        }

        if let assistantImageContext {
            badges.append(
                MetadataBadge(
                    text: assistantImageContext.label,
                    systemImage: "photo",
                    help: assistantImageContext.isOCRComplete
                        ? "A user-provided image is attached to this chat. Text fallback is ready for text-only models."
                        : "A user-provided image is attached to this chat. Pixel Pane is still preparing text fallback."
                )
            )
        } else if isPreparingAssistantImage {
            badges.append(
                MetadataBadge(
                    text: "Image",
                    systemImage: "photo",
                    help: "Pixel Pane is preparing the attached image."
                )
            )
        }

        badges.append(
            MetadataBadge(
                text: routingBadgeText,
                systemImage: routingBadgeSystemImage,
                help: routingSettings.detail
            )
        )

        return badges
    }

    private var routingBadgeText: String {
        switch routingSettings.effectiveMode {
        case .local:
            "Local"
        case .cloud:
            "Cloud"
        }
    }

    private var routingBadgeSystemImage: String {
        switch routingSettings.effectiveMode {
        case .local:
            "lock.laptopcomputer"
        case .cloud:
            "cloud"
        }
    }

    private func backendBadgeSystemImage(for label: String) -> String {
        switch label {
        case Self.appleTextBackendLabel:
            "apple.intelligence"
        case Self.mlxTextBackendLabel:
            "text.bubble"
        case Self.mlxVisionBackendLabel:
            "eye"
        case Self.cloudBackendLabel:
            "cloud"
        case "Unavailable":
            "exclamationmark.triangle"
        default:
            "cpu"
        }
    }

    private func backendBadgeHelp(for label: String) -> String {
        switch label {
        case Self.appleTextBackendLabel:
            "Text-only on-device generation through Apple's local model."
        case Self.mlxTextBackendLabel:
            "Text-only on-device generation through the selected MLX model."
        case Self.mlxVisionBackendLabel:
            "Image-aware on-device generation through the selected MLX vision model."
        case Self.cloudBackendLabel:
            "Opted-in cloud generation through the Pixel Pane proxy."
        case "Unavailable":
            "The selected action could not reach an available local backend."
        default:
            "Backend used for this action."
        }
    }

    @ViewBuilder
    private var askInputBar: some View {
        if selectedAction == .ask {
            HStack(spacing: 8) {
                OverlayPillButton(
                    title: "New",
                    systemImage: "square.and.pencil",
                    style: .secondary,
                    displayStyle: .iconOnly,
                    action: startNewAssistantChat
                )
                .disabled(!canStartNewChat)

                FileSourceMenuButton(
                    grants: localFileAccess.grants,
                    isDisabled: !loadingActions.isEmpty,
                    onGrantFolder: localFileAccess.grantFolder,
                    onGrantFile: localFileAccess.grantFile,
                    onRemove: localFileAccess.removeGrant,
                    onClear: localFileAccess.clearGrants
                )

                ChatHistoryMenuButton(
                    sessions: chatHistory.recentSessions(),
                    isDisabled: !loadingActions.isEmpty,
                    onSelect: loadChatSession
                )

                OverlayPillButton(
                    title: "Copy Chat",
                    systemImage: "doc.on.doc",
                    style: .secondary,
                    displayStyle: .iconOnly,
                    action: copyChatTranscript
                )
                .disabled(!canCopyChatTranscript)

                AssistantImageMenuButton(
                    context: assistantImageContext,
                    isPreparing: isPreparingAssistantImage,
                    isDisabled: !loadingActions.isEmpty,
                    onChoose: chooseAssistantImage,
                    onClear: clearAssistantImage
                )

                OverlayTextField(
                    placeholder: hasCaptureContext ? "Ask about this screen" : "Ask Pixel Pane",
                    text: $askInput,
                    isFocused: $isChatInputFocused,
                    onSubmit: sendAskQuestion
                )

                OverlayPillButton(
                    title: "Send",
                    systemImage: "paperplane.fill",
                    style: .accent,
                    displayStyle: .prominentIconAndTitle,
                    action: sendAskQuestion
                )
                .disabled(!canSendAskQuestion)
            }
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(activeText, forType: .string)
        showConfirmation("Copied")
    }

    private var canCopyChatTranscript: Bool {
        !askTurns.isEmpty
            || pendingTerminalCommandProposal != nil
            || pendingLocalFileWriteProposal != nil
            || !assistantToolState.recentToolResults.isEmpty
    }

    private func copyChatTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(chatTranscriptExportText(), forType: .string)
        showConfirmation("Chat copied")
    }

    private func chatTranscriptExportText() -> String {
        var sections: [String] = []
        sections.append(
            """
            # Pixel Pane Chat Export
            Exported: \(Self.chatExportDateString())
            Context: \(chatContextKind.displayName)
            Route: \(routingSettings.effectiveMode.displayName)
            Response Style: \(responseDetail.title)
            Capture Context: \(hasCaptureContext ? "attached" : "none")
            Selected Action: \(selectedAction.title)
            Loading Actions: \(loadingActions.map(\.title).sorted().joined(separator: ", "))
            Current Backend Label: \(actionBackendLabel ?? "none")
            Current Source Label: \(actionSourceLabel ?? "none")
            Current Target Label: \(actionTargetLabel ?? "none")
            Active Text Characters: \(activeText.count)
            Hidden Reasoning Characters: \(hiddenReasoning?.count ?? 0)
            """
        )

        sections.append(chatRuntimeDebugExportText())

        if let hiddenReasoning, !hiddenReasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(
                """
                ## Hidden Thinking / Reasoning
                \(Self.truncatedForDebugExport(hiddenReasoning, limit: 12_000))
                """
            )
        }

        if let assistantImageContext {
            sections.append(
                """
                ## Active Image Context
                Source: \(Self.displayName(for: assistantImageContext.source))
                Label: \(assistantImageContext.label)
                OCR: \(assistantImageContext.ocrText?.isEmpty == false ? "available" : "none")
                OCR Excerpt:
                \(Self.truncatedForDebugExport(assistantImageContext.ocrText ?? "", limit: 4_000))
                """
            )
        }

        if let visualContext = assistantToolState.activeVisualContext {
            sections.append(
                """
                ## Active Visual Tool Context
                Source: \(visualContext.source.rawValue)
                Label: \(visualContext.label)
                Image Input: \(visualContext.hasImageInput ? "yes" : "no")
                OCR: \(visualContext.hasOCRText ? "available" : "none")
                Updated: \(Self.chatExportDateString(visualContext.updatedAt))
                OCR Excerpt:
                \(visualContext.ocrExcerpt ?? "")
                """
            )
        }

        if !localFileAccess.grants.isEmpty {
            let grantLines = localFileAccess.grants.map { grant in
                "- \(grant.kindLabel): \(grant.path)"
            }
            sections.append("## Granted File Access\n\(grantLines.joined(separator: "\n"))")
        }

        if !askTurns.isEmpty {
            let turnText = askTurns.enumerated().map { index, turn in
                var lines = [
                    "### Turn \(index + 1)",
                    "User:",
                    turn.question,
                    "",
                    "Assistant (\(turn.backendLabel)):",
                    turn.answer.isEmpty ? "[Thinking / no answer yet]" : turn.answer
                ]
                if !turn.statistics.isEmpty {
                    let stats = turn.statistics.map { statistic in
                        let detail = statistic.detail.map { " (\($0))" } ?? ""
                        return "- \(statistic.label): \(statistic.value)\(detail)"
                    }
                    lines.append("")
                    lines.append("Stats:")
                    lines.append(contentsOf: stats)
                }
                return lines.joined(separator: "\n")
            }
            sections.append("## Conversation\n\(turnText.joined(separator: "\n\n"))")
        }

        let toolStateText = assistantToolStateExportText()
        if !toolStateText.isEmpty {
            sections.append("## Agent Tool State\n\(toolStateText)")
        }

        if let toolStateJSON = assistantToolStateJSONExportText() {
            sections.append("## Raw Assistant Tool State JSON\n```json\n\(toolStateJSON)\n```")
        }

        if let pendingTerminalCommandProposal {
            sections.append(
                """
                ## Pending Terminal Confirmation
                Command: \(pendingTerminalCommandProposal.command)
                Directory: \(pendingTerminalCommandProposal.workingDirectory)
                Reason: \(pendingTerminalCommandProposal.reason)
                Risk: \(pendingTerminalCommandProposal.riskLevel.rawValue)
                Requires Confirmation: \(pendingTerminalCommandProposal.requiresConfirmation ? "yes" : "no")
                """
            )
        }

        if let pendingLocalFileWriteProposal {
            sections.append(
                """
                ## Pending File Write Confirmation
                Action: \(pendingLocalFileWriteProposal.actionLabel)
                Target: \(pendingLocalFileWriteProposal.targetPath)
                Details: \(pendingLocalFileWriteProposal.detailText)
                """
            )
        }

        return sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func chatRuntimeDebugExportText() -> String {
        var lines: [String] = [
            "## Current Runtime State",
            "- Chat Context ID: \(chatContextID)",
            "- Chat Context Kind: \(chatContextKind.displayName)",
            "- Ask Input Draft: \(askInput.isEmpty ? "[empty]" : Self.truncatedForDebugExport(askInput, limit: 2_000))",
            "- Pending File Write: \(pendingLocalFileWriteProposal?.detailText ?? "none")",
            "- Pending Terminal: \(pendingTerminalCommandProposal?.command ?? "none")"
        ]

        if !outputStatistics.isEmpty {
            lines.append("- Active Output Statistics:")
            lines.append(contentsOf: outputStatistics.map { statistic in
                let detail = statistic.detail.map { " (\($0))" } ?? ""
                return "  - \(statistic.label): \(statistic.value)\(detail)"
            })
        }

        if !activeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- Active Text Snapshot:")
            lines.append(Self.truncatedForDebugExport(activeText, limit: 8_000))
        }

        return lines.joined(separator: "\n")
    }

    private func assistantToolStateExportText() -> String {
        var lines: [String] = []

        if let pending = assistantToolState.pendingContinuation {
            lines.append("Pending continuation: \(pending.kind.rawValue)")
            lines.append(contentsOf: pending.sources.map { "- Candidate: \($0.kindLabel) \($0.path)" })
        }

        if let lastListedFolder = assistantToolState.lastListedFolder {
            lines.append("Last listed folder: \(lastListedFolder.path)")
        }

        if !assistantToolState.lastFileSources.isEmpty {
            lines.append("Recent file sources:")
            lines.append(contentsOf: assistantToolState.lastFileSources.map { source in
                "- \(source.kindLabel): \(source.path) [display: \(source.displayName), snippets: \(source.snippetCount), truncated: \(source.isTruncated)]"
            })
        }

        if !assistantToolState.grantedSourcesUsed.isEmpty {
            lines.append("Granted sources used:")
            lines.append(contentsOf: assistantToolState.grantedSourcesUsed.map { source in
                "- \(source.kindLabel): \(source.path) [display: \(source.displayName), snippets: \(source.snippetCount), truncated: \(source.isTruncated)]"
            })
        }

        if !assistantToolState.lastFileSnippets.isEmpty {
            lines.append("Recent file snippets:")
            lines.append(contentsOf: assistantToolState.lastFileSnippets.map { snippet in
                """
                - \(snippet.path) [score: \(snippet.score)]
                  \(Self.truncatedForDebugExport(snippet.preview, limit: 2_500).replacingOccurrences(of: "\n", with: "\n  "))
                """
            })
        }

        if !assistantToolState.recentToolResults.isEmpty {
            lines.append("Recent tool results:")
            lines.append(contentsOf: assistantToolState.recentToolResults.map { result in
                let truncated = result.isTruncated ? ", truncated" : ""
                var resultLines = [
                    "- \(result.toolName.rawValue): \(result.summary) [items: \(result.itemCount), sources: \(result.sourceCount)\(truncated), at: \(Self.chatExportDateString(result.createdAt))]"
                ]
                if let sources = result.sources, !sources.isEmpty {
                    resultLines.append(contentsOf: sources.map { "  Source: \($0.kindLabel) \($0.path) [snippets: \($0.snippetCount), truncated: \($0.isTruncated)]" })
                }
                if let snippets = result.snippets, !snippets.isEmpty {
                    resultLines.append(contentsOf: snippets.map { snippet in
                        """
                          Snippet: \(snippet.path) [score: \(snippet.score)]
                          \(Self.truncatedForDebugExport(snippet.preview, limit: 2_000).replacingOccurrences(of: "\n", with: "\n  "))
                        """
                    })
                }
                if let writeProposalSummary = result.writeProposalSummary {
                    resultLines.append("  Write proposal/result: \(writeProposalSummary)")
                }
                if let command = result.terminalCommand {
                    resultLines.append("  Terminal command: \(command)")
                    resultLines.append("  Working directory: \(result.terminalWorkingDirectory ?? "unknown")")
                    resultLines.append("  Exit code: \(result.terminalExitCode.map(String.init) ?? "unknown"), duration: \(result.terminalDurationSeconds.map { String(format: "%.2fs", $0) } ?? "unknown"), timed out: \(result.terminalDidTimeOut == true ? "yes" : "no"), output truncated: \(result.terminalWasOutputTruncated == true ? "yes" : "no")")
                    if let stdout = result.terminalStdout, !stdout.isEmpty {
                        resultLines.append("  STDOUT:\n\(Self.truncatedForDebugExport(stdout, limit: 8_000).replacingOccurrences(of: "\n", with: "\n  "))")
                    }
                    if let stderr = result.terminalStderr, !stderr.isEmpty {
                        resultLines.append("  STDERR:\n\(Self.truncatedForDebugExport(stderr, limit: 4_000).replacingOccurrences(of: "\n", with: "\n  "))")
                    }
                }
                return resultLines.joined(separator: "\n")
            })
        }

        return lines.joined(separator: "\n")
    }

    private func assistantToolStateJSONExportText() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(assistantToolState) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func exportText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "PixelPane-\(exportDateString()).txt"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try activeText.write(to: url, atomically: true, encoding: .utf8)
            showConfirmation("Exported")
        } catch {
            showConfirmation("Export failed")
        }
    }

    private func chooseAssistantImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose Image"
        panel.message = "Pixel Pane will use this image as transient chat context."
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let image = try Self.loadCGImage(from: url)
            let context = AssistantImageContext(
                source: .userAttachment,
                label: url.lastPathComponent.isEmpty ? "Image" : url.lastPathComponent,
                image: image
            )
            assistantImageContext = context
            assistantToolState.updateVisualContext(AssistantVisualContextState(imageContext: context, imageWillBeSent: false))
            isPreparingAssistantImage = true
            showConfirmation("Image attached")

            Task {
                let ocrText = (try? await OCREngine().recognizeText(in: image))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    guard assistantImageContext?.id == context.id else { return }
                    assistantImageContext?.ocrText = ocrText
                    assistantImageContext?.isOCRComplete = true
                    if let assistantImageContext {
                        assistantToolState.updateVisualContext(
                            AssistantVisualContextState(imageContext: assistantImageContext, imageWillBeSent: false)
                        )
                    }
                    isPreparingAssistantImage = false
                    setOutputState(askOutputState(), for: .ask)
                }
            }
        } catch {
            showConfirmation("Image unavailable")
        }
    }

    private func clearAssistantImage() {
        assistantImageContext = nil
        isPreparingAssistantImage = false
        assistantToolState.updateVisualContext(Self.captureVisualState(for: result, imageWillBeSent: false))
        setOutputState(askOutputState(), for: .ask)
        focusChatInputSoon()
    }

    private static func loadCGImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }

    private func showConfirmation(_ message: String) {
        confirmationMessage = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            confirmationVisible = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    confirmationVisible = false
                }
            }
        }
    }

    private func exportDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }

    private static func chatExportDateString() -> String {
        chatExportDateString(Date())
    }

    private static func chatExportDateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func truncatedForDebugExport(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let end = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n[... truncated \(value.count - limit) characters ...]"
    }

    private static func displayName(for source: AssistantImageContextSource) -> String {
        switch source {
        case .capture:
            return "Capture"
        case .userAttachment:
            return "User attachment"
        case .clipboard:
            return "Clipboard"
        }
    }

    private var actionStates: [PanelActionState] {
        PanelActionState.states(
            selectedAction: selectedAction,
            loadingActions: visibleLoadingActions,
            hasText: hasUsableOCRText,
            allowsPlainAsk: !hasCaptureContext,
            canUseImageInput: canUseImageInput,
            showsDebug: result.technicalClassification.shouldShowDebug
        )
    }

    private var visibleLoadingActions: Set<PanelActionKind> {
        loadingActions
    }

    private var hasUsableOCRText: Bool {
        !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !result.isEmptyOCRResult
    }

    private var hasCaptureContext: Bool {
        result.sourceType != .assistant && chatContextKind == .capture
    }

    private var isBlankAssistantChat: Bool {
        selectedAction == .ask
            && askTurns.isEmpty
            && !hasCaptureContext
            && recoveryState == nil
    }

    private var canStartNewChat: Bool {
        selectedAction == .ask
            && !loadingActions.contains(.ask)
            && (!askTurns.isEmpty || hasCaptureContext || recoveryState != nil)
    }

    private var preferredNotchExpandedSize: CGSize {
        if isBlankAssistantChat {
            return ResultPanelPresentationStyle.notchEmptyAssistantSize
        }
        if selectedAction == .ask {
            return preferredAskNotchSize
        }
        return ResultPanelPresentationStyle.notchExpandedSize
    }

    private var isNotchHoverCollapseSuppressed: Bool {
        Date() < notchHoverCollapseSuppressedUntil
    }

    private func suppressNextNotchHoverCollapseBriefly() {
        guard presentationStyle == .notchAttached, isNotchExpanded else { return }
        pendingNotchCollapse?.cancel()
        pendingNotchCollapse = nil
        notchHoverCollapseSuppressedUntil = Date().addingTimeInterval(0.9)
    }

    private func updateExpandedNotchSizeIfNeeded() {
        guard presentationStyle == .notchAttached, isNotchExpanded else { return }
        onPresentationSizeChange?(preferredNotchExpandedSize)
    }

    private var preferredAskNotchSize: CGSize {
        let width: CGFloat = hasCaptureContext ? 780 : 720
        let headerHeight: CGFloat = 82
        let chipHeight: CGFloat = assistantContextBadges.isEmpty ? 0 : 34
        let composerHeight: CGFloat = 58
        let recoveryHeight: CGFloat = recoveryState == nil ? 0 : 96
        let writeConfirmationHeight: CGFloat = pendingLocalFileWriteProposal == nil ? 0 : 136
        let terminalConfirmationHeight: CGFloat = pendingTerminalCommandProposal == nil ? 0 : 132
        let transcriptHeight = estimatedAskTranscriptHeight
        let height = headerHeight
            + transcriptHeight
            + chipHeight
            + composerHeight
            + recoveryHeight
            + writeConfirmationHeight
            + terminalConfirmationHeight
            + 14

        return CGSize(
            width: width,
            height: min(ResultPanelPresentationStyle.notchExpandedSize.height, max(250, height))
        )
    }

    private var estimatedAskTranscriptHeight: CGFloat {
        guard !askTurns.isEmpty else {
            return hasCaptureContext ? 52 : 0
        }

        let visibleTurns = askTurns.suffix(3)
        let estimated = visibleTurns.reduce(CGFloat(0)) { total, turn in
            let questionLines = max(1, ceil(CGFloat(turn.question.count) / 56))
            let answerText = turn.answer.isEmpty ? "Thinking..." : turn.answer
            let answerLines = max(1, ceil(CGFloat(answerText.count) / 82))
            let questionHeight = 32 + questionLines * 17
            let answerHeight = 50 + answerLines * 19
            return total + questionHeight + answerHeight + 22
        }

        return min(340, max(112, estimated))
    }

    private func startSmartDefaultActionIfNeeded() {
        guard !didStartSmartDefault else { return }
        didStartSmartDefault = true

        switch smartDefaultSelection.action {
        case .extractText:
            return
        case .translate:
            startTranslation()
        case .simplify:
            startSimplify()
        case .explain:
            startExplain()
        case .debug:
            startDebug()
        case .ask:
            startAsk()
        }
    }

    private func selectAction(_ state: PanelActionState) {
        guard state.isEnabled else { return }
        guard selectedAction != state.kind else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selectedAction = state.kind
        }
        if state.kind == .ask {
            if let cachedState = actionOutputs[.ask] {
                applyOutputState(cachedState)
            } else {
                startAsk()
            }
            focusChatInputSoon()
            return
        }

        if let cachedState = actionOutputs[state.kind] {
            applyOutputState(cachedState)
            return
        }

        switch state.kind {
        case .extractText:
            restoreExtractOutput()
        case .translate:
            startTranslation()
        case .simplify:
            startSimplify()
        case .explain:
            startExplain()
        case .debug:
            startDebug()
        case .ask:
            break
        }
    }

    private func restoreExtractOutput() {
        if let cachedState = actionOutputs[.extractText] {
            applyOutputState(cachedState)
            return
        }

        let state = PanelActionOutputState(
            text: ExtractTextAction().run(on: result),
            sourceLabel: nil,
            targetLabel: nil,
            backendLabel: nil,
            statistics: [],
            reasoning: nil,
            recovery: result.isEmptyOCRResult ? .emptyOCR : nil
        )
        setOutputState(state, for: .extractText)
    }

    private func applyOutputState(_ state: PanelActionOutputState) {
        activeText = state.text
        actionSourceLabel = state.sourceLabel
        actionTargetLabel = state.targetLabel
        actionBackendLabel = state.backendLabel
        outputStatistics = state.statistics
        hiddenReasoning = state.reasoning
        recoveryState = state.recovery
    }

    private func setOutputState(
        _ state: PanelActionOutputState,
        for kind: PanelActionKind,
        makeVisible: Bool = true
    ) {
        actionOutputs[kind] = state
        if makeVisible, selectedAction == kind {
            applyOutputState(state)
        }
    }

    private func updateOutputState(
        for kind: PanelActionKind,
        _ update: (inout PanelActionOutputState) -> Void
    ) {
        var state = actionOutputs[kind] ?? .empty
        update(&state)
        setOutputState(state, for: kind)
    }

    private func imageInput(for action: PanelActionKind) -> CGImage? {
        if routingSettings.effectiveMode == .cloud {
            guard action.supportsCloudImageInput else { return nil }
            return result.image
        }

        guard responseDetail.usesImageInput(for: action) else { return nil }
        guard localAICapabilities.image.isAvailable else { return nil }
        return result.image
    }

    private func canUseImageInput(for action: PanelActionKind) -> Bool {
        imageInput(for: action) != nil
    }

    private var selectedAIBackend: any AIBackend {
        routingSettings.effectiveMode == .cloud ? cloudAIBackend : localAIBackend
    }

    private func backendLabel(for action: PanelActionKind, imageInput: CGImage?) -> String {
        if routingSettings.effectiveMode == .cloud {
            return Self.cloudBackendLabel
        }
        return imageInput == nil ? localTextBackendLabel() : Self.mlxVisionBackendLabel
    }

    private func localTextBackendLabel() -> String {
        localAICapabilities.text.isAvailable ? Self.mlxTextBackendLabel : Self.appleTextBackendLabel
    }

    private var cloudDetectedLanguage: String? {
        result.detectedLanguage.isKnown ? result.detectedLanguage.displayName : nil
    }

    private func startTranslation() {
        loadingActions.insert(.translate)
        setOutputState(
            PanelActionOutputState(
                text: routingSettings.effectiveMode == .cloud
                    ? "Translating with Pixel Pane Cloud..."
                    : "Translating with local text AI...",
                sourceLabel: "From: \(result.detectedLanguage.displayName)",
                targetLabel: "To: English",
                backendLabel: backendLabel(for: .translate, imageInput: nil),
                statistics: [],
                reasoning: nil,
                recovery: nil
            ),
            for: .translate
        )

        Task {
            await runLocalTranslation()
        }
    }

    private func startSimplify() {
        let imageInput = imageInput(for: .simplify)
        loadingActions.insert(.simplify)
        setOutputState(
            PanelActionOutputState(
                text: "Simplifying",
                sourceLabel: nil,
                targetLabel: nil,
                backendLabel: backendLabel(for: .simplify, imageInput: imageInput),
                statistics: [],
                reasoning: nil,
                recovery: nil
            ),
            for: .simplify
        )

        let prompt = """
        Simplify the captured text into a shorter, clearer version.

        Rules:
        - Return only the simplified text.
        - Keep the core meaning and important facts.
        - Prefer 1 short paragraph when the content allows it.
        - \(responseDetail.outputGuidance)
        - Do not explain the argument, add examples, or describe why it matters.
        - Do not add background, labels, headings, bullets, or commentary.
        - Do not invent facts.

        OCR text:

        \(result.text)
        """

        Task {
            await runLocalTextAction(
                request: AIBackendRequest(
                    actionKind: .simplify,
                    prompt: prompt,
                    capturedImage: imageInput,
                    maxOutputTokens: responseDetail.maxOutputTokens(for: .simplify),
                    cloudOCRText: result.text,
                    cloudDetectedLanguage: cloudDetectedLanguage
                )
            )
        }
    }

    private func startExplain() {
        let imageInput = imageInput(for: .explain)
        loadingActions.insert(.explain)
        setOutputState(
            PanelActionOutputState(
                text: "Explaining...",
                sourceLabel: "Source: \(result.detectedLanguage.displayName)",
                targetLabel: nil,
                backendLabel: backendLabel(for: .explain, imageInput: imageInput),
                statistics: [],
                reasoning: nil,
                recovery: nil
            ),
            for: .explain
        )

        let prompt: String
        if imageInput == nil {
            prompt = """
            Explain the captured text clearly.

            Rules:
            - Return only the useful answer.
            - Use 1 to 2 short paragraphs or up to 4 bullets.
            - \(responseDetail.outputGuidance)
            - Explain the main point, relevant context, and why it matters.
            - Do not add background, labels, headings, or visual commentary.
            - Do not invent facts.

            \(result.text)
            """
        } else {
            prompt = """
            Explain this screenshot clearly.

            Rules:
            - Return only the useful answer.
            - Use 1 to 2 short paragraphs or up to 4 bullets.
            - \(responseDetail.outputGuidance)
            - Explain what the screenshot is saying, asking, or implying.
            - Include the relevant context and why it matters.
            - Mention visual context only if it changes the meaning.
            - Do not add background, labels, headings, or a play-by-play.
            - Do not invent facts.

            OCR text:
            \(result.text)
            """
        }

        Task {
            await runLocalTextAction(
                request: AIBackendRequest(
                    actionKind: .explain,
                    prompt: prompt,
                    capturedImage: imageInput,
                    maxOutputTokens: responseDetail.maxOutputTokens(for: .explain),
                    cloudOCRText: result.text,
                    cloudDetectedLanguage: cloudDetectedLanguage
                )
            )
        }
    }

    private func startDebug() {
        let imageInput = imageInput(for: .debug)
        loadingActions.insert(.debug)
        setOutputState(
            PanelActionOutputState(
                text: "Debugging...",
                sourceLabel: "Source: \(result.detectedLanguage.displayName)",
                targetLabel: nil,
                backendLabel: backendLabel(for: .debug, imageInput: imageInput),
                statistics: [],
                reasoning: nil,
                recovery: nil
            ),
            for: .debug
        )

        let evidence = result.technicalClassification.reasons.isEmpty
            ? "technical pattern"
            : result.technicalClassification.reasons.joined(separator: ", ")

        let prompt: String
        if imageInput == nil {
            prompt = """
            Debug the following captured technical text. Explain the likely issue, cite the relevant error or code clue, and suggest concrete next steps. \(responseDetail.outputGuidance) Avoid inventing missing project context.

            Classifier evidence: \(evidence)

            Captured text:
            \(result.text)
            """
        } else {
            prompt = """
            Debug this captured technical screenshot. Use both the OCR text and visible UI context, such as highlighted lines, terminal prompts, IDE panels, or error overlays. Explain the likely issue and suggest concrete next steps. \(responseDetail.outputGuidance) Avoid inventing missing project context.

            Classifier evidence: \(evidence)

            OCR text:
            \(result.text)
            """
        }

        Task {
            await runLocalTextAction(
                request: AIBackendRequest(
                    actionKind: .debug,
                    prompt: prompt,
                    capturedImage: imageInput,
                    maxOutputTokens: responseDetail.maxOutputTokens(for: .debug),
                    cloudOCRText: result.text,
                    cloudDetectedLanguage: cloudDetectedLanguage
                )
            )
        }
    }

    private func startAsk() {
        setOutputState(askOutputState(), for: .ask)
    }

    private var canSendAskQuestion: Bool {
        selectedAction == .ask
            && !loadingActions.contains(.ask)
            && !isPreparingAssistantImage
            && !askInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendAskQuestion() {
        let question = askInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !loadingActions.contains(.ask) else { return }
        let fileGrants = localFileAccess.grants
        let toolRouter = AssistantToolRouter()
        let toolEnvironment = AssistantToolEnvironment(
            hasCaptureContext: hasCaptureContext,
            routingMode: routingSettings.effectiveMode,
            selectedLocalModelRepositoryID: mlxModelStore.selectedModel?.repositoryID,
            localTextBackendLabel: localTextBackendLabel(),
            previousTurnReferencedModel: askTurns.last.map {
                Self.normalizedQuestion($0.question).contains("model")
                    || Self.normalizedQuestion($0.answer).contains("language model")
            } == true
        )

        if handlePendingTerminalCommandTextConfirmation(
            question: question,
            grants: fileGrants,
            toolRouter: toolRouter
        ) {
            return
        }

        if toolRouter.shouldPlanWriteWithModel(
            question: question,
            grants: fileGrants,
            toolState: assistantToolState
        ) {
            planLocalFileWriteWithModel(
                question: question,
                grants: fileGrants,
                toolRouter: toolRouter
            )
            return
        }

        if let preflight = toolRouter.preflight(
            question: question,
            grants: fileGrants,
            environment: toolEnvironment,
            toolState: assistantToolState,
            scope: .appOwnedOnly
        ) {
            handleAssistantToolPreflight(preflight, question: question)
            return
        }

        if shouldUseModelPlannedActionLoop(
            question: question,
            grants: fileGrants,
            toolState: assistantToolState
        ) {
            planAssistantActionLoopWithModel(
                question: question,
                grants: fileGrants,
                environment: toolEnvironment,
                toolRouter: toolRouter
            )
            return
        }

        if let terminalRequest = toolRouter.terminalCommandRequest(
            question: question,
            grants: fileGrants,
            toolState: assistantToolState
        ) {
            handleAssistantTerminalCommandRequest(
                terminalRequest,
                question: question,
                grants: fileGrants,
                toolRouter: toolRouter
            )
            return
        }

        if let fallbackPreflight = toolRouter.preflight(
            question: question,
            grants: fileGrants,
            environment: toolEnvironment,
            toolState: assistantToolState,
            scope: .full
        ) {
            handleAssistantToolPreflight(fallbackPreflight, question: question)
            return
        }

        let cloudModeEnabled = routingSettings.effectiveMode == .cloud
        let modelCapabilities = cloudModeEnabled
            ? AssistantModelCapabilities.cloud(from: AIBackendCapabilities(
                text: .available(.pixelPaneCloud),
                image: .available(.pixelPaneCloud),
                contextWindowTokens: nil,
                maxPromptCharacters: AIModelLimits.maxPromptCharacters,
                maxOutputTokens: AIModelLimits.defaultMaxOutputTokens
            ))
            : AssistantModelCapabilities.local(from: localAICapabilities)
        let hasCaptureContextValue = hasCaptureContext
        let attachedImageContext = assistantImageContext
        let hasAssistantImageContext = attachedImageContext != nil
        let hasAnyVisualContext = hasCaptureContextValue || hasAssistantImageContext
        let capturedOCRText = result.text
        let attachedImageOCRText = attachedImageContext?.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasReadableVisualText = !capturedOCRText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachedImageOCRText.isEmpty
        let preferredVisualImage = attachedImageContext?.image ?? result.image
        let askUsesMLX = !cloudModeEnabled
            && hasAnyVisualContext
            && modelCapabilities.supportsImageInput
            && preferredVisualImage != nil
        let cloudImageInput = cloudModeEnabled
            && hasAnyVisualContext
            && modelCapabilities.supportsImageInput
            ? preferredVisualImage
            : nil
        let imageInput = cloudModeEnabled
            ? cloudImageInput
            : (askUsesMLX ? preferredVisualImage : nil)
        let preferredProvider: AIBackendProvider? = askUsesMLX ? .mlxVision : nil
        let backendLabel = cloudModeEnabled
            ? Self.cloudBackendLabel
            : (askUsesMLX ? Self.mlxVisionBackendLabel : localTextBackendLabel())
        let isCaptureImageAttached = hasCaptureContextValue && imageInput != nil && attachedImageContext == nil
        let isAssistantImageAttached = attachedImageContext != nil && imageInput != nil
        let previousTurns = assistantContextPriorTurns()
        let previousTranscript = formattedAskTranscript()
        let detectedLanguage = cloudDetectedLanguage
        let conversation = cloudConversationTurns(beforeLastTurn: false)
        let isSimpleBriefPlainChat = responseDetail == .brief
            && !hasAnyVisualContext
            && previousTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !toolRouter.fileSearchDecision(
                question: question,
                grants: fileGrants,
                toolState: assistantToolState
            ).shouldSearch

        if hasAnyVisualContext,
           !cloudModeEnabled,
           imageInput == nil,
           !hasReadableVisualText,
           Self.questionReferencesCapture(question) {
            askInput = ""
            recoveryState = nil
            hiddenReasoning = nil
            outputStatistics = []
            actionBackendLabel = backendLabel
            askTurns.append(
                AskConversationTurn(
                    question: question,
                    answer: "I have visual context, but Local text mode did not get readable OCR from it and cannot inspect the pixels directly. Switch to Cloud Mode or set up a local vision model to ask visual questions about it.",
                    backendLabel: backendLabel
                )
            )
            persistAskSession()
            setOutputState(askOutputState(), for: .ask)
            focusChatInputSoon()
            return
        }

        askInput = ""
        isChatInputFocused = true
        loadingActions.insert(.ask)
        recoveryState = nil
        outputStatistics = []
        hiddenReasoning = nil
        actionBackendLabel = backendLabel
        askTurns.append(
            AskConversationTurn(
                question: question,
                answer: "",
                backendLabel: backendLabel
            )
        )
        persistAskSession()
        setOutputState(askOutputState(), for: .ask)
        updateExpandedNotchSizeIfNeeded()

        let toolStateBeforeRun = assistantToolState
        Task {
            let toolStateSnapshot = toolStateBeforeRun
            var updatedToolState = toolStateSnapshot
            var contextToolResults: [AssistantLocalFileToolResult] = []

            let contextualReadResult = toolRouter.contextualFileReadResult(
                question: question,
                grants: fileGrants,
                toolState: updatedToolState
            )
            if let contextualReadResult {
                updatedToolState.record(contextualReadResult)
                contextToolResults.append(contextualReadResult)
            }

            let shouldSearchFiles = toolRouter.fileSearchDecision(
                question: question,
                grants: fileGrants,
                toolState: updatedToolState
            ).shouldSearch
            let fileSearchQuestion = Self.enrichedFileSearchQuestion(
                question: question,
                previousTurns: previousTurns,
                toolState: updatedToolState
            )
            let searchResult = contextualReadResult == nil && shouldSearchFiles
                ? await Task.detached {
                    toolRouter.localFileSearchResult(
                        question: fileSearchQuestion,
                        grants: fileGrants,
                        toolState: updatedToolState
                    )
                }.value
                : nil
            if let searchResult {
                updatedToolState.record(searchResult)
                contextToolResults.append(searchResult)
            }
            let localFileContext = Self.mergedLocalFileContext(
                grants: fileGrants,
                results: contextToolResults
            )
            if let attachedImageContext {
                updatedToolState.updateVisualContext(
                    AssistantVisualContextState(
                        imageContext: attachedImageContext,
                        imageWillBeSent: isAssistantImageAttached
                    )
                )
            } else {
                updatedToolState.updateVisualContext(
                    Self.captureVisualState(for: result, imageWillBeSent: isCaptureImageAttached)
                )
            }
            let packedContext = AssistantContextPacker().pack(
                AssistantContextPackingInput(
                    question: question,
                    responseDetail: responseDetail,
                    responseGuidance: responseDetail.outputGuidance,
                    modelCapabilities: modelCapabilities,
                    hasCaptureContext: hasCaptureContextValue,
                    capturedOCRText: capturedOCRText,
                    isCaptureImageAttached: isCaptureImageAttached,
                    assistantImageContext: attachedImageContext,
                    isAssistantImageAttached: isAssistantImageAttached,
                    previousTurns: previousTurns,
                    localFileContext: localFileContext,
                    toolState: updatedToolState,
                    usesCloud: cloudModeEnabled
                )
            )
            await MainActor.run {
                assistantToolState = updatedToolState
                persistAskSession()
            }
            await runAskTurn(
                request: AIBackendRequest(
                    actionKind: hasAnyVisualContext ? .ask : .chat,
                    prompt: packedContext.prompt,
                    capturedImage: imageInput,
                    maxOutputTokens: Self.askMaxOutputTokens(
                        responseDetail: responseDetail,
                        question: question,
                        hasCaptureContext: hasAnyVisualContext,
                        hasFileContext: localFileContext.hasSnippets,
                        hasPreviousTranscript: !previousTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        isSimpleBriefPlainChat: isSimpleBriefPlainChat
                    ),
                    preferredProvider: preferredProvider,
                    cloudOCRText: cloudModeEnabled
                        ? (packedContext.cloudContext.isEmpty ? nil : packedContext.cloudContext)
                        : (hasAnyVisualContext && !packedContext.cloudContext.isEmpty ? packedContext.cloudContext : nil),
                    cloudDetectedLanguage: hasCaptureContextValue ? detectedLanguage : nil,
                    cloudQuestion: question,
                    cloudConversation: conversation
                )
            )
        }
    }

    private func handlePendingTerminalCommandTextConfirmation(
        question: String,
        grants: [LocalFileGrant],
        toolRouter: AssistantToolRouter
    ) -> Bool {
        guard let proposal = pendingTerminalCommandProposal else { return false }
        let normalized = Self.normalizedQuestion(question)
        if Self.isTerminalConfirmation(normalized) {
            pendingTerminalCommandProposal = nil
            runTerminalCommand(
                proposal,
                question: "Allow terminal in \(URL(fileURLWithPath: proposal.workingDirectory).lastPathComponent): \(proposal.reason)",
                grants: grants,
                toolRouter: toolRouter
            )
            return true
        }
        if Self.isTerminalRejection(normalized) {
            cancelTerminalCommand()
            return true
        }
        return false
    }

    private static func isTerminalConfirmation(_ normalized: String) -> Bool {
        let words = normalized.split(separator: " ").map(String.init)
        guard (1...6).contains(words.count) else { return false }
        let confirmations: Set<String> = ["yes", "yeah", "yep", "sure", "ok", "okay", "confirm", "allow", "run", "do", "proceed"]
        return words.contains { confirmations.contains($0) }
    }

    private static func isTerminalRejection(_ normalized: String) -> Bool {
        let words = normalized.split(separator: " ").map(String.init)
        guard (1...6).contains(words.count) else { return false }
        let rejections: Set<String> = ["no", "nope", "cancel", "stop", "dont", "don't"]
        return words.contains { rejections.contains($0) }
    }

    private func shouldUseModelPlannedActionLoop(
        question: String,
        grants: [LocalFileGrant],
        toolState: AssistantToolState
    ) -> Bool {
        let normalized = Self.normalizedQuestion(question)
        guard !normalized.isEmpty else { return false }
        let lowValue = Set(["hi", "hello", "thanks", "thank you", "ok", "okay"])
        if lowValue.contains(normalized) { return false }

        if !grants.isEmpty {
            return true
        }

        let hasRecentToolContext = !toolState.recentToolResults.isEmpty
            || toolState.lastListedFolder != nil
            || !toolState.lastFileSources.isEmpty
        if hasRecentToolContext {
            return true
        }

        return normalized.contains("`") || normalized.hasPrefix("$ ")
    }

    private func planAssistantActionLoopWithModel(
        question: String,
        grants: [LocalFileGrant],
        environment: AssistantToolEnvironment,
        toolRouter: AssistantToolRouter
    ) {
        let cloudModeEnabled = routingSettings.effectiveMode == .cloud
        let backendLabel = cloudModeEnabled ? Self.cloudBackendLabel : localTextBackendLabel()
        let priorTurns = assistantContextPriorTurns()

        askInput = ""
        isChatInputFocused = true
        pendingLocalFileWriteProposal = nil
        pendingTerminalCommandProposal = nil
        recoveryState = nil
        hiddenReasoning = nil
        outputStatistics = []
        actionBackendLabel = backendLabel
        loadingActions.insert(.ask)
        askTurns.append(
            AskConversationTurn(
                question: question,
                answer: "",
                backendLabel: backendLabel
            )
        )
        persistAskSession()
        setOutputState(askOutputState(), for: .ask)
        updateExpandedNotchSizeIfNeeded()

        let initialToolState = assistantToolState
        Task {
            var loopToolState = initialToolState
            var observations: [AssistantLocalFileToolResult] = []
            let builder = AssistantActionPlanningPromptBuilder()
            let parser = AssistantActionPlanParser()

            for step in 0..<2 {
                let prompt = builder.prompt(
                    question: question,
                    grants: grants,
                    toolState: loopToolState,
                    observations: observations,
                    priorTurns: priorTurns
                )

                let rawPlan: String
                do {
                    rawPlan = try await generatedActionPlanText(prompt: prompt)
                } catch {
                    await runDeterministicFallbackAfterActionPlanningFailure(
                        question: question,
                        grants: grants,
                        environment: environment,
                        toolRouter: toolRouter,
                        backendLabel: backendLabel,
                        fallbackMessage: "I could not ask the selected model to plan that action: \(error.localizedDescription)"
                    )
                    return
                }

                guard let plan = parser.parse(rawPlan) else {
                    let fallbackAnswer = rawPlan.trimmingCharacters(in: .whitespacesAndNewlines)
                    await runDeterministicFallbackAfterActionPlanningFailure(
                        question: question,
                        grants: grants,
                        environment: environment,
                        toolRouter: toolRouter,
                        backendLabel: backendLabel,
                        fallbackMessage: fallbackAnswer.isEmpty
                            ? "The selected model did not return a safe action plan. Try asking with the target folder, file, or command more explicitly."
                            : fallbackAnswer
                    )
                    return
                }

                switch plan.action.kind {
                case .answerDirectly:
                    await MainActor.run {
                        finishModelPlannedAction(
                            question: question,
                            answer: plan.action.finalAnswer ?? "I do not need a local tool for that.",
                            backendLabel: backendLabel
                        )
                    }
                    return
                case .listGrants:
                    let result = toolRouter.localGrantListResult(grants: grants)
                    loopToolState.record(result)
                    observations.append(result)
                    if step == 1 {
                        await MainActor.run {
                            finishModelPlannedAction(
                                question: question,
                                answer: result.summary,
                                backendLabel: "Local Files",
                                toolResult: result
                            )
                        }
                        return
                    }
                case .listFolder:
                    let result = toolRouter.localFolderListResult(
                        path: plan.action.arguments["path"],
                        grants: grants
                    )
                    loopToolState.record(result)
                    observations.append(result)
                    if step == 1 {
                        await MainActor.run {
                            finishModelPlannedAction(
                                question: question,
                                answer: result.summary,
                                backendLabel: "Local Files",
                                toolResult: result
                            )
                        }
                        return
                    }
                case .profileFolder:
                    let result = toolRouter.localFolderProfileResult(
                        question: question,
                        path: plan.action.arguments["path"],
                        grants: grants,
                        toolState: loopToolState
                    )
                    loopToolState.record(result)
                    observations.append(result)
                    await MainActor.run {
                        finishModelPlannedAction(
                            question: question,
                            answer: result.summary,
                            backendLabel: "Local Files",
                            toolResult: result
                        )
                    }
                    return
                case .searchFiles:
                    let query = plan.action.arguments["query"] ?? question
                    let result = toolRouter.localFileSearchResult(
                        question: query,
                        grants: grants,
                        toolState: loopToolState
                    )
                    loopToolState.record(result)
                    observations.append(result)
                    if step == 1 {
                        await MainActor.run {
                            finishModelPlannedAction(
                                question: question,
                                answer: result.summary,
                                backendLabel: "Local Files",
                                toolResult: result
                            )
                        }
                        return
                    }
                case .readFile:
                    guard let path = plan.action.arguments["path"], !path.isEmpty else {
                        await MainActor.run {
                            finishModelPlannedAction(
                                question: question,
                                answer: "The selected model asked to read a file but did not provide a path.",
                                backendLabel: backendLabel
                            )
                        }
                        return
                    }
                    let result = toolRouter.localFileReadResult(
                        path: path,
                        grants: grants,
                        focusQuestion: question
                    )
                    loopToolState.record(result)
                    observations.append(result)
                    if step == 1 {
                        await MainActor.run {
                            finishModelPlannedAction(
                                question: question,
                                answer: Self.localFileReadAnswer(from: result),
                                backendLabel: "Local Files",
                                toolResult: result
                            )
                        }
                        return
                    }
                case .stageWriteProposal:
                    let result = modelPlannedWriteResult(
                        from: plan.action,
                        question: question,
                        grants: grants,
                        toolState: loopToolState,
                        toolRouter: toolRouter
                    )
                    await MainActor.run {
                        finishModelPlannedWrite(
                            question: question,
                            answer: Self.modelPlannedWriteAnswer(from: result),
                            backendLabel: "Local Files",
                            toolResult: result
                        )
                    }
                    return
                case .runTerminalCommand:
                    await handleModelPlannedTerminalAction(
                        plan.action,
                        question: question,
                        grants: grants,
                        toolState: loopToolState,
                        toolRouter: toolRouter,
                        backendLabel: backendLabel
                    )
                    return
                }
            }

            await MainActor.run {
                finishModelPlannedAction(
                    question: question,
                    answer: "The selected model inspected available context but did not produce a final safe action.",
                    backendLabel: backendLabel
                )
            }
        }
    }

    private func generatedActionPlanText(prompt: String) async throws -> String {
        var latestText = ""
        let request = AIBackendRequest(
            actionKind: .chat,
            prompt: prompt,
            maxOutputTokens: 1_024,
            cloudOCRText: prompt,
            cloudQuestion: "Return only the JSON object for this Pixel Pane action plan."
        )
        for try await event in selectedAIBackend.streamResponse(for: request) {
            switch event {
            case .metadata(let statistics):
                await MainActor.run {
                    updateLastAskStatistics(statistics)
                }
            case .snapshot(let text):
                latestText = text
            case .output(let output):
                latestText = output.finalText
                await MainActor.run {
                    updateLastAskStatistics(output.statistics)
                }
            case .completed:
                break
            }
        }
        return latestText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runDeterministicFallbackAfterActionPlanningFailure(
        question: String,
        grants: [LocalFileGrant],
        environment: AssistantToolEnvironment,
        toolRouter: AssistantToolRouter,
        backendLabel: String,
        fallbackMessage: String
    ) async {
        if let preflight = toolRouter.preflight(
            question: question,
            grants: grants,
            environment: environment,
            toolState: assistantToolState,
            scope: .full
        ) {
            await MainActor.run {
                finishModelPlannedPreflight(preflight, question: question)
            }
            return
        }

        if let terminalRequest = toolRouter.terminalCommandRequest(
            question: question,
            grants: grants,
            toolState: assistantToolState
        ) {
            await finishTerminalRequestInCurrentTurn(
                terminalRequest,
                question: question,
                grants: grants,
                toolRouter: toolRouter
            )
            return
        }

        await MainActor.run {
            finishModelPlannedAction(
                question: question,
                answer: fallbackMessage,
                backendLabel: backendLabel
            )
        }
    }

    private func finishModelPlannedPreflight(
        _ preflight: AssistantToolPreflightResult,
        question: String
    ) {
        switch preflight {
        case .directAnswer(let answer, let backendLabel, let toolResult):
            finishModelPlannedAction(
                question: question,
                answer: answer,
                backendLabel: backendLabel,
                toolResult: toolResult
            )
        case .localFileWriteMessage(let message, let toolResult):
            finishModelPlannedAction(
                question: question,
                answer: message,
                backendLabel: "Local Files",
                toolResult: toolResult
            )
        case .localFileWriteProposal(let proposal, let toolResult):
            pendingLocalFileWriteProposal = proposal
            pendingTerminalCommandProposal = nil
            finishModelPlannedAction(
                question: question,
                answer: "I can propose this local file change. Confirm below before I write anything:\n\n\(proposal.detailText)",
                backendLabel: "Local Files",
                toolResult: toolResult
            )
        }
    }

    private func modelPlannedWriteResult(
        from action: AssistantPlannedAction,
        question: String,
        grants: [LocalFileGrant],
        toolState: AssistantToolState,
        toolRouter: AssistantToolRouter
    ) -> AssistantLocalFileToolResult {
        if let targetPath = action.arguments["target_path"] ?? action.arguments["targetPath"] ?? action.arguments["path"],
           let content = action.arguments["content"],
           !targetPath.isEmpty,
           !content.isEmpty {
            let rawOperation = (action.arguments["operation"] ?? "create").lowercased()
            let operation: AssistantGeneratedWriteDraft.Operation
            if rawOperation.contains("append") {
                operation = .append
            } else if rawOperation.contains("replace")
                || rawOperation.contains("update")
                || rawOperation.contains("edit") {
                operation = .replace
            } else {
                operation = .create
            }
            return toolRouter.generatedWriteProposal(
                from: AssistantGeneratedWriteDraft(
                    operation: operation,
                    targetPath: targetPath,
                    content: content
                ),
                question: question,
                grants: grants,
                toolState: toolState
            )
        }
        return toolRouter.localFileWriteProposalResult(
            question: question,
            grants: grants,
            toolState: toolState
        )
    }

    private func handleModelPlannedTerminalAction(
        _ action: AssistantPlannedAction,
        question: String,
        grants: [LocalFileGrant],
        toolState: AssistantToolState,
        toolRouter: AssistantToolRouter,
        backendLabel: String
    ) async {
        guard let command = action.arguments["command"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty else {
            await MainActor.run {
                finishModelPlannedAction(
                    question: question,
                    answer: "The selected model asked to run a terminal command but did not provide a command.",
                    backendLabel: backendLabel
                )
            }
            return
        }

        let intent = Self.plannedTerminalIntent(from: action.arguments)
        let workingDirectory = modelPlannedWorkingDirectory(
            from: action.arguments["working_directory"] ?? action.arguments["workingDirectory"],
            intent: intent,
            grants: grants,
            toolState: toolState
        )
        let timeoutSeconds = Self.plannedTerminalTimeout(from: action.arguments["timeout_seconds"])
        let reason = action.arguments["reason"] ?? action.reason ?? "The selected model planned this terminal action."
        let request = toolRouter.terminalCommandRequest(
            command: Self.sanitizedModelPlannedTerminalCommand(command, intent: intent),
            workingDirectory: workingDirectory,
            reason: reason,
            timeoutSeconds: timeoutSeconds,
            intent: intent
        )
        await finishTerminalRequestInCurrentTurn(
            request,
            question: question,
            grants: grants,
            toolRouter: toolRouter
        )
    }

    private func finishTerminalRequestInCurrentTurn(
        _ request: AssistantTerminalCommandRequest,
        question: String,
        grants: [LocalFileGrant],
        toolRouter: AssistantToolRouter
    ) async {
        switch request {
        case .message(let message):
            await MainActor.run {
                finishModelPlannedAction(
                    question: question,
                    answer: message,
                    backendLabel: "Terminal"
                )
            }
        case .proposal(let proposal):
            if proposal.requiresConfirmation {
                await MainActor.run {
                    finishModelPlannedTerminalConfirmation(
                        question: question,
                        proposal: proposal
                    )
                }
            } else {
                let result = await toolRouter.runTerminalCommand(proposal, grants: grants)
                await MainActor.run {
                    finishModelPlannedAction(
                        question: question,
                        answer: Self.terminalAnswer(from: result),
                        backendLabel: "Terminal",
                        toolResult: result
                    )
                }
            }
        case .proposals(let proposals):
            guard let proposal = proposals.first else {
                await MainActor.run {
                    finishModelPlannedAction(
                        question: question,
                        answer: "The selected model did not produce a terminal command to run.",
                        backendLabel: "Terminal"
                    )
                }
                return
            }
            if proposal.requiresConfirmation {
                await MainActor.run {
                    finishModelPlannedTerminalConfirmation(
                        question: question,
                        proposal: proposal
                    )
                }
            } else {
                let result = await toolRouter.runTerminalCommand(proposal, grants: grants)
                await MainActor.run {
                    finishModelPlannedAction(
                        question: question,
                        answer: Self.terminalAnswer(from: result),
                        backendLabel: "Terminal",
                        toolResult: result
                    )
                }
            }
        }
    }

    private func modelPlannedWorkingDirectory(
        from proposedPath: String?,
        intent: AssistantTerminalCommandIntent,
        grants: [LocalFileGrant],
        toolState: AssistantToolState
    ) -> String {
        let activeFolders = grants.filter { $0.isDirectory && FileManager.default.fileExists(atPath: $0.path) }
        if let proposedPath,
           !proposedPath.isEmpty {
            let standardized = URL(fileURLWithPath: proposedPath).standardizedFileURL.path
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory),
               isDirectory.boolValue {
                if intent == .systemInspection
                    || activeFolders.isEmpty
                    || activeFolders.contains(where: { Self.isPath(standardized, inside: $0.path) }) {
                    return standardized
                }
            }
        }

        if let recentTerminalDirectory = toolState.recentToolResults.compactMap(\.terminalWorkingDirectory).first,
           FileManager.default.fileExists(atPath: recentTerminalDirectory) {
            return recentTerminalDirectory
        }
        if let listedFolder = toolState.lastListedFolder?.path,
           FileManager.default.fileExists(atPath: listedFolder) {
            return listedFolder
        }
        if let folder = activeFolders.first {
            return folder.path
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    private static func plannedTerminalIntent(from arguments: [String: String]) -> AssistantTerminalCommandIntent {
        let raw = (arguments["intent"] ?? "").lowercased()
        if raw.contains("file") || raw.contains("search") {
            return .fileSearch
        }
        if raw.contains("system") || raw.contains("inspection") || raw.contains("port") {
            return .systemInspection
        }
        return .generic
    }

    private static func plannedTerminalTimeout(from value: String?) -> TimeInterval {
        guard let value,
              let seconds = Double(value) else {
            return 120
        }
        return min(600, max(15, seconds))
    }

    private static func sanitizedModelPlannedTerminalCommand(
        _ command: String,
        intent: AssistantTerminalCommandIntent
    ) -> String {
        guard intent == .systemInspection else { return command }
        let normalized = normalizedQuestion(command)
        if normalized.contains("ps aux --sort") || normalized.contains("ps -aux --sort") {
            if normalized.contains("%mem") || normalized.contains("memory") {
                return "ps aux | sort -nrk 4 | head -n 15"
            }
            return "ps aux | sort -nrk 3 | head -n 15"
        }
        return command
    }

    private func finishModelPlannedTerminalConfirmation(
        question: String,
        proposal: AssistantTerminalCommandProposal
    ) {
        pendingLocalFileWriteProposal = nil
        pendingTerminalCommandProposal = proposal
        finishModelPlannedAction(
            question: question,
            answer: "I need your permission to run a terminal command in `\(URL(fileURLWithPath: proposal.workingDirectory).lastPathComponent)`.\n\n\(proposal.reason)",
            backendLabel: "Terminal"
        )
    }

    private func finishModelPlannedAction(
        question: String,
        answer: String,
        backendLabel: String,
        toolResult: AssistantLocalFileToolResult? = nil
    ) {
        if let toolResult {
            assistantToolState.record(toolResult)
        }
        if backendLabel != "Terminal" {
            pendingTerminalCommandProposal = nil
        }
        if backendLabel != "Local Files" {
            pendingLocalFileWriteProposal = nil
        }
        if let index = askTurns.indices.last {
            askTurns[index] = AskConversationTurn(
                question: question,
                answer: answer,
                backendLabel: backendLabel,
                statistics: askTurns[index].statistics
            )
        } else {
            askTurns.append(
                AskConversationTurn(
                    question: question,
                    answer: answer,
                    backendLabel: backendLabel
                )
            )
        }
        loadingActions.remove(.ask)
        actionBackendLabel = backendLabel
        persistAskSession()
        setOutputState(askOutputState(), for: .ask)
        updateExpandedNotchSizeIfNeeded()
        focusChatInputSoon()
    }

    private static func isPath(_ path: String, inside rootPath: String) -> Bool {
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.path
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        if candidate == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return candidate.hasPrefix(prefix)
    }

    private func handleAssistantToolPreflight(_ preflight: AssistantToolPreflightResult, question: String) {
        switch preflight {
        case .directAnswer(let answer, let backendLabel, let toolResult):
            if let toolResult {
                assistantToolState.record(toolResult)
            }
            appendDirectAskAnswer(question: question, answer: answer, backendLabel: backendLabel)
        case .localFileWriteMessage(let message, let toolResult):
            if let toolResult {
                assistantToolState.record(toolResult)
            }
            appendDirectAskAnswer(question: question, answer: message, backendLabel: "Local Files")
        case .localFileWriteProposal(let proposal, let toolResult):
            if let toolResult {
                assistantToolState.record(toolResult)
            }
            askInput = ""
            pendingTerminalCommandProposal = nil
            recoveryState = nil
            hiddenReasoning = nil
            outputStatistics = []
            pendingLocalFileWriteProposal = proposal
            askTurns.append(
                AskConversationTurn(
                    question: question,
                    answer: "I can propose this local file change. Confirm below before I write anything:\n\n\(proposal.detailText)",
                    backendLabel: "Local Files"
                )
            )
            persistAskSession()
            setOutputState(askOutputState(), for: .ask)
            focusChatInputSoon()
        }
    }

    private func planLocalFileWriteWithModel(
        question: String,
        grants: [LocalFileGrant],
        toolRouter: AssistantToolRouter
    ) {
        let cloudModeEnabled = routingSettings.effectiveMode == .cloud
        let backendLabel = cloudModeEnabled ? Self.cloudBackendLabel : localTextBackendLabel()
        let priorTurns = assistantContextPriorTurns()
        var planningToolState = assistantToolState
        if let readResult = toolRouter.contextualFileReadResult(
            question: question,
            grants: grants,
            toolState: planningToolState
        ) {
            planningToolState.record(readResult)
            assistantToolState = planningToolState
        }
        let prompt = AssistantWritePlanningPromptBuilder().prompt(
            question: question,
            grants: grants,
            toolState: planningToolState,
            priorTurns: priorTurns
        )

        askInput = ""
        isChatInputFocused = true
        pendingLocalFileWriteProposal = nil
        pendingTerminalCommandProposal = nil
        recoveryState = nil
        hiddenReasoning = nil
        outputStatistics = []
        actionBackendLabel = backendLabel
        loadingActions.insert(.ask)
        askTurns.append(
            AskConversationTurn(
                question: question,
                answer: "",
                backendLabel: backendLabel
            )
        )
        persistAskSession()
        setOutputState(askOutputState(), for: .ask)
        updateExpandedNotchSizeIfNeeded()

        let toolStateBeforeRun = planningToolState
        Task {
            do {
                let generated = try await generatedWriteDraftText(
                    prompt: prompt
                )
                let parser = AssistantGeneratedWriteDraftParser()
                guard let draft = parser.parse(generated) else {
                    await MainActor.run {
                        finishModelPlannedWrite(
                            question: question,
                            answer: "The selected model did not return a safe file-write plan. Try again with a filename, folder, or shorter requested content.",
                            backendLabel: backendLabel,
                            toolResult: nil
                        )
                    }
                    return
                }

                let toolResult = toolRouter.generatedWriteProposal(
                    from: draft,
                    question: question,
                    grants: grants,
                    toolState: toolStateBeforeRun
                )
                await MainActor.run {
                    finishModelPlannedWrite(
                        question: question,
                        answer: Self.modelPlannedWriteAnswer(from: toolResult),
                        backendLabel: "Local Files",
                        toolResult: toolResult
                    )
                }
            } catch {
                await MainActor.run {
                    finishModelPlannedWrite(
                        question: question,
                        answer: "I could not ask the selected model to plan that file change: \(error.localizedDescription)",
                        backendLabel: backendLabel,
                        toolResult: nil
                    )
                }
            }
        }
    }

    private func generatedWriteDraftText(
        prompt: String
    ) async throws -> String {
        var latestText = ""
        let request = AIBackendRequest(
            actionKind: .chat,
            prompt: prompt,
            maxOutputTokens: AIModelLimits.defaultMaxOutputTokens,
            cloudOCRText: prompt,
            cloudQuestion: "Return only the JSON object for this local file-write plan."
        )
        for try await event in selectedAIBackend.streamResponse(for: request) {
            switch event {
            case .metadata(let statistics):
                await MainActor.run {
                    updateLastAskStatistics(statistics)
                }
            case .snapshot(let text):
                latestText = text
            case .output(let output):
                latestText = output.finalText
                await MainActor.run {
                    updateLastAskStatistics(output.statistics)
                }
            case .completed:
                break
            }
        }
        return latestText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finishModelPlannedWrite(
        question: String,
        answer: String,
        backendLabel: String,
        toolResult: AssistantLocalFileToolResult?
    ) {
        if let toolResult {
            assistantToolState.record(toolResult)
            if case .proposal(let proposal)? = toolResult.writeProposalResult {
                pendingLocalFileWriteProposal = proposal
                pendingTerminalCommandProposal = nil
            }
        }
        if let index = askTurns.indices.last {
            askTurns[index] = AskConversationTurn(
                question: question,
                answer: answer,
                backendLabel: backendLabel,
                statistics: askTurns[index].statistics
            )
        }
        loadingActions.remove(.ask)
        actionBackendLabel = backendLabel
        persistAskSession()
        setOutputState(askOutputState(), for: .ask)
        updateExpandedNotchSizeIfNeeded()
        focusChatInputSoon()
    }

    private static func modelPlannedWriteAnswer(
        from toolResult: AssistantLocalFileToolResult
    ) -> String {
        switch toolResult.writeProposalResult {
        case .proposal(let proposal)?:
            return "I planned this local file change with the selected model. Confirm below before I write anything:\n\n\(proposal.detailText)"
        case .message(let message)?:
            return message
        case .none?, nil:
            return "The selected model did not produce a local file change to stage."
        }
    }

    private func handleAssistantTerminalCommandRequest(
        _ request: AssistantTerminalCommandRequest,
        question: String,
        grants: [LocalFileGrant],
        toolRouter: AssistantToolRouter
    ) {
        switch request {
        case .message(let message):
            appendDirectAskAnswer(question: question, answer: message, backendLabel: "Terminal")
        case .proposals(let proposals):
            guard !proposals.isEmpty else {
                appendDirectAskAnswer(question: question, answer: "I could not infer a terminal command to run.", backendLabel: "Terminal")
                return
            }
            if proposals.allSatisfy({ !$0.requiresConfirmation }) {
                runTerminalCommands(
                    proposals,
                    question: question,
                    grants: grants,
                    toolRouter: toolRouter
                )
            } else if let first = proposals.first(where: { $0.requiresConfirmation }) {
                askInput = ""
                pendingLocalFileWriteProposal = nil
                pendingTerminalCommandProposal = first
                recoveryState = nil
                hiddenReasoning = nil
                outputStatistics = []
                askTurns.append(
                    AskConversationTurn(
                        question: question,
                        answer: "I need your permission to run a terminal command in `\(URL(fileURLWithPath: first.workingDirectory).lastPathComponent)`.\n\n\(first.reason)",
                        backendLabel: "Terminal"
                    )
                )
                persistAskSession()
                setOutputState(askOutputState(), for: .ask)
                updateExpandedNotchSizeIfNeeded()
                focusChatInputSoon()
            }
        case .proposal(let proposal):
            if proposal.requiresConfirmation {
                askInput = ""
                pendingLocalFileWriteProposal = nil
                recoveryState = nil
                hiddenReasoning = nil
                outputStatistics = []
                pendingTerminalCommandProposal = proposal
                askTurns.append(
                    AskConversationTurn(
                        question: question,
                        answer: "I need your permission to run a terminal command in `\(URL(fileURLWithPath: proposal.workingDirectory).lastPathComponent)`.\n\n\(proposal.reason)",
                        backendLabel: "Terminal"
                    )
                )
                persistAskSession()
                setOutputState(askOutputState(), for: .ask)
                updateExpandedNotchSizeIfNeeded()
                focusChatInputSoon()
            } else {
                runTerminalCommand(
                    proposal,
                    question: question,
                    grants: grants,
                    toolRouter: toolRouter
                )
            }
        }
    }

    private func runTerminalCommands(
        _ proposals: [AssistantTerminalCommandProposal],
        question: String,
        grants: [LocalFileGrant],
        toolRouter: AssistantToolRouter
    ) {
        askInput = ""
        isChatInputFocused = true
        pendingLocalFileWriteProposal = nil
        recoveryState = nil
        hiddenReasoning = nil
        outputStatistics = []
        actionBackendLabel = "Terminal"
        loadingActions.insert(.ask)
        askTurns.append(
            AskConversationTurn(
                question: question,
                answer: "",
                backendLabel: "Terminal"
            )
        )
        persistAskSession()
        setOutputState(askOutputState(), for: .ask)
        updateExpandedNotchSizeIfNeeded()

        Task {
            var results: [AssistantLocalFileToolResult] = []
            for proposal in proposals {
                let result = await toolRouter.runTerminalCommand(proposal, grants: grants)
                results.append(result)
            }
            await MainActor.run {
                for result in results {
                    assistantToolState.record(result)
                }
                let answer = Self.terminalBatchAnswer(from: results)
                if let index = askTurns.indices.last {
                    askTurns[index] = AskConversationTurn(
                        question: askTurns[index].question,
                        answer: answer,
                        backendLabel: "Terminal"
                    )
                }
                loadingActions.remove(.ask)
                actionBackendLabel = "Terminal"
                persistAskSession()
                setOutputState(askOutputState(), for: .ask)
                updateExpandedNotchSizeIfNeeded()
                focusChatInputSoon()
            }
        }
    }

    private func runTerminalCommand(
        _ proposal: AssistantTerminalCommandProposal,
        question: String,
        grants: [LocalFileGrant],
        toolRouter: AssistantToolRouter
    ) {
        askInput = ""
        isChatInputFocused = true
        pendingLocalFileWriteProposal = nil
        recoveryState = nil
        hiddenReasoning = nil
        outputStatistics = []
        actionBackendLabel = "Terminal"
        loadingActions.insert(.ask)
        askTurns.append(
            AskConversationTurn(
                question: question,
                answer: "",
                backendLabel: "Terminal"
            )
        )
        persistAskSession()
        setOutputState(askOutputState(), for: .ask)
        updateExpandedNotchSizeIfNeeded()

        let toolStateSnapshot = assistantToolState
        Task {
            let toolResult = await toolRouter.runTerminalCommand(proposal, grants: grants)
            let continuation = await Self.processTerminationContinuation(
                after: toolResult,
                question: question,
                grants: grants,
                toolState: toolStateSnapshot,
                toolRouter: toolRouter
            )
            await MainActor.run {
                assistantToolState.record(toolResult)
                if let inspection = continuation?.inspection {
                    assistantToolState.record(inspection)
                }
                if let pendingProposal = continuation?.pendingProposal {
                    pendingTerminalCommandProposal = pendingProposal
                }
                let answer = continuation?.answer ?? Self.terminalAnswer(from: toolResult)
                if let index = askTurns.indices.last {
                    askTurns[index] = AskConversationTurn(
                        question: askTurns[index].question,
                        answer: answer,
                        backendLabel: "Terminal"
                    )
                }
                loadingActions.remove(.ask)
                actionBackendLabel = "Terminal"
                persistAskSession()
                setOutputState(askOutputState(), for: .ask)
                updateExpandedNotchSizeIfNeeded()
                focusChatInputSoon()
            }
        }
    }

    private struct TerminalContinuation {
        let answer: String
        let inspection: AssistantLocalFileToolResult?
        let pendingProposal: AssistantTerminalCommandProposal?
    }

    private static func processTerminationContinuation(
        after result: AssistantLocalFileToolResult,
        question: String,
        grants: [LocalFileGrant],
        toolState: AssistantToolState,
        toolRouter: AssistantToolRouter
    ) async -> TerminalContinuation? {
        guard let terminal = result.terminalResult,
              isFailedProcessTermination(terminal) else {
            return nil
        }
        guard let port = referencedLocalhostPort(question: question, toolState: toolState, currentResult: result) else {
            return nil
        }

        let inspectionRequest = toolRouter.terminalCommandRequest(
            command: "lsof -nP -iTCP:\(port) -sTCP:LISTEN",
            workingDirectory: terminal.workingDirectory,
            reason: "Check which process is currently listening on port \(port) after the previous process ID was not running.",
            timeoutSeconds: 15,
            intent: .systemInspection
        )
        guard case .proposal(let inspectionProposal) = inspectionRequest,
              !inspectionProposal.requiresConfirmation else {
            return nil
        }

        let inspection = await toolRouter.runTerminalCommand(inspectionProposal, grants: grants)
        let pids = listenerPIDs(from: inspection.terminalResult?.stdout ?? "")
        guard !pids.isEmpty else {
            let answer = """
            The previous process ID was not running, so I checked port \(port) next.

            I did not find any current listener on `localhost:\(port)`.

            Previous error:
            ```
            \(terminal.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            ```
            """
            return TerminalContinuation(answer: answer, inspection: inspection, pendingProposal: nil)
        }

        let killCommand = "kill \(pids.joined(separator: " "))"
        let killRequest = toolRouter.terminalCommandRequest(
            command: killCommand,
            workingDirectory: terminal.workingDirectory,
            reason: "Kill the process currently listening on port \(port) after the previous PID was stale.",
            timeoutSeconds: 15,
            intent: .generic
        )
        guard case .proposal(let killProposal) = killRequest else {
            return nil
        }

        let answer = """
        The previous PID was not running, so I checked port \(port) and found current listener PID\(pids.count == 1 ? "" : "s") \(pids.joined(separator: ", ")).

        I need your permission to kill the process\(pids.count == 1 ? "" : "es") currently listening on `localhost:\(port)`.

        Inspection output:
        ```
        \((inspection.terminalResult?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        ```
        """
        return TerminalContinuation(answer: answer, inspection: inspection, pendingProposal: killProposal)
    }

    private static func isFailedProcessTermination(_ terminal: AssistantTerminalCommandResult) -> Bool {
        let normalizedCommand = terminal.command.lowercased()
        let normalizedError = terminal.stderr.lowercased()
        guard terminal.exitCode != 0 else { return false }
        return (normalizedCommand.hasPrefix("kill ")
            || normalizedCommand.contains(" kill ")
            || normalizedCommand.contains("xargs kill")
            || normalizedCommand.hasPrefix("pkill ")
            || normalizedCommand.hasPrefix("killall "))
            && (normalizedError.contains("no such process") || normalizedError.contains("illegal pid"))
    }

    private static func referencedLocalhostPort(
        question: String,
        toolState: AssistantToolState,
        currentResult: AssistantLocalFileToolResult
    ) -> String? {
        let texts = [question, currentResult.terminalResult?.stdout, currentResult.terminalResult?.stderr]
            .compactMap { $0 } + toolState.recentToolResults.flatMap { result in
                [result.terminalStdout, result.terminalStderr, result.terminalCommand].compactMap { $0 }
            }
        for text in texts {
            if let port = firstPort(in: text) {
                return port
            }
        }
        return nil
    }

    private static func firstPort(in text: String) -> String? {
        let patterns = [
            #"(?i)\bport\s+([0-9]{2,5})\b"#,
            #"(?i)(?:localhost|127\.0\.0\.1|\*):([0-9]{2,5})\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let portRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let port = String(text[portRange])
            guard let value = Int(port), (1...65_535).contains(value) else { continue }
            return port
        }
        return nil
    }

    private static func listenerPIDs(from lsofOutput: String) -> [String] {
        var seen: Set<String> = []
        var pids: [String] = []
        for line in lsofOutput.split(separator: "\n").map(String.init) {
            let fields = line.split { $0 == " " || $0 == "\t" }.map(String.init)
            guard fields.count >= 2, fields[0] != "COMMAND", Int(fields[1]) != nil else { continue }
            if !seen.contains(fields[1]) {
                seen.insert(fields[1])
                pids.append(fields[1])
            }
        }
        return pids
    }

    nonisolated private static func terminalBatchAnswer(from results: [AssistantLocalFileToolResult]) -> String {
        let fileSources = results.flatMap { $0.sources }.filter { $0.kindLabel == "File" }
        let uniqueFiles = Array(
            Dictionary(grouping: fileSources, by: \.path)
                .compactMap { $0.value.first }
                .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        )
        if results.allSatisfy({ $0.terminalResult?.intent == .fileSearch }) {
            var sections: [String] = []
            if uniqueFiles.isEmpty {
                sections.append("I searched the granted folders with the terminal and did not find matching files.")
            } else {
                sections.append("I searched the granted folders with the terminal and found:")
                sections.append(uniqueFiles.prefix(30).map { "- \($0.path)" }.joined(separator: "\n"))
                if uniqueFiles.count > 30 {
                    sections.append("- ... \(uniqueFiles.count - 30) more")
                }
            }
            let folders = results.compactMap(\.terminalResult?.workingDirectory)
            if !folders.isEmpty {
                sections.append("")
                sections.append("Folders searched: \(folders.map { "`\($0)`" }.joined(separator: ", "))")
            }
            return sections.joined(separator: "\n")
        }
        return results.map(Self.terminalAnswer(from:)).joined(separator: "\n\n")
    }

    private static func mergedLocalFileContext(
        grants: [LocalFileGrant],
        results: [AssistantLocalFileToolResult]
    ) -> LocalFileContext {
        var seen: Set<String> = []
        var snippets: [LocalFileSnippet] = []
        for result in results {
            for snippet in result.context?.snippets ?? [] {
                let key = snippet.id.isEmpty ? snippet.path : snippet.id
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                snippets.append(snippet)
            }
        }
        return LocalFileContext(
            grants: grants.filter { FileManager.default.fileExists(atPath: $0.path) },
            snippets: snippets
        )
    }

    nonisolated private static func terminalAnswer(from result: AssistantLocalFileToolResult) -> String {
        guard let terminal = result.terminalResult else {
            return result.summary
        }
        if terminal.intent == .fileSearch {
            return terminalFileSearchAnswer(from: result, terminal: terminal)
        }
        if terminal.intent == .systemInspection {
            return terminalSystemInspectionAnswer(from: terminal)
        }

        var sections = [
            terminal.summary,
            "",
            "Command: `\(terminal.command)`",
            "Directory: `\(terminal.workingDirectory)`",
            String(format: "Duration: %.1fs", terminal.durationSeconds)
        ]

        if !terminal.stdout.isEmpty {
            sections.append(
                """

                stdout:
                ```
                \(terminal.stdout)
                ```
                """
            )
        }
        if !terminal.stderr.isEmpty {
            sections.append(
                """

                stderr:
                ```
                \(terminal.stderr)
                ```
                """
            )
        }
        if terminal.wasOutputTruncated {
            sections.append("\nOutput was truncated to keep the chat responsive.")
        }
        return sections.joined(separator: "\n")
    }

    nonisolated private static func localFileReadAnswer(from result: AssistantLocalFileToolResult) -> String {
        guard let snippet = result.context?.snippets.first else {
            return result.summary
        }
        let source = result.sources.first
        let truncated = source?.isTruncated == true ? "\n\n[Truncated to a safe preview.]" : ""
        return """
        \(result.summary)

        \(snippet.path)

        \(snippet.preview)\(truncated)
        """
    }

    nonisolated private static func terminalSystemInspectionAnswer(
        from terminal: AssistantTerminalCommandResult
    ) -> String {
        let normalizedCommand = terminal.command.lowercased()
        if normalizedCommand.hasPrefix("ps aux") {
            return terminalProcessAnswer(from: terminal)
        }
        if normalizedCommand.hasPrefix("lsof -n")
            || normalizedCommand.contains("-itcp") {
            return terminalListeningPortAnswer(from: terminal)
        }

        var sections = [
            terminal.succeeded ? "I checked locally with the terminal." : terminal.summary,
            "",
            "Ran `\(terminal.command)` locally from `\(terminal.workingDirectory)`."
        ]
        let output = terminal.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty {
            sections.append("")
            sections.append(output)
        }
        if !terminal.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("")
            sections.append("stderr:\n\(terminal.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return sections.joined(separator: "\n")
    }

    nonisolated private static func terminalListeningPortAnswer(
        from terminal: AssistantTerminalCommandResult
    ) -> String {
        let output = terminal.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            return terminal.succeeded
                ? "I checked local listening ports and did not find an obvious development server."
                : terminal.summary
        }

        let lines = output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let verifiedURLs = unique(lines.compactMap(verifiedLocalURLLine))
        let candidates = unique(lines.compactMap(localhostURLLine))
        var sections: [String] = []
        if !verifiedURLs.isEmpty {
            sections.append("The local server reported:")
            sections.append(verifiedURLs.prefix(8).map { "- \($0)" }.joined(separator: "\n"))
        } else if candidates.isEmpty {
            sections.append("I checked local listening ports. I found listeners, but no obvious localhost URL stood out:")
        } else {
            sections.append("I checked local listening ports. Possible local URLs:")
            sections.append(candidates.prefix(8).map { "- \($0)" }.joined(separator: "\n"))
        }
        sections.append("")
        sections.append("Terminal output:")
        sections.append("```")
        sections.append(lines.prefix(20).joined(separator: "\n"))
        sections.append("```")
        return sections.joined(separator: "\n")
    }

    nonisolated private static func verifiedLocalURLLine(_ line: String) -> String? {
        guard let range = line.range(of: #"Verified URL:\s*(https?://[^\s]+)"#, options: .regularExpression) else {
            return nil
        }
        let match = String(line[range])
        guard let urlRange = match.range(of: #"https?://[^\s]+"#, options: .regularExpression) else {
            return nil
        }
        return String(match[urlRange]).replacingOccurrences(of: "127.0.0.1", with: "localhost")
    }

    nonisolated private static func localhostURLLine(_ line: String) -> String? {
        guard let range = line.range(of: #":([0-9]{2,5})\s+\(LISTEN\)"#, options: .regularExpression) else {
            return nil
        }
        let match = String(line[range])
        guard let portRange = match.range(of: #"[0-9]{2,5}"#, options: .regularExpression) else {
            return nil
        }
        let port = String(match[portRange])
        let process = line.split(separator: " ").first.map(String.init) ?? "process"
        return "http://localhost:\(port) (\(process))"
    }

    nonisolated private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    nonisolated private static func terminalProcessAnswer(
        from terminal: AssistantTerminalCommandResult
    ) -> String {
        let metric = terminal.command.contains("sort -nrk 4") ? "memory" : "CPU"
        var lines = terminal.stdout
            .split(separator: "\n")
            .map(String.init)
            .compactMap(processSummaryLine)
        if lines.isEmpty {
            let output = terminal.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty
                ? terminal.summary
                : "I checked the top running processes by \(metric).\n\n\(output)"
        }
        lines = Array(lines.prefix(10))
        var sections = ["Top running processes by \(metric):"]
        sections.append(lines.map { "- \($0)" }.joined(separator: "\n"))
        sections.append("")
        sections.append("Ran `\(terminal.command)` locally.")
        return sections.joined(separator: "\n")
    }

    nonisolated private static func processSummaryLine(_ line: String) -> String? {
        let parts = line.split(
            maxSplits: 10,
            omittingEmptySubsequences: true,
            whereSeparator: { $0 == " " || $0 == "\t" }
        ).map(String.init)
        guard parts.count >= 11,
              let cpu = Double(parts[2]),
              let memory = Double(parts[3]) else {
            return nil
        }
        let user = parts[0]
        let pid = parts[1]
        let command = readableProcessName(from: parts[10])
        return "\(command) (PID \(pid), \(user)): \(String(format: "%.1f", cpu))% CPU, \(String(format: "%.1f", memory))% MEM"
    }

    nonisolated private static func readableProcessName(from command: String) -> String {
        if let range = command.range(of: "/Contents/MacOS/") {
            let rawName = String(command[range.upperBound...])
            return firstCommandSegment(rawName)
        }
        let firstToken = command.split(separator: " ").first.map(String.init) ?? command
        let name = URL(fileURLWithPath: firstToken).lastPathComponent
        return name.isEmpty ? firstCommandSegment(command) : name
    }

    nonisolated private static func firstCommandSegment(_ value: String) -> String {
        let separators = [" --", " -"]
        var endIndex = value.endIndex
        for separator in separators {
            if let range = value.range(of: separator) {
                endIndex = min(endIndex, range.lowerBound)
            }
        }
        return String(value[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func terminalFileSearchAnswer(
        from result: AssistantLocalFileToolResult,
        terminal: AssistantTerminalCommandResult
    ) -> String {
        let files = result.sources.filter { $0.kindLabel == "File" }
        var sections: [String] = []
        if files.isEmpty {
            sections.append("I searched the granted folder with the terminal and did not find matching files.")
        } else {
            sections.append("I searched the granted folder with the terminal and found:")
            sections.append(
                files.prefix(20)
                    .map { "- \($0.path)" }
                    .joined(separator: "\n")
            )
            if files.count > 20 {
                sections.append("- ... \(files.count - 20) more")
            }
        }
        sections.append("")
        sections.append("Folder: `\(terminal.workingDirectory)`")
        sections.append(String(format: "Terminal search completed in %.1fs.", terminal.durationSeconds))
        if !terminal.stderr.isEmpty {
            sections.append(
                """

                stderr:
                ```
                \(terminal.stderr)
                ```
                """
            )
        }
        if terminal.wasOutputTruncated {
            sections.append("\nOutput was truncated to keep the chat responsive.")
        }
        return sections.joined(separator: "\n")
    }

    private func appendDirectAskAnswer(question: String, answer: String, backendLabel: String) {
        askInput = ""
        pendingLocalFileWriteProposal = nil
        pendingTerminalCommandProposal = nil
        recoveryState = nil
        hiddenReasoning = nil
        outputStatistics = []
        actionBackendLabel = backendLabel
        askTurns.append(
            AskConversationTurn(
                question: question,
                answer: answer,
                backendLabel: backendLabel
            )
        )
        persistAskSession()
        setOutputState(askOutputState(), for: .ask)
        focusChatInputSoon()
    }

    private func confirmLocalFileWrite() {
        guard let proposal = pendingLocalFileWriteProposal else { return }

        do {
            try LocalFileWriteExecutor.execute(proposal)
            pendingLocalFileWriteProposal = nil
            askTurns.append(
                AskConversationTurn(
                    question: "Confirm \(proposal.actionLabel.lowercased())",
                    answer: "Done. \(proposal.detailText)",
                    backendLabel: "Local Files"
                )
            )
            showConfirmation("File updated")
        } catch {
            askTurns.append(
                AskConversationTurn(
                    question: "Confirm \(proposal.actionLabel.lowercased())",
                    answer: "I could not apply that file change: \(error.localizedDescription)",
                    backendLabel: "Local Files"
                )
            )
            showConfirmation("Write failed")
        }

        persistAskSession()
        setOutputState(askOutputState(), for: .ask)
        focusChatInputSoon()
    }

    private func cancelLocalFileWrite() {
        guard let proposal = pendingLocalFileWriteProposal else { return }
        pendingLocalFileWriteProposal = nil
        askTurns.append(
            AskConversationTurn(
                question: "Cancel \(proposal.actionLabel.lowercased())",
                answer: "Cancelled. No file was changed.",
                backendLabel: "Local Files"
            )
        )
        persistAskSession()
        setOutputState(askOutputState(), for: .ask)
        focusChatInputSoon()
    }

    private func confirmTerminalCommand() {
        guard let proposal = pendingTerminalCommandProposal else { return }
        pendingTerminalCommandProposal = nil
        runTerminalCommand(
            proposal,
            question: "Allow terminal in \(URL(fileURLWithPath: proposal.workingDirectory).lastPathComponent): \(proposal.reason)",
            grants: localFileAccess.grants,
            toolRouter: AssistantToolRouter()
        )
    }

    private func cancelTerminalCommand() {
        guard let proposal = pendingTerminalCommandProposal else { return }
        pendingTerminalCommandProposal = nil
        askTurns.append(
            AskConversationTurn(
                question: "Cancel terminal command",
                answer: "Cancelled. No terminal command was run.\n\n`\(proposal.command)`",
                backendLabel: "Terminal"
            )
        )
        persistAskSession()
        setOutputState(askOutputState(), for: .ask)
        updateExpandedNotchSizeIfNeeded()
        focusChatInputSoon()
    }

    private static func askPrompt(
        question: String,
        hasCaptureContext: Bool,
        capturedOCRText: String,
        isCaptureImageAttached: Bool,
        assistantImageContext: AssistantImageContext?,
        isAssistantImageAttached: Bool,
        previousTranscript: String,
        localFileContext: LocalFileContext,
        usesCloud: Bool,
        responseDetail: ResponseDetailLevel,
        responseGuidance: String
    ) -> String {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = truncate(previousTranscript.trimmingCharacters(in: .whitespacesAndNewlines), limit: 1_600)
        let ocr = truncate(
            capturedOCRText.trimmingCharacters(in: .whitespacesAndNewlines),
            limit: 1_400
        )
        let fileContext = compactFileContext(localFileContext, usesCloud: usesCloud)
        var sections: [String] = []

        if responseDetail == .brief {
            sections.append("Answer directly in one short sentence when practical. Do not show reasoning.")
        } else {
            sections.append(responseGuidance)
        }

        if hasCaptureContext {
            if isCaptureImageAttached {
                sections.append(
                    ocr.isEmpty
                        ? "Use the attached screen image as context."
                        : "Use the attached screen image as context. OCR:\n\(ocr)"
                )
            } else if !ocr.isEmpty {
                sections.append("Use this screen OCR as context:\n\(ocr)")
            } else {
                sections.append("A screen region was selected, but no readable OCR or image input is available.")
            }
        }

        if let assistantImageContext {
            let imageOCR = truncate(
                assistantImageContext.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                limit: 1_400
            )
            if isAssistantImageAttached {
                sections.append(
                    imageOCR.isEmpty
                        ? "Use the attached user image \"\(assistantImageContext.label)\" as context."
                        : "Use the attached user image \"\(assistantImageContext.label)\" as context. Image OCR:\n\(imageOCR)"
                )
            } else if !imageOCR.isEmpty {
                sections.append("Use this OCR from attached user image \"\(assistantImageContext.label)\" as context:\n\(imageOCR)")
            } else {
                sections.append("A user image \"\(assistantImageContext.label)\" is attached, but no readable OCR or image input is available.")
            }
        }

        if fileContext != "none granted", fileContext != "none relevant" {
            sections.append("Use these file snippets only when relevant:\n\(fileContext)")
        }

        if !transcript.isEmpty {
            sections.append("Prior chat:\n\(transcript)")
        }

        sections.append("User: \(trimmedQuestion)")
        return sections.joined(separator: "\n\n")
    }

    private static func askMaxOutputTokens(
        responseDetail: ResponseDetailLevel,
        question: String,
        hasCaptureContext: Bool,
        hasFileContext: Bool,
        hasPreviousTranscript: Bool,
        isSimpleBriefPlainChat: Bool
    ) -> Int {
        guard responseDetail == .brief else {
            return responseDetail.maxOutputTokens(for: .ask)
        }
        if isSimpleBriefPlainChat {
            return 128
        }
        if asksForLongAnswer(question) || hasCaptureContext || hasFileContext {
            return 1_024
        }
        return hasPreviousTranscript ? 512 : 256
    }

    private static func compactFileContext(_ context: LocalFileContext, usesCloud: Bool) -> String {
        guard context.hasGrantedFiles else { return "none granted" }
        guard context.hasSnippets else { return "none relevant" }
        let mode = usesCloud ? "cloud-routed snippets" : "local snippets"
        let snippets = context.snippets.enumerated().map { index, snippet in
            "[\(index + 1)] \(snippet.path)\n\(truncate(snippet.preview, limit: 700))"
        }.joined(separator: "\n")
        return "\(mode)\n\(snippets)"
    }

    private static func cloudAskContext(
        hasCaptureContext: Bool,
        capturedOCRText: String,
        isCaptureImageAttached: Bool,
        assistantImageContext: AssistantImageContext?,
        isAssistantImageAttached: Bool,
        localFileContext: LocalFileContext,
        usesCloud: Bool
    ) -> String {
        var sections: [String] = []
        let ocr = truncate(
            capturedOCRText.trimmingCharacters(in: .whitespacesAndNewlines),
            limit: 1_400
        )
        if hasCaptureContext {
            if !ocr.isEmpty {
                sections.append("Selected screen OCR:\n\(ocr)")
            } else if isCaptureImageAttached {
                sections.append("Selected screen region image is attached.")
            } else {
                sections.append("Selected screen region selected, but no readable OCR.")
            }
        }

        if let assistantImageContext {
            let imageOCR = truncate(
                assistantImageContext.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                limit: 1_400
            )
            if !imageOCR.isEmpty {
                sections.append("Attached image OCR (\(assistantImageContext.label)):\n\(imageOCR)")
            } else if isAssistantImageAttached {
                sections.append("Attached image is included: \(assistantImageContext.label).")
            } else {
                sections.append("Attached image has no readable OCR: \(assistantImageContext.label).")
            }
        }

        let fileContext = compactFileContext(localFileContext, usesCloud: usesCloud)
        if fileContext != "none granted", fileContext != "none relevant" {
            sections.append("Files:\n\(fileContext)")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let end = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func asksForLongAnswer(_ question: String) -> Bool {
        let normalized = normalizedQuestion(question)
        return [
            "explain",
            "steps",
            "list",
            "compare",
            "summarize",
            "write",
            "draft",
            "code",
            "why",
            "how"
        ].contains { normalized.contains($0) }
    }

    private static func normalizedQuestion(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func questionReferencesCapture(_ question: String) -> Bool {
        let lowercased = question.lowercased()
        return [
            "screen",
            "screenshot",
            "capture",
            "captured",
            "selected",
            "region",
            "image",
            "picture",
            "see",
            "shown",
            "visible",
            "this"
        ].contains { lowercased.contains($0) }
    }

    private func runAskTurn(request: AIBackendRequest) async {
        do {
            for try await event in selectedAIBackend.streamResponse(for: request) {
                switch event {
                case .metadata(let statistics):
                    await MainActor.run {
                        updateLastAskStatistics(statistics)
                        setOutputState(askOutputState(reasoning: nil), for: .ask)
                    }
                case .snapshot(let text):
                    await MainActor.run {
                        let displayText = displayTextNormalizer.normalize(text)
                        updateLastAskAnswer(
                            cleanAskAnswer(
                                displayText,
                                question: askTurns.last?.question ?? "",
                                prompt: request.prompt
                            )
                        )
                        setOutputState(askOutputState(reasoning: nil), for: .ask)
                    }
                case .output(let output):
                    await MainActor.run {
                        let displayText = displayTextNormalizer.normalize(output.finalText)
                        updateLastAskAnswer(
                            cleanAskAnswer(
                                displayText,
                                question: askTurns.last?.question ?? "",
                                prompt: request.prompt
                            )
                        )
                        updateLastAskStatistics(output.statistics)
                        setOutputState(
                            askOutputState(
                                reasoning: responseDetail == .brief
                                    ? nil
                                    : output.reasoningText.map(displayTextNormalizer.normalize)
                            ),
                            for: .ask
                        )
                    }
                case .completed:
                    await MainActor.run {
                        _ = loadingActions.remove(.ask)
                        persistAskSession()
                        updateExpandedNotchSizeIfNeeded()
                        focusChatInputSoon()
                    }
                }
            }
        } catch {
            if routingSettings.effectiveMode == .cloud {
                await showAskCloudFailure(error)
                return
            }
            await MainActor.run {
                let recovery = ActionRecoveryState(error: error)
                updateLastAskAnswer("Chat unavailable. \(recovery.detail)")
                updateLastAskStatistics([])
                setOutputState(
                    askOutputState(
                        backendLabel: "Unavailable",
                        recovery: recovery
                    ),
                    for: .ask
                )
                loadingActions.remove(.ask)
                persistAskSession()
                updateExpandedNotchSizeIfNeeded()
                focusChatInputSoon()
            }
        }
    }

    private func showAskCloudFailure(_ error: Error) async {
        await MainActor.run {
            let recovery = ActionRecoveryState(cloudError: error)
            updateLastAskAnswer("Cloud action failed. \(recovery.detail)")
            updateLastAskStatistics([])
            if let lastIndex = askTurns.indices.last {
                askTurns[lastIndex].backendLabel = Self.cloudBackendLabel
            }
            persistAskSession()
            setOutputState(
                askOutputState(
                    backendLabel: Self.cloudBackendLabel,
                    recovery: recovery
                ),
                for: .ask
            )
            loadingActions.remove(.ask)
            updateExpandedNotchSizeIfNeeded()
            focusChatInputSoon()
        }
    }

    private func updateLastAskAnswer(_ answer: String) {
        guard let lastIndex = askTurns.indices.last else { return }
        askTurns[lastIndex].answer = answer
    }

    private func updateLastAskStatistics(_ statistics: [AIModelOutputStatistic]) {
        guard let lastIndex = askTurns.indices.last else { return }
        askTurns[lastIndex].statistics = statistics
    }

    private func persistAskSession() {
        guard !askTurns.isEmpty else { return }
        chatHistory.upsertSession(
            contextID: chatContextID,
            kind: chatContextKind,
            title: chatContextKind.displayName,
            turns: askTurns.map { $0.storedTurn() },
            toolState: assistantToolState
        )
    }

    private func loadChatSession(_ session: StoredChatSession) {
        guard loadingActions.isEmpty else { return }
        assistantImageContext = nil
        isPreparingAssistantImage = false
        pendingLocalFileWriteProposal = nil
        pendingTerminalCommandProposal = nil
        assistantToolState = session.toolState ?? AssistantToolState()
        chatContextID = session.contextID
        chatContextKind = session.contextKind
        askTurns = session.turns.map { AskConversationTurn(storedTurn: $0) }
        selectedAction = .ask
        setOutputState(askOutputState(backendLabel: askTurns.last?.backendLabel), for: .ask)
        updateExpandedNotchSizeIfNeeded()
        focusChatInputSoon()
    }

    private func startNewAssistantChat() {
        guard loadingActions.isEmpty else { return }
        suppressNextNotchHoverCollapseBriefly()
        assistantImageContext = nil
        isPreparingAssistantImage = false
        pendingLocalFileWriteProposal = nil
        pendingTerminalCommandProposal = nil
        assistantToolState = AssistantToolState()
        chatContextID = Self.defaultChatContextID(
            for: CaptureResult(
                image: nil,
                text: "",
                isEmptyOCRResult: true,
                selectionFrame: result.selectionFrame,
                createdAt: Date(),
                sourceType: .assistant,
                detectedLanguage: .unknown
            )
        )
        chatContextKind = .assistant
        askTurns = []
        selectedAction = .ask
        setOutputState(
            PanelActionOutputState(
                text: "",
                sourceLabel: nil,
                targetLabel: nil,
                backendLabel: routingSettings.effectiveMode == .cloud ? Self.cloudBackendLabel : localTextBackendLabel(),
                statistics: [],
                reasoning: nil,
                recovery: nil
            ),
            for: .ask
        )
        updateExpandedNotchSizeIfNeeded()
        isChatInputFocused = true
        focusChatInputSoon()
    }

    private func cleanAskAnswer(_ answer: String, question: String, prompt: String) -> String {
        var cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = stripPromptEcho(from: cleaned, prompt: prompt)
        cleaned = stripLeadingPromptScaffold(from: cleaned, question: question)

        let markers = [
            "user question:",
            "previous turns:",
            "captured ocr text:",
            "answer concisely.",
            "screen:",
            "ocr:",
            "files:",
            "prior:",
            "q:"
        ]
        if let markerRange = markers
            .compactMap({ marker -> Range<String.Index>? in
                guard cleaned.lowercased().hasPrefix(marker) else { return nil }
                return cleaned.range(of: marker, options: .caseInsensitive)
            })
            .min(by: { $0.lowerBound < $1.lowerBound }),
            !markerRange.isEmpty {
            cleaned = String(cleaned[..<markerRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let questionLine = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !questionLine.isEmpty {
            cleaned = cleaned
                .components(separatedBy: .newlines)
                .filter { line in
                    line.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(questionLine) != .orderedSame
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned.isEmpty ? "Thinking..." : cleaned
    }

    private func stripLeadingPromptScaffold(from answer: String, question: String) -> String {
        let questionLine = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAnswer = normalizedPromptLine(answer)
        let scaffoldPrefixes = [
            "answer concisely.",
            "screen:",
            "ocr:",
            "files:",
            "prior:",
            "q:",
            "context:",
            "ocr text:",
            "question:"
        ]
        guard scaffoldPrefixes.contains(where: { normalizedAnswer.hasPrefix($0) }) else {
            return stripAnswerLeadIn(from: answer)
        }

        if !questionLine.isEmpty,
           let questionRange = answer.range(of: questionLine, options: [.caseInsensitive, .diacriticInsensitive]) {
            let remainder = answer[questionRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stripAnswerLeadIn(from: String(remainder))
        }

        let lines = answer.components(separatedBy: .newlines)
        guard let firstContentIndex = lines.firstIndex(where: {
            !normalizedPromptLine($0).isEmpty
        }) else {
            return ""
        }

        var questionIndex: Int?
        let normalizedQuestion = normalizedPromptLine(questionLine)
        for index in firstContentIndex..<lines.count {
            let normalizedLine = normalizedPromptLine(lines[index])
            if normalizedLine.hasPrefix("q:")
                || normalizedLine.hasPrefix("question:")
                || (!normalizedQuestion.isEmpty && normalizedLine == normalizedQuestion) {
                questionIndex = index
                break
            }
        }

        guard let questionIndex else {
            return ""
        }

        let remainder = lines
            .dropFirst(questionIndex + 1)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripAnswerLeadIn(from: remainder)
    }

    private func stripAnswerLeadIn(from answer: String) -> String {
        let leadIns = [
            "answer:",
            "a:",
            "assistant:"
        ]
        var cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        for leadIn in leadIns {
            if cleaned.lowercased().hasPrefix(leadIn) {
                cleaned = String(cleaned.dropFirst(leadIn.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return cleaned
    }

    private func stripPromptEcho(from answer: String, prompt: String) -> String {
        let promptLines = prompt
            .components(separatedBy: .newlines)
            .map(normalizedPromptLine)
            .filter { !$0.isEmpty }
        guard !promptLines.isEmpty else { return answer }

        var answerLines = answer.components(separatedBy: .newlines)
        var answerIndex = 0
        var promptIndex = 0
        while answerIndex < answerLines.count, promptIndex < promptLines.count {
            let normalizedAnswer = normalizedPromptLine(answerLines[answerIndex])
            guard !normalizedAnswer.isEmpty else {
                answerIndex += 1
                continue
            }
            let normalizedPrompt = promptLines[promptIndex]
            guard normalizedAnswer == normalizedPrompt || normalizedPrompt.hasPrefix(normalizedAnswer) else {
                break
            }
            answerIndex += 1
            promptIndex += 1
        }

        if answerIndex > 0 {
            answerLines.removeFirst(answerIndex)
            return answerLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let normalizedAnswer = normalizedPromptLine(answer)
        let normalizedPrompt = normalizedPromptLine(prompt)
        if normalizedPrompt.hasPrefix(normalizedAnswer) || normalizedAnswer.hasPrefix(normalizedPrompt) {
            return normalizedAnswer == normalizedPrompt ? "" : answer.replacingOccurrences(of: prompt, with: "")
        }

        return answer
    }

    private func normalizedPromptLine(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private func formattedAskTranscript() -> String {
        askTurns
            .enumerated()
            .map { index, turn in
                let answer = turn.answer.isEmpty ? "Thinking..." : turn.answer
                return """
                Q\(index + 1): \(turn.question)

                \(answer)
                """
            }
            .joined(separator: "\n\n")
    }

    private func assistantContextPriorTurns() -> [AssistantContextPriorTurn] {
        askTurns.map { turn in
            AssistantContextPriorTurn(
                question: turn.question,
                answer: turn.answer.isEmpty ? "" : turn.answer
            )
        }
    }

    private static func enrichedFileSearchQuestion(
        question: String,
        previousTurns: [AssistantContextPriorTurn],
        toolState: AssistantToolState
    ) -> String {
        let normalized = normalizedQuestion(question)
        let contextDependentSignals = [
            "his", "her", "their", "they", "them", "he ", "she ",
            "that", "this", "it", "experience", "background", "work"
        ]
        let shouldCarryContext = contextDependentSignals.contains { normalized.contains($0) }
            || toolState.lastListedFolder != nil
            || !toolState.lastFileSources.isEmpty
        guard shouldCarryContext else { return question }

        let recentContext = previousTurns
            .suffix(2)
            .flatMap { [$0.question, $0.answer] }
            .joined(separator: " ")
        let sourceContext = (toolState.lastFileSources + toolState.grantedSourcesUsed)
            .map { "\($0.displayName) \($0.path)" }
            .joined(separator: " ")

        return [question, recentContext, sourceContext]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func cloudConversationTurns(beforeLastTurn: Bool) -> [AIBackendConversationTurn] {
        let turns: ArraySlice<AskConversationTurn> = beforeLastTurn ? askTurns.dropLast() : askTurns[...]
        return turns.flatMap { turn in
            [
                AIBackendConversationTurn(role: .user, content: turn.question),
                AIBackendConversationTurn(
                    role: .assistant,
                    content: turn.answer.isEmpty ? "Thinking..." : turn.answer
                )
            ]
        }
    }

    private func askBackendLabelForNextTurn() -> String {
        if routingSettings.effectiveMode == .cloud {
            return Self.cloudBackendLabel
        }
        let askUsesMLX = hasCaptureContext
            && localAICapabilities.image.isAvailable
            && result.image != nil
        return askUsesMLX ? Self.mlxVisionBackendLabel : localTextBackendLabel()
    }

    private func askOutputState(
        backendLabel: String? = nil,
        reasoning: String? = nil,
        recovery: ActionRecoveryState? = nil
    ) -> PanelActionOutputState {
        PanelActionOutputState(
            text: askTurns.isEmpty
                ? (hasCaptureContext
                    ? "Chat about this capture."
                    : "")
                : formattedAskTranscript(),
            sourceLabel: hasCaptureContext ? "Source: \(result.detectedLanguage.displayName)" : nil,
            targetLabel: nil,
            backendLabel: backendLabel ?? askTurns.last?.backendLabel ?? askBackendLabelForNextTurn(),
            statistics: [],
            reasoning: reasoning,
            recovery: recovery
        )
    }

    private func runLocalTranslation() async {
        let prompt = """
        Translate the following captured text into natural English.

        Rules:
        - Translate non-English text into English.
        - Keep text that is already English in English.
        - Preserve useful line breaks and section order.
        - \(responseDetail.outputGuidance)
        - Return only the translated text, with no notes or explanation.

        Detected source language: \(result.detectedLanguage.displayName)

        \(result.text)
        """

        let request = AIBackendRequest(
            actionKind: .translate,
            prompt: prompt,
            capturedImage: nil,
            maxOutputTokens: responseDetail.maxOutputTokens(for: .translate),
            cloudOCRText: result.text,
            cloudDetectedLanguage: cloudDetectedLanguage,
            cloudTargetLanguage: "English"
        )

        await runLocalTextAction(request: request)
    }

    private func runLocalTextAction(request: AIBackendRequest) async {
        let actionKind = request.actionKind.panelActionKind
        do {
            for try await event in selectedAIBackend.streamResponse(for: request) {
                switch event {
                case .metadata(let statistics):
                    await MainActor.run {
                        updateOutputState(for: actionKind) { state in
                            state.statistics = statistics
                        }
                    }
                case .snapshot(let text):
                    await MainActor.run {
                        let displayText = displayTextNormalizer.normalize(text)
                        guard shouldShowStreamText(displayText, for: request) else { return }
                        updateOutputState(for: actionKind) { state in
                            state.text = displayText
                            state.reasoning = nil
                            state.recovery = nil
                        }
                    }
                case .output(let output):
                    await MainActor.run {
                        let displayText = displayTextNormalizer.normalize(output.finalText)
                        guard shouldShowStreamText(displayText, for: request) else { return }
                        updateOutputState(for: actionKind) { state in
                            state.text = displayText
                            state.statistics = output.statistics
                            state.reasoning = output.reasoningText.map(displayTextNormalizer.normalize)
                            state.recovery = nil
                        }
                    }
                case .completed:
                    await MainActor.run {
                        _ = loadingActions.remove(actionKind)
                        guard routingSettings.effectiveMode == .cloud else { return }
                        guard let currentText = actionOutputs[actionKind]?.text else { return }
                        guard isWorkingPlaceholder(currentText) else { return }
                        showCloudEmptyResponse(for: actionKind)
                    }
                }
            }
        } catch {
            if routingSettings.effectiveMode == .cloud {
                await showCloudFailure(for: actionKind, error: error)
                return
            }
            await MainActor.run {
                let recovery = ActionRecoveryState(error: error)
                updateOutputState(for: actionKind) { state in
                    state.text = "\(actionKind.title) unavailable. \(recovery.detail)"
                    state.statistics = []
                    state.reasoning = nil
                    state.recovery = recovery
                    state.backendLabel = "Unavailable"
                }
                _ = loadingActions.remove(actionKind)
            }
        }
    }

    private func showCloudEmptyResponse(for actionKind: PanelActionKind) {
        let recovery = ActionRecoveryState(cloudError: CloudAIBackendError.emptyResponse)
        updateOutputState(for: actionKind) { state in
            state.text = "Cloud returned no text. \(recovery.detail)"
            state.backendLabel = Self.cloudBackendLabel
            state.statistics = []
            state.reasoning = nil
            state.recovery = recovery
        }
        _ = loadingActions.remove(actionKind)
    }

    private func showCloudFailure(for actionKind: PanelActionKind, error: Error) async {
        await MainActor.run {
            let recovery = ActionRecoveryState(cloudError: error)
            updateOutputState(for: actionKind) { state in
                state.text = "Cloud action failed. \(recovery.detail)"
                state.backendLabel = Self.cloudBackendLabel
                state.statistics = []
                state.reasoning = nil
                state.recovery = recovery
            }
            _ = loadingActions.remove(actionKind)
        }
    }

    private func shouldShowModelText(_ text: String, for request: AIBackendRequest) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lowercased = trimmed.lowercased()
        let promptEchoMarkers = [
            "<|im_start|>user",
            "<im_start>user",
            "<lim_start>user",
            "<vision_start>",
            "<|vision_start|>",
            "rules:",
            "ocr text:",
            "captured text:",
            "rewrite the captured text",
            "explain this screenshot",
            "explain the captured text",
            "debug this captured",
            "return only the simplified text",
            "return only the useful answer",
            "do not invent facts"
        ]

        return !promptEchoMarkers.contains { lowercased.contains($0) }
    }

    private func shouldShowStreamText(_ text: String, for request: AIBackendRequest) -> Bool {
        if routingSettings.effectiveMode == .cloud {
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return shouldShowModelText(text, for: request)
    }

    private func performRecoveryPrimaryAction() {
        guard let recoveryState else { return }

        switch recoveryState.primaryAction {
        case .tryAgain:
            onTryAgain()
        case .openSettings:
            openSettings()
        case .openAppleIntelligenceSettings:
            openAppleIntelligenceSettings()
        case .refresh:
            rerunSelectedAction()
        }
    }

    private func performRecoverySecondaryAction() {
        guard let recoveryState else { return }

        switch recoveryState.secondaryAction {
        case .openSettings:
            openSettings()
        case .refresh:
            rerunSelectedAction()
        case .openAppleIntelligenceSettings:
            openAppleIntelligenceSettings()
        case .tryAgain, nil:
            onTryAgain()
        }
    }

    private func rerunSelectedAction() {
        actionOutputs[selectedAction] = nil
        switch selectedAction {
        case .extractText:
            restoreExtractOutput()
        case .translate:
            startTranslation()
        case .simplify:
            startSimplify()
        case .explain:
            startExplain()
        case .debug:
            startDebug()
        case .ask:
            startAsk()
        }
    }

    private func openAppleIntelligenceSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Apple-Intelligence") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    private var hiddenShortcuts: some View {
        Button("Close Window", action: onClose)
            .keyboardShortcut("w", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    static let appleTextBackendLabel = "Local Apple Model"
    static let mlxTextBackendLabel = "MLX Text"
    static let mlxVisionBackendLabel = "MLX Vision"
    static let cloudBackendLabel = "Pixel Pane Cloud"

    private static func initialSmartDefaultOutputState(
        for action: PanelActionKind,
        result: CaptureResult,
        routingSettings: AIRoutingSettings
    ) -> PanelActionOutputState {
        let cloudMode = routingSettings.effectiveMode == .cloud
        switch action {
        case .extractText:
            return PanelActionOutputState(
                text: ExtractTextAction().run(on: result),
                sourceLabel: nil,
                targetLabel: nil,
                backendLabel: nil,
                statistics: [],
                reasoning: nil,
                recovery: result.isEmptyOCRResult ? .emptyOCR : nil
            )
        case .translate:
            return PanelActionOutputState(
                text: cloudMode ? "Translating with Pixel Pane Cloud..." : "Translating with local text AI...",
                sourceLabel: "From: \(result.detectedLanguage.displayName)",
                targetLabel: "To: English",
                backendLabel: cloudMode ? cloudBackendLabel : appleTextBackendLabel,
                statistics: [],
                reasoning: nil,
                recovery: nil
            )
        case .simplify:
            return PanelActionOutputState(
                text: "Simplifying",
                sourceLabel: nil,
                targetLabel: nil,
                backendLabel: cloudMode ? cloudBackendLabel : appleTextBackendLabel,
                statistics: [],
                reasoning: nil,
                recovery: nil
            )
        case .explain:
            return PanelActionOutputState(
                text: "Explaining...",
                sourceLabel: "Source: \(result.detectedLanguage.displayName)",
                targetLabel: nil,
                backendLabel: cloudMode ? cloudBackendLabel : appleTextBackendLabel,
                statistics: [],
                reasoning: nil,
                recovery: nil
            )
        case .debug:
            return PanelActionOutputState(
                text: "Debugging...",
                sourceLabel: "Source: \(result.detectedLanguage.displayName)",
                targetLabel: nil,
                backendLabel: cloudMode ? cloudBackendLabel : appleTextBackendLabel,
                statistics: [],
                reasoning: nil,
                recovery: nil
            )
        case .ask:
            return PanelActionOutputState(
                text: "Chat about this capture.",
                sourceLabel: "Source: \(result.detectedLanguage.displayName)",
                targetLabel: nil,
                backendLabel: cloudMode ? cloudBackendLabel : appleTextBackendLabel,
                statistics: [],
                reasoning: nil,
                recovery: nil
            )
        }
    }

    private static func initialAskOutputState(
        for result: CaptureResult,
        routingSettings: AIRoutingSettings
    ) -> PanelActionOutputState {
        let hasCaptureContext = result.sourceType != .assistant
        return PanelActionOutputState(
            text: hasCaptureContext
                ? "Chat about this capture."
                : "Chat with Pixel Pane using the selected AI mode.",
            sourceLabel: hasCaptureContext ? "Source: \(result.detectedLanguage.displayName)" : nil,
            targetLabel: nil,
            backendLabel: routingSettings.effectiveMode == .cloud ? cloudBackendLabel : appleTextBackendLabel,
            statistics: [],
            reasoning: nil,
            recovery: nil
        )
    }

}

// MARK: - Glass Overlay Container

struct GlassOverlayContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.045),
                    Color.clear,
                    Color.black.opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)

            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: OverlayPanelMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OverlayPanelMetrics.cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.05),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }
}

struct NotchResultContainer<Content: View>: View {
    let isExpanded: Bool
    let roundsTopCorners: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            if isExpanded {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                    .opacity(0.42)
                Color.black.opacity(0.86)
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.98), location: 0.0),
                        .init(color: Color.black.opacity(0.96), location: 0.18),
                        .init(color: Color.black.opacity(0.88), location: 0.38),
                        .init(color: Color.black.opacity(0.80), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            } else {
                Color.clear
            }

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(shape)
        .padding(.horizontal, isExpanded ? 2 : 0)
        .padding(.bottom, isExpanded ? 2 : 0)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isExpanded && roundsTopCorners ? 30 : 0,
            bottomLeadingRadius: isExpanded ? 30 : 0,
            bottomTrailingRadius: isExpanded ? 30 : 8,
            topTrailingRadius: isExpanded && roundsTopCorners ? 30 : 0,
            style: .continuous
        )
    }
}

private enum CompactNotchNotificationState {
    case processing

    var color: Color {
        Color(red: 1.0, green: 0.78, blue: 0.18)
    }
}

private struct CompactNotchNotificationView: View {
    let state: CompactNotchNotificationState
    @State private var isPulsing = false
    private let shape = UnevenRoundedRectangle(
        topLeadingRadius: 0,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 4,
        topTrailingRadius: 0,
        style: .continuous
    )

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                shape
                    .fill(Color(nsColor: .black))
                    .frame(
                        width: ResultPanelPresentationStyle.notchCompactSize.width,
                        height: ResultPanelPresentationStyle.notchCompactSize.height
                    )

                Circle()
                    .fill(state.color.opacity(0.22))
                    .frame(width: 14, height: 8)
                    .blur(radius: 6)
                    .scaleEffect(isPulsing ? 1.18 : 0.88)
                    .opacity(isPulsing ? 0.64 : 0.26)

                CompactThinkingDots(color: state.color)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct CompactThinkingDots: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color.opacity(animate ? 1.0 : 0.5))
                    .frame(width: 2.8, height: 2.8)
                    .scaleEffect(animate ? 1.18 : 0.72)
                    .offset(y: animate ? -1.2 : 1.0)
                    .shadow(color: color.opacity(0.55), radius: animate ? 3 : 1.5)
                    .animation(
                        .easeInOut(duration: 0.62)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.16),
                        value: animate
                    )
            }
        }
        .onAppear {
            animate = true
        }
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Header bits

private struct ActionGradientBadge: View {
    let systemImage: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.95),
                            Color.accentColor.opacity(0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.25), lineWidth: 1)
                        .blendMode(.plusLighter)
                }
                .shadow(color: Color.accentColor.opacity(0.45), radius: 10, y: 3)

            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
        }
        .frame(width: 36, height: 36)
    }
}

private struct NotchHeaderStatusDot: View {
    var body: some View {
        Circle()
            .fill(.white.opacity(0.72))
            .frame(width: 5, height: 5)
            .shadow(color: .white.opacity(0.36), radius: 5)
            .frame(width: 10, height: 18)
    }
}

private struct OverlayCloseButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(hovered ? 0.14 : 0.07))
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 1)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovered ? .primary : .secondary)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Close (Esc)")
        .keyboardShortcut(.cancelAction)
    }
}

// MARK: - Action tab bar

private struct SegmentedActionBar: View {
    let actions: [PanelActionState]
    let onSelect: (PanelActionState) -> Void
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(actions) { action in
                ActionTab(
                    action: action,
                    namespace: indicator,
                    onSelect: onSelect
                )
            }
        }
        .padding(4)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct ActionTab: View {
    let action: PanelActionState
    let namespace: Namespace.ID
    let onSelect: (PanelActionState) -> Void
    @State private var hovered = false

    var body: some View {
        Button {
            onSelect(action)
        } label: {
            HStack(spacing: 6) {
                if action.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(action.isSelected ? Color.accentColor : .secondary)
                } else {
                    Image(systemName: action.kind.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(action.kind.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    if action.isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.16),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.white.opacity(0.16), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                            .matchedGeometryEffect(id: "indicator", in: namespace)
                    } else if hovered, action.isEnabled {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.05))
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .help(action.disabledReason ?? action.kind.title)
        .onHover { hovered = $0 }
    }

    private var foreground: Color {
        if !action.isEnabled {
            return .secondary.opacity(0.45)
        }
        return action.isSelected ? .primary : .primary.opacity(0.62)
    }
}

// MARK: - Buttons

private struct EmptyAssistantStatusChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(.white.opacity(0.055), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct OverlayPillButton: View {
    enum Style {
        case primary, secondary, accent
    }

    enum DisplayStyle {
        case iconAndTitle, prominentIconAndTitle, iconOnly
    }

    let title: String
    let systemImage: String
    let style: Style
    var displayStyle: DisplayStyle = .iconAndTitle
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: displayStyle == .iconOnly ? 0 : 6) {
                Image(systemName: systemImage)
                    .font(.system(size: displayStyle == .prominentIconAndTitle ? 13 : 12, weight: .semibold))

                if displayStyle != .iconOnly {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(foreground)
            .frame(width: displayStyle == .iconOnly ? 40 : nil)
            .padding(.horizontal, displayStyle == .iconOnly ? 0 : 14)
            .frame(minHeight: displayStyle == .prominentIconAndTitle ? 40 : 40)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
            .shadow(color: shadow, radius: 4, y: 1)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 && isEnabled }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .help(title)
    }

    private var foreground: Color {
        switch style {
        case .accent:
            return .white
        case .primary, .secondary:
            return .primary
        }
    }

    private var fill: AnyShapeStyle {
        switch style {
        case .accent:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.36, blue: 0.38).opacity(hovered ? 1.0 : 0.92),
                        Color(red: 0.55, green: 0.13, blue: 0.16).opacity(hovered ? 0.90 : 0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .primary:
            return AnyShapeStyle(.white.opacity(hovered ? 0.14 : 0.09))
        case .secondary:
            return AnyShapeStyle(.white.opacity(hovered ? 0.09 : 0.04))
        }
    }

    private var stroke: Color {
        switch style {
        case .accent:
            return .white.opacity(0.22)
        case .primary:
            return .white.opacity(0.10)
        case .secondary:
            return .white.opacity(0.06)
        }
    }

    private var shadow: Color {
        switch style {
        case .accent:
            return Color.accentColor.opacity(0.35)
        case .primary, .secondary:
            return .black.opacity(0.10)
        }
    }
}

// MARK: - Text field

private struct ChatHistoryMenuButton: View {
    let sessions: [StoredChatSession]
    let isDisabled: Bool
    let onSelect: (StoredChatSession) -> Void

    var body: some View {
        Menu {
            if sessions.isEmpty {
                Text("No recent chats")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { session in
                    Button {
                        onSelect(session)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.displayTitle)
                                Text(session.updatedAt, style: .relative)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: session.contextKind == .capture ? "viewfinder" : "bubble.left.and.bubble.right")
                        }
                    }
                    .disabled(isDisabled)
                }
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(sessions.isEmpty ? .tertiary : .secondary)
            .frame(width: 40)
            .frame(height: 40)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(isDisabled || sessions.isEmpty)
        .help(sessions.isEmpty ? "No recent chats yet" : "Open a recent chat")
    }
}

private struct FileSourceMenuButton: View {
    let grants: [LocalFileGrant]
    let isDisabled: Bool
    let onGrantFolder: () -> Void
    let onGrantFile: () -> Void
    let onRemove: (LocalFileGrant) -> Void
    let onClear: () -> Void

    var body: some View {
        Menu {
            Button {
                onGrantFolder()
            } label: {
                Label("Choose Folder", systemImage: "folder.badge.plus")
            }

            Button {
                onGrantFile()
            } label: {
                Label("Choose File", systemImage: "doc.badge.plus")
            }

            if grants.isEmpty {
                Divider()
                Text("No file sources")
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                ForEach(grants) { grant in
                    Menu {
                        Button(role: .destructive) {
                            onRemove(grant)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(grant.displayName)
                                Text(grant.path)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: grant.isDirectory ? "folder" : "doc.text")
                        }
                    }
                }

                Divider()
                Button(role: .destructive) {
                    onClear()
                } label: {
                    Label("Clear File Sources", systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: grants.isEmpty ? "folder" : "folder.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .frame(width: 40)
            .frame(height: 40)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(isDisabled)
        .help(grants.isEmpty ? "Choose files Pixel Pane can read" : "Change file sources")
    }

}

private struct AssistantImageMenuButton: View {
    let context: AssistantImageContext?
    let isPreparing: Bool
    let isDisabled: Bool
    let onChoose: () -> Void
    let onClear: () -> Void

    var body: some View {
        Menu {
            Button {
                onChoose()
            } label: {
                Label(context == nil ? "Choose Image" : "Replace Image", systemImage: "photo.badge.plus")
            }

            if let context {
                Divider()
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.label)
                        Text(context.isOCRComplete ? "Text fallback ready" : "Preparing text fallback")
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "photo")
                }

                Divider()
                Button(role: .destructive) {
                    onClear()
                } label: {
                    Label("Clear Image", systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: context == nil ? "photo" : "photo.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(context == nil ? .secondary : .primary)
            .frame(width: 40)
            .frame(height: 40)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(context == nil ? 0.08 : 0.16), lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(isDisabled || isPreparing)
        .help(context == nil ? "Attach an image" : "Change attached image")
    }
}

private struct OverlayTextField: View {
    let placeholder: String
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.bubble")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.62, green: 0.80, blue: 1.0).opacity(0.72))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .focused(isFocused)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.075),
                            Color.white.opacity(0.035)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

// MARK: - Metadata chip

private struct OverlayMetadataChip: View {
    let badge: MetadataBadge

    var body: some View {
        Label(badge.text, systemImage: badge.systemImage)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.05), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.06), lineWidth: 1)
            }
            .help(badge.help)
    }
}

// MARK: - Recovery view

private struct ActionRecoveryView: View {
    let state: ActionRecoveryState
    let onPrimaryAction: () -> Void
    let onSecondaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: state.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(state.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            Text(state.detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                OverlayPillButton(
                    title: state.primaryTitle,
                    systemImage: state.primarySystemImage,
                    style: .accent,
                    action: onPrimaryAction
                )

                if let secondaryTitle = state.secondaryTitle, let onSecondaryAction {
                    OverlayPillButton(
                        title: secondaryTitle,
                        systemImage: state.secondarySystemImage ?? "arrow.clockwise",
                        style: .primary,
                        action: onSecondaryAction
                    )
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }
}

// MARK: - Typing placeholder

private struct TypingStatusView: View {
    let title: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.35)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate * 3) % 4
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.primary.opacity(index < phase ? 0.75 : 0.22))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(width: 20, alignment: .leading)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Chat transcript

private struct AskTranscriptView: View {
    let turns: [AskConversationTurn]
    let toolState: AssistantToolState
    let emptyText: String
    private let bottomAnchorID = "ask-transcript-bottom"

    private var latestTurnSignature: String {
        guard let lastTurn = turns.last else { return "empty" }
        return "\(turns.count)-\(lastTurn.question.count)-\(lastTurn.answer.count)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if turns.isEmpty, !emptyText.isEmpty {
                        Text(emptyText)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } else {
                        ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                            AskTurnView(index: index + 1, turn: turn, toolState: toolState)
                                .id(index)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)
                .padding(.bottom, 2)
                .id(bottomAnchorID)
            }
            .scrollIndicators(.automatic)
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: turns.count) { _, newCount in
                guard newCount > 0 else { return }
                scrollToBottom(proxy)
            }
            .onChange(of: latestTurnSignature) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard !turns.isEmpty else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }
}

private struct AssistantThinkingIndicator: View {
    @State private var phase = false
    private let accent = Color(red: 0.72, green: 0.82, blue: 1.0)

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(phase ? 0.18 : 0.34), lineWidth: 1.2)
                    .frame(width: 18, height: 18)
                    .scaleEffect(phase ? 1.22 : 0.78)
                    .blur(radius: phase ? 0.6 : 0)

                Circle()
                    .fill(accent.opacity(0.24))
                    .frame(width: 16, height: 16)
                    .blur(radius: 5)
                    .scaleEffect(phase ? 1.15 : 0.85)

                Circle()
                    .fill(accent.opacity(0.82))
                    .frame(width: 4.5, height: 4.5)
                    .shadow(color: accent.opacity(0.7), radius: phase ? 5 : 2)
            }
            .frame(width: 22, height: 22)

            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(accent.opacity(phase ? 0.95 : 0.38))
                        .frame(width: 4, height: phase ? 15 : 7)
                        .shadow(color: accent.opacity(0.35), radius: phase ? 4 : 1)
                        .animation(
                            .easeInOut(duration: 0.64)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.13),
                            value: phase
                        )
                }
            }
            .frame(width: 23, height: 18)

            Text("Thinking")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .onAppear {
            phase = true
        }
    }
}

private struct AskTurnView: View {
    let index: Int
    let turn: AskConversationTurn
    let toolState: AssistantToolState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Spacer(minLength: 80)

                Text(turn.question)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.07), lineWidth: 1)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 9) {
                metadataLine

                if turn.answer.isEmpty {
                    AssistantThinkingIndicator()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Thinking")
                } else {
                    FileLinkedAnswerText(
                        text: turn.answer,
                        baseDirectoryPaths: Self.baseDirectoryPaths(from: toolState)
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.065), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var metadataLine: some View {
        HStack(spacing: 6) {
            Image(systemName: backendIcon)
                .font(.system(size: 10, weight: .semibold))

            Text(metadataText)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .foregroundStyle(.tertiary)
    }

    private var backendIcon: String {
        switch turn.backendLabel {
        case "Pixel Pane Cloud":
            return "cloud"
        case "MLX Text":
            return "text.bubble"
        case "MLX Vision":
            return "eye"
        case "Local Files":
            return "folder"
        default:
            return "lock.laptopcomputer"
        }
    }

    private var compactBackendLabel: String {
        switch turn.backendLabel {
        case "Pixel Pane Cloud":
            return "Cloud"
        case "MLX Text":
            return "MLX Text"
        case "MLX Vision":
            return "MLX Vision"
        case "Local Files":
            return "Files"
        default:
            return "Local"
        }
    }

    private var metadataText: String {
        let values = turn.statistics.reduce(into: [String: AIModelOutputStatistic]()) { result, statistic in
            result[statistic.label] = statistic
        }
        let model = values["Cloud model"]?.value
        let peakMemory = values["Peak Memory"]?.value
        let actions = Int(values["Actions left"]?.value ?? values["Cloud actions left"]?.value ?? "")
        let reset = values["Actions left"]?.detail ?? values["Cloud actions left"]?.detail
        let usageText: String? = shouldShowCloudUsage(actions) ? actions.map { count in
            if let reset {
                return "\(count) left, \(reset)"
            }
            return "\(count) left"
        } : nil
        let memoryText = shouldShowPeakMemory ? peakMemory.map { "Peak \($0)" } : nil

        return [compactBackendLabel, model, memoryText, usageText]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " - ")
    }

    private func shouldShowCloudUsage(_ remainingActions: Int?) -> Bool {
        guard compactBackendLabel == "Cloud", let remainingActions else { return false }
        return remainingActions <= 10
    }

    private var shouldShowPeakMemory: Bool {
        compactBackendLabel == "MLX Text" || compactBackendLabel == "MLX Vision"
    }

    private static func baseDirectoryPaths(from toolState: AssistantToolState) -> [String] {
        var paths: [String] = []
        if let lastListedFolder = toolState.lastListedFolder {
            paths.append(lastListedFolder.path)
        }
        paths.append(contentsOf: toolState.grantedSourcesUsed.filter { $0.kindLabel == "Folder" }.map(\.path))
        paths.append(contentsOf: toolState.lastFileSources.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path })

        var seen: Set<String> = []
        return paths.filter { path in
            guard !path.isEmpty, !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }
}

private struct FileLinkedAnswerText: View {
    private enum Segment: Identifiable {
        case text(String, UUID)
        case path(display: String, path: String, UUID)

        var id: UUID {
            switch self {
            case .text(_, let id), .path(_, _, let id):
                return id
            }
        }
    }

    let text: String
    let baseDirectoryPaths: [String]

    var body: some View {
        let lineSegments = Self.lineSegments(in: text, baseDirectoryPaths: baseDirectoryPaths)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lineSegments.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    ForEach(lineSegments[index]) { segment in
                        switch segment {
                        case .text(let value, _):
                            Text(value)
                                .font(.system(size: 13.5))
                                .lineSpacing(4)
                                .textSelection(.enabled)

                        case .path(let display, let path, _):
                            FilePathChip(display: display, path: path)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static func lineSegments(in text: String, baseDirectoryPaths: [String]) -> [[Segment]] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { segments(in: String($0), baseDirectoryPaths: baseDirectoryPaths) }
    }

    private static func segments(in line: String, baseDirectoryPaths: [String]) -> [Segment] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(/Users/[^\s,\)\]\}\"']+)"#,
            options: []
        ) else {
            return [.text(line, UUID())]
        }

        let nsLine = line as NSString
        let matches = regex.matches(
            in: line,
            range: NSRange(location: 0, length: nsLine.length)
        )
        guard !matches.isEmpty else {
            return relativeListingSegments(in: line, baseDirectoryPaths: baseDirectoryPaths)
        }

        var result: [Segment] = []
        var cursor = 0
        for match in matches {
            let range = match.range(at: 1)
            if range.location > cursor {
                result.append(.text(nsLine.substring(with: NSRange(location: cursor, length: range.location - cursor)), UUID()))
            }
            let rawPath = nsLine.substring(with: range)
            let split = splitPathCandidate(rawPath)
            if !split.path.isEmpty {
                result.append(.path(display: displayName(for: split.path), path: split.path, UUID()))
            }
            if !split.trailingText.isEmpty {
                result.append(.text(split.trailingText, UUID()))
            }
            cursor = range.location + range.length
        }

        if cursor < nsLine.length {
            result.append(.text(nsLine.substring(from: cursor), UUID()))
        }

        return result
    }

    private static func relativeListingSegments(in line: String, baseDirectoryPaths: [String]) -> [Segment] {
        guard !baseDirectoryPaths.isEmpty else { return [.text(line, UUID())] }
        let prefixes = ["- File: ", "- Folder: "]
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else {
            return [.text(line, UUID())]
        }
        let name = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { return [.text(line, UUID())] }

        let resolvedPath = baseDirectoryPaths
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            .first { FileManager.default.fileExists(atPath: $0) }
            ?? URL(fileURLWithPath: baseDirectoryPaths[0]).appendingPathComponent(name).path

        return [
            .text(prefix, UUID()),
            .path(display: displayName(for: resolvedPath), path: resolvedPath, UUID())
        ]
    }

    private static func splitPathCandidate(_ candidate: String) -> (path: String, trailingText: String) {
        var path = candidate
        var trailing = ""
        while let last = path.last, ".,;:".contains(last) {
            trailing.insert(last, at: trailing.startIndex)
            path.removeLast()
        }
        return (path, trailing)
    }

    private static func displayName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        if !name.isEmpty {
            return name
        }
        return path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

}

private struct FilePathChip: View {
    let display: String
    let path: String

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))

                Text(display)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(Color(red: 0.72, green: 0.82, blue: 1.0))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: 220, alignment: .leading)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(path)
    }

    private var iconName: String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            return isDirectory.boolValue ? "folder" : "doc.text"
        }
        return URL(fileURLWithPath: path).pathExtension.isEmpty ? "folder" : "doc.text"
    }
}

// MARK: - Stats

private struct ModelStatisticsView: View {
    let statistics: [AIModelOutputStatistic]

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(statistics) { statistic in
                VStack(alignment: .leading, spacing: 2) {
                    Text(statistic.label)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(0.35)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 4) {
                        Text(statistic.value)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        if let detail = statistic.detail {
                            Text(detail)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.white.opacity(0.04), lineWidth: 1)
                }
            }
        }
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
    }
}

// MARK: - Capture preview

private struct CapturePreviewPane: View {
    let image: CGImage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                Text("Capture")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(image.width)×\(image.height)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(0.30))

                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(8)
            }
            .frame(height: 220)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }

            Text("Selected region")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct AskConversationTurn: Equatable {
    let question: String
    var answer: String
    var backendLabel: String
    var statistics: [AIModelOutputStatistic] = []

    init(
        question: String,
        answer: String,
        backendLabel: String,
        statistics: [AIModelOutputStatistic] = []
    ) {
        self.question = question
        self.answer = answer
        self.backendLabel = backendLabel
        self.statistics = statistics
    }

    init(storedTurn: StoredChatTurn) {
        question = storedTurn.question
        answer = storedTurn.answer
        backendLabel = storedTurn.backendLabel
        statistics = []
    }

    func storedTurn() -> StoredChatTurn {
        StoredChatTurn(
            id: UUID(),
            question: question,
            answer: answer,
            backendLabel: backendLabel,
            createdAt: Date()
        )
    }
}

private struct PanelActionOutputState: Equatable {
    var text: String
    var sourceLabel: String?
    var targetLabel: String?
    var backendLabel: String?
    var statistics: [AIModelOutputStatistic]
    var reasoning: String?
    var recovery: ActionRecoveryState?

    static let empty = PanelActionOutputState(
        text: "",
        sourceLabel: nil,
        targetLabel: nil,
        backendLabel: nil,
        statistics: [],
        reasoning: nil,
        recovery: nil
    )
}

private struct ActionRecoveryState: Equatable {
    let title: String
    let detail: String
    let systemImage: String
    let primaryTitle: String
    let primarySystemImage: String
    let primaryAction: RecoveryAction
    let secondaryTitle: String?
    let secondarySystemImage: String?
    let secondaryAction: RecoveryAction?

    static let emptyOCR = ActionRecoveryState(
        title: "No Text Found",
        detail: "Try a larger region, sharper text, or higher contrast. The captured image stays available until you close this panel.",
        systemImage: "text.viewfinder",
        primaryTitle: "Try Again",
        primarySystemImage: "viewfinder",
        primaryAction: .tryAgain,
        secondaryTitle: nil,
        secondarySystemImage: nil,
        secondaryAction: nil
    )

    init(error: Error) {
        let reason = (error as? AIBackendError)?.unavailableReason
        self = ActionRecoveryState(reason: reason, fallbackDetail: error.localizedDescription)
    }

    init(cloudError error: Error) {
        let title: String
        let detail = error.localizedDescription

        if let cloudError = error as? CloudAIBackendError {
            switch cloudError {
            case .rateLimited:
                title = "Cloud Limit Reached"
            case .unauthorized:
                title = "Cloud Authentication Failed"
            default:
                title = "Cloud Action Failed"
            }
        } else {
            title = "Cloud Action Failed"
        }

        self = ActionRecoveryState(
            title: title,
            detail: detail,
            systemImage: "cloud",
            primaryTitle: "Retry Cloud",
            primarySystemImage: "arrow.clockwise",
            primaryAction: .refresh,
            secondaryTitle: "Open Settings",
            secondarySystemImage: "gearshape",
            secondaryAction: .openSettings
        )
    }

    private init(reason: AIBackendUnavailableReason?, fallbackDetail: String) {
        guard let reason else {
            self = ActionRecoveryState(
                title: "Local Action Failed",
                detail: fallbackDetail,
                systemImage: "exclamationmark.triangle",
                primaryTitle: "Retry",
                primarySystemImage: "arrow.clockwise",
                primaryAction: .refresh,
                secondaryTitle: nil,
                secondarySystemImage: nil,
                secondaryAction: nil
            )
            return
        }

        switch reason {
        case .appleIntelligenceDisabled:
            self = ActionRecoveryState(
                title: reason.label,
                detail: reason.detail,
                systemImage: "apple.intelligence",
                primaryTitle: "Open Settings",
                primarySystemImage: "gearshape",
                primaryAction: .openAppleIntelligenceSettings,
                secondaryTitle: "Retry",
                secondarySystemImage: "arrow.clockwise",
                secondaryAction: .refresh
            )
        case .appleModelNotReady:
            self = ActionRecoveryState(
                title: reason.label,
                detail: "\(reason.detail) Keep this panel open and retry after the download finishes.",
                systemImage: "arrow.down.circle",
                primaryTitle: "Retry",
                primarySystemImage: "arrow.clockwise",
                primaryAction: .refresh,
                secondaryTitle: "Open Settings",
                secondarySystemImage: "gearshape",
                secondaryAction: .openAppleIntelligenceSettings
            )
        case .mlxRuntimeMissing, .mlxModelMissing, .mlxModelTooLarge, .mlxSmokeTestMissing, .hardwareUnsupported, .imageInputUnsupported:
            self = ActionRecoveryState(
                title: reason.label,
                detail: reason.detail,
                systemImage: "cpu",
                primaryTitle: "Open Settings",
                primarySystemImage: "gearshape",
                primaryAction: .openSettings,
                secondaryTitle: "Retry",
                secondarySystemImage: "arrow.clockwise",
                secondaryAction: .refresh
            )
        case .mlxGenerationTimeout, .generationFailed, .unknown:
            self = ActionRecoveryState(
                title: reason.label,
                detail: reason.detail,
                systemImage: "exclamationmark.triangle",
                primaryTitle: "Retry",
                primarySystemImage: "arrow.clockwise",
                primaryAction: .refresh,
                secondaryTitle: "Open Settings",
                secondarySystemImage: "gearshape",
                secondaryAction: .openSettings
            )
        case .cloudModeDisabled, .cloudImageConsentMissing:
            self = ActionRecoveryState(
                title: reason.label,
                detail: reason.detail,
                systemImage: "cloud",
                primaryTitle: "Retry Locally",
                primarySystemImage: "arrow.clockwise",
                primaryAction: .refresh,
                secondaryTitle: nil,
                secondarySystemImage: nil,
                secondaryAction: nil
            )
        case .promptTooLarge, .appleFrameworkUnavailable, .cancelled:
            self = ActionRecoveryState(
                title: reason.label,
                detail: reason.detail,
                systemImage: "exclamationmark.triangle",
                primaryTitle: "Retry",
                primarySystemImage: "arrow.clockwise",
                primaryAction: .refresh,
                secondaryTitle: nil,
                secondarySystemImage: nil,
                secondaryAction: nil
            )
        }
    }

    private init(
        title: String,
        detail: String,
        systemImage: String,
        primaryTitle: String,
        primarySystemImage: String,
        primaryAction: RecoveryAction,
        secondaryTitle: String?,
        secondarySystemImage: String?,
        secondaryAction: RecoveryAction?
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.primaryTitle = primaryTitle
        self.primarySystemImage = primarySystemImage
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondarySystemImage = secondarySystemImage
        self.secondaryAction = secondaryAction
    }
}

private extension AIActionKind {
    var panelActionKind: PanelActionKind {
        switch self {
        case .translate:
            .translate
        case .explain:
            .explain
        case .simplify:
            .simplify
        case .ask:
            .ask
        case .chat:
            .ask
        case .debug:
            .debug
        }
    }
}

private extension PanelActionKind {
    var supportsCloudImageInput: Bool {
        switch self {
        case .explain, .debug, .ask:
            true
        case .extractText, .translate, .simplify:
            false
        }
    }
}

private enum RecoveryAction: Equatable {
    case tryAgain
    case openSettings
    case openAppleIntelligenceSettings
    case refresh
}

private extension AIBackendError {
    var unavailableReason: AIBackendUnavailableReason? {
        switch self {
        case .unavailable(let reason):
            reason
        case .promptTooLarge(let maxCharacters):
            .promptTooLarge(maxCharacters: maxCharacters)
        case .generationFailed:
            .generationFailed
        case .cancelled:
            .cancelled
        }
    }
}

struct MetadataBadge: Identifiable {
    let id = UUID()
    let text: String
    let systemImage: String
    let help: String
}
