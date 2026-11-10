import AppKit
import SwiftUI

/// Demo mode for README screenshots: made-up clipboard items and generated "screenshots" in a
/// temporary folder. It never reads your pasteboard or your screenshot folder.
///
///     OPTIONTAP_DEMO=panel    build/OptionTap.app/Contents/MacOS/OptionTap   # panel with clipboard items
///     OPTIONTAP_DEMO=shot     …                                               # a screenshot selected
///     OPTIONTAP_DEMO=preview  …                                               # full-screen screenshot preview
///     OPTIONTAP_DEMO=settings …                                               # settings window
///     OPTIONTAP_DEMO=trigger  …                                               # nothing opens: try the gesture
@MainActor
enum Demo {
    static let mode = ProcessInfo.processInfo.environment["OPTIONTAP_DEMO"]
    static var isOn: Bool { mode != nil }

    private static let root = FileManager.default.temporaryDirectory.appendingPathComponent("OptionTapDemo", isDirectory: true)
    static let clipboardFolder = root.appendingPathComponent("Clipboard", isDirectory: true)
    static let screenshotFolder = root.appendingPathComponent("Screenshots", isDirectory: true)

    /// Fills a fresh demo folder with sample content.
    static func seed(_ clipboard: ClipboardStore) {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: clipboardFolder.appendingPathComponent("Images"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: screenshotFolder, withIntermediateDirectories: true)

        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        let samples: [ClipboardEntry] = [
            ClipboardEntry(kind: .color, text: "#2B4CFF", sourceBundleID: "com.apple.Preview", copiedAt: ago(300), pinned: true),
            ClipboardEntry(kind: .text, text: "Thanks! I'll send the files tonight.", sourceBundleID: "com.apple.Notes", copiedAt: ago(500), pinned: true),
            ClipboardEntry(kind: .code, text: "swift build -c release", sourceBundleID: "com.apple.Terminal", copiedAt: ago(95)),
            ClipboardEntry(kind: .text, text: "Release checklist:\n• Write the README\n• Record a 30-second demo\n• Tag v1.0 and publish", sourceBundleID: "com.apple.Notes", copiedAt: ago(41)),
            ClipboardEntry(kind: .code, text: """
                func toggle() {
                    model.shown ? hide(animated: true) : show()
                }
                """, sourceBundleID: "com.apple.dt.Xcode", copiedAt: ago(18)),
            ClipboardEntry(kind: .link, text: "https://www.swift.org/documentation/", sourceBundleID: "com.apple.Safari", copiedAt: ago(7)),
        ]
        for entry in samples { clipboard.insert(entry) }

        let imageID = UUID()
        clipboard.insert(ClipboardEntry(id: imageID, kind: .image, text: nil, imageFile: imageID.uuidString + ".png",
                                        imageSize: CGSize(width: 1200, height: 800), sourceBundleID: "com.apple.Preview",
                                        copiedAt: ago(26)),
                         png: art(size: CGSize(width: 1200, height: 800), variant: 2))

        writeShot("Screenshot 2026-11-10 at 10.41.07.png", minutesAgo: 3, variant: 0)
        writeShot("Screenshot 2026-11-10 at 09.12.55.png", minutesAgo: 62, variant: 1)
        clipboard.saveNow()
    }

