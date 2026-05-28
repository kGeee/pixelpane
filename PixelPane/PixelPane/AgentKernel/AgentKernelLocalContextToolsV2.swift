import Foundation

extension AgentKernelTerminalReasonV2: Error {}

struct AgentKernelToolSourceRecordV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: String
    let path: String?
    let displayName: String
    let summary: AgentKernelBoundedTextV2
    let snippetCount: Int
    let isTruncated: Bool
    let metadata: [String: AgentKernelMetadataValueV2]

    nonisolated init(
        id: String,
        kind: String,
        path: String? = nil,
        displayName: String,
        summary: AgentKernelBoundedTextV2,
        snippetCount: Int = 0,
        isTruncated: Bool = false,
        metadata: [String: AgentKernelMetadataValueV2] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.displayName = displayName
        self.summary = summary
        self.snippetCount = snippetCount
        self.isTruncated = isTruncated
        self.metadata = metadata
    }
}

struct AgentKernelFileItemV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let path: String
    let displayName: String
    let kindLabel: String
    let isDirectory: Bool
    let byteCount: Int?

    nonisolated init(
        path: String,
        displayName: String,
        kindLabel: String,
        isDirectory: Bool,
        byteCount: Int? = nil
    ) {
        self.id = path
        self.path = path
        self.displayName = displayName
        self.kindLabel = kindLabel
        self.isDirectory = isDirectory
        self.byteCount = byteCount
    }
}

struct AgentKernelFileListOutputV2: Codable, Equatable, Sendable {
    let summary: AgentKernelBoundedTextV2
    let entries: [AgentKernelFileItemV2]
    let sources: [AgentKernelToolSourceRecordV2]
    let isTruncated: Bool
}

struct AgentKernelFileSearchOutputV2: Codable, Equatable, Sendable {
    let summary: AgentKernelBoundedTextV2
    let snippets: [AgentKernelFileSnippetV2]
    let sources: [AgentKernelToolSourceRecordV2]
    let isTruncated: Bool
}

struct AgentKernelFileSnippetV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let path: String
    let preview: AgentKernelBoundedTextV2
    let score: Int

    nonisolated init(snippet: LocalFileSnippet) {
        self.id = snippet.id
        self.path = snippet.path
        self.preview = AgentKernelBoundedTextV2(snippet.preview)
        self.score = snippet.score
    }
}

struct AgentKernelFileReadOutputV2: Codable, Equatable, Sendable {
    let summary: AgentKernelBoundedTextV2
    let path: String
    let content: AgentKernelBoundedTextV2
    let byteCount: Int
    let sources: [AgentKernelToolSourceRecordV2]
}

struct AgentKernelWriteProposalOutputV2: Codable, Equatable, Sendable {
    let summary: AgentKernelBoundedTextV2
    let proposal: LocalFileWriteProposal
    let requiresApproval: Bool
    let sources: [AgentKernelToolSourceRecordV2]
}

struct AgentKernelVisualContextOutputV2: Codable, Equatable, Sendable {
    let summary: AgentKernelBoundedTextV2
    let source: String
    let label: String
    let hasTransientImageInput: Bool
    let hasOCRText: Bool
    let ocrExcerpt: AgentKernelBoundedTextV2?
    let imagePixelsPersisted: Bool
    let sources: [AgentKernelToolSourceRecordV2]
}

struct AgentKernelLocalContextToolsV2: Sendable {
    let maxDirectoryEntries: Int
    let maxReadFileBytes: Int
    let maxReadCharacters: Int
    private let contextProvider: LocalFileContextProvider
    private let writeProposalParser: LocalFileWriteProposalParser

    private nonisolated var fileManager: FileManager {
        .default
    }

    nonisolated init(
        maxDirectoryEntries: Int = 200,
        maxReadFileBytes: Int = 1_000_000,
        maxReadCharacters: Int = 80_000,
        contextProvider: LocalFileContextProvider = LocalFileContextProvider(),
        writeProposalParser: LocalFileWriteProposalParser = LocalFileWriteProposalParser()
    ) {
        self.maxDirectoryEntries = max(1, maxDirectoryEntries)
        self.maxReadFileBytes = max(1, maxReadFileBytes)
        self.maxReadCharacters = max(1, maxReadCharacters)
        self.contextProvider = contextProvider
        self.writeProposalParser = writeProposalParser
    }

