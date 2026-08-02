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
        let store = SettingsStore(
            defaultSettings: .defaults(environment: [:]),
            fileURL: fileURL
        )
        var settings = AppSettings.defaults(environment: [:])
        settings.provider = .deepSeek
        settings.apiKey = "active-provider-key"
        settings.providerConfigurations[ModelProvider.deepSeek.rawValue]?.apiKey = "active-provider-key"
        settings.providerConfigurations[ModelProvider.openAICompatible.rawValue]?.apiKey = "other-provider-key"

        try store.save(settings)

        let data = try Data(contentsOf: fileURL)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["apiKey"] as? String, "active-provider-key")
        let configurations = try XCTUnwrap(payload["providerConfigurations"] as? [String: Any])
        let deepSeek = try XCTUnwrap(configurations[ModelProvider.deepSeek.rawValue] as? [String: Any])
        let openAI = try XCTUnwrap(configurations[ModelProvider.openAICompatible.rawValue] as? [String: Any])
        XCTAssertEqual(deepSeek["apiKey"] as? String, "active-provider-key")
        XCTAssertEqual(openAI["apiKey"] as? String, "other-provider-key")

        let loaded = store.load()
        XCTAssertEqual(loaded.apiKey, "active-provider-key")
        XCTAssertEqual(
            loaded.providerConfigurations[ModelProvider.openAICompatible.rawValue]?.apiKey,
            "other-provider-key"
        )
    }
}
