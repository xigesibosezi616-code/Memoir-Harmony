/**
 * PostBoxLogic 单测（10_BUILD_MANUAL.md 5.2）。
 *
 * 🔴 候选口径与判定顺序是跨端行为规则（06_RULES.md R-POST-02/03/04/06）：
 * - 候选按 createdAt（真正写下的时刻）判新，不按 date（用户可改的日记日期）
 * - 上次寄信 = 真信 ∪ 写信中里最大 generatedAt；退回不算，退回信关联的日记不进候选
 * - 一次最多 14 篇（LetterDelivery.maximumEntriesPerLetter）
 * - 判定顺序：退回 → 未登录 → 写信中 → 服务端拦 → 有可寄 → 在路上 → 没新日记 → 一篇都没有
 * 外加标题口径（标题 → 正文第一行 ≤30 字 → 「无题」）与 parseRhythmResponse。
 */
import { describe, it, expect } from '@ohos/hypium';
import { Letter, LetterStatus } from '../../main/ets/models/Letter';
import { JournalEntry } from '../../main/ets/models/JournalEntry';
import { LetterDelivery } from '../../main/ets/models/LetterDelivery';
import { RhythmResponse, parseRhythmResponse } from '../../main/ets/models/Api';
import {
  PostBoxSituationKind,
  PostBoxStateInput,
  candidateEntries,
  lastSentAtMs,
  judgePostBoxState,
  outgoingTitleOf,
  outgoingItemsOf,
  hasUnreadLetter
} from '../../main/ets/models/PostBoxLogic';

const NOW = 10_000_000_000; // 毫秒

function makeLetter(id: string, status: LetterStatus, body: string, generatedAt: number): Letter {
  const letter = new Letter(id, generatedAt, generatedAt);
  letter.status = status;
  letter.body = body;
  return letter;
}

function makeEntry(id: string, date: number, createdAt: number): JournalEntry {
  return new JournalEntry(id, date, createdAt, createdAt);
}

function input(letters: Letter[], entries: JournalEntry[], held: Set<string>,
  rhythm: RhythmResponse | undefined, loggedIn: boolean): PostBoxStateInput {
  return new PostBoxStateInput(letters, entries, held, rhythm, loggedIn, NOW);
}