    nonisolated static var definitions: [AgentKernelToolDefinitionV2] {
        [
            AgentKernelToolDefinitionV2(
                name: "list_grants",
                summary: "List local files and folders the user has explicitly granted.",
                inputArguments: [],
                outputType: AgentKernelToolIOTypeV2(
                    name: "file_list",
                    summary: "Granted local locations with source records."
                ),
                risk: .readOnly,
                scopeRequirements: [.grantedFileRead],
                requiresApproval: false
            ),
            AgentKernelToolDefinitionV2(
                name: "list_folder",
                summary: "List entries in a granted folder or list granted roots when no path is provided.",
                inputArguments: [
                    AgentKernelToolArgumentSchemaV2(
                        name: "path",
                        type: .string,
                        isRequired: false,
                        summary: "Granted folder path, grant name, or path relative to a granted folder."
                    )
                ],
                outputType: AgentKernelToolIOTypeV2(
                    name: "file_list",
                    summary: "Folder entries with source records."
                ),
                risk: .readOnly,
                scopeRequirements: [.grantedFileRead],
                requiresApproval: false
            ),
            AgentKernelToolDefinitionV2(
                name: "search_files",
                summary: "Search text-like files inside granted local locations.",
                inputArguments: [
                    AgentKernelToolArgumentSchemaV2(
                        name: "query",
                        type: .string,
                        summary: "Search query."
                    )
                ],
                outputType: AgentKernelToolIOTypeV2(
                    name: "file_search_results",
                    summary: "Bounded matching snippets and source records."
                ),
                risk: .readOnly,
                scopeRequirements: [.grantedFileRead],
                requiresApproval: false
            ),
            AgentKernelToolDefinitionV2(
                name: "read_file",
                summary: "Read a bounded text view of a granted local file.",
                inputArguments: [
                    AgentKernelToolArgumentSchemaV2(
                        name: "path",
                        type: .string,
                        summary: "Granted file path, grant name, or path relative to a granted folder."
                    )
                ],
                outputType: AgentKernelToolIOTypeV2(
                    name: "file_contents",
                    summary: "Bounded text and source records."
                ),
                risk: .readOnly,
                scopeRequirements: [.grantedFileRead],
                requiresApproval: false
            ),
            AgentKernelToolDefinitionV2(
                name: "stage_write_proposal",
                summary: "Stage a proposed write inside a granted local location without writing it to disk.",
                inputArguments: [
                    AgentKernelToolArgumentSchemaV2(
                        name: "operation",
                        type: .string,
                        summary: "One of create, replace, or append."
                    ),
                    AgentKernelToolArgumentSchemaV2(
                        name: "targetPath",
                        type: .string,
                        summary: "Granted target file path or path relative to a granted folder."
                    ),
                    AgentKernelToolArgumentSchemaV2(
                        name: "content",
                        type: .string,
                        summary: "Proposed file content."
                    ),
                    AgentKernelToolArgumentSchemaV2(
                        name: "preferredDirectoryPath",
                        type: .string,
                        isRequired: false,
                        summary: "Optional granted directory to prefer when resolving relative paths."
                    )
                ],
                outputType: AgentKernelToolIOTypeV2(
                    name: "write_proposal",
                    summary: "Staged write proposal and source records."
                ),
                risk: .sideEffect,
                scopeRequirements: [.grantedFileWrite],
                requiresApproval: true
            ),
            AgentKernelToolDefinitionV2(
                name: "describe_visual_context",
                summary: "Describe the active screenshot, attachment, clipboard image, and OCR context without persisting pixels.",
                inputArguments: [],
                outputType: AgentKernelToolIOTypeV2(
                    name: "visual_context",
                    summary: "Visual-context metadata and bounded OCR excerpt."
                ),
                risk: .readOnly,
                scopeRequirements: [.visualContext],
                requiresApproval: false
            )
        ]
    }

