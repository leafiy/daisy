import Foundation

public enum ModelProvider: String, Codable, CaseIterable, Equatable {
    case openAICompatible = "openai-compatible"
    case ollama
    case deepSeek = "deepseek"
    case google
    case baidu
}

public enum TargetLanguage: String, Codable, CaseIterable, Equatable {
    case auto
    case english
    case chinese
}

public struct AppSettings: Codable, Equatable {
    public var provider: ModelProvider
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var temperature: Double
    public var topP: Double
    public var maxTokens: Int
    public var debounceMilliseconds: Int
    public var autoTranslate: Bool
    public var watchClipboard: Bool
    public var autoCopy: Bool
    public var autoPaste: Bool
    public var alwaysOnTop: Bool
    public var quickTranslateEnabled: Bool
    public var quickTranslateShortcut: String
    public var targetLanguage: TargetLanguage

    public init(
        baseURL: String,
        apiKey: String,
        model: String,
        temperature: Double,
        topP: Double,
        maxTokens: Int,
        debounceMilliseconds: Int,
        autoTranslate: Bool,
        watchClipboard: Bool,
        autoCopy: Bool,
        autoPaste: Bool,
        alwaysOnTop: Bool,
        quickTranslateEnabled: Bool = false,
        quickTranslateShortcut: String = "Command+Shift+V",
        provider: ModelProvider = .openAICompatible,
        targetLanguage: TargetLanguage = .auto
    ) {
        self.provider = provider
        self.targetLanguage = targetLanguage
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.quickTranslateEnabled = quickTranslateEnabled
        self.quickTranslateShortcut = quickTranslateShortcut
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.debounceMilliseconds = debounceMilliseconds
        self.autoTranslate = autoTranslate
        self.watchClipboard = watchClipboard
        self.autoCopy = autoCopy
        self.autoPaste = autoPaste
        self.alwaysOnTop = alwaysOnTop
    }

    public static func defaults(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppSettings {
        let provider = ModelProvider(rawValue: environment["TT_PROVIDER"] ?? "") ?? .openAICompatible
        return AppSettings(
            baseURL: environment["TT_BASE_URL"] ?? defaultBaseURL(for: provider),
            apiKey: environment["TT_API_KEY"] ?? "",
            model: environment["TT_MODEL"] ?? defaultModel(for: provider),
            temperature: Double(environment["TT_TEMPERATURE"] ?? "") ?? 0.4,
            topP: Double(environment["TT_TOP_P"] ?? "") ?? 0.8,
            maxTokens: Int(environment["TT_MAX_TOKENS"] ?? "") ?? 8192,
            debounceMilliseconds: 650,
            autoTranslate: true,
            watchClipboard: false,
            autoCopy: true,
            autoPaste: false,
            alwaysOnTop: true,
            quickTranslateEnabled: false,
            quickTranslateShortcut: "Command+Shift+V",
            provider: provider,
            targetLanguage: TargetLanguage(rawValue: environment["TT_TARGET_LANGUAGE"] ?? "") ?? .auto
        )
    }

    public static func defaultBaseURL(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible:
            return "http://192.168.52.22:9940/services/qwen36-35b-a3b-mtp-q6/v1"
        case .ollama:
            return "http://localhost:11434"
        case .deepSeek:
            return "https://api.deepseek.com/v1"
        case .google:
            return "https://translate.googleapis.com"
        case .baidu:
            return "https://fanyi-api.baidu.com"
        }
    }

    public static func defaultModel(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible:
            return "qwen36-35b-a3b-mtp"
        case .ollama:
            return "qwen2.5"
        case .deepSeek:
            return "deepseek-chat"
        case .google, .baidu:
            return ""
        }
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case baseURL
        case apiKey
        case model
        case temperature
        case topP
        case maxTokens
        case debounceMilliseconds
        case autoTranslate
        case watchClipboard
        case autoCopy
        case autoPaste
        case alwaysOnTop
        case quickTranslateEnabled
        case quickTranslateShortcut
        case targetLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.defaults(environment: [:])
        provider = try container.decodeIfPresent(ModelProvider.self, forKey: .provider) ?? defaults.provider
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? defaults.baseURL
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? defaults.apiKey
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? defaults.temperature
        topP = try container.decodeIfPresent(Double.self, forKey: .topP) ?? defaults.topP
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? defaults.maxTokens
        debounceMilliseconds = try container.decodeIfPresent(Int.self, forKey: .debounceMilliseconds) ?? defaults.debounceMilliseconds
        autoTranslate = try container.decodeIfPresent(Bool.self, forKey: .autoTranslate) ?? defaults.autoTranslate
        watchClipboard = try container.decodeIfPresent(Bool.self, forKey: .watchClipboard) ?? defaults.watchClipboard
        autoCopy = try container.decodeIfPresent(Bool.self, forKey: .autoCopy) ?? defaults.autoCopy
        autoPaste = try container.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? defaults.autoPaste
        alwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? defaults.alwaysOnTop
        quickTranslateEnabled = try container.decodeIfPresent(Bool.self, forKey: .quickTranslateEnabled) ?? defaults.quickTranslateEnabled
        targetLanguage = try container.decodeIfPresent(TargetLanguage.self, forKey: .targetLanguage) ?? defaults.targetLanguage
        quickTranslateShortcut = try container.decodeIfPresent(String.self, forKey: .quickTranslateShortcut) ?? defaults.quickTranslateShortcut
    }
}
