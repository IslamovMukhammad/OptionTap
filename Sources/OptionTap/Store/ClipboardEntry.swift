import Foundation

enum ClipKind: String, Codable, Sendable {
    case text, link, code, color, image, file

    var title: String {
        switch self {
        case .text: "Text"
        case .link: "Link"
        case .code: "Code"
        case .color: "Color"
        case .image: "Image"
        case .file: "File"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .color: "paintpalette"
        case .image: "photo"
        case .file: "doc"
        }
    }
}

struct ClipboardEntry: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let kind: ClipKind
    /// The text itself for text kinds; file paths (one per line) for files; nil for images.
    let text: String?
    /// Images: name of the PNG saved in the store folder.
    let imageFile: String?
    let imageSize: CGSize?
    /// Images: SHA-256 of the PNG data, so copying the same image twice doesn't duplicate it.
    var imageHash: String?
    /// The app that was in front when this was copied.
    let sourceBundleID: String?
    var copiedAt: Date
    var pinned: Bool

    init(id: UUID = UUID(), kind: ClipKind, text: String?, imageFile: String? = nil, imageSize: CGSize? = nil,
         imageHash: String? = nil, sourceBundleID: String? = nil, copiedAt: Date = Date(), pinned: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.imageSize = imageSize
        self.imageHash = imageHash
        self.sourceBundleID = sourceBundleID
        self.copiedAt = copiedAt
        self.pinned = pinned
    }

    var filePaths: [String] { kind == .file ? (text ?? "").split(separator: "\n").map(String.init) : [] }

    /// Two entries hold the same content (used to move a re-copied item to the top).
    func sameContent(as other: ClipboardEntry) -> Bool {
        guard kind == other.kind else { return false }
        if kind == .image { return imageHash != nil && imageHash == other.imageHash }
        return text == other.text
    }

    /// One-line title for the list.
    var title: String {
        switch kind {
        case .image:
            if let size = imageSize { return "Image \(Int(size.width))×\(Int(size.height))" }
            return "Image"
        case .file:
            let paths = filePaths
            let first = (paths.first as NSString?)?.lastPathComponent ?? "File"
            return paths.count > 1 ? "\(first) and \(paths.count - 1) more" : first
        default:
            let line = (text ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return line.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Guesses what copied text is: a single link, a colour code, code, or plain text.
    static func classify(_ raw: String) -> ClipKind {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains(where: \.isWhitespace), let url = URL(string: text),
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil {
            return .link
        }
        if text.range(of: #"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#, options: .regularExpression) != nil
            || text.range(of: #"^(rgb|rgba|hsl|hsla)\([^)]*\)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .color
        }
        let lines = text.split(whereSeparator: \.isNewline)
        if lines.count >= 2 {
            let codeMarks = [";", "{", "}", "=>", "->", "()", "func ", "let ", "const ", "import ", "def ", "return ", "</", "#include"]
            let marked = lines.filter { line in codeMarks.contains { line.contains($0) } }.count
            let indented = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
            if Double(marked + indented) / Double(lines.count) >= 0.5 { return .code }
        } else if ["$ ", "git ", "cd ", "npm ", "brew ", "swift ", "xcodebuild "].contains(where: text.hasPrefix) {
            return .code
        }
        return .text
    }
}
