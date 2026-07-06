import AppKit
import ApplicationServices

/// Floating result toolbar for quick translate: shows the translation in a
/// small non-activating panel above the selected text. The panel never steals
/// focus from the frontmost app, its text is selectable with the cursor, and
/// it stays open for as long as the pointer is inside it.
@MainActor
final class QuickTranslatePopupController: NSObject {
    /// Fired when the user flips the "自动复制" checkbox in the popup.
    /// Arguments: new state, currently displayed translation.
    var onAutoCopyChanged: ((Bool, String) -> Void)?

    private var panel: QuickTranslatePanel?
    private var lingerTimer: Timer?
    private var currentText = ""
    private var shownAt = Date.distantPast
    private var hasHovered = false
    private var lastInsideAt = Date.distantPast

    /// Grace period after the pointer leaves the panel.
    private static let exitLinger: TimeInterval = 0.6
    private static let lingerTickInterval: TimeInterval = 0.25

    // MARK: - Presentation

    /// - Parameter anchor: screen rect (AppKit coordinates) of the selected
    ///   text; the panel is placed just above it. Falls back to the current
    ///   mouse location when nil.
    func show(text: String, autoCopyEnabled: Bool, above anchor: NSRect?) {
        close()
        currentText = text

        let panel = makePanel(text: text, autoCopyEnabled: autoCopyEnabled)
        position(panel, above: anchor ?? Self.mouseAnchor())
        panel.orderFrontRegardless()
        self.panel = panel

        shownAt = Date()
        hasHovered = false
        lastInsideAt = .distantPast
        lingerTimer = Timer.scheduledTimer(withTimeInterval: Self.lingerTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.lingerTick()
            }
        }
    }

    func close() {
        lingerTimer?.invalidate()
        lingerTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Time the panel stays up when the pointer never visits it; longer
    /// translations get longer to be read.
    private var initialLinger: TimeInterval {
        min(12, max(6, Double(currentText.count) * 0.06))
    }

    private func lingerTick() {
        guard let panel else { return }
        let now = Date()
        if panel.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) {
            hasHovered = true
            lastInsideAt = now
            return
        }
        // A drag that started inside (text selection) may stray past the
        // edge; never dismiss mid-drag.
        if hasHovered, NSEvent.pressedMouseButtons != 0 { return }
        if hasHovered {
            if now.timeIntervalSince(lastInsideAt) > Self.exitLinger {
                close()
            }
        } else if now.timeIntervalSince(shownAt) > initialLinger {
            close()
        }
    }

    // MARK: - Panel construction

    private func makePanel(text: String, autoCopyEnabled: Bool) -> QuickTranslatePanel {
        let font = NSFont.systemFont(ofSize: 13)
        let measuringOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        // Chrome: 12pt side insets + 5pt text-container padding each side.
        let horizontalChrome: CGFloat = 24 + 10
        let unconstrained = (text as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: measuringOptions,
            attributes: attributes
        )
        let panelWidth = min(380, max(240, ceil(unconstrained.width) + horizontalChrome))
        let wrapped = (text as NSString).boundingRect(
            with: NSSize(width: panelWidth - horizontalChrome, height: CGFloat.greatestFiniteMagnitude),
            options: measuringOptions,
            attributes: attributes
        )
        let textHeight = min(280, max(22, ceil(wrapped.height) + 6))
        let headerHeight: CGFloat = 26
        let panelSize = NSSize(width: panelWidth, height: headerHeight + textHeight + 16)

        let panel = QuickTranslatePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.onCancel = { [weak self] in self?.close() }

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true
        panel.contentView = effectView

        let autoCopyCheckbox = NSButton(
            checkboxWithTitle: "自动复制",
            target: self,
            action: #selector(autoCopyToggled(_:))
        )
        autoCopyCheckbox.controlSize = .small
        autoCopyCheckbox.font = .systemFont(ofSize: 11)
        autoCopyCheckbox.state = autoCopyEnabled ? .on : .off

        let closeButton = NSButton(title: "", target: self, action: #selector(closeClicked))
        if let image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭") {
            closeButton.image = image
            closeButton.imagePosition = .imageOnly
        } else {
            closeButton.title = "✕"
        }
        closeButton.isBordered = false
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.refusesFirstResponder = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = .labelColor
        textView.string = text
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        for view in [autoCopyCheckbox, closeButton, scrollView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            effectView.addSubview(view)
        }
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 7),
            closeButton.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),

            autoCopyCheckbox.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            autoCopyCheckbox.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 12),

            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: headerHeight + 4),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -12)
        ])

        return panel
    }

    private func position(_ panel: NSPanel, above anchor: NSRect) {
        let anchorCenter = NSPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(anchorCenter) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        var x = anchor.midX - size.width / 2
        x = max(visible.minX + 8, min(x, visible.maxX - size.width - 8))
        var y = anchor.maxY + 10
        if y + size.height > visible.maxY {
            // Not enough room above the selection — place the panel below it.
            y = anchor.minY - size.height - 10
            if y < visible.minY {
                y = visible.minY + 8
            }
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private static func mouseAnchor() -> NSRect {
        let location = NSEvent.mouseLocation
        return NSRect(x: location.x - 8, y: location.y - 8, width: 16, height: 16)
    }

    // MARK: - Actions

    @objc private func autoCopyToggled(_ sender: NSButton) {
        onAutoCopyChanged?(sender.state == .on, currentText)
    }

    @objc private func closeClicked() {
        close()
    }

    // MARK: - Selection anchor

    /// Screen rect (AppKit coordinates) of the focused element's selected
    /// text, read through the Accessibility API. Returns nil when the
    /// frontmost app doesn't expose selection bounds; callers fall back to
    /// the mouse location. Requires the Accessibility permission that quick
    /// translate already depends on.
    static func currentSelectionRect() -> NSRect? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedValue as! AXUIElement

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success,
            let boundsValue,
            CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }

        var quartzRect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &quartzRect),
              quartzRect != .zero,
              // Screen-reader APIs occasionally report garbage for web views.
              quartzRect.origin.x.isFinite, quartzRect.origin.y.isFinite,
              let primary = NSScreen.screens.first
        else { return nil }

        // AX reports Quartz coordinates (origin at the primary display's
        // top-left, y down); AppKit windows use bottom-left origin, y up.
        return NSRect(
            x: quartzRect.origin.x,
            y: primary.frame.maxY - quartzRect.maxY,
            width: quartzRect.width,
            height: quartzRect.height
        )
    }
}

/// Borderless panels refuse key status by default; this one accepts it so
/// cursor text selection works, while `.nonactivatingPanel` keeps the
/// frontmost app active. Esc dismisses.
private final class QuickTranslatePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
