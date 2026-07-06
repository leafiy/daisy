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
    case networkFailed(String)
    case appleSystemTranslationUnavailable
    case appleSystemTranslationUnsupported
    case appleSystemTranslationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "请先配置当前翻译服务的 Base URL"
        case .invalidResponse:
            return "翻译服务响应格式无效"
        case let .requestFailed(status, body):
            if body.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) {
                return "翻译请求失败：\(status) \(body.prefix(160))"
            }
            return "翻译请求失败：\(status)，请检查服务配置后重试"
        case .missingTranslatedText:
            return "翻译服务响应里没有译文"
        case .missingBaiduCredentials:
            return "请先填写百度翻译 API Key"
        case let .networkFailed(message):
            return message
        case .appleSystemTranslationUnavailable:
            return "Apple 系统翻译需要 macOS 15 或更新版本"
        case .appleSystemTranslationUnsupported:
            return "Apple 系统翻译暂不支持当前语言方向"
        case let .appleSystemTranslationFailed(message):
            return "Apple 系统翻译失败：\(message)"
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

        guard settings.provider != .appleSystem else { throw TranslationError.appleSystemTranslationUnavailable }

        let request = try Self.makeRequest(source: source, settings: settings)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw TranslationError.networkFailed(Self.networkErrorMessage(error, provider: settings.provider))
        } catch {
            throw TranslationError.networkFailed(Self.userFacingErrorMessage(error, provider: settings.provider))
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.errorMessage(from: data, statusCode: httpResponse.statusCode, provider: settings.provider)
            throw TranslationError.requestFailed(status: httpResponse.statusCode, body: message)
        }

        do {
            return try Self.decodeTranslatedText(data, settings: settings)
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.invalidResponse
        }
    }

    public static func makeRequest(source: String, settings: AppSettings) throws -> URLRequest {
        switch settings.provider {
        case .appleSystem:
            throw TranslationError.appleSystemTranslationUnavailable
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
        let url = settings.provider == .deepSeek
            ? try resolveDeepSeekChatURL(settings.baseURL)
            : try resolveChatURL(settings.baseURL)
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
        settings: AppSettings
    ) throws -> URLRequest {
        let apiKey = try baiduAPIKey(settings)
        let target = baiduTargetLanguage(for: source, preference: settings.targetLanguage)

        let url = try resolveBaiduTranslateURL(settings.baseURL)
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body = "q=\(percentEncode(source))&from=auto&to=\(percentEncode(target))"
        request.httpBody = Data(body.utf8)
        return request
    }

    public static func resolveChatURL(_ baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty else {
            throw TranslationError.missingBaseURL
        }
        guard var components = URLComponents(string: trimmed) else {
            throw TranslationError.missingBaseURL
        }

        let path = chatCompletionsPath(for: components.path, hasHost: components.host != nil)
        components.path = path
        guard let url = components.url else { throw TranslationError.missingBaseURL }
        return url
    }

    public static func resolveDeepSeekChatURL(_ baseURL: String) throws -> URL {
        let trimmed = trimBaseURL(baseURL)
        guard !trimmed.isEmpty else { throw TranslationError.missingBaseURL }

        let endpoint: String
        if trimmed.hasSuffix("/v1/chat/completions") {
            endpoint = String(trimmed.dropLast("/v1/chat/completions".count)) + "/chat/completions"
        } else if trimmed.hasSuffix("/chat/completions") {
            endpoint = trimmed
        } else if trimmed.hasSuffix("/v1") {
            endpoint = String(trimmed.dropLast("/v1".count)) + "/chat/completions"
        } else {
            endpoint = "\(trimmed)/chat/completions"
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

        let endpoint = trimmed.hasSuffix("/ait/api/aiTextTranslate") ? trimmed : "\(trimmed)/ait/api/aiTextTranslate"
        guard let url = URL(string: endpoint) else { throw TranslationError.missingBaseURL }
        return url
    }

    public static func baiduTargetLanguage(for source: String, preference: TargetLanguage) -> String {
        translatesToEnglish(source: source, preference: preference) ? "en" : "zh"
    }

    public static func translatesToEnglish(source: String, preference: TargetLanguage) -> Bool {
        let containsChinese = containsChineseText(source)
        switch preference {
        case .auto:
            return containsChinese
        case .english:
            // English-only source with an English target would round-trip
            // unchanged; translate to Chinese instead of silently no-op'ing.
            if !containsChinese && containsLatinText(source) {
                return false
            }
            return true
        case .chinese:
            // Chinese-only source with a Chinese target likewise flips.
            if containsChinese && !containsLatinText(source) {
                return true
            }
            return false
        }
    }

    public static func baiduSignature(appID: String, query: String, salt: String, secret: String) -> String {
        MD5.hex(appID + query + salt + secret)
    }

    static func baiduAPIKey(_ settings: AppSettings) throws -> String {
        let apiKey = trimmedAPIKey(settings)
        guard !apiKey.isEmpty else { throw TranslationError.missingBaiduCredentials }
        return apiKey
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
        case .appleSystem:
            throw TranslationError.appleSystemTranslationUnavailable
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
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.invalidResponse
        }
        if let errorCode = stringValue(root["error_code"] ?? root["errno"] ?? root["code"]),
           errorCode != "0" {
            let message = stringValue(root["error_msg"] ?? root["error"] ?? root["msg"] ?? root["message"]) ?? errorCode
            let statusCode = Int(errorCode) ?? -1
            throw TranslationError.requestFailed(
                status: statusCode,
                body: friendlyErrorMessage(message, statusCode: statusCode, provider: .baidu)
            )
        }
        let translated = baiduTranslatedText(in: root)
        guard !translated.isEmpty else { throw TranslationError.missingTranslatedText }
        return translated
    }

    private static func baiduTranslatedText(in root: [String: Any]) -> String {
        if let result = transResultText(root["trans_result"]) {
            return result
        }
        if let data = root["data"] as? [String: Any] {
            if let result = transResultText(data["trans_result"]) {
                return result
            }
            if let result = stringValue(data["dst"] ?? data["result"] ?? data["translated_text"] ?? data["translation"]) {
                return result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let result = stringValue(root["dst"] ?? root["result"] ?? root["translated_text"] ?? root["translation"]) {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    public static func userFacingErrorMessage(_ error: Error, provider: ModelProvider? = nil) -> String {
        if error is CancellationError {
            return "操作已取消"
        }
        if let translationError = error as? TranslationError {
            return translationError.localizedDescription
        }
        if let urlError = error as? URLError {
            return networkErrorMessage(urlError, provider: provider)
        }
        if error is DecodingError {
            return TranslationError.invalidResponse.localizedDescription
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return genericFailureMessage(provider: provider)
        }
        if containsChineseText(message) {
            return message
        }
        if message.localizedCaseInsensitiveContains("timed out") {
            return "翻译请求超时，请稍后重试"
        }
        if message.localizedCaseInsensitiveContains("offline") ||
            message.localizedCaseInsensitiveContains("internet") ||
            message.localizedCaseInsensitiveContains("network") {
            return "网络不可用，请检查网络连接"
        }
        if message.localizedCaseInsensitiveContains("cannot connect") ||
            message.localizedCaseInsensitiveContains("could not connect") ||
            message.localizedCaseInsensitiveContains("connection refused") {
            return "无法连接翻译服务，请检查服务地址或本地服务是否已启动"
        }
        if message.localizedCaseInsensitiveContains("authentication") ||
            message.localizedCaseInsensitiveContains("unauthorized") ||
            message.localizedCaseInsensitiveContains("invalid api key") {
            return "服务鉴权失败，请检查 API Key 是否正确"
        }
        return genericFailureMessage(provider: provider)
    }

    private static func errorMessage(from data: Data, statusCode: Int, provider: ModelProvider) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = root["error"] as? [String: Any] {
                let message = stringValue(error["message"] ?? error["status"] ?? error["code"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return friendlyErrorMessage(message, statusCode: statusCode, provider: provider)
            }
            let message = stringValue(root["error_msg"] ?? root["message"] ?? root["msg"] ?? root["error"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return friendlyErrorMessage(message, statusCode: statusCode, provider: provider)
        }

        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return friendlyErrorMessage(message, statusCode: statusCode, provider: provider)
    }

    private static func friendlyErrorMessage(_ message: String?, statusCode: Int, provider: ModelProvider) -> String {
        let message = message ?? ""
        switch provider {
        case .google:
            if statusCode == 403,
               message.localizedCaseInsensitiveContains("Cloud Translation API") {
                return "请在 Google Cloud 启用 Cloud Translation API，并确认 API Key 有权限"
            }
            if statusCode == 400,
               message.localizedCaseInsensitiveContains("API key") {
                return "Google API Key 无效，请检查设置里的 API Key"
            }
            if statusCode == 403 {
                return "Google 翻译权限不足，请检查 API Key、项目配额和 Cloud Translation API 是否已启用"
            }
            if statusCode == 429 {
                return "Google 翻译调用过于频繁或配额不足，请稍后重试或检查项目配额"
            }
        case .baidu:
            if statusCode == 401 || statusCode == 403 {
                return "百度翻译鉴权失败，请检查 API Key 是否正确并已开通大模型文本翻译 API"
            }
            if statusCode == 429 || message.localizedCaseInsensitiveContains("quota") {
                return "百度翻译调用过于频繁或额度不足，请稍后重试或检查账号额度"
            }
            if statusCode == 400 {
                return "百度翻译请求参数无效，请检查文本内容和服务配置"
            }
        case .deepSeek:
            if statusCode == 401 || statusCode == 403 {
                return "DeepSeek 鉴权失败，请检查 API Key 是否正确"
            }
            if statusCode == 402 ||
                statusCode == 429 ||
                message.localizedCaseInsensitiveContains("insufficient") ||
                message.localizedCaseInsensitiveContains("balance") ||
                message.localizedCaseInsensitiveContains("quota") {
                return "DeepSeek 额度或余额不足，请检查账号余额和用量限制"
            }
            if statusCode == 400,
               message.localizedCaseInsensitiveContains("model") {
                return "DeepSeek 模型不可用，请检查模型名称"
            }
            if statusCode == 404 {
                return "DeepSeek 接口不可用，请稍后重试"
            }
        case .openAICompatible:
            if statusCode == 401 || statusCode == 403 ||
                message.localizedCaseInsensitiveContains("authentication") ||
                message.localizedCaseInsensitiveContains("unauthorized") ||
                message.localizedCaseInsensitiveContains("invalid api key") {
                return "服务鉴权失败，请检查 API Key 是否正确"
            }
            if statusCode == 404 {
                return "翻译服务接口不存在，请检查 Base URL 和模型服务路径"
            }
            if statusCode == 429 {
                return "翻译服务调用过于频繁或配额不足，请稍后重试"
            }
        case .ollama:
            if statusCode == 404 ||
                message.localizedCaseInsensitiveContains("model") ||
                message.localizedCaseInsensitiveContains("not found") {
                return "Ollama 模型不可用，请确认模型已下载并且名称正确"
            }
            if statusCode == 500 {
                return "Ollama 本地服务返回错误，请检查服务状态和模型日志"
            }
        default:
            break
        }
        return genericHTTPErrorMessage(statusCode: statusCode, provider: provider)
    }

    private static func networkErrorMessage(_ error: URLError, provider: ModelProvider?) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "网络不可用，请检查网络连接"
        case .timedOut:
            return "翻译请求超时，请稍后重试"
        case .cannotFindHost, .dnsLookupFailed:
            return "找不到翻译服务地址，请检查 Base URL"
        case .cannotConnectToHost:
            if provider == .ollama {
                return "无法连接 Ollama，请确认 Ollama 已启动"
            }
            return "无法连接翻译服务，请检查网络或服务地址"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid:
            return "翻译服务证书验证失败，请检查服务地址或网络代理"
        case .badURL, .unsupportedURL:
            return "翻译服务地址无效，请检查 Base URL"
        case .cancelled:
            return "操作已取消"
        default:
            return genericFailureMessage(provider: provider)
        }
    }

    private static func genericHTTPErrorMessage(statusCode: Int, provider: ModelProvider) -> String {
        switch statusCode {
        case 400:
            return "\(providerDisplayName(provider))请求参数无效，请检查服务配置"
        case 401, 403:
            return "\(providerDisplayName(provider))鉴权失败，请检查 API Key 或服务权限"
        case 404:
            return "\(providerDisplayName(provider))接口不存在，请检查服务地址和模型名称"
        case 408:
            return "\(providerDisplayName(provider))请求超时，请稍后重试"
        case 413:
            return "文本过长，请缩短原文后再翻译"
        case 422:
            return "\(providerDisplayName(provider))无法处理当前请求，请检查模型名称和文本内容"
        case 429:
            return "\(providerDisplayName(provider))调用过于频繁或配额不足，请稍后重试"
        case 500...599:
            return "\(providerDisplayName(provider))服务暂时不可用，请稍后重试"
        default:
            return "\(providerDisplayName(provider))请求失败，请稍后重试"
        }
    }

    private static func genericFailureMessage(provider: ModelProvider?) -> String {
        if let provider {
            return "\(providerDisplayName(provider))翻译失败，请稍后重试"
        }
        return "翻译失败，请稍后重试"
    }

    private static func providerDisplayName(_ provider: ModelProvider) -> String {
        switch provider {
        case .appleSystem:
            return "Apple 系统翻译"
        case .openAICompatible:
            return "当前翻译服务"
        case .ollama:
            return "Ollama"
        case .deepSeek:
            return "DeepSeek"
        case .google:
            return "Google 翻译"
        case .baidu:
            return "百度翻译"
        }
    }

    private static func transResultText(_ value: Any?) -> String? {
        if let results = value as? [[String: Any]] {
            let translated = results
                .compactMap { stringValue($0["dst"] ?? $0["target"] ?? $0["translated_text"]) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return translated.isEmpty ? nil : translated
        }
        if let result = value as? [String: Any] {
            return stringValue(result["dst"] ?? result["target"] ?? result["translated_text"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return stringValue(value)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as Int:
            return String(value)
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func containsChineseText(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) }
    }

    private static func containsLatinText(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x0041...0x005a).contains($0.value) || (0x0061...0x007a).contains($0.value)
        }
    }

    private static func trimBaseURL(_ baseURL: String) -> String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func chatCompletionsPath(for rawPath: String, hasHost: Bool) -> String {
        var path = rawPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if path.isEmpty {
            return hasHost ? "/v1/chat/completions" : "v1/chat/completions"
        }
        if path.hasSuffix("/chat/completions") {
            return path
        }
        if path.hasSuffix("/v1") {
            return "\(path)/chat/completions"
        }
        return "\(path)/v1/chat/completions"
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
