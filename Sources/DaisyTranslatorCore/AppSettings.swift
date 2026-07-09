import Foundation

public enum ModelProvider: String, Codable, CaseIterable, Equatable {
    case appleSystem = "apple-system"
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

public struct ProviderConfiguration: Codable, Equatable {
    public var baseURL: String
    public var apiKey: String
    public var model: String

    public init(baseURL: String, apiKey: String, model: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }
}

public struct AppSettings: Codable, Equatable {
    public var provider: ModelProvider
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var providerConfigurations: [String: ProviderConfiguration]
    public var temperature: Double
    public var topP: Double
    public var maxTokens: Int
    public var debounceMilliseconds: Int
    public var autoTranslate: Bool
    public var watchClipboard: Bool
    public var autoCopy: Bool
    public var autoPaste: Bool
    public var alwaysOnTop: Bool
    public var minimalMode: Bool
    public var quickTranslateEnabled: Bool
    public var quickTranslateShortcut: String
    public var quickTranslateAutoCopy: Bool
    public var targetLanguage: TargetLanguage
    public var onboardingCompleted: Bool
    public var appLanguage: String

    public init(
        baseURL: String,
        apiKey: String,
        model: String,
        providerConfigurations: [String: ProviderConfiguration] = [:],
        temperature: Double,
        topP: Double,
        maxTokens: Int,
        debounceMilliseconds: Int,
        autoTranslate: Bool,
        watchClipboard: Bool,
        autoCopy: Bool,
        autoPaste: Bool,
        alwaysOnTop: Bool,
        minimalMode: Bool = false,
        quickTranslateEnabled: Bool = false,
        quickTranslateShortcut: String = "Command+Shift+V",
        quickTranslateAutoCopy: Bool = true,
        provider: ModelProvider = .appleSystem,
        targetLanguage: TargetLanguage = .auto,
        onboardingCompleted: Bool = false,
        appLanguage: String = "system"
    ) {
        self.provider = provider
        self.targetLanguage = targetLanguage
        self.onboardingCompleted = onboardingCompleted
        self.appLanguage = appLanguage
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.providerConfigurations = providerConfigurations
        self.quickTranslateEnabled = quickTranslateEnabled
        self.quickTranslateShortcut = quickTranslateShortcut
        self.quickTranslateAutoCopy = quickTranslateAutoCopy
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.debounceMilliseconds = debounceMilliseconds
        self.autoTranslate = autoTranslate
        self.watchClipboard = watchClipboard
        self.autoCopy = autoCopy
        self.autoPaste = autoPaste
        self.alwaysOnTop = alwaysOnTop
        self.minimalMode = minimalMode
    }

