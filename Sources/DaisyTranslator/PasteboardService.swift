import AppKit
import Foundation

@MainActor
final class PasteboardService {
    private(set) var lastProgrammaticText = ""

    private enum VirtualKey {
        static let c = 8
        static let v = 9
    }

    func readText() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    /// Ground-truth read for user-initiated actions (hotkeys, menu items).
    /// Reads through a fresh `pbpaste` process so a stale in-process
    /// pasteboard cache — possible after the app has been idle for a long
    /// time — cannot serve outdated content. Falls back to NSPasteboard
    /// when the helper is unavailable.
    func readTextVerified() -> String {
        readViaPbpaste() ?? readText()
    }

    @discardableResult
    func writeText(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let changeCountBefore = pasteboard.changeCount
        pasteboard.clearContents()
        let accepted = pasteboard.setString(text, forType: .string)

        // Verify OUT of process. After long idle the app's connection to the
        // pasteboard server can go stale; NSPasteboard then reports success
        // against its process-local cache (setString returns true and an
        // in-process read-back matches) while the system clipboard that
        // other apps see never changes. pbpaste runs with a fresh
        // connection and cannot be fooled by this process's state.
        switch verifyClipboard(equals: text) {
        case .match:
            lastProgrammaticText = text
            return true
        case .unverifiable:
            // pbpaste unavailable — best-effort in-process verification.
            if accepted, pasteboard.string(forType: .string) == text {
                lastProgrammaticText = text
                return true
            }
        case .mismatch:
            break
        }
        NSLog(
            "Daisy: NSPasteboard write did not reach the system clipboard (setString=%d, changeCount %ld -> %ld); retrying via pbcopy",
            accepted ? 1 : 0,
            changeCountBefore,
            pasteboard.changeCount
        )

        // Retry through a fresh helper process: it opens its own pasteboard
        // connection and bypasses whatever this process has wedged.
        if writeViaPbcopy(text), verifyClipboard(equals: text) != .mismatch {
            lastProgrammaticText = text
            return true
        }
        NSLog("Daisy: pbcopy fallback failed; clipboard write lost")
        return false
    }

    /// Copies the frontmost app's current selection by synthesizing Cmd+C
    /// and waiting for the pasteboard to change. Returns nil when nothing
    /// was selected (the pasteboard stays untouched in that case).
    /// Requires accessibility permission.
    func copySelectedTextFromFrontmostApp() async throws -> String? {
        let pasteboard = NSPasteboard.general
        let changeCountBefore = pasteboard.changeCount
        try sendCommandKeystroke(Self.VirtualKey.c)
        // Give the frontmost app time to service the copy; apps with
        // asynchronous clipboards (browsers) can take a few hundred ms.
        for _ in 0..<8 {
            try await Task.sleep(nanoseconds: 60_000_000)
            if pasteboard.changeCount != changeCountBefore {
                return pasteboard.string(forType: .string)
            }
        }
        return nil
    }

    func pasteIntoFrontmostApp(_ text: String, hiding window: NSWindow?) async throws {
        guard writeText(text) else {
            throw PasteboardError.writeFailed
        }
        let wasVisible = window?.isVisible == true
        if wasVisible {
            window?.orderOut(nil)
        }

        try await Task.sleep(nanoseconds: 120_000_000)
        try sendCommandKeystroke(Self.VirtualKey.v)

        if wasVisible {
            try await Task.sleep(nanoseconds: 180_000_000)
            window?.orderFrontRegardless()
        }
    }

    // MARK: - Out-of-process pasteboard access

    private enum ClipboardVerification {
        case match
        case mismatch
        case unverifiable
    }

    /// pbcopy/pbpaste transcode using the locale; GUI apps launched by
    /// launchd have no LANG set, which would mangle non-ASCII text.
    private static let utf8Environment = [
        "LC_ALL": "en_US.UTF-8",
        "LANG": "en_US.UTF-8"
    ]

    private func verifyClipboard(equals text: String) -> ClipboardVerification {
        guard let current = readViaPbpaste() else { return .unverifiable }
        return current == text ? .match : .mismatch
    }

    private func readViaPbpaste() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbpaste")
        process.environment = Self.utf8Environment
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Drain before waiting so output larger than the pipe buffer
        // cannot deadlock the child.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeViaPbcopy(_ text: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        process.environment = Self.utf8Environment
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        stdin.fileHandleForWriting.write(Data(text.utf8))
        stdin.fileHandleForWriting.closeFile()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Posts Cmd+<key> as CGEvents. Unlike AppleScript keystrokes through
    /// System Events, this needs only the Accessibility permission — no
    /// Automation (Apple Events) consent and no hardened-runtime
    /// apple-events entitlement, both of which silently break in signed
    /// release builds.
    private func sendCommandKeystroke(_ virtualKey: Int) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(virtualKey), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(virtualKey), keyDown: false) else {
            throw PasteboardError.keystrokeFailed
        }
        // Explicit flags override any physically held hotkey modifiers.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

enum PasteboardError: LocalizedError {
    case writeFailed
    case keystrokeFailed

    var errorDescription: String? {
        switch self {
        case .writeFailed:
            return L("Failed to write to clipboard. Try again.")
        case .keystrokeFailed:
            return L("Failed to send keystroke. Check Accessibility permission.")
        }
    }
}
