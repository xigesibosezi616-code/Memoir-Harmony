import Foundation
import SwiftData

@Observable
class JournalStore {
    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD

    func addEntry(title: String, content: String, mood: String, moodColorHex: String? = nil, tags: [String]) {
        let entry = JournalEntry(
            title: title,
            content: content,
            mood: mood,
            moodColorHex: moodColorHex,
            tags: tags
        )
        entry.wordCount = content.count
        modelContext.insert(entry)
        try? modelContext.save()
    }

    func updateEntry(_ entry: JournalEntry, title: String, content: String, mood: String, moodColorHex: String? = nil, tags: [String]) {
        entry.title = title
        entry.content = content
        entry.mood = mood
        entry.moodColorHex = moodColorHex
        entry.tags = tags
        entry.wordCount = content.count
        entry.updatedAt = .now
        try? modelContext.save()
    }

    func deleteEntry(_ entry: JournalEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
    }

    // MARK: - Queries

    func fetchAllEntries() -> [JournalEntry] {
        let descriptor = FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func entriesGroupedByMonth() -> [(key: String, entries: [JournalEntry])] {
        let all = fetchAllEntries()
        let grouped = Dictionary(grouping: all) { $0.date.yearMonthKey }
        return grouped
            .map { (key: $0.key, entries: $0.value) }
            .sorted { $0.entries.first?.date ?? .distantPast > $1.entries.first?.date ?? .distantPast }
    }

    func entries(withTag tag: String) -> [JournalEntry] {
        let all = fetchAllEntries()
        return all.filter { $0.tags.contains(tag) }
    }

    // MARK: - Tags

    func fetchAllTags() -> [Tag] {
        let descriptor = FetchDescriptor<Tag>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func addTag(name: String) {
        let existing = fetchAllTags()
        guard !Tag.isNameTaken(name, in: existing.map(\.name)) else { return }
        let tag = Tag(name: name)
        tag.sortOrder = Tag.nextSortOrder(after: existing)
        modelContext.insert(tag)
        try? modelContext.save()
    }

    func deleteTag(_ tag: Tag) {
        modelContext.delete(tag)
        try? modelContext.save()
    }
}
