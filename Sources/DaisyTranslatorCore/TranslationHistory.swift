import Foundation

/// One stored translation. Only successful translations are recorded, so both
/// texts are always non-empty.
public struct TranslationHistoryEntry: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let sourceText: String
    public let translatedText: String
    public let provider: ModelProvider
    public let targetLanguage: TargetLanguage
    public let createdAt: Date

    public init(
        id: Int64,
        sourceText: String,
        translatedText: String,
        provider: ModelProvider,
        targetLanguage: TargetLanguage,
        createdAt: Date
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.provider = provider
        self.targetLanguage = targetLanguage
        self.createdAt = createdAt
    }
}

/// Storage-independent rules for the translation history: how many entries are
/// kept, when a new translation replaces the newest one instead of stacking on
/// top of it, and how a search term becomes a SQL `LIKE` pattern.
public enum TranslationHistory {
    /// Hard cap on stored entries; the oldest ones are trimmed after each write.
    public static let maximumEntryCount = 500

    /// How long a newest entry stays eligible for collapsing. Long enough to
    /// cover one editing session, short enough that translating text that
    /// happens to start with an old entry does not overwrite it.
    public static let collapseWindow: TimeInterval = 300

    /// Whether an incoming translation should overwrite the newest entry rather
    /// than become a new one.
    ///
    /// Auto-translate fires on every pause in typing, so a sentence typed in
    /// one go would otherwise land as a trail of prefix fragments
    /// (`"ship the"`, `"ship the release"`, `"ship the release notes"`). Same
    /// request shape plus a source text that only grew means the user is still
    /// editing the same input, so the newest entry is the same thought and gets
    /// replaced. Equal source text (a retry, or a re-translated clipboard hit)
    /// is the degenerate prefix case and collapses too.
    public static func collapses(
        incomingSourceText: String,
        provider: ModelProvider,
        targetLanguage: TargetLanguage,
        into latest: TranslationHistoryEntry?,
        now: Date = Date()
    ) -> Bool {
        guard let latest else { return false }
        guard latest.provider == provider, latest.targetLanguage == targetLanguage else { return false }
        guard !latest.sourceText.isEmpty, incomingSourceText.hasPrefix(latest.sourceText) else { return false }
        return now.timeIntervalSince(latest.createdAt) <= collapseWindow
    }

    /// Escape character used by the search pattern, passed to SQL as `ESCAPE`.
    public static let searchEscapeCharacter = "\\"

    /// Substring-match `LIKE` pattern for a user-typed search term, or nil when
    /// the term is blank (the caller then lists everything). Wildcards typed by
    /// the user are escaped so they match literally.
    public static func searchPattern(for term: String) -> String? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var escaped = ""
        escaped.reserveCapacity(trimmed.count + 2)
        for character in trimmed {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return "%\(escaped)%"
    }
}
