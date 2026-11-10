import Foundation

/// The clipboard history rules, as a plain value type so they can be unit tested without a pasteboard.
///
/// - Newest first. Pinned entries stay in the same array; the panel sorts them to the top.
/// - Copying the same thing again moves the old entry to the top instead of adding a duplicate.
/// - Pinned entries never expire. The rest drop after `retention`, and the oldest unpinned ones
///   drop when there are more than `maxEntries`.
struct ClipHistory: Equatable, Sendable {
    var entries: [ClipboardEntry] = []
    var retention: TimeInterval = 24 * 60 * 60
    var maxEntries = 300

    enum AddResult: Equatable {
        case inserted
        /// Same content already existed; that entry (this id) was moved to the top.
        case bumped(UUID)
    }

    /// Adds a newly copied entry. Returns what happened, plus any entries that fell out
    /// (so the caller can delete their image files).
    @discardableResult
    mutating func add(_ entry: ClipboardEntry, now: Date = Date()) -> (result: AddResult, removed: [ClipboardEntry]) {
        if let index = entries.firstIndex(where: { $0.sameContent(as: entry) }) {
            var existing = entries.remove(at: index)
            existing.copiedAt = now
            entries.insert(existing, at: 0)
            return (.bumped(existing.id), [])
        }
        entries.insert(entry, at: 0)
        return (.inserted, prune(now: now))
    }

    /// Drops expired and overflowing unpinned entries. Returns what was removed.
    @discardableResult
    mutating func prune(now: Date = Date()) -> [ClipboardEntry] {
        let cutoff = now.addingTimeInterval(-retention)
        var removed = entries.filter { !$0.pinned && $0.copiedAt < cutoff }
        var keep = entries.filter { $0.pinned || $0.copiedAt >= cutoff }
        while keep.count > maxEntries, let last = keep.lastIndex(where: { !$0.pinned }) {
            removed.append(keep.remove(at: last))
        }
        if !removed.isEmpty { entries = keep }
        return removed
    }

    mutating func togglePin(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].pinned.toggle()
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> ClipboardEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index)
    }

    /// Removes every unpinned entry. Returns what was removed.
    @discardableResult
    mutating func removeUnpinned() -> [ClipboardEntry] {
        let removed = entries.filter { !$0.pinned }
        entries.removeAll { !$0.pinned }
        return removed
    }
}
