import Foundation
import DaisyTranslatorCore
import LeafiyUICore

/// App strings resolved against this target's zh-Hans table.
private let appBundle = LeafiyLocalization.moduleBundle(package: "DaisyTranslator", target: "DaisyTranslator")

@inline(__always)
func L(_ key: String) -> String { LeafiyLocalization.string(key, bundle: appBundle) }

extension AppSettings {
    var selectedAppLanguage: AppLanguage {
        get { AppLanguage(rawValue: appLanguage) ?? .system }
        set { appLanguage = newValue.rawValue }
    }
}
