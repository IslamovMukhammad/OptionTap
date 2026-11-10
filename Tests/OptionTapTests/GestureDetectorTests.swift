import AppKit
import Testing
@testable import OptionTap

struct DoubleTapDetectorTests {
    /// Press-release-press-release with the given timings; returns whether it fired.
    private func tapTwice(hold: Double = 0.08, gap: Double = 0.15) -> Bool {
        var d = DoubleTapDetector()
        var t = 10.0
        _ = d.flagsChanged(.onlyTrigger, at: t); t += hold
        _ = d.flagsChanged(.released, at: t); t += gap
        _ = d.flagsChanged(.onlyTrigger, at: t); t += hold
        return d.flagsChanged(.released, at: t)
    }

    @Test func quickDoubleTapFires() { #expect(tapTwice()) }

    @Test func singleTapDoesNotFire() {
        var d = DoubleTapDetector()
        _ = d.flagsChanged(.onlyTrigger, at: 0)
        do { let r = d.flagsChanged(.released, at: 0.1); #expect(!r) }
    }

    @Test func longPressDoesNotCount() { #expect(!tapTwice(hold: 0.4)) }

    @Test func slowSecondTapDoesNotFire() { #expect(!tapTwice(gap: 0.5)) }

    @Test func slowPairThenQuickPairFires() {
        var d = DoubleTapDetector()
        _ = d.flagsChanged(.onlyTrigger, at: 0); _ = d.flagsChanged(.released, at: 0.1)
        // Second tap too late: becomes the first tap of a new pair.
        _ = d.flagsChanged(.onlyTrigger, at: 1.0); _ = d.flagsChanged(.released, at: 1.1)
        _ = d.flagsChanged(.onlyTrigger, at: 1.25)
        do { let r = d.flagsChanged(.released, at: 1.3); #expect(r) }
    }

    @Test func otherModifierCancels() {
        var d = DoubleTapDetector()
        _ = d.flagsChanged(.onlyTrigger, at: 0); _ = d.flagsChanged(.released, at: 0.1)
        _ = d.flagsChanged(.onlyTrigger, at: 0.2)
        _ = d.flagsChanged(.other, at: 0.22)          // ⌥⌘ pressed: a shortcut
        do { let r = d.flagsChanged(.released, at: 0.25); #expect(!r) }
    }

    @Test func keyPressBetweenTapsCancels() {
        var d = DoubleTapDetector()
        _ = d.flagsChanged(.onlyTrigger, at: 0); _ = d.flagsChanged(.released, at: 0.1)
        d.interrupt(keyHeld: false)                   // typed a letter between taps
        _ = d.flagsChanged(.onlyTrigger, at: 0.2)
        do { let r = d.flagsChanged(.released, at: 0.25); #expect(!r) }
    }

    @Test func keyPressWhileHeldCancels() {
        var d = DoubleTapDetector()
        _ = d.flagsChanged(.onlyTrigger, at: 0); _ = d.flagsChanged(.released, at: 0.1)
        _ = d.flagsChanged(.onlyTrigger, at: 0.2)
        d.interrupt(keyHeld: true)                    // ⌥-letter (typing a special character)
        do { let r = d.flagsChanged(.released, at: 0.25); #expect(!r) }
    }

    @Test func dragDoesNotCount() {
        var d = DoubleTapDetector()
        _ = d.flagsChanged(.onlyTrigger, at: 0); _ = d.flagsChanged(.released, at: 0.1)
        _ = d.flagsChanged(.onlyTrigger, at: 0.2)
        do { let r = d.flagsChanged(.released, at: 0.25, mouseDown: true); #expect(!r) }
    }

    @Test func tripleTapFiresOnce() {
        var d = DoubleTapDetector()
        var fired = 0
        for i in 0..<3 {
            let t = Double(i) * 0.2
            _ = d.flagsChanged(.onlyTrigger, at: t)
            if d.flagsChanged(.released, at: t + 0.08) { fired += 1 }
        }
        #expect(fired == 1)
    }
}

struct HoldDetectorTests {
    @Test func holdFiresOnce() {
        var d = HoldDetector()
        do { let r = d.flagsChanged(.onlyTrigger); #expect(r == .startTimer) }
        do { let r = d.timerFired(.onlyTrigger); #expect(r) }
        // Still held, timer would not restart: one hold, one action.
        do { let r = d.flagsChanged(.onlyTrigger); #expect(r == .none) }
        do { let r = d.flagsChanged(.released); #expect(r == .none) }
        do { let r = d.flagsChanged(.onlyTrigger); #expect(r == .startTimer) }
    }

    @Test func releaseBeforeTimerCancels() {
        var d = HoldDetector()
        _ = d.flagsChanged(.onlyTrigger)
        do { let r = d.flagsChanged(.released); #expect(r == .cancelTimer) }
        do { let r = d.timerFired(.released); #expect(!r) }
    }

    @Test func comboCancels() {
        var d = HoldDetector()
        _ = d.flagsChanged(.onlyTrigger)
        do { let r = d.flagsChanged(.other); #expect(r == .cancelTimer) }
        do { let r = d.timerFired(.onlyTrigger); #expect(!r) }
    }

    @Test func keyPressWhileHeldCancels() {
        var d = HoldDetector()
        _ = d.flagsChanged(.onlyTrigger)
        do { let r = d.interrupt(keyHeld: true); #expect(r == .cancelTimer) }
        do { let r = d.timerFired(.onlyTrigger); #expect(!r) }
    }

    @Test func neverStartsWhileDragging() {
        var d = HoldDetector()
        do { let r = d.flagsChanged(.onlyTrigger, mouseDown: true); #expect(r == .none) }
    }
}

struct TriggerKeyTests {
    private let option = NSEvent.ModifierFlags.option.rawValue

    @Test func leftOptionAlone() {
        let flags = NSEvent.ModifierFlags(rawValue: option | 0x20)
        #expect(TriggerKey.doubleLeftOption.state(of: flags) == .onlyTrigger)
        #expect(TriggerKey.doubleRightOption.state(of: flags) == .other)
    }

    @Test func bothOptionsIsNotATap() {
        let flags = NSEvent.ModifierFlags(rawValue: option | 0x20 | 0x40)
        #expect(TriggerKey.doubleLeftOption.state(of: flags) == .other)
    }

    @Test func optionWithCommandIsOther() {
        let flags = NSEvent.ModifierFlags(rawValue: option | NSEvent.ModifierFlags.command.rawValue | 0x20 | 0x08)
        #expect(TriggerKey.doubleLeftOption.state(of: flags) == .other)
    }

    @Test func capsLockIsIgnored() {
        let flags = NSEvent.ModifierFlags(rawValue: option | NSEvent.ModifierFlags.capsLock.rawValue | 0x40)
        #expect(TriggerKey.holdRightOption.state(of: flags) == .onlyTrigger)
        #expect(TriggerKey.doubleLeftOption.state(of: NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.capsLock.rawValue)) == .released)
    }
}
