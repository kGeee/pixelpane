import Foundation
import SQLite3

nonisolated protocol AgentRunStorePersistenceBackend: AnyObject {
    var databaseURL: URL { get }

    func hasStoredSnapshot() throws -> Bool
    func loadSnapshot() throws -> AgentRunStoreSnapshot
    func saveSnapshot(_ snapshot: AgentRunStoreSnapshot) throws
    func clearSnapshot() throws
}

nonisolated final class AgentRunSQLitePersistenceBackend: AgentRunStorePersistenceBackend {
    static let databaseFileName = "store.sqlite3"
    static let sqliteSchemaVersion = 2

    let databaseURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootDirectory: URL) throws {
        databaseURL = rootDirectory.appendingPathComponent(Self.databaseFileName, isDirectory: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        decoder = JSONDecoder()

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try withDatabase { database in
            try configure(database)
            try createSchema(database)
        }
    }

    func hasStoredSnapshot() throws -> Bool {
        try withDatabase { database in
            try configure(database)
            let metadataCount = try scalarInt("SELECT COUNT(*) FROM store_metadata WHERE key = 'schema_version';", database: database)
            if metadataCount > 0 {
                return true
            }
            for table in Self.recordTableNames {
                if try scalarInt("SELECT COUNT(*) FROM \(table);", database: database) > 0 {
                    return true
                }
            }
            return false
        }
    }

    func loadSnapshot() throws -> AgentRunStoreSnapshot {
        try withDatabase { database in
            try configure(database)
            try createSchema(database)

            let schemaVersion = try metadataInt("schema_version", database: database)
                ?? sqliteUserVersion(database: database)
                ?? AgentRunStoreSchema.currentVersion

            return AgentRunStoreSnapshot(
                schemaVersion: schemaVersion,
                sessions: try loadRecords(
                    AgentRunSessionRecord.self,
                    sql: "SELECT record_json FROM sessions ORDER BY created_at ASC, session_id ASC;",
                    database: database
                ),
                runs: try loadRecords(
                    AgentRunRecord.self,
                    sql: "SELECT record_json FROM runs ORDER BY created_at ASC, run_id ASC;",
                    database: database
                ),
                steps: try loadRecords(
                    AgentRunStepRecord.self,
                    sql: "SELECT record_json FROM steps ORDER BY created_at ASC, step_id ASC;",
                    database: database
                ),
                waits: try loadRecords(
                    AgentRunWaitRecord.self,
                    sql: "SELECT record_json FROM waits ORDER BY created_at ASC, wait_id ASC;",
                    database: database
                ),
                artifacts: try loadRecords(
                    AgentRunArtifactRecord.self,
                    sql: "SELECT record_json FROM artifacts ORDER BY created_at ASC, artifact_id ASC;",
                    database: database
                ),
                evidence: try loadRecords(
                    AgentRunEvidenceRecord.self,
                    sql: "SELECT record_json FROM evidence ORDER BY created_at ASC, evidence_id ASC;",
                    database: database
                ),
                sideEffects: try loadRecords(
                    AgentRunSideEffectRecord.self,
                    sql: "SELECT record_json FROM side_effects ORDER BY created_at ASC, side_effect_id ASC;",
                    database: database
                ),
                controlRecords: try loadRecords(
                    AgentRunControlRecord.self,
                    sql: "SELECT record_json FROM control_records ORDER BY created_at ASC, run_id ASC, sequence ASC;",
                    database: database
                ),
                events: try loadRecords(
                    AgentRunEventRecord.self,
                    sql: "SELECT record_json FROM events ORDER BY created_at ASC, run_id ASC, sequence ASC;",
                    database: database
                )
            )
        }
    }

    func saveSnapshot(_ snapshot: AgentRunStoreSnapshot) throws {
        try withDatabase { database in
            try configure(database)
            try createSchema(database)
            try execute("BEGIN IMMEDIATE TRANSACTION;", database: database)
            do {
                try deleteExistingRecords(database)
                try execute("PRAGMA user_version = \(Self.sqliteSchemaVersion);", database: database)
                try insertMetadata(key: "sqlite_schema_version", value: "\(Self.sqliteSchemaVersion)", database: database)
                try insertMetadata(key: "schema_version", value: "\(snapshot.schemaVersion)", database: database)

                try insertSessions(snapshot.sessions, database: database)
                try insertRuns(snapshot.runs, database: database)
                try insertSteps(snapshot.steps, database: database)
                try insertWaits(snapshot.waits, database: database)
                try insertArtifacts(snapshot.artifacts, database: database)
                try insertEvidence(snapshot.evidence, database: database)
                try insertSideEffects(snapshot.sideEffects, database: database)
                try insertControlRecords(snapshot.controlRecords, database: database)
                try insertEvents(snapshot.events, database: database)

                try execute("COMMIT;", database: database)
            } catch {
                try? execute("ROLLBACK;", database: database)
                throw error
            }
        }
    }

    func clearSnapshot() throws {
        try saveSnapshot(AgentRunStoreSnapshot())
    }

    private static let recordTableNames = [
        "sessions",
        "runs",
        "steps",
        "waits",
        "artifacts",
        "evidence",
        "side_effects",
        "control_records",
        "events"
    ]

    private func configure(_ database: OpaquePointer) throws {
        try execute("PRAGMA foreign_keys = ON;", database: database)
        try execute("PRAGMA journal_mode = WAL;", database: database)
        try execute("PRAGMA synchronous = NORMAL;", database: database)
    }

    private func createSchema(_ database: OpaquePointer) throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS store_metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS sessions (
                session_id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                context_id TEXT,
                context_kind TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                record_json TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS runs (
                run_id TEXT PRIMARY KEY NOT NULL,
                session_id TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                last_sequence INTEGER NOT NULL,
                active_step_id TEXT,
                record_json TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS steps (
                step_id TEXT PRIMARY KEY NOT NULL,
                session_id TEXT NOT NULL,
                run_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                record_json TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
                FOREIGN KEY(run_id) REFERENCES runs(run_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS waits (
                wait_id TEXT PRIMARY KEY NOT NULL,
                session_id TEXT NOT NULL,
                run_id TEXT NOT NULL,
                step_id TEXT,
                kind TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at REAL NOT NULL,
                resolved_at REAL,
                record_json TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
                FOREIGN KEY(run_id) REFERENCES runs(run_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS artifacts (
                artifact_id TEXT PRIMARY KEY NOT NULL,
                session_id TEXT NOT NULL,
                run_id TEXT NOT NULL,
                step_id TEXT,
                kind TEXT NOT NULL,
                mime_type TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                byte_count INTEGER NOT NULL,
                created_at REAL NOT NULL,
                record_json TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
                FOREIGN KEY(run_id) REFERENCES runs(run_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS evidence (
                evidence_id TEXT PRIMARY KEY NOT NULL,
                session_id TEXT NOT NULL,
                run_id TEXT NOT NULL,
                step_id TEXT,
                source_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                artifact_id TEXT,
                created_at REAL NOT NULL,
                record_json TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
                FOREIGN KEY(run_id) REFERENCES runs(run_id) ON DELETE CASCADE,
                FOREIGN KEY(artifact_id) REFERENCES artifacts(artifact_id) ON DELETE SET NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS side_effects (
                side_effect_id TEXT PRIMARY KEY NOT NULL,
                session_id TEXT NOT NULL,
                run_id TEXT NOT NULL,
                step_id TEXT,
                kind TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                record_json TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
                FOREIGN KEY(run_id) REFERENCES runs(run_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS control_records (
                control_record_id TEXT PRIMARY KEY NOT NULL,
                session_id TEXT NOT NULL,
                run_id TEXT NOT NULL,
                step_id TEXT,
                sequence INTEGER NOT NULL,
                kind TEXT NOT NULL,
                created_at REAL NOT NULL,
                payload_json TEXT NOT NULL,
                record_json TEXT NOT NULL,
                UNIQUE(run_id, sequence),
                FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
                FOREIGN KEY(run_id) REFERENCES runs(run_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS events (
                event_id TEXT PRIMARY KEY NOT NULL,
                session_id TEXT NOT NULL,
                run_id TEXT NOT NULL,
                step_id TEXT,
                sequence INTEGER NOT NULL,
                kind TEXT NOT NULL,
                created_at REAL NOT NULL,
                payload_json TEXT NOT NULL,
                record_json TEXT NOT NULL,
                UNIQUE(run_id, sequence),
                FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
                FOREIGN KEY(run_id) REFERENCES runs(run_id) ON DELETE CASCADE
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_runs_session_updated ON runs(session_id, updated_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_runs_status_updated ON runs(status, updated_at ASC);",
            "CREATE INDEX IF NOT EXISTS idx_steps_run_created ON steps(run_id, created_at ASC);",
            "CREATE INDEX IF NOT EXISTS idx_waits_run_status ON waits(run_id, status, created_at ASC);",
            "CREATE INDEX IF NOT EXISTS idx_artifacts_run_created ON artifacts(run_id, created_at ASC);",
            "CREATE INDEX IF NOT EXISTS idx_evidence_run_kind ON evidence(run_id, kind, created_at ASC);",
            "CREATE INDEX IF NOT EXISTS idx_side_effects_run_created ON side_effects(run_id, created_at ASC);",
            "CREATE INDEX IF NOT EXISTS idx_control_records_run_sequence ON control_records(run_id, sequence ASC);",
            "CREATE INDEX IF NOT EXISTS idx_control_records_run_kind ON control_records(run_id, kind, created_at ASC);",
            "CREATE INDEX IF NOT EXISTS idx_events_run_sequence ON events(run_id, sequence ASC);",
            "CREATE INDEX IF NOT EXISTS idx_events_session_created ON events(session_id, created_at ASC);"
        ]

        for statement in statements {
            try execute(statement, database: database)
        }
    }

    private func deleteExistingRecords(_ database: OpaquePointer) throws {
        for table in Self.recordTableNames.reversed() {
            try execute("DELETE FROM \(table);", database: database)
        }
        try execute("DELETE FROM store_metadata;", database: database)
    }

    private func insertMetadata(key: String, value: String, database: OpaquePointer) throws {
        let statement = try prepare(
            "INSERT INTO store_metadata(key, value) VALUES (?, ?);",
            database: database
        )
        defer { sqlite3_finalize(statement) }
        try bindText(key, at: 1, in: statement)
        try bindText(value, at: 2, in: statement)
        try stepDone(statement, database: database)
    }

    private func insertSessions(_ records: [AgentRunSessionRecord], database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO sessions(session_id, title, context_id, context_kind, created_at, updated_at, record_json)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(record.id.uuidString, at: 1, in: statement)
            try bindText(record.title, at: 2, in: statement)
            try bindText(record.contextID, at: 3, in: statement)
            try bindText(record.contextKind, at: 4, in: statement)
            try bindDate(record.createdAt, at: 5, in: statement)
            try bindDate(record.updatedAt, at: 6, in: statement)
            try bindJSON(record, at: 7, in: statement)
            try stepDone(statement, database: database)
        }
    }

    private func insertRuns(_ records: [AgentRunRecord], database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO runs(run_id, session_id, status, created_at, updated_at, last_sequence, active_step_id, record_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(record.runID.uuidString, at: 1, in: statement)
            try bindText(record.sessionID.uuidString, at: 2, in: statement)
            try bindText(record.status.rawValue, at: 3, in: statement)
            try bindDate(record.createdAt, at: 4, in: statement)
            try bindDate(record.updatedAt, at: 5, in: statement)
            try bindInt(record.lastSequence, at: 6, in: statement)
            try bindText(record.activeStepID?.uuidString, at: 7, in: statement)
            try bindJSON(record, at: 8, in: statement)
            try stepDone(statement, database: database)
        }
    }

    private func insertSteps(_ records: [AgentRunStepRecord], database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO steps(step_id, session_id, run_id, kind, status, created_at, updated_at, record_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(record.stepID.uuidString, at: 1, in: statement)
            try bindText(record.sessionID.uuidString, at: 2, in: statement)
            try bindText(record.runID.uuidString, at: 3, in: statement)
            try bindText(record.kind.rawValue, at: 4, in: statement)
            try bindText(record.status.rawValue, at: 5, in: statement)
            try bindDate(record.createdAt, at: 6, in: statement)
            try bindDate(record.updatedAt, at: 7, in: statement)
            try bindJSON(record, at: 8, in: statement)
            try stepDone(statement, database: database)
        }
    }

    private func insertWaits(_ records: [AgentRunWaitRecord], database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO waits(wait_id, session_id, run_id, step_id, kind, status, created_at, resolved_at, record_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(record.waitID.uuidString, at: 1, in: statement)
            try bindText(record.sessionID.uuidString, at: 2, in: statement)
            try bindText(record.runID.uuidString, at: 3, in: statement)
            try bindText(record.stepID?.uuidString, at: 4, in: statement)
            try bindText(record.kind.rawValue, at: 5, in: statement)
            try bindText(record.status.rawValue, at: 6, in: statement)
            try bindDate(record.createdAt, at: 7, in: statement)
            try bindDate(record.resolvedAt, at: 8, in: statement)
            try bindJSON(record, at: 9, in: statement)
            try stepDone(statement, database: database)
        }
    }

    private func insertArtifacts(_ records: [AgentRunArtifactRecord], database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO artifacts(artifact_id, session_id, run_id, step_id, kind, mime_type, relative_path, byte_count, created_at, record_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(record.artifactID.uuidString, at: 1, in: statement)
            try bindText(record.sessionID.uuidString, at: 2, in: statement)
            try bindText(record.runID.uuidString, at: 3, in: statement)
            try bindText(record.stepID?.uuidString, at: 4, in: statement)
            try bindText(record.kind, at: 5, in: statement)
            try bindText(record.mimeType, at: 6, in: statement)
            try bindText(record.relativePath, at: 7, in: statement)
            try bindInt(record.byteCount, at: 8, in: statement)
            try bindDate(record.createdAt, at: 9, in: statement)
            try bindJSON(record, at: 10, in: statement)
            try stepDone(statement, database: database)
        }
    }

    private func insertEvidence(_ records: [AgentRunEvidenceRecord], database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO evidence(evidence_id, session_id, run_id, step_id, source_id, kind, artifact_id, created_at, record_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(record.evidenceID.uuidString, at: 1, in: statement)
            try bindText(record.sessionID.uuidString, at: 2, in: statement)
            try bindText(record.runID.uuidString, at: 3, in: statement)
            try bindText(record.stepID?.uuidString, at: 4, in: statement)
            try bindText(record.sourceID, at: 5, in: statement)
            try bindText(record.kind, at: 6, in: statement)
            try bindText(record.artifactID?.uuidString, at: 7, in: statement)
            try bindDate(record.createdAt, at: 8, in: statement)
            try bindJSON(record, at: 9, in: statement)
            try stepDone(statement, database: database)
        }
    }

    private func insertSideEffects(_ records: [AgentRunSideEffectRecord], database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO side_effects(side_effect_id, session_id, run_id, step_id, kind, status, created_at, updated_at, record_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(record.sideEffectID.uuidString, at: 1, in: statement)
            try bindText(record.sessionID.uuidString, at: 2, in: statement)
            try bindText(record.runID.uuidString, at: 3, in: statement)
            try bindText(record.stepID?.uuidString, at: 4, in: statement)
            try bindText(record.kind.rawValue, at: 5, in: statement)
            try bindText(record.status.rawValue, at: 6, in: statement)
            try bindDate(record.createdAt, at: 7, in: statement)
            try bindDate(record.updatedAt, at: 8, in: statement)
            try bindJSON(record, at: 9, in: statement)
            try stepDone(statement, database: database)
        }
    }

    private func insertControlRecords(_ records: [AgentRunControlRecord], database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO control_records(control_record_id, session_id, run_id, step_id, sequence, kind, created_at, payload_json, record_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(record.recordID.uuidString, at: 1, in: statement)
            try bindText(record.sessionID.uuidString, at: 2, in: statement)
            try bindText(record.runID.uuidString, at: 3, in: statement)
            try bindText(record.stepID?.uuidString, at: 4, in: statement)
            try bindInt(record.sequence, at: 5, in: statement)
            try bindText(record.kind.rawValue, at: 6, in: statement)
            try bindDate(record.createdAt, at: 7, in: statement)
            try bindJSON(record.payload, at: 8, in: statement)
            try bindJSON(record, at: 9, in: statement)
            try stepDone(statement, database: database)
        }
    }

    private func insertEvents(_ records: [AgentRunEventRecord], database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO events(event_id, session_id, run_id, step_id, sequence, kind, created_at, payload_json, record_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        for record in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(record.eventID.uuidString, at: 1, in: statement)
            try bindText(record.sessionID.uuidString, at: 2, in: statement)
            try bindText(record.runID.uuidString, at: 3, in: statement)
            try bindText(record.stepID?.uuidString, at: 4, in: statement)
            try bindInt(record.sequence, at: 5, in: statement)
            try bindText(record.kind.rawValue, at: 6, in: statement)
            try bindDate(record.createdAt, at: 7, in: statement)
            try bindJSON(record.payload, at: 8, in: statement)
            try bindJSON(record, at: 9, in: statement)
            try stepDone(statement, database: database)
        }
    }

    private func loadRecords<T: Decodable>(
        _ type: T.Type,
        sql: String,
        database: OpaquePointer
    ) throws -> [T] {
        let statement = try prepare(sql, database: database)
        defer { sqlite3_finalize(statement) }

        var records: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                guard let text = sqlite3_column_text(statement, 0) else {
                    throw sqliteError("Missing SQLite record JSON.", database: database)
                }
                let string = String(cString: text)
                guard let data = string.data(using: .utf8) else {
                    throw AgentRunStoreError.persistence("Stored SQLite record JSON is not UTF-8.")
                }
                records.append(try decoder.decode(T.self, from: data))
            } else if result == SQLITE_DONE {
                return records
            } else {
                throw sqliteError("Failed to read SQLite records.", database: database)
            }
        }
    }

    private func metadataInt(_ key: String, database: OpaquePointer) throws -> Int? {
        let statement = try prepare("SELECT value FROM store_metadata WHERE key = ?;", database: database)
        defer { sqlite3_finalize(statement) }
        try bindText(key, at: 1, in: statement)

        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { return nil }
            return Int(String(cString: text))
        }
        if result == SQLITE_DONE {
            return nil
        }
        throw sqliteError("Failed to read SQLite metadata.", database: database)
    }

    private func sqliteUserVersion(database: OpaquePointer) throws -> Int? {
        let value = try scalarInt("PRAGMA user_version;", database: database)
        return value == 0 ? nil : value
    }

    private func scalarInt(_ sql: String, database: OpaquePointer) throws -> Int {
        let statement = try prepare(sql, database: database)
        defer { sqlite3_finalize(statement) }

        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, 0))
        }
        if result == SQLITE_DONE {
            return 0
        }
        throw sqliteError("Failed to read SQLite scalar.", database: database)
    }

    private func bindJSON<T: Encodable>(_ value: T, at index: Int32, in statement: OpaquePointer) throws {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw AgentRunStoreError.persistence("Encoded store record JSON is not UTF-8.")
        }
        try bindText(string, at: index, in: statement)
    }

    private func bindText(_ value: String?, at index: Int32, in statement: OpaquePointer) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else {
            throw AgentRunStoreError.persistence("Failed to bind SQLite text value.")
        }
    }

    private func bindDate(_ value: Date?, at index: Int32, in statement: OpaquePointer) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        guard sqlite3_bind_double(statement, index, value.timeIntervalSince1970) == SQLITE_OK else {
            throw AgentRunStoreError.persistence("Failed to bind SQLite date value.")
        }
    }

    private func bindInt(_ value: Int, at index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
            throw AgentRunStoreError.persistence("Failed to bind SQLite integer value.")
        }
    }

    private func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw sqliteError("Failed to prepare SQLite statement.", database: database)
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError("Failed to execute SQLite statement.", database: database)
        }
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite error."
            sqlite3_free(errorMessage)
            throw AgentRunStoreError.persistence(message)
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open SQLite database."
            if let database {
                sqlite3_close(database)
            }
            throw AgentRunStoreError.persistence(message)
        }
        defer { sqlite3_close(database) }
        return try body(database)
    }

    private func sqliteError(_ summary: String, database: OpaquePointer) -> AgentRunStoreError {
        let message = String(cString: sqlite3_errmsg(database))
        return .persistence("\(summary) \(message)")
    }
}
