import Foundation
import SQLite3
import DaisyTranslatorCore

/// Local SQLite database of successful translations, capped at
/// `TranslationHistory.maximumEntryCount` entries.
///
/// Synchronous and main-actor-called like `SettingsStore`: a write is one small
/// transaction against a local file, once per completed translation, which is
/// far cheaper than the network round trip that produced it.
final class TranslationHistoryStore {
    private let database: OpaquePointer

    /// - Throws: `TranslationHistoryStoreError` when the database file cannot be
    ///   opened or migrated. History is auxiliary, so callers treat a failed
    ///   store as "no history" rather than a fatal error.
    convenience init(fileManager: FileManager = .default) throws {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = applicationSupport.appendingPathComponent("DaisyTranslator", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try self.init(fileURL: directory.appendingPathComponent("history.sqlite"))
    }

    init(fileURL: URL) throws {
        database = try Self.openDatabase(at: fileURL)
    }

    deinit {
        sqlite3_close_v2(database)
    }

    /// Opens and migrates the file, closing the handle itself on failure: a
    /// class initializer that throws before assigning its properties never runs
    /// `deinit`, so the handle has no other owner yet.
    private static func openDatabase(at fileURL: URL) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(
            fileURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard status == SQLITE_OK, let handle else {
            if let handle { sqlite3_close_v2(handle) }
            throw TranslationHistoryStoreError(
                message: "Could not open \(fileURL.lastPathComponent)",
                code: status
            )
        }
        for statement in schemaStatements {
            let result = sqlite3_exec(handle, statement, nil, nil, nil)
            guard result == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(handle))
                sqlite3_close_v2(handle)
                throw TranslationHistoryStoreError(message: message, code: result)
            }
        }
        return handle
    }

    private static let schemaStatements = [
        "PRAGMA journal_mode = WAL",
        """
        CREATE TABLE IF NOT EXISTS entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            source_text TEXT NOT NULL,
            translated_text TEXT NOT NULL,
            provider TEXT NOT NULL,
            target_language TEXT NOT NULL
        )
        """,
        // Matches the read/trim ordering: recency first, id as the tiebreaker
        // for entries whose timestamps collide.
        "CREATE INDEX IF NOT EXISTS entries_recency ON entries(created_at DESC, id DESC)"
    ]

    // MARK: - Writing

    /// Stores one successful translation, collapsing a continued edit into the
    /// newest entry, moving a repeated translation back to the top, and trimming
    /// everything past the 500-entry cap.
    func record(
        sourceText: String,
        translatedText: String,
        provider: ModelProvider,
        targetLanguage: TargetLanguage,
        now: Date = Date()
    ) throws {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !translation.isEmpty else { return }

        try execute("BEGIN IMMEDIATE")
        do {
            let latest = try newestEntry()
            let shouldCollapse = TranslationHistory.collapses(
                incomingSourceText: source,
                provider: provider,
                targetLanguage: targetLanguage,
                into: latest,
                now: now
            )
            let collapseTarget = shouldCollapse ? latest?.id : nil

            // A repeat of an existing translation should resurface, not
            // duplicate: drop the older twin, keeping the entry being collapsed.
            try withStatement(
                """
                DELETE FROM entries
                WHERE source_text = ?1 AND provider = ?2 AND target_language = ?3 AND id IS NOT ?4
                """
            ) { statement in
                try bind(statement, 1, source)
                try bind(statement, 2, provider.rawValue)
                try bind(statement, 3, targetLanguage.rawValue)
                if let collapseTarget {
                    try check(sqlite3_bind_int64(statement, 4, collapseTarget))
                } else {
                    try check(sqlite3_bind_null(statement, 4))
                }
                try step(statement)
            }

            if let collapseTarget {
                try withStatement(
                    """
                    UPDATE entries
                    SET source_text = ?1, translated_text = ?2, created_at = ?3
                    WHERE id = ?4
                    """
                ) { statement in
                    try bind(statement, 1, source)
                    try bind(statement, 2, translation)
                    try check(sqlite3_bind_double(statement, 3, now.timeIntervalSince1970))
                    try check(sqlite3_bind_int64(statement, 4, collapseTarget))
                    try step(statement)
                }
            } else {
                try withStatement(
                    """
                    INSERT INTO entries (created_at, source_text, translated_text, provider, target_language)
                    VALUES (?1, ?2, ?3, ?4, ?5)
                    """
                ) { statement in
                    try check(sqlite3_bind_double(statement, 1, now.timeIntervalSince1970))
                    try bind(statement, 2, source)
                    try bind(statement, 3, translation)
                    try bind(statement, 4, provider.rawValue)
                    try bind(statement, 5, targetLanguage.rawValue)
                    try step(statement)
                }
                try trimToCap()
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func trimToCap() throws {
        try withStatement(
            """
            DELETE FROM entries WHERE id NOT IN (
                SELECT id FROM entries ORDER BY created_at DESC, id DESC LIMIT ?1
            )
            """
        ) { statement in
            try check(sqlite3_bind_int(statement, 1, Int32(TranslationHistory.maximumEntryCount)))
            try step(statement)
        }
    }

    func delete(id: Int64) throws {
        try withStatement("DELETE FROM entries WHERE id = ?1") { statement in
            try check(sqlite3_bind_int64(statement, 1, id))
            try step(statement)
        }
    }

    func deleteAll() throws {
        try execute("DELETE FROM entries")
    }

    // MARK: - Reading

    /// Newest entries first, restricted to those whose source or translated text
    /// contains `searchTerm`. A blank term lists everything.
    func entries(matching searchTerm: String = "") throws -> [TranslationHistoryEntry] {
        guard let pattern = TranslationHistory.searchPattern(for: searchTerm) else {
            return try entries(sql: "\(Self.selectColumns) ORDER BY created_at DESC, id DESC LIMIT ?1") { statement in
                try self.check(sqlite3_bind_int(statement, 1, Int32(TranslationHistory.maximumEntryCount)))
            }
        }
        return try entries(
            sql: """
            \(Self.selectColumns)
            WHERE source_text LIKE ?1 ESCAPE '\(TranslationHistory.searchEscapeCharacter)'
               OR translated_text LIKE ?1 ESCAPE '\(TranslationHistory.searchEscapeCharacter)'
            ORDER BY created_at DESC, id DESC
            LIMIT ?2
            """
        ) { statement in
            try self.bind(statement, 1, pattern)
            try self.check(sqlite3_bind_int(statement, 2, Int32(TranslationHistory.maximumEntryCount)))
        }
    }

    func count() throws -> Int {
        var total = 0
        try withStatement("SELECT COUNT(*) FROM entries") { statement in
            if sqlite3_step(statement) == SQLITE_ROW {
                total = Int(sqlite3_column_int64(statement, 0))
            }
        }
        return total
    }

    private static let selectColumns =
        "SELECT id, created_at, source_text, translated_text, provider, target_language FROM entries"

    private func newestEntry() throws -> TranslationHistoryEntry? {
        try entries(sql: "\(Self.selectColumns) ORDER BY created_at DESC, id DESC LIMIT 1") { _ in }.first
    }

    private func entries(
        sql: String,
        bindings: (OpaquePointer) throws -> Void
    ) throws -> [TranslationHistoryEntry] {
        var results: [TranslationHistoryEntry] = []
        try withStatement(sql) { statement in
            try bindings(statement)
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW else { throw error(status) }
                guard let entry = Self.entry(from: statement) else { continue }
                results.append(entry)
            }
        }
        return results
    }

    /// Rows written by a future schema (or hand-edited) can carry a provider or
    /// language this build does not know; those are skipped rather than failing
    /// the whole read.
    private static func entry(from statement: OpaquePointer) -> TranslationHistoryEntry? {
        guard let provider = ModelProvider(rawValue: text(statement, 4)),
              let targetLanguage = TargetLanguage(rawValue: text(statement, 5)) else {
            return nil
        }
        return TranslationHistoryEntry(
            id: sqlite3_column_int64(statement, 0),
            sourceText: text(statement, 2),
            translatedText: text(statement, 3),
            provider: provider,
            targetLanguage: targetLanguage,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        )
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: bytes)
    }

    // MARK: - SQLite plumbing

    private func withStatement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(database, sql, -1, &statement, nil))
        guard let statement else { throw error(SQLITE_ERROR) }
        defer { sqlite3_finalize(statement) }
        try body(statement)
    }

    private func execute(_ sql: String) throws {
        try check(sqlite3_exec(database, sql, nil, nil, nil))
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String) throws {
        try check(sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT))
    }

    private func step(_ statement: OpaquePointer) throws {
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else { throw error(status) }
    }

    private func check(_ status: Int32) throws {
        guard status == SQLITE_OK else { throw error(status) }
    }

    private func error(_ code: Int32) -> TranslationHistoryStoreError {
        TranslationHistoryStoreError(message: String(cString: sqlite3_errmsg(database)), code: code)
    }
}

struct TranslationHistoryStoreError: LocalizedError {
    let message: String
    let code: Int32

    var errorDescription: String? {
        "Translation history database error \(code): \(message)"
    }
}

/// `SQLITE_TRANSIENT` is a function-pointer sentinel the SQLite headers define
/// as a cast that Swift cannot import.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
