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

    func testMakeRequestRoutesTargetLanguageByChineseHanPresence() throws {
        let cases: [(name: String, source: String, expectedPrompt: String)] = [
            (
                name: "Chinese Han text without kana or Hangul uses the official Chinese-to-English prompt",
                source: "今天发布版本说明。",
                expectedPrompt: chineseToEnglishPrompt(source: "今天发布版本说明。")
            ),
            (
                name: "Chinese mixed with English identifiers still uses the official Chinese-to-English prompt",
                source: "Translate API 响应",
                expectedPrompt: chineseToEnglishPrompt(source: "Translate API 响应")
            ),
            (
                name: "English input uses the official English-to-Chinese prompt",
                source: "Ship the release notes today.",
                expectedPrompt: englishToChinesePrompt(source: "Ship the release notes today.")
            ),
            (
                name: "Japanese kana and kanji input containing Han uses the official Chinese-to-English prompt",
                source: "設定を保存しました。",
                expectedPrompt: chineseToEnglishPrompt(source: "設定を保存しました。")
            ),
            (
                name: "Korean Hangul input uses the official English-to-Chinese prompt",
                source: "릴리스 노트를 게시하세요.",
                expectedPrompt: englishToChinesePrompt(source: "릴리스 노트를 게시하세요.")
            ),
            (
                name: "Spanish input uses the official English-to-Chinese prompt",
                source: "Publica las notas de la versión hoy.",
                expectedPrompt: englishToChinesePrompt(source: "Publica las notas de la versión hoy.")
            )
        ]

        for testCase in cases {
            let messages = try makeOpenAICompatibleMessages(source: testCase.source)

            assertTranslationMessages(messages, expectedContent: testCase.expectedPrompt, testCase.name)
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
        assertTranslationMessages(messages, expectedContent: chineseToEnglishPrompt(source: "Hello, 世界"))
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
        assertTranslationMessages(messages, expectedContent: englishToChinesePrompt(source: "Ship it"))
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
        assertTranslationMessages(messages, expectedContent: chineseToEnglishPrompt(source: "你好"))
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

    private func makeOpenAICompatibleMessages(source: String) throws -> [[String: String]] {
        let settings = AppSettings(
            baseURL: "https://llm.example.test/v1",
            apiKey: "direction-token",
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

        let request = try TranslationService.makeRequest(source: source, settings: settings)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        return try XCTUnwrap(json["messages"] as? [[String: String]])
    }

    private func chineseToEnglishPrompt(source: String) -> String {
        "将以下文本翻译为英语，注意只需要输出翻译后的结果，不要额外解释：\n\n\(source)"
    }

    private func englishToChinesePrompt(source: String) -> String {
        "Translate the following text into Chinese. Note that you should only output the translated result without any additional explanation:\n\n\(source)"
    }

    private func assertTranslationMessages(
        _ messages: [[String: String]],
        expectedContent: String,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            messages,
            [["role": "user", "content": expectedContent]],
            message,
            file: file,
            line: line
        )
    }
}

