import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TranslationError: LocalizedError, Equatable {
    case missingBaseURL
    case invalidResponse
    case requestFailed(status: Int, body: String)
    case missingTranslatedText
    case invalidTranslationDirection(target: String)

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
        case let .invalidTranslationDirection(target):
            return "模型返回了错误语言，目标语言应为 \(target)"
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

        for attempt in 0..<2 {
            let retryInstruction = attempt == 0 ? nil : Self.retryInstruction(for: source)
            let request = try Self.makeRequest(source: source, settings: settings, retryInstruction: retryInstruction)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw TranslationError.requestFailed(status: httpResponse.statusCode, body: body)
            }

            let translated = try Self.decodeTranslatedText(data, provider: settings.provider)
            if Self.isTranslationDirectionValid(source: source, translated: translated) {
                return translated
            }
        }

        throw TranslationError.invalidTranslationDirection(target: Self.detectTargetLanguage(source))
    }

    public static func makeRequest(source: String, settings: AppSettings) throws -> URLRequest {
        try makeRequest(source: source, settings: settings, retryInstruction: nil)
    }

    private static func makeRequest(source: String, settings: AppSettings, retryInstruction: String?) throws -> URLRequest {
        switch settings.provider {
        case .openAICompatible, .deepSeek:
            return try makeOpenAICompatibleRequest(source: source, settings: settings, retryInstruction: retryInstruction)
        case .ollama:
            return try makeOllamaRequest(source: source, settings: settings, retryInstruction: retryInstruction)
        }
    }

    public static func makeOpenAICompatibleRequest(source: String, settings: AppSettings, retryInstruction: String? = nil) throws -> URLRequest {
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
            messages: messages(for: source, retryInstruction: retryInstruction)
        ))
        return request
    }

    public static func makeOllamaRequest(source: String, settings: AppSettings, retryInstruction: String? = nil) throws -> URLRequest {
        let url = try resolveOllamaChatURL(settings.baseURL)
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaChatRequest(
            model: settings.model,
            messages: messages(for: source, retryInstruction: retryInstruction),
            stream: false,
            options: .init(
                temperature: settings.temperature,
                topP: settings.topP,
                numPredict: settings.maxTokens
            )
        ))
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

    public static func detectTargetLanguage(_ text: String) -> String {
        isChineseSource(text) ? "English" : "Simplified Chinese"
    }

    private static func isChineseSource(_ text: String) -> Bool {
        let hasHan = text.range(of: #"[\u{3400}-\u{9fff}]"#, options: .regularExpression) != nil
        let hasJapaneseKana = text.range(of: #"[\u{3040}-\u{30ff}]"#, options: .regularExpression) != nil
        let hasHangul = text.range(of: #"[\u{ac00}-\u{d7af}]"#, options: .regularExpression) != nil
        return hasHan && !hasJapaneseKana && !hasHangul
    }

    private static func messages(for source: String, retryInstruction: String?) -> [ChatMessage] {
        var userContent = "Target language: \(detectTargetLanguage(source))\nRule: Chinese source -> English only; non-Chinese source -> Simplified Chinese only.\n\nText:\n\(source)"
        if let retryInstruction {
            userContent = "\(retryInstruction)\n\n\(userContent)"
        }

        return [
            .init(
                role: "system",
                content: [
                    "You are a deterministic translation engine.",
                    "Choose the target language strictly by this rule: if the source contains Chinese text, translate the natural-language content into English; otherwise translate the natural-language content into Simplified Chinese.",
                    "Never translate Chinese into Chinese, and never translate non-Chinese text into English.",
                    "Never return the source unchanged when natural-language text is present.",
                    "Return only the translated text.",
                    "Preserve markdown structure, code blocks, inline code, identifiers, URLs, placeholders, names, and numbers unless they are part of natural-language prose.",
                    "Do not explain the translation."
                ].joined(separator: " ")
            ),
            .init(role: "user", content: userContent)
        ]
    }

    private static func retryInstruction(for source: String) -> String {
        let target = detectTargetLanguage(source)
        return "The previous output used the wrong language or copied the source. Retry now. Output must be \(target). Do not include the original text unless it is code, a URL, a placeholder, a number, or a proper name."
    }

    private static func decodeTranslatedText(_ data: Data, provider: ModelProvider) throws -> String {
        switch provider {
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
        }
    }

    private static func isTranslationDirectionValid(source: String, translated: String) -> Bool {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTranslated = translated.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedSource != normalizedTranslated else { return false }

        switch detectTargetLanguage(source) {
        case "English":
            return !containsChineseText(translated)
        default:
            return containsChineseText(translated)
        }
    }

    private static func containsChineseText(_ text: String) -> Bool {
        text.range(of: #"[\u{3400}-\u{9fff}]"#, options: .regularExpression) != nil
    }

    private static func trimBaseURL(_ baseURL: String) -> String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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
