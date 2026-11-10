import AppKit

/// Watches the keyboard globally and calls `onFire` when the chosen gesture happens.
///
/// Only keyboard, click and scroll events are monitored. Monitors for `mouseMoved` /
/// `leftMouseDragged` are deliberately absent: in the original app they broke clicks on
/// status-bar items and cost CPU on every mouse move.
@MainActor
final class KeyTrigger {
    var onFire: (() -> Void)?

    private let key: () -> TriggerKey
    private var monitors: [Any] = []
    private var doubleTap = DoubleTapDetector()
    private var hold = HoldDetector()
    private var holdTimer: DispatchWorkItem?

    init(key: @escaping () -> TriggerKey) { self.key = key }

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let interrupting: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            let flags = e.modifierFlags
            MainActor.assumeIsolated { self?.flagsChanged(flags) }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: interrupting, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.interrupt() }
        }) { monitors.append(m) }
        // Global monitors don't see events while one of our own windows is key.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            let flags = e.modifierFlags
            MainActor.assumeIsolated { self?.flagsChanged(flags) }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: interrupting, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.interrupt() }
            return e
        }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        cancelTimer()
        doubleTap.reset()
        hold = HoldDetector()
    }

    private var mouseDown: Bool { NSEvent.pressedMouseButtons != 0 }

    private func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        let key = key()
        let state = key.state(of: flags)
        if key.isDoubleTap {
            if doubleTap.flagsChanged(state, at: ProcessInfo.processInfo.systemUptime, mouseDown: mouseDown) {
                onFire?()
            }
        } else {
            run(hold.flagsChanged(state, mouseDown: mouseDown))
        }
    }

    private func interrupt() {
        let key = key()
        let held = NSEvent.modifierFlags.contains(key.flag)
        if key.isDoubleTap {
            doubleTap.interrupt(keyHeld: held)
        } else {
            run(hold.interrupt(keyHeld: held))
        }
    }

    private func run(_ command: HoldDetector.Command) {
        switch command {
        case .none: break
        case .cancelTimer: cancelTimer()
        case .startTimer:
            cancelTimer()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.holdTimer = nil
                let state = self.key().state(of: NSEvent.modifierFlags)
                if self.hold.timerFired(state, mouseDown: self.mouseDown) { self.onFire?() }
            }
            holdTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + HoldDetector.holdDuration, execute: work)
        }
    }

    private func cancelTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }
}
