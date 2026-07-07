import AppKit
import SwiftUI
import DaisyTranslatorCore
import LeafiyUI
import LeafiyUICore

struct TranslatorView: View {
    @ObservedObject var model: DaisyModel
    let appleTranslationBridge: AnyView

    var body: some View {
        VStack(spacing: 0) {
            mainContent
            FooterBar {
                Text(model.statusText)
                    .lineLimit(1)
                Spacer()
                Text(model.settings.targetLanguage.menuTitle)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(
            minWidth: LeafiyDesign.Size.mainWindowMinWidth,
            minHeight: LeafiyDesign.Size.mainWindowMinHeight
        )
        .overlay(alignment: .topLeading) {
            appleTranslationBridge
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .leafiyToast(model.transientStatusMessage)
        .toolbar {
            ToolbarItemGroup {
                Button("读剪贴板") {
                    model.pullClipboardAndTranslate()
                }
                Button("翻译") {
                    model.translateCurrentText()
                }
                Button("复制") {
                    model.copyResult()
                }
                Button("粘贴到前台") {
                    model.pasteResult()
                }
                Button("清空") {
                    model.clear()
                }
                Button {
                    model.updateSettings { $0.alwaysOnTop.toggle() }
                } label: {
                    Label("置顶窗口", systemImage: model.settings.alwaysOnTop ? "pin.fill" : "pin")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { model.isOnboardingPresented },
            set: { presented in
                if !presented {
                    model.dismissOnboardingForNow()
                }
            }
        )) {
            OnboardingView(model: model)
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.m) {
            Text("原文")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            LeafiyCard {
                TextEditor(text: Binding(
                    get: { model.sourceText },
                    set: { newValue in
                        model.sourceText = newValue
                        model.sourceTextDidChange()
                    }
                ))
                .font(.body)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("原文输入框")
            }

            HStack {
                Text("译文")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("目标语言")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("目标语言", selection: settingsBinding(\.targetLanguage)) {
                    ForEach(TargetLanguage.allCases, id: \.rawValue) { language in
                        Text(language.menuTitle).tag(language)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: model.settings.targetLanguage) { _, _ in
                    model.scheduleTranslation()
                }
            }
            LeafiyCard {
                resultPane
                    .accessibilityLabel("译文输出框")
            }
        }
        .padding(LeafiyDesign.Spacing.l)
    }

    @ViewBuilder
    private var resultPane: some View {
        if model.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyStateView(systemImage: "text.bubble", title: "暂无译文", subtitle: "输入原文或读取剪贴板后开始翻译")
        } else {
            ScrollView {
                Text(model.translatedText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in
                model.updateSettings { $0[keyPath: keyPath] = value }
            }
        )
    }
}

struct DaisySettingsView: View {
    @ObservedObject var model: DaisyModel

    var body: some View {
        SettingsScaffold {
            SettingsPane("服务", systemImage: "globe", height: 480) {
                Section("服务") {
                    ProviderConfigurationForm(model: model)
                    providerHint
                }
            }
            SettingsPane("工作流", systemImage: "slider.horizontal.3", height: 560) {
                Section("快捷翻译") {
                    Toggle("快捷翻译", isOn: settingsBinding(\.quickTranslateEnabled))
                    Text("翻译选中文本并在弹出工具条中显示译文")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("快捷键") {
                        ShortcutField(spec: shortcutBinding)
                    }
                    Text("当前快捷键：\(shortcutDisplay)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("快捷翻译自动复制", isOn: settingsBinding(\.quickTranslateAutoCopy))
                    Text("弹出译文时自动写入剪贴板")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("自动化") {
                    Toggle("自动翻译", isOn: settingsBinding(\.autoTranslate))
                    Text("输入停止后自动翻译")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("监听剪贴板", isOn: settingsBinding(\.watchClipboard))
                    Text("剪贴板变化后自动读取并翻译")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("自动复制", isOn: settingsBinding(\.autoCopy))
                    Text("翻译完成后写入剪贴板")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("自动粘贴", isOn: settingsBinding(\.autoPaste))
                    Text("翻译完成后粘贴到前台应用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SettingsPane("隐私", systemImage: "hand.raised", height: 360) {
                Section("隐私") {
                    Text("""
Daisy 不采集账号、设备标识、联系人、浏览记录或使用分析数据。

当你使用 Apple 系统翻译时，翻译由 macOS 的系统翻译能力处理。改用 DeepSeek、Google、百度或 OpenAI-compatible 等外部服务时，原文会发送到你在“服务”里配置的翻译接口；译文由该服务返回。API Key 只保存在本机设置文件中，用于请求你选择的服务。

剪贴板监听默认关闭。开启后，Daisy 会在本机读取剪贴板文本，并按你的配置进行翻译。自动粘贴需要 macOS 辅助功能权限，Daisy 只在触发粘贴时发送 Cmd+V。
""")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            }
            AboutPane(
                title: "关于",
                tagline: "一个极简 macOS 原生 Swift 桌面翻译工具",
                copyright: "© 2026 Leafiy"
            )
        }
    }

    private var providerHint: some View {
        Text("默认使用 Apple 系统翻译，不需要 API Key。OpenAI-compatible 和 Ollama 可接入你自己的服务，DeepSeek / Google / 百度可使用对应官方 API。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var shortcutBinding: Binding<KeyboardShortcutSpec> {
        Binding(
            get: {
                KeyboardShortcutSpec(parsing: model.settings.quickTranslateShortcut)
                    ?? KeyboardShortcutSpec(parsing: AppSettings.defaults(environment: [:]).quickTranslateShortcut)!
            },
            set: { spec in
                let shortcut = spec.canonicalDescription
                guard HotKeyCenter.isShortcutSupported(shortcut) else {
                    model.showTransientStatus("快捷键无效")
                    return
                }
                model.updateSettings { $0.quickTranslateShortcut = shortcut }
            }
        )
    }

    private var shortcutDisplay: String {
        KeyboardShortcutSpec(parsing: model.settings.quickTranslateShortcut)?.display
            ?? model.settings.quickTranslateShortcut
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in
                model.updateSettings { $0[keyPath: keyPath] = value }
            }
        )
    }
}

struct ProviderConfigurationForm: View {
    @ObservedObject var model: DaisyModel

    var body: some View {
        Picker("类型", selection: Binding(
            get: { model.settings.provider },
            set: { model.setProvider($0) }
        )) {
            ForEach(ModelProvider.allCases, id: \.rawValue) { provider in
                Text(providerTitle(provider)).tag(provider)
            }
        }
        LabeledContent("Base URL") {
            TextField(
                providerFieldSemantics.baseURLPlaceholder,
                text: providerFieldBinding(\.baseURL)
            )
            .disabled(!providerFieldSemantics.baseURLEnabled)
        }
        LabeledContent("API Key") {
            SecureField(
                providerFieldSemantics.apiKeyPlaceholder,
                text: providerFieldBinding(\.apiKey)
            )
            .disabled(!providerFieldSemantics.apiKeyEnabled)
        }
        LabeledContent("Model") {
            TextField(
                providerFieldSemantics.modelPlaceholder,
                text: providerFieldBinding(\.model)
            )
            .disabled(!providerFieldSemantics.modelEnabled)
        }
        providerLinks
    }

    private var providerLinks: some View {
        VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.s) {
            ForEach(externalServiceProviders, id: \.rawValue) { provider in
                if let title = providerApplicationLinkTitle(provider),
                   let url = providerApplicationLinkURL(provider) {
                    Link(title, destination: url)
                }
            }
        }
        .font(.callout)
    }

    private var providerFieldSemantics: ProviderFieldSemantics {
        ProviderFieldSemantics(provider: model.settings.provider)
    }

    private func providerFieldBinding(_ keyPath: WritableKeyPath<ProviderConfiguration, String>) -> Binding<String> {
        Binding(
            get: {
                let configuration = ProviderConfiguration(
                    baseURL: model.settings.baseURL,
                    apiKey: model.settings.apiKey,
                    model: model.settings.model
                )
                return configuration[keyPath: keyPath]
            },
            set: { value in
                model.setProviderField(keyPath, to: value)
            }
        )
    }
}

private struct ProviderFieldSemantics {
    let provider: ModelProvider

    var baseURLEnabled: Bool {
        provider != .appleSystem && provider != .deepSeek
    }

    var apiKeyEnabled: Bool {
        provider != .appleSystem
    }

    var modelEnabled: Bool {
        provider != .appleSystem && provider != .google && provider != .baidu
    }

    var baseURLPlaceholder: String {
        switch provider {
        case .appleSystem:
            return "无需配置"
        case .deepSeek:
            return "自动使用官方地址"
        case .google:
            return "https://translate.googleapis.com"
        case .baidu:
            return "https://fanyi-api.baidu.com"
        case .ollama, .openAICompatible:
            return "https://api.example.com/v1"
        }
    }

    var apiKeyPlaceholder: String {
        switch provider {
        case .appleSystem:
            return "无需配置"
        case .google:
            return "可选：Google Cloud API Key"
        case .deepSeek, .baidu, .ollama, .openAICompatible:
            return "API Key"
        }
    }

    var modelPlaceholder: String {
        switch provider {
        case .appleSystem, .google, .baidu:
            return "无需配置"
        case .deepSeek:
            return AppSettings.defaultModel(for: .deepSeek)
        case .ollama, .openAICompatible:
            return "模型名称"
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: DaisyModel

    var body: some View {
        VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.l) {
            VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.s) {
                Text("欢迎使用 Daisy")
                    .font(.title2.weight(.semibold))
                Text("默认使用 Apple 系统翻译。你也可以改用自己的 DeepSeek、Google、百度或 OpenAI-compatible 服务。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Form {
                Section("首次配置") {
                    ProviderConfigurationForm(model: model)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("稍后配置") {
                    model.dismissOnboardingForNow()
                }
                Button("开始使用") {
                    model.completeOnboarding()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(LeafiyDesign.Spacing.xl)
        .frame(width: LeafiyDesign.Size.settingsPaneWidth)
    }
}

struct DaisyMenuBarMenu: View {
    @ObservedObject var model: DaisyModel
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(appDelegate.isMainWindowVisible ? "隐藏窗口" : "显示窗口") {
            appDelegate.toggleMainWindow(openWindow: openWindow)
        }
        Divider()
        Button("读取剪贴板翻译并复制") {
            appDelegate.translateClipboardAndCopyWithoutWindow()
        }
        Button("粘贴当前译文") {
            model.pasteResult()
        }
        Divider()
        SettingsLink {
            Text("设置…")
        }
        Picker("目标语言", selection: Binding(
            get: { model.settings.targetLanguage },
            set: { language in model.updateSettings { $0.targetLanguage = language } }
        )) {
            ForEach(TargetLanguage.allCases, id: \.rawValue) { language in
                Text(language.menuTitle).tag(language)
            }
        }
        Divider()
        Toggle("快捷翻译", isOn: settingsBinding(\.quickTranslateEnabled))
        Toggle("自动翻译", isOn: settingsBinding(\.autoTranslate))
        Toggle("监听剪贴板", isOn: settingsBinding(\.watchClipboard))
        Toggle("自动复制", isOn: settingsBinding(\.autoCopy))
        Toggle("自动粘贴", isOn: settingsBinding(\.autoPaste))
        Text("快捷键：\(shortcutDisplay)")
        Divider()
        Button("退出 Daisy") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var shortcutDisplay: String {
        KeyboardShortcutSpec(parsing: model.settings.quickTranslateShortcut)?.display
            ?? model.settings.quickTranslateShortcut
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}

struct DaisyMenuBarLabel: View {
    @ObservedObject var model: DaisyModel

    /// Sized once: the status bar draws the NSImage's own point size, and
    /// label views re-render on every model change.
    private static let icon = NSImage.daisyIcon()?.leafiyMenuBarSized()

    var body: some View {
        HStack(spacing: LeafiyDesign.Spacing.xs) {
            if let icon = Self.icon {
                Image(nsImage: icon)
            } else {
                Text("daisy")
            }
            if let message = model.menuBarStatusText, !message.isEmpty {
                Text(message)
            }
        }
        .accessibilityLabel("Daisy")
    }
}
