import AppKit
import Foundation

@MainActor
final class PasteboardService {
    private(set) var lastProgrammaticText = ""

    func readText() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    func writeText(_ text: String) {
        lastProgrammaticText = text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func pasteIntoFrontmostApp(_ text: String, hiding window: NSWindow?) async throws {
        writeText(text)
        let wasVisible = window?.isVisible == true
        if wasVisible {
            window?.orderOut(nil)
        }

        try await Task.sleep(nanoseconds: 120_000_000)
        try runAppleScript("""
tell application "System Events"
  keystroke "v" using command down
end tell
""")

        if wasVisible {
            try await Task.sleep(nanoseconds: 180_000_000)
            window?.orderFrontRegardless()
        }
    }

    private func runAppleScript(_ source: String) throws {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw PasteboardError.invalidAppleScript
        }
        script.executeAndReturnError(&error)
        if let error {
            throw PasteboardError.appleScriptFailed(error[NSAppleScript.errorMessage] as? String ?? "未知 AppleScript 错误")
        }
    }
}

enum PasteboardError: LocalizedError {
    case invalidAppleScript
    case appleScriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAppleScript:
            return "AppleScript 无效"
        case let .appleScriptFailed(message):
            return message
        }
    }
}
