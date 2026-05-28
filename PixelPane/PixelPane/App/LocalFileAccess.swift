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

struct LocalFileWriteProposal: Codable, Equatable, Identifiable, Sendable {
    enum Operation: Codable, Equatable, Sendable {
        case create(content: String)
        case replaceContents(content: String)
        case append(content: String)
        case replaceText(oldText: String, newText: String)
    }

    let id: UUID
    let targetPath: String
    let operation: Operation

    nonisolated var actionLabel: String {
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

    nonisolated var detailText: String {
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

struct AssistantGeneratedWriteDraft: Equatable, Sendable {
    enum Operation: String, Equatable, Sendable {
        case create
        case replace
        case append
    }

    let operation: Operation
    let targetPath: String
    let content: String
}

struct LocalFileWriteProposalParser: Sendable {
    private let maxContentCharacters = 100_000

    nonisolated init() {}

    nonisolated func proposal(
        from draft: AssistantGeneratedWriteDraft,
        grants: [LocalFileGrant],
        preferredDirectoryPath: String? = nil,
        recentTargetPaths: [String] = []
    ) -> LocalFileWriteProposalResult {
        let activeGrants = grants.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !activeGrants.isEmpty else {
            return .message("Grant a file or folder in Settings -> Files before I can propose local file changes.")
        }

        let content = normalizedGeneratedContent(
            draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !content.isEmpty else {
            return .message("The model planned an empty file change.")
        }
        guard content.count <= maxContentCharacters else {
            return .message("That proposed file change is too large. Keep confirmed local writes under \(maxContentCharacters) characters.")
        }

        guard let targetURL = resolvedURL(
            for: draft.targetPath,
            grants: activeGrants,
            preferredDirectoryPath: preferredDirectoryPath,
            recentTargetPaths: recentTargetPaths
        ) else {
            return .message("The model chose a target path outside the granted folders. Try naming the granted folder more explicitly.")
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return .message("The model chose a folder instead of a file path. Ask again with a filename, or let me choose one.")
        }

        let fileExists = FileManager.default.fileExists(atPath: targetURL.path)
        let operation: LocalFileWriteProposal.Operation
        switch draft.operation {
        case .append:
            guard fileExists else {
                return .message("I can append only to an existing granted text file. Ask me to create a file instead.")
            }
            operation = .append(content: content)
        case .replace:
            operation = fileExists ? .replaceContents(content: content) : .create(content: content)
        case .create:
            operation = fileExists ? .replaceContents(content: content) : .create(content: content)
        }

        return .proposal(
            LocalFileWriteProposal(
                id: UUID(),
                targetPath: targetURL.path,
                operation: operation
            )
        )
    }

    private nonisolated func normalizedGeneratedContent(_ content: String) -> String {
        var normalized = content
        if content.contains(" n-")
            || content.contains(" n\n")
            || content.contains(" n\r\n")
            || content.hasSuffix(" n") {
            normalized = normalized
                .replacingOccurrences(of: " n- ", with: "\n- ")
                .replacingOccurrences(of: " n-", with: "\n-")
                .replacingOccurrences(of: " n\r\n", with: "\n\n")
                .replacingOccurrences(of: " n\n", with: "\n\n")
                .replacingOccurrences(of: #" n$"#, with: "\n", options: .regularExpression)
        }
        if looksLikeCodeWithLiteralNewlineArtifact(normalized) {
            normalized = normalized
                .replacingOccurrences(
                    of: #" n(?=\s{2,}\S)"#,
                    with: "\n",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: #" n(?=[A-Za-z_#])"#,
                    with: "\n",
                    options: .regularExpression
                )
        }
        return normalized
    }

    private nonisolated func looksLikeCodeWithLiteralNewlineArtifact(_ content: String) -> Bool {
        if content.hasPrefix("#!") {
            return true
        }
        let lowercased = content.lowercased()
        return [
            " nimport ",
            " nfrom ",
            " nwith ",
            " ndef ",
            " nclass ",
            " nif ",
            " nfor ",
            " nwhile ",
            " ntry ",
            " nexcept ",
            " necho ",
            " nprintf ",
            " ncp ",
            " nmv ",
            " ncat ",
            " nsubprocess"
        ].contains { lowercased.contains($0) }
    }

    private nonisolated func resolvedURL(
        for path: String,
        grants: [LocalFileGrant],
        preferredDirectoryPath: String?,
        recentTargetPaths: [String]
    ) -> URL? {
        let cleanedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if let recentURL = recentTargetURL(
            matching: cleanedPath,
            grants: grants,
            recentTargetPaths: recentTargetPaths
        ) {
            return recentURL
        }

        let rawURL: URL?
        if cleanedPath.hasPrefix("/") {
            rawURL = URL(fileURLWithPath: cleanedPath)
        } else if let grantRelativeURL = grantRelativeURL(for: cleanedPath, grants: grants) {
            rawURL = grantRelativeURL
        } else if let preferredDirectoryPath,
                  let preferredGrant = grants.first(where: { grant in
                      grant.isDirectory
                          && grant.url.standardizedFileURL.path == URL(fileURLWithPath: preferredDirectoryPath).standardizedFileURL.path
                  }) {
            rawURL = preferredGrant.url.appendingPathComponent(cleanedPath)
        } else {
            rawURL = grants.first(where: { $0.isDirectory })?.url.appendingPathComponent(cleanedPath)
        }
        guard let candidate = rawURL?.standardizedFileURL else { return nil }

        if isAllowed(candidate, grants: grants) {
            return candidate
        }

        guard !cleanedPath.contains("/") else { return nil }
        return recursiveTargetURL(
            named: cleanedPath,
            grants: grants,
            preferredDirectoryPath: preferredDirectoryPath
        )
    }

    private nonisolated func grantRelativeURL(
        for cleanedPath: String,
        grants: [LocalFileGrant]
    ) -> URL? {
        let parts = cleanedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first else { return nil }
        let candidates = grants.filter(\.isDirectory)
        guard let grant = candidates.first(where: { grant in
            let name = grant.url.lastPathComponent
            return name.localizedCaseInsensitiveCompare(first) == .orderedSame
                || grant.displayName.localizedCaseInsensitiveCompare(first) == .orderedSame
        }) else {
            return nil
        }
        let remainder = parts.dropFirst().joined(separator: "/")
        guard !remainder.isEmpty else { return grant.url.standardizedFileURL }
        return grant.url.appendingPathComponent(remainder).standardizedFileURL
    }

    private nonisolated func recentTargetURL(
        matching reference: String,
        grants: [LocalFileGrant],
        recentTargetPaths: [String]
    ) -> URL? {
        let cleaned = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let matches = recentTargetPaths.compactMap { rawPath -> URL? in
            let url = URL(fileURLWithPath: rawPath).standardizedFileURL
            guard isAllowed(url, grants: grants) else { return nil }
            if url.lastPathComponent.localizedCaseInsensitiveCompare(cleaned) == .orderedSame
                || url.path.localizedCaseInsensitiveContains(cleaned) {
                return url
            }
            return nil
        }
        return matches.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }.first
    }

    private nonisolated func recursiveTargetURL(
        named fileName: String,
        grants: [LocalFileGrant],
        preferredDirectoryPath: String?
    ) -> URL? {
        let activeFolders = grants.filter(\.isDirectory)
        let preferred = preferredDirectoryPath.flatMap { preferredPath in
            activeFolders.first { folder in
                folder.url.standardizedFileURL.path == URL(fileURLWithPath: preferredPath).standardizedFileURL.path
            }
        }
        let orderedFolders = ([preferred].compactMap { $0 } + activeFolders).reduce(into: [LocalFileGrant]()) { result, folder in
            guard !result.contains(where: { $0.path == folder.path }) else { return }
            result.append(folder)
        }

        var matches: [URL] = []
        for folder in orderedFolders {
            if let match = firstFile(named: fileName, in: folder.url.standardizedFileURL, maxDepth: 8) {
                matches.append(match)
            }
        }
        return matches.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }.first
    }

    private nonisolated func firstFile(named fileName: String, in root: URL, maxDepth: Int) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        var matches: [URL] = []
        for case let url as URL in enumerator {
            let relative = relativePath(from: root, to: url)
            let parts = relative.split(separator: "/").map(String.init)
            if shouldSkip(relativePath: relative) {
                enumerator.skipDescendants()
                continue
            }
            guard parts.count <= maxDepth else {
                enumerator.skipDescendants()
                continue
            }
            guard url.lastPathComponent.localizedCaseInsensitiveCompare(fileName) == .orderedSame else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                matches.append(url)
            }
        }
        return matches.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }.first
    }

