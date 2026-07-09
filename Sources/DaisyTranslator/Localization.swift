import Foundation
import DaisyTranslatorCore
import LeafiyUICore

/// App strings resolved against this target's zh-Hans table.
@inline(__always)
func L(_ key: String) -> String {
    LeafiyLocalization.string(key, bundle: daisyResourceBundle)
}

private let daisyResourceBundle: Bundle = {
    let bundleName = "DaisyTranslator_DaisyTranslator.bundle"
    let candidates = [
        Bundle.main.resourceURL?.appendingPathComponent(bundleName, isDirectory: true),
        Bundle.main.bundleURL.appendingPathComponent(bundleName, isDirectory: true)
    ].compactMap { $0 }

    for url in candidates {
        if let bundle = Bundle(url: url) {
            return bundle
        }
    }
    return Bundle.main
}()

extension AppSettings {
    var selectedAppLanguage: AppLanguage {
        get { AppLanguage(rawValue: appLanguage) ?? .system }
        set { appLanguage = newValue.rawValue }
    }
}
