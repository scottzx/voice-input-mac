import AppKit
import Carbon
import Foundation

/// Right Option: double-tap keeps listening, double-tap again stops;
/// long-press starts, release stops.
public final class HotkeyMonitor {
    public struct Chord: Equatable {
        public var display: String
        public static let rightOption = Chord(display: "右 ⌥")
    }

    public var onHoldStart: (() -> Void)?
    public var onHoldEnd: (() -> Void)?
    public var onStickyToggle: (() -> Void)?
    public private(set) var chord: Chord = .rightOption

    private var gesture = RightOptionGesture()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var longPressWork: DispatchWorkItem?
    private let rightOptionKey: UInt16 = UInt16(kVK_RightOption)

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
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        gesture = RightOptionGesture()
    }

    deinit { unregister() }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == rightOptionKey else { return }
        let down = event.modifierFlags.contains(.option)
        if down {
            guard let deadline = gesture.keyDown(now: event.timestamp) else { return }
            scheduleLongPress(deadline: deadline, now: event.timestamp)
        } else {
            cancelLongPress()
            emit(gesture.keyUp(now: event.timestamp))
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

    private func emit(_ event: RightOptionGesture.Event?) {
        guard let event else { return }
        switch event {
        case .holdStart: onHoldStart?()
        case .holdEnd: onHoldEnd?()
        case .stickyToggle: onStickyToggle?()
        }
    }
}
