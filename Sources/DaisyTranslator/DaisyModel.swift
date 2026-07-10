import Foundation
import SwiftUI
import DaisyTranslatorCore

@MainActor
final class DaisyModel: ObservableObject {
    @Published private(set) var settings: AppSettings = .defaults()
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var statusText = L("Ready")
    @Published var transientStatusMessage: String?
    @Published var isOnboardingPresented = false
    @Published private(set) var activeTranslationCount = 0
    /// Whether the minimal window is currently folded into the corner capsule.
    @Published private(set) var isMinimalCapsuleCollapsed = false

    var onSettingsChanged: ((AppSettings) -> Void)?
    var translateText: ((String, AppSettings) async throws -> String)?
    var writeClipboardText: ((String) -> Bool)?
    var pasteIntoFrontmostApp: ((String) async throws -> Void)?
    var ensurePastePermission: (() -> Bool)?
    var onTranslationActivityChanged: ((Bool) -> Void)?

    private var requestID = 0
    private var debounceTask: Task<Void, Never>?
    private var transientStatusClearTask: Task<Void, Never>?
    private let minimumDebounceMilliseconds = 150
    private let maximumDebounceMilliseconds = 1_200

    var menuBarStatusText: String? {
        if activeTranslationCount > 0 {
            return L("Translating…")
        }
        return transientStatusMessage
    }

    func replaceSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    func setMinimalCapsuleCollapsed(_ collapsed: Bool) {
        guard isMinimalCapsuleCollapsed != collapsed else { return }
        isMinimalCapsuleCollapsed = collapsed
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
            var copySucceeded = false
            if requestSettings.autoCopy {
                copySucceeded = writeClipboardText?(translated) ?? false
                showTransientStatus(copySucceeded ? L("Copied translation") : L("Copy failed. Copy manually."))
            }
            if requestSettings.autoPaste {
                guard ensurePastePermission?() ?? false else {
                    statusText = L("Auto paste requires Accessibility permission")
                    return
                }
                try await pasteIntoFrontmostApp?(translated)
                showTransientStatus(L("Auto pasted"))
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
                self.showTransientStatus(L("Pasted"))
            } catch {
                self.statusText = String(format: L("Paste failed: %@"), TranslationService.userFacingErrorMessage(error, provider: nil))
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
            onTranslationActivityChanged?(true)
        }
    }

    func endTranslation() {
        activeTranslationCount = max(0, activeTranslationCount - 1)
        if activeTranslationCount == 0 {
            onTranslationActivityChanged?(false)
        }
    }

    func showTransientStatus(_ message: String) {
        transientStatusClearTask?.cancel()
        transientStatusMessage = message
        transientStatusClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.transientStatusMessage = nil
            self?.transientStatusClearTask = nil
        }
    }
}
