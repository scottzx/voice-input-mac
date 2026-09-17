import AppKit
import Carbon
import Foundation

/// Long-press starts/stops; single tap toggles; double tap triggers polish.
/// One monitor owns one `Chord` (one key). Use two monitors for two keys.
public final class HotkeyMonitor {
    public struct Chord: Equatable {
        public var display: String
        public var keyCode: UInt16
        /// Modifier flag that flips on/off when the chord's key is pressed.
        public var modifierFlag: NSEvent.ModifierFlags

        public static let rightOption = Chord(
            display: "右 ⌥",
            keyCode: UInt16(kVK_RightOption),
            modifierFlag: .option
        )
        public static let leftCommand = Chord(
            display: "左 ⌘",
            keyCode: UInt16(kVK_Command),
            modifierFlag: .command
        )
    }

    public var onHoldStart: (() -> Void)?
    public var onHoldEnd: (() -> Void)?
    public var onClickToggle: (() -> Void)?
    public var onDoubleClickPolish: (() -> Void)?
    public private(set) var chord: Chord = .rightOption
    public var singleTapImmediate: Bool {
        get { gesture.singleTapImmediate }
        set { gesture.singleTapImmediate = newValue }
    }

    private var gesture = RightOptionGesture()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var longPressWork: DispatchWorkItem?
    private var clickWindowWork: DispatchWorkItem?

    public init() {}

    public func register(_ chord: Chord = .rightOption) {
        unregister()
        self.chord = chord
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    public func unregister() {
        cancelLongPress()
        cancelClickWindow()
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        let wasImmediate = gesture.singleTapImmediate
        gesture = RightOptionGesture(singleTapImmediate: wasImmediate)
    }

    deinit { unregister() }

    private func handle(_ event: NSEvent) {
        // Ignore events synthesized by TextInserter (e.g. Cmd+C / Cmd+V)
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == TextInserter.syntheticEventMagic {
            return
        }
        // `flagsChanged` fires for *every* modifier; gate on the chord's keyCode.
        guard event.keyCode == chord.keyCode else { return }
        let down = event.modifierFlags.contains(chord.modifierFlag)
        if down {
            cancelClickWindow()
            guard let deadline = gesture.keyDown(now: event.timestamp) else { return }
            scheduleLongPress(deadline: deadline, now: event.timestamp)
        } else {
            cancelLongPress()
            let ts = event.timestamp
            if let event = gesture.keyUp(now: ts) {
                cancelClickWindow()
                emit(event)
            } else {
                scheduleClickWindow(now: ts)
            }
        }
    }

    private func scheduleLongPress(deadline: TimeInterval, now: TimeInterval) {
        cancelLongPress()
        let delay = max(0, deadline - now)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.emit(self.gesture.longPressFired(now: ProcessInfo.processInfo.systemUptime))
        }
        longPressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelLongPress() {
        longPressWork?.cancel()
        longPressWork = nil
    }

    private func scheduleClickWindow(now: TimeInterval) {
        cancelClickWindow()
        let delay = gesture.doubleClick
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.emit(self.gesture.clickWindowExpired(now: ProcessInfo.processInfo.systemUptime))
        }
        clickWindowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelClickWindow() {
        clickWindowWork?.cancel()
        clickWindowWork = nil
    }

    private func emit(_ event: RightOptionGesture.Event?) {
        guard let event else { return }
        switch event {
        case .holdStart: onHoldStart?()
        case .holdEnd: onHoldEnd?()
        case .clickToggle: onClickToggle?()
        case .doubleClickPolish: onDoubleClickPolish?()
        }
    }
}