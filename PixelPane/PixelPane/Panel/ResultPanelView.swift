import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ResultPanelView: View {
    @Environment(\.openSettings) private var openSettings
    @FocusState private var isChatInputFocused: Bool

    let result: CaptureResult
    let routingSettings: AIRoutingSettings
    let localAICapabilities: AIBackendCapabilities
    @ObservedObject var localFileAccess: LocalFileAccessStore
    @ObservedObject var chatHistory: ChatHistoryStore
    @StateObject private var agentRunViewModel: AgentRunViewModel
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
    private let agentModelConformanceStore = AgentModelConformanceStore()
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
    @State private var assistantImageContext: AssistantImageContext?
    @State private var assistantToolState: AssistantToolState
    @State private var isPreparingAssistantImage = false
    @State private var chatContextID: String
    @State private var chatContextKind: ChatSessionContextKind
    @State private var didAppear = false
    @State private var didLoadAgentRunProjection = false
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
        _agentRunViewModel = StateObject(wrappedValue: AgentRunViewModel.makeDefault())
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
                initializeAgentRunProjectionIfNeeded()
                startSmartDefaultActionIfNeeded()
                focusChatInputSoon()
            }
            .onChange(of: loadingActions) { _, newValue in
                updateNotchNotificationState(isProcessing: !newValue.isEmpty)
            }
            .onChange(of: askInput) { _, _ in
                updateExpandedNotchSizeIfNeeded()
            }
            .onChange(of: askTurns.count) { _, _ in
                updateExpandedNotchSizeIfNeeded()
            }
            .onChange(of: loadingActions.contains(.ask)) { _, _ in
                updateExpandedNotchSizeIfNeeded()
            }
            .onChange(of: agentRunViewModel.state) { _, _ in
                applyAgentRunProjectionChange()
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

    private func initializeAgentRunProjectionIfNeeded() {
        guard !didLoadAgentRunProjection else { return }
        didLoadAgentRunProjection = true
        Task {
            try? await agentRunViewModel.loadOrCreateSession(context: agentRunViewContext())
            _ = try? await agentRunViewModel.recoverOnLaunch()
            applyAgentRunProjectionChange()
        }
    }

    private func agentRunViewContext() -> AgentRunViewContext {
        AgentRunViewContext(
            title: chatContextKind.displayName,
            contextID: chatContextID,
            contextKind: chatContextKind.rawValue,
            selectedAction: selectedAction.rawValue
        )
    }

    private func applyAgentRunProjectionChange() {
        if selectedAction == .ask {
            setOutputState(askOutputState(backendLabel: actionBackendLabel ?? askBackendLabelForNextTurn()), for: .ask)
        }
        updateNotchNotificationState(isProcessing: !visibleLoadingActions.isEmpty)
        updateExpandedNotchSizeIfNeeded()
    }

    private func durableAgentSystemPrompt() -> String {
        var sections = [
            "You are Pixel Pane's local-first macOS assistant.",
            "When Pixel Pane exposes local tools, use those tools instead of asking the user to run terminal commands or paste file listings.",
            "Answer the user's latest message directly. Do not claim that files, commands, or processes changed unless Pixel Pane records an approved side effect.",
            "Treat this chat as isolated from previous chats. Use only messages visible in this chat as conversation history.",
            "If asked about previous chats or sessions and this chat does not contain them, say that no previous chat context is available here.",
            "If the available context is insufficient, say what is missing instead of inventing details."
        ]

        if hasCaptureContext {
            let ocrText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ocrText.isEmpty {
                sections.append(
                    """
                    Current screen OCR:
                    \(Self.truncatedForDebugExport(ocrText, limit: 12_000))
                    """
                )
            }
        }

        if let visualContext = assistantToolState.activeVisualContext,
           let excerpt = visualContext.ocrExcerpt,
           !excerpt.isEmpty {
            sections.append(
                """
                Active visual context (\(visualContext.label)):
                \(Self.truncatedForDebugExport(excerpt, limit: 6_000))
                """
            )
        }

        return sections.joined(separator: "\n\n")
    }

    private func agentModelAttachmentsForAsk() -> [AgentKernelModelAttachmentV2] {
        guard let visualContext = assistantToolState.activeVisualContext else {
            return []
        }
        var metadata: [String: AgentKernelMetadataValueV2] = [
            "source": .string(visualContext.source.rawValue),
            "hasImageInput": .bool(visualContext.hasImageInput),
            "hasOCRText": .bool(visualContext.hasOCRText)
        ]
        if let ocrExcerpt = visualContext.ocrExcerpt, !ocrExcerpt.isEmpty {
            metadata["ocrText"] = .string(ocrExcerpt)
        }
        return [
            AgentKernelModelAttachmentV2(
                modality: visualContext.hasImageInput ? .image : .text,
                label: visualContext.label,
                transientOnly: true,
                metadata: metadata
            )
        ]
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
            agentRunApprovalSection
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
            agentRunApprovalSection
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
            focusChatInputImmediately()
            return
        }
        isNotchContentVisible = false
        onPresentationSizeChange?(targetSize)
        isNotchExpanded = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            guard isNotchExpanded else { return }
            isNotchContentVisible = true
            focusChatInputImmediately()
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
            focusChatInputImmediately()
        }
    }

    private func focusChatInputImmediately() {
        guard selectedAction == .ask else { return }
        guard presentationStyle != .notchAttached || isNotchExpanded else { return }
        isChatInputFocused = true
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
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            if isAskRunning {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, isBlankAssistantChat ? 4 : 10)
    }

    private var emptyAssistantWelcomeSection: some View {
        HStack(spacing: 6) {
            Text("Ready")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Circle()
                .fill(.secondary.opacity(0.45))
                .frame(width: 3, height: 3)

            Text(assistantModelStatusText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 10)

            HStack(spacing: 6) {
                EmptyAssistantStatusChip(
                    title: localFileAccess.grants.isEmpty ? "No Files" : "\(localFileAccess.grants.count) Files",
                    systemImage: localFileAccess.grants.isEmpty ? "folder" : "folder.fill"
                )
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
    }

    private var assistantModelStatusText: String {
        switch routingSettings.effectiveMode {
        case .cloud:
            return "Cloud Mode"
        case .local:
            if let selectedModelName {
                return "Local - \(selectedModelName)"
            }
            return localAICapabilities.text.isAvailable ? "Local - MLX" : "Local"
        }
    }

    private var selectedModelName: String? {
        guard let selection = mlxModelStore.selectedModel else { return nil }
        return Self.compactModelName(selection.repositoryID)
    }

    private static func compactModelName(_ repositoryID: String) -> String {
        let name = repositoryID
            .split(separator: "/")
            .last
            .map(String.init) ?? repositoryID
        return name
            .replacingOccurrences(of: "-Instruct", with: "")
            .replacingOccurrences(of: "-4bit", with: "")
            .replacingOccurrences(of: "-6bit", with: "")
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
        } else if selectedAction == .ask,
                  agentRunViewModel.state.activeStatus == .interrupted {
            AgentRunRecoveryControlView(
                summary: agentRunViewModel.state.statusSummary,
                onRetry: retryInterruptedAgentRun,
                onCancel: cancelAskQuestion
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
                .padding(.bottom, presentationStyle == .notchAttached ? 12 : 16)
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
    private var agentRunApprovalSection: some View {
        if selectedAction == .ask, !agentRunViewModel.state.pendingApprovals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(agentRunViewModel.state.pendingApprovals) { approval in
                    AgentRunApprovalCard(
                        approval: approval,
                        onApprove: { approveAgentRunApproval(approval) },
                        onDeny: { denyAgentRunApproval(approval) }
                    )
                }
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
                turns: displayedAskTurns,
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
            VStack(alignment: .leading, spacing: 8) {
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
                        isDisabled: !loadingActions.isEmpty || isAskRunning,
                        onGrantFolder: localFileAccess.grantFolder,
                        onGrantFile: localFileAccess.grantFile,
                        onRemove: localFileAccess.removeGrant,
                        onClear: localFileAccess.clearGrants
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
                        isDisabled: !loadingActions.isEmpty || isAskRunning,
                        onChoose: chooseAssistantImage,
                        onClear: clearAssistantImage
                    )

                    Spacer(minLength: 0)
                }

                HStack(alignment: .center, spacing: 8) {
                    OverlayTextField(
                        placeholder: hasCaptureContext ? "Ask about this screen" : "Ask Pixel Pane",
                        text: $askInput,
                        height: askComposerInputHeight,
                        isFocused: $isChatInputFocused,
                        onSubmit: sendAskQuestion
                    )
                    .layoutPriority(1)

                    if isAskRunning {
                        OverlayPillButton(
                            title: "Cancel",
                            systemImage: "xmark.circle.fill",
                            style: .accent,
                            displayStyle: .iconOnly,
                            action: cancelAskQuestion
                        )
                    } else {
                        OverlayPillButton(
                            title: "Send",
                            systemImage: "paperplane.fill",
                            style: .accent,
                            displayStyle: .iconOnly,
                            action: sendAskQuestion
                        )
                        .disabled(!canSendAskQuestion)
                    }
                }
                .frame(height: askComposerInputHeight)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .bottom)
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(activeText, forType: .string)
        showConfirmation("Copied")
    }

    private var canCopyChatTranscript: Bool {
        !displayedAskTurns.isEmpty
            || !agentRunViewModel.state.messages.isEmpty
            || !assistantToolState.recentToolResults.isEmpty
    }

    private func copyChatTranscript() {
        Task { @MainActor in
            let transcript = await chatTranscriptExportText()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
            showConfirmation("Chat copied")
        }
    }

    private func chatTranscriptExportText() async -> String {
        var sections: [String] = []
        sections.append(
            """
            # Pixel Pane Chat Export
            Exported: \(Self.chatExportDateString())
            Context: \(chatContextKind.displayName)
            Route: \(routingSettings.effectiveMode.displayName)
            Capture Context: \(hasCaptureContext ? "attached" : "none")
            Selected Action: \(selectedAction.title)
            Loading Actions: \(loadingActions.map(\.title).sorted().joined(separator: ", "))
            Current Backend Label: \(actionBackendLabel ?? "none")
            Current Source Label: \(actionSourceLabel ?? "none")
            Current Target Label: \(actionTargetLabel ?? "none")
            Active Text Characters: \(activeText.count)
            Private Reasoning Content: omitted from export
            """
        )

        sections.append(chatRuntimeDebugExportText())

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

        let exportTurns = displayedAskTurns
        if !exportTurns.isEmpty {
            let turnText = exportTurns.enumerated().map { index, turn in
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
            sections.append("## Agent Tool State Snapshot\n\(toolStateText)")
        }

#if DEBUG
        let debugAppendix = await debugChatExportAppendix()
        if !debugAppendix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(debugAppendix)
        }
#else
        if let traceExport = agentRunViewModel.state.traceExport,
           !traceExport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("## Latest Run Trace\n\(traceExport)")
        }
#endif

        return sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func chatRuntimeDebugExportText() -> String {
        var lines: [String] = [
            "## Observable Agent Debug Trace",
            "This section contains observable runtime events and UI state only. It is not the model's private hidden reasoning.",
            "- Chat Context ID: \(chatContextID)",
            "- Chat Context Kind: \(chatContextKind.displayName)",
            "- Durable Session ID: \(agentRunViewModel.state.sessionID?.uuidString ?? "none")",
            "- Durable Run ID: \(agentRunViewModel.state.activeRunID?.uuidString ?? "none")",
            "- Durable Run Status: \(agentRunViewModel.state.activeStatus?.rawValue ?? "none")",
            "- Durable Progress: \(agentRunViewModel.state.statusSummary)",
            "- Ask Input Draft: \(askInput.isEmpty ? "[empty]" : Self.truncatedForDebugExport(askInput, limit: 2_000))",
            "- Pending Durable Approvals: \(agentRunViewModel.state.pendingApprovals.count)"
        ]

        if !outputStatistics.isEmpty {
            lines.append("- Active Output Statistics:")
            lines.append(contentsOf: outputStatistics.map { statistic in
                let detail = statistic.detail.map { " (\($0))" } ?? ""
                return "  - \(statistic.label): \(statistic.value)\(detail)"
            })
        }

        if selectedAction != .ask,
           !activeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

#if DEBUG
    private func debugChatExportAppendix() async -> String {
        let model = await makeAgentKernelModelAdapter()
        let toolConfiguration = agentToolRunConfiguration(for: model)
        var sections: [String] = [
            """
            ## Debug Appendix (DEBUG only)
            Build Scope: DEBUG builds only; Release builds keep the normal transcript export.
            Removal: delete this DEBUG-only appendix builder and its call site in `chatTranscriptExportText()`.
            """
        ]

        sections.append(debugSessionProjectionSnapshot())
        sections.append(debugModelAndProviderSnapshot(model: model))
        sections.append(debugToolConfigurationSnapshot(toolConfiguration))
        sections.append(debugPromptAndContextSnapshot())
        sections.append(await debugAllRunTracesSnapshot())

        return sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func debugSessionProjectionSnapshot() -> String {
        let state = agentRunViewModel.state
        let projectedRunIDs = Array(Set(state.messages.map { $0.runID.uuidString })).sorted()
        var lines: [String] = [
            "- Session ID: \(state.sessionID?.uuidString ?? "none")",
            "- Active Run ID: \(state.activeRunID?.uuidString ?? "none")",
            "- Active Status: \(state.activeStatus?.rawValue ?? "none")",
            "- Status Summary: \(state.statusSummary)",
            "- Updated At: \(state.updatedAt.map { Self.chatExportDateString($0) } ?? "none")",
            "- Visible Durable Messages: \(state.messages.count)",
            "- Displayed Ask Turns: \(displayedAskTurns.count)",
            "- Projected Run IDs: \(Self.debugJoinedList(projectedRunIDs))",
            "- Pending Approvals: \(state.pendingApprovals.count)"
        ]

        if let recovery = state.recovery {
            lines.append("- Recovery Interrupted Runs: \(Self.debugJoinedList(recovery.interruptedRunIDs.map(\.uuidString)))")
            lines.append("- Recovery Pending Waits: \(Self.debugJoinedList(recovery.pendingWaitIDs.map(\.uuidString)))")
        }

        if !state.pendingApprovals.isEmpty {
            lines.append("- Pending Approval Details:")
            lines.append(
                contentsOf: state.pendingApprovals.prefix(12).map { approval in
                    "  - \(approval.kind.rawValue) wait=\(approval.waitID.uuidString) run=\(approval.runID.uuidString) title=\(approval.title)"
                }
            )
            if state.pendingApprovals.count > 12 {
                lines.append("  - ... \(state.pendingApprovals.count - 12) more")
            }
        }

        return "### Session And UI Projection\n\(lines.joined(separator: "\n"))"
    }

    private func debugModelAndProviderSnapshot(model: any AgentKernelModelAdapterV2) -> String {
        let descriptor = model.descriptor
        let capabilities = model.capabilities
        let selectedModel = mlxModelStore.selectedModel
        let conformanceProfile = currentMLXAgentConformanceProfile()
        let tier = AgentModelGateway.tier(
            for: capabilities,
            conformanceProfile: conformanceProfile
        )
        let cloudModels = debugStatisticValues(named: "Cloud model")
        var lines: [String] = [
            "- Effective Model Being Used: \(debugEffectiveModelLabel(model: model))",
            "- Selected Backend ID: \(selectedAIBackend.id)",
            "- Selected Backend Display Name: \(selectedAIBackend.displayName)",
            "- Current Backend Label: \(actionBackendLabel ?? "none")",
            "- Next Ask Backend Label: \(askBackendLabelForNextTurn())",
            "- Adapter Descriptor ID: \(descriptor.id)",
            "- Adapter Display Name: \(descriptor.displayName)",
            "- Adapter Provider Kind: \(descriptor.providerKind.rawValue)",
            "- Adapter Route: \(descriptor.route.rawValue)",
            "- Adapter Model Name: \(descriptor.modelName ?? "none")",
            "- Capability Tier: \(tier.rawValue)",
            "- Agent Conformance Tier: \(conformanceProfile?.derivedTier.rawValue ?? "not_checked")",
            "- Agent Conformance Tested At: \(conformanceProfile.map { Self.chatExportDateString($0.testedAt) } ?? "none")",
            "- Agent Conformance Plain Chat: \(conformanceProfile?.plainChat.status.rawValue ?? "none")",
            "- Agent Conformance Structured JSON: \(conformanceProfile?.structuredJSON.status.rawValue ?? "none")",
            "- Agent Conformance Tool Call: \(conformanceProfile?.toolCall.status.rawValue ?? "none")",
            "- Agent Conformance Tool Follow-Up: \(conformanceProfile?.toolResultFollowUp.status.rawValue ?? "none")",
            "- Cloud-Assisted Local Tools: \(descriptor.route == .cloud && tier != .tierCPlainChat ? "enabled" : "disabled")",
            "- Tool Calling Mode: \(capabilities.toolCallingMode.rawValue)",
            "- Structured Output Reliability: \(capabilities.structuredOutputReliability.rawValue)",
            "- Streaming Mode: \(capabilities.streamingMode.rawValue)",
            "- Input Modalities: \(Self.debugJoinedList(capabilities.inputModalities.map(\.rawValue).sorted()))",
            "- Output Modalities: \(Self.debugJoinedList(capabilities.outputModalities.map(\.rawValue).sorted()))",
            "- Adapter Available: \(capabilities.isAvailable ? "yes" : "no")",
            "- Adapter Unavailable Reason: \(capabilities.unavailableReason?.text ?? "none")",
            "- Context Window Tokens: \(capabilities.limits.contextWindowTokens.map(String.init) ?? "unknown")",
            "- Max Prompt Characters: \(capabilities.limits.maxPromptCharacters)",
            "- Max Output Tokens: \(capabilities.limits.maxOutputTokens)",
            "- Reported Cloud Model Statistics: \(Self.debugJoinedList(cloudModels))",
            "- Local Text Capability: \(Self.debugCapabilityStatus(localAICapabilities.text))",
            "- Local Image Capability: \(Self.debugCapabilityStatus(localAICapabilities.image))",
            "- MLX Setup State: \(mlxModelStore.setupState.rawValue)",
            "- MLX Setup Failure: \(mlxModelStore.setupFailure ?? "none")",
            "- Selected MLX Repository: \(selectedModel?.repositoryID ?? "none")",
            "- Selected MLX Local Path: \(selectedModel?.localPath ?? "none")",
            "- Selected MLX Smoke Tested At: \(selectedModel.map { Self.chatExportDateString($0.smokeTestedAt) } ?? "none")"
        ]

        if let modelName = selectedModelName {
            lines.append("- Compact Selected Model Name: \(modelName)")
        }

        return "### Model And Provider Snapshot\n\(lines.joined(separator: "\n"))"
    }

    private func debugToolConfigurationSnapshot(
        _ configuration: (
            mode: AgentModelGatewayMode,
            tools: [AgentKernelToolSchemaV2],
            context: AgentToolRunContext
        )
    ) -> String {
        let tools = configuration.tools.map(\.name).sorted()
        let grants = configuration.context.localGrants
        var lines: [String] = [
            "- Gateway Mode: \(configuration.mode.rawValue)",
            "- Run Permission Mode: \(configuration.context.runMode.rawValue)",
            "- Active Tool Capability: \(configuration.mode == .plainChat || tools.isEmpty ? "plain-chat" : "agent-tools")",
            "- Visible Tool Count: \(tools.count)",
            "- Visible Tools: \(Self.debugJoinedList(tools, maxVisible: 40))",
            "- Supported Operations: \(Self.debugJoinedList(configuration.context.supportedOperations.map(\.rawValue).sorted()))",
            "- Granted Scopes: \(Self.debugJoinedList(configuration.context.grantedScopes.map(\.rawValue).sorted()))",
            "- Denied Scopes: \(Self.debugJoinedList(configuration.context.deniedScopes.map(\.rawValue).sorted()))",
            "- Runtime Local Grants: \(grants.count)"
        ]

        if !grants.isEmpty {
            lines.append("- Runtime Local Grant Details:")
            lines.append(
                contentsOf: grants.prefix(20).map { grant in
                    let kind = grant.isDirectory ? "folder" : "file"
                    return "  - \(kind): \(grant.path)"
                }
            )
            if grants.count > 20 {
                lines.append("  - ... \(grants.count - 20) more")
            }
        }

        return "### Tool And Permission Snapshot\n\(lines.joined(separator: "\n"))"
    }

    private func debugPromptAndContextSnapshot() -> String {
        let latestUserMessage = latestAgentUserMessage()
        var lines: [String] = [
            "- Ask Max Output Tokens: \(AssistantResponsePolicy.maxOutputTokens(for: .ask))",
            "- Latest User Message Characters: \(latestUserMessage.count)",
            "- Ask Draft Characters: \(askInput.count)",
            "- Active Text Characters: \(activeText.count)",
            "- Capture Context Attached: \(hasCaptureContext ? "yes" : "no")",
            "- Assistant Image Context Attached: \(assistantImageContext == nil ? "no" : "yes")",
            "- Active Visual Tool Context Attached: \(assistantToolState.activeVisualContext == nil ? "no" : "yes")",
            "- Recent Tool Results: \(assistantToolState.recentToolResults.count)",
            "- Recent File Sources: \(assistantToolState.lastFileSources.count)",
            "- Granted Sources Used: \(assistantToolState.grantedSourcesUsed.count)",
            "- Recent File Snippets: \(assistantToolState.lastFileSnippets.count)"
        ]

        if !latestUserMessage.isEmpty {
            lines.append("- Latest User Message Excerpt:")
            lines.append(Self.truncatedForDebugExport(latestUserMessage, limit: 2_000))
        }

        if let imageContext = assistantImageContext {
            lines.append("- Assistant Image Source: \(Self.displayName(for: imageContext.source))")
            lines.append("- Assistant Image Label: \(imageContext.label)")
            lines.append("- Assistant Image OCR Characters: \(imageContext.ocrText?.count ?? 0)")
        }

        if let visualContext = assistantToolState.activeVisualContext {
            lines.append("- Visual Tool Source: \(visualContext.source.rawValue)")
            lines.append("- Visual Tool Label: \(visualContext.label)")
            lines.append("- Visual Tool Has Image Input: \(visualContext.hasImageInput ? "yes" : "no")")
            lines.append("- Visual Tool Has OCR Text: \(visualContext.hasOCRText ? "yes" : "no")")
            lines.append("- Visual Tool Updated At: \(Self.chatExportDateString(visualContext.updatedAt))")
        }

        return "### Prompt And Context Snapshot\n\(lines.joined(separator: "\n"))"
    }

    private func debugAllRunTracesSnapshot() async -> String {
        let traceExports = await agentRunViewModel.debugTraceExportsForCurrentSession()
        guard !traceExports.isEmpty else {
            return "### All Run Traces\nTrace Count: 0"
        }

        let traceSections = traceExports.enumerated().map { index, traceExport in
            """
            #### Run Trace \(index + 1)
            \(Self.truncatedForDebugExport(traceExport, limit: 60_000))
            """
        }

        return """
        ### All Run Traces
        Trace Count: \(traceExports.count)

        \(traceSections.joined(separator: "\n\n"))
        """
    }

    private func debugEffectiveModelLabel(model: any AgentKernelModelAdapterV2) -> String {
        let descriptor = model.descriptor
        if descriptor.route == .cloud {
            let cloudModels = debugStatisticValues(named: "Cloud model")
            if !cloudModels.isEmpty {
                return "Pixel Pane Cloud - \(Self.debugJoinedList(cloudModels))"
            }
            return descriptor.modelName.map { "\(descriptor.displayName) - \($0)" }
                ?? "\(descriptor.displayName) (exact upstream model not reported yet)"
        }
        switch descriptor.providerKind {
        case .appleLocal:
            return descriptor.modelName.map { "Apple Foundation Models - \($0)" } ?? "Apple Foundation Models"
        case .mlxLocal:
            if let selection = mlxModelStore.selectedModel {
                return "\(selection.repositoryID) [MLX] at \(selection.localPath)"
            }
            return descriptor.modelName.map { "\($0) [MLX]" } ?? "MLX local model (selection unavailable)"
        case .pixelPaneCloud:
            return descriptor.modelName.map { "Pixel Pane Cloud - \($0)" } ?? "Pixel Pane Cloud"
        case .fixture, .openAICompatible, .custom:
            return descriptor.modelName.map { "\(descriptor.displayName) - \($0)" } ?? descriptor.displayName
        }
    }

    private func debugStatisticValues(named label: String) -> [String] {
        let activeValues = outputStatistics
            .filter { $0.label == label }
            .map(\.value)
        let turnValues = displayedAskTurns.flatMap { turn in
            turn.statistics
                .filter { $0.label == label }
                .map(\.value)
        }
        return Array(Set(activeValues + turnValues)).sorted()
    }

    private static func debugCapabilityStatus(_ status: AIBackendCapabilityStatus) -> String {
        "\(status.label) - \(status.detail)"
    }

    private static func debugJoinedList(_ values: [String], maxVisible: Int = 20) -> String {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "none" }
        let visibleCount = min(cleaned.count, max(1, maxVisible))
        let visible = cleaned.prefix(visibleCount).joined(separator: ", ")
        let remaining = cleaned.count - visibleCount
        return remaining > 0 ? "\(visible), ... (+\(remaining) more)" : visible
    }
#endif

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
        var actions = loadingActions
        if agentRunViewModel.state.isBusy {
            actions.insert(.ask)
        }
        return actions
    }

    private var isAskRunning: Bool {
        loadingActions.contains(.ask) || agentRunViewModel.state.isBusy
    }

    private var displayedAskTurns: [AskConversationTurn] {
        let projected = agentRunProjectedAskTurns()
        return projected.isEmpty ? askTurns : projected
    }

    private func agentRunProjectedAskTurns() -> [AskConversationTurn] {
        guard !agentRunViewModel.state.messages.isEmpty else { return [] }

        var turns: [AskConversationTurn] = []
        for message in agentRunViewModel.state.messages {
            switch message.role {
            case .user:
                turns.append(
                    AskConversationTurn(
                        question: message.text.text,
                        answer: "",
                        backendLabel: actionBackendLabel ?? askBackendLabelForNextTurn()
                    )
                )
            case .assistant:
                let answer = displayTextNormalizer.normalize(message.text.text)
                if let index = turns.indices.last, turns[index].answer.isEmpty {
                    turns[index].answer = answer
                } else {
                    turns.append(
                        AskConversationTurn(
                            question: "Continue",
                            answer: answer,
                            backendLabel: actionBackendLabel ?? askBackendLabelForNextTurn()
                        )
                    )
                }
            }
        }

        if let index = turns.indices.last,
           turns[index].answer.isEmpty,
           agentRunViewModel.state.activeStatus != .completed {
            switch agentRunViewModel.state.activeStatus {
            case .queued, .running, .waitingForApproval, .waitingForUserInput, .interrupted:
                turns[index].runtimeProgressSummary = agentRunViewModel.state.statusSummary
            case .blocked, .failed, .canceled:
                turns[index].answer = agentRunViewModel.state.statusSummary
            case .draft, .completed, .none:
                break
            }
        }

        return turns
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
            && displayedAskTurns.isEmpty
            && !hasCaptureContext
            && recoveryState == nil
    }

    private var canStartNewChat: Bool {
        selectedAction == .ask
            && !isAskRunning
            && (!displayedAskTurns.isEmpty || hasCaptureContext || recoveryState != nil)
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
        let width: CGFloat = hasCaptureContext ? 820 : 760
        let headerHeight: CGFloat = 82
        let chipHeight: CGFloat = assistantContextBadges.isEmpty ? 0 : 34
        let composerHeight = estimatedAskComposerHeight
        let recoveryHeight: CGFloat = recoveryState == nil ? 0 : 96
        let approvalHeight: CGFloat = agentRunViewModel.state.pendingApprovals.isEmpty ? 0 : 136
        let transcriptHeight = estimatedAskTranscriptHeight
        let height = headerHeight
            + transcriptHeight
            + chipHeight
            + composerHeight
            + recoveryHeight
            + approvalHeight
            + 14

        return CGSize(
            width: width,
            height: min(ResultPanelPresentationStyle.notchExpandedSize.height, max(280, height))
        )
    }

    private var estimatedAskComposerHeight: CGFloat {
        AskComposerMetrics.toolbarHeight
            + AskComposerMetrics.verticalSpacing
            + askComposerInputHeight
    }

    private var askComposerInputHeight: CGFloat {
        let trimmed = askInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AskComposerMetrics.minimumInputHeight }
        let explicitLines = CGFloat(trimmed.filter { $0 == "\n" }.count + 1)
        let wrappedLines = ceil(CGFloat(trimmed.count) / 72)
        let lines = min(5, max(1, max(explicitLines, wrappedLines)))
        return min(
            AskComposerMetrics.maximumInputHeight,
            AskComposerMetrics.minimumInputHeight + (lines - 1) * AskComposerMetrics.lineHeight
        )
    }

    private var estimatedAskTranscriptHeight: CGFloat {
        let turns = displayedAskTurns
        guard !turns.isEmpty else {
            return hasCaptureContext ? 52 : 0
        }

        let visibleTurns = turns.suffix(3)
        let estimated = visibleTurns.reduce(CGFloat(0)) { total, turn in
            let questionLines = max(1, ceil(CGFloat(turn.question.count) / 64))
            let answerText = turn.answer.isEmpty ? "Thinking..." : turn.answer
            let answerLines = max(1, ceil(CGFloat(answerText.count) / 92))
            let questionHeight = 26 + questionLines * 15
            let answerHeight = 42 + answerLines * 17
            return total + questionHeight + answerHeight + 18
        }

        return min(460, max(132, estimated))
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

        guard AssistantResponsePolicy.usesImageInput(for: action) else { return nil }
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
        switch localAICapabilities.text {
        case .available(.mlxText):
            return Self.mlxTextBackendLabel
        case .available(.appleFoundationModels):
            return Self.appleTextBackendLabel
        case .available(.mlxVision):
            return Self.mlxVisionBackendLabel
        case .available(.pixelPaneCloud):
            return Self.cloudBackendLabel
        case .installing, .unavailable:
            return Self.appleTextBackendLabel
        }
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
        - \(AssistantResponsePolicy.outputGuidance)
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
                    maxOutputTokens: AssistantResponsePolicy.maxOutputTokens(for: .simplify),
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
            - \(AssistantResponsePolicy.outputGuidance)
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
            - \(AssistantResponsePolicy.outputGuidance)
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
                    maxOutputTokens: AssistantResponsePolicy.maxOutputTokens(for: .explain),
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
            Debug the following captured technical text. Explain the likely issue, cite the relevant error or code clue, and suggest concrete next steps. \(AssistantResponsePolicy.outputGuidance) Avoid inventing missing project context.

            Classifier evidence: \(evidence)

            Captured text:
            \(result.text)
            """
        } else {
            prompt = """
            Debug this captured technical screenshot. Use both the OCR text and visible UI context, such as highlighted lines, terminal prompts, IDE panels, or error overlays. Explain the likely issue and suggest concrete next steps. \(AssistantResponsePolicy.outputGuidance) Avoid inventing missing project context.

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
                    maxOutputTokens: AssistantResponsePolicy.maxOutputTokens(for: .debug),
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
            && !isAskRunning
            && !isPreparingAssistantImage
            && !askInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendAskQuestion() {
        let question = askInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAskRunning else { return }
        askInput = ""
        recoveryState = nil
        hiddenReasoning = nil
        outputStatistics = []
        let backendLabel = askBackendLabelForNextTurn()
        actionBackendLabel = backendLabel
        setOutputState(askOutputState(backendLabel: backendLabel), for: .ask)
        updateExpandedNotchSizeIfNeeded()

        Task {
            do {
                let model = await makeAgentKernelModelAdapter(userMessage: question)
                let conformanceProfile = currentMLXAgentConformanceProfile()
                let toolConfiguration = agentToolRunConfiguration(for: model)
                try await agentRunViewModel.startRun(
                    userMessage: question,
                    context: agentRunViewContext(),
                    adapter: model,
                    mode: toolConfiguration.mode,
                    tools: toolConfiguration.tools,
                    toolContext: toolConfiguration.context,
                    modelConformanceProfile: conformanceProfile,
                    attachments: agentModelAttachmentsForAsk(),
                    systemPrompt: durableAgentSystemPrompt(),
                    maxOutputTokens: AssistantResponsePolicy.maxOutputTokens(for: .ask)
                )
                setOutputState(askOutputState(backendLabel: backendLabel), for: .ask)
                updateExpandedNotchSizeIfNeeded()
            } catch {
                updateLastAskAnswer("The agent could not start: \(error)", backendLabel: backendLabel)
                setOutputState(askOutputState(backendLabel: backendLabel), for: .ask)
                updateExpandedNotchSizeIfNeeded()
            }
        }
    }

    private func cancelAskQuestion() {
        if routingSettings.effectiveMode == .local {
            Task {
                await MLXTextServerManager.terminateCurrentProcess()
            }
        }
        Task {
            await agentRunViewModel.cancelRun()
            setOutputState(askOutputState(), for: .ask)
            updateExpandedNotchSizeIfNeeded()
            focusChatInputSoon()
        }
    }

    private func makeAgentKernelModelAdapter(userMessage: String? = nil) async -> any AgentKernelModelAdapterV2 {
        let backend = selectedAIBackend
        let capabilities = await backend.capabilities()
        let modeID: String = routingSettings.effectiveMode == .cloud ? "cloud" : "local"
        let provider = effectiveAskProvider(capabilities: capabilities)
        let providerKind = agentProviderKind(for: provider)
        let modelName = agentModelName(for: provider)
        let displayName = agentDisplayName(for: provider, fallback: askBackendLabelForNextTurn())
        let descriptor = AgentKernelModelDescriptorV2(
            id: "\(modeID).\(backend.id).chat",
            providerKind: providerKind,
            route: routingSettings.effectiveMode == .cloud ? .cloud : .local,
            displayName: displayName,
            modelName: modelName
        )
        if routingSettings.effectiveMode == .cloud {
            return AgentKernelCloudChatAdapterV2(
                descriptor: descriptor,
                backend: backend,
                backendCapabilities: capabilities,
                preferredProvider: provider,
                supportsLocalToolProtocol: true
            )
        }
        let baseCapabilities = AgentKernelModelAdapterCapabilitiesV2.aiBackendBridge(
            descriptor: descriptor,
            backendCapabilities: capabilities
        )
        let adjustedCapabilities = baseCapabilities.applyingAgentConformanceProfile(
            currentMLXAgentConformanceProfile()
        )
        if provider == .mlxText {
            return AgentKernelMLXNativeToolAdapterV2(
                descriptor: descriptor,
                backend: MLXTextBackend(store: mlxModelStore),
                capabilities: adjustedCapabilities,
                preferredProvider: .mlxText
            )
        }
        return AgentKernelAIBackendAdapterV2(
            descriptor: descriptor,
            backend: backend,
            capabilities: adjustedCapabilities,
            preferredProvider: provider
        )
    }

    private func effectiveAskProvider(capabilities: AIBackendCapabilities) -> AIBackendProvider? {
        if routingSettings.effectiveMode == .cloud {
            return .pixelPaneCloud
        }
        if case .available(let provider) = capabilities.text {
            return provider
        }
        return nil
    }

    private func agentProviderKind(for provider: AIBackendProvider?) -> AgentKernelModelProviderKindV2 {
        switch provider {
        case .appleFoundationModels:
            return .appleLocal
        case .mlxText, .mlxVision:
            return .mlxLocal
        case .pixelPaneCloud:
            return .pixelPaneCloud
        case .none:
            return routingSettings.effectiveMode == .cloud ? .pixelPaneCloud : .custom
        }
    }

    private func agentModelName(for provider: AIBackendProvider?) -> String? {
        switch provider {
        case .mlxText, .mlxVision:
            return mlxModelStore.selectedModel?.repositoryID
        case .appleFoundationModels:
            return nil
        case .pixelPaneCloud:
            return debugStatisticValues(named: "Cloud model").last
        case .none:
            return nil
        }
    }

    private func agentDisplayName(for provider: AIBackendProvider?, fallback: String) -> String {
        switch provider {
        case .appleFoundationModels:
            return Self.appleTextBackendLabel
        case .mlxText:
            return Self.mlxTextBackendLabel
        case .mlxVision:
            return Self.mlxVisionBackendLabel
        case .pixelPaneCloud:
            return Self.cloudBackendLabel
        case .none:
            return fallback
        }
    }

    private func agentToolRunConfiguration(
        for model: any AgentKernelModelAdapterV2
    ) -> (mode: AgentModelGatewayMode, tools: [AgentKernelToolSchemaV2], context: AgentToolRunContext) {
        let conformanceProfile = currentMLXAgentConformanceProfile()
        let providerTier = AgentModelGateway.tier(
            for: model.capabilities,
            conformanceProfile: conformanceProfile
        )
        let grants = agentRuntimeLocalGrants()
        let usesLocalEvidenceSynthesis = model.descriptor.providerKind == .mlxLocal
            && model.descriptor.route == .local
            && providerTier == .tierCPlainChat
        let runMode: AgentRunPermissionMode
        if providerTier == .tierCPlainChat {
            runMode = usesLocalEvidenceSynthesis ? .readOnly : .plainChat
        } else if grants.isEmpty {
            runMode = .readOnly
        } else {
            runMode = providerTier == .tierAFullAgent ? .fullAgent : .proposalOnly
        }

        let context = AgentToolRunContext(
            runMode: runMode,
            localGrants: grants,
            grantedScopes: [],
            deniedScopes: [.network, .processControl, .privileged],
            supportedOperations: AgentToolExecutionCapabilities.activeLocalRuntimeOperations
        )
        guard providerTier != .tierCPlainChat, runMode != .plainChat else {
            return (.plainChat, [], context)
        }

        let tools = AgentToolCatalog().visibleModelSchemas(
            providerTier: providerTier,
            runMode: runMode,
            localGrants: grants,
            grantedScopes: context.grantedScopes,
            deniedScopes: context.deniedScopes,
            supportedOperations: context.supportedOperations
        )
        guard !tools.isEmpty else {
            return (.plainChat, [], context)
        }
        let mode: AgentModelGatewayMode = providerTier == .tierAFullAgent
            ? .fullAgent
            : .constrainedStructuredText
        return (mode, tools, context)
    }

    private func currentMLXAgentConformanceProfile() -> AgentModelConformanceProfile? {
        guard let selection = mlxModelStore.selectedModel else { return nil }
        let target = AgentModelConformanceTarget.mlxText(
            selection: selection,
            textRuntimeURL: mlxDetector.mlxTextGenerateExecutableURL()
        )
        return agentModelConformanceStore.profile(for: target)
    }

    private func agentRuntimeLocalGrants() -> [AgentLocalFileGrant] {
        localFileAccess.grants.map { grant in
            AgentLocalFileGrant(
                path: grant.path,
                isDirectory: grant.isDirectory
            )
        }
    }

    private func latestAgentUserMessage() -> String {
        agentRunViewModel.state.messages
            .reversed()
            .first { $0.role == .user }?
            .text
            .text ?? ""
    }

    private func approveAgentRunApproval(_ approval: AgentRunProjectedApproval) {
        Task {
            do {
                let model = await makeAgentKernelModelAdapter()
                let conformanceProfile = currentMLXAgentConformanceProfile()
                try await agentRunViewModel.approveWait(
                    approval.waitID,
                    adapter: model,
                    modelConformanceProfile: conformanceProfile
                )
                showConfirmation("Approved")
                setOutputState(askOutputState(), for: .ask)
                updateExpandedNotchSizeIfNeeded()
                focusChatInputSoon()
            } catch {
                updateLastAskAnswer("Approval failed: \(error)", backendLabel: "Agent")
                setOutputState(askOutputState(), for: .ask)
            }
        }
    }

    private func denyAgentRunApproval(_ approval: AgentRunProjectedApproval) {
        Task {
            do {
                let model = await makeAgentKernelModelAdapter()
                let conformanceProfile = currentMLXAgentConformanceProfile()
                try await agentRunViewModel.denyWait(
                    approval.waitID,
                    adapter: model,
                    modelConformanceProfile: conformanceProfile
                )
                showConfirmation("Denied")
                setOutputState(askOutputState(), for: .ask)
                updateExpandedNotchSizeIfNeeded()
                focusChatInputSoon()
            } catch {
                updateLastAskAnswer("Could not deny approval: \(error)", backendLabel: "Agent")
                setOutputState(askOutputState(), for: .ask)
            }
        }
    }

    private func retryInterruptedAgentRun() {
        Task {
            do {
                try await agentRunViewModel.retryInterruptedRun()
                showConfirmation("Queued")
                setOutputState(askOutputState(), for: .ask)
                updateExpandedNotchSizeIfNeeded()
            } catch {
                updateLastAskAnswer("Retry failed: \(error)", backendLabel: "Agent")
                setOutputState(askOutputState(), for: .ask)
            }
        }
    }

    private func updateLastAskAnswer(_ answer: String, backendLabel: String) {
        if let index = askTurns.indices.last {
            askTurns[index].answer = answer
            askTurns[index].backendLabel = backendLabel
            askTurns[index].runtimeProgressSummary = nil
        } else {
            askTurns.append(AskConversationTurn(question: "Continue", answer: answer, backendLabel: backendLabel))
        }
        actionBackendLabel = backendLabel
    }

    private func persistAskSession() {
        Task {
            await agentRunViewModel.refresh()
        }
    }

    private func loadAgentRunSession(_ session: AgentRunProjectedSession) {
        guard loadingActions.isEmpty, !isAskRunning else { return }
        assistantImageContext = nil
        isPreparingAssistantImage = false
        if let contextID = session.contextID {
            chatContextID = contextID
        }
        if let contextKind = session.contextKind,
           let kind = ChatSessionContextKind(rawValue: contextKind) {
            chatContextKind = kind
        }
        askTurns = []
        selectedAction = .ask
        Task {
            try? await agentRunViewModel.loadSession(sessionID: session.id)
            setOutputState(askOutputState(), for: .ask)
            updateExpandedNotchSizeIfNeeded()
            focusChatInputSoon()
        }
    }

    private func startNewAssistantChat() {
        guard loadingActions.isEmpty, !isAskRunning else { return }
        suppressNextNotchHoverCollapseBriefly()
        assistantImageContext = nil
        isPreparingAssistantImage = false
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
        Task {
            try? await agentRunViewModel.startNewSession(context: agentRunViewContext())
        }
        focusChatInputSoon()
    }

    private func clearChatHistory() {
        guard loadingActions.isEmpty, !isAskRunning else { return }
        Task {
            try? await agentRunViewModel.clearHistory()
            chatHistory.clearAll()
            askTurns = []
            setOutputState(askOutputState(), for: .ask)
            updateExpandedNotchSizeIfNeeded()
            showConfirmation("History cleared")
        }
    }

    private func formattedAskTranscript() -> String {
        displayedAskTurns
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
        let turns = displayedAskTurns
        return PanelActionOutputState(
            text: turns.isEmpty
                ? (hasCaptureContext
                    ? "Chat about this capture."
                    : "")
                : formattedAskTranscript(),
            sourceLabel: hasCaptureContext ? "Source: \(result.detectedLanguage.displayName)" : nil,
            targetLabel: nil,
            backendLabel: backendLabel ?? turns.last?.backendLabel ?? askBackendLabelForNextTurn(),
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
        - \(AssistantResponsePolicy.outputGuidance)
        - Return only the translated text, with no notes or explanation.

        Detected source language: \(result.detectedLanguage.displayName)

        \(result.text)
        """

        let request = AIBackendRequest(
            actionKind: .translate,
            prompt: prompt,
            capturedImage: nil,
            maxOutputTokens: AssistantResponsePolicy.maxOutputTokens(for: .translate),
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

    private enum AskComposerMetrics {
        static let toolbarHeight: CGFloat = 40
        static let verticalSpacing: CGFloat = 8
        static let minimumInputHeight: CGFloat = 36
        static let maximumInputHeight: CGFloat = 108
        static let lineHeight: CGFloat = 18
    }

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
