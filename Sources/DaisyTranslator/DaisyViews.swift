import AppKit
import SwiftUI
import DaisyTranslatorCore
import LeafiyUI
import LeafiyUICore

struct TranslatorView: View {
    @ObservedObject var model: DaisyModel
    let appleTranslationBridge: AnyView
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        content
            .toolbar(minimalMode ? .hidden : .automatic, for: .windowToolbar)
            .frame(minWidth: contentMinWidth, minHeight: contentMinHeight)
            .overlay(alignment: .topLeading) {
                appleTranslationBridge
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
            .leafiyToast(model.transientStatusMessage)
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

    /// The unobtrusive floating state: only in minimal mode, whenever this
    /// window is not the key window.
    private var minimalMode: Bool { model.settings.minimalMode }

    private var isCapsule: Bool { minimalMode && model.isMinimalCapsuleCollapsed }

    private var isGhosted: Bool {
        minimalMode && controlActiveState != .key
    }

    /// Folded state declares no minimum: the AppKit frame transition owns
    /// the capsule size, and any SwiftUI minimum would be inflated by the
    /// title-bar safe-area inset and push the 40pt window into a tall pill.
    private var contentMinWidth: CGFloat {
        if isCapsule { return 0 }
        return minimalMode ? MinimalLayout.minWidth : LeafiyDesign.Size.mainWindowMinWidth
    }

    private var contentMinHeight: CGFloat {
        if isCapsule { return 0 }
        return minimalMode ? MinimalLayout.minHeight : LeafiyDesign.Size.mainWindowMinHeight
    }

    @ViewBuilder
    private var content: some View {
        if isCapsule {
            capsuleContent
        } else if minimalMode {
            minimalContent
        } else {
            standardContent
        }
    }

    /// The folded state after a minute out of focus: a small frosted capsule
    /// in the screen corner. Clicking it makes the window key, which expands
    /// it back to the minimal frame.
    private var capsuleContent: some View {
        HStack(spacing: LeafiyDesign.Spacing.xs) {
            if let icon = NSImage.daisyAppIcon()?.leafiyMenuBarSized() {
                Image(nsImage: icon)
            }
            Text(verbatim: "Daisy")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground().clipShape(Capsule()))
        .overlay(Capsule().strokeBorder(.quaternary))
        .ignoresSafeArea()
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
            LeafiyCard {
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
            LeafiyCard {
                minimalResultPane
                    .frame(minHeight: MinimalLayout.paneMinHeight, maxHeight: .infinity)
                    .accessibilityLabel(L("Translation output"))
            }
        }
        .opacity(isGhosted ? 0.7 : 1)
        .blur(radius: isGhosted ? 2 : 0)
        .padding(LeafiyDesign.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(minimalBackground)
        // No chrome remains in minimal mode, so claim the title-bar strip
        // instead of leaving it as a blank band above the content.
        .ignoresSafeArea(.container, edges: .top)
        .animation(.easeInOut(duration: 0.2), value: isGhosted)
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

    /// Solid window backing while focused; a frosted, behind-window blur once
    /// the window drops out of focus.
    @ViewBuilder
    private var minimalBackground: some View {
        if isGhosted {
            VisualEffectBackground().ignoresSafeArea()
        } else {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
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
            LeafiyCard {
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
            LeafiyCard {
                resultPane
                    .accessibilityLabel(L("Translation output"))
            }
        }
        .padding(LeafiyDesign.Spacing.l)
    }

    @ViewBuilder
    private var resultPane: some View {
        if model.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyStateView(systemImage: "text.bubble", title: L("No translation yet"), subtitle: L("Enter source text to start translating"))
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
            SettingsPane(L("General"), systemImage: "globe", height: 480) {
                Section(L("General")) {
                    LanguagePicker(selection: appLanguageBinding)
                    ProviderConfigurationForm(model: model)
                    providerHint
                }
            }
            SettingsPane(L("Workflow"), systemImage: "slider.horizontal.3", height: 560) {
                Section(L("Quick Translate")) {
                    Toggle(L("Quick Translate"), isOn: settingsBinding(\.quickTranslateEnabled))
                    Text(L("Translate selected text and show the translation in a popup toolbar"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent(L("Shortcut")) {
                        ShortcutField(spec: shortcutBinding)
                    }
                    Text(String(format: L("Current shortcut: %@"), shortcutDisplay))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(L("Quick Translate Auto Copy"), isOn: settingsBinding(\.quickTranslateAutoCopy))
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
            }
            SettingsPane(L("Privacy"), systemImage: "hand.raised", height: 360) {
                Section(L("Privacy")) {
                    Text(L("""
Daisy does not collect accounts, device identifiers, contacts, browsing history, or analytics data.

When you use Apple System Translation, translation is handled by macOS system translation. If you switch to external services such as DeepSeek, Google, Baidu, or OpenAI-compatible, the source text is sent to the translation endpoint you configure in General; the translation is returned by that service. API keys are stored only in the local settings file and are used to request the service you choose.

Clipboard watching is off by default. When enabled, Daisy reads clipboard text locally and translates it according to your configuration. Auto paste requires macOS Accessibility permission; Daisy sends Cmd+V only when paste is triggered.
"""))
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
        Text(L("Apple System Translation is used by default and does not require an API key. OpenAI-compatible and Ollama can connect to your own services; DeepSeek, Google, and Baidu can use their official APIs."))
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
    private var shortcutBinding: Binding<KeyboardShortcutSpec> {
        Binding(
            get: {
                KeyboardShortcutSpec(parsing: model.settings.quickTranslateShortcut)
                    ?? KeyboardShortcutSpec(parsing: AppSettings.defaults(environment: [:]).quickTranslateShortcut)!
            },
            set: { spec in
                let shortcut = spec.canonicalDescription
                guard HotKeyCenter.isShortcutSupported(shortcut) else {
                    model.showTransientStatus(L("Invalid shortcut"))
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
        LabeledContent(L("Base URL")) {
            TextField(
                providerFieldSemantics.baseURLPlaceholder,
                text: providerFieldBinding(\.baseURL)
            )
            .disabled(!providerFieldSemantics.baseURLEnabled)
        }
        LabeledContent(L("API Key")) {
            SecureField(
                providerFieldSemantics.apiKeyPlaceholder,
                text: providerFieldBinding(\.apiKey)
            )
            .disabled(!providerFieldSemantics.apiKeyEnabled)
        }
        LabeledContent(L("Model")) {
            TextField(
                providerFieldSemantics.modelPlaceholder,
                text: providerFieldBinding(\.model)
            )
            .disabled(!providerFieldSemantics.modelEnabled)
        }
        providerLinks
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

    var baseURLPlaceholder: String {
        switch provider {
        case .appleSystem:
            return L("No configuration needed")
        case .deepSeek:
            return L("Automatically uses official URL")
        case .google:
            return "https://translate.googleapis.com"
        case .baidu:
            return "https://fanyi-api.baidu.com"
        case .ollama, .openAICompatible:
            return "https://api.example.com/v1"
        }
    }

    var apiKeyPlaceholder: String {
        switch provider {
        case .appleSystem:
            return L("No configuration needed")
        case .google:
            return L("Optional: Google Cloud API Key")
        case .deepSeek, .baidu, .ollama, .openAICompatible:
            return L("API Key")
        }
    }

    var modelPlaceholder: String {
        switch provider {
        case .appleSystem, .google, .baidu:
            return L("No configuration needed")
        case .deepSeek:
            return AppSettings.defaultModel(for: .deepSeek)
        case .ollama, .openAICompatible:
            return L("Model name")
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
        Divider()
        SettingsLink {
            Text(L("Settings…"))
        }
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
        Toggle(L("Quick Translate"), isOn: settingsBinding(\.quickTranslateEnabled))
        Toggle(L("Auto Translate"), isOn: settingsBinding(\.autoTranslate))
        Toggle(L("Watch Clipboard"), isOn: settingsBinding(\.watchClipboard))
        Toggle(L("Auto Copy"), isOn: settingsBinding(\.autoCopy))
        Toggle(L("Auto Paste"), isOn: settingsBinding(\.autoPaste))
        Text(String(format: L("Shortcut: %@"), shortcutDisplay))
        Divider()
        Button(L("Quit Daisy")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
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

struct DaisyMenuBarLabel: View {
    @ObservedObject var model: DaisyModel

    var body: some View {
        HStack(spacing: LeafiyDesign.Spacing.xs) {
            if let image = NSImage.daisyAppIcon()?.leafiyMenuBarSized() {
                Image(nsImage: image)
                    .frame(width: LeafiyDesign.Size.menuBarIcon, height: LeafiyDesign.Size.menuBarIcon)
            }
            if let message = model.menuBarStatusText, !message.isEmpty {
                Text(message)
            }
        }
        .accessibilityLabel(Text(verbatim: "Daisy"))
    }
}

/// Frosted, behind-window blur used as the minimal-mode ghost backing.
private struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}
