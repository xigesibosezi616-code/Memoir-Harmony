/**
 * 一位笔友的一本手记（U01 B3；对应 iOS `Services/PenPalNotebook.swift`）。
 *
 * 两个纯函数，不碰库、不碰网络——什么时候读、什么时候落库由调用方（LetterOutboxService）定：
 * - `snapshot`：寄信时带哪几条（R-NOTEBOOK-03）——画像在前，大事按记下 / 改写时刻
 *   升序取**最近 `PenPalNote.recentLimit` 条**（旧的被合并掉了就不带）
 * - `apply`：回执说这本怎么改（R-NOTEBOOK-04）——算出一份落库计划返回，
 *   **改的是传入的实例**（text / updatedAtMs 就地改），新增的 new 出来；
 *   顺序 remove → update（跳过已删）→ add，与后端语义一致
 *
 * 只认这一位笔友的：`notes` 由调用方按 penPalID 查好传进来，
 * 回执里画像的 id、别的笔友的 id 对上了也不动。
 */
import { NotebookEdits, NotebookItem } from './Api';
import { PenPalNote, PenPalNoteKind } from './PenPalNote';

/** apply 算出的落库计划：调用方照单执行（toUpsert 逐条 upsert、toDeleteIds 按 id 删） */
export class NotebookApplyPlan {
  /** 要改的已有条 + 新建的（一起 upsert；PenPalNoteRepository.saveNote 幂等） */
  readonly toUpsert: PenPalNote[] = [];
  /** 要删的 id（重复的画像 + 被合并掉的大事） */
  readonly toDeleteIds: string[] = [];
}

export class PenPalNotebook {
  /** 画像在前、大事按 touched 升序取尾部 recentLimit 条 */
  static snapshot(notes: PenPalNote[]): NotebookItem[] {
    let profile: PenPalNote | undefined = undefined;
    const recents: PenPalNote[] = [];
    for (const note of notes) {
      if (note.noteKind() === PenPalNoteKind.Profile) {
        if (profile === undefined || note.touchedMs() > profile.touchedMs()) {
          profile = note;
        }
      } else {
        recents.push(note);
      }
    }
    recents.sort((a: PenPalNote, b: PenPalNote) => a.touchedMs() - b.touchedMs());
    const kept: PenPalNote[] = recents.length > PenPalNote.recentLimit
      ? recents.slice(recents.length - PenPalNote.recentLimit) : recents;
    const out: NotebookItem[] = [];
    if (profile !== undefined) {
      out.push(PenPalNotebook.itemOf(profile));
    }
    for (const note of kept) {
      out.push(PenPalNotebook.itemOf(note));
    }
    return out;
  }

  private static itemOf(note: PenPalNote): NotebookItem {
    return new NotebookItem(note.id, note.noteKind() === PenPalNoteKind.Profile
      ? PenPalNoteKind.Profile : PenPalNoteKind.Recent, note.text, note.touchedMs());
  }

  /** 这一堆里最新的画像（touched 最大）；没有返回 undefined */
  private static latestProfile(notes: PenPalNote[]): PenPalNote | undefined {
    let latest: PenPalNote | undefined = undefined;
    for (const note of notes) {
      if (note.noteKind() === PenPalNoteKind.Profile &&
        (latest === undefined || note.touchedMs() > latest.touchedMs())) {
        latest = note;
      }
    }
    return latest;
  }

  /**
   * 回执落到这本上（R-NOTEBOOK-04）。返回落库计划，**不落库**（调用方执行）。
   * - 画像：有 → 改最新那份 + 删其余重复画像；无 → 新建 kind=profile
   * - 大事 remove/update 只认**这一位最近大事**的 id（画像 / 别的笔友的 id 对上不动）
   * - update 与 remove 冲突以删为准
   * - add 新建（notedAtMs = atMs，即回执的写信时刻）
   */
  static apply(notes: PenPalNote[], penPalID: string, edits: NotebookEdits,
    atMs: number): NotebookApplyPlan {
    const plan = new NotebookApplyPlan();
    if (edits.isEmpty()) {
      return plan;
    }
    // 1) 画像：改最新那份 + 删重复；没有 → 新建
    if (edits.profile !== undefined) {
      const keep = PenPalNotebook.latestProfile(notes);
      if (keep !== undefined) {
        keep.text = edits.profile;
        keep.updatedAtMs = atMs;
        plan.toUpsert.push(keep);
        for (const note of notes) {
          if (note.noteKind() === PenPalNoteKind.Profile && note !== keep) {
            plan.toDeleteIds.push(note.id);
          }
        }
      } else {
        const created = new PenPalNote(penPalID, edits.profile, atMs);
        created.kind = PenPalNoteKind.Profile;
        plan.toUpsert.push(created);
      }
    }
    // 2) 大事：按 id 建表（只认这一位的 recent，画像 id 对上不动）
    const byId: Map<string, PenPalNote> = new Map();
    for (const note of notes) {
      if (note.noteKind() === PenPalNoteKind.Recent) {
        byId.set(note.id, note);
      }
    }
    // 2a) remove（先记下来，update 撞上以删为准）
    const removedIds: Set<string> = new Set();
    for (const id of edits.remove) {
      const note = byId.get(id);
      if (note !== undefined) {
        plan.toDeleteIds.push(note.id);
        removedIds.add(id);
      }
    }
    // 2b) update（已删的跳过）
    for (const rewrite of edits.update) {
      if (removedIds.has(rewrite.id)) {
        continue;
      }
      const note = byId.get(rewrite.id);
      if (note !== undefined) {
        note.text = rewrite.text;
        note.updatedAtMs = atMs;
        plan.toUpsert.push(note);
      }
    }
    // 2c) add
    for (const text of edits.add) {
      plan.toUpsert.push(new PenPalNote(penPalID, text, atMs));
    }
    return plan;
  }
}
