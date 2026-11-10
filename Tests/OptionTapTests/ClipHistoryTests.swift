import Foundation
import Testing
@testable import OptionTap

struct ClipHistoryTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func text(_ s: String, at date: Date, pinned: Bool = false) -> ClipboardEntry {
        ClipboardEntry(kind: ClipboardEntry.classify(s), text: s, copiedAt: date, pinned: pinned)
    }

    @Test func newestFirst() {
        var h = ClipHistory()
        h.add(text("one", at: t0), now: t0)
        h.add(text("two", at: t0 + 1), now: t0 + 1)
        #expect(h.entries.map(\.text) == ["two", "one"])
    }

    @Test func copyingAgainMovesToTopWithoutDuplicate() {
        var h = ClipHistory()
        let first = text("hello", at: t0)
        h.add(first, now: t0)
        h.add(text("other", at: t0 + 1), now: t0 + 1)
        let (result, _) = h.add(text("hello", at: t0 + 2), now: t0 + 2)
        #expect(result == .bumped(first.id))
        #expect(h.entries.count == 2)
        #expect(h.entries.first?.id == first.id)
        #expect(h.entries.first?.copiedAt == t0 + 2)
    }

    @Test func sameTextDifferentKindIsNotADuplicate() {
        let a = ClipboardEntry(kind: .text, text: "x", copiedAt: t0)
        let b = ClipboardEntry(kind: .code, text: "x", copiedAt: t0)
        #expect(!a.sameContent(as: b))
    }

    @Test func imagesDedupeByHash() {
        let a = ClipboardEntry(kind: .image, text: nil, imageFile: "a.png", imageHash: "abc", copiedAt: t0)
        let b = ClipboardEntry(kind: .image, text: nil, imageFile: "b.png", imageHash: "abc", copiedAt: t0)
        let c = ClipboardEntry(kind: .image, text: nil, imageFile: "c.png", imageHash: nil, copiedAt: t0)
        #expect(a.sameContent(as: b))
        #expect(!c.sameContent(as: c))   // unknown hash: never treated as a duplicate
    }

    @Test func unpinnedExpireAfterRetention() {
        var h = ClipHistory()
        h.retention = 3600
        h.add(text("old", at: t0), now: t0)
        h.add(text("pinned", at: t0, pinned: true), now: t0)
        h.add(text("fresh", at: t0 + 3000), now: t0 + 3000)
        let removed = h.prune(now: t0 + 3601)
        #expect(removed.map(\.text) == ["old"])
        #expect(Set(h.entries.compactMap(\.text)) == ["pinned", "fresh"])
    }

    @Test func pinnedNeverExpire() {
        var h = ClipHistory()
        h.retention = 60
        h.add(text("keep", at: t0, pinned: true), now: t0)
        h.prune(now: t0 + 365 * 86_400)
        #expect(h.entries.count == 1)
    }

    @Test func overflowDropsOldestUnpinned() {
        var h = ClipHistory()
        h.maxEntries = 3
        h.add(text("pinned-old", at: t0, pinned: true), now: t0)
        for i in 1...4 { h.add(text("item \(i)", at: t0 + Double(i)), now: t0 + Double(i)) }
        #expect(h.entries.count == 3)
        #expect(h.entries.map(\.text) == ["item 4", "item 3", "pinned-old"])
    }

    @Test func overflowWithOnlyPinnedStops() {
        var h = ClipHistory()
        h.maxEntries = 1
        h.entries = [text("a", at: t0, pinned: true), text("b", at: t0, pinned: true)]
        do { let r = h.prune(now: t0); #expect(r.isEmpty) }
        #expect(h.entries.count == 2)
    }

    @Test func togglePinAndClearUnpinned() {
        var h = ClipHistory()
        let a = text("a", at: t0)
        h.add(a, now: t0)
        h.add(text("b", at: t0 + 1), now: t0 + 1)
        h.togglePin(a.id)
        #expect(h.entries.first { $0.id == a.id }?.pinned == true)
        let removed = h.removeUnpinned()
        #expect(removed.map(\.text) == ["b"])
        #expect(h.entries.map(\.id) == [a.id])
        h.togglePin(a.id)
        #expect(h.entries.first?.pinned == false)
    }

    @Test func removeByID() {
        var h = ClipHistory()
        let a = text("a", at: t0)
        h.add(a, now: t0)
        do { let r = h.remove(a.id); #expect(r?.id == a.id) }
        do { let r = h.remove(a.id); #expect(r == nil) }
        #expect(h.entries.isEmpty)
    }

    @Test func panelOrderPinnedFirstThenNewest() {
        let old = PanelItem.clip(text("old", at: t0))
        let new = PanelItem.clip(text("new", at: t0 + 10))
        let pin = PanelItem.clip(text("pin", at: t0 - 100, pinned: true))
        let shot = PanelItem.shot(ScreenshotItem(id: "s.png", url: URL(fileURLWithPath: "/tmp/s.png"), createdAt: t0 + 5))
        #expect(PanelItem.ordered([old, new, shot, pin]) == [pin, new, shot, old])
    }
}

struct ClassifyTests {
    @Test(arguments: [
        ("https://swift.org/docs", ClipKind.link),
        ("  http://example.com  ", .link),
        ("see https://swift.org", .text),
        ("#2B4CFF", .color),
        ("#fff", .color),
        ("rgb(43, 76, 255)", .color),
        ("hsla(230 100% 58% / 0.5)", .color),
        ("git status", .code),
        ("let a = 1;\nlet b = 2;", .code),
        ("Hello there\nhow are you", .text),
        ("Just some words", .text),
    ])
    func classify(input: String, expected: ClipKind) {
        #expect(ClipboardEntry.classify(input) == expected)
    }

    @Test func titles() {
        #expect(ClipboardEntry(kind: .text, text: "  first line \nsecond").title == "first line")
        #expect(ClipboardEntry(kind: .file, text: "/a/one.txt\n/a/two.txt\n/a/three.txt").title == "one.txt and 2 more")
        #expect(ClipboardEntry(kind: .image, text: nil, imageSize: CGSize(width: 40, height: 30)).title == "Image 40×30")
    }
}

struct ColorParseTests {
    @Test func hex() {
        #expect(ColorParse.components("#ff0000") == .init(r: 1, g: 0, b: 0, a: 1))
        #expect(ColorParse.components("#0f08") == nil)   // 4 digits isn't supported
        #expect(ColorParse.components("#00ff0080")?.a == Double(0x80) / 255)
    }

    @Test func rgbAndHsl() {
        #expect(ColorParse.components("rgb(255, 0, 0)") == .init(r: 1, g: 0, b: 0, a: 1))
        #expect(ColorParse.components("rgba(0 0 255 / 50%)")?.a == 0.5)
        let red = ColorParse.components("hsl(0, 100%, 50%)")
        #expect(red == .init(r: 1, g: 0, b: 0, a: 1))
        let green = ColorParse.components("hsl(120, 100%, 25%)")
        #expect(abs((green?.g ?? 0) - 0.5) < 0.001 && green?.r == 0)
        #expect(ColorParse.components("not a colour") == nil)
    }
}
