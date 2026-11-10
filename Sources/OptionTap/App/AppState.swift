import AppKit
import ApplicationServices
import Observation
import ServiceManagement

/// How long unpinned clipboard entries are kept.
enum HistoryLength: Int, CaseIterable, Identifiable, Codable {
    case hour = 3600
    case day = 86_400
    case week = 604_800
    case month = 2_592_000
    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .hour: "1 hour"
        case .day: "24 hours"
        case .week: "7 days"
        case .month: "30 days"
        }
    }
}

/// App-wide state: settings, permission, the stores and the panel.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var enabled: Bool { didSet { save(enabled, "enabled"); updateTrigger() } }
    var triggerKey: TriggerKey { didSet { save(triggerKey.rawValue, "triggerKey") } }
    var historyLength: HistoryLength {
        didSet {
            save(historyLength.rawValue, "historyLength")
            clipboard.retention = historyLength.seconds
        }
    }

    private(set) var isTrusted = AXIsProcessTrusted()
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginError: String?

    @ObservationIgnored let clipboard: ClipboardStore
    @ObservationIgnored let screenshots: ScreenshotStore
    @ObservationIgnored let panel: QuickPanelController
    @ObservationIgnored private var trigger: KeyTrigger!
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private let defaults = UserDefaults.standard

    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    private init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: "enabled") as? Bool ?? true
        triggerKey = d.string(forKey: "triggerKey").flatMap(TriggerKey.init(rawValue:)) ?? .doubleLeftOption
        historyLength = HistoryLength(rawValue: d.integer(forKey: "historyLength")) ?? .day

        if Demo.isOn {
            clipboard = ClipboardStore(folder: Demo.clipboardFolder)
            screenshots = ScreenshotStore(folder: Demo.screenshotFolder)
        } else {
            clipboard = ClipboardStore()
            screenshots = ScreenshotStore()
        }
        panel = QuickPanelController(screenshots: screenshots, clipboard: clipboard)
        trigger = KeyTrigger { [unowned self] in self.triggerKey }
        trigger.onFire = { [weak self] in self?.panel.toggle() }

        guard !Self.isRunningTests else { return }
        clipboard.retention = historyLength.seconds
        if Demo.isOn { Demo.seed(clipboard) }
        clipboard.start(watch: !Demo.isOn)
        updateTrigger()
        if !isTrusted { startPolling() }
    }

    func shutdown() {
        trigger.stop()
        clipboard.stop()
    }

    func clearHistory() { clipboard.clearUnpinned() }

    private func updateTrigger() {
        if enabled { trigger.start() } else { trigger.stop() }
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    // MARK: Accessibility permission
    // Needed for the global key monitor (to see the ⌥ taps) and to send ⌘V into the app you were in.

    func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    /// Polls only while permission is missing; stops for good once it's granted.
    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let state = AppState.shared
                guard AXIsProcessTrusted() else { return }
                state.isTrusted = true
                state.pollTimer?.invalidate()
                state.pollTimer = nil
                // Monitors added before the permission was granted never receive events: re-add them.
                state.trigger.stop()
                state.updateTrigger()
            }
        }
    }

    // MARK: Launch at login

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
