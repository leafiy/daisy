import AppKit
import ApplicationServices
import Foundation
import SwiftUI
import DaisyTranslatorCore
#if canImport(Translation)
import Translation
#endif

private func normalizedServiceConfiguration(
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

private func providerApplicationLinkTitle(_ provider: ModelProvider) -> String? {
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

private func providerApplicationLinkURL(_ provider: ModelProvider) -> URL? {
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

private let externalServiceProviders: [ModelProvider] = [
    .deepSeek,
    .google,
    .baidu,
    .openAICompatible,
    .ollama
]

@main
enum DaisyTranslatorApp {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            SelfTest.run()
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let translationService = TranslationService()
    private let appleTranslationService = AppleSystemTranslationService()
    private let pasteboardService = PasteboardService()
    private let hotKeyCenter = HotKeyCenter()
    private var statusItem: NSStatusItem?

    private var window: NSWindow?
    private var viewController: TranslatorViewController?
    private var settings = AppSettings.defaults()
    private var clipboardTimer: Timer?
    private var lastClipboardText = ""
    private var clipboardShortcutTask: Task<Void, Never>?
    private var toastWindow: NSWindow?
    private var settingsWindowController: SettingsWindowController?
    private var shouldShowOnboarding = false
    private var activeTranslationCount = 0
    private var isClipboardWatcherPaused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        shouldShowOnboarding = !settingsStore.hasSavedSettings
        settings = settingsStore.load()
        configureApplicationIcon()
        createMenu()
        createWindow()
        createStatusItem()
        applyWindowBehavior()
        updateClipboardWatcher()
        registerHotKeys()
        NSApp.activate(ignoringOtherApps: true)
        showOnboardingIfNeeded()
        prepareAppleSystemTranslationIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardTimer?.invalidate()
        clipboardShortcutTask?.cancel()
        toastWindow?.orderOut(nil)
        hotKeyCenter.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func createWindow() {
        let controller = TranslatorViewController(
            settings: settings,
            pasteboardService: pasteboardService,
            translateText: { [weak self] text, settings in
                guard let self else { return "" }
                return try await self.translate(text, settings: settings)
            },
            onSettingsChanged: { [weak self] nextSettings in
                self?.saveSettings(nextSettings)
            },
            onTranslationActivityChanged: { [weak self] isActive in
                self?.setTranslationInProgress(isActive)
            },
            onUserNotification: { [weak self] message in
                self?.showToast(message)
            },
            ensurePastePermission: { [weak self] in
                self?.ensureAccessibilityPermissionForPaste() ?? false
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Daisy"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 500, height: 460)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.center()
        window.makeKeyAndOrderFront(nil)
        appleTranslationService.attach(to: window)

        self.viewController = controller
        self.window = window
    }

    private func saveSettings(_ nextSettings: AppSettings) {
        let previousSettings = settings
        let normalizedSettings = normalized(nextSettings)
        settings = normalizedSettings
        do {
            try settingsStore.save(normalizedSettings)
            applyWindowBehavior()
            updateClipboardWatcher()
            registerHotKeys()
            prepareAppleSystemTranslationIfNeeded()
            viewController?.render(settings: normalizedSettings)
            rebuildStatusMenu()
            if shouldRetryTranslation(afterChangingFrom: previousSettings, to: normalizedSettings) {
                viewController?.retryCurrentText()
            }
        } catch {
            viewController?.setStatus("保存失败，请检查设置文件权限")
        }
    }

    private func normalized(_ settings: AppSettings) -> AppSettings {
        var normalized = settings
        var providerConfigurations = AppSettings.defaultProviderConfigurations()
        providerConfigurations.merge(normalized.providerConfigurations) { _, savedConfiguration in
            savedConfiguration
        }
        let activeConfiguration = normalizedServiceConfiguration(
            ProviderConfiguration(
                baseURL: normalized.baseURL,
                apiKey: normalized.apiKey,
                model: normalized.model
            ),
            for: normalized.provider
        )
        providerConfigurations[normalized.provider.rawValue] = activeConfiguration
        normalized.providerConfigurations = providerConfigurations
        normalized.baseURL = activeConfiguration.baseURL
        normalized.apiKey = activeConfiguration.apiKey
        normalized.model = activeConfiguration.model
        return normalized
    }

    private func shouldRetryTranslation(afterChangingFrom oldSettings: AppSettings, to newSettings: AppSettings) -> Bool {
        oldSettings.provider != newSettings.provider ||
            oldSettings.baseURL != newSettings.baseURL ||
            oldSettings.apiKey != newSettings.apiKey ||
            oldSettings.model != newSettings.model ||
            oldSettings.targetLanguage != newSettings.targetLanguage
    }

    private func applyWindowBehavior() {
        guard let window else { return }
        if settings.alwaysOnTop {
            window.level = .floating
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        } else {
            window.level = .normal
            window.collectionBehavior.remove([.canJoinAllSpaces, .fullScreenAuxiliary])
        }
    }

    private func updateClipboardWatcher() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        guard settings.watchClipboard else { return }

        lastClipboardText = pasteboardService.readText()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.isClipboardWatcherPaused else { return }
                let current = self.pasteboardService.readText()
                guard !current.isEmpty,
                      current != self.lastClipboardText,
                      current != self.pasteboardService.lastProgrammaticText else {
                    return
                }
                self.lastClipboardText = current
                self.viewController?.acceptClipboardText(current)
            }
        }
    }

    private func setTranslationInProgress(_ isActive: Bool) {
        if isActive {
            activeTranslationCount += 1
            isClipboardWatcherPaused = true
            return
        }

        activeTranslationCount = max(0, activeTranslationCount - 1)
        if activeTranslationCount == 0 {
            isClipboardWatcherPaused = false
            lastClipboardText = pasteboardService.readText()
        }
    }

    private func registerHotKeys() {
        hotKeyCenter.onHotKey = { [weak self] hotKey in
            guard let self else { return }
            switch hotKey {
            case .translateClipboard:
                self.viewController?.pullClipboardAndTranslate()
            case .quickTranslateClipboard:
                self.translateClipboardAndCopyWithoutWindow()
            case .toggleAlwaysOnTop:
                var next = self.settings
                next.alwaysOnTop.toggle()
                self.saveSettings(next)
            }
        }
        hotKeyCenter.register(
            quickTranslateEnabled: settings.quickTranslateEnabled,
            quickTranslateShortcut: settings.quickTranslateShortcut
        )
    }

    private func createMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Daisy", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Daisy", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"))
        appMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Daisy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))


        let mainMenu = NSMenu(title: "Main")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = loadIcon(named: "daisy", accessibilityDescription: "Daisy") {
                image.isTemplate = false
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else {
                button.title = "daisy"
            }
        }
        statusItem = item
        rebuildStatusMenu()
    }

    private func configureApplicationIcon() {
        if let image = loadIcon(named: "daisy", accessibilityDescription: "Daisy") {
            NSApp.applicationIconImage = image
        }
    }

    private func loadIcon(named name: String, accessibilityDescription: String) -> NSImage? {
        for subdirectory in [nil, "Icons"] as [String?] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: subdirectory),
                  let image = NSImage(contentsOf: url) else {
                continue
            }
            image.accessibilityDescription = accessibilityDescription
            return image
        }
        return nil
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem(title: window?.isVisible == true ? "隐藏窗口" : "显示窗口", action: #selector(toggleWindowFromStatusMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "读取剪贴板翻译并复制", action: #selector(translateClipboardFromStatusMenu)))
        menu.addItem(menuItem(title: "粘贴当前译文", action: #selector(pasteResultFromStatusMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "设置…", action: #selector(openSettingsWindow)))
        let targetLanguageMenu = NSMenu()
        for language in TargetLanguage.allCases {
            let item = menuItem(title: language.menuTitle, action: #selector(selectTargetLanguageFromStatusMenu(_:)))
            item.representedObject = language.rawValue
            item.state = settings.targetLanguage == language ? .on : .off
            targetLanguageMenu.addItem(item)
        }
        let targetLanguageItem = NSMenuItem(title: "目标语言", action: nil, keyEquivalent: "")
        targetLanguageItem.submenu = targetLanguageMenu
        menu.addItem(targetLanguageItem)
        menu.addItem(.separator())
        menu.addItem(settingItem(title: "快捷翻译", enabled: settings.quickTranslateEnabled, action: #selector(toggleQuickTranslateFromStatusMenu)))
        menu.addItem(menuItem(title: "快捷翻译快捷键：\(settings.quickTranslateShortcut)", action: #selector(openQuickTranslateShortcutFromStatusMenu)))
        menu.addItem(settingItem(title: "自动翻译", enabled: settings.autoTranslate, action: #selector(toggleAutoTranslateFromStatusMenu)))
        menu.addItem(settingItem(title: "监听剪贴板", enabled: settings.watchClipboard, action: #selector(toggleWatchClipboardFromStatusMenu)))
        menu.addItem(settingItem(title: "自动复制", enabled: settings.autoCopy, action: #selector(toggleAutoCopyFromStatusMenu)))
        menu.addItem(settingItem(title: "自动粘贴", enabled: settings.autoPaste, action: #selector(toggleAutoPasteFromStatusMenu)))
        menu.addItem(NSMenuItem(title: "退出 Daisy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func selectTargetLanguageFromStatusMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = TargetLanguage(rawValue: raw),
              language != settings.targetLanguage else {
            return
        }
        var next = settings
        next.targetLanguage = language
        saveSettings(next)
    }

    private func settingItem(title: String, enabled: Bool, action: Selector) -> NSMenuItem {
        let item = menuItem(title: title, action: action)
        item.state = enabled ? .on : .off
        return item
    }

    @objc private func toggleWindowFromStatusMenu() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        rebuildStatusMenu()
    }

    @objc private func translateClipboardFromStatusMenu() {
        translateClipboardAndCopyWithoutWindow()
    }

    @objc private func pasteResultFromStatusMenu() {
        viewController?.pasteResult()
    }

    private func translateClipboardAndCopyWithoutWindow() {
        let text = pasteboardService.readText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showToast("剪贴板为空")
            return
        }

        clipboardShortcutTask?.cancel()
        showToast("翻译中…")
        let settingsSnapshot = settings
        clipboardShortcutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.setTranslationInProgress(true)
            defer { self.setTranslationInProgress(false) }
            do {
                let translated = try await self.translate(text, settings: settingsSnapshot)
                guard !Task.isCancelled else { return }
                if self.pasteboardService.writeText(translated) {
                    self.showToast("已翻译并复制")
                } else {
                    self.showToast("翻译完成，但复制失败，请重试")
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = String(
                    TranslationService.userFacingErrorMessage(error, provider: settingsSnapshot.provider).prefix(40)
                )
                self.showToast("翻译失败：\(message)")
            }
        }
    }

    @objc private func openSettingsWindow() {
        let controller = SettingsWindowController(settings: settings) { [weak self] nextSettings in
            self?.saveSettings(nextSettings)
        }
        settingsWindowController = controller
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openOnboarding() {
        let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for provider in ModelProvider.allCases {
            providerPopup.addItem(withTitle: providerTitle(provider))
        }
        providerPopup.selectItem(at: ModelProvider.allCases.firstIndex(of: settings.provider) ?? 0)

        var providerConfigurations = AppSettings.defaultProviderConfigurations()
        providerConfigurations.merge(settings.providerConfigurations) { _, savedConfiguration in
            savedConfiguration
        }
        providerConfigurations[settings.provider.rawValue] = normalizedServiceConfiguration(
            settings.configuration(for: settings.provider),
            for: settings.provider
        )
        let initialConfiguration = providerConfigurations[settings.provider.rawValue]
            ?? AppSettings.defaultConfiguration(for: settings.provider)

        let baseURLField = NSTextField(string: initialConfiguration.baseURL)
        baseURLField.placeholderString = "https://api.example.com/v1"
        baseURLField.setContentCompressionResistancePriority(.required, for: .horizontal)
        let apiKeyField = NSSecureTextField(string: initialConfiguration.apiKey)
        apiKeyField.placeholderString = "API Key"
        apiKeyField.setContentCompressionResistancePriority(.required, for: .horizontal)
        let modelField = NSTextField(string: initialConfiguration.model)
        modelField.placeholderString = "模型名称"
        modelField.setContentCompressionResistancePriority(.required, for: .horizontal)
        updateServiceFields(
            provider: settings.provider,
            baseURLField: baseURLField,
            apiKeyField: apiKeyField,
            modelField: modelField
        )

        func captureProviderConfiguration(_ provider: ModelProvider) {
            providerConfigurations[provider.rawValue] = normalizedServiceConfiguration(
                ProviderConfiguration(
                    baseURL: baseURLField.stringValue,
                    apiKey: apiKeyField.stringValue,
                    model: modelField.stringValue
                ),
                for: provider
            )
        }

        func showProviderConfiguration(_ provider: ModelProvider) {
            let configuration = providerConfigurations[provider.rawValue]
                ?? AppSettings.defaultConfiguration(for: provider)
            baseURLField.stringValue = configuration.baseURL
            apiKeyField.stringValue = configuration.apiKey
            modelField.stringValue = configuration.model
            updateServiceFields(
                provider: provider,
                baseURLField: baseURLField,
                apiKeyField: apiKeyField,
                modelField: modelField
            )
        }

        var lastSelectedProvider = settings.provider
        let providerTarget = ModalActionTarget {
            let provider = ModelProvider.allCases[providerPopup.indexOfSelectedItem]
            guard provider != lastSelectedProvider else { return }
            let previousProvider = lastSelectedProvider
            captureProviderConfiguration(previousProvider)
            lastSelectedProvider = provider
            showProviderConfiguration(provider)
        }
        providerPopup.target = providerTarget
        providerPopup.action = #selector(ModalActionTarget.runAction)

        let titleLabel = NSTextField(labelWithString: "欢迎使用 Daisy")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitleLabel = wrappingLabel("默认使用 Apple 系统翻译。你也可以改用自己的 DeepSeek、Google、百度或 OpenAI-compatible 服务。")

        let grid = NSGridView(views: [
            [formLabel("类型"), providerPopup],
            [formLabel("Base URL"), baseURLField],
            [formLabel("API Key"), apiKeyField],
            [formLabel("Model"), modelField]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 640

        let linkTargets = externalServiceProviders.map { provider in
            ModalActionTarget { self.openProviderLink(provider) }
        }
        let linkButtons = zip(externalServiceProviders, linkTargets).compactMap { provider, target -> NSButton? in
            guard let title = providerApplicationLinkTitle(provider) else { return nil }
            return NSButton(title: title, target: target, action: #selector(ModalActionTarget.runAction))
        }
        let firstLinkRow = NSStackView(views: Array(linkButtons.prefix(3)))
        firstLinkRow.orientation = .horizontal
        firstLinkRow.spacing = 8
        let secondLinkRow = NSStackView(views: Array(linkButtons.dropFirst(3)))
        secondLinkRow.orientation = .horizontal
        secondLinkRow.spacing = 8
        let links = NSStackView(views: [firstLinkRow, secondLinkRow])
        links.orientation = .vertical
        links.spacing = 8
        links.translatesAutoresizingMaskIntoConstraints = false

        let saveTarget = ModalActionTarget { NSApp.stopModal(withCode: .OK) }
        let laterTarget = ModalActionTarget { NSApp.stopModal(withCode: .cancel) }
        let saveButton = NSButton(title: "开始使用", target: saveTarget, action: #selector(ModalActionTarget.runAction))
        let laterButton = NSButton(title: "稍后配置", target: laterTarget, action: #selector(ModalActionTarget.runAction))
        saveButton.keyEquivalent = "\r"
        laterButton.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [laterButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 390),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 760, height: 390)
        panel.title = "首次配置"
        panel.contentView = contentView
        panel.level = .floating

        for view in [titleLabel, subtitleLabel, grid, links, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            grid.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),

            links.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            links.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),

            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22)
        ])

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        guard response == .OK else {
            _ = providerTarget
            _ = saveTarget
            _ = laterTarget
            _ = linkTargets
            return
        }

        let provider = ModelProvider.allCases[providerPopup.indexOfSelectedItem]
        captureProviderConfiguration(provider)
        let configuration = providerConfigurations[provider.rawValue]
            ?? AppSettings.defaultConfiguration(for: provider)
        var next = settings
        next.provider = provider
        next.baseURL = configuration.baseURL
        next.apiKey = configuration.apiKey
        next.model = configuration.model
        next.providerConfigurations = providerConfigurations
        next.onboardingCompleted = true
        saveSettings(next)
        _ = providerTarget
        _ = saveTarget
        _ = laterTarget
        _ = linkTargets
    }

    private func showOnboardingIfNeeded() {
        guard shouldShowOnboarding || !settings.onboardingCompleted else { return }
        openOnboarding()
    }

    private func translate(_ text: String, settings: AppSettings) async throws -> String {
        if settings.provider == .appleSystem {
            return try await appleTranslationService.translate(text, targetLanguage: settings.targetLanguage)
        }
        return try await translationService.translate(text, settings: settings)
    }

    private func prepareAppleSystemTranslationIfNeeded() {
        guard settings.provider == .appleSystem else { return }
        Task { @MainActor in
            try? await appleTranslationService.prepareEnglishChinese()
        }
    }

    private func openProviderLink(_ provider: ModelProvider) {
        if let url = providerApplicationLinkURL(provider) {
            NSWorkspace.shared.open(url)
        }
    }

    private func ensureAccessibilityPermissionForPaste() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "允许 Daisy 自动粘贴"
        alert.informativeText = "自动粘贴需要 macOS 辅助功能权限。Daisy 只会在你启用自动粘贴或点击粘贴到前台时发送 Cmd+V。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        return AXIsProcessTrusted()
    }

    private func showToast(_ message: String) {
        toastWindow?.orderOut(nil)

        let width = min(max(CGFloat(message.count * 9 + 44), 160), 420)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true

        let background = NSView()
        background.translatesAutoresizingMaskIntoConstraints = false
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor

        let label = NSTextField(labelWithString: message)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail

        panel.contentView = background
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor)
        ])

        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - width - 24, y: frame.maxY - 64))
        }

        panel.orderFrontRegardless()
        toastWindow = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self, weak panel] in
            guard let panel else { return }
            panel.orderOut(nil)
            if self?.toastWindow === panel {
                self?.toastWindow = nil
            }
        }
    }

    @objc private func openQuickTranslateShortcutFromStatusMenu() {
        let shortcutField = NSTextField(string: settings.quickTranslateShortcut)
        shortcutField.placeholderString = "Command+Shift+V"
        shortcutField.translatesAutoresizingMaskIntoConstraints = false

        let label = formLabel("快捷键")
        label.translatesAutoresizingMaskIntoConstraints = false

        let saveTarget = ModalActionTarget { NSApp.stopModal(withCode: .OK) }
        let cancelTarget = ModalActionTarget { NSApp.stopModal(withCode: .cancel) }
        let saveButton = NSButton(title: "保存", target: saveTarget, action: #selector(ModalActionTarget.runAction))
        let cancelButton = NSButton(title: "取消", target: cancelTarget, action: #selector(ModalActionTarget.runAction))
        saveButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 140),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "快捷翻译快捷键"
        panel.contentView = contentView
        panel.level = .floating

        contentView.addSubview(label)
        contentView.addSubview(shortcutField)
        contentView.addSubview(buttons)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            label.centerYAnchor.constraint(equalTo: shortcutField.centerYAnchor),
            shortcutField.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
            shortcutField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            shortcutField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        guard response == .OK else { return }

        let shortcut = shortcutField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HotKeyCenter.isShortcutSupported(shortcut) else {
            showToast("快捷键无效")
            return
        }

        var next = settings
        next.quickTranslateShortcut = shortcut
        saveSettings(next)
        _ = saveTarget
        _ = cancelTarget
    }

    private func formLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13)
        return label
    }

    private func providerTitle(_ provider: ModelProvider) -> String {
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

    private func updateServiceFields(
        provider: ModelProvider,
        baseURLField: NSTextField,
        apiKeyField: NSTextField,
        modelField: NSTextField
    ) {
        let usesExternalService = provider != .appleSystem
        baseURLField.isEnabled = usesExternalService && provider != .deepSeek
        apiKeyField.isEnabled = usesExternalService
        modelField.isEnabled = usesExternalService && provider != .google && provider != .baidu
        switch provider {
        case .appleSystem:
            baseURLField.stringValue = ""
            apiKeyField.stringValue = ""
            modelField.stringValue = ""
            baseURLField.placeholderString = "无需配置"
            apiKeyField.placeholderString = "无需配置"
            modelField.placeholderString = "无需配置"
        case .google:
            modelField.stringValue = ""
            baseURLField.placeholderString = "https://translate.googleapis.com"
            apiKeyField.placeholderString = "可选：Google Cloud API Key"
            modelField.placeholderString = "无需配置"
        case .baidu:
            modelField.stringValue = ""
            baseURLField.placeholderString = "https://fanyi-api.baidu.com"
            apiKeyField.placeholderString = "API Key"
            modelField.placeholderString = "无需配置"
        case .deepSeek:
            baseURLField.stringValue = AppSettings.defaultBaseURL(for: .deepSeek)
            if modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                modelField.stringValue = AppSettings.defaultModel(for: .deepSeek)
            }
            baseURLField.placeholderString = "自动使用官方地址"
            apiKeyField.placeholderString = "API Key"
            modelField.placeholderString = AppSettings.defaultModel(for: .deepSeek)
        case .ollama, .openAICompatible:
            baseURLField.placeholderString = "https://api.example.com/v1"
            apiKeyField.placeholderString = "API Key"
            modelField.placeholderString = "模型名称"
        }
    }

    @objc private func toggleQuickTranslateFromStatusMenu() {
        var next = settings
        next.quickTranslateEnabled.toggle()
        saveSettings(next)
    }

    @objc private func toggleAutoTranslateFromStatusMenu() {
        var next = settings
        next.autoTranslate.toggle()
        saveSettings(next)
    }

    @objc private func toggleWatchClipboardFromStatusMenu() {
        var next = settings
        next.watchClipboard.toggle()
        saveSettings(next)
    }

    @objc private func toggleAutoCopyFromStatusMenu() {
        var next = settings
        next.autoCopy.toggle()
        saveSettings(next)
    }

    @objc private func toggleAutoPasteFromStatusMenu() {
        var next = settings
        next.autoPaste.toggle()
        saveSettings(next)
    }

}

private final class ModalActionTarget: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func runAction() {
        action()
    }
}

@MainActor
private final class AppleSystemTranslationService {
    private var implementation: Any?
    private var hostingView: NSView?

    func attach(to window: NSWindow) {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            let implementation = AppleSystemTranslationImplementation()
            let hostingView = NSHostingView(rootView: AppleSystemTranslationBridgeView(model: implementation.model))
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            hostingView.alphaValue = 0
            window.contentView?.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.widthAnchor.constraint(equalToConstant: 1),
                hostingView.heightAnchor.constraint(equalToConstant: 1),
                hostingView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
                hostingView.topAnchor.constraint(equalTo: window.contentView!.topAnchor)
            ])
            self.implementation = implementation
            self.hostingView = hostingView
        }
        #endif
    }

    func translate(_ text: String, targetLanguage: TargetLanguage) async throws -> String {
        #if canImport(Translation)
        guard #available(macOS 15.0, *),
              let implementation = implementation as? AppleSystemTranslationImplementation else {
            throw DaisyTranslatorCore.TranslationError.appleSystemTranslationUnavailable
        }
        return try await implementation.translate(text, targetLanguage: targetLanguage)
        #else
        throw DaisyTranslatorCore.TranslationError.appleSystemTranslationUnavailable
        #endif
    }

    func prepareEnglishChinese() async throws {
        #if canImport(Translation)
        guard #available(macOS 15.0, *),
              let implementation = implementation as? AppleSystemTranslationImplementation else {
            return
        }
        try await implementation.prepareEnglishChinese()
        #endif
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
@MainActor
private final class AppleSystemTranslationImplementation {
    let model = AppleSystemTranslationBridgeModel()
    private let availability = LanguageAvailability()

    func translate(_ text: String, targetLanguage: TargetLanguage) async throws -> String {
        let target = await supportedLanguage(for: targetLanguageIdentifier(for: text, targetLanguage: targetLanguage))
        let source = await detectedSourceLanguage(for: text)
        if let source {
            if source.languageCode == target.languageCode {
                return text
            }
            guard await isAvailable(source: source, target: target) else {
                throw DaisyTranslatorCore.TranslationError.appleSystemTranslationUnsupported
            }
        } else {
            try await ensureAvailable(text: text, target: target)
        }
        return try await model.translate(text, source: source, target: target)
    }

    func prepareEnglishChinese() async throws {
        let english = await supportedLanguage(for: "en")
        let chinese = await supportedLanguage(for: "zh-Hans")
        guard await isAvailable(source: english, target: chinese),
              await isAvailable(source: chinese, target: english) else {
            throw DaisyTranslatorCore.TranslationError.appleSystemTranslationUnsupported
        }
        try await model.prepare(
            source: english,
            target: chinese
        )
        try await model.prepare(
            source: chinese,
            target: english
        )
    }

    private func targetLanguageIdentifier(
        for text: String,
        targetLanguage: TargetLanguage
    ) -> String {
        TranslationService.translatesToEnglish(source: text, preference: targetLanguage)
            ? "en"
            : "zh-Hans"
    }

    private func supportedLanguage(for identifier: String) async -> Locale.Language {
        let preferred = Locale.Language(identifier: identifier)
        let supportedLanguages = await availability.supportedLanguages
        if let exact = supportedLanguages.first(where: { $0 == preferred }) {
            return exact
        }
        if let languageCode = preferred.languageCode {
            if let sameScript = supportedLanguages.first(where: {
                $0.languageCode == languageCode && $0.script == preferred.script
            }) {
                return sameScript
            }
            if let sameLanguage = supportedLanguages.first(where: { $0.languageCode == languageCode }) {
                return sameLanguage
            }
        }
        return preferred
    }

    private func detectedSourceLanguage(for text: String) async -> Locale.Language? {
        if Self.containsChineseText(text) {
            return await supportedLanguage(for: "zh-Hans")
        }
        if Self.containsLatinText(text) {
            return await supportedLanguage(for: "en")
        }
        return nil
    }

    private func isAvailable(source: Locale.Language, target: Locale.Language) async -> Bool {
        switch await availability.status(from: source, to: target) {
        case .installed, .supported:
            return true
        case .unsupported:
            return false
        @unknown default:
            return false
        }
    }

    private func ensureAvailable(text: String, target: Locale.Language) async throws {
        guard let status = try? await availability.status(for: text, to: target) else {
            return
        }
        switch status {
        case .installed, .supported:
            return
        case .unsupported:
            throw DaisyTranslatorCore.TranslationError.appleSystemTranslationUnsupported
        @unknown default:
            return
        }
    }

    private static func containsChineseText(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) }
    }

    private static func containsLatinText(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x0041...0x005a).contains($0.value) || (0x0061...0x007a).contains($0.value)
        }
    }
}

