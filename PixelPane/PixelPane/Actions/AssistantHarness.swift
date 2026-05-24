import CoreGraphics
import Foundation

enum AssistantRoute: Sendable {
    case local
    case cloud
}

enum AssistantStructuredOutputReliability: Sendable {
    case native
    case prompted
    case weak
}

enum AssistantImageInputFormat: Sendable {
    case none
    case inMemoryImage
    case temporaryFile
    case remotePayload
}

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

struct AssistantModelCapabilities: Sendable {
    let route: AssistantRoute
    let supportsTextChat: Bool
    let supportsImageInput: Bool
    let supportsNativeToolCalling: Bool
    let structuredOutputReliability: AssistantStructuredOutputReliability
    let supportsStreaming: Bool
    let contextWindowTokens: Int?
    let maxPromptCharacters: Int
    let maxOutputTokens: Int
    let imageInputFormat: AssistantImageInputFormat

    static func local(from capabilities: AIBackendCapabilities) -> AssistantModelCapabilities {
        AssistantModelCapabilities(
            route: .local,
            supportsTextChat: capabilities.text.isAvailable,
            supportsImageInput: capabilities.image.isAvailable,
            supportsNativeToolCalling: false,
            structuredOutputReliability: .prompted,
            supportsStreaming: true,
            contextWindowTokens: capabilities.contextWindowTokens,
            maxPromptCharacters: capabilities.maxPromptCharacters,
            maxOutputTokens: capabilities.maxOutputTokens,
            imageInputFormat: capabilities.image.isAvailable ? .temporaryFile : .none
        )
    }

    static func cloud(from capabilities: AIBackendCapabilities) -> AssistantModelCapabilities {
        AssistantModelCapabilities(
            route: .cloud,
            supportsTextChat: capabilities.text.isAvailable,
            supportsImageInput: capabilities.image.isAvailable,
            supportsNativeToolCalling: false,
            structuredOutputReliability: .native,
            supportsStreaming: true,
            contextWindowTokens: capabilities.contextWindowTokens,
            maxPromptCharacters: capabilities.maxPromptCharacters,
            maxOutputTokens: capabilities.maxOutputTokens,
            imageInputFormat: capabilities.image.isAvailable ? .remotePayload : .none
        )
    }
}

struct AssistantToolEnvironment: Sendable {
    let hasCaptureContext: Bool
    let routingMode: AIRoutingMode
    let selectedLocalModelRepositoryID: String?
    let localTextBackendLabel: String
    let previousTurnReferencedModel: Bool
}

enum AssistantToolPreflightResult: Sendable {
    case directAnswer(answer: String, backendLabel: String)
    case localFileWriteMessage(message: String)
    case localFileWriteProposal(LocalFileWriteProposal)
}

enum AssistantLocalFileToolName: String, Sendable {
    case listGrants
    case searchGrantedFiles
    case readGrantedFile
    case explainUnavailableAccess
    case stageWriteProposal
}

struct AssistantLocalFileToolSource: Identifiable, Sendable {
    let id: String
    let path: String
    let displayName: String
    let kindLabel: String
    let snippetCount: Int
    let isTruncated: Bool
}

struct AssistantLocalFileToolResult: Sendable {
    let toolName: AssistantLocalFileToolName
    let summary: String
    let sources: [AssistantLocalFileToolSource]
    let context: LocalFileContext?
    let writeProposalResult: LocalFileWriteProposalResult?
}

struct AssistantLocalFileToolExecutor: Sendable {
    private let contextProvider: LocalFileContextProvider
    private let writeProposalParser: LocalFileWriteProposalParser
    private let maxReadCharacters: Int

    init(
        contextProvider: LocalFileContextProvider = LocalFileContextProvider(),
        writeProposalParser: LocalFileWriteProposalParser = LocalFileWriteProposalParser(),
        maxReadCharacters: Int = 8_000
    ) {
        self.contextProvider = contextProvider
        self.writeProposalParser = writeProposalParser
        self.maxReadCharacters = maxReadCharacters
    }

