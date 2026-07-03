import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TranslationError: LocalizedError, Equatable {
    case missingBaseURL
    case invalidResponse
    case requestFailed(status: Int, body: String)
    case missingTranslatedText

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
        }
    }

    public static func makeRequest(source: String, settings: AppSettings) throws -> URLRequest {
        switch settings.provider {
        case .openAICompatible, .deepSeek:
            return try makeOpenAICompatibleRequest(source: source, settings: settings)
        case .ollama:
            return try makeOllamaRequest(source: source, settings: settings)
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
            messages: messages(for: source)
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
            messages: messages(for: source),
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
        text.range(of: #"[\u{3400}-\u{9fff}]"#, options: .regularExpression) == nil
            ? "Simplified Chinese"
            : "English"
    }

    private static func messages(for source: String) -> [ChatMessage] {
        [
            .init(
                role: "system",
                content: [
                    "You are a translation engine for Chinese and English.",
                    "Translate the user text into the target language.",
                    "Return only the translated text.",
                    "Preserve markdown, code blocks, names, URLs, and numbers.",
                    "Do not explain the translation."
                ].joined(separator: " ")
            ),
            .init(
                role: "user",
                content: "Target language: \(detectTargetLanguage(source))\n\nText:\n\(source)"
            )
        ]
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
