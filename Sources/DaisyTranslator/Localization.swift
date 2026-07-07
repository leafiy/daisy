import Foundation
import DaisyTranslatorCore
import LeafiyUICore

/// App strings resolved against this target's zh-Hans table.
@inline(__always)
func L(_ key: String) -> String {
    LeafiyLocalization.string(key, bundle: .module)
}

extension AppSettings {
    var selectedAppLanguage: AppLanguage {
        get { AppLanguage(rawValue: appLanguage) ?? .system }
        set { appLanguage = newValue.rawValue }
    }
}
