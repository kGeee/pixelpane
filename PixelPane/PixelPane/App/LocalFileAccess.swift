import AppKit
import Combine
import Foundation

struct LocalFileGrant: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let path: String
    let isDirectory: Bool
    let addedAt: Date

    nonisolated var url: URL {
        URL(fileURLWithPath: path)
    }

    nonisolated var displayName: String {
        url.lastPathComponent.isEmpty ? path : url.lastPathComponent
    }

    nonisolated var kindLabel: String {
        isDirectory ? "Folder" : "File"
    }
}

@MainActor
final class LocalFileAccessStore: ObservableObject {
    @Published private(set) var grants: [LocalFileGrant]

    private let userDefaults: UserDefaults
    private let key = "LocalFileAccess.Grants"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([LocalFileGrant].self, from: data) {
            grants = decoded
        } else {
            grants = []
        }
    }

    func grantFolder() {
        let panel = NSOpenPanel()
        panel.title = "Grant Folder Access"
        panel.prompt = "Grant Access"
        panel.message = "Pixel Pane will be able to read and search this folder locally."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        addGrant(url: url, isDirectory: true)
    }

    func grantFile() {
        let panel = NSOpenPanel()
        panel.title = "Grant File Access"
        panel.prompt = "Grant Access"
        panel.message = "Pixel Pane will be able to read this file locally."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        addGrant(url: url, isDirectory: false)
    }

    func removeGrant(_ grant: LocalFileGrant) {
        grants.removeAll { $0.id == grant.id }
        persist()
    }

    func clearGrants() {
        grants = []
        userDefaults.removeObject(forKey: key)
    }

    func clearMissingGrants() {
        grants.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        persist()
    }

    private func addGrant(url: URL, isDirectory: Bool) {
        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.path
        grants.removeAll { $0.path == path }
        grants.append(
            LocalFileGrant(
                id: UUID(),
                path: path,
                isDirectory: isDirectory,
                addedAt: Date()
            )
        )
        grants.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(grants) {
            userDefaults.set(data, forKey: key)
        }
    }
}

struct LocalFileContext: Sendable {
    let grants: [LocalFileGrant]
    let snippets: [LocalFileSnippet]

    nonisolated var hasGrantedFiles: Bool {
        !grants.isEmpty
    }

    nonisolated var hasSnippets: Bool {
        !snippets.isEmpty
    }

    nonisolated var promptText: String {
        guard hasGrantedFiles else {
            return "No local files or folders have been granted."
        }

        var lines = [
            "Granted read-only local locations:",
            grants.map { "- \($0.kindLabel): \($0.path)" }.joined(separator: "\n")
        ]

        if snippets.isEmpty {
            lines.append("No relevant local file snippets were found for this question.")
        } else {
            lines.append("Relevant read-only local file snippets:")
            for (index, snippet) in snippets.enumerated() {
                lines.append(
                    """
                    [\(index + 1)] \(snippet.path)
                    \(snippet.preview)
                    """
                )
            }
        }

        return lines.joined(separator: "\n\n")
    }
}

struct LocalFileSnippet: Identifiable, Sendable {
    let id: String
    let path: String
    let preview: String
    let score: Int
}

struct LocalFileWriteProposal: Equatable, Identifiable, Sendable {
    enum Operation: Equatable, Sendable {
        case create(content: String)
        case replaceContents(content: String)
        case append(content: String)
        case replaceText(oldText: String, newText: String)
    }

    let id: UUID
    let targetPath: String
    let operation: Operation

    var actionLabel: String {
        switch operation {
        case .create:
            "Create file"
        case .replaceContents:
            "Replace file"
        case .append:
            "Append to file"
        case .replaceText:
            "Edit file"
        }
    }

    var detailText: String {
        switch operation {
        case .create(let content):
            "Create \(targetPath) with \(content.count) characters."
        case .replaceContents(let content):
            "Replace all text in \(targetPath) with \(content.count) characters."
        case .append(let content):
            "Append \(content.count) characters to \(targetPath)."
        case .replaceText(let oldText, let newText):
            "Replace \(oldText.count) characters with \(newText.count) characters in \(targetPath)."
        }
    }
}

