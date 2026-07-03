import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import TTTranslatorCore

final class TranslationCoreTests: XCTestCase {
    func testResolveChatURLNormalizesOpenAICompatibleBaseURLs() throws {
        let cases: [(name: String, baseURL: String, expected: String)] = [
            (
                name: "bare host appends version and chat endpoint",
                baseURL: "https://llm.example.test",
                expected: "https://llm.example.test/v1/chat/completions"
            ),
            (
                name: "versioned base appends chat endpoint",
                baseURL: " https://llm.example.test/api/v1/ ",
                expected: "https://llm.example.test/api/v1/chat/completions"
            ),
            (
                name: "complete chat endpoint is preserved",
                baseURL: "https://llm.example.test/services/model/v1/chat/completions/",
                expected: "https://llm.example.test/services/model/v1/chat/completions"
            )
        ]

        for testCase in cases {
            let url = try TranslationService.resolveChatURL(testCase.baseURL)

            XCTAssertEqual(url.absoluteString, testCase.expected, testCase.name)
        }
    }

    func testResolveChatURLRejectsEmptyBaseURL() {
        let cases = ["", "   \n\t  ", "///"]

        for baseURL in cases {
            XCTAssertThrowsError(try TranslationService.resolveChatURL(baseURL), "baseURL: \(baseURL.debugDescription)") { error in
                XCTAssertEqual(error as? TranslationError, .missingBaseURL)
            }
        }
    }

    func testDetectTargetLanguageChoosesChineseForEnglishAndEnglishForChinese() {
        let cases: [(name: String, source: String, expected: String)] = [
            (name: "English input targets Simplified Chinese", source: "Ship the release notes today.", expected: "Simplified Chinese"),
            (name: "Chinese input targets English", source: "今天发布版本说明。", expected: "English"),
            (name: "mixed input with any Han character targets English", source: "Translate API 响应", expected: "English")
        ]

        for testCase in cases {
            XCTAssertEqual(TranslationService.detectTargetLanguage(testCase.source), testCase.expected, testCase.name)
        }
    }

    func testAppSettingsDefaultsHonorSuppliedEnvironmentOverrides() {
        let settings = AppSettings.defaults(environment: [
            "TT_PROVIDER": ModelProvider.deepSeek.rawValue,
            "TT_BASE_URL": "https://env.example.test/v1",
            "TT_API_KEY": "env-token",
            "TT_MODEL": "env-model",
            "TT_TEMPERATURE": "0.25",
            "TT_TOP_P": "0.9",
            "TT_MAX_TOKENS": "2048"
        ])

        XCTAssertEqual(settings.provider, .deepSeek)
        XCTAssertEqual(settings.baseURL, "https://env.example.test/v1")
        XCTAssertEqual(settings.apiKey, "env-token")
        XCTAssertEqual(settings.model, "env-model")
        XCTAssertEqual(settings.temperature, 0.25)
        XCTAssertEqual(settings.topP, 0.9)
        XCTAssertEqual(settings.maxTokens, 2048)
    }

    func testMakeRequestBuildsOpenAICompatibleHeadersAndJSONBody() throws {
        let settings = AppSettings(
            baseURL: "https://llm.example.test/services/model/v1/",
            apiKey: "secret-token",
            model: "translator-model",
            temperature: 0.2,
            topP: 0.75,
            maxTokens: 512,
            debounceMilliseconds: 650,
            autoTranslate: true,
            watchClipboard: false,
            autoCopy: true,
            autoPaste: false,
            alwaysOnTop: true,
            provider: .openAICompatible
        )

        let request = try TranslationService.makeRequest(source: "Hello, 世界", settings: settings)

        XCTAssertEqual(request.url?.absoluteString, "https://llm.example.test/services/model/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "translator-model")
        XCTAssertEqual(json["temperature"] as? Double, 0.2)
        XCTAssertEqual(json["top_p"] as? Double, 0.75)
        XCTAssertEqual(json["max_tokens"] as? Int, 512)
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertNil(json["topP"])
        XCTAssertNil(json["maxTokens"])

        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
        XCTAssertEqual(messages.last?["content"], "Target language: English\n\nText:\nHello, 世界")
    }

    func testMakeRequestBuildsDeepSeekOpenAICompatibleEndpointHeadersAndJSONBody() throws {
        let settings = AppSettings(
            baseURL: "https://api.deepseek.com/v1/",
            apiKey: "deepseek-token",
            model: "deepseek-chat",
            temperature: 0.35,
            topP: 0.65,
            maxTokens: 1024,
            debounceMilliseconds: 650,
            autoTranslate: true,
            watchClipboard: false,
            autoCopy: true,
            autoPaste: false,
            alwaysOnTop: true,
            provider: .deepSeek
        )

        let request = try TranslationService.makeRequest(source: "Ship it", settings: settings)

        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer deepseek-token")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "deepseek-chat")
        XCTAssertEqual(json["temperature"] as? Double, 0.35)
        XCTAssertEqual(json["top_p"] as? Double, 0.65)
        XCTAssertEqual(json["max_tokens"] as? Int, 1024)
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertNil(json["options"])

        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
        XCTAssertEqual(messages.last?["content"], "Target language: Simplified Chinese\n\nText:\nShip it")
    }

    func testMakeRequestBuildsOllamaChatEndpointBodyAndOptions() throws {
        let settings = AppSettings(
            baseURL: "http://localhost:11434/",
            apiKey: "ignored-for-ollama",
            model: "qwen2.5",
            temperature: 0.15,
            topP: 0.55,
            maxTokens: 256,
            debounceMilliseconds: 650,
            autoTranslate: true,
            watchClipboard: false,
            autoCopy: true,
            autoPaste: false,
            alwaysOnTop: true,
            provider: .ollama
        )

        let request = try TranslationService.makeRequest(source: "你好", settings: settings)

        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "qwen2.5")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertNil(json["temperature"])
        XCTAssertNil(json["top_p"])
        XCTAssertNil(json["max_tokens"])

        let options = try XCTUnwrap(json["options"] as? [String: Any])
        XCTAssertEqual(options["temperature"] as? Double, 0.15)
        XCTAssertEqual(options["top_p"] as? Double, 0.55)
        XCTAssertEqual(options["num_predict"] as? Int, 256)

        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
        XCTAssertEqual(messages.last?["content"], "Target language: English\n\nText:\n你好")
    }

    func testMakeRequestOmitsAuthorizationHeaderWhenAPIKeyIsBlank() throws {
        let settings = AppSettings(
            baseURL: "https://llm.example.test/v1",
            apiKey: "  ",
            model: "translator-model",
            temperature: 0.2,
            topP: 0.75,
            maxTokens: 512,
            debounceMilliseconds: 650,
            autoTranslate: true,
            watchClipboard: false,
            autoCopy: true,
            autoPaste: false,
            alwaysOnTop: true,
            provider: .openAICompatible
        )

        let request = try TranslationService.makeRequest(source: "Hello", settings: settings)

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}
