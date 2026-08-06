import AppKit
import DaisyTranslatorCore
import SwiftUI
import XCTest
@testable import DaisyTranslator

/// Renders production Daisy views with fictional, in-memory state for product
/// video capture. It never reads user settings, history, clipboard, or keys.
@MainActor
final class PromoCaptureTests: XCTestCase {
    /// Keep offscreen windows alive until the test process exits. Releasing an
    /// AppKit hosting window immediately after capture can tear down its text
    /// services while XCTest is still draining the main run loop.
    private static var retainedWindows: [NSWindow] = []

    func testCaptureProductionUI() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["PROMO_CAPTURE_DIR"],
              !outputPath.isEmpty
        else {
            throw XCTSkip("Set PROMO_CAPTURE_DIR to write production UI captures.")
        }

        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        try captureTranslator(
            name: "minimal-empty",
            minimal: true,
            pinned: false,
            source: "",
            translation: "",
            size: NSSize(width: 340, height: 308),
            in: outputDirectory
        )
        try captureTranslator(
            name: "minimal-unpinned",
            minimal: true,
            pinned: false,
            source: "Ideas should travel farther than language.",
            translation: "想法应该走得比语言更远。",
            size: NSSize(width: 340, height: 308),
            in: outputDirectory
        )
        try captureTranslator(
            name: "minimal-pinned",
            minimal: true,
            pinned: true,
            source: "Ideas should travel farther than language.",
            translation: "想法应该走得比语言更远。",
            size: NSSize(width: 340, height: 308),
            in: outputDirectory
        )
        try captureTranslator(
            name: "minimal-auto",
            minimal: true,
            pinned: true,
            source: "A quiet tool that stays out of your way.",
            translation: "一个安静、不打扰你的工具。",
            size: NSSize(width: 340, height: 308),
            in: outputDirectory
        )
        try captureTranslator(
            name: "standard-auto",
            minimal: false,
            pinned: false,
            source: "Keep the original. Let the meaning appear beside it.",
            translation: "保留原文，让含义自然出现在旁边。",
            size: NSSize(width: 620, height: 540),
            in: outputDirectory
        )

        try capture(
            quickTranslatePopupCaptureView(
                text: "无需切换窗口，译文就在原文旁边。",
                autoCopyEnabled: true
            )
            .frame(width: 390, height: 156),
            named: "quick-popup",
            size: NSSize(width: 390, height: 156),
            in: outputDirectory
        )

        try captureSettings(provider: .appleSystem, name: "settings-apple", in: outputDirectory)
        try captureSettings(provider: .openAICompatible, name: "settings-openai", in: outputDirectory)
        try captureSettings(provider: .ollama, name: "settings-ollama", in: outputDirectory)
        try captureSettings(provider: .deepSeek, name: "settings-deepseek", in: outputDirectory)
        try captureWorkflow(in: outputDirectory)
    }

    private func captureTranslator(
        name: String,
        minimal: Bool,
        pinned: Bool,
        source: String,
        translation: String,
        size: NSSize,
        in outputDirectory: URL
    ) throws {
        let model = makeModel(provider: .appleSystem)
        var settings = model.settings
        settings.minimalMode = minimal
        settings.alwaysOnTop = pinned
        settings.autoTranslate = true
        settings.autoCopy = true
        model.replaceSettings(settings)
        model.sourceText = source
        model.translatedText = translation

        try capture(
            TranslatorView(model: model, appleTranslationBridge: AnyView(EmptyView()))
                .frame(width: size.width, height: size.height),
            named: name,
            size: size,
            in: outputDirectory
        )
    }

    private func captureSettings(
        provider: ModelProvider,
        name: String,
        in outputDirectory: URL
    ) throws {
        let model = makeModel(provider: provider)
        try capture(
            DaisySettingsView(model: model)
                .frame(width: 700, height: 600),
            named: name,
            size: NSSize(width: 700, height: 600),
            in: outputDirectory
        )
    }

    private func captureWorkflow(in outputDirectory: URL) throws {
        let model = makeModel(provider: .appleSystem)
        try capture(
            DaisyWorkflowSettingsPane(model: model)
                .frame(width: 700, height: 820),
            named: "settings-workflow",
            size: NSSize(width: 700, height: 820),
            in: outputDirectory
        )
    }

    private func makeModel(provider: ModelProvider) -> DaisyModel {
        let model = DaisyModel()
        var settings = AppSettings.defaults(environment: [:])
        settings.provider = provider
        settings.onboardingCompleted = true
        settings.appLanguage = "en"
        settings.apiKey = ""
        settings.quickTranslateEnabled = true
        settings.quickTranslateAutoCopy = true
        settings.autoTranslate = true
        settings.watchClipboard = false
        settings.autoCopy = true
        settings.autoPaste = false
        settings.alwaysOnTop = true

        switch provider {
        case .appleSystem:
            settings.baseURL = ""
            settings.model = ""
        case .openAICompatible:
            settings.baseURL = "https://api.example.com/v1"
            settings.model = "gpt-4.1-mini"
        case .ollama:
            settings.ollamaConnection = .local
            settings.baseURL = ""
            settings.model = "llama3.2"
        case .deepSeek:
            settings.baseURL = AppSettings.defaultBaseURL(for: .deepSeek)
            settings.model = AppSettings.defaultModel(for: .deepSeek)
        case .google, .baidu:
            settings.baseURL = AppSettings.defaultBaseURL(for: provider)
            settings.model = ""
        }

        settings.providerConfigurations[provider.rawValue] = ProviderConfiguration(
            baseURL: settings.baseURL,
            apiKey: "",
            model: settings.model
        )
        model.replaceSettings(settings)
        model.onSettingsChanged = { [weak model] settings in
            model?.replaceSettings(settings)
        }
        return model
    }

    private func capture<Content: View>(
        _ content: Content,
        named name: String,
        size: NSSize,
        in outputDirectory: URL
    ) throws {
        _ = NSApplication.shared
        let root = content
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.wantsLayer = true

        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        hostingView.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            XCTFail("Could not allocate bitmap for \(name)")
            return
        }
        representation.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        guard let data = representation.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode \(name).png")
            return
        }
        try data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        Self.retainedWindows.append(window)
    }
}
