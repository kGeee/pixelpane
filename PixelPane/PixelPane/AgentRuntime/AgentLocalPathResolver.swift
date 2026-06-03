//
//  AgentLocalPathResolver.swift
//  PixelPane
//
//  Local path access/target intents, resolution result/failure types, and the AgentLocalPathResolver.
//

import Foundation

nonisolated enum AgentLocalPathAccessIntent: String, Equatable, Sendable {
    case read
    case write
}

nonisolated enum AgentLocalPathTargetIntent: Equatable, Sendable {
    case any
    case existingFile
    case existingDirectory
    case writeTarget(requiresExistingParent: Bool)
}

nonisolated enum AgentLocalPathResolutionFailureCode: String, Equatable, Sendable {
    case emptyPath
    case noMatchingGrant
    case ambiguousRelativePath
    case pathDoesNotExist
    case pathIsNotFile
    case pathIsNotDirectory
    case targetIsDirectory
    case parentDirectoryMissing
}

nonisolated struct AgentLocalPathResolutionFailure: Equatable, Sendable {
    let code: AgentLocalPathResolutionFailureCode
    let summary: AgentRunText
    let candidates: [String]
}

nonisolated struct AgentLocalPathResolution: Equatable, Sendable {
    let path: String
    let grant: AgentLocalFileGrant
    let source: String

    var url: URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }
}

nonisolated enum AgentLocalPathResolutionResult: Equatable, Sendable {
    case resolved(AgentLocalPathResolution)
    case failed(AgentLocalPathResolutionFailure)

    var resolution: AgentLocalPathResolution? {
        guard case .resolved(let resolution) = self else { return nil }
        return resolution
    }

    var failure: AgentLocalPathResolutionFailure? {
        guard case .failed(let failure) = self else { return nil }
        return failure
    }
}

