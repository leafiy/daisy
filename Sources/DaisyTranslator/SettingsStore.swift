import Foundation
import DaisyTranslatorCore

final class SettingsStore {
    private let fileURL: URL
    private let defaultSettings: AppSettings
    private let secrets: KeychainSecretStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        defaultSettings: AppSettings = .defaults()
    ) {
        self.defaultSettings = defaultSettings
        self.secrets = KeychainSecretStore()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.fileURL = applicationSupport
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
            let hydratedSettings = hydrated(stored)
            try? save(hydratedSettings)
            return merged(hydratedSettings, with: defaultSettings)
        } catch {
            return defaultSettings
        }
    }

    func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var persisted = settings
        try persistSecrets(from: settings)
        persisted.apiKey = ""
        persisted.providerConfigurations = persisted.providerConfigurations.mapValues { configuration in
            ProviderConfiguration(baseURL: configuration.baseURL, apiKey: "", model: configuration.model)
        }
        let data = try encoder.encode(persisted)
        try data.write(to: fileURL, options: .atomic)
    }

    private func hydrated(_ settings: AppSettings) -> AppSettings {
        var hydrated = settings
        var configurations = hydrated.providerConfigurations
        for provider in ModelProvider.allCases {
            let key = provider.rawValue
            var configuration = configurations[key] ?? AppSettings.defaultConfiguration(for: provider)
            let legacy = configuration.apiKey.isEmpty && provider == hydrated.provider ? hydrated.apiKey : configuration.apiKey
            do {
                if let stored = try secrets.read(account: key) {
                    configuration.apiKey = stored
                } else if !legacy.isEmpty {
                    try secrets.write(legacy, account: key)
                    configuration.apiKey = legacy
                } else {
                    configuration.apiKey = ""
                }
            } catch {
                NSLog("Daisy: failed to access Keychain for %@: %@", key, String(describing: error))
                configuration.apiKey = legacy
            }
            configurations[key] = configuration
        }
        hydrated.providerConfigurations = configurations
        hydrated.apiKey = configurations[hydrated.provider.rawValue]?.apiKey ?? hydrated.apiKey
        return hydrated
    }

    private func persistSecrets(from settings: AppSettings) throws {
        for provider in ModelProvider.allCases {
            let key = provider.rawValue
            let value = settings.providerConfigurations[key]?.apiKey
                ?? (provider == settings.provider ? settings.apiKey : "")
            if value.isEmpty {
                try secrets.remove(account: key)
            } else {
                try secrets.write(value, account: key)
            }
        }
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
            minimalIdleGhostEnabled: stored.minimalIdleGhostEnabled,
            quickTranslateEnabled: stored.quickTranslateEnabled,
            quickTranslateShortcut: stored.quickTranslateShortcut.isEmpty ? defaults.quickTranslateShortcut : stored.quickTranslateShortcut,
            quickTranslateAutoCopy: stored.quickTranslateAutoCopy,
            provider: stored.provider,
            targetLanguage: stored.targetLanguage,
            onboardingCompleted: stored.onboardingCompleted,
            appLanguage: stored.appLanguage.isEmpty ? defaults.appLanguage : stored.appLanguage
        )
    }
}
