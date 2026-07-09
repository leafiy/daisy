import AppKit
import ApplicationServices
import Foundation
import SwiftUI
import DaisyTranslatorCore
import LeafiyUICore
#if canImport(Translation)
import Translation
#endif

@main
struct DaisyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        LeafiyLocalization.language = SettingsStore().load().selectedAppLanguage
        if CommandLine.arguments.contains("--self-test") {
            SelfTest.run()
            Foundation.exit(0)
        }
    }

    var body: some Scene {
        Window("Daisy", id: "main") {
            TranslatorView(
                model: appDelegate.model,
                appleTranslationBridge: appDelegate.appleTranslationService.bridgeView()
            )
            .onAppear {
                appDelegate.applyWindowBehavior()
            }
            .id(appDelegate.model.settings.selectedAppLanguage.rawValue)
        }
        .defaultSize(width: 620, height: 560)

        Settings {
            DaisySettingsView(model: appDelegate.model)
                .id(appDelegate.model.settings.selectedAppLanguage.rawValue)
        }

        MenuBarExtra {
            DaisyMenuBarMenu(model: appDelegate.model, appDelegate: appDelegate)
                .id(appDelegate.model.settings.selectedAppLanguage.rawValue)
        } label: {
            DaisyMenuBarLabel(model: appDelegate.model)
                .id(appDelegate.model.settings.selectedAppLanguage.rawValue)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = DaisyModel()
    let appleTranslationService = AppleSystemTranslationService()

    private let settingsStore = SettingsStore()
    private let translationService = TranslationService()
    private let pasteboardService = PasteboardService()
    private let hotKeyCenter = HotKeyCenter()
    private let quickTranslatePopup = QuickTranslatePopupController()

    private var clipboardTimer: Timer?
    private var lastClipboardText = ""
    private var clipboardShortcutTask: Task<Void, Never>?
    private var isClipboardWatcherPaused = false
    private var translationBridgeHostWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let shouldShowOnboarding = !settingsStore.hasSavedSettings
        let loadedSettings = normalized(settingsStore.load())
        LeafiyLocalization.language = loadedSettings.selectedAppLanguage
        model.statusText = L("Ready")
        model.replaceSettings(loadedSettings)
        configureModelCallbacks()
        configureQuickTranslatePopup()
        installTranslationBridgeHost()
        updateClipboardWatcher()
        registerHotKeys()
        prepareAppleSystemTranslationIfNeeded()
        applyWindowBehavior()
        NSApp.activate(ignoringOtherApps: true)
        if shouldShowOnboarding || !loadedSettings.onboardingCompleted {
            model.presentOnboardingIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardTimer?.invalidate()
        clipboardShortcutTask?.cancel()
        hotKeyCenter.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// The Apple-translation bridge inside TranslatorView dies with the main
    /// window when the user closes it (the SwiftUI Window scene tears down
    /// its content), which would stall menu-bar/hotkey quick translation on
    /// the Apple provider until the window reopens. This invisible utility
    /// window hosts a second bridge view sharing the same serialized request
    /// model, so a translation session is always reachable; the model's
    /// take-once guard keeps the two hosts from double-running a request.
    private func installTranslationBridgeHost() {
        let hostingView = NSHostingView(rootView: appleTranslationService.bridgeView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.collectionBehavior = [.ignoresCycle, .stationary]
        window.contentView = hostingView
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        translationBridgeHostWindow = window
    }

    var isMainWindowVisible: Bool {
        findMainWindow()?.isVisible == true
    }

    func toggleMainWindow(openWindow: OpenWindowAction) {
        if let window = findMainWindow(), window.isVisible {
            window.orderOut(nil)
        } else {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                self.findMainWindow()?.makeKeyAndOrderFront(nil)
                self.applyWindowBehavior()
            }
        }
    }

    func applyWindowBehavior() {
        guard let window = findMainWindow() else { return }
        if model.settings.alwaysOnTop {
            window.level = .floating
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        } else {
            window.level = .normal
            window.collectionBehavior.remove([.canJoinAllSpaces, .fullScreenAuxiliary])
        }
        applyMinimalModeChrome(to: window)
    }

    /// In minimal mode the window sheds its chrome: traffic lights vanish,
    /// the title bar goes transparent and title-less, and the whole surface
    /// becomes draggable. Standard mode restores all of it.
    private func applyMinimalModeChrome(to window: NSWindow) {
        let minimal = model.settings.minimalMode
        window.standardWindowButton(.closeButton)?.isHidden = minimal
        window.standardWindowButton(.miniaturizeButton)?.isHidden = minimal
        window.standardWindowButton(.zoomButton)?.isHidden = minimal
        window.titleVisibility = minimal ? .hidden : .visible
        window.titlebarAppearsTransparent = minimal
        window.isMovableByWindowBackground = minimal
    }

    private func configureModelCallbacks() {
        model.onSettingsChanged = { [weak self] nextSettings in
            self?.saveSettings(nextSettings)
        }
        model.translateText = { [weak self] text, settings in
            guard let self else { return "" }
            return try await self.translate(text, settings: settings)
        }
        model.writeClipboardText = { [weak self] text in
            self?.pasteboardService.writeText(text) ?? false
        }
        model.pasteIntoFrontmostApp = { [weak self] text in
            guard let self else { return }
            try await self.pasteboardService.pasteIntoFrontmostApp(text, hiding: self.findMainWindow())
        }
        model.ensurePastePermission = { [weak self] in
            self?.ensureAccessibilityPermission() ?? false
        }
        model.onTranslationActivityChanged = { [weak self] isActive in
            self?.translationActivityChanged(isActive)
        }
    }

    private func saveSettings(_ nextSettings: AppSettings) {
        let previousSettings = model.settings
        let normalizedSettings = normalized(nextSettings)
        model.replaceSettings(normalizedSettings)
        do {
            try settingsStore.save(normalizedSettings)
            LeafiyLocalization.language = normalizedSettings.selectedAppLanguage
            applyWindowBehavior()
            updateClipboardWatcher()
            registerHotKeys()
            prepareAppleSystemTranslationIfNeeded()
            if shouldRetryTranslation(afterChangingFrom: previousSettings, to: normalizedSettings) {
                model.retryCurrentText()
            }
        } catch {
            model.statusText = L("Failed to save. Check settings file permissions.")
        }
    }

    private func normalized(_ settings: AppSettings) -> AppSettings {
        var normalized = settings
        var providerConfigurations = AppSettings.defaultProviderConfigurations()
        providerConfigurations.merge(normalized.providerConfigurations) { _, savedConfiguration in
            savedConfiguration
        }
        let activeConfiguration = normalizedServiceConfiguration(
            ProviderConfiguration(
                baseURL: normalized.baseURL,
                apiKey: normalized.apiKey,
                model: normalized.model
            ),
            for: normalized.provider
        )
        providerConfigurations[normalized.provider.rawValue] = activeConfiguration
        normalized.providerConfigurations = providerConfigurations
        normalized.baseURL = activeConfiguration.baseURL
        normalized.apiKey = activeConfiguration.apiKey
        normalized.model = activeConfiguration.model
        if AppLanguage(rawValue: normalized.appLanguage) == nil {
            normalized.appLanguage = AppLanguage.system.rawValue
        }
        return normalized
    }

    private func shouldRetryTranslation(afterChangingFrom oldSettings: AppSettings, to newSettings: AppSettings) -> Bool {
        oldSettings.provider != newSettings.provider ||
            oldSettings.baseURL != newSettings.baseURL ||
            oldSettings.apiKey != newSettings.apiKey ||
            oldSettings.model != newSettings.model ||
            oldSettings.targetLanguage != newSettings.targetLanguage
    }

    private func updateClipboardWatcher() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        guard model.settings.watchClipboard else { return }

        lastClipboardText = pasteboardService.readText()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.isClipboardWatcherPaused else { return }
                let current = self.pasteboardService.readText()
                guard !current.isEmpty,
                      current != self.lastClipboardText,
                      current != self.pasteboardService.lastProgrammaticText else {
                    return
                }
                self.lastClipboardText = current
                self.model.acceptClipboardText(current)
            }
        }
    }

    private func translationActivityChanged(_ isActive: Bool) {
        if isActive {
            isClipboardWatcherPaused = true
            return
        }
        isClipboardWatcherPaused = false
        lastClipboardText = pasteboardService.readText()
    }

    private func registerHotKeys() {
        hotKeyCenter.onHotKey = { [weak self] hotKey in
            guard let self else { return }
            switch hotKey {
            case .quickTranslateSelection:
                self.translateSelectionWithoutWindow()
            case .toggleAlwaysOnTop:
                self.model.updateSettings { $0.alwaysOnTop.toggle() }
            }
        }
        hotKeyCenter.register(
            quickTranslateEnabled: model.settings.quickTranslateEnabled,
            quickTranslateShortcut: model.settings.quickTranslateShortcut
        )
    }

    private func configureQuickTranslatePopup() {
        quickTranslatePopup.onAutoCopyChanged = { [weak self] enabled, text in
            guard let self else { return }
            self.model.updateSettings { $0.quickTranslateAutoCopy = enabled }
            guard enabled else { return }
            self.showStatusMessage(self.pasteboardService.writeText(text) ? L("Copied") : L("Copy failed. Try again."))
        }
    }

    private func translateSelectionWithoutWindow() {
        guard ensureAccessibilityPermission() else { return }
        let anchor = QuickTranslatePopupController.currentSelectionRect()
        startQuickTranslation(above: anchor) { [pasteboardService] in
            let selection = try await pasteboardService.copySelectedTextFromFrontmostApp()?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let selection, !selection.isEmpty else { return nil }
            return selection
        }
    }

    private func startQuickTranslation(
        above anchor: NSRect?,
        _ makeSourceText: @escaping @MainActor () async throws -> String?
    ) {
        clipboardShortcutTask?.cancel()
        let settingsSnapshot = model.settings
        clipboardShortcutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.model.beginTranslation()
            defer { self.model.endTranslation() }
            do {
                guard let text = try await makeSourceText() else {
                    self.showStatusMessage(L("No text selected"))
                    return
                }
                guard !Task.isCancelled else { return }
                let translated = try await self.translate(text, settings: settingsSnapshot)
                guard !Task.isCancelled else { return }
                let autoCopy = settingsSnapshot.quickTranslateAutoCopy
                if autoCopy, !self.pasteboardService.writeText(translated) {
                    self.showStatusMessage(L("Translation completed, but copy failed. Try again."))
                }
                self.quickTranslatePopup.show(text: translated, autoCopyEnabled: autoCopy, above: anchor)
            } catch {
                guard !Task.isCancelled else { return }
                let message = String(
                    TranslationService.userFacingErrorMessage(error, provider: settingsSnapshot.provider).prefix(40)
                )
                self.showStatusMessage(String(format: L("Translation failed: %@"), message))
            }
        }
    }

    private func translate(_ text: String, settings: AppSettings) async throws -> String {
        if settings.provider == .appleSystem {
            return try await appleTranslationService.translate(text, targetLanguage: settings.targetLanguage)
        }
        return try await translationService.translate(text, settings: settings)
    }

    private func prepareAppleSystemTranslationIfNeeded() {
        guard model.settings.provider == .appleSystem else { return }
        Task { @MainActor in
            try? await appleTranslationService.prepareEnglishChinese()
        }
    }

    private func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let alert = NSAlert()
        alert.messageText = L("Allow Daisy to control the keyboard")
        alert.informativeText = L("Quick translate needs to send Cmd+C to read selected text, and auto paste needs to send Cmd+V. Both require macOS Accessibility permission.\n\nIf Daisy is already enabled in the list but this prompt still appears, the authorization was invalidated by rebuilding the app. Remove Daisy from the Accessibility list with “−”, then add it again.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("Open System Settings"))
        alert.addButton(withTitle: L("Later"))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        return AXIsProcessTrusted()
    }

    private func showStatusMessage(_ message: String) {
        model.showTransientStatus(message)
    }

    private func findMainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            !(window is NSPanel) && window.title == "Daisy"
        } ?? NSApp.windows.first { window in
            !(window is NSPanel) && window.isVisible
        }
    }
}