@available(macOS 15.0, *)
@MainActor
private final class AppleSystemTranslationBridgeModel: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
    private var pending: PendingRequest?
    private var requestID = 0
    private var timeoutTask: Task<Void, Never>?

    func translate(_ text: String, source: Locale.Language?, target: Locale.Language) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            begin(
                kind: .translate(text),
                source: source,
                target: target,
                continuation: continuation
            )
        }
    }

    func prepare(source: Locale.Language?, target: Locale.Language) async throws {
        let _: String = try await withCheckedThrowingContinuation { continuation in
            begin(kind: .prepare, source: source, target: target, continuation: continuation)
        }
    }

    private func begin(
        kind: PendingRequest.Kind,
        source: Locale.Language?,
        target: Locale.Language,
        continuation: CheckedContinuation<String, Error>
    ) {
        pending?.continuation.resume(throwing: CancellationError())
        timeoutTask?.cancel()
        requestID += 1
        pending = PendingRequest(
            id: requestID,
            kind: kind,
            continuation: continuation
        )
        let currentID = requestID
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled else { return }
            self?.fail(
                requestID: currentID,
                error: DaisyTranslatorCore.TranslationError.appleSystemTranslationFailed("系统翻译超时，请稍后重试")
            )
        }
        if var currentConfiguration = configuration,
           currentConfiguration.source == source,
           currentConfiguration.target == target {
            currentConfiguration.invalidate()
            configuration = currentConfiguration
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    func run(session: TranslationSession) async {
        guard let request = pending else { return }
        do {
            try await session.prepareTranslation()
            switch request.kind {
            case .prepare:
                complete(requestID: request.id, result: "")
            case let .translate(text):
                let response = try await session.translate(text)
                let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translated.isEmpty else { throw DaisyTranslatorCore.TranslationError.missingTranslatedText }
                complete(requestID: request.id, result: translated)
            }
        } catch {
            fail(requestID: request.id, error: normalizedError(error))
        }
    }

    private func normalizedError(_ error: Error) -> Error {
        if error is CancellationError {
            return error
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let containsChinese = message.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) }
        if message.isEmpty || message == "Unable to Translate" || !containsChinese {
            return DaisyTranslatorCore.TranslationError.appleSystemTranslationFailed("系统无法完成这次翻译，请确认源文本语言和目标语言不同，且对应语言包已下载")
        }
        return DaisyTranslatorCore.TranslationError.appleSystemTranslationFailed(message)
    }

    private func complete(requestID: Int, result: String) {
        guard pending?.id == requestID else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        pending?.continuation.resume(returning: result)
        pending = nil
    }

    private func fail(requestID: Int, error: Error) {
        guard pending?.id == requestID else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        pending?.continuation.resume(throwing: error)
        pending = nil
    }

    private struct PendingRequest {
        enum Kind {
            case prepare
            case translate(String)
        }

        let id: Int
        let kind: Kind
        let continuation: CheckedContinuation<String, Error>
    }
}

