import Foundation
import XCTest
import DaisyTranslatorCore
@testable import DaisyTranslator

final class SettingsStoreTests: XCTestCase {
    func testSavePersistsAPIKeysAndLoadRestoresThem() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: fileURL)
        var settings = AppSettings.defaults(environment: [:])
        settings.provider = .deepSeek
        settings.apiKey = "active-provider-key"
        settings.providerConfigurations[ModelProvider.deepSeek.rawValue]?.apiKey = "active-provider-key"
        settings.providerConfigurations[ModelProvider.openAICompatible.rawValue]?.apiKey = "other-provider-key"
        settings.showDockIcon = false

        try store.save(settings)

        let data = try Data(contentsOf: fileURL)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["apiKey"] as? String, "active-provider-key")
        let configurations = try XCTUnwrap(payload["providerConfigurations"] as? [String: Any])
        let deepSeek = try XCTUnwrap(configurations[ModelProvider.deepSeek.rawValue] as? [String: Any])
        let openAI = try XCTUnwrap(configurations[ModelProvider.openAICompatible.rawValue] as? [String: Any])
        XCTAssertEqual(deepSeek["apiKey"] as? String, "active-provider-key")
        XCTAssertEqual(openAI["apiKey"] as? String, "other-provider-key")
        XCTAssertEqual(payload["showDockIcon"] as? Bool, false)
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("{\n  \"alwaysOnTop\" : false,\n  \"apiKey\" : \"active-provider-key\""))
        XCTAssertTrue(text.contains("\n  \"providerConfigurations\" : {"))

        let loaded = store.load()
        XCTAssertEqual(loaded.apiKey, "active-provider-key")
        XCTAssertEqual(
            loaded.providerConfigurations[ModelProvider.openAICompatible.rawValue]?.apiKey,
            "other-provider-key"
        )
        XCTAssertFalse(loaded.showDockIcon)
    }

    func testLoadMergesProviderDefaultsAndLegacyProviderFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("settings.json")
        try Data(
            #"{"provider":"deepseek","baseURL":"","apiKey":"legacy-key","model":"","providerConfigurations":{}}"#.utf8
        ).write(to: fileURL)
        let store = SettingsStore(fileURL: fileURL)

        let loaded = store.load()

        XCTAssertEqual(loaded.baseURL, AppSettings.defaultBaseURL(for: .deepSeek))
        XCTAssertEqual(loaded.apiKey, "legacy-key")
        XCTAssertEqual(loaded.model, AppSettings.defaultModel(for: .deepSeek))
        XCTAssertEqual(loaded.providerConfigurations.count, ModelProvider.allCases.count)
        XCTAssertEqual(
            loaded.providerConfigurations[ModelProvider.deepSeek.rawValue]?.apiKey,
            "legacy-key"
        )
        XCTAssertTrue(loaded.showDockIcon)
    }
}