export default function postBoxLogicTest() {
  describe('PostBoxLogicTest', () => {
    // ---- R-POST-02：候选按 createdAt 判新，不按 date ----

    it('candidatesUseCreatedAtNotDate', 0, () => {
      const sent = makeLetter('L1', LetterStatus.Read, '回信', 5000);
      sent.deliveredAt = 6000;
      // 补记上周的日记：date 在寄信之前，createdAt 在之后 —— 也算「新写的」
      const backdated = makeEntry('E1', 1000, 6000);
      const ordinary = makeEntry('E2', 6500, 6500);
      const fresh = candidateEntries([sent], [backdated, ordinary], new Set<string>());
      expect(fresh.length).assertEqual(2);
      expect(fresh[0].id === 'E1' || fresh[1].id === 'E1').assertTrue();
    })

    it('candidatesAreEmptyBeforeFirstLetterAndCutAt14', 0, () => {
      // 一封都没寄过：全部日记都是候选
      const entries: JournalEntry[] = [];
      for (let i = 0; i < 20; i++) {
        entries.push(makeEntry(`E${i}`, 1000 + i, 1000 + i));
      }
      const fresh = candidateEntries([], entries, new Set<string>());
      expect(fresh.length).assertEqual(LetterDelivery.maximumEntriesPerLetter);
      expect(fresh.length).assertEqual(14);
    })

    it('candidatesRequireStrictlyAfterLastSent', 0, () => {
      const sent = makeLetter('L1', LetterStatus.Delivered, '回信', 5000);
      sent.deliveredAt = 5001;
      const sameMoment = makeEntry('E1', 5000, 5000); // createdAt == lastSentAt：不算新
      const justAfter = makeEntry('E2', 5001, 5001);
      const fresh = candidateEntries([sent], [sameMoment, justAfter], new Set<string>());
      expect(fresh.length).assertEqual(1);
      expect(fresh[0].id).assertEqual('E2');
    })

    // ---- R-POST-03：退回不算寄过；退回信关联的日记不进候选 ----

    it('lastSentAtIgnoresBouncedLetters', 0, () => {
      const sent = makeLetter('L1', LetterStatus.Delivered, '回信', 5000);
      sent.deliveredAt = 5001;
      const bounced = makeLetter('L2', LetterStatus.Failed, '', 9000);
      // 退回不算寄过 → 上次寄信仍是 5000
      expect(lastSentAtMs([bounced, sent])).assertEqual(5000);
    })

    it('lastSentAtCountsWritingLetters', 0, () => {
      const writing = makeLetter('L1', LetterStatus.Generating, '', 7000);
      expect(lastSentAtMs([writing])).assertEqual(7000);
    })

    it('lastSentAtIsUndefinedWhenNothingSent', 0, () => {
      expect(lastSentAtMs([])).assertUndefined();
      const bounced = makeLetter('L1', LetterStatus.Failed, '', 9000);
      expect(lastSentAtMs([bounced])).assertUndefined();
    })

    it('heldEntriesAreExcludedFromCandidates', 0, () => {
      const bounced = makeLetter('L1', LetterStatus.Failed, '', 9000);
      const e1 = makeEntry('E1', 9500, 9500);
      const e2 = makeEntry('E2', 9600, 9600);
      const held = new Set<string>(['E1']); // 退回那封里的日记
      const fresh = candidateEntries([bounced], [e1, e2], held);
      expect(fresh.length).assertEqual(1);
      expect(fresh[0].id).assertEqual('E2');
    })

    // ---- R-POST-06：判定顺序，先命中先算 ----

    it('returnedWinsOverEverything', 0, () => {
      const bounced = makeLetter('L1', LetterStatus.Failed, '', 9000);
      const entries = [makeEntry('E1', 9500, 9500)];
      const rhythm = new RhythmResponse('free', true, 'ok', '');
      const state = judgePostBoxState(input([bounced], entries, new Set<string>(), rhythm, false));
      expect(state.kind).assertEqual(PostBoxSituationKind.Returned);
    })

    it('notLoggedInComesSecond', 0, () => {
      const entries = [makeEntry('E1', 1000, 1000)];
      const state = judgePostBoxState(input([], entries, new Set<string>(), undefined, false));
      expect(state.kind).assertEqual(PostBoxSituationKind.NotLoggedIn);
    })

    it('justPostedComesBeforeBlockedAndReady', 0, () => {
      const writing = makeLetter('L1', LetterStatus.Generating, '', 5000);
      const entries = [makeEntry('E1', 6000, 6000)];
      // 服务端说能寄、也有新日记 —— 写信中优先
      const state = judgePostBoxState(input([writing], entries, new Set<string>(), undefined, true));
      expect(state.kind).assertEqual(PostBoxSituationKind.JustPosted);
      // 候选照算：状态行要区分「投进邮筒了」和「刚寄出过一会儿再寄」
      expect(state.candidates.length).assertEqual(1);
      // 服务端说不能寄也一样：写信中优先
      const blocked = new RhythmResponse('free', false, 'weekly_pending', '2099-01-01T00:00:00Z');
      const state2 = judgePostBoxState(input([writing], entries, new Set<string>(), blocked, true));
      expect(state2.kind).assertEqual(PostBoxSituationKind.JustPosted);
    })

    it('blockedShowsCandidatesForThePile', 0, () => {
      const sent = makeLetter('L1', LetterStatus.Delivered, '回信', 5000);
      sent.deliveredAt = 5001;
      const entries = [makeEntry('E1', 6000, 6000)];
      const rhythm = new RhythmResponse('free', false, 'weekly_pending', '2099-01-01T00:00:00Z');
      const state = judgePostBoxState(input([sent], entries, new Set<string>(), rhythm, true));
      expect(state.kind).assertEqual(PostBoxSituationKind.Blocked);
      // 这周寄不了，新写的先摆着：候选要给下半区的纸
      expect(state.candidates.length).assertEqual(1);
      // 问不到节奏（undefined）不拦：直接 Ready
      const state2 = judgePostBoxState(input([sent], entries, new Set<string>(), undefined, true));
      expect(state2.kind).assertEqual(PostBoxSituationKind.Ready);
    })

    it('readyWhenFreshEntriesExist', 0, () => {
      const entries = [makeEntry('E1', 1000, 1000)];
      const rhythm = new RhythmResponse('free', true, 'ok', '');
      const state = judgePostBoxState(input([], entries, new Set<string>(), rhythm, true));
      expect(state.kind).assertEqual(PostBoxSituationKind.Ready);
      expect(state.candidates.length).assertEqual(1);
    })

    it('inTransitWhenLetterOnTheWayAndNothingNew', 0, () => {
      const sent = makeLetter('L1', LetterStatus.Pending, '回信', 5000);
      sent.deliveredAt = NOW + 3600_000; // 还没到
      const state = judgePostBoxState(input([sent], [], new Set<string>(), undefined, true));
      expect(state.kind).assertEqual(PostBoxSituationKind.InTransit);
    })

    it('nothingNewWhenAllEntriesOlderThanLastSent', 0, () => {
      const sent = makeLetter('L1', LetterStatus.Delivered, '回信', 5000);
      sent.deliveredAt = 5001;
      const entries = [makeEntry('E1', 4000, 4000)]; // 寄信之前写的
      const state = judgePostBoxState(input([sent], entries, new Set<string>(), undefined, true));
      expect(state.kind).assertEqual(PostBoxSituationKind.NothingNew);
    })

    it('noEntriesWhenJournalEmpty', 0, () => {
      const state = judgePostBoxState(input([], [], new Set<string>(), undefined, true));
      expect(state.kind).assertEqual(PostBoxSituationKind.NoEntries);
    })

    // ---- R-POST-04：标题口径（标题 → 正文第一行 ≤30 字 → 无题） ----

    it('outgoingTitlePrefersTitleThenFirstLine', 0, () => {
      const withTitle = makeEntry('E1', 0, 0);
      withTitle.title = '标题';
      expect(outgoingTitleOf(withTitle)).assertEqual('标题');

      const noTitle = makeEntry('E2', 0, 0);
      noTitle.title = '   ';
      noTitle.content = '第一行\n第二行';
      expect(outgoingTitleOf(noTitle)).assertEqual('第一行');

      const neither = makeEntry('E3', 0, 0);
      neither.title = '';
      neither.content = '\n  \n只有第二行有字';
      expect(outgoingTitleOf(neither)).assertEqual('');

      const longLine = makeEntry('E4', 0, 0);
      longLine.title = '';
      longLine.content = '这一行特别长'.repeat(10);
      expect(outgoingTitleOf(longLine).length).assertEqual(30);
    })

    it('outgoingItemsSnapshotIdDateTitle', 0, () => {
      const entry = makeEntry('E1', 12345, 1000);
      entry.title = '海边';
      const items = outgoingItemsOf([entry]);
      expect(items.length).assertEqual(1);
      expect(items[0].id).assertEqual('E1');
      expect(items[0].date).assertEqual(12345);
      expect(items[0].title).assertEqual('海边');
    })

    // ---- 信箱入口红点 ----

    it('hasUnreadLetterRequiresArrivedAndUnread', 0, () => {
      const unread = makeLetter('L1', LetterStatus.Delivered, '回信', 5000);
      unread.deliveredAt = 5001;
      expect(hasUnreadLetter([unread], NOW)).assertTrue();
      const read = makeLetter('L2', LetterStatus.Read, '回信', 5000);
      read.deliveredAt = 5001;
      expect(hasUnreadLetter([read], NOW)).assertFalse();
      const pending = makeLetter('L3', LetterStatus.Pending, '回信', 5000);
      pending.deliveredAt = NOW + 1000; // 还没到
      expect(hasUnreadLetter([pending], NOW)).assertFalse();
    })

    // ---- parseRhythmResponse（GET /me/rhythm 的形状） ----

    it('parseRhythmResponseReadsAllFields', 0, () => {
      const raw = '{"tier":"free","canRequestNow":false,"reason":"weekly_pending",' +
        '"nextLetterAt":"2099-01-01T00:00:00Z"}';
      const r = parseRhythmResponse(raw);
      expect(r.tier).assertEqual('free');
      expect(r.canRequestNow).assertFalse();
      expect(r.reason).assertEqual('weekly_pending');
      expect(r.nextLetterAt).assertEqual('2099-01-01T00:00:00Z');
      // nextLetterAt 可为 null（现在就能寄）
      const ok = parseRhythmResponse('{"tier":"subscribed","canRequestNow":true,"reason":"ok","nextLetterAt":null}');
      expect(ok.canRequestNow).assertTrue();
      expect(ok.nextLetterAt).assertEqual('');
    })

    it('parseRhythmResponseRejectsBadShapes', 0, () => {
      const bad: string[] = ['{"tier":"free"}', '[]', 'not json'];
      for (const raw of bad) {
        let caught = false;
        try {
          parseRhythmResponse(raw);
        } catch (e) {
          caught = true;
        }
        expect(caught).assertTrue();
      }
    })
  })
}
