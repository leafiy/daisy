import AppKit
import Foundation
import DaisyTranslatorCore

@MainActor
final class TranslatorViewController: NSViewController, NSTextViewDelegate {
    private var settings: AppSettings
    private let pasteboardService: PasteboardService
    private let translateText: (String, AppSettings) async throws -> String
    private let onSettingsChanged: (AppSettings) -> Void
    private let onTranslationActivityChanged: (Bool) -> Void
    private let onUserNotification: (String) -> Void
    private let ensurePastePermission: () -> Bool

    private var requestID = 0
    private var debounceTask: Task<Void, Never>?
    private var lastResult = ""
    private let minimumDebounceMilliseconds = 150
    private let maximumDebounceMilliseconds = 1_200

    private let statusLabel = NSTextField(labelWithString: "就绪")
    private let sourceTextView = WrappingTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
    private let resultTextView = WrappingTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
    private let targetLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let alwaysOnTopButton = NSButton()

    init(
        settings: AppSettings,
        pasteboardService: PasteboardService,
        translateText: @escaping (String, AppSettings) async throws -> String,
        onSettingsChanged: @escaping (AppSettings) -> Void,
        onTranslationActivityChanged: @escaping (Bool) -> Void,
        onUserNotification: @escaping (String) -> Void,
        ensurePastePermission: @escaping () -> Bool
    ) {
        self.settings = settings
        self.pasteboardService = pasteboardService
        self.translateText = translateText
        self.onSettingsChanged = onSettingsChanged
        self.onTranslationActivityChanged = onTranslationActivityChanged
        self.onUserNotification = onUserNotification
        self.ensurePastePermission = ensurePastePermission
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = .sidebar
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        view = effectView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        render(settings: settings)
    }

