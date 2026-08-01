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
    /// Whether the minimal window has faded to the frosted idle ghost.
    @Published private(set) var isMinimalIdleGhosted = false
    /// Phase of the menu-bar busy pulse, ticked by a task while translating.
    /// `MenuBarExtra` labels only re-render on published changes, so the
    /// animation must be driven from the model rather than a `TimelineView`.
    @Published private(set) var busyPulsePhase: Double = 0
    /// Corner dot on the menu-bar icon reporting the last outcome.
    @Published private(set) var menuBarDot: MenuBarDot?

    var onSettingsChanged: ((AppSettings) -> Void)?
    var translateText: ((String, AppSettings) async throws -> String)?
    var writeClipboardText: ((String) -> Bool)?
    var pasteIntoFrontmostApp: ((String) async throws -> Void)?
    var ensurePastePermission: (() -> Bool)?
    var onTranslationActivityChanged: ((Bool) -> Void)?
    /// Called with (source, translation, settings) after a translation
    /// succeeds, so the delegate can store it in the local history.
    var recordTranslation: ((String, String, AppSettings) -> Void)?

    private var requestID = 0
    private var debounceTask: Task<Void, Never>?
    private var transientStatusClearTask: Task<Void, Never>?
    private var busyPulseTask: Task<Void, Never>?
    private var menuBarDotClearTask: Task<Void, Never>?
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

    var isTranslating: Bool {
        activeTranslationCount > 0
    }

    func replaceSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    func setMinimalIdleGhosted(_ ghosted: Bool) {
        guard isMinimalIdleGhosted != ghosted else { return }
        isMinimalIdleGhosted = ghosted
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
