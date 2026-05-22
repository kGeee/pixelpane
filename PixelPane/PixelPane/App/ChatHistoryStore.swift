import Combine
import Foundation

enum ChatSessionContextKind: String, Codable, Sendable {
    case assistant
    case capture

    var displayName: String {
        switch self {
        case .assistant:
            "Chat"
        case .capture:
            "Screen region"
        }
    }
}

struct StoredChatTurn: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let question: String
    let answer: String
    let backendLabel: String
    let createdAt: Date
}

struct StoredChatSession: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var contextID: String
    var contextKind: ChatSessionContextKind
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var turns: [StoredChatTurn]

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? contextKind.displayName : trimmed
    }
}

@MainActor
final class ChatHistoryStore: ObservableObject {
    @Published private(set) var sessions: [StoredChatSession]

    private let userDefaults: UserDefaults
    private let key = "ChatHistoryStore.Sessions"
    private let maxSessions = 60
    private let maxTurnsPerSession = 80

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([StoredChatSession].self, from: data) {
            sessions = decoded.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            sessions = []
        }
    }

    func session(contextID: String, kind: ChatSessionContextKind) -> StoredChatSession? {
        sessions.first { $0.contextID == contextID && $0.contextKind == kind }
    }

    func latestAssistantSession() -> StoredChatSession? {
        sessions
            .filter { $0.contextKind == .assistant && !$0.turns.isEmpty }
            .max { $0.updatedAt < $1.updatedAt }
    }

    func recentSessions(limit: Int = 8) -> [StoredChatSession] {
        Array(sessions.filter { !$0.turns.isEmpty }.prefix(limit))
    }

    @discardableResult
    func upsertSession(
        contextID: String,
        kind: ChatSessionContextKind,
        title: String,
        turns: [StoredChatTurn]
    ) -> StoredChatSession {
        let now = Date()
        let limitedTurns = Array(turns.suffix(maxTurnsPerSession))
        let resolvedTitle = Self.title(from: limitedTurns) ?? title

        if let index = sessions.firstIndex(where: { $0.contextID == contextID && $0.contextKind == kind }) {
            sessions[index].title = resolvedTitle
            sessions[index].turns = limitedTurns
            sessions[index].updatedAt = now
            let session = sessions.remove(at: index)
            sessions.insert(session, at: 0)
        } else {
            sessions.insert(
                StoredChatSession(
                    id: UUID(),
                    contextID: contextID,
                    contextKind: kind,
                    title: resolvedTitle,
                    createdAt: now,
                    updatedAt: now,
                    turns: limitedTurns
                ),
                at: 0
            )
        }

        sessions = Array(sessions.prefix(maxSessions))
        persist()
        return sessions[0]
    }

    func deleteSession(_ session: StoredChatSession) {
        sessions.removeAll { $0.id == session.id }
        persist()
    }

    func clearAll() {
        sessions = []
        userDefaults.removeObject(forKey: key)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) {
            userDefaults.set(data, forKey: key)
        }
    }

    private static func title(from turns: [StoredChatTurn]) -> String? {
        guard let firstQuestion = turns.first?.question.trimmingCharacters(in: .whitespacesAndNewlines),
              !firstQuestion.isEmpty else {
            return nil
        }
        if firstQuestion.count <= 42 {
            return firstQuestion
        }
        let end = firstQuestion.index(firstQuestion.startIndex, offsetBy: 42)
        return String(firstQuestion[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
