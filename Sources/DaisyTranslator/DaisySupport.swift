import AppKit
import Foundation
import DaisyTranslatorCore
import LeafiyUICore
import LeafiyUI

func providerTitle(_ provider: ModelProvider) -> String {
    switch provider {
    case .appleSystem:
        return L("Apple System Translation")
    case .openAICompatible:
        return "OpenAI-compatible"
    case .ollama:
        return "Ollama"
    case .deepSeek:
        return "DeepSeek"
    case .google:
        return L("Google Translate")
    case .baidu:
        return L("Baidu Translate")
    }
}

func providerApplicationLinkTitle(_ provider: ModelProvider) -> String? {
    switch provider {
    case .appleSystem:
        return nil
    case .openAICompatible:
        return L("OpenAI API Key")
    case .ollama:
        return L("Ollama Model Library")
    case .deepSeek:
        return L("DeepSeek API Key")
    case .google:
        return L("Google Cloud Translation")
    case .baidu:
        return L("Baidu Translate Open Platform")
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
            return L("Auto (Chinese ↔ English)")
        case .english:
            return L("English")
        case .chinese:
            return L("Chinese")
        }
    }
}

extension NSImage {
    static func daisyAppIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            image.accessibilityDescription = LeafiyAppIdentity.current.name
            return image
        }

        if let image = NSApplication.shared.applicationIconImage,
           !image.representations.isEmpty {
            image.accessibilityDescription = LeafiyAppIdentity.current.name
            return image
        }
        return nil
    }
}
