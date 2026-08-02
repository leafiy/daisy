import Foundation
import SwiftUI
import DaisyTranslatorCore

@MainActor
final class DaisyModel: ObservableObject {
    @Published private(set) var settings: AppSettings = .defaults()
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var statusText = L("Ready")
    @Published private(set) var transientStatus: TransientStatus?
    @Published var isOnboardingPresented = false
    @Published private(set) var activeTranslationCount = 0
    /// Phase of the menu-bar busy pulse, ticked by a task while translating.
    /// `MenuBarExtra` labels only re-render on published changes, so the
    /// animation must be driven from the model rather than a `TimelineView`.
    @Published private(set) var busyPulsePhase: Double = 0
    /// Corner dot on the menu-bar icon reporting the last outcome.
    @Published private(set) var menuBarDot: MenuBarDot?
    /// Outcome of the last `/api/tags` probe against the configured Ollama
    /// server. Drives the model picker in settings.
    @Published private(set) var ollamaModelDiscovery: OllamaModelDiscovery = .idle
    /// Strength of the frosted backdrop currently applied to the main
    /// window, derived from the transparency level by the app delegate.
    /// Mirrored here so minimal mode, which paints its own background, can
    /// step aside far enough to let the backdrop through.
    @Published private(set) var windowBlurIntensity: Double = 0

    var onSettingsChanged: ((AppSettings) -> Void)?
    var translateText: ((String, AppSettings) async throws -> String)?
    var writeClipboardText: ((String) -> Bool)?
    var pasteIntoFrontmostApp: ((String) async throws -> Void)?
    var ensurePastePermission: (() -> Bool)?
    var onTranslationActivityChanged: ((Bool) -> Void)?
    /// Called with (source, translation, settings) after a translation
    /// succeeds, so the delegate can store it in the local history.
    var recordTranslation: ((String, String, AppSettings) -> Void)?
    /// Lists the models installed on the configured Ollama server.
    var fetchOllamaModels: ((AppSettings) async throws -> [String])?
    /// Live alpha feedback while an opacity slider is dragged. Saving a
    /// settings change is comparatively expensive (disk I/O and hot-key
    /// re-registration), so the drag only previews and the value is
    /// persisted once, when the drag ends.
    var previewWindowOpacity: ((Double) -> Void)?

    private var requestID = 0
    private var debounceTask: Task<Void, Never>?
    private var transientStatusClearTask: Task<Void, Never>?
    private var busyPulseTask: Task<Void, Never>?
    private var menuBarDotClearTask: Task<Void, Never>?
    private var ollamaModelDiscoveryTask: Task<Void, Never>?
    private let minimumDebounceMilliseconds = 150
    private let maximumDebounceMilliseconds = 1_200

    struct TransientStatus: Equatable {
        enum Kind {
            case success
            case failure
        }

        let message: String
        let kind: Kind
    }

    struct MenuBarDot: Equatable {
        let kind: TransientStatus.Kind
        /// True for the first beat after appearing; drawn slightly oversized.
        let isPopped: Bool
    }

    enum OllamaModelDiscovery: Equatable {
        /// Ollama is not the active provider, or a remote address is missing.
        case idle
        case loading
        case loaded([String])
        /// A user-facing message from `TranslationService`.
        case failed(String)

        var models: [String] {
            if case let .loaded(models) = self { return models }
            return []
        }

        var isLoading: Bool {
            self == .loading
        }
    }

    var isTranslating: Bool {
        activeTranslationCount > 0
    }

    func replaceSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    func setWindowBlurIntensity(_ intensity: Double) {
        guard abs(windowBlurIntensity - intensity) > 0.001 else { return }
        windowBlurIntensity = intensity
    }

    func presentOnboardingIfNeeded() {
        guard !settings.onboardingCompleted else { return }
        isOnboardingPresented = true
    }

    func dismissOnboardingForNow() {
        isOnboardingPresented = false
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var next = settings
        mutate(&next)
        onSettingsChanged?(next)
    }

    func setProvider(_ provider: ModelProvider) {
        guard provider != settings.provider else { return }
        updateSettings { next in
            next.provider = provider
            let configuration = next.configuration(for: provider)
            next.baseURL = configuration.baseURL
            next.apiKey = configuration.apiKey
            next.model = configuration.model
        }
        if provider != .ollama {
            ollamaModelDiscovery = .idle
        }
    }

    func setProviderField(_ keyPath: WritableKeyPath<ProviderConfiguration, String>, to value: String) {
        updateSettings { next in
            var configuration = ProviderConfiguration(
                baseURL: next.baseURL,
                apiKey: next.apiKey,
                model: next.model
            )
            configuration[keyPath: keyPath] = value
            next.baseURL = configuration.baseURL
            next.apiKey = configuration.apiKey
            next.model = configuration.model
            next.providerConfigurations[next.provider.rawValue] = configuration
        }
    }

    func setOllamaConnection(_ connection: OllamaConnection) {
        guard connection != settings.ollamaConnection else { return }
        updateSettings { $0.ollamaConnection = connection }
    }

    /// Probes the configured Ollama server for installed models, replacing any
    /// probe still in flight. Pass a delay when reacting to typing so a remote
    /// address does not fire one request per keystroke.
    func refreshOllamaModels(afterMilliseconds delay: Int = 0) {
        ollamaModelDiscoveryTask?.cancel()
        let requestSettings = settings
        guard requestSettings.provider == .ollama,
              !requestSettings.effectiveBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let fetchOllamaModels else {
            ollamaModelDiscovery = .idle
            return
        }

        ollamaModelDiscoveryTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.ollamaModelDiscovery = .loading
            do {
                let models = try await fetchOllamaModels(requestSettings)
                guard !Task.isCancelled, self.settings.provider == .ollama else { return }
                self.ollamaModelDiscovery = .loaded(models)
                // Nothing chosen yet: adopt the first installed model so the
                // picker never starts on an empty selection.
                if self.settings.model.isEmpty, let first = models.first {
                    self.setProviderField(\.model, to: first)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.ollamaModelDiscovery = .failed(
                    TranslationService.userFacingErrorMessage(error, provider: .ollama)
                )
            }
        }
    }

