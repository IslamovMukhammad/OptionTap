import Foundation

/// Detects a clean double tap of one modifier key. Pure logic: time comes in as a number.
///
/// Rules (kept from the original app, tuned by daily use):
/// - each press is shorter than `tapMax`, and the gap between the two presses is shorter than `tapGap`;
/// - the key is pressed **on its own**: any other modifier, the other side's key, a key press,
///   a click or a scroll in between cancels the pair. So ⌥-shortcuts (⌥⌘…, ⌥-letters) never fire it;
/// - a tap that ends while a mouse button is down (a drag) does not count.
///
/// Why ⌥ and not ⌘: holding ⌘ is part of normal work (⌘-clicking several files, ⌘Tab, ⌘C/⌘V).
/// A "hold ⌘ for one second" gesture used to pop the panel up while the user was still deciding
/// where to click, because intent can't be known in advance. A lone double tap of ⌥ almost never
/// happens by accident, so it became the default.
struct DoubleTapDetector: Sendable {
    static let tapMax: TimeInterval = 0.30
    static let tapGap: TimeInterval = 0.35

    /// When the trigger key went down on its own.
    private var pressedAt: TimeInterval?
    /// When the previous clean tap ended.
    private var lastTapEnd: TimeInterval?
    /// Something else was pressed with the key: ignore until every modifier is released.
    private var spoiled = false

    /// Feed every modifier change. Returns `true` when the double tap is complete.
    mutating func flagsChanged(_ state: KeyState, at now: TimeInterval, mouseDown: Bool = false) -> Bool {
        switch state {
        case .released:
            defer { pressedAt = nil; spoiled = false }
            guard let pressed = pressedAt, !spoiled, now - pressed < Self.tapMax, !mouseDown else {
                lastTapEnd = nil
                return false
            }
            if let last = lastTapEnd, now - last < Self.tapGap {
                lastTapEnd = nil
                return true
            }
            lastTapEnd = now
            return false
        case .onlyTrigger:
            if pressedAt == nil, !spoiled {
                pressedAt = now
                // A long pause after the first tap starts a new pair.
                if let last = lastTapEnd, now - last >= Self.tapGap { lastTapEnd = nil }
            }
            return false
        case .other:
            // Another modifier or the other side: this is a shortcut, not a tap.
            spoiled = true
            pressedAt = nil
            lastTapEnd = nil
            return false
        }
    }

    /// A key press, click or scroll happened. `keyHeld`: the trigger modifier is down right now.
    mutating func interrupt(keyHeld: Bool) {
        lastTapEnd = nil
        guard keyHeld else { return }
        spoiled = true
        pressedAt = nil
    }

    mutating func reset() { self = DoubleTapDetector() }
}

/// Detects holding one modifier on its own for `holdDuration`. Pure logic: the caller owns the timer.
struct HoldDetector: Sendable {
    static let holdDuration: TimeInterval = 1.0

    enum Command: Equatable, Sendable {
        case none
        /// Start a timer for `holdDuration`, then call `timerFired`.
        case startTimer
        case cancelTimer
    }

    private var spoiled = false
    private var timerRunning = false

    mutating func flagsChanged(_ state: KeyState, mouseDown: Bool = false) -> Command {
        switch state {
        case .released:
            spoiled = false
            return cancel()
        case .onlyTrigger:
            // While a mouse button is down (dragging a file) the panel never opens.
            guard !spoiled, !timerRunning, !mouseDown else { return .none }
            timerRunning = true
            return .startTimer
        case .other:
            spoiled = true
            return cancel()
        }
    }

    /// The timer ran out. Returns `true` when the panel should open.
    mutating func timerFired(_ state: KeyState, mouseDown: Bool = false) -> Bool {
        guard timerRunning else { return false }
        timerRunning = false
        guard state == .onlyTrigger, !spoiled, !mouseDown else { return false }
        spoiled = true   // one hold, one action
        return true
    }

    /// A key press, click or scroll happened while the key may be held.
    mutating func interrupt(keyHeld: Bool) -> Command {
        guard keyHeld else { return .none }
        spoiled = true
        return cancel()
    }

    private mutating func cancel() -> Command {
        guard timerRunning else { return .none }
        timerRunning = false
        return .cancelTimer
    }
}
