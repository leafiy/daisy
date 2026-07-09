import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import DaisyTranslatorCore

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
            ),
            (
                name: "long versioned base path preserves every segment",
                baseURL: "https://llm.example.test/services/workspaces/team-a/providers/openai-compatible/models/qwen36-35b-a3b-mtp-q6/v1",
                expected: "https://llm.example.test/services/workspaces/team-a/providers/openai-compatible/models/qwen36-35b-a3b-mtp-q6/v1/chat/completions"
            ),
            (
                name: "full endpoint with query is preserved",
                baseURL: "https://llm.example.test/openai/deployments/translator/chat/completions?api-version=2024-10-21",
                expected: "https://llm.example.test/openai/deployments/translator/chat/completions?api-version=2024-10-21"
            ),
            (
                name: "versioned base with query appends path before query",
                baseURL: "https://llm.example.test/openai/deployments/translator/v1?api-version=2024-10-21",
                expected: "https://llm.example.test/openai/deployments/translator/v1/chat/completions?api-version=2024-10-21"
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
                name: "already-English source flips to Chinese to avoid identity translation",
                source: "Ship the release notes today.",
                preference: .english,
                expected: false
            ),
            (
                name: "English preference translates Chinese-only source to English",
                source: "今天发布版本说明。",
                preference: .english,
                expected: true
            ),
            (
                name: "English preference honors mixed Chinese and Latin source",
                source: "今天 ship the release notes.",
                preference: .english,
                expected: true
            ),
            (
                name: "already-Chinese source flips to English to avoid identity translation",
                source: "今天发布版本说明。",
                preference: .chinese,
                expected: true
            ),
            (
                name: "Chinese preference translates English-only source to Chinese",
                source: "Ship the release notes today.",
                preference: .chinese,
                expected: false
            ),
            (
                name: "Chinese preference honors mixed Chinese and Latin source",
                source: "今天 ship the release notes.",
                preference: .chinese,
                expected: false
            ),
            (
                name: "English preference translates scriptless source to English",
                source: "12345",
                preference: .english,
                expected: true
            ),
            (
                name: "Chinese preference translates scriptless source to Chinese",
                source: "12345",
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
            expectedContent: englishToChinesePrompt(source: "Ship it"),
            "already-English source flips to Chinese prompt to avoid identity translation"
        )

        let chineseMessages = try makeOpenAICompatibleMessages(source: "你好", targetLanguage: .chinese)
        assertTranslationMessages(
            chineseMessages,
            expectedContent: chineseToEnglishPrompt(source: "你好"),
            "already-Chinese source flips to English prompt to avoid identity translation"
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

    func testAppSettingsDefaultsUseAppleSystemProvider() {
        let settings = AppSettings.defaults(environment: [:])

        XCTAssertEqual(settings.provider, .appleSystem)
        XCTAssertEqual(settings.baseURL, "")
        XCTAssertEqual(settings.model, "")
        XCTAssertFalse(settings.alwaysOnTop)
        XCTAssertEqual(ModelProvider.appleSystem.rawValue, "apple-system")
    }

    func testAppSettingsDefaultsKeepProviderConfigurationsSeparate() {
        let settings = AppSettings.defaults(environment: [
            "TT_PROVIDER": ModelProvider.deepSeek.rawValue,
            "TT_API_KEY": "deepseek-token",
            "TT_MODEL": "deepseek-custom"
        ])

        XCTAssertEqual(settings.providerConfigurations[ModelProvider.deepSeek.rawValue]?.apiKey, "deepseek-token")
        XCTAssertEqual(settings.providerConfigurations[ModelProvider.deepSeek.rawValue]?.model, "deepseek-custom")
        XCTAssertEqual(settings.providerConfigurations[ModelProvider.google.rawValue]?.apiKey, "")
        XCTAssertEqual(
            settings.providerConfigurations[ModelProvider.google.rawValue]?.baseURL,
            AppSettings.defaultBaseURL(for: .google)
        )
    }

    func testAppSettingsDecodingMigratesLegacyProviderFieldsIntoProviderConfiguration() throws {
        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"provider":"baidu","baseURL":"https://legacy.example.test","apiKey":"baidu-token","model":"legacy-model"}"#.utf8)
        )

        let configuration = try XCTUnwrap(settings.providerConfigurations[ModelProvider.baidu.rawValue])
        XCTAssertEqual(configuration.baseURL, "https://legacy.example.test")
        XCTAssertEqual(configuration.apiKey, "baidu-token")
        XCTAssertEqual(configuration.model, "legacy-model")
        XCTAssertEqual(settings.appLanguage, "system")
    }

    func testAppleSystemProviderDoesNotBuildNetworkRequest() {
        let settings = AppSettings.defaults(environment: [:])

        XCTAssertThrowsError(try TranslationService.makeRequest(source: "Hello", settings: settings)) { error in
            XCTAssertEqual(error as? TranslationError, .appleSystemTranslationUnavailable)
        }
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

    func testAppSettingsDecodingDefaultsMissingMinimalModeToFalseAndReadsExplicitTrue() throws {
        let missingMinimalMode = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(missingMinimalMode.minimalMode)

        let enabledMinimalMode = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"minimalMode":true}"#.utf8)
        )
        XCTAssertTrue(enabledMinimalMode.minimalMode)
    }

    func testAppSettingsDecodingDefaultsMissingQuickTranslateAutoCopyToTrueAndReadsExplicitFalse() throws {
        let missingQuickTranslateAutoCopy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(missingQuickTranslateAutoCopy.quickTranslateAutoCopy)

        let disabledQuickTranslateAutoCopy = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"quickTranslateAutoCopy":false}"#.utf8)
        )
        XCTAssertFalse(disabledQuickTranslateAutoCopy.quickTranslateAutoCopy)
    }

    func testAppSettingsEncodingRoundTripPreservesAppLanguage() throws {
        var settings = AppSettings.defaults(environment: [:])
        settings.appLanguage = "zh-Hans"

        let decoded = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))

        XCTAssertEqual(decoded.appLanguage, "zh-Hans")
    }

    func testAppSettingsEncodingRoundTripPreservesMinimalMode() throws {
        var settings = AppSettings.defaults(environment: [:])
        settings.minimalMode = true

        let decoded = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))

        XCTAssertTrue(decoded.minimalMode)
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
            baseURL: "https://api.deepseek.com/",
            apiKey: "deepseek-token",
            model: "deepseek-v4-flash",
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

        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer deepseek-token")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "deepseek-v4-flash")
        XCTAssertEqual(json["temperature"] as? Double, 0.35)
        XCTAssertEqual(json["top_p"] as? Double, 0.65)
        XCTAssertEqual(json["max_tokens"] as? Int, 1024)
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertNil(json["options"])

        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        assertTranslationMessages(messages, expectedContent: englishToChinesePrompt(source: "Ship it"))
    }

    func testDeepSeekProviderDefaultsUseFlashModel() {
        var settings = AppSettings.defaults(environment: [:])
        settings.provider = .deepSeek
        settings.baseURL = AppSettings.defaultBaseURL(for: .deepSeek)
        settings.model = AppSettings.defaultModel(for: .deepSeek)

        XCTAssertEqual(settings.baseURL, "https://api.deepseek.com")
        XCTAssertEqual(settings.model, "deepseek-v4-flash")
    }

    func testResolveDeepSeekChatURLUsesUnversionedEndpointAndNormalizesOldBaseURL() throws {
        let bareURL = try TranslationService.resolveDeepSeekChatURL(" https://api.deepseek.com/ ")
        XCTAssertEqual(bareURL.absoluteString, "https://api.deepseek.com/chat/completions")

        let oldVersionedBaseURL = try TranslationService.resolveDeepSeekChatURL("https://api.deepseek.com/v1/")
        XCTAssertEqual(oldVersionedBaseURL.absoluteString, "https://api.deepseek.com/chat/completions")

        let oldVersionedEndpointURL = try TranslationService.resolveDeepSeekChatURL(
            "https://api.deepseek.com/v1/chat/completions/"
        )
        XCTAssertEqual(oldVersionedEndpointURL.absoluteString, "https://api.deepseek.com/chat/completions")
    }

    func testDeepSeekHTTPErrorShowsReadableMessage() async throws {
        let service = makeMockedTranslationService(
            body: #"{"error":{"message":"Insufficient Balance","type":"invalid_request_error"}}"#,
            statusCode: 402
        )
        var settings = AppSettings.defaults(environment: [:])
        settings.provider = .deepSeek
        settings.baseURL = AppSettings.defaultBaseURL(for: .deepSeek)
        settings.apiKey = "deepseek-token"
        settings.model = AppSettings.defaultModel(for: .deepSeek)

        do {
            _ = try await service.translate("Hello", settings: settings)
            XCTFail("Expected DeepSeek HTTP error to throw")
        } catch {
            XCTAssertEqual(
                error as? TranslationError,
                .requestFailed(status: 402, body: "DeepSeek 额度或余额不足，请检查账号余额和用量限制")
            )
            XCTAssertFalse(error.localizedDescription.contains("Insufficient Balance"))
        }
    }

    func testDeepSeekPlainAuthenticationErrorShowsReadableMessage() async throws {
        let service = makeMockedTranslationService(body: "Authentication Fails", statusCode: 401)
        var settings = AppSettings.defaults(environment: [:])
        settings.provider = .deepSeek
        settings.baseURL = AppSettings.defaultBaseURL(for: .deepSeek)
        settings.apiKey = "bad-token"
        settings.model = AppSettings.defaultModel(for: .deepSeek)

        do {
            _ = try await service.translate("Hello", settings: settings)
            XCTFail("Expected DeepSeek authentication error to throw")
        } catch {
            XCTAssertEqual(
                error as? TranslationError,
                .requestFailed(status: 401, body: "DeepSeek 鉴权失败，请检查 API Key 是否正确")
            )
            XCTAssertFalse(error.localizedDescription.contains("Authentication"))
        }
    }

    func testOpenAICompatibleAuthenticationErrorShowsReadableMessage() async throws {
        let service = makeMockedTranslationService(
            body: #"{"error":{"message":"Authentication Fails"}}"#,
            statusCode: 401
        )
        var settings = AppSettings.defaults(environment: [:])
        settings.provider = .openAICompatible
        settings.baseURL = "https://llm.example.test/v1"
        settings.apiKey = "bad-token"
        settings.model = "translator-model"

        do {
            _ = try await service.translate("Hello", settings: settings)
            XCTFail("Expected compatible provider authentication error to throw")
        } catch {
            XCTAssertEqual(
                error as? TranslationError,
                .requestFailed(status: 401, body: "服务鉴权失败，请检查 API Key 是否正确")
            )
            XCTAssertFalse(error.localizedDescription.contains("Authentication"))
        }
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
                name: "already-English source flips to Simplified Chinese to avoid identity translation",
                source: "Ship the release notes today.",
                preference: .english,
                expectedTarget: "zh-CN"
            ),
            (
                name: "already-Chinese source flips to English to avoid identity translation",
                source: "今天发布版本说明。",
                preference: .chinese,
                expectedTarget: "en"
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
            let settings = makeBaiduSettings(apiKey: "baidu-token")

            let request = try TranslationService.makeBaiduTranslateRequest(
                source: testCase.source,
                settings: settings
            )

            XCTAssertEqual(request.url?.absoluteString, "https://fanyi-api.baidu.com/ait/api/aiTextTranslate", testCase.name)
            XCTAssertEqual(request.httpMethod, "POST", testCase.name)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded", testCase.name)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer baidu-token", testCase.name)

            let fields = try baiduFormBodyItems(in: request)
            XCTAssertEqual(fields["q"], testCase.source, testCase.name)
            XCTAssertEqual(fields["from"], "auto", testCase.name)
            XCTAssertEqual(fields["to"], testCase.expectedTarget, testCase.name)
            XCTAssertNil(fields["appid"], testCase.name)
            XCTAssertNil(fields["sign"], testCase.name)
        }
    }

    func testMakeBaiduTranslateRequestHonorsTargetLanguagePreferenceOverAutoDetection() throws {
        let cases: [(name: String, source: String, preference: TargetLanguage, expectedTarget: String)] = [
            (
                name: "already-English source flips to Chinese to avoid identity translation",
                source: "Ship the release notes today.",
                preference: .english,
                expectedTarget: "zh"
            ),
            (
                name: "already-Chinese source flips to English to avoid identity translation",
                source: "今天发布版本说明。",
                preference: .chinese,
                expectedTarget: "en"
            )
        ]

        for testCase in cases {
            var settings = makeBaiduSettings(apiKey: "baidu-token")
            settings.targetLanguage = testCase.preference

            let request = try TranslationService.makeBaiduTranslateRequest(
                source: testCase.source,
                settings: settings
            )

            let fields = try baiduFormBodyItems(in: request)
            XCTAssertEqual(fields["to"], testCase.expectedTarget, testCase.name)
        }
    }

    func testMakeBaiduRequestRejectsBlankAPIKey() {
        let invalidAPIKeys = ["", "   \n\t  "]

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

    func testBaiduDecodeHandlesNestedTransResultResponse() async throws {
        let service = makeMockedTranslationService(body: #"{"data":{"trans_result":[{"src":"Hello","dst":"你好"}]}}"#)

        let translated = try await service.translate("Hello", settings: makeBaiduSettings(apiKey: "baidu-token"))

        XCTAssertEqual(translated, "你好")
    }

    func testBaiduDecodeReportsNumericErrorCode() async throws {
        let service = makeMockedTranslationService(body: #"{"error_code":401,"error_msg":"invalid api key"}"#)

        do {
            _ = try await service.translate("Hello", settings: makeBaiduSettings(apiKey: "baidu-token"))
            XCTFail("Expected Baidu error response to throw")
        } catch {
            XCTAssertEqual(
                error as? TranslationError,
                .requestFailed(status: 401, body: "百度翻译鉴权失败，请检查 API Key 是否正确并已开通大模型文本翻译 API")
            )
            XCTAssertFalse(error.localizedDescription.contains("invalid api key"))
        }
    }

    func testRawEnglishHTTPErrorFallsBackToChineseMessage() async throws {
        let service = makeMockedTranslationService(body: "Internal Server Error", statusCode: 500)

        do {
            _ = try await service.translate("Hello", settings: makeGoogleSettings(apiKey: "google-token"))
            XCTFail("Expected HTTP error to throw")
        } catch {
            XCTAssertEqual(
                error as? TranslationError,
                .requestFailed(status: 500, body: "Google 翻译服务暂时不可用，请稍后重试")
            )
            XCTAssertFalse(error.localizedDescription.contains("Internal Server Error"))
        }
    }

    func testUserFacingErrorMessageMapsURLSessionEnglishErrorsToChinese() {
        let message = TranslationService.userFacingErrorMessage(URLError(.timedOut), provider: .deepSeek)

        XCTAssertEqual(message, "翻译请求超时，请稍后重试")
        XCTAssertFalse(message.localizedCaseInsensitiveContains("timed out"))
    }

    func testResolveBaiduTranslateURLNormalizesBaseURLsAndRejectsEmptyBaseURL() throws {
        let trailingSlashURL = try TranslationService.resolveBaiduTranslateURL(" https://fanyi-api.baidu.com/ ")
        XCTAssertEqual(trailingSlashURL.absoluteString, "https://fanyi-api.baidu.com/ait/api/aiTextTranslate")

        let endpointURL = try TranslationService.resolveBaiduTranslateURL(
            "https://fanyi-api.baidu.com/ait/api/aiTextTranslate/"
        )
        XCTAssertEqual(endpointURL.absoluteString, "https://fanyi-api.baidu.com/ait/api/aiTextTranslate")

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

    func testGoogleHTTPErrorShowsReadableMessage() async throws {
        let service = makeMockedTranslationService(
            body: #"{"error":{"code":403,"message":"Cloud Translation API has not been used in project before or it is disabled.","status":"PERMISSION_DENIED"}}"#,
            statusCode: 403
        )

        do {
            _ = try await service.translate("Hello", settings: makeGoogleSettings(apiKey: "google-token"))
            XCTFail("Expected Google HTTP error to throw")
        } catch {
            XCTAssertEqual(
                error as? TranslationError,
                .requestFailed(status: 403, body: "请在 Google Cloud 启用 Cloud Translation API，并确认 API Key 有权限")
            )
            XCTAssertFalse(error.localizedDescription.contains(#""error""#))
            XCTAssertFalse(error.localizedDescription.contains("Cloud Translation API has not been used"))
        }
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

    private func makeMockedTranslationService(body: String, statusCode: Int = 200) -> TranslationService {
        MockURLProtocol.statusCode = statusCode
        MockURLProtocol.responseData = Data(body.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return TranslationService(session: URLSession(configuration: configuration))
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

private final class MockURLProtocol: URLProtocol {
    static var responseData = Data()
    static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