    nonisolated func listGrants(_ grants: [LocalFileGrant]) -> AssistantLocalFileToolResult {
        let sources = grants.map { grant in
            AssistantLocalFileToolSource(
                id: grant.id.uuidString,
                path: grant.path,
                displayName: grant.displayName,
                kindLabel: grant.kindLabel,
                snippetCount: 0,
                isTruncated: false
            )
        }
        let summary = grants.isEmpty
            ? "No local files or folders have been granted."
            : grants.map { "- \($0.kindLabel): \($0.path)" }.joined(separator: "\n")
        return AssistantLocalFileToolResult(
            toolName: .listGrants,
            summary: summary,
            sources: sources,
            context: LocalFileContext(grants: grants, snippets: []),
            writeProposalResult: nil
        )
    }

    nonisolated func directAnswer(for question: String, grants: [LocalFileGrant]) -> String? {
        contextProvider.directAnswer(for: question, grants: grants)
    }

    nonisolated func folderOverviewAnswer(for question: String, grants: [LocalFileGrant]) -> String? {
        let normalized = Self.normalized(question)
        let asksForFolderContents = [
            "what do you see in this folder",
            "what can you see in this folder",
            "what is in this folder",
            "what's in this folder",
            "what is inside this folder",
            "what's inside this folder",
            "show this folder",
            "list this folder",
            "folder contents",
            "directory contents"
        ].contains { normalized.contains($0) }
        guard asksForFolderContents else { return nil }

        let activeFolders = grants
            .filter { $0.isDirectory && FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        guard !activeFolders.isEmpty else {
            return "I can inspect folder contents only after you grant a folder in Settings -> Files."
        }

        if activeFolders.count > 1 {
            let lines = activeFolders.map { "- \($0.path)" }
            return "I have access to multiple folders. Which one should I inspect?\n\n\(lines.joined(separator: "\n"))"
        }

        return overview(for: activeFolders[0])
    }

    nonisolated func search(question: String, grants: [LocalFileGrant]) -> AssistantLocalFileToolResult {
        let context = contextProvider.context(for: question, grants: grants)
        let groupedSnippets = Dictionary(grouping: context.snippets, by: \.path)
        let sources = groupedSnippets.map { path, snippets in
            AssistantLocalFileToolSource(
                id: path,
                path: path,
                displayName: URL(fileURLWithPath: path).lastPathComponent,
                kindLabel: "File",
                snippetCount: snippets.count,
                isTruncated: snippets.contains { $0.preview.count >= 1_800 }
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        let summary = context.hasSnippets
            ? "Found \(context.snippets.count) relevant local file snippet\(context.snippets.count == 1 ? "" : "s")."
            : "No relevant local file snippets were found."
        return AssistantLocalFileToolResult(
            toolName: .searchGrantedFiles,
            summary: summary,
            sources: sources,
            context: context,
            writeProposalResult: nil
        )
    }

    nonisolated func read(path: String, grants: [LocalFileGrant]) -> AssistantLocalFileToolResult {
        guard let allowedURL = allowedURL(for: path, grants: grants) else {
            return unavailableAccessResult(path: path)
        }

        do {
            let text = try String(contentsOf: allowedURL, encoding: .utf8)
            let truncated = text.count > maxReadCharacters
            let preview = truncated ? String(text.prefix(maxReadCharacters)) : text
            let snippet = LocalFileSnippet(
                id: allowedURL.path,
                path: allowedURL.path,
                preview: preview,
                score: 1_000
            )
            return AssistantLocalFileToolResult(
                toolName: .readGrantedFile,
                summary: truncated ? "Read granted file with truncation." : "Read granted file.",
                sources: [
                    AssistantLocalFileToolSource(
                        id: allowedURL.path,
                        path: allowedURL.path,
                        displayName: allowedURL.lastPathComponent,
                        kindLabel: "File",
                        snippetCount: 1,
                        isTruncated: truncated
                    )
                ],
                context: LocalFileContext(grants: grants, snippets: [snippet]),
                writeProposalResult: nil
            )
        } catch {
            return AssistantLocalFileToolResult(
                toolName: .readGrantedFile,
                summary: "Could not read granted file: \(error.localizedDescription)",
                sources: [],
                context: LocalFileContext(grants: grants, snippets: []),
                writeProposalResult: nil
            )
        }
    }

    nonisolated func stageWriteProposal(question: String, grants: [LocalFileGrant]) -> AssistantLocalFileToolResult {
        let result = writeProposalParser.proposal(for: question, grants: grants)
        return AssistantLocalFileToolResult(
            toolName: .stageWriteProposal,
            summary: "Checked whether the user requested a confirmed local file write.",
            sources: [],
            context: nil,
            writeProposalResult: result
        )
    }

    nonisolated func unavailableAccessResult(path: String? = nil) -> AssistantLocalFileToolResult {
        let target = path.map { " for \($0)" } ?? ""
        return AssistantLocalFileToolResult(
            toolName: .explainUnavailableAccess,
            summary: "No granted local file access\(target).",
            sources: [],
            context: LocalFileContext(grants: [], snippets: []),
            writeProposalResult: nil
        )
    }

    private nonisolated func allowedURL(for path: String, grants: [LocalFileGrant]) -> URL? {
        let candidate = URL(fileURLWithPath: path).standardizedFileURL
        for grant in grants {
            let grantURL = grant.url.standardizedFileURL
            if grant.isDirectory {
                let grantPath = grantURL.path.hasSuffix("/") ? grantURL.path : grantURL.path + "/"
                let candidatePath = candidate.path.hasSuffix("/") ? candidate.path : candidate.path + "/"
                if candidatePath.hasPrefix(grantPath) {
                    return candidate
                }
            } else if candidate.path == grantURL.path {
                return candidate
            }
        }
        return nil
    }

    private nonisolated func overview(for grant: LocalFileGrant) -> String {
        let url = grant.url.standardizedFileURL
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            )
            let visibleContents = contents.filter { itemURL in
                let values = try? itemURL.resourceValues(forKeys: [.isHiddenKey])
                return values?.isHidden != true
            }
            let folders = visibleContents.filter { itemURL in
                let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
                return values?.isDirectory == true
            }
            let files = visibleContents.filter { itemURL in
                let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
                return values?.isDirectory != true
            }
            let sortedFolders = folders.sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }
            let sortedFiles = files.sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }
            var lines = [
                "I can see this granted folder:",
                grant.path,
                "",
                "Top-level contents:"
            ]
            let maxItems = 40
            let displayedFolders = sortedFolders.prefix(maxItems)
            let remainingSlots = max(0, maxItems - displayedFolders.count)
            let displayedFiles = sortedFiles.prefix(remainingSlots)
            lines.append(contentsOf: displayedFolders.map { "- Folder: \($0.lastPathComponent)" })
            lines.append(contentsOf: displayedFiles.map { "- File: \($0.lastPathComponent)" })
            let hiddenCount = visibleContents.count - displayedFolders.count - displayedFiles.count
            if hiddenCount > 0 {
                lines.append("- ... \(hiddenCount) more item\(hiddenCount == 1 ? "" : "s")")
            }
            if visibleContents.isEmpty {
                lines.append("- No visible top-level files or folders.")
            }
            return lines.joined(separator: "\n")
        } catch {
            return "I have a grant for \(grant.path), but I could not list it: \(error.localizedDescription)"
        }
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9/._ -]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AssistantFileSearchDecision: Sendable {
    let shouldSearch: Bool
}

