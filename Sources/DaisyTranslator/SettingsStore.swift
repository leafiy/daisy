import Foundation
import DaisyTranslatorCore

final class SettingsStore {
    private let fileURL: URL
    private let defaultSettings: AppSettings
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        defaultSettings: AppSettings = .defaults(),
        fileURL: URL? = nil
    ) {
        self.defaultSettings = defaultSettings
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.fileURL = fileURL ?? applicationSupport
            .appendingPathComponent("DaisyTranslator", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    var hasSavedSettings: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func load() -> AppSettings {
        do {
            let data = try Data(contentsOf: fileURL)
            let stored = try decoder.decode(AppSettings.self, from: data)
            return merged(stored, with: defaultSettings)
        } catch {
            return defaultSettings
        }
    }

    func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }

    private func merged(_ stored: AppSettings, with defaults: AppSettings) -> AppSettings {
        let providerDefaultBaseURL = AppSettings.defaultBaseURL(for: stored.provider)
        let providerDefaultModel = AppSettings.defaultModel(for: stored.provider)
        var providerConfigurations = AppSettings.defaultProviderConfigurations()
        providerConfigurations.merge(stored.providerConfigurations) { _, storedConfiguration in
            storedConfiguration
        }
        if stored.providerConfigurations[stored.provider.rawValue] == nil {
            providerConfigurations[stored.provider.rawValue] = ProviderConfiguration(
                baseURL: stored.baseURL.isEmpty ? providerDefaultBaseURL : stored.baseURL,
                apiKey: stored.apiKey,
                model: stored.model.isEmpty ? providerDefaultModel : stored.model
            )
        }
        let activeConfiguration = providerConfigurations[stored.provider.rawValue]
            ?? AppSettings.defaultConfiguration(for: stored.provider)

        return AppSettings(
            baseURL: activeConfiguration.baseURL.isEmpty ? providerDefaultBaseURL : activeConfiguration.baseURL,
            apiKey: activeConfiguration.apiKey,
            model: activeConfiguration.model.isEmpty ? providerDefaultModel : activeConfiguration.model,
            providerConfigurations: providerConfigurations,
            ollamaConnection: stored.ollamaConnection,
            temperature: stored.temperature == 0 ? defaults.temperature : stored.temperature,
            topP: stored.topP == 0 ? defaults.topP : stored.topP,
            maxTokens: stored.maxTokens == 0 ? defaults.maxTokens : stored.maxTokens,
            debounceMilliseconds: stored.debounceMilliseconds == 0 ? defaults.debounceMilliseconds : stored.debounceMilliseconds,
            autoTranslate: stored.autoTranslate,
            watchClipboard: stored.watchClipboard,
            autoCopy: stored.autoCopy,
            autoPaste: stored.autoPaste,
            alwaysOnTop: stored.alwaysOnTop,
            minimalMode: stored.minimalMode,
            windowOpacityEnabled: stored.windowOpacityEnabled,
            focusedWindowOpacity: stored.focusedWindowOpacity,
            unfocusedWindowOpacity: stored.unfocusedWindowOpacity,
            quickTranslateEnabled: stored.quickTranslateEnabled,
            quickTranslateShortcut: stored.quickTranslateShortcut.isEmpty ? defaults.quickTranslateShortcut : stored.quickTranslateShortcut,
            quickTranslateAutoCopy: stored.quickTranslateAutoCopy,
            provider: stored.provider,
            targetLanguage: stored.targetLanguage,
            onboardingCompleted: stored.onboardingCompleted,
            appLanguage: stored.appLanguage.isEmpty ? defaults.appLanguage : stored.appLanguage,
            launchAtLogin: stored.launchAtLogin
        )
    }
}