enum LocalFileWriteProposalResult: Sendable {
    case none
    case proposal(LocalFileWriteProposal)
    case message(String)
}

struct LocalFileWriteProposalParser: Sendable {
    private let maxContentCharacters = 100_000

    nonisolated init() {}

    nonisolated func proposal(for question: String, grants: [LocalFileGrant]) -> LocalFileWriteProposalResult {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        guard isWriteIntent(normalized) else { return .none }

        let activeGrants = grants.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !activeGrants.isEmpty else {
            return .message("Grant a file or folder in Settings -> Files before I can propose local file changes.")
        }

        if normalized.hasPrefix("replace in ") || normalized.hasPrefix("replace text in ") {
            return replaceTextProposal(from: trimmed, grants: activeGrants)
        }

        if normalized.hasPrefix("append to ") {
            return contentProposal(from: trimmed, prefix: "append to", operation: .append, grants: activeGrants)
        }

        if normalized.hasPrefix("create file ")
            || normalized.hasPrefix("create ")
            || normalized.hasPrefix("write file ")
            || normalized.hasPrefix("write ") {
            let prefix: String
            if normalized.hasPrefix("create file ") {
                prefix = "create file"
            } else if normalized.hasPrefix("create ") {
                prefix = "create"
            } else if normalized.hasPrefix("write file ") {
                prefix = "write file"
            } else {
                prefix = "write"
            }
            return contentProposal(from: trimmed, prefix: prefix, operation: .createOrReplace, grants: activeGrants)
        }

        return .message("I can propose file changes with commands like `create file notes.md with content: ...`, `append to notes.md: ...`, or `replace in notes.md \"old\" with \"new\"`.")
    }

    private nonisolated enum ParsedContentOperation {
        case createOrReplace
        case append
    }

    private nonisolated func isWriteIntent(_ normalized: String) -> Bool {
        normalized.hasPrefix("create file ")
            || normalized.hasPrefix("create ")
            || normalized.hasPrefix("write file ")
            || normalized.hasPrefix("write ")
            || normalized.hasPrefix("append to ")
            || normalized.hasPrefix("replace in ")
            || normalized.hasPrefix("replace text in ")
    }

    private nonisolated func contentProposal(
        from command: String,
        prefix: String,
        operation: ParsedContentOperation,
        grants: [LocalFileGrant]
    ) -> LocalFileWriteProposalResult {
        let body = String(command.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = parsePathAndContent(from: body) else {
            return .message("Name the target path and content before I can propose a local file change.")
        }

        let content = parsed.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return .message("The proposed file content is empty.")
        }
        guard content.count <= maxContentCharacters else {
            return .message("That proposed file change is too large. Keep confirmed local writes under \(maxContentCharacters) characters.")
        }

        guard let targetURL = resolvedURL(for: parsed.path, grants: grants) else {
            return .message("The target path must be inside a granted folder or match a granted file.")
        }

        let fileExists = FileManager.default.fileExists(atPath: targetURL.path)
        let writeOperation: LocalFileWriteProposal.Operation
        switch operation {
        case .append:
            guard fileExists else {
                return .message("I can append only to an existing granted text file. Use create file for a new file.")
            }
            writeOperation = .append(content: content)
        case .createOrReplace:
            writeOperation = fileExists ? .replaceContents(content: content) : .create(content: content)
        }

        return .proposal(
            LocalFileWriteProposal(
                id: UUID(),
                targetPath: targetURL.path,
                operation: writeOperation
            )
        )
    }

