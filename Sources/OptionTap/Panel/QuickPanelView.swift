import AppKit
import SwiftUI

// The Spotlight-style panel: search on top, clipboard and screenshots in one list on the left
// (pinned first, then by time), a large preview on the right, keyboard hints at the bottom.
// Keyboard first: ↑↓ select, ⏎ paste, ⌘1–9, ⌘P, ⌘⌫, Tab, Esc.
//
// Motion: only the panel's entrance (200 ms strong ease-out). Selection and the list are not
// animated: keyboard actions used hundreds of times a day must respond instantly.

// MARK: - Sizes and colours

enum QP {
    static let size = CGSize(width: 780, height: 480)
    static let radius: CGFloat = 26
    static let listWidth: CGFloat = 330
    static let rowHeight: CGFloat = 46
    static let easeOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
    static let exit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
    static let red = Color(red: 1, green: 0.271, blue: 0.227)          // #ff453a
    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.40)
    static let hairline = Color.white.opacity(0.09)
    static let selection = Color.white.opacity(0.13)

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    /// Compact age for the list: "now", "4m", "2h", "Yesterday".
    static func age(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        if Calendar.current.isDateInToday(date) { return "\(s / 3600)h" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Full time for the preview: "Today at 18:54".
    static func when(_ date: Date) -> String {
        let day: String
        if Calendar.current.isDateInToday(date) { day = "Today" }
        else if Calendar.current.isDateInYesterday(date) { day = "Yesterday" }
        else { day = date.formatted(.dateTime.day().month(.wide)) }
        return "\(day) at \(time.string(from: date))"
    }
}

/// Panel actions live in the controller (closing the window, sending ⌘V).
struct PanelActions {
    let paste: (PanelItem, _ copyOnly: Bool) -> Void
    let preview: (ScreenshotItem) -> Void
    let delete: (PanelItem) -> Void
    let togglePin: (PanelItem) -> Void
    let reveal: (PanelItem) -> Void
}

// MARK: - Panel

struct QuickPanelView: View {
    @ObservedObject var model: PanelModel
    let actions: PanelActions
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let items = model.items
        let selected = model.selected
        VStack(spacing: 0) {
            searchBar
            Rectangle().fill(QP.hairline).frame(height: 1)
            HStack(spacing: 0) {
                ItemList(items: items, selectedID: selected?.id, model: model, actions: actions)
                    .frame(width: QP.listWidth)
                Rectangle().fill(QP.hairline).frame(width: 1)
                DetailPane(item: selected, model: model, actions: actions)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(QP.hairline).frame(height: 1)
            Footer(item: selected, count: items.count)
        }
        .frame(width: QP.size.width, height: QP.size.height)
        .background(RoundedRectangle(cornerRadius: QP.radius, style: .continuous).fill(Color(white: 0.09).opacity(0.72)))
        // A dark layer under the Liquid Glass, so text in windows behind doesn't hurt readability.
        .glassEffect(.regular.tint(.black.opacity(0.25)), in: .rect(cornerRadius: QP.radius))
        .overlay(RoundedRectangle(cornerRadius: QP.radius, style: .continuous)
            .strokeBorder(.white.opacity(0.11), lineWidth: 1))
        // The shadow follows the rounded shape; the window itself has no system shadow
        // (that one is drawn around the whole rectangle and shows lines at the corners).
        .background(RoundedRectangle(cornerRadius: QP.radius, style: .continuous)
            .fill(.black.opacity(0.001))
            .shadow(color: .black.opacity(0.42), radius: 26, y: 14))
        .padding(QuickPanelController.shadowRoom)
        .environment(\.colorScheme, .dark)
        // Entrance: scale 0.97 → 1 from the top, 200 ms strong ease-out; exit 140 ms.
        .opacity(model.shown ? 1 : 0)
        .scaleEffect(model.shown || reduceMotion ? 1 : 0.97, anchor: .top)
        .animation(model.shown ? QP.easeOut : QP.exit, value: model.shown)
        .onChange(of: model.focusToken) { searchFocused = true }
        .onAppear { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(QP.secondary)
            TextField("Search clipboard and screenshots", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(QP.primary)
                .focused($searchFocused)
                .onChange(of: model.query) { model.selectedID = model.items.first?.id }
            FilterTabs(model: model)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }
}

// MARK: - Filters

private struct FilterTabs: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelFilter.allCases) { filter in
                let on = model.filter == filter
                Button {
                    model.filter = filter
                    model.selectedID = model.items.first?.id
                } label: {
                    Text(filter.title)
                        .font(.system(size: 12, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? QP.primary : QP.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(on ? .white.opacity(0.14) : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.05)))
        .help("Tab switches filters")
    }
}

// MARK: - List

private struct ItemList: View {
    let items: [PanelItem]
    let selectedID: String?
    @ObservedObject var model: PanelModel
    let actions: PanelActions

    var body: some View {
        if items.isEmpty {
            EmptyList(searching: !model.query.isEmpty, filter: model.filter)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    // One flat sequence (headers + rows). With nested ForEach, a row that moved from one
                    // section to another kept its old state (pin mark and ⌘ number didn't update).
                    LazyVStack(alignment: .leading, spacing: 1) {
                        Color.clear.frame(height: 0).id("top")
                        ForEach(lines) { line in
                            switch line {
                            case .header(let title):
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(QP.tertiary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 12)
                                    .padding(.bottom, 4)
                            case .item(let item, let index):
                                Row(item: item, selected: item.id == selectedID, shortcut: index < 9 ? index + 1 : nil,
                                    imageURL: imageURL(item))
                                    .onTapGesture(count: 2) { actions.paste(item, false) }
                                    .onTapGesture { model.selectedID = item.id }
                                    .contextMenu { menu(item) }
                                    .modifier(DragIfScreenshot(item: item))
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onChange(of: selectedID) { _, id in
                    // When the first item is selected, show its section header too.
                    if id == items.first?.id { proxy.scrollTo("top", anchor: .top) }
                    else if let id { proxy.scrollTo(id) }
                }
                .onChange(of: model.shown) { _, now in
                    if now { proxy.scrollTo("top", anchor: .top) }
                }
            }
        }
    }

    private func imageURL(_ item: PanelItem) -> URL? {
        switch item {
        case .shot(let s): s.url
        case .clip(let e): model.clipboard.imageURL(e)
        }
    }

    private enum Line: Identifiable {
        case header(String)
        case item(PanelItem, Int)
        var id: String {
            switch self {
            case .header(let title): "h-" + title
            case .item(let item, _): item.id
            }
        }
    }

    /// Pinned, Today, Earlier, with headers. The number is the position in the overall order.
    private var lines: [Line] {
        let indexed = items.enumerated().map { ($1, $0) }
        let groups: [(String, [(PanelItem, Int)])] = [
            ("Pinned", indexed.filter { $0.0.pinned }),
            ("Today", indexed.filter { !$0.0.pinned && Calendar.current.isDateInToday($0.0.date) }),
            ("Earlier", indexed.filter { !$0.0.pinned && !Calendar.current.isDateInToday($0.0.date) }),
        ]
        return groups.filter { !$0.1.isEmpty }.flatMap { title, rows in
            [Line.header(title)] + rows.map { Line.item($0.0, $0.1) }
        }
    }

    @ViewBuilder private func menu(_ item: PanelItem) -> some View {
        Button("Paste") { actions.paste(item, false) }
        Button("Copy") { actions.paste(item, true) }
        if case .clip(let e) = item {
            Button(e.pinned ? "Unpin" : "Pin") { actions.togglePin(item) }
            if e.kind == .file { Button("Show in Finder") { actions.reveal(item) } }
        }
        if case .shot = item { Button("Show in Finder") { actions.reveal(item) } }
        Divider()
        Button("Delete", role: .destructive) { actions.delete(item) }
    }
}

/// Drag a screenshot from the list straight into any app.
private struct DragIfScreenshot: ViewModifier {
    let item: PanelItem
    func body(content: Content) -> some View {
        if case .shot(let s) = item {
            content.onDrag {
                DragOut.began()
                return NSItemProvider(contentsOf: s.url) ?? NSItemProvider()
            }
        } else {
            content
        }
    }
}

private struct Row: View {
    let item: PanelItem
    let selected: Bool
    let shortcut: Int?
    let imageURL: URL?

    var body: some View {
        HStack(spacing: 10) {
            Leading(item: item, imageURL: imageURL)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(QP.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(QP.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(QP.tertiary)
            }
            if let shortcut {
                Text("⌘\(shortcut)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(selected ? QP.secondary : QP.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: QP.rowHeight)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? QP.selection : .clear))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var title: String {
        switch item {
        case .clip(let e): e.title.isEmpty ? e.kind.title : e.title
        case .shot: "Screenshot"
        }
    }

    private var subtitle: String {
        switch item {
        case .clip(let e):
            var parts = [e.kind.title]
            if let app = SourceApps.name(e.sourceBundleID) { parts.append(app) }
            parts.append(QP.age(e.copiedAt))
            return parts.joined(separator: " · ")
        case .shot(let s):
            return "\(QP.time.string(from: s.createdAt)) · \(QP.age(s.createdAt))"
        }
    }
}

/// The row's leading mark: a thumbnail for images and screenshots, a swatch for colours,
/// otherwise the source app's icon.
private struct Leading: View {
    let item: PanelItem
    let imageURL: URL?
    @State private var thumb: NSImage?

    var body: some View {
        switch item {
        case .shot:
            thumbnail
        case .clip(let e) where e.kind == .image:
            thumbnail
        case .clip(let e) where e.kind == .color:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(ColorParse.color(e.text ?? "") ?? .gray)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .padding(3)
        case .clip(let e):
            if let icon = SourceApps.icon(e.sourceBundleID) {
                Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .overlay(alignment: .bottomTrailing) { badge(e.kind) }
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.08))
                    .overlay(Image(systemName: e.kind.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(QP.secondary))
                    .padding(2)
            }
        }
    }

    private var thumbnail: some View {
        thumbView.task(id: imageURL) {
            if let imageURL { thumb = await Thumbnail.load(imageURL, maxPixel: 90) }
        }
    }

    private var thumbView: some View {
        Group {
            if let thumb { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill) }
            else { Rectangle().fill(.white.opacity(0.07)) }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    /// A small kind badge in the icon's corner (link, code, file); plain text has none.
    @ViewBuilder private func badge(_ kind: ClipKind) -> some View {
        if kind == .link || kind == .code || kind == .file {
            Image(systemName: kind.symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Color(white: 0.22)))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .offset(x: 3, y: 3)
        }
    }
}

private struct EmptyList: View {
    let searching: Bool
    let filter: PanelFilter

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: searching ? "magnifyingglass" : (filter == .pinned ? "pin" : "doc.on.clipboard"))
                .font(.system(size: 22))
                .foregroundStyle(QP.tertiary)
            Text(searching ? "No matches" : (filter == .pinned ? "Nothing pinned" : "Nothing here yet"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(QP.secondary)
            Text(searching ? "Try another word" : (filter == .pinned ? "Select an item and press ⌘P" : "Copy text or take a screenshot (⇧⌘4)"))
                .font(.system(size: 11.5))
                .foregroundStyle(QP.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

// MARK: - Preview (right side)

private struct DetailPane: View {
    let item: PanelItem?
    @ObservedObject var model: PanelModel
    let actions: PanelActions

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Rectangle().fill(QP.hairline).frame(height: 1)
                MetaBlock(item: item)
            }
            .id(item.id)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private func content(_ item: PanelItem) -> some View {
        switch item {
        case .shot(let s):
            ImagePreview(url: s.url)
                .onTapGesture(count: 2) { actions.preview(s) }
                .modifier(DragIfScreenshot(item: item))
        case .clip(let e):
            switch e.kind {
            case .image:
                if let url = model.clipboard.imageURL(e) { ImagePreview(url: url) }
            case .color:
                ColorPreview(text: e.text ?? "")
            case .link:
                LinkPreview(text: e.text ?? "")
            case .file:
                FilePreview(paths: e.filePaths)
            case .code:
                TextPreview(text: e.text ?? "", mono: true)
            case .text:
                TextPreview(text: e.text ?? "", mono: false)
            }
        }
    }
}

private struct TextPreview: View {
    let text: String
    let mono: Bool

    var body: some View {
        ScrollView {
            Text(text)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 14))
                .lineSpacing(mono ? 2 : 3)
                .foregroundStyle(QP.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
        }
    }
}

private struct ImagePreview: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) { image = await Thumbnail.load(url, maxPixel: 1200) }
    }
}

private struct ColorPreview: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ColorParse.color(text) ?? .gray)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .frame(height: 170)
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(QP.primary)
                .textSelection(.enabled)
        }
        .padding(18)
    }
}

private struct LinkPreview: View {
    let text: String
    var body: some View {
        let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
        VStack(alignment: .leading, spacing: 10) {
            Text((url?.host ?? text).replacingOccurrences(of: "www.", with: ""))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(QP.primary)
                .lineLimit(2)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(QP.secondary)
                .textSelection(.enabled)
                .lineLimit(8)
            if let url {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open in browser", systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(QP.primary)
                .padding(.top, 6)
            }
        }
        .padding(18)
    }
}

private struct FilePreview: View {
    let paths: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let first = paths.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first))
                    .resizable().frame(width: 72, height: 72)
            }
            ForEach(paths.prefix(8), id: \.self) { path in
                VStack(alignment: .leading, spacing: 2) {
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FileManager.default.fileExists(atPath: path) ? QP.primary : QP.red)
                    Text((path as NSString).deletingLastPathComponent)
                        .font(.system(size: 11.5))
                        .foregroundStyle(QP.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            if paths.count > 8 {
                Text("and \(paths.count - 8) more").font(.system(size: 11.5)).foregroundStyle(QP.tertiary)
            }
        }
        .padding(18)
    }
}

