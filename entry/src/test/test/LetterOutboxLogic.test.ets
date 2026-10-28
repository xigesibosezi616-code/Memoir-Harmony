/**
 * LetterOutboxLogic 单测（10_BUILD_MANUAL.md 5.3）。
 *
 * 🔴 重试计时与补领匹配是跨端行为规则（06_RULES.md R-OUTBOX-04/05/07/09）：
 * - 断网 / 超时 / 取消 / 传输故障不算失败，30 秒后再试
 * - 服务端出错第 1 次 1 分钟、之后 5 分钟；连续 3 次退回
 * - 本机负责表 JSON 坏了按空表（信还在库里，最多多试一次）
 * - 补领：服务端信升序逐条认领 waiting 里第一封 generatedAt ≤ 这条 + 5 分钟的；
 *   认领掉的不再用；正文按去重跳过；对不上新落一封
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  OutboxItem,
  OUTBOX_MAX_FAILURES,
  OUTBOX_CLOCK_SKEW_MS,
  OUTBOX_NETWORK_RETRY_MS,
  OUTBOX_FIRST_FAILURE_RETRY_MS,
  OUTBOX_LATER_FAILURE_RETRY_MS,
  encodeOutboxState,
  decodeOutboxState,
  isOutboxDue,
  failureRetryDelayMs,
  itemAfterNetworkError,
  itemAfterServerFailure,
  shouldGiveBack,
  itemForResend,
  dominantMoodOf,
  RemoteLetter,
  WaitingLetter,
  ReconcileActionKind,
  reconcilePlan,
  isOwnedWriting,
  isOwnedBounce
} from '../../main/ets/models/LetterOutboxLogic';
import { Letter, LetterStatus } from '../../main/ets/models/Letter';

const NOW = 10_000_000_000; // 毫秒

function letter(id: string, status: LetterStatus, body: string): Letter {
  const l = new Letter(id, NOW, NOW);
  l.status = status;
  l.body = body;
  return l;
}

export default function letterOutboxLogicTest() {
  describe('LetterOutboxLogicTest', () => {
    // ---- R-OUTBOX-01：本机负责表的 JSON 编解码 ----

    it('encodeDecodeRoundTrips', 0, () => {
      const state = new Map<string, OutboxItem>();
      state.set('L1', new OutboxItem(2, 1, NOW + 5000));
      state.set('L2', new OutboxItem(0, 0));
      const raw = encodeOutboxState(state);
      const back = decodeOutboxState(raw);
      expect(back.size).assertEqual(2);
      const l1 = back.get('L1');
      expect(l1?.attempts).assertEqual(2);
      expect(l1?.failures).assertEqual(1);
      expect(l1?.nextAttemptAt).assertEqual(NOW + 5000);
      const l2 = back.get('L2');
      expect(l2?.attempts).assertEqual(0);
      expect(l2?.nextAttemptAt).assertUndefined();
    })

    it('decodeTreatsBadJsonAsEmptyState', 0, () => {
      for (const raw of ['not json', '[]', '"x"', '{"L1":', '']) {
        expect(decodeOutboxState(raw).size).assertEqual(0);
      }
    })

    it('decodeFillsDefaultsForBadShapes', 0, () => {
      // 字段坏了不丢这条信：按缺省处理（最多多试一次，比弄丢负责表好）
      const back = decodeOutboxState('{"L1":{"attempts":"x","failures":null},"L2":3}');
      expect(back.size).assertEqual(1);
      const l1 = back.get('L1');
      expect(l1?.attempts).assertEqual(0);
      expect(l1?.failures).assertEqual(0);
      expect(l1?.nextAttemptAt).assertUndefined();
    })

    // ---- R-OUTBOX-04：断网 / 超时不算失败，30 秒后再试 ----

    it('networkErrorKeepsFailuresAndRetriesIn30s', 0, () => {
      const before = new OutboxItem(1, 2, NOW);
      const after = itemAfterNetworkError(before, NOW);
      expect(after.attempts).assertEqual(1);
      expect(after.failures).assertEqual(2);
      expect(after.nextAttemptAt).assertEqual(NOW + OUTBOX_NETWORK_RETRY_MS);
      expect(OUTBOX_NETWORK_RETRY_MS).assertEqual(30 * 1000);
    })

    // ---- R-OUTBOX-05：服务端出错 1 分钟 / 5 分钟；连续 3 次退回 ----

    it('serverFailureGrowsFailuresAndDelays', 0, () => {
      expect(failureRetryDelayMs(1)).assertEqual(OUTBOX_FIRST_FAILURE_RETRY_MS);
      expect(failureRetryDelayMs(2)).assertEqual(OUTBOX_LATER_FAILURE_RETRY_MS);
      expect(failureRetryDelayMs(3)).assertEqual(OUTBOX_LATER_FAILURE_RETRY_MS);
      expect(OUTBOX_FIRST_FAILURE_RETRY_MS).assertEqual(60 * 1000);
      expect(OUTBOX_LATER_FAILURE_RETRY_MS).assertEqual(5 * 60 * 1000);
      const first = itemAfterServerFailure(new OutboxItem(1, 0), NOW);
      expect(first.failures).assertEqual(1);
      expect(first.nextAttemptAt).assertEqual(NOW + 60 * 1000);
      const second = itemAfterServerFailure(first, NOW);
      expect(second.failures).assertEqual(2);
      expect(second.nextAttemptAt).assertEqual(NOW + 5 * 60 * 1000);
    })

    it('giveBackAfterThreeConsecutiveServerFailures', 0, () => {
      expect(OUTBOX_MAX_FAILURES).assertEqual(3);
      expect(shouldGiveBack(new OutboxItem(3, 2))).assertFalse();
      expect(shouldGiveBack(new OutboxItem(3, 3))).assertTrue();
      // 断网重试不涨 failures → 不会被退回
      const netOnly = itemAfterNetworkError(new OutboxItem(0, 2), NOW);
      expect(shouldGiveBack(netOnly)).assertFalse();
    })

    // ---- 到时候没有 / 重新寄出 ----

    it('isDueWhenNoNextAttemptOrTimeReached', 0, () => {
      expect(isOutboxDue(new OutboxItem(0, 0), NOW)).assertTrue();
      expect(isOutboxDue(new OutboxItem(0, 0, NOW + 1), NOW)).assertFalse();
      // 恰好到点也算到（<=）
      expect(isOutboxDue(new OutboxItem(0, 0, NOW), NOW)).assertTrue();
    })

    it('resendClearsFailuresButKeepsAttempts', 0, () => {
      // attempts 记着：重发前先补领（R-OUTBOX-07）
      const after = itemForResend(new OutboxItem(2, 3, NOW + 9999));
      expect(after.attempts).assertEqual(2);
      expect(after.failures).assertEqual(0);
      expect(after.nextAttemptAt).assertUndefined();
      expect(isOutboxDue(after, NOW)).assertTrue();
    })

    // ---- R-OUTBOX-10 / U03：主导心情 ----

    it('dominantMoodIsMostCommonNonEmpty', 0, () => {
      expect(dominantMoodOf(['calm', 'joy', 'calm', ''])).assertEqual('calm');
      // 并列取先出现的
      expect(dominantMoodOf(['joy', 'calm', 'calm', 'joy'])).assertEqual('joy');
      expect(dominantMoodOf(['', '', ''])).assertEqual('');
      expect(dominantMoodOf([])).assertEqual('');
    })

    // ---- R-OUTBOX-07/09：补领匹配 ----

    it('reconcileAdoptsWithinClockSkewBoundary', 0, () => {
      // 手机钟慢了：waiting 比服务端回信晚写也认（恰好 5 分钟，<= 含等于）
      const remote = [new RemoteLetter('回信', '青鸟', 20_000)];
      const boundary = [new WaitingLetter('L1', 20_000 + OUTBOX_CLOCK_SKEW_MS)];
      const actions = reconcilePlan(remote, boundary, new Set<string>());
      expect(actions.length).assertEqual(1);
      expect(actions[0].kind).assertEqual(ReconcileActionKind.Adopt);
      expect(actions[0].adoptLetterId).assertEqual('L1');
      // 晚超过 5 分钟：不是这封的回信 → 新落一封
      const tooLate = [new WaitingLetter('L2', 20_000 + OUTBOX_CLOCK_SKEW_MS + 1)];
      const actions2 = reconcilePlan(remote, tooLate, new Set<string>());
      expect(actions2[0].kind).assertEqual(ReconcileActionKind.Create);
    })

    it('reconcileProcessesRemoteOldestFirst', 0, () => {
      // 传入乱序：先处理写信早的那条，认领最早的 waiting
      const remote = [
        new RemoteLetter('后写的回信', '青鸟', 30_000),
        new RemoteLetter('先写的回信', '青鸟', 20_000)
      ];
      const waiting = [
        new WaitingLetter('L1', 19_000),
        new WaitingLetter('L2', 29_000)
      ];
      const actions = reconcilePlan(remote, waiting, new Set<string>());
      expect(actions.length).assertEqual(2);
      // 先写的回信归 L1（升序第一个动作），后写的归 L2
      expect(actions[0].remote.body).assertEqual('先写的回信');
      expect(actions[0].adoptLetterId).assertEqual('L1');
      expect(actions[1].remote.body).assertEqual('后写的回信');
      expect(actions[1].adoptLetterId).assertEqual('L2');
    })

    it('reconcileDoesNotReuseAdoptedLetter', 0, () => {
      // 两条服务端信、一封 waiting：第一条认领掉，第二条对不上 → Create
      const remote = [
        new RemoteLetter('回信一', '青鸟', 20_000),
        new RemoteLetter('回信二', '青鸟', 21_000)
      ];
      const waiting = [new WaitingLetter('L1', 19_000)];
      const actions = reconcilePlan(remote, waiting, new Set<string>());
      expect(actions[0].kind).assertEqual(ReconcileActionKind.Adopt);
      expect(actions[1].kind).assertEqual(ReconcileActionKind.Create);
    })

    it('reconcileSkipsBodiesAlreadyLocal', 0, () => {
      // 正文去重：本机已有的跳过（不认领也不新落，R-OUTBOX-07）
      const existing = new Set<string>(['已有的回信']);
      const remote = [new RemoteLetter('已有的回信', '青鸟', 20_000)];
      const waiting = [new WaitingLetter('L1', 19_000)];
      const actions = reconcilePlan(remote, waiting, existing);
      expect(actions.length).assertEqual(1);
      expect(actions[0].kind).assertEqual(ReconcileActionKind.Skip);
      expect(actions[0].adoptLetterId).assertEqual('');
    })

    it('reconcileCreatesWhenNothingWaiting', 0, () => {
      const remote = [new RemoteLetter('别处的回信', '青鸟', 20_000)];
      const actions = reconcilePlan(remote, [], new Set<string>());
      expect(actions[0].kind).assertEqual(ReconcileActionKind.Create);
    })

    // ---- owns 口径（Returned / JustPosted 的门） ----

    it('ownedWritingAndBounceRequireOwnership', 0, () => {
      const writing = letter('L1', LetterStatus.Generating, '');
      const bounced = letter('L2', LetterStatus.Failed, '');
      const owned = new Set<string>(['L1', 'L2']);
      const none = new Set<string>();
      expect(isOwnedWriting(writing, owned)).assertTrue();
      expect(isOwnedWriting(writing, none)).assertFalse();
      expect(isOwnedBounce(bounced, owned)).assertTrue();
      expect(isOwnedBounce(bounced, none)).assertFalse();
      // 有正文的 failed 不算退回（那是服务端失败的旧信，不归卡片管）
      const filled = letter('L3', LetterStatus.Failed, '有正文');
      expect(isOwnedBounce(filled, owned)).assertFalse();
    })
  })
}