    public static func defaults(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppSettings {
        let provider = ModelProvider(rawValue: environment["TT_PROVIDER"] ?? "") ?? .appleSystem
        var providerConfigurations = defaultProviderConfigurations()
        providerConfigurations[provider.rawValue] = ProviderConfiguration(
            baseURL: environment["TT_BASE_URL"] ?? defaultBaseURL(for: provider),
            apiKey: environment["TT_API_KEY"] ?? "",
            model: environment["TT_MODEL"] ?? defaultModel(for: provider)
        )
        return AppSettings(
            baseURL: environment["TT_BASE_URL"] ?? defaultBaseURL(for: provider),
            apiKey: environment["TT_API_KEY"] ?? "",
            model: environment["TT_MODEL"] ?? defaultModel(for: provider),
            providerConfigurations: providerConfigurations,
            temperature: Double(environment["TT_TEMPERATURE"] ?? "") ?? 0.4,
            topP: Double(environment["TT_TOP_P"] ?? "") ?? 0.8,
            maxTokens: Int(environment["TT_MAX_TOKENS"] ?? "") ?? 8192,
            debounceMilliseconds: 650,
            autoTranslate: true,
            watchClipboard: false,
            autoCopy: true,
            autoPaste: false,
            alwaysOnTop: false,
            minimalMode: false,
            quickTranslateEnabled: false,
            quickTranslateShortcut: "Command+Shift+V",
            quickTranslateAutoCopy: true,
            provider: provider,
            targetLanguage: TargetLanguage(rawValue: environment["TT_TARGET_LANGUAGE"] ?? "") ?? .auto,
            appLanguage: "system"
        )
    }

    public static func defaultBaseURL(for provider: ModelProvider) -> String {
        switch provider {
        case .appleSystem:
            return ""
        case .openAICompatible:
            #if DEBUG
            return "http://192.168.52.22:9940/services/qwen36-35b-a3b-mtp-q6/v1"
            #else
            return ""
            #endif
        case .ollama:
            return "http://localhost:11434"
        case .deepSeek:
            return "https://api.deepseek.com"
        case .google:
            return "https://translate.googleapis.com"
        case .baidu:
            return "https://fanyi-api.baidu.com"
        }
    }

    public static func defaultModel(for provider: ModelProvider) -> String {
        switch provider {
        case .appleSystem:
            return ""
        case .openAICompatible:
            #if DEBUG
            return "qwen36-35b-a3b-mtp"
            #else
            return ""
            #endif
        case .ollama:
            return "qwen2.5"
        case .deepSeek:
            return "deepseek-v4-flash"
        case .google, .baidu:
            return ""
        }
    }

    public static func defaultConfiguration(for provider: ModelProvider) -> ProviderConfiguration {
        ProviderConfiguration(
            baseURL: defaultBaseURL(for: provider),
            apiKey: "",
            model: defaultModel(for: provider)
        )
    }

    public static func defaultProviderConfigurations() -> [String: ProviderConfiguration] {
        Dictionary(
            uniqueKeysWithValues: ModelProvider.allCases.map { provider in
                (provider.rawValue, defaultConfiguration(for: provider))
            }
        )
    }

    public func configuration(for provider: ModelProvider) -> ProviderConfiguration {
        if let configuration = providerConfigurations[provider.rawValue] {
            return configuration
        }
        if provider == self.provider {
            return ProviderConfiguration(baseURL: baseURL, apiKey: apiKey, model: model)
        }
        return AppSettings.defaultConfiguration(for: provider)
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case baseURL
        case apiKey
        case model
        case providerConfigurations
        case temperature
        case topP
        case maxTokens
        case debounceMilliseconds
        case autoTranslate
        case watchClipboard
        case autoCopy
        case autoPaste
        case alwaysOnTop
        case minimalMode
        case quickTranslateEnabled
        case quickTranslateShortcut
        case quickTranslateAutoCopy
        case targetLanguage
        case onboardingCompleted
        case appLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.defaults(environment: [:])
        provider = try container.decodeIfPresent(ModelProvider.self, forKey: .provider) ?? defaults.provider
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? defaults.baseURL
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? defaults.apiKey
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        var decodedProviderConfigurations = try container.decodeIfPresent(
            [String: ProviderConfiguration].self,
            forKey: .providerConfigurations
        ) ?? [:]
        if decodedProviderConfigurations[provider.rawValue] == nil {
            decodedProviderConfigurations[provider.rawValue] = ProviderConfiguration(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model
            )
        }
        providerConfigurations = decodedProviderConfigurations
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? defaults.temperature
        topP = try container.decodeIfPresent(Double.self, forKey: .topP) ?? defaults.topP
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? defaults.maxTokens
        debounceMilliseconds = try container.decodeIfPresent(Int.self, forKey: .debounceMilliseconds) ?? defaults.debounceMilliseconds
        autoTranslate = try container.decodeIfPresent(Bool.self, forKey: .autoTranslate) ?? defaults.autoTranslate
        watchClipboard = try container.decodeIfPresent(Bool.self, forKey: .watchClipboard) ?? defaults.watchClipboard
        autoCopy = try container.decodeIfPresent(Bool.self, forKey: .autoCopy) ?? defaults.autoCopy
        autoPaste = try container.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? defaults.autoPaste
        alwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? defaults.alwaysOnTop
        minimalMode = try container.decodeIfPresent(Bool.self, forKey: .minimalMode) ?? defaults.minimalMode
        quickTranslateEnabled = try container.decodeIfPresent(Bool.self, forKey: .quickTranslateEnabled) ?? defaults.quickTranslateEnabled
        targetLanguage = try container.decodeIfPresent(TargetLanguage.self, forKey: .targetLanguage) ?? defaults.targetLanguage
        quickTranslateShortcut = try container.decodeIfPresent(String.self, forKey: .quickTranslateShortcut) ?? defaults.quickTranslateShortcut
        quickTranslateAutoCopy = try container.decodeIfPresent(Bool.self, forKey: .quickTranslateAutoCopy) ?? defaults.quickTranslateAutoCopy
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? defaults.onboardingCompleted
        appLanguage = try container.decodeIfPresent(String.self, forKey: .appLanguage) ?? "system"
    }
}
