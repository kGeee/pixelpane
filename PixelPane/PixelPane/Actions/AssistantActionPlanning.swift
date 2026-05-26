import Foundation

enum AssistantPlannedActionKind: String, Equatable, Sendable {
    case answerDirectly = "answer_directly"
    case listGrants = "list_grants"
    case listFolder = "list_folder"
    case profileFolder = "profile_folder"
    case searchFiles = "search_files"
    case readFile = "read_file"
    case stageWriteProposal = "stage_write_proposal"
    case runTerminalCommand = "run_terminal_command"
}

struct AssistantPlannedAction: Equatable, Sendable {
    let kind: AssistantPlannedActionKind
    let arguments: [String: String]
    let reason: String?
    let finalAnswer: String?
}

struct AssistantActionPlan: Equatable, Sendable {
    let action: AssistantPlannedAction
}

struct AssistantActionPlanningPromptBuilder: Sendable {
    nonisolated func prompt(
        question: String,
        grants: [LocalFileGrant],
        toolState: AssistantToolState,
        observations: [AssistantLocalFileToolResult] = [],
        priorTurns: [AssistantContextPriorTurn] = []
    ) -> String {
        let activeGrants = grants
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        let grantLines = activeGrants.enumerated().map { index, grant in
            "\(index + 1). \(grant.kindLabel): \(grant.path)"
        }
        let recentFolder = toolState.lastListedFolder?.path ?? "none"
        let recentFiles = toolState.lastFileSources
            .prefix(8)
            .map { "- \($0.kindLabel): \($0.path)" }
            .joined(separator: "\n")
        let prior = priorTurnsSection(priorTurns)
        let recentTools = recentToolResultsSection(toolState.recentToolResults)
        let observationText = observationsSection(observations)

        return """
        You are Pixel Pane's model-agnostic action planner.
        Pick the next app action for the user's request. Pixel Pane, not you, executes tools, validates permissions, classifies risk, tracks sources, and asks for confirmation before side effects.

        Output only one JSON object. No markdown and no explanation outside JSON.
        JSON shape:
        {"action":"answer_directly|list_grants|list_folder|profile_folder|search_files|read_file|stage_write_proposal|run_terminal_command","arguments":{"path":"","query":"","scope_path":"","command":"","working_directory":"","reason":"","intent":"generic|file_search|system_inspection","timeout_seconds":"120","operation":"create|replace|append","target_path":"","content":""},"final_answer":""}

        Planning rules:
        - Use answer_directly only when no app tool is needed or when the observations already answer the user.
        - Use list_folder to inspect a granted folder before choosing a build, serve, test, or read action when the workspace is ambiguous.
        - Use profile_folder when the user asks what a folder, project, repo, site, workspace, or codebase is.
        - Use search_files to find local files by topic, project, website, filename, or content inside granted locations.
        - Use read_file for a specific granted text file or a recent file the user refers to.
        - Use stage_write_proposal for local file create/edit requests. Include operation, target_path, and complete content only when the user delegated the content to you.
        - Use run_terminal_command for explicit shell commands, builds, tests, dev servers, process control, and system inspection. Provide command, working_directory, reason, optional intent, and optional timeout_seconds.
        - If the user asks whether something is already running locally, inspect local listeners or recent verified URLs. Do not start a server unless the user asks to start, build, serve, open, view, or run it locally.
        - If the user asks to stop, end, or kill a previously started server/process, prefer the PID from recent terminal output and plan a command like kill <pid> in the same working directory.
        - If a recent terminal output includes a verified localhost URL or PID, use that observation instead of scanning unrelated ports.
        - Do not invent file access outside the granted locations. If no safe action is possible, use answer_directly and say what is missing.
        - Do not claim an action already happened. You are only planning the next action.

        Granted locations:
        \(grantLines.isEmpty ? "none" : grantLines.joined(separator: "\n"))

        Recent folder:
        \(recentFolder)

        Recent files:
        \(recentFiles.isEmpty ? "none" : recentFiles)

        Recent app tool results:
        \(recentTools.isEmpty ? "none" : recentTools)

        New observations from this planning loop:
        \(observationText.isEmpty ? "none" : observationText)

        Prior turns from this chat:
        \(prior.isEmpty ? "none" : prior)

        User request:
        \(question.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    private nonisolated func priorTurnsSection(_ turns: [AssistantContextPriorTurn]) -> String {
        let body = turns
            .suffix(4)
            .enumerated()
            .map { index, turn in
                """
                Turn \(index + 1) user: \(truncate(turn.question, limit: 500))
                Turn \(index + 1) assistant: \(truncate(turn.answer, limit: 1_200))
                """
            }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return truncate(body, limit: 4_000)
    }

    private nonisolated func recentToolResultsSection(_ results: [AssistantRecentToolResultState]) -> String {
        let body = results
            .prefix(5)
            .map { result in
                var lines = [
                    "- Tool: \(result.toolName.rawValue)",
                    "  Summary: \(truncate(result.summary, limit: 700))"
                ]
                if let command = result.terminalCommand {
                    lines.append("  Command: \(truncate(command, limit: 600))")
                }
                if let workingDirectory = result.terminalWorkingDirectory {
                    lines.append("  Working directory: \(workingDirectory)")
                }
                if let exitCode = result.terminalExitCode {
                    lines.append("  Exit code: \(exitCode)")
                }
                if let stdout = result.terminalStdout, !stdout.isEmpty {
                    lines.append("  stdout: \(truncate(stdout, limit: 1_200))")
                }
                if let stderr = result.terminalStderr, !stderr.isEmpty {
                    lines.append("  stderr: \(truncate(stderr, limit: 600))")
                }
                if let sources = result.sources, !sources.isEmpty {
                    let sourceLines = sources
                        .prefix(8)
                        .map { "\($0.kindLabel): \($0.path)" }
                        .joined(separator: "; ")
                    lines.append("  Sources: \(sourceLines)")
                }
                return lines.joined(separator: "\n")
            }
            .joined(separator: "\n\n")
        return truncate(body, limit: 6_000)
    }

    private nonisolated func observationsSection(_ observations: [AssistantLocalFileToolResult]) -> String {
        let body = observations
            .map { observation in
                var lines = [
                    "- Tool: \(observation.toolName.rawValue)",
                    "  Summary: \(truncate(observation.summary, limit: 800))"
                ]
                if let terminal = observation.terminalResult {
                    lines.append("  Command: \(truncate(terminal.command, limit: 600))")
                    lines.append("  Working directory: \(terminal.workingDirectory)")
                    lines.append("  Exit code: \(terminal.exitCode)")
                    if !terminal.stdout.isEmpty {
                        lines.append("  stdout: \(truncate(terminal.stdout, limit: 1_400))")
                    }
                    if !terminal.stderr.isEmpty {
                        lines.append("  stderr: \(truncate(terminal.stderr, limit: 700))")
                    }
                }
                if let snippets = observation.context?.snippets, !snippets.isEmpty {
                    let snippetLines = snippets
                        .prefix(3)
                        .map { "File: \($0.path)\n\(truncate($0.preview, limit: 1_200))" }
                        .joined(separator: "\n\n")
                    lines.append("  Snippets:\n\(snippetLines)")
                }
                if !observation.sources.isEmpty {
                    let sources = observation.sources
                        .prefix(10)
                        .map { "\($0.kindLabel): \($0.path)" }
                        .joined(separator: "; ")
                    lines.append("  Sources: \(sources)")
                }
                return lines.joined(separator: "\n")
            }
            .joined(separator: "\n\n")
        return truncate(body, limit: 7_000)
    }

    private nonisolated func truncate(_ value: String, limit: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

struct AssistantActionPlanParser: Sendable {
    nonisolated func parse(_ rawText: String) -> AssistantActionPlan? {
        guard let jsonText = extractJSONObject(from: rawText),
              let data = jsonText.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let actionPayload = (payload["action"] as? [String: Any])
            ?? (payload["tool"] as? [String: Any])
        let rawAction = stringValue(payload["action"])
            ?? stringValue(payload["tool"])
            ?? stringValue(payload["name"])
            ?? actionPayload.flatMap { stringValue($0["name"]) }
            ?? actionPayload.flatMap { stringValue($0["action"]) }
        guard let kind = rawAction.flatMap(actionKind(from:)) else {
            return nil
        }

        var arguments: [String: String] = [:]
        if let actionPayload {
            arguments.merge(stringArguments(from: actionPayload["arguments"] as? [String: Any] ?? actionPayload)) { _, new in new }
        }
        if let directArguments = payload["arguments"] as? [String: Any] {
            arguments.merge(stringArguments(from: directArguments)) { _, new in new }
        }
        for key in ["path", "query", "scope_path", "command", "working_directory", "reason", "intent", "timeout_seconds", "operation", "target_path", "content"] {
            if let value = stringValue(payload[key]) {
                arguments[key] = value
            }
        }

        let finalAnswer = [
            stringValue(payload["final_answer"]),
            stringValue(payload["answer"]),
            stringValue(payload["message"]),
            actionPayload.flatMap { stringValue($0["final_answer"]) },
            actionPayload.flatMap { stringValue($0["answer"]) },
            actionPayload.flatMap { stringValue($0["message"]) }
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        let reason = [
            stringValue(payload["reason"]),
            stringValue(payload["rationale"]),
            actionPayload.flatMap { stringValue($0["reason"]) },
            actionPayload.flatMap { stringValue($0["rationale"]) }
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        return AssistantActionPlan(
            action: AssistantPlannedAction(
                kind: kind,
                arguments: arguments,
                reason: reason,
                finalAnswer: finalAnswer
            )
        )
    }

    private nonisolated func actionKind(from rawValue: String) -> AssistantPlannedActionKind? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
        switch normalized {
        case "answer", "answer_directly", "direct_answer", "respond", "none":
            return .answerDirectly
        case "list_grants", "grants":
            return .listGrants
        case "list_folder", "listfolder", "folder", "inspect_folder":
            return .listFolder
        case "profile_folder", "profilefolder", "profile_project", "inspect_project", "project_profile":
            return .profileFolder
        case "search_files", "searchfiles", "file_search", "search":
            return .searchFiles
        case "read_file", "readfile", "read":
            return .readFile
        case "stage_write_proposal", "write_file", "propose_write", "write":
            return .stageWriteProposal
        case "run_terminal_command", "runterminalcommand", "terminal", "shell", "command":
            return .runTerminalCommand
        default:
            return nil
        }
    }

    private nonisolated func stringArguments(from object: [String: Any]) -> [String: String] {
        object.reduce(into: [String: String]()) { result, element in
            guard !["action", "tool", "name", "arguments", "final_answer", "answer", "message"].contains(element.key),
                  let value = stringValue(element.value)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return
            }
            result[element.key] = value
        }
    }

    private nonisolated func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        case let value as Bool:
            return value ? "true" : "false"
        default:
            return nil
        }
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