    nonisolated func listGrants(
        grants: [LocalFileGrant]
    ) -> Result<AgentKernelFileListOutputV2, AgentKernelTerminalReasonV2> {
        let activeGrants = activeGrants(from: grants)
        let entries = activeGrants.map { grant in
            AgentKernelFileItemV2(
                path: grant.url.standardizedFileURL.path,
                displayName: grant.displayName,
                kindLabel: grant.kindLabel,
                isDirectory: grant.isDirectory,
                byteCount: grant.isDirectory ? nil : fileSize(grant.url)
            )
        }
        let sources = activeGrants.map { sourceRecord(for: $0) }
        return .success(
            AgentKernelFileListOutputV2(
                summary: AgentKernelBoundedTextV2("Found \(entries.count) active granted local location(s)."),
                entries: entries,
                sources: sources,
                isTruncated: false
            )
        )
    }

    nonisolated func listFolder(
        path: String?,
        grants: [LocalFileGrant]
    ) -> Result<AgentKernelFileListOutputV2, AgentKernelTerminalReasonV2> {
        let cleanedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanedPath.isEmpty else {
            return listGrants(grants: grants)
        }

        switch resolvedGrantedURL(for: cleanedPath, grants: grants) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let url):
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return .failure(reason(code: "file_not_found", summary: "The requested folder does not exist.", path: url.path))
            }
            guard isDirectory.boolValue else {
                return .failure(reason(code: "not_a_folder", summary: "The requested path is a file, not a folder.", path: url.path))
            }

            do {
                let urls = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
                let sorted = urls.sorted { lhs, rhs in
                    lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
                }
                let visible = Array(sorted.prefix(maxDirectoryEntries))
                let entries = visible.map { item in
                    let values = try? item.resourceValues(forKeys: Set([URLResourceKey.isDirectoryKey]))
                    let isDirectory = values?.isDirectory ?? false
                    return AgentKernelFileItemV2(
                        path: item.standardizedFileURL.path,
                        displayName: item.lastPathComponent,
                        kindLabel: isDirectory ? "Folder" : "File",
                        isDirectory: isDirectory,
                        byteCount: isDirectory ? nil : fileSize(item)
                    )
                }
                let truncated = sorted.count > visible.count
                return .success(
                    AgentKernelFileListOutputV2(
                        summary: AgentKernelBoundedTextV2("Listed \(entries.count) item(s) in \(url.path)."),
                        entries: entries,
                        sources: [
                            AgentKernelToolSourceRecordV2(
                                id: "folder:\(url.path)",
                                kind: "folder",
                                path: url.path,
                                displayName: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                                summary: AgentKernelBoundedTextV2("Granted folder listing."),
                                snippetCount: entries.count,
                                isTruncated: truncated
                            )
                        ],
                        isTruncated: truncated
                    )
                )
            } catch {
                return .failure(reason(code: "folder_list_failed", summary: error.localizedDescription, path: url.path))
            }
        }
    }

    nonisolated func searchFiles(
        query: String,
        grants: [LocalFileGrant]
    ) -> Result<AgentKernelFileSearchOutputV2, AgentKernelTerminalReasonV2> {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else {
            return .failure(reason(code: "empty_query", summary: "Search query cannot be empty."))
        }

        let context = contextProvider.context(for: cleanedQuery, grants: grants)
        let grantSources = context.grants.map { sourceRecord(for: $0) }
        let snippetSources = context.snippets.map { snippet in
            AgentKernelToolSourceRecordV2(
                id: "file:\(snippet.path)",
                kind: "file",
                path: snippet.path,
                displayName: URL(fileURLWithPath: snippet.path).lastPathComponent,
                summary: AgentKernelBoundedTextV2("Matched local file snippet."),
                snippetCount: 1,
                isTruncated: snippet.preview.hasPrefix("...") || snippet.preview.hasSuffix("...")
            )
        }
        return .success(
            AgentKernelFileSearchOutputV2(
                summary: AgentKernelBoundedTextV2("Found \(context.snippets.count) local file snippet(s)."),
                snippets: context.snippets.map(AgentKernelFileSnippetV2.init),
                sources: grantSources + snippetSources,
                isTruncated: context.snippets.contains { $0.preview.hasPrefix("...") || $0.preview.hasSuffix("...") }
            )
        )
    }

    nonisolated func readFile(
        path: String,
        grants: [LocalFileGrant]
    ) -> Result<AgentKernelFileReadOutputV2, AgentKernelTerminalReasonV2> {
        switch resolvedGrantedURL(for: path, grants: grants) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let url):
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return .failure(reason(code: "file_not_found", summary: "The requested file does not exist.", path: url.path))
            }
            guard !isDirectory.boolValue else {
                return .failure(reason(code: "not_a_file", summary: "The requested path is a folder, not a file.", path: url.path))
            }
            let size = fileSize(url) ?? 0
            guard size <= maxReadFileBytes else {
                return .failure(
                    reason(
                        code: "file_too_large",
                        summary: "The requested file exceeds the configured read limit.",
                        path: url.path,
                        metadata: ["byteCount": .int(size), "limit": .int(maxReadFileBytes)]
                    )
                )
            }
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), !data.contains(0) else {
                return .failure(reason(code: "file_not_text", summary: "The requested file is not readable as text.", path: url.path))
            }
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii)
                ?? String(decoding: data, as: UTF8.self)
            let bounded = AgentKernelBoundedTextV2(text, characterLimit: maxReadCharacters)
            return .success(
                AgentKernelFileReadOutputV2(
                    summary: AgentKernelBoundedTextV2("Read \(url.path)."),
                    path: url.path,
                    content: bounded,
                    byteCount: data.count,
                    sources: [
                        AgentKernelToolSourceRecordV2(
                            id: "file:\(url.path)",
                            kind: "file",
                            path: url.path,
                            displayName: url.lastPathComponent,
                            summary: AgentKernelBoundedTextV2("Granted local text file."),
                            isTruncated: bounded.isTruncated,
                            metadata: ["byteCount": .int(data.count)]
                        )
                    ]
                )
            )
        }
    }

    nonisolated func stageWriteProposal(
        operation: String,
        targetPath: String,
        content: String,
        grants: [LocalFileGrant],
        preferredDirectoryPath: String? = nil,
        recentTargetPaths: [String] = []
    ) -> Result<AgentKernelWriteProposalOutputV2, AgentKernelTerminalReasonV2> {
        guard let parsedOperation = AssistantGeneratedWriteDraft.Operation(rawValue: operation) else {
            return .failure(
                reason(
                    code: "unsupported_write_operation",
                    summary: "Write operation must be create, replace, or append.",
                    metadata: ["operation": .string(operation)]
                )
            )
        }

        let draft = AssistantGeneratedWriteDraft(
            operation: parsedOperation,
            targetPath: targetPath,
            content: content
        )
        switch writeProposalParser.proposal(
            from: draft,
            grants: grants,
            preferredDirectoryPath: preferredDirectoryPath,
            recentTargetPaths: recentTargetPaths
        ) {
        case .proposal(let proposal):
            return .success(
                AgentKernelWriteProposalOutputV2(
                    summary: AgentKernelBoundedTextV2(proposal.detailText),
                    proposal: proposal,
                    requiresApproval: true,
                    sources: [
                        AgentKernelToolSourceRecordV2(
                            id: "write-proposal:\(proposal.targetPath)",
                            kind: "write_proposal",
                            path: proposal.targetPath,
                            displayName: URL(fileURLWithPath: proposal.targetPath).lastPathComponent,
                            summary: AgentKernelBoundedTextV2("Staged local write proposal. No file was written."),
                            metadata: ["action": .string(proposal.actionLabel)]
                        )
                    ]
                )
            )
        case .message(let message):
            return .failure(reason(code: "write_proposal_rejected", summary: message))
        case .none:
            return .failure(reason(code: "write_proposal_empty", summary: "No write proposal was produced."))
        }
    }

    nonisolated func describeVisualContext(
        state: AssistantVisualContextState?
    ) -> Result<AgentKernelVisualContextOutputV2, AgentKernelTerminalReasonV2> {
        guard let state else {
            return .failure(
                reason(
                    code: "visual_context_unavailable",
                    summary: "No active visual context is available."
                )
            )
        }

        let sourceID = "visual:\(state.source.rawValue):\(state.label)"
        return .success(
            AgentKernelVisualContextOutputV2(
                summary: AgentKernelBoundedTextV2("Active visual context: \(state.label)."),
                source: state.source.rawValue,
                label: state.label,
                hasTransientImageInput: state.hasImageInput,
                hasOCRText: state.hasOCRText,
                ocrExcerpt: state.ocrExcerpt.map { AgentKernelBoundedTextV2($0, characterLimit: 1_600) },
                imagePixelsPersisted: false,
                sources: [
                    AgentKernelToolSourceRecordV2(
                        id: sourceID,
                        kind: "visual_context",
                        displayName: state.label,
                        summary: AgentKernelBoundedTextV2("Transient visual context metadata and OCR excerpt."),
                        isTruncated: state.ocrExcerpt?.hasSuffix("...") ?? false,
                        metadata: [
                            "source": .string(state.source.rawValue),
                            "hasImageInput": .bool(state.hasImageInput),
                            "hasOCRText": .bool(state.hasOCRText),
                            "imagePixelsPersisted": .bool(false)
                        ]
                    )
                ]
            )
        )
    }

    private nonisolated func activeGrants(from grants: [LocalFileGrant]) -> [LocalFileGrant] {
        grants
            .filter { fileManager.fileExists(atPath: $0.path) }
            .sorted { lhs, rhs in
                lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            }
    }

    private nonisolated func resolvedGrantedURL(
        for requestedPath: String,
        grants: [LocalFileGrant]
    ) -> Result<URL, AgentKernelTerminalReasonV2> {
        let activeGrants = activeGrants(from: grants)
        guard !activeGrants.isEmpty else {
            return .failure(
                reason(
                    code: "no_file_grants",
                    summary: "No active local file or folder grants are available."
                )
            )
        }

        let cleanedPath = requestedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPath.isEmpty else {
            return .failure(reason(code: "empty_path", summary: "Path cannot be empty."))
        }

        let candidate: URL?
        if cleanedPath.hasPrefix("/") {
            candidate = URL(fileURLWithPath: cleanedPath).standardizedFileURL
        } else if let matchingGrant = activeGrants.first(where: {
            $0.displayName.localizedCaseInsensitiveCompare(cleanedPath) == .orderedSame
                || $0.path.localizedCaseInsensitiveCompare(cleanedPath) == .orderedSame
        }) {
            candidate = matchingGrant.url.standardizedFileURL
        } else {
            candidate = activeGrants
                .filter(\.isDirectory)
                .map { $0.url.appendingPathComponent(cleanedPath).standardizedFileURL }
                .first { isAllowed($0, grants: activeGrants) }
        }

        guard let candidate else {
            return .failure(
                reason(
                    code: "path_not_granted",
                    summary: "The requested path is outside the active local file grants.",
                    path: cleanedPath
                )
            )
        }
        guard isAllowed(candidate, grants: activeGrants) else {
            return .failure(
                reason(
                    code: "path_not_granted",
                    summary: "The requested path is outside the active local file grants.",
                    path: candidate.path
                )
            )
        }
        return .success(candidate)
    }

    private nonisolated func isAllowed(_ candidate: URL, grants: [LocalFileGrant]) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        for grant in grants {
            let grantURL = grant.url.standardizedFileURL
            let grantPath = grantURL.path
            if grant.isDirectory {
                let root = grantPath.hasSuffix("/") ? grantPath : grantPath + "/"
                if candidatePath == grantPath || candidatePath.hasPrefix(root) {
                    return true
                }
            } else if candidatePath == grantPath {
                return true
            }
        }
        return false
    }

    private nonisolated func sourceRecord(for grant: LocalFileGrant) -> AgentKernelToolSourceRecordV2 {
        AgentKernelToolSourceRecordV2(
            id: "grant:\(grant.id.uuidString)",
            kind: grant.isDirectory ? "folder_grant" : "file_grant",
            path: grant.url.standardizedFileURL.path,
            displayName: grant.displayName,
            summary: AgentKernelBoundedTextV2("User-granted local \(grant.kindLabel.lowercased()).")
        )
    }

    private nonisolated func fileSize(_ url: URL) -> Int? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize
    }

    private nonisolated func reason(
        code: String,
        summary: String,
        path: String? = nil,
        metadata: [String: AgentKernelMetadataValueV2] = [:]
    ) -> AgentKernelTerminalReasonV2 {
        var nextMetadata = metadata
        if let path {
            nextMetadata["path"] = .string(path)
        }
        return AgentKernelTerminalReasonV2(
            code: code,
            summary: AgentKernelBoundedTextV2(summary),
            metadata: nextMetadata
        )
    }
}
