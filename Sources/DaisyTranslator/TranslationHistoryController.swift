import Foundation
import SwiftUI
import DaisyTranslatorCore

/// Owns the translation-history database and the state the history panel binds
/// to: the current search term, the matching entries, and the total count.
///
/// The store is opened once at launch. If that fails there is no history rather
/// than no app: `isUnavailable` flips and the panel says so instead of showing a
/// permanently empty list.
@MainActor
final class TranslationHistoryController: ObservableObject {
    @Published var searchTerm = "" {
        didSet {
            guard searchTerm != oldValue else { return }
            reload()
        }
    }

    @Published private(set) var entries: [TranslationHistoryEntry] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var isUnavailable = false

    /// Set by the panel controller; recording only refreshes the published
    /// entries while someone is looking at them.
    var isPresented = false

    private let store: TranslationHistoryStore?

    init() {
        store = try? TranslationHistoryStore()
        isUnavailable = store == nil
    }

    /// Records one successful translation. Called from every translate path, so
    /// it must never surface a failure into the translation flow.
    func record(sourceText: String, translatedText: String, settings: AppSettings) {
        guard let store else { return }
        do {
            try store.record(
                sourceText: sourceText,
                translatedText: translatedText,
                provider: settings.provider,
                targetLanguage: settings.targetLanguage
            )
        } catch {
            isUnavailable = true
            return
        }
        if isPresented {
            reload()
        }
    }

    func reload() {
        guard let store else {
            entries = []
            totalCount = 0
            return
        }
        do {
            entries = try store.entries(matching: searchTerm)
            totalCount = try store.count()
            isUnavailable = false
        } catch {
            entries = []
            totalCount = 0
            isUnavailable = true
        }
    }

    func delete(_ entry: TranslationHistoryEntry) {
        guard let store else { return }
        do {
            try store.delete(id: entry.id)
        } catch {
            isUnavailable = true
        }
        reload()
    }

    func clearAll() {
        guard let store else { return }
        do {
            try store.deleteAll()
        } catch {
            isUnavailable = true
        }
        reload()
    }
}
