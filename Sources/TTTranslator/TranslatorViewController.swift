import AppKit
import Foundation
import TTTranslatorCore

@MainActor
final class TranslatorViewController: NSViewController, NSTextViewDelegate {
    private var settings: AppSettings
    private let translationService: TranslationService
    private let pasteboardService: PasteboardService
    private let onSettingsChanged: (AppSettings) -> Void

    private var requestID = 0
    private var debounceTask: Task<Void, Never>?
    private var lastResult = ""

    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let sourceTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
    private let resultTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))

    init(
        settings: AppSettings,
        translationService: TranslationService,
        pasteboardService: PasteboardService,
        onSettingsChanged: @escaping (AppSettings) -> Void
    ) {
        self.settings = settings
        self.translationService = translationService
        self.pasteboardService = pasteboardService
        self.onSettingsChanged = onSettingsChanged
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
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func acceptClipboardText(_ text: String) {
        sourceTextView.string = text
        setStatus("Clipboard changed")
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
                try await pasteboardService.pasteIntoFrontmostApp(result, hiding: view.window)
                setStatus("已粘贴")
            } catch {
                setStatus("粘贴失败：\(error.localizedDescription)")
            }
        }
    }

    func textDidChange(_ notification: Notification) {
        if notification.object as? NSTextView === sourceTextView {
            scheduleTranslation()
        }
    }

    private func buildInterface() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let titleLabel = NSTextField(labelWithString: "TT")
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let titleStack = NSStackView(views: [titleLabel, statusLabel])
        titleStack.orientation = .vertical
        titleStack.spacing = 2

        let pasteInputButton = makeButton(title: "读剪贴板", action: #selector(pasteInputClicked))
        let translateButton = makeButton(title: "翻译", action: #selector(translateClicked), emphasized: true)
        let headerActions = NSStackView(views: [pasteInputButton, translateButton])
        headerActions.orientation = .horizontal
        headerActions.spacing = 8

        let header = NSStackView(views: [titleStack, spacer(), headerActions])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let sourceLabel = sectionLabel("原文")
        let resultLabel = sectionLabel("译文")
        container.addSubview(sourceLabel)
        container.addSubview(resultLabel)

        configureTextView(sourceTextView, editable: true, accessibilityLabel: "原文输入框")
        configureTextView(resultTextView, editable: false, accessibilityLabel: "译文输出框")
        sourceTextView.delegate = self

        let sourceScrollView = makeScrollView(documentView: sourceTextView)
        let resultScrollView = makeScrollView(documentView: resultTextView)
        container.addSubview(sourceScrollView)
        container.addSubview(resultScrollView)

        let controls = NSStackView(views: [
            makeButton(title: "复制译文", action: #selector(copyClicked)),
            makeButton(title: "粘贴到前台", action: #selector(pasteResultClicked)),
            makeButton(title: "交换", action: #selector(swapClicked)),
            makeButton(title: "清空", action: #selector(clearClicked))
        ])
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(controls)


        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),

            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.topAnchor.constraint(equalTo: container.topAnchor),

            sourceLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sourceLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sourceLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),

            sourceScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sourceScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sourceScrollView.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 6),
            sourceScrollView.heightAnchor.constraint(equalTo: resultScrollView.heightAnchor),
            sourceScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),

            resultLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            resultLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            resultLabel.topAnchor.constraint(equalTo: sourceScrollView.bottomAnchor, constant: 12),

            resultScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            resultScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            resultScrollView.topAnchor.constraint(equalTo: resultLabel.bottomAnchor, constant: 6),
            resultScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),

            controls.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controls.topAnchor.constraint(equalTo: resultScrollView.bottomAnchor, constant: 12),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            controls.bottomAnchor.constraint(equalTo: container.bottomAnchor)
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
        textView.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel(accessibilityLabel)
    }

    private func makeScrollView(documentView: NSTextView) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = documentView
        scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.required, for: .horizontal)
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


    private func scheduleTranslation() {
        debounceTask?.cancel()
        guard settings.autoTranslate else { return }
        let delay = UInt64(max(settings.debounceMilliseconds, 150)) * 1_000_000
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
            setStatus("Ready")
            return
        }

        let requestSettings = settings
        setStatus("Translating...")

        do {
            let translated = try await translationService.translate(text, settings: requestSettings)
            guard currentRequestID == requestID else { return }
            lastResult = translated
            resultTextView.string = translated
            if requestSettings.autoCopy {
                pasteboardService.writeText(translated)
            }
            if requestSettings.autoPaste {
                try await pasteboardService.pasteIntoFrontmostApp(translated, hiding: view.window)
            }
            setStatus(requestSettings.autoCopy ? "Done · copied" : "Done")
        } catch {
            guard currentRequestID == requestID else { return }
            setStatus(error.localizedDescription)
        }
    }

    private func currentSettingsFromToggles() -> AppSettings {
        settings
    }

    @objc private func translateClicked() {
        translateCurrentText()
    }

    @objc private func pasteInputClicked() {
        pullClipboardAndTranslate()
    }

    @objc private func copyClicked() {
        let result = resultTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return }
        pasteboardService.writeText(result)
        setStatus("已复制")
    }

    @objc private func pasteResultClicked() {
        pasteResult()
    }

    @objc private func swapClicked() {
        let source = sourceTextView.string
        sourceTextView.string = resultTextView.string
        resultTextView.string = source
        scheduleTranslation()
    }

    @objc private func clearClicked() {
        sourceTextView.string = ""
        resultTextView.string = ""
        lastResult = ""
        setStatus("Ready")
    }

    private func makeButton(title: String, action: Selector, emphasized: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        if emphasized {
            button.keyEquivalent = "\r"
        }
        return button
    }

    private func spacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return spacer
    }
}
