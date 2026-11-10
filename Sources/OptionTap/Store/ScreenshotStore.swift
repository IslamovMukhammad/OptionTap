import AppKit
import Combine

struct ScreenshotItem: Identifiable, Equatable, Sendable {
    let id: String       // file name
    let url: URL
    let createdAt: Date
}

/// Screenshots from the last 24 hours, read from the folder macOS saves them to.
///
/// The app never moves or deletes files on its own. A file goes to the Trash only when the
/// user presses ⌘⌫ / Delete on it (and can be put back from the Trash).
@MainActor
final class ScreenshotStore: ObservableObject {
    /// Newest first.
    @Published private(set) var items: [ScreenshotItem] = []

    static let window: TimeInterval = 24 * 60 * 60
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]

    /// A fixed folder (demo mode); otherwise the system screenshot location.
    private let fixedFolder: URL?

    init(folder: URL? = nil) { fixedFolder = folder }

    /// Where macOS saves screenshots: the `location` set in the Screenshot app, or the Desktop.
    var folder: URL {
        if let fixedFolder { return fixedFolder }
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return url }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// Re-reads the folder. Called every time the panel opens.
    func refresh(now: Date = Date()) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        items = contents.compactMap { url -> ScreenshotItem? in
            guard Self.imageExtensions.contains(url.pathExtension.lowercased()),
                  let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  now.timeIntervalSince(created) < Self.window,
                  Self.isScreenshot(url)
            else { return nil }
            return ScreenshotItem(id: url.lastPathComponent, url: url, createdAt: created)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// The user asked to delete it: move to the Trash (recoverable).
    func trash(_ item: ScreenshotItem) {
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        refresh()
    }

    /// macOS tags its screenshots with `kMDItemIsScreenCapture`, whatever the system language.
    /// The English "Screenshot" file-name prefix is a fallback for files that lost the tag.
    nonisolated static func isScreenshot(_ url: URL) -> Bool {
        if url.lastPathComponent.hasPrefix("Screenshot") { return true }
        let name = "com.apple.metadata:kMDItemIsScreenCapture"
        return getxattr(url.path, name, nil, 0, 0, 0) > 0
    }
}