    private nonisolated func replaceTextProposal(
        from command: String,
        grants: [LocalFileGrant]
    ) -> LocalFileWriteProposalResult {
        let prefixes = ["replace text in ", "replace in "]
        guard let prefix = prefixes.first(where: { command.lowercased().hasPrefix($0) }) else {
            return .none
        }
        let body = String(command.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedPath = parsePathPrefix(from: body) else {
            return .message("Name the file path before the replacement text.")
        }
        let remainder = parsedPath.remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let replacement = parseReplacement(from: remainder) else {
            return .message("Use `replace in path \"old text\" with \"new text\"` so I can propose a precise edit.")
        }
        guard !replacement.oldText.isEmpty else {
            return .message("The text to replace is empty.")
        }
        guard replacement.newText.count <= maxContentCharacters else {
            return .message("That replacement is too large. Keep confirmed local writes under \(maxContentCharacters) characters.")
        }
        guard let targetURL = resolvedURL(for: parsedPath.path, grants: grants),
              FileManager.default.fileExists(atPath: targetURL.path) else {
            return .message("The target file must already exist inside a granted folder or match a granted file.")
        }

        return .proposal(
            LocalFileWriteProposal(
                id: UUID(),
                targetPath: targetURL.path,
                operation: .replaceText(oldText: replacement.oldText, newText: replacement.newText)
            )
        )
    }

    private nonisolated func parsePathAndContent(from body: String) -> (path: String, content: String)? {
        if let quoted = parsePathPrefix(from: body), quoted.remainder.lowercased().hasPrefix("with content") {
            return (quoted.path, contentAfterMarker(in: quoted.remainder) ?? "")
        }

        let markers = [" with content:", " with content ", " content:", ":"]
        for marker in markers {
            if let range = body.range(of: marker, options: [.caseInsensitive]) {
                let path = String(body[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let content = String(body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else { return nil }
                return (path, content)
            }
        }
        return nil
    }

    private nonisolated func contentAfterMarker(in text: String) -> String? {
        let markers = ["with content:", "with content"]
        for marker in markers {
            if let range = text.range(of: marker, options: [.caseInsensitive]) {
                return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private nonisolated func parsePathPrefix(from body: String) -> (path: String, remainder: String)? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.first == "\"" {
            let rest = trimmed.dropFirst()
            guard let closing = rest.firstIndex(of: "\"") else { return nil }
            let path = String(rest[..<closing])
            let remainder = String(rest[rest.index(after: closing)...])
            return (path, remainder)
        }

        let markers = [" with content:", " with content ", " content:", " \"", ":"]
        let lower = trimmed.lowercased()
        let markerRange = markers
            .compactMap { marker -> Range<String.Index>? in lower.range(of: marker) }
            .min { $0.lowerBound < $1.lowerBound }
        guard let markerRange else { return nil }
        let path = String(trimmed[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = String(trimmed[markerRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : (path, remainder)
    }

    private nonisolated func parseReplacement(from text: String) -> (oldText: String, newText: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "\"" else { return nil }
        let rest = trimmed.dropFirst()
        guard let oldEnd = rest.firstIndex(of: "\"") else { return nil }
        let oldText = String(rest[..<oldEnd])
        let afterOld = String(rest[rest.index(after: oldEnd)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard afterOld.lowercased().hasPrefix("with ") else { return nil }
        let newPart = String(afterOld.dropFirst("with ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard newPart.first == "\"" else { return nil }
        let newRest = newPart.dropFirst()
        guard let newEnd = newRest.firstIndex(of: "\"") else { return nil }
        return (oldText, String(newRest[..<newEnd]))
    }

    private nonisolated func resolvedURL(for path: String, grants: [LocalFileGrant]) -> URL? {
        let rawURL = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : grants.first(where: { $0.isDirectory })?.url.appendingPathComponent(path)
        guard let candidate = rawURL?.standardizedFileURL else { return nil }

        let candidatePath = candidate.path
        for grant in grants {
            let grantURL = grant.url.standardizedFileURL
            if grant.isDirectory {
                let root = grantURL.path.hasSuffix("/") ? grantURL.path : grantURL.path + "/"
                if candidatePath.hasPrefix(root) {
                    return candidate
                }
            } else if candidatePath == grantURL.path {
                return candidate
            }
        }
        return nil
    }
}

enum LocalFileWriteExecutor: Sendable {
    nonisolated static func execute(_ proposal: LocalFileWriteProposal) throws {
        let targetURL = URL(fileURLWithPath: proposal.targetPath).standardizedFileURL
        switch proposal.operation {
        case .create(let content):
            guard !FileManager.default.fileExists(atPath: targetURL.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            guard FileManager.default.fileExists(atPath: targetURL.deletingLastPathComponent().path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
        case .replaceContents(let content):
            guard FileManager.default.fileExists(atPath: targetURL.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
        case .append(let content):
            guard FileManager.default.fileExists(atPath: targetURL.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let handle = try FileHandle(forWritingTo: targetURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = content.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        case .replaceText(let oldText, let newText):
            let original = try String(contentsOf: targetURL, encoding: .utf8)
            guard original.contains(oldText) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let updated = original.replacingOccurrences(of: oldText, with: newText)
            try updated.write(to: targetURL, atomically: true, encoding: .utf8)
        }
    }
}

struct LocalFileContextProvider: Sendable {
    private let maxCandidateFiles = 700
    private let maxFilesToRead = 120
    private let maxFileBytes = 700_000
    private let maxSnippets = 5
    private let snippetRadius = 520

    nonisolated init() {}

    nonisolated func context(for question: String, grants: [LocalFileGrant]) -> LocalFileContext {
        let activeGrants = grants.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !activeGrants.isEmpty else {
            return LocalFileContext(grants: [], snippets: [])
        }

        let terms = searchTerms(from: question)
        guard !terms.isEmpty else {
            return LocalFileContext(grants: activeGrants, snippets: [])
        }

        var snippets: [LocalFileSnippet] = []
        var visitedFiles = 0
        var filesRead = 0
        var contentCandidates: [URL] = []

        for grant in activeGrants {
            guard visitedFiles < maxCandidateFiles else { break }
            for fileURL in fileURLs(in: grant) {
                guard visitedFiles < maxCandidateFiles, !Task.isCancelled else { break }
                visitedFiles += 1

                let searchablePath = [
                    fileURL.deletingLastPathComponent().lastPathComponent,
                    fileURL.lastPathComponent
                ].joined(separator: " ")
                let pathScore = score(text: searchablePath, terms: terms) * 3
                guard pathScore > 0 else {
                    if contentCandidates.count < maxFilesToRead {
                        contentCandidates.append(fileURL)
                    }
                    continue
                }
                guard filesRead < maxFilesToRead else { continue }
                guard let content = readTextFile(fileURL) else { continue }
                filesRead += 1
                let contentScore = score(text: content, terms: terms)
                let totalScore = pathScore + contentScore

                snippets.append(
                    LocalFileSnippet(
                        id: fileURL.path,
                        path: fileURL.path,
                        preview: snippet(from: content, terms: terms),
                        score: totalScore
                    )
                )
            }
        }

        for fileURL in contentCandidates {
            guard filesRead < maxFilesToRead, !Task.isCancelled else { break }
            guard let content = readTextFile(fileURL) else { continue }
            filesRead += 1
            let contentScore = score(text: content, terms: terms)
            guard contentScore > 0 else { continue }

            snippets.append(
                LocalFileSnippet(
                    id: fileURL.path,
                    path: fileURL.path,
                    preview: snippet(from: content, terms: terms),
                    score: contentScore
                )
            )
        }

        return LocalFileContext(
            grants: activeGrants,
            snippets: snippets
                .sorted { lhs, rhs in
                    if lhs.score == rhs.score {
                        return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
                    }
                    return lhs.score > rhs.score
                }
                .prefix(maxSnippets)
                .map { $0 }
        )
    }

    nonisolated func directAnswer(for question: String, grants: [LocalFileGrant]) -> String? {
        let normalized = Self.normalized(question)
        let fileSignals = [
            "file", "files", "folder", "folders", "directory", "directories",
            "local file", "local files", "source", "sources", "repo", "repository",
            "project", "workspace"
        ]
        let accessSignals = [
            "access", "see", "view", "read", "search", "look at", "look in",
            "have", "know about", "use"
        ]
        let capabilitySignals = [
            "can you", "are you able", "do you have access", "do you see",
            "can pixel pane", "can the app"
        ]
        let inventorySignals = [
            "what", "which", "list", "show", "where", "any", "granted",
            "connected", "available"
        ]
        let asksForGrants =
            normalized.contains("granted files")
            || normalized.contains("granted folders")
            || normalized.contains("file sources")
            || normalized.contains("local sources")
            || (
                fileSignals.contains { normalized.contains($0) }
                && accessSignals.contains { normalized.contains($0) }
                && (
                    inventorySignals.contains { normalized.contains($0) }
                    || capabilitySignals.contains { normalized.contains($0) }
                )
            )

        guard asksForGrants else { return nil }

        let activeGrants = grants.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !activeGrants.isEmpty else {
            return "I can read and search only files or folders you grant. Right now, no local file sources are granted."
        }

        let lines = activeGrants.map { "- \($0.kindLabel): \($0.path)" }
        return "I can read and search only these user-granted locations:\n\n\(lines.joined(separator: "\n"))"
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9/._ -]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func fileURLs(in grant: LocalFileGrant) -> [URL] {
        if !grant.isDirectory {
            return isTextLikeFile(grant.url) ? [grant.url] : []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: grant.url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard urls.count < maxCandidateFiles else { break }
            if shouldSkip(url) {
                enumerator.skipDescendants()
                continue
            }
            guard isTextLikeFile(url), fileSize(url) <= maxFileBytes else { continue }
            urls.append(url)
        }
        return urls
    }

    private nonisolated func isTextLikeFile(_ url: URL) -> Bool {
        let allowedExtensions: Set<String> = [
            "txt", "md", "markdown", "rst", "json", "yaml", "yml", "toml", "xml",
            "csv", "tsv", "log", "swift", "py", "js", "ts", "tsx", "jsx", "html",
            "css", "scss", "c", "h", "m", "mm", "cpp", "hpp", "java", "kt", "go",
            "rs", "rb", "php", "sh", "zsh", "bash", "sql", "ini", "conf", "env"
        ]
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty || allowedExtensions.contains(ext)
    }

    private nonisolated func shouldSkip(_ url: URL) -> Bool {
        let skipped = Set([".git", "node_modules", "DerivedData", ".build", "build", "dist", ".next"])
        return url.pathComponents.contains { skipped.contains($0) }
    }

    private nonisolated func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private nonisolated func readTextFile(_ url: URL) -> String? {
        guard fileSize(url) <= maxFileBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              !data.contains(0) else {
            return nil
        }

        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? String(decoding: data, as: UTF8.self)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated func searchTerms(from question: String) -> [String] {
        let stopwords: Set<String> = [
            "about", "after", "again", "also", "could", "file", "files", "find",
            "from", "have", "into", "local", "read", "search", "show", "tell",
            "that", "the", "their", "there", "this", "what", "when", "where",
            "which", "with", "would", "you", "your"
        ]

        let normalized = question
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Array(
            Set(
                normalized
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count >= 3 && !stopwords.contains($0) }
            )
        )
        .sorted()
    }

    private nonisolated func score(text: String, terms: [String]) -> Int {
        let lowercased = text.lowercased()
        return terms.reduce(0) { partial, term in
            partial + (lowercased.contains(term) ? 1 : 0)
        }
    }

    private nonisolated func snippet(from text: String, terms: [String]) -> String {
        let lowercased = text.lowercased() as NSString
        let content = text as NSString
        let locations = terms
            .map { lowercased.range(of: $0).location }
            .filter { $0 != NSNotFound }
        let matchLocation = locations.min() ?? 0
        let start = max(0, matchLocation - snippetRadius)
        let end = min(content.length, matchLocation + snippetRadius)
        let range = NSRange(location: start, length: max(0, end - start))
        var value = content.substring(with: range)
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
        while value.contains("\n\n\n") {
            value = value.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        if start > 0 { value = "... \(value)" }
        if end < content.length { value += " ..." }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
