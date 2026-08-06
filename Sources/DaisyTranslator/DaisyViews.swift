import AppKit
import SwiftUI
import DaisyTranslatorCore
import LeafiyUI
import LeafiyUICore

struct TranslatorView: View {
    @ObservedObject var model: DaisyModel
    let appleTranslationBridge: AnyView

    var body: some View {
        content
            .toolbar(minimalMode ? .hidden : .automatic, for: .windowToolbar)
            .frame(
                minWidth: minimalMode ? MinimalLayout.minWidth : LeafiyDesign.Size.mainWindowMinWidth,
                minHeight: minimalMode ? MinimalLayout.minHeight : LeafiyDesign.Size.mainWindowMinHeight
            )
            .overlay(alignment: .topLeading) {
                appleTranslationBridge
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
            .leafiyToast(model.transientStatus?.message)
            .sheet(isPresented: Binding(
                get: { model.isOnboardingPresented },
                set: { presented in
                    if !presented {
                        model.dismissOnboardingForNow()
                    }
                }
            )) {
                OnboardingView(model: model)
            }
    }

    private var minimalMode: Bool { model.settings.minimalMode }

    @ViewBuilder
    private var content: some View {
        if minimalMode {
            minimalContent
        } else {
            standardContent
        }
    }

    private var standardContent: some View {
        VStack(spacing: 0) {
            mainContent
            FooterBar {
                Text(model.statusText)
                    .lineLimit(1)
                Spacer()
                Text(model.settings.targetLanguage.menuTitle)
                    .foregroundStyle(.tertiary)
            }
        }
        .toolbar {
            ToolbarItem {
                Button(L("Translate")) {
                    model.translateCurrentText()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                pinButton
            }
        }
    }

    private var minimalContent: some View {
        VStack(spacing: LeafiyDesign.Spacing.s) {
            HStack(spacing: LeafiyDesign.Spacing.xs) {
                Spacer()
                pinButton
                    .buttonStyle(.borderless)
            }
            GroupBox {
                SourceTextEditor(
                    text: Binding(
                        get: { model.sourceText },
                        set: { model.sourceText = $0 }
                    ),
                    onTextChange: {
                        model.sourceTextDidChange()
                    },
                    focusOnAppear: true
                )
                .frame(minHeight: MinimalLayout.paneMinHeight, maxHeight: .infinity)
                .accessibilityLabel(L("Source input"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            GroupBox {
                minimalResultPane
                    .frame(
                        maxWidth: .infinity,
                        minHeight: MinimalLayout.paneMinHeight,
                        maxHeight: .infinity
                    )
                    .accessibilityLabel(L("Translation output"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(LeafiyDesign.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The frosted backdrop lives behind the hosting view, so minimal
        // mode's own fill has to thin out by the blur strength; at full
        // coverage it would paint straight over the blur.
        .background(
            Color(nsColor: .windowBackgroundColor)
                .opacity(1 - model.windowBlurIntensity)
                .ignoresSafeArea()
        )
        // No chrome remains in minimal mode, so claim the title-bar strip
        // instead of leaving it as a blank band above the content.
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Compact stand-in for the standard empty state: the full placeholder
    /// (icon, title, generous padding) overflows the minimal panes.
    @ViewBuilder
    private var minimalResultPane: some View {
        if model.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(L("No translation yet"))
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            resultPane
        }
    }

    private var pinButton: some View {
        Button {
            model.updateSettings { $0.alwaysOnTop.toggle() }
        } label: {
            Image(systemName: model.settings.alwaysOnTop ? "pin.fill" : "pin")
        }
        .help(L("Pin Window"))
    }

    private enum MinimalLayout {
        static let minWidth: CGFloat = 300
        static let minHeight: CGFloat = 280
        static let paneMinHeight: CGFloat = 64
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.m) {
            Text(L("Source"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            GroupBox {
                SourceTextEditor(
                    text: Binding(
                        get: { model.sourceText },
                        set: { model.sourceText = $0 }
                    ),
                    onTextChange: {
                        model.sourceTextDidChange()
                    }
                )
                .accessibilityLabel(L("Source input"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text(L("Translation"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L("Target Language"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker(L("Target Language"), selection: settingsBinding(\.targetLanguage)) {
                    ForEach(TargetLanguage.allCases, id: \.rawValue) { language in
                        Text(language.menuTitle).tag(language)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: model.settings.targetLanguage) { _, _ in
                    model.scheduleTranslation()
                }
            }
            GroupBox {
                resultPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(L("Translation output"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(LeafiyDesign.Spacing.l)
    }

    @ViewBuilder
    private var resultPane: some View {
        if model.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                L("No translation yet"),
                systemImage: "text.bubble",
                description: Text(L("Enter source text to start translating"))
            )
        } else {
            ScrollView {
                Text(model.translatedText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in
                model.updateSettings { $0[keyPath: keyPath] = value }
            }
        )
    }
}

private struct SourceTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onTextChange: () -> Void
    var focusOnAppear = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.allowsDocumentBackgroundColorChange = false

        scrollView.documentView = textView
        context.coordinator.textView = textView
        // With minSize zero, an empty text view is one line tall and clicks
        // in the rest of the card land on the clip view — the editor looks
        // and feels a few pixels high. Track the clip view's height so the
        // text view always fills the visible area and any click focuses it.
        let clipView = scrollView.contentView
        clipView.postsFrameChangedNotifications = true
        context.coordinator.clipViewObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak textView, weak clipView] _ in
            guard let textView, let clipView else { return }
            let height = clipView.bounds.height
            textView.minSize = NSSize(width: 0, height: height)
            if textView.frame.height < height {
                textView.setFrameSize(NSSize(width: textView.frame.width, height: height))
            }
        }
        if focusOnAppear {
            // The minimal-mode editor is rebuilt on every mode switch; claim
            // key focus once the view lands in its window so typing works
            // without an extra click.
            DispatchQueue.main.async { [weak textView] in
                guard let textView, let window = textView.window else { return }
                window.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onTextChange = onTextChange

        guard let textView = scrollView.documentView as? NSTextView else { return }

        // During IME composition, rewriting NSTextView.string from SwiftUI commits
        // or cancels the marked text. Let AppKit own the editor until composition
        // finishes, then sync the committed text through the delegate.
        guard !textView.hasMarkedText() else { return }
        guard textView.string != text else { return }

        context.coordinator.isApplyingProgrammaticChange = true
        let selectedRange = textView.selectedRange()
        textView.string = text
        let textLength = (text as NSString).length
        if selectedRange.location <= textLength {
            textView.setSelectedRange(NSRange(
                location: selectedRange.location,
                length: min(selectedRange.length, textLength - selectedRange.location)
            ))
        } else {
            textView.setSelectedRange(NSRange(location: textLength, length: 0))
        }
        context.coordinator.isApplyingProgrammaticChange = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onTextChange: () -> Void
        var isApplyingProgrammaticChange = false
        weak var textView: NSTextView?
        var clipViewObserver: NSObjectProtocol?

        init(text: Binding<String>, onTextChange: @escaping () -> Void) {
            self.text = text
            self.onTextChange = onTextChange
        }

        deinit {
            if let clipViewObserver {
                NotificationCenter.default.removeObserver(clipViewObserver)
            }
        }

        func textDidChange(_ notification: Notification) {
            syncCommittedText()
        }

        func textDidEndEditing(_ notification: Notification) {
            syncCommittedText()
        }

        private func syncCommittedText() {
            guard !isApplyingProgrammaticChange else { return }
            guard let textView else { return }
            guard !textView.hasMarkedText() else { return }

            let newValue = textView.string
            guard newValue != text.wrappedValue else { return }
            text.wrappedValue = newValue
            onTextChange()
        }
    }
}

struct DaisySettingsView: View {
    @ObservedObject var model: DaisyModel

    var body: some View {
        SettingsScaffold {
            LeafiyGeneralPane(
                language: appLanguageBinding,
                launchAtLogin: settingsBinding(\.launchAtLogin),
                dockIcon: settingsBinding(\.showDockIcon),
                tail: {
                    ProviderConfigurationForm(model: model)
                    providerHint
                }
            )
            DaisyWorkflowSettingsPane(model: model)
            SettingsPane(L("Privacy"), systemImage: "hand.raised", height: 420) {
                Section(L("Privacy")) {
                    Text(L("""
Daisy does not collect accounts, device identifiers, contacts, browsing history, or analytics data.

When you use Apple System Translation, translation is handled by macOS system translation. If you switch to external services such as DeepSeek, Google, Baidu, or OpenAI-compatible, the source text is sent to the translation endpoint you configure in General; the translation is returned by that service. API keys are stored only in the local settings file and are used to request the service you choose.

Clipboard watching is off by default. When enabled, Daisy reads clipboard text locally and translates it according to your configuration. Auto paste requires macOS Accessibility permission; Daisy sends Cmd+V only when paste is triggered.
"""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    Text(L("The last 500 successful translations are kept in a local database inside Daisy's application support folder. They never leave your Mac, and you can delete them at any time from Translation History in the menu bar."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            AboutPane(
                title: L("About"),
                tagline: L("A minimal native Swift desktop translator for macOS"),
                copyright: L("© 2026 Leafiy")
            )
        }
    }

    private var providerHint: some View {
        Text(L("Apple System Translation is used by default and does not require an API key. Ollama can use the local service or a remote address, and its installed models are detected automatically; OpenAI-compatible can connect to your own service (end the Base URL with # to use it verbatim as the full endpoint); DeepSeek, Google, and Baidu can use their official APIs."))
            .font(.caption)
            .foregroundStyle(.secondary)
    }


    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { model.settings.selectedAppLanguage },
            set: { language in
                model.updateSettings { $0.selectedAppLanguage = language }
            }
        )
    }
    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in
                model.updateSettings { $0[keyPath: keyPath] = value }
            }
        )
    }
}

/// The production Workflow settings pane, factored as a view so visual capture
/// can render the exact controls without selecting a `TabView` tab manually.
struct DaisyWorkflowSettingsPane: View {
    @ObservedObject var model: DaisyModel

    var body: some View {
        SettingsPane(L("Workflow"), systemImage: "slider.horizontal.3", height: 760) {
            Section(L("Translate Selection")) {
                Toggle(L("Translate Selection"), isOn: settingsBinding(\.quickTranslateEnabled))
                Text(L("Translate selected text and show the translation in a popup toolbar"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(L("Shortcut")) {
                    ShortcutField(spec: shortcutBinding)
                }
                Text(String(format: L("Current shortcut: %@"), shortcutDisplay))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(L("Translate Selection Auto Copy"), isOn: settingsBinding(\.quickTranslateAutoCopy))
                Text(L("Automatically write the popup translation to the clipboard"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Automation")) {
                Toggle(L("Auto Translate"), isOn: settingsBinding(\.autoTranslate))
                Text(L("Automatically translate after input stops"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(L("Watch Clipboard"), isOn: settingsBinding(\.watchClipboard))
                Text(L("Automatically read and translate clipboard changes"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(L("Auto Copy"), isOn: settingsBinding(\.autoCopy))
                Text(L("Write translations to the clipboard when complete"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(L("Auto Paste"), isOn: settingsBinding(\.autoPaste))
                Text(L("Paste translations into the frontmost app when complete"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Window")) {
                Toggle(L("Window Transparency"), isOn: settingsBinding(\.windowOpacityEnabled))
                Text(L("Make the whole window translucent in both standard and minimal mode"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.settings.windowOpacityEnabled {
                    WindowOpacitySlider(
                        title: L("Focused"),
                        value: settingsBinding(\.focusedWindowOpacity),
                        onPreview: { model.previewWindowOpacity?($0) }
                    )
                    WindowOpacitySlider(
                        title: L("Unfocused"),
                        value: settingsBinding(\.unfocusedWindowOpacity),
                        onPreview: { model.previewWindowOpacity?($0) }
                    )
                    Text(L("Transparency automatically blurs the background behind the window, more so the more transparent it is"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var shortcutBinding: Binding<KeyboardShortcutSpec> {
        Binding(
            get: {
                KeyboardShortcutSpec(parsing: model.settings.quickTranslateShortcut)
                    ?? KeyboardShortcutSpec(parsing: AppSettings.defaults(environment: [:]).quickTranslateShortcut)!
            },
            set: { spec in
                let shortcut = spec.canonicalDescription
                guard LeafiyHotKeyCenter.isShortcutSupported(spec) else {
                    model.showTransientStatus(L("Invalid shortcut"), kind: .failure)
                    return
                }
                model.updateSettings { $0.quickTranslateShortcut = shortcut }
            }
        )
    }

    private var shortcutDisplay: String {
        KeyboardShortcutSpec(parsing: model.settings.quickTranslateShortcut)?.display
            ?? model.settings.quickTranslateShortcut
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in
                model.updateSettings { $0[keyPath: keyPath] = value }
            }
        )
    }
}

/// Opacity slider that previews live on the main window but only writes the
/// setting when the drag ends: every write persists to disk and re-applies
/// the whole window behaviour, which is far too heavy per drag frame.
private struct WindowOpacitySlider: View {
    let title: String
    @Binding var value: Double
    let onPreview: (Double) -> Void

    @State private var draft: Double?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: LeafiyDesign.Spacing.s) {
                Slider(
                    value: Binding(
                        get: { draft ?? value },
                        set: { next in
                            draft = next
                            onPreview(next)
                        }
                    ),
                    in: AppSettings.windowOpacityRange,
                    onEditingChanged: { editing in
                        guard !editing, let settled = draft else { return }
                        draft = nil
                        value = settled
                    }
                )
                Text(String(format: "%.0f%%", (draft ?? value) * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

struct ProviderConfigurationForm: View {
    @ObservedObject var model: DaisyModel

    var body: some View {
        Picker(L("Type"), selection: Binding(
            get: { model.settings.provider },
            set: { model.setProvider($0) }
        )) {
            ForEach(ModelProvider.allCases, id: \.rawValue) { provider in
                Text(providerTitle(provider)).tag(provider)
            }
        }
        if model.settings.provider == .ollama {
            ollamaFields
        } else {
            standardFields
        }
        providerLinks
    }

    @ViewBuilder
    private var standardFields: some View {
        ProviderFieldRow(L("Base URL"), hint: providerFieldSemantics.baseURLHint) {
            TextField("", text: providerFieldBinding(\.baseURL))
                .disabled(!providerFieldSemantics.baseURLEnabled)
        }
        ProviderFieldRow(L("API Key"), hint: providerFieldSemantics.apiKeyHint) {
            SecureField("", text: providerFieldBinding(\.apiKey))
                .disabled(!providerFieldSemantics.apiKeyEnabled)
        }
        ProviderFieldRow(L("Model"), hint: providerFieldSemantics.modelHint) {
            TextField("", text: providerFieldBinding(\.model))
                .disabled(!providerFieldSemantics.modelEnabled)
        }
    }

    /// Ollama needs neither an address nor a key when it runs locally, and its
    /// installed models are discoverable — so it gets its own field set.
    @ViewBuilder
    private var ollamaFields: some View {
        Picker(L("Ollama Service"), selection: Binding(
            get: { model.settings.ollamaConnection },
            set: { model.setOllamaConnection($0) }
        )) {
            Text(L("Local")).tag(OllamaConnection.local)
            Text(L("Remote")).tag(OllamaConnection.remote)
        }
        .pickerStyle(.segmented)
        if model.settings.ollamaConnection == .local {
            Text(String(format: L("Connects to the Ollama running on this Mac (%@)"), AppSettings.localOllamaBaseURL))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ProviderFieldRow(L("Base URL"), hint: String(format: L("Example: %@"), "http://192.168.1.10:11434")) {
                TextField("", text: providerFieldBinding(\.baseURL))
            }
            ProviderFieldRow(L("API Key"), hint: L("Optional: only for a gated Ollama")) {
                SecureField("", text: providerFieldBinding(\.apiKey))
            }
        }
        LabeledContent(L("Model")) {
            HStack(spacing: LeafiyDesign.Spacing.s) {
                ollamaModelControl
                Button {
                    model.refreshOllamaModels()
                } label: {
                    if model.ollamaModelDiscovery.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.ollamaModelDiscovery.isLoading)
                .help(L("Reload installed models"))
            }
        }
        // Attached to a leaf row on purpose: wrapping the whole field group in a
        // modifier would collapse it into a single Form row.
        ollamaDiscoveryHint
            .onAppear {
                model.refreshOllamaModels()
            }
            .onChange(of: ollamaDiscoveryKey) {
                model.refreshOllamaModels(afterMilliseconds: 400)
            }
    }

    /// A picker once models are known, a plain field otherwise — so an
    /// unreachable server never blocks typing a model name by hand.
    @ViewBuilder
    private var ollamaModelControl: some View {
        if ollamaModelChoices.isEmpty {
            TextField("", text: providerFieldBinding(\.model))
        } else {
            Picker(L("Model"), selection: providerFieldBinding(\.model)) {
                ForEach(ollamaModelChoices, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
        }
    }

    /// Discovered models, plus the current selection when the server does not
    /// report it, so an existing choice is never silently dropped.
    private var ollamaModelChoices: [String] {
        let discovered = model.ollamaModelDiscovery.models
        let current = model.settings.model
        guard !current.isEmpty, !discovered.contains(current) else { return discovered }
        return discovered + [current]
    }

    /// Re-probes whenever the target server changes, including while the
    /// remote address is being typed.
    private var ollamaDiscoveryKey: String {
        "\(model.settings.ollamaConnection.rawValue)|\(model.settings.effectiveBaseURL)"
    }

    @ViewBuilder
    private var ollamaDiscoveryHint: some View {
        switch model.ollamaModelDiscovery {
        case .idle:
            Text(L("Fill in the remote Ollama address to load its models"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loading:
            Text(L("Loading installed models…"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .loaded(models) where models.isEmpty:
            Text(L("No models installed. Pull one with “ollama pull” first."))
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .loaded(models):
            Text(String(format: L("%ld installed models found"), models.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var providerLinks: some View {
        VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.s) {
            ForEach(externalServiceProviders, id: \.rawValue) { provider in
                if let title = providerApplicationLinkTitle(provider),
                   let url = providerApplicationLinkURL(provider) {
                    Link(title, destination: url)
                }
            }
        }
        .font(.callout)
    }

    private var providerFieldSemantics: ProviderFieldSemantics {
        ProviderFieldSemantics(provider: model.settings.provider)
    }

    private func providerFieldBinding(_ keyPath: WritableKeyPath<ProviderConfiguration, String>) -> Binding<String> {
        Binding(
            get: {
                let configuration = ProviderConfiguration(
                    baseURL: model.settings.baseURL,
                    apiKey: model.settings.apiKey,
                    model: model.settings.model
                )
                return configuration[keyPath: keyPath]
            },
            set: { value in
                model.setProviderField(keyPath, to: value)
            }
        )
    }
}

/// Provider form row: the title carries the example/status hint as caption
/// text underneath, so the input itself stays free of placeholder noise.
private struct ProviderFieldRow<Field: View>: View {
    private let title: String
    private let hint: String?
    private let field: Field

    init(_ title: String, hint: String? = nil, @ViewBuilder field: () -> Field) {
        self.title = title
        self.hint = hint
        self.field = field()
    }

    var body: some View {
        LabeledContent {
            field
        } label: {
            Text(title)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Field behaviour for the providers that share the standard Base URL / API Key
/// / Model layout. Ollama has its own fields, so it never reaches here.
private struct ProviderFieldSemantics {
    let provider: ModelProvider

    var baseURLEnabled: Bool {
        provider != .appleSystem && provider != .deepSeek
    }

    var apiKeyEnabled: Bool {
        provider != .appleSystem
    }

    var modelEnabled: Bool {
        provider != .appleSystem && provider != .google && provider != .baidu
    }

    var baseURLHint: String? {
        switch provider {
        case .appleSystem:
            return L("No configuration needed")
        case .deepSeek:
            return L("Automatically uses official URL")
        case .google:
            return String(format: L("Example: %@"), "https://translate.googleapis.com")
        case .baidu:
            return String(format: L("Example: %@"), "https://fanyi-api.baidu.com")
        case .openAICompatible:
            return String(format: L("Example: %@"), "https://api.example.com/v1")
        case .ollama:
            return String(format: L("Example: %@"), AppSettings.localOllamaBaseURL)
        }
    }

    var apiKeyHint: String? {
        switch provider {
        case .appleSystem:
            return L("No configuration needed")
        case .google:
            return L("Optional: Google Cloud API Key")
        case .deepSeek, .baidu, .ollama, .openAICompatible:
            return nil
        }
    }

    var modelHint: String? {
        switch provider {
        case .appleSystem, .google, .baidu:
            return L("No configuration needed")
        case .deepSeek:
            return String(format: L("Example: %@"), AppSettings.defaultModel(for: .deepSeek))
        case .ollama, .openAICompatible:
            return nil
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: DaisyModel

    var body: some View {
        VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.l) {
            VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.s) {
                Text(L("Welcome to Daisy"))
                    .font(.title2.weight(.semibold))
                Text(L("Apple System Translation is used by default. You can also switch to your own DeepSeek, Google, Baidu, or OpenAI-compatible service."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Form {
                Section(L("First-time Setup")) {
                    ProviderConfigurationForm(model: model)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(L("Configure Later")) {
                    model.dismissOnboardingForNow()
                }
                Button(L("Get Started")) {
                    model.completeOnboarding()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(LeafiyDesign.Spacing.xl)
        .frame(width: LeafiyDesign.Size.settingsPaneWidth)
    }
}

struct DaisyMenuBarMenu: View {
    @ObservedObject var model: DaisyModel
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(appDelegate.isMainWindowVisible ? L("Hide Window") : L("Show Window")) {
            appDelegate.toggleMainWindow(openWindow: openWindow)
        }
        Button(L("Paste Current Translation")) {
            model.pasteResult()
        }
        Button(L("Translation History…")) {
            appDelegate.showHistoryWindow(openWindow: openWindow)
        }
        Divider()
        Picker(L("Target Language"), selection: Binding(
            get: { model.settings.targetLanguage },
            set: { language in model.updateSettings { $0.targetLanguage = language } }
        )) {
            ForEach(TargetLanguage.allCases, id: \.rawValue) { language in
                Text(language.menuTitle).tag(language)
            }
        }
        Divider()
        Toggle(L("Minimal Mode"), isOn: settingsBinding(\.minimalMode))
        Toggle(L("Translate Selection"), isOn: settingsBinding(\.quickTranslateEnabled))
        Toggle(L("Auto Translate"), isOn: settingsBinding(\.autoTranslate))
        Toggle(L("Watch Clipboard"), isOn: settingsBinding(\.watchClipboard))
        Toggle(L("Auto Copy"), isOn: settingsBinding(\.autoCopy))
        Toggle(L("Auto Paste"), isOn: settingsBinding(\.autoPaste))
        Text(String(format: L("Shortcut: %@"), shortcutDisplay))
        LeafiyMenuTail(language: model.settings.selectedAppLanguage)
    }

    private var shortcutDisplay: String {
        KeyboardShortcutSpec(parsing: model.settings.quickTranslateShortcut)?.display
            ?? model.settings.quickTranslateShortcut
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}

/// Standard app-menu entry for a standard auxiliary window. The menu-bar
/// extra remains the fastest entry point, while this keeps Daisy consistent
/// with ordinary macOS apps and makes history keyboard-accessible.
struct DaisyCommands: Commands {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Divider()
            Button(L("Translation History…")) {
                appDelegate.showHistoryWindow(openWindow: openWindow)
            }
            .keyboardShortcut("y", modifiers: .command)
        }
    }
}

struct DaisyMenuBarLabel: View {
    @ObservedObject var model: DaisyModel

    private static let baseIcon = LeafiyMenuBarIconRenderer.baseIcon(
        NSImage.daisyIcon(),
        symbolFallback: "character.bubble",
        accessibilityDescription: "Daisy"
    )

    var body: some View {
        Image(nsImage: LeafiyMenuBarIconRenderer.image(base: Self.baseIcon, status: menuBarStatus))
        .accessibilityLabel(Text(verbatim: "Daisy"))
    }

    private var menuBarStatus: LeafiyMenuBarStatus {
        if model.isTranslating {
            return .busy
        }

        guard let kind = model.menuBarDot?.kind else {
            return .idle
        }

        switch kind {
        case .success:
            return .success
        case .failure:
            return .failure
        }
    }
}