@available(macOS 15.0, *)
private struct AppleSystemTranslationBridgeView: View {
    @ObservedObject var model: AppleSystemTranslationBridgeModel

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(model.configuration) { session in
                await model.run(session: session)
            }
    }
}
#endif

@MainActor
private final class SettingsWindowController: NSWindowController {
    private var settings: AppSettings
    private var providerConfigurations: [String: ProviderConfiguration]
    private let onSave: (AppSettings) -> Void

    private let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let baseURLField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let modelField = NSTextField()
    private let quickTranslateCheckbox = NSButton(checkboxWithTitle: "快捷翻译", target: nil, action: nil)
    private let autoTranslateCheckbox = NSButton(checkboxWithTitle: "自动翻译", target: nil, action: nil)
    private let watchClipboardCheckbox = NSButton(checkboxWithTitle: "监听剪贴板", target: nil, action: nil)
    private let autoCopyCheckbox = NSButton(checkboxWithTitle: "自动复制", target: nil, action: nil)
    private let autoPasteCheckbox = NSButton(checkboxWithTitle: "自动粘贴", target: nil, action: nil)
    private let shortcutField = NSTextField()
    private var lastSelectedProvider: ModelProvider

    init(settings: AppSettings, onSave: @escaping (AppSettings) -> Void) {
        self.settings = settings
        self.providerConfigurations = AppSettings.defaultProviderConfigurations()
        self.providerConfigurations.merge(settings.providerConfigurations) { _, savedConfiguration in
            savedConfiguration
        }
        self.providerConfigurations[settings.provider.rawValue] = normalizedServiceConfiguration(
            settings.configuration(for: settings.provider),
            for: settings.provider
        )
        self.onSave = onSave
        self.lastSelectedProvider = settings.provider

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.minSize = NSSize(width: 760, height: 440)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = makeContentView()
        render()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeContentView() -> NSView {
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.addTabViewItem(NSTabViewItem(identifier: "service"))
        tabView.tabViewItem(at: 0).label = "服务"
        tabView.tabViewItem(at: 0).view = makeServiceView()
        tabView.addTabViewItem(NSTabViewItem(identifier: "workflow"))
        tabView.tabViewItem(at: 1).label = "工作流"
        tabView.tabViewItem(at: 1).view = makeWorkflowView()
        tabView.addTabViewItem(NSTabViewItem(identifier: "privacy"))
        tabView.tabViewItem(at: 2).label = "隐私"
        tabView.tabViewItem(at: 2).view = makePrivacyView()

        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveClicked))
        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        saveButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(tabView)
        contentView.addSubview(buttons)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            tabView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -16),

            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])
        return contentView
    }

    private func makeServiceView() -> NSView {
        for provider in ModelProvider.allCases {
            providerPopup.addItem(withTitle: providerTitle(provider))
        }
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        baseURLField.placeholderString = "https://api.example.com/v1"
        baseURLField.setContentCompressionResistancePriority(.required, for: .horizontal)
        apiKeyField.placeholderString = "API Key"
        apiKeyField.setContentCompressionResistancePriority(.required, for: .horizontal)
        modelField.placeholderString = "模型名称"
        modelField.setContentCompressionResistancePriority(.required, for: .horizontal)

        let grid = NSGridView(views: [
            [formLabel("类型"), providerPopup],
            [formLabel("Base URL"), baseURLField],
            [formLabel("API Key"), apiKeyField],
            [formLabel("Model"), modelField]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 640

        let hint = wrappingLabel("默认使用 Apple 系统翻译，不需要 API Key。OpenAI-compatible 和 Ollama 可接入你自己的服务，DeepSeek / Google / 百度可使用对应官方 API。")
        hint.translatesAutoresizingMaskIntoConstraints = false
        let links = makeProviderLinksView()

        let view = NSView()
        view.addSubview(grid)
        view.addSubview(links)
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),

            hint.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            links.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            links.trailingAnchor.constraint(lessThanOrEqualTo: grid.trailingAnchor),
            links.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),

            hint.topAnchor.constraint(equalTo: links.bottomAnchor, constant: 16)
        ])
        return view
    }

    private func makeProviderLinksView() -> NSStackView {
        let buttons = externalServiceProviders.compactMap { provider -> NSButton? in
            guard let title = providerApplicationLinkTitle(provider) else { return nil }
            let button = NSButton(title: title, target: self, action: #selector(providerLinkClicked(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(provider.rawValue)
            return button
        }
        let firstRow = NSStackView(views: Array(buttons.prefix(3)))
        firstRow.orientation = .horizontal
        firstRow.spacing = 8
        let secondRow = NSStackView(views: Array(buttons.dropFirst(3)))
        secondRow.orientation = .horizontal
        secondRow.spacing = 8
        let stack = NSStackView(views: [firstRow, secondRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeWorkflowView() -> NSView {
        shortcutField.placeholderString = "Command+Shift+V"
        let grid = NSGridView(views: [
            [quickTranslateCheckbox, formLabel("后台翻译剪贴板并复制译文")],
            [formLabel("快捷键"), shortcutField],
            [autoTranslateCheckbox, formLabel("输入停止后自动翻译")],
            [watchClipboardCheckbox, formLabel("剪贴板变化后自动读取并翻译")],
            [autoCopyCheckbox, formLabel("翻译完成后写入剪贴板")],
            [autoPasteCheckbox, formLabel("翻译完成后粘贴到前台应用")]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 360

        let view = NSView()
        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 22)
        ])
        return view
    }

    private func makePrivacyView() -> NSView {
        let body = wrappingLabel("""
Daisy 不采集账号、设备标识、联系人、浏览记录或使用分析数据。

当你使用 Apple 系统翻译时，翻译由 macOS 的系统翻译能力处理。改用 DeepSeek、Google、百度或 OpenAI-compatible 等外部服务时，原文会发送到你在“服务”里配置的翻译接口；译文由该服务返回。API Key 只保存在本机设置文件中，用于请求你选择的服务。

剪贴板监听默认关闭。开启后，Daisy 会在本机读取剪贴板文本，并按你的配置进行翻译。自动粘贴需要 macOS 辅助功能权限，Daisy 只在触发粘贴时发送 Cmd+V。
""")
        body.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView()
        view.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            body.topAnchor.constraint(equalTo: view.topAnchor, constant: 22)
        ])
        return view
    }

    private func render() {
        providerPopup.selectItem(at: ModelProvider.allCases.firstIndex(of: settings.provider) ?? 0)
        showProviderConfiguration(settings.provider)
        quickTranslateCheckbox.state = settings.quickTranslateEnabled ? .on : .off
        autoTranslateCheckbox.state = settings.autoTranslate ? .on : .off
        watchClipboardCheckbox.state = settings.watchClipboard ? .on : .off
        autoCopyCheckbox.state = settings.autoCopy ? .on : .off
        autoPasteCheckbox.state = settings.autoPaste ? .on : .off
        shortcutField.stringValue = settings.quickTranslateShortcut
    }

    @objc private func providerChanged() {
        let provider = ModelProvider.allCases[providerPopup.indexOfSelectedItem]
        guard provider != lastSelectedProvider else { return }
        let previousProvider = lastSelectedProvider
        captureProviderConfiguration(previousProvider)
        lastSelectedProvider = provider
        showProviderConfiguration(provider)
    }

    @objc private func providerLinkClicked(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let provider = ModelProvider(rawValue: rawValue),
              let url = providerApplicationLinkURL(provider) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func saveClicked() {
        let shortcut = shortcutField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HotKeyCenter.isShortcutSupported(shortcut) else {
            NSSound.beep()
            return
        }

        var next = settings
        let provider = ModelProvider.allCases[providerPopup.indexOfSelectedItem]
        captureProviderConfiguration(provider)
        let configuration = providerConfigurations[provider.rawValue]
            ?? AppSettings.defaultConfiguration(for: provider)
        next.provider = provider
        next.baseURL = configuration.baseURL
        next.apiKey = configuration.apiKey
        next.model = configuration.model
        next.providerConfigurations = providerConfigurations
        next.quickTranslateEnabled = quickTranslateCheckbox.state == .on
        next.quickTranslateShortcut = shortcut
        next.autoTranslate = autoTranslateCheckbox.state == .on
        next.watchClipboard = watchClipboardCheckbox.state == .on
        next.autoCopy = autoCopyCheckbox.state == .on
        next.autoPaste = autoPasteCheckbox.state == .on
        next.onboardingCompleted = true
        settings = next
        onSave(next)
        window?.close()
    }

    private func captureProviderConfiguration(_ provider: ModelProvider) {
        providerConfigurations[provider.rawValue] = normalizedServiceConfiguration(
            ProviderConfiguration(
                baseURL: baseURLField.stringValue,
                apiKey: apiKeyField.stringValue,
                model: modelField.stringValue
            ),
            for: provider
        )
    }

    private func showProviderConfiguration(_ provider: ModelProvider) {
        let configuration = providerConfigurations[provider.rawValue]
            ?? AppSettings.defaultConfiguration(for: provider)
        baseURLField.stringValue = configuration.baseURL
        apiKeyField.stringValue = configuration.apiKey
        modelField.stringValue = configuration.model
        updateServiceFields(provider: provider)
    }

    @objc private func cancelClicked() {
        window?.close()
    }

    private func formLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13)
        return label
    }

    private func providerTitle(_ provider: ModelProvider) -> String {
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

    private func updateServiceFields(provider: ModelProvider) {
        let usesExternalService = provider != .appleSystem
        baseURLField.isEnabled = usesExternalService && provider != .deepSeek
        apiKeyField.isEnabled = usesExternalService
        modelField.isEnabled = usesExternalService && provider != .google && provider != .baidu
        switch provider {
        case .appleSystem:
            baseURLField.stringValue = ""
            apiKeyField.stringValue = ""
            modelField.stringValue = ""
            baseURLField.placeholderString = "无需配置"
            apiKeyField.placeholderString = "无需配置"
            modelField.placeholderString = "无需配置"
        case .google:
            modelField.stringValue = ""
            baseURLField.placeholderString = "https://translate.googleapis.com"
            apiKeyField.placeholderString = "可选：Google Cloud API Key"
            modelField.placeholderString = "无需配置"
        case .baidu:
            modelField.stringValue = ""
            baseURLField.placeholderString = "https://fanyi-api.baidu.com"
            apiKeyField.placeholderString = "API Key"
            modelField.placeholderString = "无需配置"
        case .deepSeek:
            baseURLField.stringValue = AppSettings.defaultBaseURL(for: .deepSeek)
            if modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                modelField.stringValue = AppSettings.defaultModel(for: .deepSeek)
            }
            baseURLField.placeholderString = "自动使用官方地址"
            apiKeyField.placeholderString = "API Key"
            modelField.placeholderString = AppSettings.defaultModel(for: .deepSeek)
        case .ollama, .openAICompatible:
            baseURLField.placeholderString = "https://api.example.com/v1"
            apiKeyField.placeholderString = "API Key"
            modelField.placeholderString = "模型名称"
        }
    }
}

