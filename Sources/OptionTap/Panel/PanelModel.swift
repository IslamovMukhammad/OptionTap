import AppKit
import Combine

/// One row in the panel: a clipboard entry or a screenshot.
enum PanelItem: Identifiable, Equatable {
    case clip(ClipboardEntry)
    case shot(ScreenshotItem)

    var id: String {
        switch self {
        case .clip(let e): "c-" + e.id.uuidString
        case .shot(let s): "s-" + s.id
        }
    }

    var date: Date {
        switch self {
        case .clip(let e): e.copiedAt
        case .shot(let s): s.createdAt
        }
    }

    var pinned: Bool { if case .clip(let e) = self { e.pinned } else { false } }

    /// Pinned first, then newest first.
    static func ordered(_ items: [PanelItem]) -> [PanelItem] {
        items.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.date > b.date
        }
    }
}

enum PanelFilter: Int, CaseIterable, Identifiable {
    case all, clipboard, screenshots, pinned
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .clipboard: "Clipboard"
        case .screenshots: "Screenshots"
        case .pinned: "Pinned"
        }
    }
}

@MainActor
final class PanelModel: ObservableObject {
    @Published var query = ""
    @Published var filter: PanelFilter = .all
    @Published var selectedID: String?
    /// Bumped on every show, to put focus back in the search field.
    @Published var focusToken = 0
    @Published var shown = false

    let clipboard: ClipboardStore
    let screenshots: ScreenshotStore
    private var bag: Set<AnyCancellable> = []

    init(clipboard: ClipboardStore, screenshots: ScreenshotStore) {
        self.clipboard = clipboard
        self.screenshots = screenshots
        clipboard.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        screenshots.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
    }

    /// What the list shows, in order: filtered, searched, pinned first, then newest first.
    var items: [PanelItem] {
        var all: [PanelItem] = []
        if filter != .screenshots { all += clipboard.entries.map(PanelItem.clip) }
        if filter == .all || filter == .screenshots { all += screenshots.items.map(PanelItem.shot) }
        if filter == .pinned { all = all.filter(\.pinned) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { all = all.filter { Self.matches($0, q) } }
        return PanelItem.ordered(all)
    }

    var selected: PanelItem? {
        let list = items
        return list.first { $0.id == selectedID } ?? list.first
    }

    func resetForShow() {
        query = ""
        filter = .all
        selectedID = items.first?.id
        focusToken += 1
    }

    func move(_ delta: Int) {
        let list = items
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = list[min(max(0, current + delta), list.count - 1)].id
    }

    func cycleFilter(_ delta: Int) {
        let all = PanelFilter.allCases
        filter = all[(filter.rawValue + delta + all.count) % all.count]
        selectedID = items.first?.id
    }

    private static func matches(_ item: PanelItem, _ q: String) -> Bool {
        switch item {
        case .clip(let e):
            if (e.text ?? "").lowercased().contains(q) || e.kind.title.lowercased().contains(q) { return true }
            return SourceApps.name(e.sourceBundleID)?.lowercased().contains(q) ?? false
        case .shot(let s):
            return "screenshot".contains(q) || s.id.lowercased().contains(q)
        }
    }
}

/// Icons and names of the apps things were copied from (cached).
@MainActor
enum SourceApps {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    static func icon(_ bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = image
        return image
    }

    static func name(_ bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        if let cached = names[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        names[bundleID] = name
        return name
    }
}