@MainActor
final class AppleSystemTranslationService {
    private var implementation: Any?

    func bridgeView() -> AnyView {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            let implementation = appleImplementation()
            return AnyView(AppleSystemTranslationBridgeView(model: implementation.model))
        }
        #endif
        return AnyView(EmptyView())
    }

    func translate(_ text: String, targetLanguage: TargetLanguage) async throws -> String {
        #if canImport(Translation)
        guard #available(macOS 15.0, *) else {
            throw DaisyTranslatorCore.TranslationError.appleSystemTranslationUnavailable
        }
        return try await appleImplementation().translate(text, targetLanguage: targetLanguage)
        #else
        throw DaisyTranslatorCore.TranslationError.appleSystemTranslationUnavailable
        #endif
    }

    func prepareEnglishChinese() async throws {
        #if canImport(Translation)
        guard #available(macOS 15.0, *) else { return }
        try await appleImplementation().prepareEnglishChinese()
        #endif
    }

    #if canImport(Translation)
    @available(macOS 15.0, *)
    private func appleImplementation() -> AppleSystemTranslationImplementation {
        if let implementation = implementation as? AppleSystemTranslationImplementation {
            return implementation
        }
        let implementation = AppleSystemTranslationImplementation()
        self.implementation = implementation
        return implementation
    }
    #endif
}

