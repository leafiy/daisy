import AppKit
import ApplicationServices
import SwiftUI
import LeafiyUI
import LeafiyUICore

/// Floating result toolbar for quick translate: shows the translation in a
/// small non-activating panel above the selected text. The panel never steals
/// focus from the frontmost app, its text is selectable with the cursor, and
/// it stays open for as long as the pointer is inside it.
@MainActor
final class QuickTranslatePopupController: NSObject, NSWindowDelegate {
    /// Fired when the user flips the "Auto copy" checkbox in the popup.
    /// Arguments: new state, currently displayed translation.
    var onAutoCopyChanged: ((Bool, String) -> Void)?

    private var panel: LeafiyFloatingPanel?
    private var lingerTimer: Timer?
    private var currentText = ""
    private var currentAutoCopyEnabled = true
    private var languageObserver: NSObjectProtocol?
    private var shownAt = Date.distantPast
    private var hasHovered = false
    private var lastInsideAt = Date.distantPast

    private enum Metrics {
        static let minWidth: CGFloat = 240
        static let maxWidth: CGFloat = 380
        static let maxTextHeight: CGFloat = 280
        static let minTextHeight: CGFloat = 44
        static let headerHeight: CGFloat = 30
        static let panelMargin: CGFloat = 8
        static let anchorGap: CGFloat = 10
    }

    /// Grace period after the pointer leaves the panel.
    private static let exitLinger: TimeInterval = 0.6
    private static let lingerTickInterval: TimeInterval = 0.25

    override init() {
        super.init()
        languageObserver = NotificationCenter.default.addObserver(
            forName: LeafiyLocalization.languageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshForLanguageChange()
            }
        }
    }

    // MARK: - Presentation

    /// - Parameter anchor: screen rect (AppKit coordinates) of the selected
    ///   text; the panel is placed just above it. Falls back to the current
    ///   mouse location when nil.
    func show(text: String, autoCopyEnabled: Bool, above anchor: NSRect?) {
        close()
        currentText = text
        currentAutoCopyEnabled = autoCopyEnabled

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
        let panel = panel
        self.panel = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingPanel = notification.object as? LeafiyFloatingPanel,
              closingPanel === panel
        else { return }
        lingerTimer?.invalidate()
        lingerTimer = nil
        panel?.delegate = nil
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
        if panel.frame.insetBy(dx: -LeafiyDesign.Spacing.xs, dy: -LeafiyDesign.Spacing.xs).contains(NSEvent.mouseLocation) {
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

    private func makePanel(text: String, autoCopyEnabled: Bool) -> LeafiyFloatingPanel {
        let panelSize = fittingPanelSize(for: text)
        let panel = LeafiyFloatingPanel(
            configuration: LeafiyFloatingPanelConfiguration(
                canBecomeKey: true,
                isMovable: true,
                hasShadow: true
            ),
            content: popupContent(text: text, autoCopyEnabled: autoCopyEnabled)
        )
        panel.setFrame(NSRect(origin: .zero, size: panelSize), display: false)
        panel.contentView?.frame = NSRect(origin: .zero, size: panelSize)
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        return panel
    }

    private func popupContent(text: String, autoCopyEnabled: Bool) -> QuickTranslatePopupContent {
        QuickTranslatePopupContent(
            text: text,
            autoCopyEnabled: autoCopyEnabled,
            onAutoCopyChanged: { [weak self] enabled in
                self?.currentAutoCopyEnabled = enabled
                self?.onAutoCopyChanged?(enabled, text)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
    }

    private func refreshForLanguageChange() {
        guard let panel else { return }
        panel.setContent(popupContent(text: currentText, autoCopyEnabled: currentAutoCopyEnabled))
    }

    private func fittingPanelSize(for text: String) -> NSSize {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let measuringOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let horizontalChrome = (LeafiyDesign.Spacing.m + LeafiyDesign.Spacing.l) * 2
        let unconstrained = (text as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: measuringOptions,
            attributes: attributes
        )
        let panelWidth = min(Metrics.maxWidth, max(Metrics.minWidth, ceil(unconstrained.width) + horizontalChrome))
        let wrapped = (text as NSString).boundingRect(
            with: NSSize(width: panelWidth - horizontalChrome, height: CGFloat.greatestFiniteMagnitude),
            options: measuringOptions,
            attributes: attributes
        )
        let textHeight = min(Metrics.maxTextHeight, max(Metrics.minTextHeight, ceil(wrapped.height) + LeafiyDesign.Spacing.m))
        return NSSize(
            width: panelWidth,
            height: Metrics.headerHeight + textHeight + LeafiyDesign.Spacing.xl
        )
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
        x = max(visible.minX + Metrics.panelMargin, min(x, visible.maxX - size.width - Metrics.panelMargin))
        var y = anchor.maxY + Metrics.anchorGap
        if y + size.height > visible.maxY {
            // Not enough room above the selection — place the panel below it.
            y = anchor.minY - size.height - Metrics.anchorGap
            if y < visible.minY {
                y = visible.minY + Metrics.panelMargin
            }
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private static func mouseAnchor() -> NSRect {
        let location = NSEvent.mouseLocation
        return NSRect(
            x: location.x - Metrics.panelMargin,
            y: location.y - Metrics.panelMargin,
            width: Metrics.panelMargin * 2,
            height: Metrics.panelMargin * 2
        )
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

    deinit {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
    }
}

private struct QuickTranslatePopupContent: View {
    let text: String
    @State private var autoCopyEnabled: Bool
    let onAutoCopyChanged: (Bool) -> Void
    let onClose: () -> Void

    init(
        text: String,
        autoCopyEnabled: Bool,
        onAutoCopyChanged: @escaping (Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.text = text
        self._autoCopyEnabled = State(initialValue: autoCopyEnabled)
        self.onAutoCopyChanged = onAutoCopyChanged
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.s) {
            HStack {
                Toggle(L("Auto copy"), isOn: Binding(
                    get: { autoCopyEnabled },
                    set: { enabled in
                        autoCopyEnabled = enabled
                        onAutoCopyChanged(enabled)
                    }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Close"))
            }
            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, LeafiyDesign.Spacing.m)
        .padding(.vertical, LeafiyDesign.Spacing.s)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LeafiyDesign.Radius.panel))
        .overlay(
            RoundedRectangle(cornerRadius: LeafiyDesign.Radius.panel)
                .strokeBorder(.quaternary)
        )
    }
}

/// Exposes the production popup composition to visual-capture tests while
/// keeping `QuickTranslatePopupContent` private.
@MainActor
func quickTranslatePopupCaptureView(
    text: String,
    autoCopyEnabled: Bool = true
) -> AnyView {
    AnyView(
        QuickTranslatePopupContent(
            text: text,
            autoCopyEnabled: autoCopyEnabled,
            onAutoCopyChanged: { _ in },
            onClose: {}
        )
    )
}