    private nonisolated func isAllowed(_ candidate: URL, grants: [LocalFileGrant]) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        for grant in grants {
            let grantURL = grant.url.standardizedFileURL
            if grant.isDirectory {
                let root = grantURL.path.hasSuffix("/") ? grantURL.path : grantURL.path + "/"
                if candidatePath.hasPrefix(root) {
                    return true
                }
            } else if candidatePath == grantURL.path {
                return true
            }
        }
        return false
    }

    private nonisolated func shouldSkip(relativePath: String) -> Bool {
        let skipped = Set([".git", "node_modules", "DerivedData", ".build", "build", "dist", ".next"])
        return relativePath.split(separator: "/").contains { skipped.contains(String($0)) }
    }

    private nonisolated func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count))
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
        var seenSnippetPaths: Set<String> = []
        var visitedFiles = 0
        var filesRead = 0
        var contentCandidates: [URL] = []

        for grant in activeGrants {
            guard visitedFiles < maxCandidateFiles else { break }
            for fileURL in fileURLs(in: grant) {
                guard visitedFiles < maxCandidateFiles, !Task.isCancelled else { break }
                guard !seenSnippetPaths.contains(fileURL.path) else { continue }
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
                seenSnippetPaths.insert(fileURL.path)
            }
        }

        for fileURL in contentCandidates {
            guard filesRead < maxFilesToRead, !Task.isCancelled else { break }
            guard !seenSnippetPaths.contains(fileURL.path) else { continue }
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
            seenSnippetPaths.insert(fileURL.path)
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
            "rs", "rb", "php", "sh", "zsh", "bash", "sql", "ini", "conf", "env",
            "tex"
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
            "from", "have", "her", "him", "his", "into", "local", "read",
            "search", "show", "tell", "that", "the", "their", "there", "this",
            "what", "when", "where", "which", "whose", "with", "would", "you",
            "your"
        ]

        let normalized = Self.normalized(question)
        let baseTerms = Set(
            normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && !stopwords.contains($0) }
        )
        return Array(baseTerms).sorted()
    }

    private nonisolated func score(text: String, terms: [String]) -> Int {
        let lowercased = text.lowercased()
        return terms.reduce(0) { partial, term in
            var count = 0
            var searchRange = lowercased.startIndex..<lowercased.endIndex
            while let range = lowercased.range(of: term, options: [], range: searchRange) {
                count += 1
                guard count < 4 else { break }
                searchRange = range.upperBound..<lowercased.endIndex
            }
            return partial + count
        }
    }

    private nonisolated func snippet(from text: String, terms: [String]) -> String {
        let lowercased = text.lowercased() as NSString
        let content = text as NSString
        let locations = terms
            .map { lowercased.range(of: $0).location }
            .filter { $0 != NSNotFound }
        let matchLocation = bestSnippetLocation(
            in: lowercased,
            contentLength: content.length,
            terms: terms,
            fallbackLocations: locations
        )
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

    private nonisolated func bestSnippetLocation(
        in lowercased: NSString,
        contentLength: Int,
        terms: [String],
        fallbackLocations: [Int]
    ) -> Int {
        guard !fallbackLocations.isEmpty else { return 0 }

        let candidates = Array(Set(fallbackLocations)).sorted()
        let best = candidates.max { lhs, rhs in
            snippetWindowScore(
                in: lowercased,
                contentLength: contentLength,
                center: lhs,
                terms: terms
            ) < snippetWindowScore(
                in: lowercased,
                contentLength: contentLength,
                center: rhs,
                terms: terms
            )
        }
        return best ?? fallbackLocations.min() ?? 0
    }

    private nonisolated func snippetWindowScore(
        in lowercased: NSString,
        contentLength: Int,
        center: Int,
        terms: [String]
    ) -> Int {
        let start = max(0, center - snippetRadius)
        let end = min(contentLength, center + snippetRadius)
        let range = NSRange(location: start, length: max(0, end - start))
        guard range.length > 0 else { return 0 }
        let window = lowercased.substring(with: range)
        return terms.reduce(0) { partial, term in
            partial + (window.contains(term) ? 1 : 0)
        }
    }
}