nonisolated struct AgentLocalPathResolver: Sendable {
    private struct Candidate: Equatable {
        let path: String
        let grant: AgentLocalFileGrant
        let source: String
    }

    nonisolated init() {}

    nonisolated func resolve(
        _ rawPath: String,
        grants: [AgentLocalFileGrant],
        access: AgentLocalPathAccessIntent,
        target: AgentLocalPathTargetIntent = .any,
        preferredDirectoryPath: String? = nil
    ) -> AgentLocalPathResolutionResult {
        let cleaned = expandUserHome(rawPath.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !cleaned.isEmpty else {
            return failure(.emptyPath, "The local path is empty.")
        }

        guard !grants.isEmpty else {
            return failure(.noMatchingGrant, "No matching local file grant is available for this request.")
        }

        if cleaned.hasPrefix("/") {
            let candidatePath = URL(fileURLWithPath: cleaned).standardizedFileURL.path
            let candidates = grants.compactMap { grant -> Candidate? in
                isAllowed(candidatePath, by: grant, access: access)
                    ? Candidate(path: candidatePath, grant: grant, source: "absolute")
                    : nil
            }
            return select(candidates, rawPath: cleaned, access: access, target: target, allowsFallback: false)
        }

        for group in relativeCandidateGroups(
            cleaned,
            grants: grants,
            preferredDirectoryPath: preferredDirectoryPath
        ) {
            let result = select(group.candidates, rawPath: cleaned, access: access, target: target, allowsFallback: group.allowsFallback)
            switch result {
            case .resolved:
                return result
            case .failed(let resolutionFailure):
                if !group.allowsFallback || resolutionFailure.code == .ambiguousRelativePath {
                    return result
                }
            }
        }

        return failure(
            .noMatchingGrant,
            "The requested path is outside granted local file access.",
            candidates: []
        )
    }

    private nonisolated func expandUserHome(_ path: String) -> String {
        if path == "~" {
            return NSHomeDirectory()
        }
        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(String(path.dropFirst(2)))
                .standardizedFileURL
                .path
        }
        return path
    }

    private nonisolated func relativeCandidateGroups(
        _ cleaned: String,
        grants: [AgentLocalFileGrant],
        preferredDirectoryPath: String?
    ) -> [(candidates: [Candidate], allowsFallback: Bool)] {
        var groups: [(candidates: [Candidate], allowsFallback: Bool)] = []
        let directories = grants.filter(\.isDirectory)

        let exact = exactGrantReferenceCandidates(cleaned, grants: directories)
        if !exact.isEmpty {
            groups.append((unique(exact), false))
        }

        if let preferred = preferredDirectoryGrant(preferredDirectoryPath, grants: directories) {
            groups.append((unique([candidate(cleaned, in: preferred, source: "preferred-directory")]), false))
        }

        let fileGrantMatches = grants
            .filter { !$0.isDirectory }
            .compactMap { grant -> Candidate? in
                URL(fileURLWithPath: grant.path).lastPathComponent.localizedCaseInsensitiveCompare(cleaned) == .orderedSame
                    ? Candidate(path: grant.path, grant: grant, source: "file-grant-name")
                    : nil
            }
        if !fileGrantMatches.isEmpty {
            groups.append((unique(fileGrantMatches), false))
        }

        let existing = directories
            .map { candidate(cleaned, in: $0, source: "existing-relative") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !existing.isEmpty {
            groups.append((unique(existing), false))
        }

        let fallback = directories.map { candidate(cleaned, in: $0, source: "relative-fallback") }
        if !fallback.isEmpty {
            groups.append((unique(fallback), true))
        }

        return groups
    }

    private nonisolated func exactGrantReferenceCandidates(
        _ cleaned: String,
        grants: [AgentLocalFileGrant]
    ) -> [Candidate] {
        let parts = cleaned.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first else { return [] }
        let remainder = parts.dropFirst().joined(separator: "/")
        return grants.compactMap { grant in
            guard grant.url.lastPathComponent.localizedCaseInsensitiveCompare(first) == .orderedSame else {
                return nil
            }
            let path = remainder.isEmpty
                ? grant.path
                : grant.url.appendingPathComponent(remainder).standardizedFileURL.path
            return Candidate(path: path, grant: grant, source: "grant-name")
        }
    }

    private nonisolated func preferredDirectoryGrant(
        _ preferredDirectoryPath: String?,
        grants: [AgentLocalFileGrant]
    ) -> AgentLocalFileGrant? {
        guard let preferredDirectoryPath else { return nil }
        let preferredPath = URL(fileURLWithPath: preferredDirectoryPath).standardizedFileURL.path
        return grants.first { grant in
            grant.isDirectory && grant.path == preferredPath
        }
    }

    private nonisolated func candidate(
        _ cleaned: String,
        in grant: AgentLocalFileGrant,
        source: String
    ) -> Candidate {
        Candidate(
            path: grant.url.appendingPathComponent(cleaned).standardizedFileURL.path,
            grant: grant,
            source: source
        )
    }

    private nonisolated func select(
        _ rawCandidates: [Candidate],
        rawPath: String,
        access: AgentLocalPathAccessIntent,
        target: AgentLocalPathTargetIntent,
        allowsFallback: Bool
    ) -> AgentLocalPathResolutionResult {
        let candidates = unique(rawCandidates)
        guard !candidates.isEmpty else {
            return failure(.noMatchingGrant, "The requested path is outside granted local file access.")
        }

        var resolved: [AgentLocalPathResolution] = []
        var failures: [AgentLocalPathResolutionFailure] = []

        for candidate in candidates {
            guard isAllowed(candidate.path, by: candidate.grant, access: access) else {
                failures.append(
                    AgentLocalPathResolutionFailure(
                        code: .noMatchingGrant,
                        summary: AgentRunText("The requested path escapes its granted local folder: \(candidate.path)"),
                        candidates: [candidate.path]
                    )
                )
                continue
            }
            switch validate(candidate, target: target) {
            case .resolved(let resolution):
                resolved.append(resolution)
            case .failed(let failure):
                failures.append(failure)
            }
        }

        if resolved.count == 1, let value = resolved.first {
            return .resolved(value)
        }
        if resolved.count > 1 {
            let paths = resolved.map(\.path).sorted()
            return failure(
                .ambiguousRelativePath,
                "The relative path matches multiple granted locations. Name the exact granted folder.",
                candidates: paths
            )
        }
        if let failure = failures.first, !allowsFallback || failures.count == candidates.count {
            return .failed(failure)
        }
        return failure(.noMatchingGrant, "The requested path is outside granted local file access.")
    }

    private nonisolated func validate(
        _ candidate: Candidate,
        target: AgentLocalPathTargetIntent
    ) -> AgentLocalPathResolutionResult {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)

        switch target {
        case .any:
            return .resolved(resolution(from: candidate))
        case .existingFile:
            guard exists else {
                return failure(.pathDoesNotExist, "The requested file does not exist: \(candidate.path)", candidates: [candidate.path])
            }
            guard !isDirectory.boolValue else {
                return failure(.pathIsNotFile, "The requested path is a folder, not a file: \(candidate.path)", candidates: [candidate.path])
            }
            return .resolved(resolution(from: candidate))
        case .existingDirectory:
            guard exists else {
                return failure(.pathDoesNotExist, "The requested folder does not exist: \(candidate.path)", candidates: [candidate.path])
            }
            guard isDirectory.boolValue else {
                return failure(.pathIsNotDirectory, "The requested path is not a folder: \(candidate.path)", candidates: [candidate.path])
            }
            return .resolved(resolution(from: candidate))
        case .writeTarget(let requiresExistingParent):
            guard !exists || !isDirectory.boolValue else {
                return failure(.targetIsDirectory, "The write target is a folder, not a file: \(candidate.path)", candidates: [candidate.path])
            }
            if requiresExistingParent {
                let parent = URL(fileURLWithPath: candidate.path).deletingLastPathComponent().standardizedFileURL.path
                var parentIsDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: parent, isDirectory: &parentIsDirectory),
                      parentIsDirectory.boolValue else {
                    return failure(.parentDirectoryMissing, "The write target parent directory does not exist: \(parent)", candidates: [candidate.path])
                }
            }
            return .resolved(resolution(from: candidate))
        }
    }

    private nonisolated func resolution(from candidate: Candidate) -> AgentLocalPathResolution {
        AgentLocalPathResolution(path: candidate.path, grant: candidate.grant, source: candidate.source)
    }

    private nonisolated func isAllowed(
        _ candidatePath: String,
        by grant: AgentLocalFileGrant,
        access: AgentLocalPathAccessIntent
    ) -> Bool {
        access == .write ? grant.allowsWrite(candidatePath) : grant.allowsRead(candidatePath)
    }

    private nonisolated func unique(_ candidates: [Candidate]) -> [Candidate] {
        var seen = Set<String>()
        var result: [Candidate] = []
        for candidate in candidates {
            let key = "\(candidate.path)|\(candidate.grant.path)|\(candidate.source)"
            guard seen.insert(key).inserted else { continue }
            result.append(candidate)
        }
        return result
    }

    private nonisolated func failure(
        _ code: AgentLocalPathResolutionFailureCode,
        _ summary: String,
        candidates: [String] = []
    ) -> AgentLocalPathResolutionResult {
        .failed(
            AgentLocalPathResolutionFailure(
                code: code,
                summary: AgentRunText(summary),
                candidates: candidates
            )
        )
    }
}