#if canImport(Translation)
@available(macOS 15.0, *)
@MainActor
private final class AppleSystemTranslationImplementation {
    let model = AppleSystemTranslationBridgeModel()
    private let availability = LanguageAvailability()

    func translate(_ text: String, targetLanguage: TargetLanguage) async throws -> String {
        let target = await supportedLanguage(for: targetLanguageIdentifier(for: text, targetLanguage: targetLanguage))
        var source = await detectedSourceLanguage(for: text)
        if let detected = source, detected.languageCode == target.languageCode {
            source = nil
        }
        if let source {
            guard await isAvailable(source: source, target: target) else {
                throw DaisyTranslatorCore.TranslationError.appleSystemTranslationUnsupported
            }
        } else {
            try await ensureAvailable(text: text, target: target)
        }
        return try await model.translate(text, source: source, target: target)
    }

    func prepareEnglishChinese() async throws {
        let english = await supportedLanguage(for: "en")
        let chinese = await supportedLanguage(for: "zh-Hans")
        guard await isAvailable(source: english, target: chinese),
              await isAvailable(source: chinese, target: english) else {
            throw DaisyTranslatorCore.TranslationError.appleSystemTranslationUnsupported
        }
        try await model.prepare(source: english, target: chinese)
        try await model.prepare(source: chinese, target: english)
    }

