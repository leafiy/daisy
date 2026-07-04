import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TranslationError: LocalizedError, Equatable {
    case missingBaseURL
    case invalidResponse
    case requestFailed(status: Int, body: String)
    case missingTranslatedText
    case missingBaiduCredentials

    public var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "请先配置 LLM Base URL"
        case .invalidResponse:
            return "LLM 响应格式无效"
        case let .requestFailed(status, body):
            return "LLM 请求失败：\(status) \(body.prefix(300))"
        case .missingTranslatedText:
            return "LLM 响应里没有翻译结果"
        case .missingBaiduCredentials:
            return "请在 API Key 里按 APPID:密钥 格式配置百度翻译凭证"
        }
    }
}

public struct TranslationService {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func translate(_ text: String, settings: AppSettings) async throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "" }

        let request = try Self.makeRequest(source: source, settings: settings)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.requestFailed(status: httpResponse.statusCode, body: body)
        }

        return try Self.decodeTranslatedText(data, settings: settings)
    }

    public static func makeRequest(source: String, settings: AppSettings) throws -> URLRequest {
        switch settings.provider {
        case .openAICompatible, .deepSeek:
            return try makeOpenAICompatibleRequest(source: source, settings: settings)
        case .ollama:
            return try makeOllamaRequest(source: source, settings: settings)
        case .google:
            return try makeGoogleTranslateRequest(source: source, settings: settings)
        case .baidu:
            return try makeBaiduTranslateRequest(source: source, settings: settings)
        }
    }

    public static func makeOpenAICompatibleRequest(source: String, settings: AppSettings) throws -> URLRequest {
        let url = try resolveChatURL(settings.baseURL)
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(OpenAIChatRequest(
            model: settings.model,
            temperature: settings.temperature,
            topP: settings.topP,
            maxTokens: settings.maxTokens,
            stream: false,
            messages: messages(for: source, preference: settings.targetLanguage)
        ))
        return request
    }

    public static func makeOllamaRequest(source: String, settings: AppSettings) throws -> URLRequest {
        let url = try resolveOllamaChatURL(settings.baseURL)
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaChatRequest(
            model: settings.model,
            messages: messages(for: source, preference: settings.targetLanguage),
            stream: false,
            options: .init(
                temperature: settings.temperature,
                topP: settings.topP,
                numPredict: settings.maxTokens
            )
        ))
        return request
    }

    public static func makeGoogleTranslateRequest(source: String, settings: AppSettings) throws -> URLRequest {
        let target = googleTargetLanguage(for: source, preference: settings.targetLanguage)
        let apiKey = trimmedAPIKey(settings)
        if apiKey.isEmpty {
            let url = try resolveGoogleFreeTranslateURL(settings.baseURL, target: target, query: source)
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.httpMethod = "GET"
            return request
        }

        let url = try resolveGoogleCloudTranslateURL(settings.baseURL, apiKey: apiKey)
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GoogleCloudTranslateRequest(
            q: [source],
            target: target,
            format: "text"
        ))
        return request
    }

    public static func makeBaiduTranslateRequest(
        source: String,
        settings: AppSettings,
        salt: String = String(UInt32.random(in: 100_000...999_999))
    ) throws -> URLRequest {
        let credentials = try baiduCredentials(settings)
        let target = baiduTargetLanguage(for: source, preference: settings.targetLanguage)
        let sign = baiduSignature(appID: credentials.appID, query: source, salt: salt, secret: credentials.secret)

        let url = try resolveBaiduTranslateURL(settings.baseURL)
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "q=\(percentEncode(source))&from=auto&to=\(percentEncode(target))"
            + "&appid=\(percentEncode(credentials.appID))&salt=\(percentEncode(salt))&sign=\(sign)"
        request.httpBody = Data(body.utf8)
        return request
    }

    public static func resolveChatURL(_ baseURL: String) throws -> URL {
        let trimmed = trimBaseURL(baseURL)
        guard !trimmed.isEmpty else { throw TranslationError.missingBaseURL }

        let endpoint: String
        if trimmed.hasSuffix("/chat/completions") {
            endpoint = trimmed
        } else if trimmed.hasSuffix("/v1") {
            endpoint = "\(trimmed)/chat/completions"
        } else {
            endpoint = "\(trimmed)/v1/chat/completions"
        }

        guard let url = URL(string: endpoint) else { throw TranslationError.missingBaseURL }
        return url
    }

    public static func resolveOllamaChatURL(_ baseURL: String) throws -> URL {
        let trimmed = trimBaseURL(baseURL)
        guard !trimmed.isEmpty else { throw TranslationError.missingBaseURL }

        let endpoint: String
        if trimmed.hasSuffix("/api/chat") {
            endpoint = trimmed
        } else if trimmed.hasSuffix("/api") {
            endpoint = "\(trimmed)/chat"
        } else {
            endpoint = "\(trimmed)/api/chat"
        }

        guard let url = URL(string: endpoint) else { throw TranslationError.missingBaseURL }
        return url
    }

    public static func resolveGoogleFreeTranslateURL(_ baseURL: String, target: String, query: String) throws -> URL {
        let trimmed = trimBaseURL(baseURL)
        guard !trimmed.isEmpty else { throw TranslationError.missingBaseURL }

        let endpoint = trimmed.hasSuffix("/translate_a/single") ? trimmed : "\(trimmed)/translate_a/single"
        guard var components = URLComponents(string: endpoint) else { throw TranslationError.missingBaseURL }
        components.percentEncodedQuery = "client=gtx&sl=auto&tl=\(percentEncode(target))&dt=t&q=\(percentEncode(query))"
        guard let url = components.url else { throw TranslationError.missingBaseURL }
        return url
    }

    public static func resolveGoogleCloudTranslateURL(_ baseURL: String, apiKey: String) throws -> URL {
        let trimmed = trimBaseURL(baseURL)
        guard !trimmed.isEmpty else { throw TranslationError.missingBaseURL }

        let endpoint = trimmed.hasSuffix("/language/translate/v2") ? trimmed : "\(trimmed)/language/translate/v2"
        guard var components = URLComponents(string: endpoint) else { throw TranslationError.missingBaseURL }
        components.percentEncodedQuery = "key=\(percentEncode(apiKey))"
        guard let url = components.url else { throw TranslationError.missingBaseURL }
        return url
    }

    public static func googleTargetLanguage(for source: String, preference: TargetLanguage) -> String {
        translatesToEnglish(source: source, preference: preference) ? "en" : "zh-CN"
    }

    public static func resolveBaiduTranslateURL(_ baseURL: String) throws -> URL {
        let trimmed = trimBaseURL(baseURL)
        guard !trimmed.isEmpty else { throw TranslationError.missingBaseURL }

        let endpoint = trimmed.hasSuffix("/api/trans/vip/translate") ? trimmed : "\(trimmed)/api/trans/vip/translate"
        guard let url = URL(string: endpoint) else { throw TranslationError.missingBaseURL }
        return url
    }

    public static func baiduTargetLanguage(for source: String, preference: TargetLanguage) -> String {
        translatesToEnglish(source: source, preference: preference) ? "en" : "zh"
    }

    public static func translatesToEnglish(source: String, preference: TargetLanguage) -> Bool {
        switch preference {
        case .auto:
            return containsChineseText(source)
        case .english:
            return true
        case .chinese:
            return false
        }
    }

    public static func baiduSignature(appID: String, query: String, salt: String, secret: String) -> String {
        MD5.hex(appID + query + salt + secret)
    }

    static func baiduCredentials(_ settings: AppSettings) throws -> (appID: String, secret: String) {
        let raw = trimmedAPIKey(settings)
        guard let separator = raw.firstIndex(of: ":") else { throw TranslationError.missingBaiduCredentials }
        let appID = String(raw[..<separator])
        let secret = String(raw[raw.index(after: separator)...])
        guard !appID.isEmpty, !secret.isEmpty else { throw TranslationError.missingBaiduCredentials }
        return (appID, secret)
    }

    private static func messages(for source: String, preference: TargetLanguage) -> [ChatMessage] {
        [.init(role: "user", content: prompt(for: source, preference: preference))]
    }

    private static func prompt(for source: String, preference: TargetLanguage) -> String {
        if translatesToEnglish(source: source, preference: preference) {
            return "将以下文本翻译为英语，注意只需要输出翻译后的结果，不要额外解释：\n\n\(source)"
        }
        return "Translate the following text into Chinese. Note that you should only output the translated result without any additional explanation:\n\n\(source)"
    }

    private static func decodeTranslatedText(_ data: Data, settings: AppSettings) throws -> String {
        switch settings.provider {
        case .openAICompatible, .deepSeek:
            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            guard let translated = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                  !translated.isEmpty else {
                throw TranslationError.missingTranslatedText
            }
            return translated
        case .ollama:
            let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
            let translated = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translated.isEmpty else { throw TranslationError.missingTranslatedText }
            return translated
        case .google:
            return try decodeGoogleTranslatedText(data, usesCloudAPI: !trimmedAPIKey(settings).isEmpty)
        case .baidu:
            return try decodeBaiduTranslatedText(data)
        }
    }

    private static func decodeGoogleTranslatedText(_ data: Data, usesCloudAPI: Bool) throws -> String {
        if usesCloudAPI {
            let decoded = try JSONDecoder().decode(GoogleCloudTranslateResponse.self, from: data)
            guard let translated = decoded.data.translations.first?.translatedText.trimmingCharacters(in: .whitespacesAndNewlines),
                  !translated.isEmpty else {
                throw TranslationError.missingTranslatedText
            }
            return translated
        }

        guard let root = try? JSONSerialization.jsonObject(with: data), let sentences = (root as? [Any])?.first as? [Any] else {
            throw TranslationError.invalidResponse
        }
        let translated = sentences
            .compactMap { ($0 as? [Any])?.first as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else { throw TranslationError.missingTranslatedText }
        return translated
    }

    private static func decodeBaiduTranslatedText(_ data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(BaiduTranslateResponse.self, from: data)
        if let errorCode = decoded.errorCode, errorCode != "0" {
            throw TranslationError.requestFailed(status: Int(errorCode) ?? -1, body: decoded.errorMsg ?? errorCode)
        }
        guard let results = decoded.transResult else { throw TranslationError.missingTranslatedText }
        let translated = results
            .map(\.dst)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else { throw TranslationError.missingTranslatedText }
        return translated
    }

    private static func containsChineseText(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) }
    }

    private static func trimBaseURL(_ baseURL: String) -> String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func trimmedAPIKey(_ settings: AppSettings) -> String {
        settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

struct OpenAIChatRequest: Encodable {
    let model: String
    let temperature: Double
    let topP: Double
    let maxTokens: Int
    let stream: Bool
    let messages: [ChatMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case stream
        case messages
    }
}

struct OllamaChatRequest: Encodable {
    struct Options: Encodable {
        let temperature: Double
        let topP: Double
        let numPredict: Int

        enum CodingKeys: String, CodingKey {
            case temperature
            case topP = "top_p"
            case numPredict = "num_predict"
        }
    }

    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let options: Options
}

struct ChatMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        let message: ChatMessage
    }

    let choices: [Choice]
}

struct OllamaChatResponse: Decodable {
    let message: ChatMessage
}

struct GoogleCloudTranslateRequest: Encodable {
    let q: [String]
    let target: String
    let format: String
}

struct GoogleCloudTranslateResponse: Decodable {
    struct Payload: Decodable {
        let translations: [Translation]
    }

    struct Translation: Decodable {
        let translatedText: String
    }

    let data: Payload
}

struct BaiduTranslateResponse: Decodable {
    struct Item: Decodable {
        let src: String
        let dst: String
    }

    let errorCode: String?
    let errorMsg: String?
    let transResult: [Item]?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMsg = "error_msg"
        case transResult = "trans_result"
    }
}
