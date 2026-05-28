import CoreGraphics
import Foundation

enum AssistantImageContextSource: Sendable {
    case capture
    case userAttachment
    case clipboard
}

struct AssistantImageContext: Identifiable, Sendable {
    let id: UUID
    let source: AssistantImageContextSource
    let label: String
    let image: CGImage
    var ocrText: String?
    var isOCRComplete: Bool

    init(
        id: UUID = UUID(),
        source: AssistantImageContextSource,
        label: String,
        image: CGImage,
        ocrText: String? = nil,
        isOCRComplete: Bool = false
    ) {
        self.id = id
        self.source = source
        self.label = label
        self.image = image
        self.ocrText = ocrText
        self.isOCRComplete = isOCRComplete
    }
}

enum AssistantToolName: String, Codable, CaseIterable, Sendable {
    case listGrants = "list_grants"
    case listFolder = "list_folder"
    case legacyProfileFolder = "profile_folder"
    case searchFiles = "search_files"
    case readFile = "read_file"
    case stageWriteProposal = "stage_write_proposal"
    case describeScreenOrImageContext = "describe_screen_or_image_context"
    case runTerminalCommand = "run_terminal_command"
}

enum AssistantToolRiskLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}

enum AssistantTerminalCommandIntent: String, Codable, Equatable, Sendable {
    case generic
    case fileSearch
    case systemInspection
}

struct AssistantTerminalCommandProposal: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let command: String
    let workingDirectory: String
    let reason: String
    let riskLevel: AssistantToolRiskLevel
    let requiresConfirmation: Bool
    let timeoutSeconds: TimeInterval
    let intent: AssistantTerminalCommandIntent

    nonisolated init(
        id: UUID = UUID(),
        command: String,
        workingDirectory: String,
        reason: String,
        riskLevel: AssistantToolRiskLevel,
        requiresConfirmation: Bool,
        timeoutSeconds: TimeInterval,
        intent: AssistantTerminalCommandIntent = .generic
    ) {
        self.id = id
        self.command = command
        self.workingDirectory = workingDirectory
        self.reason = reason
        self.riskLevel = riskLevel
        self.requiresConfirmation = requiresConfirmation
        self.timeoutSeconds = timeoutSeconds
        self.intent = intent
    }

    nonisolated var actionLabel: String {
        requiresConfirmation ? "Confirm terminal command" : "Run terminal command"
    }

    nonisolated var detailText: String {
        "Run from \(workingDirectory) with a \(Int(timeoutSeconds)) second timeout."
    }
}

struct AssistantToolSourceState: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let path: String
    let displayName: String
    let kindLabel: String
    let snippetCount: Int
    let isTruncated: Bool
}

struct AssistantToolSnippetState: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let path: String
    let preview: String
    let score: Int
}

struct AssistantVisualContextState: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case capture
        case userAttachment
        case clipboard
    }

    let source: Source
    let label: String
    let hasImageInput: Bool
    let hasOCRText: Bool
    let ocrExcerpt: String?
    let updatedAt: Date

    init(
        source: Source,
        label: String,
        hasImageInput: Bool,
        ocrText: String?,
        updatedAt: Date = Date()
    ) {
        self.source = source
        self.label = label
        self.hasImageInput = hasImageInput
        let trimmedOCR = ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        hasOCRText = !trimmedOCR.isEmpty
        ocrExcerpt = trimmedOCR.isEmpty ? nil : Self.truncate(trimmedOCR, limit: 1_600)
        self.updatedAt = updatedAt
    }

    init?(imageContext: AssistantImageContext?, imageWillBeSent: Bool) {
        guard let imageContext else { return nil }
        let source: Source
        switch imageContext.source {
        case .capture:
            source = .capture
        case .userAttachment:
            source = .userAttachment
        case .clipboard:
            source = .clipboard
        }
        self.init(
            source: source,
            label: imageContext.label,
            hasImageInput: imageWillBeSent,
            ocrText: imageContext.ocrText
        )
    }

    private static func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let end = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

struct AssistantRecentToolResultState: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let toolName: AssistantToolName
    let summary: String
    let sources: [AssistantToolSourceState]?
    let snippets: [AssistantToolSnippetState]?
    let writeProposalSummary: String?
    let terminalCommand: String?
    let terminalWorkingDirectory: String?
    let terminalExitCode: Int32?
    let terminalStdout: String?
    let terminalStderr: String?
    let terminalDurationSeconds: TimeInterval?
    let terminalDidTimeOut: Bool?
    let terminalWasOutputTruncated: Bool?
    let sourceCount: Int
    let itemCount: Int
    let isTruncated: Bool
    let createdAt: Date
}

struct AssistantPendingToolContinuationState: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case selectFolderToList
    }

    let kind: Kind
    let sources: [AssistantToolSourceState]
    let createdAt: Date
}

struct AssistantToolState: Codable, Equatable, Sendable {
    var grantedSourcesUsed: [AssistantToolSourceState]
    var lastListedFolder: AssistantToolSourceState?
    var lastFileSources: [AssistantToolSourceState]
    var lastFileSnippets: [AssistantToolSnippetState]
    var activeVisualContext: AssistantVisualContextState?
    var recentToolResults: [AssistantRecentToolResultState]
    var pendingContinuation: AssistantPendingToolContinuationState?

    init(
        grantedSourcesUsed: [AssistantToolSourceState] = [],
        lastListedFolder: AssistantToolSourceState? = nil,
        lastFileSources: [AssistantToolSourceState] = [],
        lastFileSnippets: [AssistantToolSnippetState] = [],
        activeVisualContext: AssistantVisualContextState? = nil,
        recentToolResults: [AssistantRecentToolResultState] = [],
        pendingContinuation: AssistantPendingToolContinuationState? = nil
    ) {
        self.grantedSourcesUsed = grantedSourcesUsed
        self.lastListedFolder = lastListedFolder
        self.lastFileSources = lastFileSources
        self.lastFileSnippets = lastFileSnippets
        self.activeVisualContext = activeVisualContext
        self.recentToolResults = recentToolResults
        self.pendingContinuation = pendingContinuation
    }

    mutating func updateVisualContext(_ context: AssistantVisualContextState?) {
        activeVisualContext = context
    }
}