    private func targetLanguageIdentifier(
        for text: String,
        targetLanguage: TargetLanguage
    ) -> String {
        TranslationService.translatesToEnglish(source: text, preference: targetLanguage)
            ? "en"
            : "zh-Hans"
    }

    private func supportedLanguage(for identifier: String) async -> Locale.Language {
        let preferred = Locale.Language(identifier: identifier)
        let supportedLanguages = await availability.supportedLanguages
        if let exact = supportedLanguages.first(where: { $0 == preferred }) {
            return exact
        }
        if let languageCode = preferred.languageCode {
            if let sameScript = supportedLanguages.first(where: {
                $0.languageCode == languageCode && $0.script == preferred.script
            }) {
                return sameScript
            }
            if let sameLanguage = supportedLanguages.first(where: { $0.languageCode == languageCode }) {
                return sameLanguage
            }
        }
        return preferred
    }

    private func detectedSourceLanguage(for text: String) async -> Locale.Language? {
        if Self.containsChineseText(text) {
            return await supportedLanguage(for: "zh-Hans")
        }
        if Self.containsLatinText(text) {
            return await supportedLanguage(for: "en")
        }
        return nil
    }

    private func isAvailable(source: Locale.Language, target: Locale.Language) async -> Bool {
        switch await availability.status(from: source, to: target) {
        case .installed, .supported:
            return true
        case .unsupported:
            return false
        @unknown default:
            return false
        }
    }

