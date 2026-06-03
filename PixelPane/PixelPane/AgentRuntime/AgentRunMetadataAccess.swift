//
//  AgentRunMetadataAccess.swift
//  PixelPane
//
//  Shared typed accessors for agent metadata values and evidence-record
//  metadata. These were previously duplicated as file-private extensions
//  across the runtime; they now live here as one module-internal source.
//

import Foundation

extension AgentRunMetadataValue {
    nonisolated var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    nonisolated var intValue: Int? {
        guard case .int(let value) = self else { return nil }
        return value
    }

    nonisolated var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

extension AgentKernelMetadataValue {
    nonisolated var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    nonisolated var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

extension AgentRunEvidenceRecord {
    nonisolated func stringMetadata(_ key: String) -> String? {
        guard case .string(let value) = metadata[key] else { return nil }
        return value
    }

    nonisolated func intMetadata(_ key: String) -> Int? {
        metadata[key]?.intValue
    }

    nonisolated func boolMetadata(_ key: String) -> Bool? {
        metadata[key]?.boolValue
    }
}
