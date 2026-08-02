import Foundation

public enum ModelProvider: String, Codable, CaseIterable, Equatable, Sendable {
    case appleSystem = "apple-system"
    case openAICompatible = "openai-compatible"
    case ollama
    case deepSeek = "deepseek"
    case google
    case baidu
}

/// Where the Ollama server lives. Local is a fixed loopback endpoint, so the
/// address field only exists for `remote`.
public enum OllamaConnection: String, Codable, CaseIterable, Equatable, Sendable {
    case local
    case remote
}

public enum TargetLanguage: String, Codable, CaseIterable, Equatable, Sendable {
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
    /// Only meaningful for `.ollama`: local pins the endpoint to loopback,
    /// remote uses the configured `baseURL`.
    public var ollamaConnection: OllamaConnection
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
    /// Window transparency, applied to the whole window in both standard and
    /// minimal mode. Off by default; both levels are clamped to
    /// `windowOpacityRange`.
    public var windowOpacityEnabled: Bool
    public var focusedWindowOpacity: Double
    public var unfocusedWindowOpacity: Double
    public var quickTranslateEnabled: Bool
    public var quickTranslateShortcut: String
    public var quickTranslateAutoCopy: Bool
    public var targetLanguage: TargetLanguage
    public var onboardingCompleted: Bool
    public var appLanguage: String
    public var launchAtLogin: Bool

    public init(
        baseURL: String,
        apiKey: String,
        model: String,
        providerConfigurations: [String: ProviderConfiguration] = [:],
        ollamaConnection: OllamaConnection = .local,
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
        windowOpacityEnabled: Bool = false,
        focusedWindowOpacity: Double = AppSettings.defaultWindowOpacity,
        unfocusedWindowOpacity: Double = AppSettings.defaultWindowOpacity,
        quickTranslateEnabled: Bool = false,
        quickTranslateShortcut: String = "Command+Shift+V",
        quickTranslateAutoCopy: Bool = true,
        provider: ModelProvider = .appleSystem,
        targetLanguage: TargetLanguage = .auto,
        onboardingCompleted: Bool = false,
        appLanguage: String = "system",
        launchAtLogin: Bool = false
    ) {
        self.provider = provider
        self.targetLanguage = targetLanguage
        self.onboardingCompleted = onboardingCompleted
        self.appLanguage = appLanguage
        self.launchAtLogin = launchAtLogin
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.providerConfigurations = providerConfigurations
        self.ollamaConnection = ollamaConnection
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
        self.windowOpacityEnabled = windowOpacityEnabled
        self.focusedWindowOpacity = AppSettings.clampedOpacity(focusedWindowOpacity)
        self.unfocusedWindowOpacity = AppSettings.clampedOpacity(unfocusedWindowOpacity)
    }

