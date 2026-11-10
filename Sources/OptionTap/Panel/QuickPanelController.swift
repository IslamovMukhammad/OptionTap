import AppKit
import SwiftUI

/// A panel that takes the keyboard (Esc, arrows, typing) without activating the app,
/// so the app you were in stays frontmost and ⌘V lands there.
final class KeyPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Opens, closes and positions the panel, handles its keyboard and runs its actions.
/// Closes on Esc, on a click outside, or on the trigger gesture again.
@MainActor
final class QuickPanelController {
    private let screenshots: ScreenshotStore
    private let clipboard: ClipboardStore
    private var panel: KeyPanel?
    private(set) lazy var model = PanelModel(clipboard: clipboard, screenshots: screenshots)
    private var outsideClick: Any?
    private var hideWork: DispatchWorkItem?
    private lazy var preview = ScreenshotPreviewController(store: screenshots)

    /// The window is this much larger than the glass panel on every side, so the shadow isn't clipped.
    static let shadowRoom: CGFloat = 40

    init(screenshots: ScreenshotStore, clipboard: ClipboardStore) {
        self.screenshots = screenshots
        self.clipboard = clipboard
        DragOut.onBegan = { [weak self] in self?.beginDragOut() }
    }

    var isShown: Bool { model.shown }

    func toggle() { model.shown ? hide(animated: true) : show() }

