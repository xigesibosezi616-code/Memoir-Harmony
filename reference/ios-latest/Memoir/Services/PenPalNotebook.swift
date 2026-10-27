import Foundation
import SwiftData

/// 笔友手记的读和改（2026-10-27）。手记是什么见 `PenPalNote`；服务端怎么决定改法见 `Backend/shared/src/notebook.ts`。
///
/// - 寄信时 `snapshot` 取这一位的那本带上；回信到了 `apply` 照服务端交回的改法改
/// - 改完由调用方和回信一起 `save`（同一个 context，要么一起落库、要么都没落）
/// - 读不出来就当这次没带手记：信照样寄，不能因为手记卡住一封信
enum PenPalNotebook {
    /// 寄信时带上的那一本：画像一份（最新的那份）+ 最近的 `PenPalNote.recentLimit` 件大事，旧的在前
    static func snapshot(for penPalID: String, context: ModelContext) -> [PenPalNoteSnapshot] {
        let notes = fetch(penPalID, context: context)
        let profile = latestProfile(in: notes)
        let recent = notes
            .filter { $0.noteKind == .recent }
            .sorted { touched($0) < touched($1) }
            .suffix(PenPalNote.recentLimit)
        return (profile.map { [$0] } ?? []).map { snapshot($0) } + recent.map { snapshot($0) }
    }

    /// 照服务端交回的改法改本机那一本（不 save）
    static func apply(_ edits: NotebookEdits, for penPalID: String, at date: Date, context: ModelContext) {
        guard !edits.isEmpty else { return }
        let notes = fetch(penPalID, context: context)

        if let text = edits.profile {
            if let keep = latestProfile(in: notes) {
                keep.text = text
                keep.updatedAt = date
                // 两台设备各起了一份画像（iCloud 同步前各自寄了信）：留新的那份
                for other in notes where other.noteKind == .profile && other !== keep {
                    context.delete(other)
                }
            } else {
                context.insert(PenPalNote(penPalID: penPalID, text: text, notedAt: date, kind: .profile))
            }
        }

        // 只认这一位的大事：别的笔友的、画像，id 对上了也不动
        let recent = Dictionary(
            notes.filter { $0.noteKind == .recent }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let removed = Set(edits.remove)
        var deleted = 0
        for id in removed {
            guard let note = recent[id] else { continue }
            context.delete(note)
            deleted += 1
        }
        for rewrite in edits.update where !removed.contains(rewrite.id) {
            guard let note = recent[rewrite.id] else { continue }
            note.text = rewrite.text
            note.updatedAt = date
        }
        for text in edits.add {
            context.insert(PenPalNote(penPalID: penPalID, text: text, notedAt: date))
        }
        NSLog("ℹ️ [PenPalNotebook] %@ 画像%@ +%ld ~%ld -%ld", penPalID, edits.profile == nil ? "不动" : "重写",
              edits.add.count, edits.update.count, deleted)
    }

    // MARK: -

    private static func fetch(_ penPalID: String, context: ModelContext) -> [PenPalNote] {
        do {
            return try context.fetch(FetchDescriptor<PenPalNote>(predicate: #Predicate { $0.penPalID == penPalID }))
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [PenPalNotebook] 读手记失败 %@ domain=%@ code=%ld %@", penPalID, ns.domain, ns.code, "\(error)")
            return []
        }
    }

    /// 最后一次记下 / 改写的时刻
    private static func touched(_ note: PenPalNote) -> Date {
        note.updatedAt ?? note.notedAt
    }

    private static func latestProfile(in notes: [PenPalNote]) -> PenPalNote? {
        notes.filter { $0.noteKind == .profile }.max { touched($0) < touched($1) }
    }

    private static func snapshot(_ note: PenPalNote) -> PenPalNoteSnapshot {
        PenPalNoteSnapshot(id: note.id, kind: note.noteKind, text: note.text, date: touched(note))
    }
}