    public static func defaults(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppSettings {
        let provider = ModelProvider(rawValue: environment["TT_PROVIDER"] ?? "") ?? .appleSystem
        var providerConfigurations = defaultProviderConfigurations()
        providerConfigurations[provider.rawValue] = ProviderConfiguration(
            baseURL: environment["TT_BASE_URL"] ?? defaultBaseURL(for: provider),
            apiKey: environment["TT_API_KEY"] ?? "",
            model: environment["TT_MODEL"] ?? defaultModel(for: provider)
        )
        let ollamaBaseURL = provider == .ollama
            ? (environment["TT_BASE_URL"] ?? defaultBaseURL(for: .ollama))
            : defaultBaseURL(for: .ollama)
        return AppSettings(
            baseURL: environment["TT_BASE_URL"] ?? defaultBaseURL(for: provider),
            apiKey: environment["TT_API_KEY"] ?? "",
            model: environment["TT_MODEL"] ?? defaultModel(for: provider),
            providerConfigurations: providerConfigurations,
            ollamaConnection: inferredOllamaConnection(baseURL: ollamaBaseURL),
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
            windowOpacityEnabled: false,
            focusedWindowOpacity: AppSettings.defaultWindowOpacity,
            unfocusedWindowOpacity: AppSettings.defaultWindowOpacity,
            quickTranslateEnabled: false,
            quickTranslateShortcut: "Command+Shift+V",
            quickTranslateAutoCopy: true,
            provider: provider,
            targetLanguage: TargetLanguage(rawValue: environment["TT_TARGET_LANGUAGE"] ?? "") ?? .auto,
            appLanguage: "system",
            launchAtLogin: false
        )
    }

    /// Rules that fire on a settings transition rather than on a state.
    /// Enabling minimal mode switches auto-copy on: the compact window hides
    /// the result affordances, so completed translations must land on the
    /// clipboard. The user can still turn auto-copy back off afterwards.
    public func applyingTransitions(from previous: AppSettings) -> AppSettings {
        var next = self
        if minimalMode && !previous.minimalMode {
            next.autoCopy = true
        }
        return next
    }

    /// Fully opaque is the top of the range; below `minWindowOpacity` the
    /// window stops being usable (and unclickable chrome is hard to recover
    /// from), so the sliders bottom out there.
    public static let minWindowOpacity: Double = 0.1
    public static let defaultWindowOpacity: Double = 0.9
    public static let windowOpacityRange: ClosedRange<Double> = minWindowOpacity...1

    public static func clampedOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultWindowOpacity }
        return min(max(value, minWindowOpacity), 1)
    }

    /// The alpha the window should carry right now. Disabled means fully
    /// opaque regardless of the stored levels.
    public func windowOpacity(focused: Bool) -> Double {
        guard windowOpacityEnabled else { return 1 }
        return focused ? focusedWindowOpacity : unfocusedWindowOpacity
    }

    /// A translucent window that shows a razor-sharp desktop through it is
    /// unreadable, so transparency drags a frosted backdrop along with it.
    /// The strength is derived, never configured: none at fully opaque,
    /// rising to `maxWindowBlur` at `minWindowOpacity`. It stops short of 1
    /// so the window keeps some of its own colour at every level.
    public static let maxWindowBlur: Double = 0.8

    public static func windowBlur(forOpacity opacity: Double) -> Double {
        let transparency = (1 - clampedOpacity(opacity)) / (1 - minWindowOpacity)
        return maxWindowBlur * transparency
    }

    /// Blur strength that pairs with `windowOpacity(focused:)`; zero while
    /// transparency is off, since the window is then fully opaque.
    public func windowBlurIntensity(focused: Bool) -> Double {
        AppSettings.windowBlur(forOpacity: windowOpacity(focused: focused))
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
            // `baseURL` holds the *remote* Ollama address only; the local
            // connection is pinned to `localOllamaBaseURL`.
            return ""
        case .deepSeek:
            return "https://api.deepseek.com"
        case .google:
            return "https://translate.googleapis.com"
        case .baidu:
            return "https://fanyi-api.baidu.com"
        }
    }

    /// The loopback endpoint used whenever `ollamaConnection` is `.local`.
    public static let localOllamaBaseURL = "http://localhost:11434"

    /// Classifies a stored Ollama address, used to migrate settings written
    /// before the connection mode existed.
    public static func inferredOllamaConnection(baseURL: String) -> OllamaConnection {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let host = URLComponents(string: trimmed)?.host?.lowercased() else { return .local }
        let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"]
        return loopbackHosts.contains(host) ? .local : .remote
    }

    /// The address requests actually go to. Local Ollama ignores `baseURL` so
    /// switching back to remote keeps the address the user typed.
    public var effectiveBaseURL: String {
        guard provider == .ollama, ollamaConnection == .local else { return baseURL }
        return AppSettings.localOllamaBaseURL
    }

    /// The bearer token requests actually carry. A loopback Ollama has no auth
    /// surface, so a token left over from a remote host is never sent to it.
    public var effectiveAPIKey: String {
        guard provider == .ollama, ollamaConnection == .local else { return apiKey }
        return ""
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
            // Discovered from `/api/tags`, so there is nothing sensible to
            // guess before the server has been reached.
            return ""
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
        case ollamaConnection
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
        case windowOpacityEnabled
        case focusedWindowOpacity
        case unfocusedWindowOpacity
        case quickTranslateEnabled
        case quickTranslateShortcut
        case quickTranslateAutoCopy
        case targetLanguage
        case onboardingCompleted
        case appLanguage
        case launchAtLogin
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
        // Settings written before the connection mode existed stored the local
        // endpoint in `baseURL`; classify that address instead of forcing
        // remote users back onto loopback.
        if let decodedOllamaConnection = try container.decodeIfPresent(
            OllamaConnection.self,
            forKey: .ollamaConnection
        ) {
            ollamaConnection = decodedOllamaConnection
        } else {
            ollamaConnection = AppSettings.inferredOllamaConnection(
                baseURL: decodedProviderConfigurations[ModelProvider.ollama.rawValue]?.baseURL ?? ""
            )
        }
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
        windowOpacityEnabled = try container.decodeIfPresent(Bool.self, forKey: .windowOpacityEnabled) ?? defaults.windowOpacityEnabled
        focusedWindowOpacity = AppSettings.clampedOpacity(
            try container.decodeIfPresent(Double.self, forKey: .focusedWindowOpacity) ?? defaults.focusedWindowOpacity
        )
        unfocusedWindowOpacity = AppSettings.clampedOpacity(
            try container.decodeIfPresent(Double.self, forKey: .unfocusedWindowOpacity) ?? defaults.unfocusedWindowOpacity
        )
        quickTranslateEnabled = try container.decodeIfPresent(Bool.self, forKey: .quickTranslateEnabled) ?? defaults.quickTranslateEnabled
        targetLanguage = try container.decodeIfPresent(TargetLanguage.self, forKey: .targetLanguage) ?? defaults.targetLanguage
        quickTranslateShortcut = try container.decodeIfPresent(String.self, forKey: .quickTranslateShortcut) ?? defaults.quickTranslateShortcut
        quickTranslateAutoCopy = try container.decodeIfPresent(Bool.self, forKey: .quickTranslateAutoCopy) ?? defaults.quickTranslateAutoCopy
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? defaults.onboardingCompleted
        appLanguage = try container.decodeIfPresent(String.self, forKey: .appLanguage) ?? "system"
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
    }
}