/// Details under the preview: where from, when, how big.
private struct MetaBlock: View {
    let item: PanelItem

    var body: some View {
        HStack(spacing: 16) {
            ForEach(rows, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(QP.tertiary)
                    Text(value).font(.system(size: 12).monospacedDigit()).foregroundStyle(QP.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
    }

    private var rows: [(String, String)] {
        switch item {
        case .clip(let e):
            var r: [(String, String)] = [("Copied", QP.when(e.copiedAt))]
            if let app = SourceApps.name(e.sourceBundleID) { r.append(("From", app)) }
            if let text = e.text, e.kind != .file {
                let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                r.append(("Size", "\(text.count) \(text.count == 1 ? "char" : "chars") · \(words) \(words == 1 ? "word" : "words")"))
            }
            if let size = e.imageSize { r.append(("Size", "\(Int(size.width)) × \(Int(size.height))")) }
            return r
        case .shot(let s):
            var r: [(String, String)] = [("Taken", QP.when(s.createdAt))]
            if let size = try? s.url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                r.append(("File", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
            }
            return r
        }
    }
}

// MARK: - Bottom bar: keyboard hints

private struct Footer: View {
    let item: PanelItem?
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(hints, id: \.0) { key, label in
                HStack(spacing: 5) {
                    Text(key)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(QP.secondary)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 20, minHeight: 18)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.09)))
                    Text(label).font(.system(size: 11.5)).foregroundStyle(QP.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(count == 1 ? "1 item" : "\(count) items")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(QP.tertiary)
        }
        .padding(.horizontal, 18)
        .frame(height: 38)
    }

    private var hints: [(String, String)] {
        guard let item else { return [("Esc", "Close")] }
        var h: [(String, String)] = [("⏎", "Paste"), ("⌘⏎", "Copy")]
        switch item {
        case .clip(let e): h.append(("⌘P", e.pinned ? "Unpin" : "Pin"))
        case .shot: h.append(("Space", "Preview"))
        }
        h.append(("⌘⌫", "Delete"))
        h.append(("Tab", "Filter"))
        return h
    }
}