    func completeOnboarding() {
        updateSettings { next in
            next.onboardingCompleted = true
        }
        isOnboardingPresented = false
    }

    func acceptClipboardText(_ text: String) {
        sourceText = text
        statusText = L("Read clipboard")
        scheduleTranslation()
    }

    func retryCurrentText() {
        translateCurrentText()
    }

    func sourceTextDidChange() {
        requestID += 1
        scheduleTranslation(waitingForInputToStop: true)
    }

    func scheduleTranslation(waitingForInputToStop: Bool = false) {
        debounceTask?.cancel()
        guard settings.autoTranslate else { return }
        let configuredDelay = min(
            max(settings.debounceMilliseconds, minimumDebounceMilliseconds),
            maximumDebounceMilliseconds
        )
        let delayMilliseconds = waitingForInputToStop ? maximumDebounceMilliseconds : configuredDelay
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delayMilliseconds) * 1_000_000)
            guard !Task.isCancelled else { return }
            await self?.translateCurrentTextAsync()
        }
    }

    func translateCurrentText() {
        Task { @MainActor [weak self] in
            await self?.translateCurrentTextAsync()
        }
    }

    private func translateCurrentTextAsync() async {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        requestID += 1
        let currentRequestID = requestID

        guard !text.isEmpty else {
            translatedText = ""
            statusText = L("Ready")
            return
        }
        guard let translateText else {
            statusText = L("Translation service is not ready")
            return
        }

        let requestSettings = settings
        statusText = L("Translating…")
        beginTranslation()
        defer { endTranslation() }

        do {
            let translated = try await translateText(text, requestSettings)
            guard currentRequestID == requestID else { return }
            translatedText = translated
            recordTranslation?(text, translated, requestSettings)
            flashMenuBarDot(.success)
            var copySucceeded = false
            if requestSettings.autoCopy {
                copySucceeded = writeClipboardText?(translated) ?? false
                showTransientStatus(
                    copySucceeded ? L("Copied translation") : L("Copy failed. Copy manually."),
                    kind: copySucceeded ? .success : .failure
                )
            }
            if requestSettings.autoPaste {
                guard ensurePastePermission?() ?? false else {
                    statusText = L("Auto paste requires Accessibility permission")
                    flashMenuBarDot(.failure)
                    return
                }
                try await pasteIntoFrontmostApp?(translated)
                showTransientStatus(L("Auto pasted"), kind: .success)
            }
            if requestSettings.autoCopy {
                statusText = copySucceeded ? L("Completed and copied") : L("Completed, copy failed")
            } else {
                statusText = L("Completed")
            }
        } catch {
            guard currentRequestID == requestID else { return }
            translatedText = ""
            statusText = TranslationService.userFacingErrorMessage(error, provider: requestSettings.provider)
            flashMenuBarDot(.failure)
        }
    }

    func pasteResult() {
        let result = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard self.ensurePastePermission?() ?? false else { return }
                try await self.pasteIntoFrontmostApp?(result)
                self.statusText = L("Pasted")
                self.showTransientStatus(L("Pasted"), kind: .success)
            } catch {
                self.statusText = String(format: L("Paste failed: %@"), TranslationService.userFacingErrorMessage(error, provider: nil))
                self.flashMenuBarDot(.failure)
            }
        }
    }

    func clear() {
        sourceText = ""
        translatedText = ""
        statusText = L("Ready")
    }

    func beginTranslation() {
        let wasIdle = activeTranslationCount == 0
        activeTranslationCount += 1
        if wasIdle {
            menuBarDotClearTask?.cancel()
            menuBarDot = nil
            startBusyPulse()
            onTranslationActivityChanged?(true)
        }
    }

    func endTranslation() {
        activeTranslationCount = max(0, activeTranslationCount - 1)
        if activeTranslationCount == 0 {
            stopBusyPulse()
            onTranslationActivityChanged?(false)
        }
    }

    func showTransientStatus(_ message: String, kind: TransientStatus.Kind) {
        transientStatusClearTask?.cancel()
        transientStatus = TransientStatus(message: message, kind: kind)
        flashMenuBarDot(kind)
        transientStatusClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.transientStatus = nil
            self?.transientStatusClearTask = nil
        }
    }

    /// Shows the outcome dot: pops in slightly oversized, settles after a
    /// beat, and disappears on its own 10 seconds later.
    func flashMenuBarDot(_ kind: TransientStatus.Kind) {
        menuBarDotClearTask?.cancel()
        menuBarDot = MenuBarDot(kind: kind, isPopped: true)
        menuBarDotClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self, !Task.isCancelled else { return }
            self.menuBarDot = MenuBarDot(kind: kind, isPopped: false)
            try? await Task.sleep(nanoseconds: 9_800_000_000)
            guard !Task.isCancelled else { return }
            self.menuBarDot = nil
            self.menuBarDotClearTask = nil
        }
    }

    private func startBusyPulse() {
        busyPulseTask?.cancel()
        busyPulsePhase = 0
        busyPulseTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, !Task.isCancelled else { return }
                self.busyPulsePhase = (self.busyPulsePhase + 30).truncatingRemainder(dividingBy: 360)
            }
        }
    }

    private func stopBusyPulse() {
        busyPulseTask?.cancel()
        busyPulseTask = nil
        busyPulsePhase = 0
    }
}
