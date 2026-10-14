/**
 * LetterDelivery 阶段判定单测（10_BUILD_MANUAL.md 1.3）。
 *
 * 🔴 阶段判定是跨端行为规则（05_DATA_MODEL.md §6.1），五个判定逐一对表：
 * hasArrived / isInTransit / isUnread / isWriting / isBounced，
 * 外加到达时刻的 [6h, 72h] 随机窗口与 timeScale。
 */
import { describe, it, expect } from '@ohos/hypium';
import { Letter, LetterStatus, letterStationery, LetterStationeryKind } from '../../main/ets/models/Letter';
import { LetterDelivery } from '../../main/ets/models/LetterDelivery';

const SENT_AT = 1_000_000; // 毫秒

function makeLetter(status: LetterStatus, body: string): Letter {
  const letter = new Letter('L1', SENT_AT, SENT_AT);
  letter.status = status;
  letter.body = body;
  return letter;
}

export default function letterDeliveryTest() {
  describe('LetterDeliveryTest', () => {
    // ---- 到达时刻：寄出后 [6 小时, 3 天] 均匀随机 ----

    it('arrivalDatePicksRandomDelayInWindow', 0, () => {
      const minMs = LetterDelivery.minimumDelaySec * 1000;
      const maxMs = LetterDelivery.maximumDelaySec * 1000;
      // random=0 → 正好 6 小时；random=0.5 → 窗口中点
      expect(LetterDelivery.arrivalDate(SENT_AT, 1, () => 0)).assertEqual(SENT_AT + minMs);
      const mid = LetterDelivery.arrivalDate(SENT_AT, 1, () => 0.5);
      expect(mid).assertEqual(SENT_AT + (minMs + maxMs) / 2);
      const nearMax = LetterDelivery.arrivalDate(SENT_AT, 1, () => 0.999999);
      expect(nearMax > SENT_AT + maxMs - 1000).assertTrue();
    })

    it('arrivalDateCompressesTimeByScale', 0, () => {
      const minMs = LetterDelivery.minimumDelaySec * 1000;
      // 测试加速（5.8）：timeScale 压缩等待时长
      expect(LetterDelivery.arrivalDate(SENT_AT, 10, () => 0)).assertEqual(SENT_AT + minMs / 10);
    })

    it('delayWindowConstants', 0, () => {
      expect(LetterDelivery.minimumDelaySec).assertEqual(6 * 3600);
      expect(LetterDelivery.maximumDelaySec).assertEqual(72 * 3600);
      expect(LetterDelivery.maximumEntriesPerLetter).assertEqual(14);
    })

    // ---- 真正的信：有正文且 status ∈ {pending, delivered, read} ----

    it('isRealLetterRequiresBodyAndKnownStatus', 0, () => {
      expect(LetterDelivery.isRealLetter(makeLetter(LetterStatus.Pending, '回信'))).assertTrue();
      expect(LetterDelivery.isRealLetter(makeLetter(LetterStatus.Delivered, '回信'))).assertTrue();
      expect(LetterDelivery.isRealLetter(makeLetter(LetterStatus.Read, '回信'))).assertTrue();
      // 空正文：老流程残留，不算寄出过
      expect(LetterDelivery.isRealLetter(makeLetter(LetterStatus.Pending, ''))).assertFalse();
      expect(LetterDelivery.isRealLetter(makeLetter(LetterStatus.Generating, '回信'))).assertFalse();
      expect(LetterDelivery.isRealLetter(makeLetter(LetterStatus.Failed, '回信'))).assertFalse();
      const unknown = makeLetter(LetterStatus.Pending, '回信');
      unknown.status = 'archived'; // 不认识的值一律不算
      expect(LetterDelivery.isRealLetter(unknown)).assertFalse();
    })

    // ---- 五个阶段判定（05 §6.1 的表） ----

    it('hasArrivedAndIsInTransitSplitByArrivalTime', 0, () => {
      const arrived = makeLetter(LetterStatus.Delivered, '回信');
      arrived.deliveredAt = SENT_AT + 3600_000;
      expect(LetterDelivery.hasArrived(arrived, SENT_AT + 7200_000)).assertTrue();
      expect(LetterDelivery.isInTransit(arrived, SENT_AT + 7200_000)).assertFalse();
      const inTransit = makeLetter(LetterStatus.Pending, '回信');
      inTransit.deliveredAt = SENT_AT + 72 * 3600_000;
      expect(LetterDelivery.hasArrived(inTransit, SENT_AT)).assertFalse();
      expect(LetterDelivery.isInTransit(inTransit, SENT_AT)).assertTrue();
    })

    it('arrivalOfFallsBackToGeneratedAtForOldRows', 0, () => {
      const old = makeLetter(LetterStatus.Delivered, '回信'); // 没有 deliveredAt
      expect(LetterDelivery.arrivalOf(old)).assertEqual(SENT_AT);
      const fresh = makeLetter(LetterStatus.Delivered, '回信');
      fresh.deliveredAt = SENT_AT + 123;
      expect(LetterDelivery.arrivalOf(fresh)).assertEqual(SENT_AT + 123);
    })

    it('isUnreadRequiresArrivedAndNotRead', 0, () => {
      const unread = makeLetter(LetterStatus.Delivered, '回信');
      unread.deliveredAt = SENT_AT - 1000;
      expect(LetterDelivery.isUnread(unread, SENT_AT)).assertTrue();
      const read = makeLetter(LetterStatus.Read, '回信');
      read.deliveredAt = SENT_AT - 1000;
      expect(LetterDelivery.isUnread(read, SENT_AT)).assertFalse();
      const notYet = makeLetter(LetterStatus.Delivered, '回信');
      notYet.deliveredAt = SENT_AT + 1000;
      expect(LetterDelivery.isUnread(notYet, SENT_AT)).assertFalse();
    })

    it('isWritingIsGeneratingWithEmptyBody', 0, () => {
      expect(LetterDelivery.isWriting(makeLetter(LetterStatus.Generating, ''))).assertTrue();
      expect(LetterDelivery.isWriting(makeLetter(LetterStatus.Generating, '写好了'))).assertFalse();
      expect(LetterDelivery.isWriting(makeLetter(LetterStatus.Pending, ''))).assertFalse();
    })

    it('isBouncedIsFailedWithEmptyBody', 0, () => {
      expect(LetterDelivery.isBounced(makeLetter(LetterStatus.Failed, ''))).assertTrue();
      expect(LetterDelivery.isBounced(makeLetter(LetterStatus.Failed, '有正文'))).assertFalse();
      expect(LetterDelivery.isBounced(makeLetter(LetterStatus.Generating, ''))).assertFalse();
    })

    // ---- 信纸快照（寄出时定死） ----

    it('stationerySnapshotAtSendTime', 0, () => {
      expect(letterStationery(true)).assertEqual(LetterStationeryKind.Sealed);
      expect(letterStationery(false)).assertUndefined();
      const sealed = makeLetter(LetterStatus.Delivered, '回信');
      sealed.stationery = letterStationery(true);
      expect(sealed.isSealed).assertTrue();
    })
  })
}