struct AssistantToolRouter: Sendable {
    private let fileToolExecutor: AssistantLocalFileToolExecutor

    init(
        fileToolExecutor: AssistantLocalFileToolExecutor = AssistantLocalFileToolExecutor()
    ) {
        self.fileToolExecutor = fileToolExecutor
    }

    nonisolated func preflight(
        question: String,
        grants: [LocalFileGrant],
        environment: AssistantToolEnvironment
    ) -> AssistantToolPreflightResult? {
        switch fileToolExecutor.stageWriteProposal(question: question, grants: grants).writeProposalResult {
        case .none?:
            break
        case .message(let message)?:
            return .localFileWriteMessage(message: message)
        case .proposal(let proposal)?:
            return .localFileWriteProposal(proposal)
        case nil:
            break
        }

        if let identityAnswer = assistantIdentityAnswer(for: question) {
            return .directAnswer(answer: identityAnswer, backendLabel: "Pixel Pane")
        }

        if let folderOverviewAnswer = fileToolExecutor.folderOverviewAnswer(for: question, grants: grants) {
            return .directAnswer(answer: folderOverviewAnswer, backendLabel: "Local Files")
        }

        if let modelAnswer = selectedModelAnswer(for: question, environment: environment) {
            return .directAnswer(answer: modelAnswer, backendLabel: "Pixel Pane")
        }

        if let routingAnswer = routingAnswer(for: question, routingMode: environment.routingMode) {
            return .directAnswer(answer: routingAnswer, backendLabel: "Pixel Pane")
        }

        if let fileAnswer = fileToolExecutor.directAnswer(for: question, grants: grants) {
            return .directAnswer(answer: fileAnswer, backendLabel: "Local Files")
        }

        if !fileSearchDecision(question: question, grants: grants).shouldSearch,
           let screenAnswer = unavailableScreenContextAnswer(
            for: question,
            hasCaptureContext: environment.hasCaptureContext
           ) {
            return .directAnswer(answer: screenAnswer, backendLabel: "Pixel Pane")
        }

        return nil
    }

