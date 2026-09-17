import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
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

    public static let syntheticEventMagic: Int64 = 0x56494D

    /// Insert at the current caret. Prefers Accessibility, then unicode key events, then ⌘V.
    @discardableResult
    public func insert(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        if insertViaAX(text) { return true }
        if insertViaUnicode(text) { return isTrusted }
        pasteViaClipboard(text)
        return isTrusted
    }

    /// Read currently selected text. Prefers Accessibility, falls back to simulated ⌘C.
    public func readSelection() -> String? {
        if let ax = readSelectionViaAX(), !ax.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ax
        }
        return readSelectionViaClipboard()
    }

    /// Read the currently focused element's selection via Accessibility. Nil if no focus or no selection.
    public func readSelectionViaAX() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let copy = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard copy == .success, let focusedRef else { return nil }
        let element = unsafeBitCast(focusedRef, to: AXUIElement.self)
        var selectionRef: CFTypeRef?
        let sel = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectionRef
        )
        guard sel == .success, let selectionRef else { return nil }
        let raw = unsafeBitCast(selectionRef, to: CFString.self) as String
        return raw.isEmpty ? nil : raw
    }

    /// Read selection by simulating ⌘C and observing the pasteboard.
    public func readSelectionViaClipboard() -> String? {
        guard isTrusted else { return nil }
        let board = NSPasteboard.general
        let initialChangeCount = board.changeCount

        guard sendCopyShortcut() else { return nil }

        let start = Date()
        while board.changeCount == initialChangeCount && Date().timeIntervalSince(start) < 0.15 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        guard board.changeCount != initialChangeCount else {
            return nil
        }

        let copied = board.string(forType: .string)
        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return copied
    }

    private func sendCopyShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let cmdKey = CGKeyCode(kVK_Command)
        let cKey = CGKeyCode(kVK_ANSI_C)
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true),
              let cDown = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true),
              let cUp = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false) else {
            return false
        }
        cDown.flags = .maskCommand
        cUp.flags = .maskCommand
        cmdDown.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMagic)
        cDown.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMagic)
        cUp.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMagic)
        cmdUp.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMagic)

        cmdDown.post(tap: .cgSessionEventTap)
        cDown.post(tap: .cgSessionEventTap)
        cUp.post(tap: .cgSessionEventTap)
        cmdUp.post(tap: .cgSessionEventTap)
        return true
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let copy = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard copy == .success, let focusedRef else { return nil }
        return unsafeBitCast(focusedRef, to: AXUIElement.self)
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
                down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMagic)
                down.post(tap: .cgSessionEventTap)
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                up?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMagic)
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
            down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMagic)
            up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMagic)
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
