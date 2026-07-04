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

    func testTranslatesToEnglishHonorsTargetLanguagePreference() {
        let cases: [(name: String, source: String, preference: TargetLanguage, expected: Bool)] = [
            (
                name: "auto routes Han-containing source to English",
                source: "今天发布版本说明。",
                preference: .auto,
                expected: true
            ),
            (
                name: "auto routes English source to Chinese",
                source: "Ship the release notes today.",
                preference: .auto,
                expected: false
            ),
            (
                name: "English preference forces English source to English",
                source: "Ship the release notes today.",
                preference: .english,
                expected: true
            ),
            (
                name: "Chinese preference forces Han-containing source to Chinese",
                source: "今天发布版本说明。",
                preference: .chinese,
                expected: false
            )
        ]

        for testCase in cases {
            XCTAssertEqual(
                TranslationService.translatesToEnglish(source: testCase.source, preference: testCase.preference),
                testCase.expected,
                testCase.name
            )
        }
    }

    func testMakeRequestOpenAICompatibleHonorsTargetLanguagePreferenceOverAutoDetection() throws {
        let englishMessages = try makeOpenAICompatibleMessages(source: "Ship it", targetLanguage: .english)
        assertTranslationMessages(
            englishMessages,
            expectedContent: chineseToEnglishPrompt(source: "Ship it"),
            "English preference forces to-English prompt for English source"
        )

        let chineseMessages = try makeOpenAICompatibleMessages(source: "你好", targetLanguage: .chinese)
        assertTranslationMessages(
            chineseMessages,
            expectedContent: englishToChinesePrompt(source: "你好"),
            "Chinese preference forces to-Chinese prompt for Han source"
        )
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

    func testAppSettingsDecodingDefaultsMissingTargetLanguageToAutoAndReadsKnownValue() throws {
        let missingTargetLanguage = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(missingTargetLanguage.targetLanguage, .auto)

        let englishTargetLanguage = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"targetLanguage":"english"}"#.utf8)
        )
        XCTAssertEqual(englishTargetLanguage.targetLanguage, .english)
    }

    func testAppSettingsDefaultsHonorTargetLanguageEnvironmentOverride() {
        XCTAssertEqual(
            AppSettings.defaults(environment: ["TT_TARGET_LANGUAGE": "chinese"]).targetLanguage,
            .chinese
        )
        XCTAssertEqual(
            AppSettings.defaults(environment: ["TT_TARGET_LANGUAGE": "klingon"]).targetLanguage,
            .auto
        )
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

    func testMakeRequestGoogleFreeGETHonorsTargetLanguagePreferenceOverAutoDetection() throws {
        let cases: [(name: String, source: String, preference: TargetLanguage, expectedTarget: String)] = [
            (
                name: "English preference forces English source to English",
                source: "Ship the release notes today.",
                preference: .english,
                expectedTarget: "en"
            ),
            (
                name: "Chinese preference forces Han-containing source to Simplified Chinese",
                source: "今天发布版本说明。",
                preference: .chinese,
                expectedTarget: "zh-CN"
            )
        ]

        for testCase in cases {
            var settings = makeGoogleSettings(apiKey: "")
            settings.targetLanguage = testCase.preference

            let request = try TranslationService.makeRequest(source: testCase.source, settings: settings)

            XCTAssertEqual(request.httpMethod, "GET", testCase.name)
            let url = try XCTUnwrap(request.url, testCase.name)
            XCTAssertEqual(try googleQueryItems(in: url)["tl"], testCase.expectedTarget, testCase.name)
        }
    }

    func testGoogleProviderPublicDefaults() {
        var settings = AppSettings.defaults(environment: [:])
        settings.provider = .google
        settings.baseURL = AppSettings.defaultBaseURL(for: .google)
        settings.model = AppSettings.defaultModel(for: .google)

        XCTAssertEqual(ModelProvider.google.rawValue, "google")
        XCTAssertEqual(settings.baseURL, "https://translate.googleapis.com")
        XCTAssertEqual(settings.model, "")
    }

    func testBaiduProviderPublicDefaults() {
        var settings = AppSettings.defaults(environment: [:])
        settings.provider = .baidu
        settings.baseURL = AppSettings.defaultBaseURL(for: .baidu)
        settings.model = AppSettings.defaultModel(for: .baidu)

        XCTAssertEqual(ModelProvider.baidu.rawValue, "baidu")
        XCTAssertEqual(settings.baseURL, "https://fanyi-api.baidu.com")
        XCTAssertEqual(settings.model, "")
    }

    func testBaiduSignatureMatchesKnownVectors() {
        XCTAssertEqual(
            TranslationService.baiduSignature(
                appID: "2015063000000001",
                query: "apple",
                salt: "1435660288",
                secret: "12345678"
            ),
            "f89f9594663708c1605f3d736d01d2d4"
        )
        XCTAssertEqual(
            TranslationService.baiduSignature(
                appID: "myappid",
                query: "你好，世界",
                salt: "987654",
                secret: "mysecret"
            ),
            "93718aba75609785829e18775b36d073"
        )
    }

    func testMakeBaiduTranslateRequestBuildsFormPOSTAndRoutesTargetLanguage() throws {
        let cases: [(name: String, source: String, expectedTarget: String)] = [
            (
                name: "Han-containing source routes to English",
                source: "今天发布 release notes。",
                expectedTarget: "en"
            ),
            (
                name: "English source routes to Chinese",
                source: "Ship the release notes today.",
                expectedTarget: "zh"
            )
        ]

        for testCase in cases {
            let settings = makeBaiduSettings(apiKey: "myappid:mysecret")
            let salt = "987654"

            let request = try TranslationService.makeBaiduTranslateRequest(
                source: testCase.source,
                settings: settings,
                salt: salt
            )

            XCTAssertEqual(request.url?.absoluteString, "https://fanyi-api.baidu.com/api/trans/vip/translate", testCase.name)
            XCTAssertEqual(request.httpMethod, "POST", testCase.name)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded", testCase.name)

            let fields = try baiduFormBodyItems(in: request)
            XCTAssertEqual(fields["q"], testCase.source, testCase.name)
            XCTAssertEqual(fields["from"], "auto", testCase.name)
            XCTAssertEqual(fields["to"], testCase.expectedTarget, testCase.name)
            XCTAssertEqual(fields["appid"], "myappid", testCase.name)
            XCTAssertEqual(fields["salt"], salt, testCase.name)
            XCTAssertEqual(
                fields["sign"],
                TranslationService.baiduSignature(
                    appID: "myappid",
                    query: testCase.source,
                    salt: salt,
                    secret: "mysecret"
                ),
                testCase.name
            )
        }
    }

    func testMakeBaiduTranslateRequestHonorsTargetLanguagePreferenceOverAutoDetection() throws {
        let cases: [(name: String, source: String, preference: TargetLanguage, expectedTarget: String)] = [
            (
                name: "English preference forces English source to English",
                source: "Ship the release notes today.",
                preference: .english,
                expectedTarget: "en"
            ),
            (
                name: "Chinese preference forces Han-containing source to Chinese",
                source: "今天发布版本说明。",
                preference: .chinese,
                expectedTarget: "zh"
            )
        ]

        for testCase in cases {
            var settings = makeBaiduSettings(apiKey: "app:secret")
            settings.targetLanguage = testCase.preference

            let request = try TranslationService.makeBaiduTranslateRequest(
                source: testCase.source,
                settings: settings,
                salt: "fixed-salt"
            )

            let fields = try baiduFormBodyItems(in: request)
            XCTAssertEqual(fields["to"], testCase.expectedTarget, testCase.name)
        }
    }

    func testMakeBaiduRequestRejectsMalformedCredentials() {
        let invalidAPIKeys = ["appidonly", ":secret", "appid:"]

        for apiKey in invalidAPIKeys {
            let settings = makeBaiduSettings(apiKey: apiKey)

            XCTAssertThrowsError(
                try TranslationService.makeRequest(source: "Hello", settings: settings),
                "apiKey: \(apiKey.debugDescription)"
            ) { error in
                XCTAssertEqual(error as? TranslationError, .missingBaiduCredentials)
            }
        }
    }

    func testBaiduCredentialsSplitSecretOnFirstColon() throws {
        let source = "你好，世界"
        let salt = "123456"
        let settings = makeBaiduSettings(apiKey: "app:se:cret")

        let request = try TranslationService.makeBaiduTranslateRequest(
            source: source,
            settings: settings,
            salt: salt
        )

        let fields = try baiduFormBodyItems(in: request)
        XCTAssertEqual(fields["appid"], "app")
        XCTAssertEqual(
            fields["sign"],
            TranslationService.baiduSignature(appID: "app", query: source, salt: salt, secret: "se:cret")
        )
    }

    func testResolveBaiduTranslateURLNormalizesBaseURLsAndRejectsEmptyBaseURL() throws {
        let trailingSlashURL = try TranslationService.resolveBaiduTranslateURL(" https://fanyi-api.baidu.com/ ")
        XCTAssertEqual(trailingSlashURL.absoluteString, "https://fanyi-api.baidu.com/api/trans/vip/translate")

        let endpointURL = try TranslationService.resolveBaiduTranslateURL(
            "https://fanyi-api.baidu.com/api/trans/vip/translate/"
        )
        XCTAssertEqual(endpointURL.absoluteString, "https://fanyi-api.baidu.com/api/trans/vip/translate")

        for baseURL in ["", "   \n\t  "] {
            XCTAssertThrowsError(
                try TranslationService.resolveBaiduTranslateURL(baseURL),
                "baseURL: \(baseURL.debugDescription)"
            ) { error in
                XCTAssertEqual(error as? TranslationError, .missingBaseURL)
            }
        }
    }

    func testMakeRequestBuildsGoogleFreeTranslateGETForBlankAPIKey() throws {
        let cases: [(name: String, source: String, expectedTarget: String)] = [
            (
                name: "Han-containing source routes to English",
                source: "今天发布 release notes。",
                expectedTarget: "en"
            ),
            (
                name: "pure English source routes to Simplified Chinese",
                source: "Ship the release notes today.",
                expectedTarget: "zh-CN"
            )
        ]

        for testCase in cases {
            let settings = makeGoogleSettings(apiKey: "")

            let request = try TranslationService.makeRequest(source: testCase.source, settings: settings)

            XCTAssertEqual(request.httpMethod, "GET", testCase.name)
            let url = try XCTUnwrap(request.url, testCase.name)
            XCTAssertEqual(url.scheme, "https", testCase.name)
            XCTAssertEqual(url.host, "translate.googleapis.com", testCase.name)
            XCTAssertEqual(url.path, "/translate_a/single", testCase.name)
            XCTAssertNil(request.httpBody, testCase.name)

            let queryItems = try googleQueryItems(in: url)
            XCTAssertEqual(queryItems["client"], "gtx", testCase.name)
            XCTAssertEqual(queryItems["sl"], "auto", testCase.name)
            XCTAssertEqual(queryItems["tl"], testCase.expectedTarget, testCase.name)
            XCTAssertEqual(queryItems["dt"], "t", testCase.name)
            XCTAssertEqual(queryItems["q"], testCase.source, testCase.name)
        }
    }

    func testMakeRequestBuildsGoogleCloudTranslatePOSTForNonEmptyAPIKey() throws {
        let source = "Translate API 响应"
        let settings = makeGoogleSettings(apiKey: "google-token")

        let request = try TranslationService.makeRequest(source: source, settings: settings)

        XCTAssertEqual(request.httpMethod, "POST")
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "translate.googleapis.com")
        XCTAssertEqual(url.path, "/language/translate/v2")
        XCTAssertEqual(try googleQueryItems(in: url)["key"], "google-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["q"] as? [String], [source])
        XCTAssertEqual(json["target"] as? String, "en")
        XCTAssertEqual(json["format"] as? String, "text")
    }

    func testResolveGoogleTranslateURLsNormalizeBaseURLsAndRejectEmptyBaseURL() throws {
        let freeTrailingSlashURL = try TranslationService.resolveGoogleFreeTranslateURL(
            " https://translate.googleapis.com/ ",
            target: "en",
            query: "Hello, 世界"
        )
        XCTAssertEqual(freeTrailingSlashURL.path, "/translate_a/single")
        XCTAssertEqual(try googleQueryItems(in: freeTrailingSlashURL)["q"], "Hello, 世界")

        let freeEndpointURL = try TranslationService.resolveGoogleFreeTranslateURL(
            "https://translate.googleapis.com/translate_a/single/",
            target: "zh-CN",
            query: "Ship it"
        )
        XCTAssertEqual(freeEndpointURL.path, "/translate_a/single")
        XCTAssertEqual(try googleQueryItems(in: freeEndpointURL)["tl"], "zh-CN")

        let cloudTrailingSlashURL = try TranslationService.resolveGoogleCloudTranslateURL(
            " https://translate.googleapis.com/ ",
            apiKey: "secret key"
        )
        XCTAssertEqual(cloudTrailingSlashURL.path, "/language/translate/v2")
        XCTAssertEqual(try googleQueryItems(in: cloudTrailingSlashURL)["key"], "secret key")

        let cloudEndpointURL = try TranslationService.resolveGoogleCloudTranslateURL(
            "https://translate.googleapis.com/language/translate/v2/",
            apiKey: "cloud-token"
        )
        XCTAssertEqual(cloudEndpointURL.path, "/language/translate/v2")
        XCTAssertEqual(try googleQueryItems(in: cloudEndpointURL)["key"], "cloud-token")

        for baseURL in ["", "   \n\t  ", "///"] {
            XCTAssertThrowsError(
                try TranslationService.resolveGoogleFreeTranslateURL(baseURL, target: "en", query: "Hello"),
                "free baseURL: \(baseURL.debugDescription)"
            ) { error in
                XCTAssertEqual(error as? TranslationError, .missingBaseURL)
            }
            XCTAssertThrowsError(
                try TranslationService.resolveGoogleCloudTranslateURL(baseURL, apiKey: "token"),
                "cloud baseURL: \(baseURL.debugDescription)"
            ) { error in
                XCTAssertEqual(error as? TranslationError, .missingBaseURL)
            }
        }
    }

    func testMakeRequestTreatsWhitespaceGoogleAPIKeyAsFreeTranslateGET() throws {
        let settings = makeGoogleSettings(apiKey: " \n\t  ")

        let request = try TranslationService.makeRequest(source: "Ship it", settings: settings)

        XCTAssertEqual(request.httpMethod, "GET")
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/translate_a/single")
        XCTAssertEqual(try googleQueryItems(in: url)["client"], "gtx")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    private func makeBaiduSettings(
        apiKey: String,
        baseURL: String = AppSettings.defaultBaseURL(for: .baidu)
    ) -> AppSettings {
        var settings = AppSettings.defaults(environment: [:])
        settings.provider = .baidu
        settings.baseURL = baseURL
        settings.apiKey = apiKey
        settings.model = AppSettings.defaultModel(for: .baidu)
        return settings
    }

    private func baiduFormBodyItems(
        in request: URLRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: String] {
        let body = try XCTUnwrap(request.httpBody, "Missing form body", file: file, line: line)
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8), "Body is not UTF-8", file: file, line: line)
        return Dictionary(uniqueKeysWithValues: bodyString.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(parts[0])
            let rawValue = parts.count == 2 ? String(parts[1]) : ""
            let value = rawValue.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawValue
            return (key, value)
        })
    }

    private func makeGoogleSettings(
        apiKey: String = "",
        baseURL: String = AppSettings.defaultBaseURL(for: .google)
    ) -> AppSettings {
        var settings = AppSettings.defaults(environment: [:])
        settings.provider = .google
        settings.baseURL = baseURL
        settings.apiKey = apiKey
        settings.model = AppSettings.defaultModel(for: .google)
        return settings
    }

    private func googleQueryItems(
        in url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: String] {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false), file: file, line: line)
        let queryItems = try XCTUnwrap(components.queryItems, "Missing query items", file: file, line: line)
        return Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }

    private func makeOpenAICompatibleMessages(
        source: String,
        targetLanguage: TargetLanguage = .auto
    ) throws -> [[String: String]] {
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
            provider: .openAICompatible,
            targetLanguage: targetLanguage
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

