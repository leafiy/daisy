import AppKit
import Foundation
import TTTranslatorCore

@main
enum TTTranslatorApp {
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
    private var activeTranslationCount = 0
    private var isClipboardWatcherPaused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = settingsStore.load()
        createMenu()
        createWindow()
        createStatusItem()
        applyWindowBehavior()
        updateClipboardWatcher()
        registerHotKeys()
        NSApp.activate(ignoringOtherApps: true)
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
            translationService: translationService,
            pasteboardService: pasteboardService,
            onSettingsChanged: { [weak self] nextSettings in
                self?.saveSettings(nextSettings)
            },
            onTranslationActivityChanged: { [weak self] isActive in
                self?.setTranslationInProgress(isActive)
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TT Translator"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 500, height: 460)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.viewController = controller
        self.window = window
    }

    private func saveSettings(_ nextSettings: AppSettings) {
        settings = nextSettings
        do {
            try settingsStore.save(nextSettings)
            applyWindowBehavior()
            updateClipboardWatcher()
            registerHotKeys()
            viewController?.render(settings: nextSettings)
            rebuildStatusMenu()
        } catch {
            viewController?.setStatus("保存失败：\(error.localizedDescription)")
        }
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
        appMenu.addItem(NSMenuItem(title: "About TT Translator", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide TT Translator", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"))
        appMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit TT Translator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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
            if let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "TT Translator") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "TT"
            }
        }
        statusItem = item
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem(title: window?.isVisible == true ? "隐藏窗口" : "显示窗口", action: #selector(toggleWindowFromStatusMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "读取剪贴板翻译并复制", action: #selector(translateClipboardFromStatusMenu)))
        menu.addItem(menuItem(title: "粘贴当前译文", action: #selector(pasteResultFromStatusMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "模型接口设置…", action: #selector(openModelSettingsFromStatusMenu)))
        menu.addItem(.separator())
        menu.addItem(settingItem(title: "快捷翻译", enabled: settings.quickTranslateEnabled, action: #selector(toggleQuickTranslateFromStatusMenu)))
        menu.addItem(menuItem(title: "快捷翻译快捷键：\(settings.quickTranslateShortcut)", action: #selector(openQuickTranslateShortcutFromStatusMenu)))
        menu.addItem(settingItem(title: "自动翻译", enabled: settings.autoTranslate, action: #selector(toggleAutoTranslateFromStatusMenu)))
        menu.addItem(settingItem(title: "监听剪贴板", enabled: settings.watchClipboard, action: #selector(toggleWatchClipboardFromStatusMenu)))
        menu.addItem(settingItem(title: "自动复制", enabled: settings.autoCopy, action: #selector(toggleAutoCopyFromStatusMenu)))
        menu.addItem(settingItem(title: "自动粘贴", enabled: settings.autoPaste, action: #selector(toggleAutoPasteFromStatusMenu)))
        menu.addItem(settingItem(title: "置顶", enabled: settings.alwaysOnTop, action: #selector(toggleAlwaysOnTopFromMenu)))
        menu.addItem(NSMenuItem(title: "退出 TT Translator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
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
                let translated = try await self.translationService.translate(text, settings: settingsSnapshot)
                guard !Task.isCancelled else { return }
                self.pasteboardService.writeText(translated)
                self.showToast("已翻译并复制")
            } catch {
                guard !Task.isCancelled else { return }
                let message = String(error.localizedDescription.prefix(40))
                self.showToast("翻译失败：\(message)")
            }
        }
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

    @objc private func openModelSettingsFromStatusMenu() {
        let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for provider in ModelProvider.allCases {
            providerPopup.addItem(withTitle: providerTitle(provider))
        }
        providerPopup.selectItem(at: ModelProvider.allCases.firstIndex(of: settings.provider) ?? 0)

        let baseURLField = NSTextField(string: settings.baseURL)
        let apiKeyField = NSSecureTextField(string: settings.apiKey)
        let modelField = NSTextField(string: settings.model)

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
        grid.column(at: 1).width = 380

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
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 230),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "模型接口设置"
        panel.contentView = contentView
        panel.level = .floating

        contentView.addSubview(grid)
        contentView.addSubview(buttons)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            buttons.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 24)
        ])

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        guard response == .OK else { return }

        let provider = ModelProvider.allCases[providerPopup.indexOfSelectedItem]
        let trimmedBaseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = settings
        next.provider = provider
        next.baseURL = trimmedBaseURL.isEmpty ? AppSettings.defaultBaseURL(for: provider) : trimmedBaseURL
        next.apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        next.model = trimmedModel.isEmpty ? AppSettings.defaultModel(for: provider) : trimmedModel
        saveSettings(next)
        _ = saveTarget
        _ = cancelTarget
    }

    private func formLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func providerTitle(_ provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible:
            return "OpenAI-compatible"
        case .ollama:
            return "Ollama"
        case .deepSeek:
            return "DeepSeek"
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

    @objc private func toggleAlwaysOnTopFromMenu() {
        var next = settings
        next.alwaysOnTop.toggle()
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

enum SelfTest {
    static func run() {
        do {
            let settings = AppSettings.defaults(environment: [:])
            _ = try TranslationService.makeRequest(source: "hello", settings: settings)
            guard TranslationService.detectTargetLanguage("hello") == "Simplified Chinese" else { throw SelfTestError.languageDetection }
            guard TranslationService.detectTargetLanguage("你好") == "English" else { throw SelfTestError.languageDetection }
            let url = try TranslationService.resolveChatURL("http://localhost:11434/v1")
            guard url.absoluteString == "http://localhost:11434/v1/chat/completions" else { throw SelfTestError.urlResolution }
            print("self-test passed")
        } catch {
            fputs("self-test failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

enum SelfTestError: LocalizedError {
    case languageDetection
    case urlResolution

    var errorDescription: String? {
        switch self {
        case .languageDetection:
            return "language detection failed"
        case .urlResolution:
            return "chat URL resolution failed"
        }
    }
}
