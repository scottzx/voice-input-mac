import Foundation

/// Right Option state machine:
/// - press-and-hold past `longPress`: `holdStart` on entry, `holdEnd` on release.
/// - single quick tap: `clickToggle` after the `doubleClick` window expires with no second tap.
/// - two quick taps within `doubleClick`: `doubleClickPolish` immediately on the second release.
public struct RightOptionGesture: Sendable {
    public enum Event: Sendable, Equatable {
        case holdStart
        case holdEnd
        case clickToggle
        case doubleClickPolish
    }

    public var longPress: TimeInterval
    public var doubleClick: TimeInterval
    public var singleTapImmediate: Bool

    private var down = false
    private var holding = false
    private var downAt: TimeInterval = 0
    private var lastTapAt: TimeInterval = 0
    private var waitingSecondTap = false

    public init(
        longPress: TimeInterval = 0.28,
        doubleClick: TimeInterval = 0.50,
        singleTapImmediate: Bool = false
    ) {
        self.longPress = longPress
        self.doubleClick = doubleClick
        self.singleTapImmediate = singleTapImmediate
    }

    public var isDown: Bool { down }
    public var isHolding: Bool { holding }

    /// Call on Right Option key-down. Returns the deadline for a long-press timer.
    public mutating func keyDown(now: TimeInterval) -> TimeInterval? {
        guard !down else { return nil }
        down = true
        holding = false
        downAt = now
        return now + longPress
    }

    /// Call on Right Option key-up.
    public mutating func keyUp(now: TimeInterval) -> Event? {
        guard down else { return nil }
        down = false
        if holding {
            holding = false
            lastTapAt = 0
            waitingSecondTap = false
            return .holdEnd
        }
        if singleTapImmediate {
            lastTapAt = 0
            waitingSecondTap = false
            return .clickToggle
        }
        if waitingSecondTap, lastTapAt > 0, now - lastTapAt <= doubleClick {
            waitingSecondTap = false
            lastTapAt = 0
            return .doubleClickPolish
        }
        lastTapAt = now
        waitingSecondTap = true
        return nil
    }

    /// Call when the long-press timer fires.
    public mutating func longPressFired(now: TimeInterval) -> Event? {
        guard down, !holding else { return nil }
        guard now - downAt >= longPress - 0.001 else { return nil }
        holding = true
        waitingSecondTap = false
        lastTapAt = 0
        return .holdStart
    }

    /// Call when the click-window timer fires. Emits `clickToggle` only when no
    /// second tap arrived in time and no key is currently held.
    public mutating func clickWindowExpired(now: TimeInterval) -> Event? {
        guard waitingSecondTap, !down else { return nil }
        waitingSecondTap = false
        lastTapAt = 0
        return .clickToggle
    }
}