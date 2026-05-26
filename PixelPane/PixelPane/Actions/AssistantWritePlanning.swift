import Foundation

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

struct AssistantWritePlanningPromptBuilder: Sendable {
    nonisolated func prompt(
        question: String,
        grants: [LocalFileGrant],
        toolState: AssistantToolState,
        priorTurns: [AssistantContextPriorTurn] = []
    ) -> String {
        let activeFolders = grants
            .filter { $0.isDirectory && FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        let activeFiles = grants
            .filter { !$0.isDirectory && FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        let folderLines = activeFolders.enumerated().map { index, grant in
            "\(index + 1). \(grant.displayName): \(grant.path)"
        }
        let fileLines = activeFiles.enumerated().map { index, grant in
            "\(index + 1). \(grant.displayName): \(grant.path)"
        }
        let recentFolder = toolState.lastListedFolder?.path ?? "none"
        let recentFiles = toolState.lastFileSources
            .filter { $0.kindLabel == "File" }
            .prefix(6)
            .map(\.path)
            .joined(separator: "\n")
        let recentSnippets = toolState.lastFileSnippets
            .prefix(4)
            .map { snippet in
                """
                File: \(snippet.path)
                \(snippet.preview)
                """
            }
            .joined(separator: "\n\n")
        let priorConversation = priorTurnsSection(priorTurns)

        return """
        You are planning one local file write for Pixel Pane.
        The user is allowed to delegate creative and practical choices to you, including filename and file contents.
        Choose a complete target file path and complete content that satisfy the user.
        Use only the current chat turns and tool context shown in this prompt. Do not assume any hidden or global chat history.

        Hard rules:
        - Output only one JSON object. No markdown and no explanation.
        - The target_path must be inside one granted folder or exactly one granted file.
        - Prefer an explicitly named granted folder from the user prompt.
        - If the current user request is a clarification to a prior write request, combine it with the prior write request and current tool context.
        - If the user refers to "this folder" or a recent folder, use the Recent folder when it is not "none".
        - If the user asks to format, reformat, clean up, polish, organize, or make a recent file nicer, use the current content from Recent file snippets and target that same file.
        - If the user refers to "this", "these results", "that output", "the previous result", "the last answer", or similar, use the relevant prior assistant answer in this current chat as the file content.
        - Preserve referenced result lines exactly unless the user asks for a summary or rewrite.
        - Do not invent placeholder results when prior chat output answers the user's reference.
        - If the user does not provide a filename for a text/story/note, choose a reasonable filename such as story.txt or notes.md.
        - Put the complete file contents in content. Do not ask the user to provide content when they asked you to choose.
        - Encode line breaks in JSON strings as \\n so the written file contains real newlines. Do not use a literal " n" marker.
        - Do not include commands, shell syntax, or commentary.

        JSON schema:
        {"operation":"create|replace|append","target_path":"/absolute/or/grant-relative/path","content":"complete UTF-8 text"}

        Granted folders:
        \(folderLines.isEmpty ? "none" : folderLines.joined(separator: "\n"))

        Granted files:
        \(fileLines.isEmpty ? "none" : fileLines.joined(separator: "\n"))

        Recent folder:
        \(recentFolder)

        Recent files:
        \(recentFiles.isEmpty ? "none" : recentFiles)

        Recent file snippets:
        \(recentSnippets.isEmpty ? "none" : recentSnippets)

        Relevant prior turns from this chat only:
        \(priorConversation.isEmpty ? "none" : priorConversation)

        User request:
        \(question.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    private nonisolated func priorTurnsSection(_ turns: [AssistantContextPriorTurn]) -> String {
        let body = turns
            .suffix(4)
            .enumerated()
            .map { index, turn in
                let question = truncate(
                    turn.question.trimmingCharacters(in: .whitespacesAndNewlines),
                    limit: 600
                )
                let answer = truncate(
                    turn.answer.trimmingCharacters(in: .whitespacesAndNewlines),
                    limit: 2_000
                )
                return """
                Turn \(index + 1) user: \(question.isEmpty ? "No user text." : question)
                Turn \(index + 1) assistant: \(answer.isEmpty ? "No assistant answer yet." : answer)
                """
            }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return truncate(body, limit: 5_000)
    }

    private nonisolated func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let end = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

struct AssistantGeneratedWriteDraftParser: Sendable {
    nonisolated func parse(_ rawText: String) -> AssistantGeneratedWriteDraft? {
        guard let jsonText = extractJSONObject(from: rawText),
              let data = jsonText.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let rawOperation = (stringValue(payload["operation"]) ?? stringValue(payload["action"]) ?? "create")
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let operation: AssistantGeneratedWriteDraft.Operation
        if rawOperation.contains("append") {
            operation = .append
        } else if rawOperation.contains("replace")
            || rawOperation.contains("overwrite")
            || rawOperation.contains("update")
            || rawOperation.contains("edit") {
            operation = .replace
        } else {
            operation = .create
        }

        guard let target = [
            stringValue(payload["targetPath"]),
            stringValue(payload["target_path"]),
            stringValue(payload["path"]),
            stringValue(payload["filename"])
        ]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }),
              let content = stringValue(payload["content"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            return nil
        }

        return AssistantGeneratedWriteDraft(
            operation: operation,
            targetPath: target,
            content: content
        )
    }

    private nonisolated func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private nonisolated func extractJSONObject(from rawText: String) -> String? {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(text[start...end])
    }
}

enum AssistantWriteIntentDetector {
    nonisolated static func shouldUseModelPlanning(
        question: String,
        grants: [LocalFileGrant],
        toolState: AssistantToolState
    ) -> Bool {
        guard grants.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return false
        }
        let normalized = normalize(question)
        if isPendingWriteClarification(normalized, grants: grants, toolState: toolState) {
            return true
        }
        let hasWriteIntent = hasWriteVerb(normalized) || hasTransformVerb(normalized)
        guard hasWriteIntent else { return false }
        if hasExplicitContentDelimiter(normalized) {
            return false
        }
        if normalized.hasPrefix("replace in ")
            || normalized.hasPrefix("replace text in ")
            || normalized.hasPrefix("append to ") {
            return false
        }
        if mentionsGrantedLocation(normalized, grants: grants) {
            return true
        }
        if toolState.lastListedFolder != nil,
           containsAny(normalized, ["this folder", "inside this", "in here", "there", "same folder"]) {
            return true
        }
        if containsAny(normalized, [
            "text file",
            "txt file",
            ".txt",
            ".md",
            "md file",
            "markdown",
            "markdown file",
            "story.txt",
            "notes.txt",
            "within ",
            "inside ",
            "to a file",
            "as a file",
            "save this",
            "save these",
            "write this",
            "write these"
        ]) {
            return true
        }
        if hasRecentActionableContext(toolState),
           containsAny(normalized, ["this", "these", "that", "previous", "last answer", "last result"]) {
            return true
        }
        if hasTransformVerb(normalized), hasRecentWritableFile(toolState) {
            return true
        }
        return containsAny(normalized, ["inside the file", "inside a file", "to a file", "as a file", "save it"])
    }

    nonisolated static func isNaturalFileWritePrompt(_ normalized: String) -> Bool {
        guard hasWriteVerb(normalized) || hasTransformVerb(normalized) else { return false }
        return containsAny(normalized, [
            "create file",
            "write file",
            "edit file",
            "modify file",
            "update file",
            "overwrite file",
            "text file",
            "txt file",
            "md file",
            ".md",
            "markdown",
            "inside the file",
            "inside a file",
            "to a file",
            "as a file",
            "save it",
            "format it",
            "reformat",
            "formatted poorly",
            "format the file",
            "clean it up",
            "make it nicer",
            "make this nicer",
            "organize it"
        ])
    }

    private nonisolated static func hasWriteVerb(_ normalized: String) -> Bool {
        containsAny(normalized, [
            "create",
            "write",
            "save",
            "make",
            "draft",
            "compose",
            "put",
            "add"
        ])
    }

    private nonisolated static func hasTransformVerb(_ normalized: String) -> Bool {
        containsAny(normalized, [
            "format",
            "reformat",
            "formatted poorly",
            "clean up",
            "clean it up",
            "polish",
            "prettify",
            "make it nicer",
            "make this nicer",
            "organize",
            "tidy"
        ])
    }

    private nonisolated static func hasRecentWritableFile(_ toolState: AssistantToolState) -> Bool {
        (toolState.lastFileSources + toolState.grantedSourcesUsed).contains { $0.kindLabel == "File" }
    }

    private nonisolated static func hasRecentActionableContext(_ toolState: AssistantToolState) -> Bool {
        if !toolState.recentToolResults.isEmpty || !toolState.lastFileSnippets.isEmpty {
            return true
        }
        return !toolState.lastFileSources.isEmpty || !toolState.grantedSourcesUsed.isEmpty
    }

    private nonisolated static func isPendingWriteClarification(
        _ normalized: String,
        grants: [LocalFileGrant],
        toolState: AssistantToolState
    ) -> Bool {
        guard let recentWrite = toolState.recentToolResults.first(where: { $0.toolName == .stageWriteProposal }),
              let summary = recentWrite.writeProposalSummary?.lowercased(),
              summary.contains("name the target path") || summary.contains("target path and content") else {
            return false
        }
        return mentionsGrantedLocation(normalized, grants: grants)
            || fuzzyMentionsGrantedLocation(normalized, grants: grants)
            || containsAny(normalized, [
                "folder",
                "file",
                "path",
                "directory",
                "repo",
                "workspace",
                "here",
                "there",
                "this one",
                "that one"
            ])
    }

    private nonisolated static func hasExplicitContentDelimiter(_ normalized: String) -> Bool {
        normalized.contains(" with content:")
            || normalized.contains(" content:")
            || normalized.contains("append to ")
            || normalized.contains("replace in ")
            || normalized.contains("replace text in ")
    }

    private nonisolated static func mentionsGrantedLocation(
        _ normalized: String,
        grants: [LocalFileGrant]
    ) -> Bool {
        grants.contains { grant in
            let name = URL(fileURLWithPath: grant.path).lastPathComponent.lowercased()
            return (!name.isEmpty && normalized.contains(name))
                || normalized.contains(grant.path.lowercased())
        }
    }

    private nonisolated static func fuzzyMentionsGrantedLocation(
        _ normalized: String,
        grants: [LocalFileGrant]
    ) -> Bool {
        let tokens = normalized
            .split { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" }
            .map(String.init)
            .filter { $0.count >= 4 }
        guard !tokens.isEmpty else { return false }
        return grants.contains { grant in
            let name = URL(fileURLWithPath: grant.path).lastPathComponent.lowercased()
            guard name.count >= 4 else { return false }
            return tokens.contains { token in
                token == name || boundedEditDistance(token, name, maxDistance: 3) != nil
            }
        }
    }

    private nonisolated static func boundedEditDistance(
        _ lhs: String,
        _ rhs: String,
        maxDistance: Int
    ) -> Int? {
        let left = Array(lhs)
        let right = Array(rhs)
        guard abs(left.count - right.count) <= maxDistance else { return nil }
        if left.isEmpty { return right.count <= maxDistance ? right.count : nil }
        if right.isEmpty { return left.count <= maxDistance ? left.count : nil }

        var previous = Array(0...right.count)
        for i in 1...left.count {
            var current = [i] + Array(repeating: 0, count: right.count)
            var rowMinimum = current[0]
            for j in 1...right.count {
                let substitution = previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1)
                let insertion = current[j - 1] + 1
                let deletion = previous[j] + 1
                current[j] = min(substitution, insertion, deletion)
                rowMinimum = min(rowMinimum, current[j])
            }
            guard rowMinimum <= maxDistance else { return nil }
            previous = current
        }

        let distance = previous[right.count]
        return distance <= maxDistance ? distance : nil
    }

    private nonisolated static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private nonisolated static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
}
