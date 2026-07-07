import AppKit
import Foundation
import DaisyTranslatorCore

func normalizedServiceConfiguration(
    _ configuration: ProviderConfiguration,
    for provider: ModelProvider
) -> ProviderConfiguration {
    var normalized = ProviderConfiguration(
        baseURL: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
        apiKey: configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
        model: configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    if normalized.baseURL.isEmpty {
        normalized.baseURL = AppSettings.defaultBaseURL(for: provider)
    }
    switch provider {
    case .appleSystem:
        normalized = ProviderConfiguration(baseURL: "", apiKey: "", model: "")
    case .google, .baidu:
        normalized.model = ""
    case .deepSeek:
        normalized.baseURL = AppSettings.defaultBaseURL(for: .deepSeek)
        if normalized.model.isEmpty {
            normalized.model = AppSettings.defaultModel(for: .deepSeek)
        }
    case .ollama, .openAICompatible:
        if normalized.model.isEmpty {
            normalized.model = AppSettings.defaultModel(for: provider)
        }
    }
    return normalized
}

func providerTitle(_ provider: ModelProvider) -> String {
    switch provider {
    case .appleSystem:
        return "Apple 系统翻译"
    case .openAICompatible:
        return "OpenAI-compatible"
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

func providerApplicationLinkTitle(_ provider: ModelProvider) -> String? {
    switch provider {
    case .appleSystem:
        return nil
    case .openAICompatible:
        return "OpenAI API Key"
    case .ollama:
        return "Ollama 模型库"
    case .deepSeek:
        return "DeepSeek API Key"
    case .google:
        return "Google Cloud Translation"
    case .baidu:
        return "百度翻译开放平台"
    }
}

func providerApplicationLinkURL(_ provider: ModelProvider) -> URL? {
    let urlString: String
    switch provider {
    case .appleSystem:
        return nil
    case .openAICompatible:
        urlString = "https://platform.openai.com/api-keys"
    case .ollama:
        urlString = "https://ollama.com/library"
    case .deepSeek:
        urlString = "https://platform.deepseek.com/api_keys"
    case .google:
        urlString = "https://console.cloud.google.com/apis/library/translate.googleapis.com"
    case .baidu:
        urlString = "https://fanyi-api.baidu.com/"
    }
    return URL(string: urlString)
}

let externalServiceProviders: [ModelProvider] = [
    .deepSeek,
    .google,
    .baidu,
    .openAICompatible,
    .ollama
]

extension TargetLanguage {
    var menuTitle: String {
        switch self {
        case .auto:
            return "自动（中英互译）"
        case .english:
            return "英语"
        case .chinese:
            return "中文"
        }
    }
}

extension NSImage {
    static func daisyIcon() -> NSImage? {
        for subdirectory in [nil, "Icons"] as [String?] {
            guard let url = Bundle.module.url(forResource: "daisy", withExtension: "png", subdirectory: subdirectory),
                  let image = NSImage(contentsOf: url) else {
                continue
            }
            image.accessibilityDescription = "Daisy"
            return image
        }
        return nil
    }
}