    nonisolated func localFileContext(question: String, grants: [LocalFileGrant]) -> LocalFileContext {
        fileToolExecutor.search(question: question, grants: grants).context ?? LocalFileContext(grants: grants, snippets: [])
    }

    nonisolated func fileSearchDecision(question: String, grants: [LocalFileGrant]) -> AssistantFileSearchDecision {
        guard !grants.isEmpty else {
            return AssistantFileSearchDecision(shouldSearch: false)
        }

        let normalized = Self.normalizedQuestion(question)
        let fileSignals = [
            "file", "files", "folder", "folders", "project", "repo", "repository",
            "code", "source", "readme", "document", "docs", "path", "search",
            "find", "where is", "show me", "what do you see", "what can you see",
            "what is in", "what's in", "inside", "open", "swift", "python", "json",
            "markdown", "md", "this project", "this repo"
        ]
        if fileSignals.contains(where: { normalized.contains($0) }) {
            return AssistantFileSearchDecision(shouldSearch: true)
        }

        let mentionsGrant = grants.contains { grant in
            let name = URL(fileURLWithPath: grant.path).lastPathComponent.lowercased()
            return !name.isEmpty && normalized.contains(name)
        }
        return AssistantFileSearchDecision(shouldSearch: mentionsGrant)
    }

    private nonisolated func assistantIdentityAnswer(for question: String) -> String? {
        let normalized = Self.normalizedQuestion(question)
        let asksForAssistantName = [
            "what is your name",
            "whats your name",
            "who are you",
            "what are you called",
            "your name"
        ].contains { normalized.contains($0) }
        guard asksForAssistantName else { return nil }
        return "I am Pixel Pane."
    }

    private nonisolated func unavailableScreenContextAnswer(for question: String, hasCaptureContext: Bool) -> String? {
        guard !hasCaptureContext else { return nil }
        let normalized = Self.normalizedQuestion(question)
        let asksAboutCurrentScreen = [
            "what is on my screen",
            "what's on my screen",
            "what is onscreen",
            "what's onscreen",
            "what am i looking at",
            "what do you see",
            "what can you see",
            "read my screen",
            "look at my screen"
        ].contains { normalized.contains($0) }
        guard asksAboutCurrentScreen else { return nil }
        return "I do not have a screen region attached to this chat yet."
    }

    private nonisolated func selectedModelAnswer(
        for question: String,
        environment: AssistantToolEnvironment
    ) -> String? {
        let normalized = Self.normalizedQuestion(question)
        let asksForModel = [
            "what model",
            "what is this model",
            "which model",
            "what are you running",
            "what llm",
            "which llm",
            "model name"
        ].contains { normalized.contains($0) }
        guard asksForModel || (normalized == "which one" && environment.previousTurnReferencedModel) else { return nil }

        if case .cloud = environment.routingMode {
            return "Pixel Pane is using Cloud Mode."
        }

        if let selectedLocalModelRepositoryID = environment.selectedLocalModelRepositoryID {
            return "Pixel Pane is using \(selectedLocalModelRepositoryID)."
        }

        return environment.localTextBackendLabel == "Local Apple Model"
            ? "Pixel Pane is using Apple Foundation Models."
            : "No local MLX model is selected."
    }

    private nonisolated func routingAnswer(for question: String, routingMode: AIRoutingMode) -> String? {
        let normalized = Self.normalizedQuestion(question)
        let asksForRouting = [
            "local or cloud",
            "using cloud",
            "using local",
            "cloud mode",
            "local mode",
            "where is this running"
        ].contains { normalized.contains($0) }
        guard asksForRouting else { return nil }

        switch routingMode {
        case .local:
            return "Pixel Pane is in Local Mode."
        case .cloud:
            return "Pixel Pane is in Cloud Mode."
        }
    }

    private nonisolated static func normalizedQuestion(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
}
