import Foundation

/// Right Option: short double-tap toggles sticky listen; press-and-hold starts,
/// release ends. Pure state machine so the timing rules can be unit-tested.
public struct RightOptionGesture: Sendable {
    public enum Event: Sendable, Equatable {
        case holdStart
        case holdEnd
        case stickyToggle
    }

    public var longPress: TimeInterval
    public var doubleClick: TimeInterval

    private var down = false
    private var holding = false
    private var downAt: TimeInterval = 0
    private var lastTapAt: TimeInterval = 0

    public init(longPress: TimeInterval = 0.28, doubleClick: TimeInterval = 0.38) {
        self.longPress = longPress
        self.doubleClick = doubleClick
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
            return .holdEnd
        }
        if lastTapAt > 0, now - lastTapAt <= doubleClick {
            lastTapAt = 0
            return .stickyToggle
        }
        lastTapAt = now
        return nil
    }

    /// Call when the long-press timer fires.
    public mutating func longPressFired(now: TimeInterval) -> Event? {
        guard down, !holding else { return nil }
        guard now - downAt >= longPress - 0.001 else { return nil }
        holding = true
        lastTapAt = 0
        return .holdStart
    }
}