    private func ensureAvailable(text: String, target: Locale.Language) async throws {
        guard let status = try? await availability.status(for: text, to: target) else {
            return
        }
        switch status {
        case .installed, .supported:
            return
        case .unsupported:
            throw DaisyTranslatorCore.TranslationError.appleSystemTranslationUnsupported
        @unknown default:
            return
        }
    }

    private static func containsChineseText(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) }
    }

    private static func containsLatinText(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x0041...0x005a).contains($0.value) || (0x0061...0x007a).contains($0.value)
        }
    }
}

@available(macOS 15.0, *)
@MainActor
private final class AppleSystemTranslationBridgeModel: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    private var queue: [PendingRequest] = []
    private var active: PendingRequest?
    private var timeoutTask: Task<Void, Never>?
    private var nextRequestID = 0

    func translate(_ text: String, source: Locale.Language?, target: Locale.Language) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(kind: .translate(text), source: source, target: target, continuation: continuation)
        }
    }

    func prepare(source: Locale.Language?, target: Locale.Language) async throws {
        let _: String = try await withCheckedThrowingContinuation { continuation in
            enqueue(kind: .prepare, source: source, target: target, continuation: continuation)
        }
    }

    private func enqueue(
        kind: PendingRequest.Kind,
        source: Locale.Language?,
        target: Locale.Language,
        continuation: CheckedContinuation<String, Error>
    ) {
        nextRequestID += 1
        let request = PendingRequest(
            id: nextRequestID,
            kind: kind,
            source: source,
            target: target,
            continuation: continuation
        )
        if request.isTranslate {
            for queued in queue where queued.isTranslate {
                queued.finish(throwing: CancellationError())
            }
            queue.removeAll { $0.isFinished }
            if let active, active.isTranslate {
                active.finish(throwing: CancellationError())
            }
        }
        queue.append(request)
        pump()
    }

    private func pump() {
        guard active == nil else { return }
        while let request = queue.first, request.isFinished {
            queue.removeFirst()
        }
        guard !queue.isEmpty else { return }
        let request = queue.removeFirst()
        active = request
        startTimeout(for: request.id)
        if var current = configuration,
           current.source == request.source,
           current.target == request.target {
            current.invalidate()
            configuration = current
        } else {
            configuration = TranslationSession.Configuration(source: request.source, target: request.target)
        }
    }

    func run(session: TranslationSession) async {
        guard !Task.isCancelled else { return }
        guard let request = active, !request.isTaken else { return }
        if request.isFinished {
            resolveActive(request.id)
            return
        }
        request.isTaken = true
        do {
            try await session.prepareTranslation()
            switch request.kind {
            case .prepare:
                complete(requestID: request.id, result: "")
            case let .translate(text):
                let response = try await session.translate(text)
                let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translated.isEmpty else { throw DaisyTranslatorCore.TranslationError.missingTranslatedText }
                complete(requestID: request.id, result: translated)
            }
        } catch {
            fail(requestID: request.id, error: normalizedError(error))
        }
    }

    private func normalizedError(_ error: Error) -> Error {
        if error is CancellationError {
            return error
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let containsChinese = message.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) }
        if message.isEmpty || message == "Unable to Translate" || !containsChinese {
            return DaisyTranslatorCore.TranslationError.appleSystemTranslationFailed(L("The system could not complete this translation. Make sure the source text language and target language are different and that the language packs are downloaded."))
        }
        return DaisyTranslatorCore.TranslationError.appleSystemTranslationFailed(message)
    }

    private func complete(requestID: Int, result: String) {
        guard let request = active, request.id == requestID else { return }
        request.finish(returning: result)
        resolveActive(requestID)
    }

    private func fail(requestID: Int, error: Error) {
        guard let request = active, request.id == requestID else { return }
        request.finish(throwing: error)
        resolveActive(requestID)
    }

    private func resolveActive(_ requestID: Int) {
        guard active?.id == requestID else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        active = nil
        pump()
    }

    private func startTimeout(for requestID: Int) {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled else { return }
            self?.fail(
                requestID: requestID,
                error: DaisyTranslatorCore.TranslationError.appleSystemTranslationFailed(L("System translation timed out. Try again later."))
            )
        }
    }

    private final class PendingRequest {
        enum Kind {
            case prepare
            case translate(String)
        }

        let id: Int
        let kind: Kind
        let source: Locale.Language?
        let target: Locale.Language
        var isTaken = false
        private(set) var isFinished = false
        private var continuation: CheckedContinuation<String, Error>?

        init(
            id: Int,
            kind: Kind,
            source: Locale.Language?,
            target: Locale.Language,
            continuation: CheckedContinuation<String, Error>
        ) {
            self.id = id
            self.kind = kind
            self.source = source
            self.target = target
            self.continuation = continuation
        }

        var isTranslate: Bool {
            if case .translate = kind { return true }
            return false
        }

        func finish(returning result: String) {
            guard !isFinished else { return }
            isFinished = true
            continuation?.resume(returning: result)
            continuation = nil
        }

        func finish(throwing error: Error) {
            guard !isFinished else { return }
            isFinished = true
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

@available(macOS 15.0, *)
private struct AppleSystemTranslationBridgeView: View {
    @ObservedObject var model: AppleSystemTranslationBridgeModel

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(model.configuration) { session in
                await model.run(session: session)
            }
    }
}
#endif

enum SelfTest {
    static func run() {
        do {
            let settings = AppSettings.defaults(environment: ["TT_PROVIDER": ModelProvider.deepSeek.rawValue])
            _ = try TranslationService.makeRequest(source: "hello", settings: settings)
            let url = try TranslationService.resolveChatURL("http://localhost:11434/v1")
            guard url.absoluteString == "http://localhost:11434/v1/chat/completions" else { throw SelfTestError.urlResolution }
            let googleURL = try TranslationService.resolveGoogleFreeTranslateURL("https://translate.googleapis.com/", target: "en", query: "hi")
            guard googleURL.absoluteString == "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=t&q=hi" else { throw SelfTestError.urlResolution }
            let baiduURL = try TranslationService.resolveBaiduTranslateURL("https://fanyi-api.baidu.com/")
            guard baiduURL.absoluteString == "https://fanyi-api.baidu.com/ait/api/aiTextTranslate" else { throw SelfTestError.urlResolution }
            guard TranslationService.baiduSignature(appID: "2015063000000001", query: "apple", salt: "1435660288", secret: "12345678") == "f89f9594663708c1605f3d736d01d2d4" else { throw SelfTestError.urlResolution }
            guard let icon = NSImage.daisyAppIcon(),
                  let representation = icon.representations.first,
                  representation.pixelsWide >= 128,
                  representation.pixelsHigh >= 128 else {
                throw SelfTestError.iconResource
            }
            print("self-test passed")
        } catch {
            fputs("self-test failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

enum SelfTestError: LocalizedError {
    case iconResource
    case urlResolution

    var errorDescription: String? {
        switch self {
        case .iconResource:
            return "icon resource failed"
        case .urlResolution:
            return "chat URL resolution failed"
        }
    }
}
