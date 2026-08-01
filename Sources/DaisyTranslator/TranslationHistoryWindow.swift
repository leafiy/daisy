import AppKit
import SwiftUI
import DaisyTranslatorCore
import LeafiyUI
import LeafiyUICore

/// Utility panel listing stored translations, opened from the menu-bar menu.
///
/// A panel rather than another SwiftUI `Window` scene: the delegate's
/// window-behavior code (minimal mode, always-on-top, the idle ghost) targets
/// the one non-panel window, so keeping history out of that set means it can
/// never be mistaken for the main window.
@MainActor
final class TranslationHistoryWindowController: NSObject, NSWindowDelegate {
    private let history: TranslationHistoryController
    private let onCopy: (String) -> Void
    private var panel: NSPanel?
    private var languageObserver: NSObjectProtocol?

    init(history: TranslationHistoryController, onCopy: @escaping (String) -> Void) {
        self.history = history
        self.onCopy = onCopy
        super.init()
        languageObserver = NotificationCenter.default.addObserver(
            forName: LeafiyLocalization.languageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshForLanguageChange()
            }
        }
    }

    deinit {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        history.isPresented = true
        history.reload()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        history.isPresented = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: HistoryPanelMetrics.defaultSize),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = L("Translation History")
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = false
        panel.contentMinSize = HistoryPanelMetrics.minSize
        panel.animationBehavior = .documentWindow
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: content)
        panel.center()
        return panel
    }

    private var content: some View {
        TranslationHistoryView(history: history, onCopy: onCopy)
            .id(LeafiyLocalization.language.rawValue)
    }

    private func refreshForLanguageChange() {
        guard let panel else { return }
        panel.title = L("Translation History")
        panel.contentView = NSHostingView(rootView: content)
    }
}

private enum HistoryPanelMetrics {
    static let defaultSize = NSSize(width: 480, height: 540)
    static let minSize = NSSize(width: 380, height: 320)
}

struct TranslationHistoryView: View {
    @ObservedObject var history: TranslationHistoryController
    let onCopy: (String) -> Void

    @State private var copiedEntryID: Int64?
    @State private var isClearConfirmationPresented = false

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            list
            FooterBar {
                Text(countLabel)
                    .lineLimit(1)
                Spacer()
                Button(L("Clear History")) {
                    isClearConfirmationPresented = true
                }
                .buttonStyle(.borderless)
                .disabled(history.totalCount == 0)
            }
        }
        .frame(minWidth: HistoryPanelMetrics.minSize.width, minHeight: HistoryPanelMetrics.minSize.height)
        .onAppear {
            history.reload()
        }
        .confirmationDialog(
            L("Delete all translation history?"),
            isPresented: $isClearConfirmationPresented
        ) {
            Button(L("Clear History"), role: .destructive) {
                history.clearAll()
            }
            Button(L("Cancel"), role: .cancel) {}
        }
    }

    private var searchBar: some View {
        HStack(spacing: LeafiyDesign.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L("Search source or translation"), text: $history.searchTerm)
                .textFieldStyle(.plain)
            if !history.searchTerm.isEmpty {
                Button {
                    history.searchTerm = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Clear"))
            }
        }
        .padding(.horizontal, LeafiyDesign.Spacing.m)
        .padding(.vertical, LeafiyDesign.Spacing.s)
    }

    @ViewBuilder
    private var list: some View {
        if history.isUnavailable {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: L("History is unavailable"),
                subtitle: L("The local history database could not be opened.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if history.entries.isEmpty {
            EmptyStateView(
                systemImage: "clock.arrow.circlepath",
                title: history.searchTerm.isEmpty ? L("No translation history yet") : L("No matches"),
                subtitle: history.searchTerm.isEmpty ? L("Completed translations are saved here.") : nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(history.entries) { entry in
                TranslationHistoryRow(
                    entry: entry,
                    isCopied: copiedEntryID == entry.id,
                    onCopy: { copy(entry) },
                    onDelete: { history.delete(entry) }
                )
            }
            .listStyle(.inset)
        }
    }

    /// `%ld` rather than `%d`: `String(format:)` reads a 32-bit value for `%d`,
    /// which misaligns the following argument when a 64-bit `Int` is passed.
    private var countLabel: String {
        if history.searchTerm.isEmpty {
            return String(
                format: L("%1$ld of %2$ld saved"),
                history.totalCount,
                TranslationHistory.maximumEntryCount
            )
        }
        return String(format: L("%ld matches"), history.entries.count)
    }

    private func copy(_ entry: TranslationHistoryEntry) {
        onCopy(entry.translatedText)
        copiedEntryID = entry.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedEntryID == entry.id {
                copiedEntryID = nil
            }
        }
    }
}

private struct TranslationHistoryRow: View {
    let entry: TranslationHistoryEntry
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: LeafiyDesign.Spacing.s) {
            VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xxs) {
                Text(entry.sourceText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(entry.translatedText)
                    .font(.body)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.vertical, LeafiyDesign.Spacing.xs)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(L("Copy")) { onCopy() }
            Button(L("Delete"), role: .destructive) { onDelete() }
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: LeafiyDesign.Spacing.xs) {
            Button(action: onCopy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(L("Copy"))
            .accessibilityLabel(L("Copy"))
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L("Delete"))
            .accessibilityLabel(L("Delete"))
        }
        .foregroundStyle(.secondary)
        .opacity(isHovering || isCopied ? 1 : 0)
    }

    private var caption: String {
        "\(HistoryTimestampFormatter.string(from: entry.createdAt)) · \(providerTitle(entry.provider)) · \(entry.targetLanguage.menuTitle)"
    }
}

/// Short date+time in the current UI language. `DateFormatter` construction is
/// expensive relative to a list row, so one instance is cached and rebuilt only
/// when the resolved language changes.
@MainActor
private enum HistoryTimestampFormatter {
    private static var cachedCode = ""
    private static var cachedFormatter = DateFormatter()

    static func string(from date: Date) -> String {
        let code = LeafiyLocalization.resolvedCode()
        if cachedCode != code {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: code)
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            cachedFormatter = formatter
            cachedCode = code
        }
        return cachedFormatter.string(from: date)
    }
}
