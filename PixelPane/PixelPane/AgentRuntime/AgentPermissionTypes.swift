//
//  AgentPermissionTypes.swift
//  PixelPane
//
//  Permission modes, scopes, operation kinds, risk, reasons, grants, approval/sensitive rules, and permission request/decision value types.
//

import Foundation

nonisolated enum AgentRunPermissionMode: String, Codable, Equatable, Sendable {
    case plainChat
    case readOnly
    case proposalOnly
    case fullAgent
}

nonisolated enum AgentPermissionDecisionKind: String, Codable, Equatable, Sendable {
    case allow
    case ask
    case deny
}

nonisolated enum AgentPermissionScope: String, Codable, Equatable, Sendable {
    case fileRead
    case fileWrite
    case visualContext
    case workingDirectory
    case network
    case processControl
    case localServer
    case privileged
}

nonisolated enum AgentToolOperationKind: String, Codable, Equatable, Hashable, Sendable {
    case fileGrantList
    case fileList
    case fileSearch
    case fileRead
    case fileWriteDraft
    case visualContext
    case finiteCommand
    case processSnapshot
    case processStart
    case processStatus
    case processStop
    case processOutput
    case localServerProbe
    case localServerDiscovery
    case custom
}

nonisolated enum AgentToolRisk: String, Codable, Equatable, Sendable {
    case readOnly
    case localRead
    case localWriteDraft
    case command
    case network
    case processControl
    case privileged
}

nonisolated enum AgentPermissionReason: String, Codable, Equatable, Sendable {
    case allowed
    case approvalGrantMatched
    case unknownTool
    case providerTierDisallowsTool
    case runModeDisallowsTool
    case unsupportedOperation
    case missingRequiredArgument
    case malformedArgument
    case deniedScope
    case missingFileGrant
    // Legacy persisted value from the old read-only/read-write grant split. New policy emits missingFileGrant.
    case missingWriteGrant
    case sensitivePathDenied
    case approvalRequired
    case rawShellRequiresApproval
    case fileMutationRequiresApproval
    case installRequiresApproval
    case networkRequiresApproval
    case processControlRequiresApproval
    case privilegedCommandRequiresApproval
    case unsafeCommandDenied
}

nonisolated struct AgentLocalFileGrant: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let path: String
    let isDirectory: Bool

    init(
        id: UUID = UUID(),
        path: String,
        isDirectory: Bool
    ) {
        self.id = id
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.isDirectory = isDirectory
    }

    var url: URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    func allowsRead(_ candidatePath: String) -> Bool {
        allows(candidatePath)
    }

    func allowsWrite(_ candidatePath: String) -> Bool {
        allows(candidatePath)
    }

    private func allows(_ candidatePath: String) -> Bool {
        let candidate = URL(fileURLWithPath: candidatePath).standardizedFileURL.path
        if isDirectory {
            let root = path.hasSuffix("/") ? path : path + "/"
            return candidate == path || candidate.hasPrefix(root)
        }
        return candidate == path
    }
}

nonisolated struct AgentPermissionApprovalGrant: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let toolName: String
    let argumentDigest: String
    let expiresAt: Date?

    init(
        id: UUID = UUID(),
        toolName: String,
        argumentDigest: String,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.argumentDigest = argumentDigest
        self.expiresAt = expiresAt
    }

    func matches(toolName: String, argumentDigest: String, now: Date) -> Bool {
        self.toolName == toolName
            && self.argumentDigest == argumentDigest
            && (expiresAt.map { $0 >= now } ?? true)
    }
}

nonisolated struct AgentSensitivePathRule: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let exactFilenames: [String]
    let filenameSuffixes: [String]
    let pathComponents: [String]
    let substrings: [String]
    let summary: AgentRunText

    init(
        id: String,
        exactFilenames: [String] = [],
        filenameSuffixes: [String] = [],
        pathComponents: [String] = [],
        substrings: [String] = [],
        summary: AgentRunText
    ) {
        self.id = id
        self.exactFilenames = exactFilenames.map { $0.lowercased() }
        self.filenameSuffixes = filenameSuffixes.map { $0.lowercased() }
        self.pathComponents = pathComponents.map { $0.lowercased() }
        self.substrings = substrings.map { $0.lowercased() }
        self.summary = summary
    }

    func matches(_ rawValue: String) -> Bool {
        let lowercased = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return false }

        if substrings.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let components = lowercased
            .split { character in
                character == "/" || character == "\\" || character == " " || character == "\t" || character == "\n"
            }
            .map(String.init)
        if components.contains(where: { exactFilenames.contains($0) }) {
            return true
        }
        if components.contains(where: { component in filenameSuffixes.contains { component.hasSuffix($0) } }) {
            return true
        }
        return components.contains(where: { pathComponents.contains($0) })
    }
}

nonisolated struct AgentPermissionRequest: Codable, Equatable, Sendable {
    let runMode: AgentRunPermissionMode
    let providerTier: AgentModelCapabilityTier
    let toolName: String
    let arguments: [String: String]
    let localGrants: [AgentLocalFileGrant]
    let grantedScopes: [AgentPermissionScope]
    let deniedScopes: [AgentPermissionScope]
    let supportedOperations: Set<AgentToolOperationKind>
    let approvalGrants: [AgentPermissionApprovalGrant]
    let now: Date

    init(
        runMode: AgentRunPermissionMode,
        providerTier: AgentModelCapabilityTier,
        toolName: String,
        arguments: [String: String] = [:],
        localGrants: [AgentLocalFileGrant] = [],
        grantedScopes: [AgentPermissionScope] = [],
        deniedScopes: [AgentPermissionScope] = [],
        supportedOperations: Set<AgentToolOperationKind> = AgentToolExecutionCapabilities.activeLocalRuntimeOperations,
        approvalGrants: [AgentPermissionApprovalGrant] = [],
        now: Date = Date()
    ) {
        self.runMode = runMode
        self.providerTier = providerTier
        self.toolName = toolName
        self.arguments = arguments
        self.localGrants = localGrants
        self.grantedScopes = grantedScopes
        self.deniedScopes = deniedScopes
        self.supportedOperations = supportedOperations
        self.approvalGrants = approvalGrants
        self.now = now
    }

    func replacingArguments(_ arguments: [String: String]) -> AgentPermissionRequest {
        AgentPermissionRequest(
            runMode: runMode,
            providerTier: providerTier,
            toolName: toolName,
            arguments: arguments,
            localGrants: localGrants,
            grantedScopes: grantedScopes,
            deniedScopes: deniedScopes,
            supportedOperations: supportedOperations,
            approvalGrants: approvalGrants,
            now: now
        )
    }
}

nonisolated struct AgentPermissionDecision: Codable, Equatable, Sendable {
    let kind: AgentPermissionDecisionKind
    let reason: AgentPermissionReason
    let summary: AgentRunText
    let toolName: String
    let risk: AgentToolRisk?
    let metadata: [String: AgentRunMetadataValue]

    init(
        kind: AgentPermissionDecisionKind,
        reason: AgentPermissionReason,
        summary: AgentRunText,
        toolName: String,
        risk: AgentToolRisk? = nil,
        metadata: [String: AgentRunMetadataValue] = [:]
    ) {
        self.kind = kind
        self.reason = reason
        self.summary = summary
        self.toolName = toolName
        self.risk = risk
        self.metadata = metadata
    }

    var isAllowed: Bool {
        kind == .allow
    }
}