    private static func writeShot(_ name: String, minutesAgo: Double, variant: Int) {
        let url = screenshotFolder.appendingPathComponent(name)
        guard let png = art(size: CGSize(width: 1600, height: 1000), variant: variant) else { return }
        try? png.write(to: url)
        try? FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-minutesAgo * 60)], ofItemAtPath: url.path)
    }

    /// Opens what the mode asks for, over a plain backdrop that hides whatever is on screen.
    static func run(_ state: AppState) {
        if mode != "settings" { showBackdrop() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            switch mode {
            case "settings":
                SettingsWindow.shared.show()
            case "trigger":
                break   // demo content only; open the panel yourself with the gesture
            case "shot", "preview":
                state.panel.show()
                let model = state.panel.model
                if let shot = state.screenshots.items.first {
                    model.selectedID = PanelItem.shot(shot).id
                    if mode == "preview" { state.panel.openPreview(shot) }
                }
            default:
                state.panel.show()
                // Select the code snippet so the preview shows something interesting.
                model(state).selectedID = model(state).items.first { if case .clip(let e) = $0 { e.kind == .code && e.text?.contains("func") == true } else { false } }?.id
            }
        }
    }

    private static func model(_ state: AppState) -> PanelModel { state.panel.model }

    private static var backdrop: NSWindow?

    private static func showBackdrop() {
        // The panel opens on the screen with the mouse; cover that one.
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Wallpaper())
        window.orderFrontRegardless()
        backdrop = window
    }

    private struct Wallpaper: View {
        var body: some View {
            LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.52), Color(red: 0.45, green: 0.30, blue: 0.62),
                                    Color(red: 0.93, green: 0.55, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
    }

    /// A made-up app window (sidebar, cards, a chart) drawn in code, so no real screen is ever shown.
    static func art(size: CGSize, variant: Int) -> Data? {
        let image = NSImage(size: size, flipped: true) { rect in
            let palettes: [[NSColor]] = [
                [NSColor(red: 0.91, green: 0.93, blue: 0.95, alpha: 1), NSColor(red: 0.17, green: 0.30, blue: 1, alpha: 1), NSColor(red: 1, green: 0.85, blue: 0.30, alpha: 1)],
                [NSColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1), NSColor(red: 0.13, green: 0.70, blue: 0.37, alpha: 1), NSColor(red: 0.17, green: 0.30, blue: 1, alpha: 1)],
                [NSColor(red: 0.99, green: 0.95, blue: 0.88, alpha: 1), NSColor(red: 0.95, green: 0.45, blue: 0.30, alpha: 1), NSColor(red: 0.17, green: 0.30, blue: 1, alpha: 1)],
            ]
            let p = palettes[variant % palettes.count]
            let dark = variant == 1
            let card = dark ? NSColor(white: 0.19, alpha: 1) : .white
            let line = dark ? NSColor(white: 0.32, alpha: 1) : NSColor(white: 0.86, alpha: 1)
            p[0].setFill(); rect.fill()
            let s = rect.width / 1600

            func box(_ r: NSRect, _ color: NSColor, radius: CGFloat = 18) {
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s),
                             xRadius: radius * s, yRadius: radius * s).fill()
            }
            // Sidebar
            box(NSRect(x: 40, y: 40, width: 300, height: 920), card)
            for i in 0..<7 { box(NSRect(x: 72, y: 90 + CGFloat(i) * 64, width: i == 1 ? 236 : 190, height: 28), i == 1 ? p[1] : line, radius: 10) }
            // Header
            box(NSRect(x: 380, y: 40, width: 1180, height: 110), card)
            box(NSRect(x: 420, y: 78, width: 420, height: 34), line, radius: 10)
            box(NSRect(x: 1380, y: 70, width: 140, height: 50), p[1], radius: 25)
            // Stat cards
            for i in 0..<3 {
                let x = 380 + CGFloat(i) * 400
                box(NSRect(x: x, y: 190, width: 380, height: 200), card)
                box(NSRect(x: x + 32, y: 230, width: 140, height: 22), line, radius: 8)
                box(NSRect(x: x + 32, y: 280, width: 220, height: 64), i == 0 ? p[1] : (i == 1 ? p[2] : line), radius: 12)
            }
            // Chart
            box(NSRect(x: 380, y: 430, width: 1180, height: 530), card)
            let heights: [CGFloat] = [180, 260, 210, 330, 290, 380, 340, 420, 300, 360, 440, 400]
            for (i, h) in heights.enumerated() {
                box(NSRect(x: 440 + CGFloat(i) * 92, y: 900 - h, width: 56, height: h), i % 4 == 3 ? p[2] : p[1], radius: 10)
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
