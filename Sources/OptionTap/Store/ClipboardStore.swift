import AppKit
import Combine
import CryptoKit
import ImageIO

/// Clipboard history: text, links, code, colours, images and files.
///
/// - Saved to disk (`~/Library/Application Support/OptionTap/`), so it survives restarts.
///   The folder is readable by the owner only: copied text can contain private things.
/// - The rules (dedupe, pin, expiry) live in `ClipHistory`.
/// - `NSPasteboard` has no change notification, so `changeCount` is compared every 0.5 s.
///   It's a single integer read, so polling costs next to nothing.
@MainActor
final class ClipboardStore: ObservableObject {
    /// Newest first (pinned entries too; the panel sorts them to the top).
    @Published private(set) var history = ClipHistory()

    var entries: [ClipboardEntry] { history.entries }

    let folder: URL
    private var imagesFolder: URL { folder.appendingPathComponent("Images", isDirectory: true) }
    private var indexURL: URL { folder.appendingPathComponent("history.json") }

    private var lastChangeCount = NSPasteboard.general.changeCount
    private var pollTimer: Timer?
    private var pruneTimer: Timer?
    private var saveWork: DispatchWorkItem?

    private static let maxImageBytes = 25 * 1024 * 1024

    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OptionTap", isDirectory: true)
    }

    init(folder: URL = ClipboardStore.defaultFolder) {
        self.folder = folder
        for url in [folder, imagesFolder] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }

    /// How long unpinned entries are kept.
    var retention: TimeInterval {
        get { history.retention }
        set {
            history.retention = newValue
            removeFiles(of: history.prune())
            scheduleSave()
        }
    }

    // MARK: Lifecycle

    /// `watch: false` loads the saved history without reading the pasteboard (demo mode).
    func start(watch: Bool = true) {
        guard pollTimer == nil else { return }
        load()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune() }
        }
        guard watch else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        pollTimer?.tolerance = 0.2
    }

    func stop() {
        pollTimer?.invalidate(); pollTimer = nil
        pruneTimer?.invalidate(); pruneTimer = nil
        saveNow()
    }

    // MARK: Actions

    /// Puts an entry back on the pasteboard, in its own type. The order does NOT change:
    /// pasting from the panel doesn't move the entry to the top, otherwise after ⌘8 item 8
    /// would become item 1 and every shortcut number would shift.
    func recopy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch entry.kind {
        case .image:
            if let url = imageURL(entry), let data = try? Data(contentsOf: url) {
                pasteboard.setData(data, forType: .png)
                if let tiff = NSImage(data: data)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
            }
        case .file:
            pasteboard.writeObjects(entry.filePaths.map { URL(fileURLWithPath: $0) as NSURL })
        default:
            pasteboard.setString(entry.text ?? "", forType: .string)
        }
        // Our own write must not come back as a new copy.
        lastChangeCount = pasteboard.changeCount
    }

    /// A screenshot goes on the pasteboard as both an image (for chat apps) and a file (for Finder).
    func copyScreenshot(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let data = try? Data(contentsOf: url) { item.setData(data, forType: .png) }
        item.setString(url.absoluteString, forType: .fileURL)
        pasteboard.writeObjects([item])
        lastChangeCount = pasteboard.changeCount
    }

    func togglePin(_ entry: ClipboardEntry) {
        history.togglePin(entry.id)
        scheduleSave()
    }

    func delete(_ entry: ClipboardEntry) {
        if let removed = history.remove(entry.id) { removeFiles(of: [removed]) }
        scheduleSave()
    }

    /// Clears everything except pinned entries.
    func clearUnpinned() {
        removeFiles(of: history.removeUnpinned())
        scheduleSave()
    }

    func imageURL(_ entry: ClipboardEntry) -> URL? {
        entry.imageFile.map { imagesFolder.appendingPathComponent($0) }
    }

    /// Adds an entry directly (demo content). Images are passed as PNG data.
    func insert(_ entry: ClipboardEntry, png: Data? = nil) {
        var entry = entry
        if let png, let name = entry.imageFile {
            try? png.write(to: imagesFolder.appendingPathComponent(name), options: .atomic)
            entry.imageHash = Self.hash(png)
        }
        removeFiles(of: history.add(entry, now: entry.copiedAt).removed)
        scheduleSave()
    }

    // MARK: Reading the pasteboard

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        // Respect apps that mark their copies as secret or temporary (password managers do).
        let types = Set(pasteboard.types ?? [])
        if types.contains(.init("org.nspasteboard.ConcealedType")) || types.contains(.init("org.nspasteboard.TransientType")) {
            return
        }
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let captured = capture(pasteboard, source: source) else { return }
        let (result, removed) = history.add(captured)
        if case .bumped = result { removeFiles(of: [captured]) }   // the new copy's image isn't needed
        removeFiles(of: removed)
        scheduleSave()
    }

    private func capture(_ pasteboard: NSPasteboard, source: String?) -> ClipboardEntry? {
        // 1) Files (copied in Finder)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return ClipboardEntry(kind: .file, text: urls.map(\.path).joined(separator: "\n"), sourceBundleID: source)
        }
        // 2) Text wins even when other types come with it (Pages, Notes put both).
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ClipboardEntry(kind: ClipboardEntry.classify(text), text: text, sourceBundleID: source)
        }
        // 3) Images
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let data = pasteboard.data(forType: type), data.count <= Self.maxImageBytes,
                  let size = Self.safeImageSize(data),
                  let png = type == .png ? data : Self.pngData(data) else { continue }
            let id = UUID()
            let name = id.uuidString + ".png"
            guard (try? png.write(to: imagesFolder.appendingPathComponent(name), options: .atomic)) != nil else { return nil }
            return ClipboardEntry(id: id, kind: .image, text: nil, imageFile: name, imageSize: size,
                                  imageHash: Self.hash(png), sourceBundleID: source)
        }
        return nil
    }

    /// Images larger than this are not recorded. The byte limit alone isn't enough: a small,
    /// highly compressed PNG/TIFF can decode into a bitmap of many gigabytes.
    nonisolated static let maxImagePixels = 100_000_000

    /// Pixel size read from the image header only (nothing is decoded). Nil when the size is
    /// unknown or over `maxImagePixels`, which means "skip this image".
    nonisolated static func safeImageSize(_ data: Data, maxPixels: Int = maxImagePixels) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
                as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0,
              width.multipliedReportingOverflow(by: height).overflow == false,
              width * height <= maxPixels
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Re-encodes an image (already checked by `safeImageSize`) as PNG through ImageIO.
    nonisolated static func pngData(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Internals

    private func prune() {
        let removed = history.prune()
        guard !removed.isEmpty else { return }
        removeFiles(of: removed)
        scheduleSave()
    }

    private func removeFiles(of entries: [ClipboardEntry]) {
        for entry in entries {
            if let url = imageURL(entry) { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: Saving

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else { return }
        history.entries = saved.filter { entry in
            entry.kind != .image || imageURL(entry).map { FileManager.default.fileExists(atPath: $0.path) } == true
        }
        prune()
    }

    /// Changes are batched for a second, so a burst of copies is one disk write.
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func saveNow() {
        saveWork?.cancel(); saveWork = nil
        guard let data = try? JSONEncoder().encode(history.entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
    }
}
