import AppKit
import ApplicationServices
import Foundation

public final class TextInserter {
    public init() {}

    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Insert at the current caret. Prefers Accessibility, then unicode key events, then ⌘V.
    @discardableResult
    public func insert(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        if insertViaAX(text) { return true }
        if insertViaUnicode(text) { return isTrusted }
        pasteViaClipboard(text)
        return isTrusted
    }

    private func insertViaAX(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let copy = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard copy == .success, let focusedRef else { return false }
        let element = unsafeBitCast(focusedRef, to: AXUIElement.self)
        let set = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        return set == .success
    }

    private func insertViaUnicode(_ text: String) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let units = Array(text.utf16)
        var index = 0
        var posted = false
        while index < units.count {
            let end = min(index + 20, units.count)
            let chunk = Array(units[index..<end])
            let ok = chunk.withUnsafeBufferPointer { buf -> Bool in
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let base = buf.baseAddress else {
                    return false
                }
                down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: base)
                down.post(tap: .cgSessionEventTap)
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                up?.post(tap: .cgSessionEventTap)
                return true
            }
            if !ok { return posted }
            posted = true
            index = end
        }
        return posted
    }

    private func pasteViaClipboard(_ text: String) {
        let board = NSPasteboard.general
        let previous = board.string(forType: .string)
        board.clearContents()
        board.setString(text, forType: .string)
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 0x09
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) {
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            board.clearContents()
            if let previous {
                board.setString(previous, forType: .string)
            }
        }
    }
}
