//
//  ResultPanelState.swift
//  PixelPane
//
//  Equatable panel state/model types, action-kind helpers, recovery action, and metadata badge.
//

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct AskConversationTurn: Equatable {
    let question: String
    var answer: String
    var backendLabel: String
    var runtimeProgressSummary: String?
    var statistics: [AIModelOutputStatistic] = []

    init(
        question: String,
        answer: String,
        backendLabel: String,
        runtimeProgressSummary: String? = nil,
        statistics: [AIModelOutputStatistic] = []
    ) {
        self.question = question
        self.answer = answer
        self.backendLabel = backendLabel
        self.runtimeProgressSummary = runtimeProgressSummary
        self.statistics = statistics
    }

    init(storedTurn: StoredChatTurn) {
        question = storedTurn.question
        answer = storedTurn.answer
        backendLabel = storedTurn.backendLabel
        runtimeProgressSummary = nil
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

struct PanelActionOutputState: Equatable {
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

struct ActionRecoveryState: Equatable {
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

extension AIActionKind {
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

extension PanelActionKind {
    var supportsCloudImageInput: Bool {
        switch self {
        case .explain, .debug, .ask:
            true
        case .extractText, .translate, .simplify:
            false
        }
    }
}

enum RecoveryAction: Equatable {
    case tryAgain
    case openSettings
    case openAppleIntelligenceSettings
    case refresh
}

extension AIBackendError {
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
