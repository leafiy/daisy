import Foundation
import SwiftUI
import DaisyTranslatorCore

@MainActor
final class DaisyModel: ObservableObject {
    @Published private(set) var settings: AppSettings = .defaults()
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var statusText = "就绪"
    @Published var transientStatusMessage: String?
    @Published var isOnboardingPresented = false
    @Published private(set) var activeTranslationCount = 0

    var onSettingsChanged: ((AppSettings) -> Void)?
    var translateText: ((String, AppSettings) async throws -> String)?
    var readClipboardText: (() -> String)?
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
            return "翻译中…"
        }
        return transientStatusMessage
    }

    func replaceSettings(_ settings: AppSettings) {
        self.settings = settings
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
        statusText = "已读取剪贴板"
        scheduleTranslation()
    }

    func pullClipboardAndTranslate() {
        let text = readClipboardText?() ?? ""
        guard !text.isEmpty else {
            statusText = "剪贴板为空"
            return
        }
        sourceText = text
        translateCurrentText()
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
            statusText = "就绪"
            return
        }
        guard let translateText else {
            statusText = "翻译服务未就绪"
            return
        }

        let requestSettings = settings
        statusText = "翻译中…"
        beginTranslation()
        defer { endTranslation() }

        do {
            let translated = try await translateText(text, requestSettings)
            guard currentRequestID == requestID else { return }
            translatedText = translated
            var copySucceeded = false
            if requestSettings.autoCopy {
                copySucceeded = writeClipboardText?(translated) ?? false
                showTransientStatus(copySucceeded ? "已复制译文" : "复制失败，请手动复制")
            }
            if requestSettings.autoPaste {
                guard ensurePastePermission?() ?? false else {
                    statusText = "自动粘贴需要辅助功能权限"
                    return
                }
                try await pasteIntoFrontmostApp?(translated)
                showTransientStatus("已自动粘贴")
            }
            if requestSettings.autoCopy {
                statusText = copySucceeded ? "已完成并复制" : "已完成，复制失败"
            } else {
                statusText = "已完成"
            }
        } catch {
            guard currentRequestID == requestID else { return }
            translatedText = ""
            statusText = TranslationService.userFacingErrorMessage(error, provider: requestSettings.provider)
        }
    }

    func copyResult() {
        let result = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return }
        if writeClipboardText?(result) == true {
            statusText = "已复制"
            showTransientStatus("已复制")
        } else {
            statusText = "复制失败"
            showTransientStatus("复制失败，请重试")
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
                self.statusText = "已粘贴"
                self.showTransientStatus("已粘贴")
            } catch {
                self.statusText = "粘贴失败：\(TranslationService.userFacingErrorMessage(error, provider: nil))"
            }
        }
    }

    func clear() {
        sourceText = ""
        translatedText = ""
        statusText = "就绪"
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