enum SelfTest {
    static func run() {
        do {
            let settings = AppSettings.defaults(environment: ["TT_PROVIDER": ModelProvider.deepSeek.rawValue])
            _ = try TranslationService.makeRequest(source: "hello", settings: settings)
            let url = try TranslationService.resolveChatURL("http://localhost:11434/v1")
            guard url.absoluteString == "http://localhost:11434/v1/chat/completions" else { throw SelfTestError.urlResolution }
            let googleURL = try TranslationService.resolveGoogleFreeTranslateURL("https://translate.googleapis.com/", target: "en", query: "hi")
            guard googleURL.absoluteString == "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=t&q=hi" else { throw SelfTestError.urlResolution }
            let baiduURL = try TranslationService.resolveBaiduTranslateURL("https://fanyi-api.baidu.com/")
            guard baiduURL.absoluteString == "https://fanyi-api.baidu.com/ait/api/aiTextTranslate" else { throw SelfTestError.urlResolution }
            guard TranslationService.baiduSignature(appID: "2015063000000001", query: "apple", salt: "1435660288", secret: "12345678") == "f89f9594663708c1605f3d736d01d2d4" else { throw SelfTestError.urlResolution }
            guard Bundle.module.url(forResource: "daisy", withExtension: "png") != nil else { throw SelfTestError.iconResource }
            try TextWrappingSelfTest.run()
            print("self-test passed")
        } catch {
            fputs("self-test failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

enum SelfTestError: LocalizedError {
    case iconResource
    case urlResolution

    var errorDescription: String? {
        switch self {
        case .iconResource:
            return "icon resource failed"
        case .urlResolution:
            return "chat URL resolution failed"
        }
    }
}

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