    func render(settings: AppSettings) {
        self.settings = settings
        if targetLanguagePopup.numberOfItems == TargetLanguage.allCases.count {
            targetLanguagePopup.selectItem(at: TargetLanguage.allCases.firstIndex(of: settings.targetLanguage) ?? 0)
        }
        updateAlwaysOnTopButton()
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func acceptClipboardText(_ text: String) {
        sourceTextView.string = text
        setStatus("已读取剪贴板")
        scheduleTranslation()
    }

    func pullClipboardAndTranslate() {
        let text = pasteboardService.readText()
        guard !text.isEmpty else {
            setStatus("剪贴板为空")
            return
        }
        sourceTextView.string = text
        translateCurrentText()
    }

    func pasteResult() {
        let result = resultTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                guard ensurePastePermission() else { return }
                try await pasteboardService.pasteIntoFrontmostApp(result, hiding: view.window)
                setStatus("已粘贴")
                onUserNotification("已粘贴")
            } catch {
                setStatus("粘贴失败：\(TranslationService.userFacingErrorMessage(error, provider: nil))")
            }
        }
    }

    func retryCurrentText() {
        translateCurrentText()
    }

    func textDidChange(_ notification: Notification) {
        if notification.object as? NSTextView === sourceTextView {
            requestID += 1
            scheduleTranslation(waitingForInputToStop: true)
        }
    }

    private func buildInterface() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        configureAlwaysOnTopButton()
        let pasteInputButton = makeButton(title: "读剪贴板", action: #selector(pasteInputClicked))
        let headerActions = NSStackView(views: [alwaysOnTopButton, pasteInputButton])
        headerActions.orientation = .horizontal
        headerActions.alignment = .centerY
        headerActions.spacing = 8

        let targetLanguageLabel = NSTextField(labelWithString: "目标语言")
        targetLanguageLabel.font = .systemFont(ofSize: 12)
        targetLanguageLabel.textColor = .secondaryLabelColor
        targetLanguagePopup.addItems(withTitles: TargetLanguage.allCases.map(\.menuTitle))
        targetLanguagePopup.target = self
        targetLanguagePopup.action = #selector(targetLanguageChanged)
        targetLanguagePopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [spacer(), headerActions])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let sourceLabel = sectionLabel("原文")
        let resultLabel = sectionLabel("译文")
        container.addSubview(sourceLabel)

        let resultHeader = NSStackView(views: [resultLabel, spacer(), targetLanguageLabel, targetLanguagePopup])
        resultHeader.orientation = .horizontal
        resultHeader.alignment = .centerY
        resultHeader.distribution = .fill
        resultHeader.spacing = 8
        resultHeader.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(resultHeader)

        configureTextView(sourceTextView, editable: true, accessibilityLabel: "原文输入框")
        configureTextView(resultTextView, editable: false, accessibilityLabel: "译文输出框")
        sourceTextView.delegate = self

        let sourceScrollView = makeScrollView(documentView: sourceTextView)
        let resultScrollView = makeScrollView(documentView: resultTextView)
        let resultContainer = NSView()
        resultContainer.translatesAutoresizingMaskIntoConstraints = false
        let resultCopyButton = makeButton(title: "复制", action: #selector(copyClicked))
        resultCopyButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sourceScrollView)
        container.addSubview(resultContainer)
        resultContainer.addSubview(resultScrollView)
        resultContainer.addSubview(resultCopyButton)
        container.addSubview(statusLabel)

        let controls = NSStackView(views: [
            makeButton(title: "粘贴到前台", action: #selector(pasteResultClicked)),
            makeButton(title: "清空", action: #selector(clearClicked))
        ])
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(controls)

        let windowPadding: CGFloat = 18
        let titlebarControlsClearance: CGFloat = 154
        let headerTopClearance: CGFloat = 10

        NSLayoutConstraint.activate([
            alwaysOnTopButton.widthAnchor.constraint(equalToConstant: 30),
            alwaysOnTopButton.heightAnchor.constraint(equalToConstant: 28),
            targetLanguagePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            targetLanguagePopup.widthAnchor.constraint(lessThanOrEqualToConstant: 282),

            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: windowPadding),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -windowPadding),
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: windowPadding),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -windowPadding),

            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: titlebarControlsClearance),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: headerTopClearance),

            sourceLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sourceLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sourceLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),

            sourceScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sourceScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sourceScrollView.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 6),
            sourceScrollView.heightAnchor.constraint(equalTo: resultContainer.heightAnchor),
            sourceScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            resultHeader.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            resultHeader.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            resultHeader.topAnchor.constraint(equalTo: sourceScrollView.bottomAnchor, constant: 12),

            resultContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            resultContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            resultContainer.topAnchor.constraint(equalTo: resultHeader.bottomAnchor, constant: 6),
            resultContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            resultScrollView.leadingAnchor.constraint(equalTo: resultContainer.leadingAnchor),
            resultScrollView.trailingAnchor.constraint(equalTo: resultContainer.trailingAnchor),
            resultScrollView.topAnchor.constraint(equalTo: resultContainer.topAnchor),
            resultScrollView.bottomAnchor.constraint(equalTo: resultContainer.bottomAnchor),
            resultCopyButton.trailingAnchor.constraint(equalTo: resultContainer.trailingAnchor, constant: -10),
            resultCopyButton.bottomAnchor.constraint(equalTo: resultContainer.bottomAnchor, constant: -10),

            controls.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controls.topAnchor.constraint(equalTo: resultContainer.bottomAnchor, constant: 12),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -12),
            controls.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: controls.centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220)
        ])
    }

    private func configureTextView(_ textView: NSTextView, editable: Bool, accessibilityLabel: String) {
        textView.font = .systemFont(ofSize: 15)
        textView.isEditable = editable
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.allowsUndo = editable
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.textContainer?.containerSize = NSSize(width: max(textView.bounds.width, 1), height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.setAccessibilityLabel(accessibilityLabel)
    }

    private func makeScrollView(documentView: NSTextView) -> NSScrollView {
        let scrollView = NonExpandingScrollView(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = documentView
        scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollView.setContentCompressionResistancePriority(.required, for: .vertical)
        return scrollView
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }


    private func scheduleTranslation(waitingForInputToStop: Bool = false) {
        debounceTask?.cancel()
        guard settings.autoTranslate else { return }
        let configuredDelay = min(
            max(settings.debounceMilliseconds, minimumDebounceMilliseconds),
            maximumDebounceMilliseconds
        )
        let delayMilliseconds = waitingForInputToStop ? maximumDebounceMilliseconds : configuredDelay
        let delay = UInt64(delayMilliseconds) * 1_000_000
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.translateCurrentTextAsync()
        }
    }

    private func translateCurrentText() {
        Task { [weak self] in
            await self?.translateCurrentTextAsync()
        }
    }

    private func translateCurrentTextAsync() async {
        let text = sourceTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        requestID += 1
        let currentRequestID = requestID

        guard !text.isEmpty else {
            resultTextView.string = ""
            lastResult = ""
            setStatus("就绪")
            return
        }

        let requestSettings = settings
        setStatus("翻译中…")
        onTranslationActivityChanged(true)
        defer { onTranslationActivityChanged(false) }

        do {
            let translated = try await translateText(text, requestSettings)
            guard currentRequestID == requestID else { return }
            lastResult = translated
            resultTextView.string = translated
            if requestSettings.autoCopy {
                pasteboardService.writeText(translated)
                onUserNotification("已复制译文")
            }
            if requestSettings.autoPaste {
                guard ensurePastePermission() else {
                    setStatus("自动粘贴需要辅助功能权限")
                    return
                }
                try await pasteboardService.pasteIntoFrontmostApp(translated, hiding: view.window)
                onUserNotification("已自动粘贴")
            }
            setStatus(requestSettings.autoCopy ? "已完成并复制" : "已完成")
        } catch {
            guard currentRequestID == requestID else { return }
            lastResult = ""
            resultTextView.string = ""
            setStatus(TranslationService.userFacingErrorMessage(error, provider: requestSettings.provider))
        }
    }

    private func currentSettingsFromToggles() -> AppSettings {
        settings
    }

    @objc private func pasteInputClicked() {
        pullClipboardAndTranslate()
    }

    @objc private func copyClicked() {
        let result = resultTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return }
        pasteboardService.writeText(result)
        setStatus("已复制")
        onUserNotification("已复制")
    }

    @objc private func pasteResultClicked() {
        pasteResult()
    }

    @objc private func targetLanguageChanged() {
        let selected = TargetLanguage.allCases[targetLanguagePopup.indexOfSelectedItem]
        guard selected != settings.targetLanguage else { return }
        var next = settings
        next.targetLanguage = selected
        onSettingsChanged(next)
        scheduleTranslation()
    }

    @objc private func alwaysOnTopClicked() {
        var next = settings
        next.alwaysOnTop.toggle()
        onSettingsChanged(next)
    }

    @objc private func clearClicked() {
        sourceTextView.string = ""
        resultTextView.string = ""
        lastResult = ""
        setStatus("就绪")
    }

    private func makeButton(title: String, action: Selector, emphasized: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        if emphasized {
            button.keyEquivalent = "\r"
        }
        return button
    }

    private func configureAlwaysOnTopButton() {
        alwaysOnTopButton.target = self
        alwaysOnTopButton.action = #selector(alwaysOnTopClicked)
        alwaysOnTopButton.bezelStyle = .rounded
        alwaysOnTopButton.imagePosition = .imageOnly
        alwaysOnTopButton.setButtonType(.toggle)
        alwaysOnTopButton.translatesAutoresizingMaskIntoConstraints = false
        alwaysOnTopButton.setContentHuggingPriority(.required, for: .horizontal)
        alwaysOnTopButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        updateAlwaysOnTopButton()
    }

    private func updateAlwaysOnTopButton() {
        alwaysOnTopButton.state = settings.alwaysOnTop ? .on : .off
        alwaysOnTopButton.toolTip = settings.alwaysOnTop ? "取消置顶" : "置顶窗口"
        let symbolName = settings.alwaysOnTop ? "pin.fill" : "pin"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "置顶") {
            let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            alwaysOnTopButton.image = image.withSymbolConfiguration(configuration) ?? image
        } else {
            alwaysOnTopButton.title = "置顶"
        }
    }

    private func spacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return spacer
    }
}

