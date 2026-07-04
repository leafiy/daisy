import Foundation
import TTTranslatorCore

final class SettingsStore {
    private let fileURL: URL
    private let defaultSettings: AppSettings
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        defaultSettings: AppSettings = .defaults()
    ) {
        self.defaultSettings = defaultSettings
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.fileURL = applicationSupport
            .appendingPathComponent("TT Translator", isDirectory: true)
            .appendingPathComponent("settings.json")
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
        AppSettings(
            baseURL: stored.baseURL.isEmpty ? defaults.baseURL : stored.baseURL,
            apiKey: stored.apiKey,
            model: stored.model.isEmpty ? defaults.model : stored.model,
            temperature: stored.temperature == 0 ? defaults.temperature : stored.temperature,
            topP: stored.topP == 0 ? defaults.topP : stored.topP,
            maxTokens: stored.maxTokens == 0 ? defaults.maxTokens : stored.maxTokens,
            debounceMilliseconds: stored.debounceMilliseconds == 0 ? defaults.debounceMilliseconds : stored.debounceMilliseconds,
            autoTranslate: stored.autoTranslate,
            watchClipboard: stored.watchClipboard,
            autoCopy: stored.autoCopy,
            autoPaste: stored.autoPaste,
            alwaysOnTop: stored.alwaysOnTop,
            quickTranslateEnabled: stored.quickTranslateEnabled,
            quickTranslateShortcut: stored.quickTranslateShortcut.isEmpty ? defaults.quickTranslateShortcut : stored.quickTranslateShortcut,
            provider: stored.provider,
            targetLanguage: stored.targetLanguage
        )
    }
}