    func show() {
        hideWork?.cancel()
        panel?.ignoresMouseEvents = false
        screenshots.refresh()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // On the screen with the mouse, like Spotlight: centred, about 18% from the top.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let room = Self.shadowRoom
            let size = QP.size
            let top = visible.maxY - max(40, visible.height * 0.18)
            panel.setFrame(NSRect(x: visible.midX - size.width / 2 - room, y: max(visible.minY, top - size.height) - room,
                                  width: size.width + room * 2, height: size.height + room * 2),
                           display: false)
        }
        model.resetForShow()
        panel.makeKeyAndOrderFront(nil)
        model.shown = true
        watchOutsideClicks()
    }

    func hide(animated: Bool) {
        preview.close()
        guard model.shown || panel?.isVisible == true else { return }
        model.shown = false
        stopWatchingOutsideClicks()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        hideWork = work
        // Hide the window once the SwiftUI exit animation (140 ms) is done.
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.16 : 0), execute: work)
    }

    /// Opens the full-screen preview of a screenshot (also used by demo mode).
    func openPreview(_ shot: ScreenshotItem) { preview.open(shot) }

    /// The panel window (demo mode uses it for screenshots of the app).
    var window: NSWindow? { panel }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: QP.size),
                             styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The system shadow follows the window rectangle (lines at the corners). SwiftUI draws
        // one that follows the glass shape instead.
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        let actions = PanelActions(
            paste: { [weak self] item, copyOnly in self?.paste(item, copyOnly: copyOnly) },
            preview: { [weak self] shot in self?.preview.open(shot) },
            delete: { [weak self] item in self?.delete(item) },
            togglePin: { [weak self] item in self?.togglePin(item) },
            reveal: { [weak self] item in self?.reveal(item) })
        panel.contentView = NSHostingView(rootView: QuickPanelView(model: model, actions: actions))
        return panel
    }

    // MARK: Keyboard

    /// Runs before the search field sees the key: control keys are handled here, the rest is typed.
    private func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let cmd = mods == .command
        switch event.keyCode {
        case 53:                                                     // Esc: clear the search first
            if model.query.isEmpty { hide(animated: true) } else { model.query = "" }
            return true
        case 125: model.move(1); return true                         // ↓
        case 126: model.move(-1); return true                        // ↑
        case 36, 76:                                                 // ⏎ paste, ⌘⏎ copy only
            if let item = model.selected { paste(item, copyOnly: cmd) }
            return true
        case 48: model.cycleFilter(mods == .shift ? -1 : 1); return true   // Tab / ⇧Tab
        case 51 where cmd:                                           // ⌘⌫
            if let item = model.selected { delete(item) }
            return true
        case 35 where cmd:                                           // ⌘P
            if let item = model.selected { togglePin(item) }
            return true
        case 49 where model.query.isEmpty:                           // Space (empty search): big preview
            if case .shot(let shot) = model.selected { preview.open(shot); return true }
            return false
        default:
            // ⌘1…⌘9 paste that item right away
            if cmd, let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(digit) {
                let list = model.items
                if list.indices.contains(digit - 1) { paste(list[digit - 1], copyOnly: false) }
                return true
            }
            return false
        }
    }

    // MARK: Actions

    /// Puts the item on the pasteboard, closes the panel and sends ⌘V to the app you were in
    /// (the panel never activated our app, so that app is still frontmost).
    private func paste(_ item: PanelItem, copyOnly: Bool) {
        switch item {
        case .clip(let entry): clipboard.recopy(entry)
        case .shot(let shot): clipboard.copyScreenshot(shot.url)
        }
        // When pasting, close at once without animation: during the 0.16 s exit animation the panel
        // would still hold the keyboard and ⌘V would land in its own search field.
        hide(animated: copyOnly)
        guard !copyOnly, AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            let source = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)   // V
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    private func delete(_ item: PanelItem) {
        let list = model.items
        let index = list.firstIndex(of: item) ?? 0
        switch item {
        case .clip(let entry): clipboard.delete(entry)
        case .shot(let shot): screenshots.trash(shot)
        }
        // Selection moves to the next item.
        let rest = model.items
        model.selectedID = rest.isEmpty ? nil : rest[min(index, rest.count - 1)].id
    }

    private func togglePin(_ item: PanelItem) {
        if case .clip(let entry) = item { clipboard.togglePin(entry) }
    }

    private func reveal(_ item: PanelItem) {
        switch item {
        case .shot(let shot): NSWorkspace.shared.activateFileViewerSelecting([shot.url])
        case .clip(let entry): NSWorkspace.shared.activateFileViewerSelecting(entry.filePaths.map { URL(fileURLWithPath: $0) })
        }
        hide(animated: true)
    }

    /// A click in another app closes the panel. Clicks in our own windows never reach a global
    /// monitor, so clicking inside the preview doesn't close it.
    private func watchOutsideClicks() {
        guard outsideClick == nil else { return }
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(animated: true) }
        }
    }

    private func stopWatchingOutsideClicks() {
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
    }

    // MARK: Dragging a screenshot out

    /// A screenshot drag started: the panel and preview turn invisible at once and let clicks
    /// through (so the window under the drop point gets the drop), then close fully when the
    /// mouse is released. Windows are not ordered out during the drag: that can end the drag session.
    private var dragEndMonitors: [Any] = []

    private func beginDragOut() {
        guard dragEndMonitors.isEmpty else { return }
        preview.fadeForDrag()
        model.shown = false
        stopWatchingOutsideClicks()
        panel?.ignoresMouseEvents = true
        let finish: () -> Void = { [weak self] in self?.finishDragOut() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { _ in
            MainActor.assumeIsolated { finish() }
        }) { dragEndMonitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { e in
            MainActor.assumeIsolated { finish() }
            return e
        }) { dragEndMonitors.append(m) }
    }

    private func finishDragOut() {
        dragEndMonitors.forEach(NSEvent.removeMonitor)
        dragEndMonitors.removeAll()
        // Give the drop a moment to finish, then close the windows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.preview.close()
            self.panel?.orderOut(nil)
            self.panel?.ignoresMouseEvents = false
        }
    }
}

/// Tells the controller from inside SwiftUI views that a drag started.
@MainActor
enum DragOut {
    static var onBegan: (() -> Void)?
    nonisolated static func began() {
        // `onDrag` runs while the drag is starting; change state on the next run-loop turn.
        DispatchQueue.main.async { MainActor.assumeIsolated { onBegan?() } }
    }
}

/// Small images, made in the background with ImageIO (doesn't decode the whole file).
enum Thumbnail {
    static func load(_ url: URL, maxPixel: Int) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
    }
}