private final class WrappingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateWrappingWidth()
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    private func updateWrappingWidth() {
        textContainer?.containerSize = NSSize(width: max(bounds.width, 1), height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = true
    }
}

private final class NonExpandingScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func tile() {
        super.tile()
        resizeDocumentViewForWrapping()
    }

    private func resizeDocumentViewForWrapping() {
        guard let textView = documentView as? NSTextView else { return }
        let targetWidth = max(contentView.bounds.width, 1)
        let targetHeight = max(textView.frame.height, contentView.bounds.height)
        if abs(textView.frame.width - targetWidth) > 0.5 || abs(textView.frame.height - targetHeight) > 0.5 {
            textView.setFrameSize(NSSize(width: targetWidth, height: targetHeight))
        }
        if let textContainer = textView.textContainer, abs(textContainer.containerSize.width - targetWidth) > 0.5 {
            textContainer.containerSize = NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
            textContainer.widthTracksTextView = true
        }
    }
}

enum TextWrappingSelfTest {
    static func run() throws {
        let textView = WrappingTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        textView.font = .systemFont(ofSize: 15)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping

        let scrollView = NonExpandingScrollView(frame: NSRect(x: 0, y: 0, width: 180, height: 120))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        scrollView.tile()

        let viewportWidth = max(scrollView.contentView.bounds.width, 1)
        guard abs(textView.frame.width - viewportWidth) <= 0.5 else {
            throw TextWrappingSelfTestError.didNotConstrainToViewport
        }

        textView.string = "This is a long sentence that must wrap into multiple visual lines inside the Daisy translation text box."
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            throw TextWrappingSelfTestError.didNotWrapLongText
        }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var lineCount = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
            lineCount += 1
        }
        guard lineCount > 1 else {
            throw TextWrappingSelfTestError.didNotWrapLongText
        }
    }
}

enum TextWrappingSelfTestError: LocalizedError {
    case didNotConstrainToViewport
    case didNotWrapLongText

    var errorDescription: String? {
        switch self {
        case .didNotConstrainToViewport:
            return "text view width did not track the scroll viewport"
        case .didNotWrapLongText:
            return "long text did not wrap into multiple visual lines"
        }
    }
}
