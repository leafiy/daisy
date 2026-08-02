import AppKit
import SwiftUI
import DaisyTranslatorCore
import LeafiyUI
import LeafiyUICore

struct TranslationHistoryView: View {
    @ObservedObject var history: TranslationHistoryController
    @ObservedObject var model: DaisyModel
    let onCopy: (String) -> Void

    @State private var copiedEntryID: Int64?
    @State private var isClearConfirmationPresented = false

    var body: some View {
        VStack(spacing: 0) {
            list
            FooterBar {
                Text(countLabel)
                    .lineLimit(1)
                Spacer()
            }
        }
        .frame(
            minWidth: LeafiyDesign.Size.mainWindowMinWidth,
            minHeight: LeafiyDesign.Size.mainWindowMinHeight
        )
        .navigationTitle(L("Translation History"))
        .searchable(
            text: $history.searchTerm,
            placement: .toolbar,
            prompt: Text(L("Search source or translation"))
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isClearConfirmationPresented = true
                } label: {
                    Label(L("Clear History"), systemImage: "trash")
                }
                .help(L("Clear History"))
                .disabled(history.totalCount == 0)
            }
        }
        .onAppear {
            history.isPresented = true
            history.reload()
        }
        .onDisappear {
            history.isPresented = false
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

    @ViewBuilder
    private var list: some View {
        if history.isUnavailable {
            ContentUnavailableView {
                Label(L("History is unavailable"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(L("The local history database could not be opened."))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if history.entries.isEmpty {
            ContentUnavailableView {
                Label(
                    history.searchTerm.isEmpty ? L("No translation history yet") : L("No matches"),
                    systemImage: "clock.arrow.circlepath"
                )
            } description: {
                if history.searchTerm.isEmpty {
                    Text(L("Completed translations are saved here."))
                }
            }
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
