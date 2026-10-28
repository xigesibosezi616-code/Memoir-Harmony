/**
 * 到达通知纯逻辑单测（10_BUILD_MANUAL.md 5.4；R-NOTIFY-01~05）。
 *
 * - arrivalRemindersOf：只挑在途信（写信中 / 已到不排），字段是值快照
 * - 注册表 decode/encode 往返 + 坏输入兜底空表
 * - planArrivalReschedule：同信复用同 notificationId（覆盖不重复）、新信递增取号、
 *   触发秒数 max(1, ceil(距离毫秒 / 1000))、已过到达时刻 → 1 秒
 */
import { describe, it, expect } from '@ohos/hypium';
import { Letter, LetterStatus } from '../../main/ets/models/Letter';
import {
  ArrivalReminder,
  arrivalRemindersOf,
  ArrivalNotifyRegistry,
  decodeArrivalNotifyRegistry,
  encodeArrivalNotifyRegistry,
  planArrivalReschedule
} from '../../main/ets/models/NotifyLogic';

const SENT_AT = 1_000_000;
const NOW = 2_000_000;

function makeLetter(id: string, status: LetterStatus, body: string,
  deliveredAt?: number): Letter {
  const letter = new Letter(id, SENT_AT, SENT_AT);
  letter.status = status;
  letter.body = body;
  letter.fromCharacter = '阿夏';
  if (deliveredAt !== undefined) {
    letter.deliveredAt = deliveredAt;
  }
  return letter;
}

export default function notifyLogicTest() {
  describe('NotifyLogicTest', () => {
    // ---- arrivalRemindersOf：只挑在途信，字段是值快照 ----

    it('arrivalRemindersOfPicksOnlyInTransitLetters', 0, () => {
      const inTransit = makeLetter('L1', LetterStatus.Pending, '在途', NOW + 500_000);
      const arrived = makeLetter('L2', LetterStatus.Delivered, '已到', NOW - 1);
      const writing = makeLetter('L3', LetterStatus.Generating, '');
      const bounced = makeLetter('L4', LetterStatus.Failed, '');
      const letters = [inTransit, arrived, writing, bounced];
      const reminders = arrivalRemindersOf(letters, NOW);
      expect(reminders.length).assertEqual(1);
      expect(reminders[0].letterId).assertEqual('L1');
      expect(reminders[0].triggerAtMs).assertEqual(NOW + 500_000);
      expect(reminders[0].penPalName).assertEqual('阿夏');
    })

    it('arrivalRemindersOfFallsBackToGeneratedAtWhenDeliveredAtMissing', 0, () => {
      // 老数据没有 deliveredAt → 按 generatedAt 算（等于早就到了，不会入选）
      const old = makeLetter('L1', LetterStatus.Pending, '老信');
      const reminders = arrivalRemindersOf([old], NOW);
      expect(reminders.length).assertEqual(0);
    })

    // ---- 注册表编解码 ----

    it('registryEncodeDecodeRoundTrips', 0, () => {
      const ids = new Map<string, number>();
      ids.set('L1', 1);
      ids.set('L2', 2);
      const registry = new ArrivalNotifyRegistry(3, ids);
      const decoded = decodeArrivalNotifyRegistry(encodeArrivalNotifyRegistry(registry));
      expect(decoded.nextNotifyId).assertEqual(3);
      expect(decoded.notifyIds.size).assertEqual(2);
      expect(decoded.notifyIds.get('L1')).assertEqual(1);
      expect(decoded.notifyIds.get('L2')).assertEqual(2);
    })

    it('registryDecodeToleratesBadInput', 0, () => {
      expect(decodeArrivalNotifyRegistry('').nextNotifyId).assertEqual(1);
      expect(decodeArrivalNotifyRegistry('not json').nextNotifyId).assertEqual(1);
      expect(decodeArrivalNotifyRegistry('{}').nextNotifyId).assertEqual(1);
      // next 非法（0 / 负数）→ 空表
      expect(decodeArrivalNotifyRegistry('{"v":1,"next":0}').nextNotifyId).assertEqual(1);
      // ids 里的脏值忽略，干净值保留
      const mixed = decodeArrivalNotifyRegistry(
        '{"v":1,"next":5,"ids":{"L1":3,"L2":"x","L3":-1}}');
      expect(mixed.nextNotifyId).assertEqual(5);
      expect(mixed.notifyIds.size).assertEqual(1);
      expect(mixed.notifyIds.get('L1')).assertEqual(3);
    })

    // ---- planArrivalReschedule：覆盖取号 + 触发秒数 ----

    it('planReusesNotifyIdForSameLetterAndAssignsIncreasingIds', 0, () => {
      const ids = new Map<string, number>();
      ids.set('L1', 4);
      const registry = new ArrivalNotifyRegistry(5, ids);
      const reminders = [
        new ArrivalReminder('L1', NOW + 90_000, '阿夏'),
        new ArrivalReminder('L2', NOW + 60_000, '阿秋')
      ];
      const plan = planArrivalReschedule(registry, reminders, NOW);
      // L1 复用旧号 4（覆盖不重复）；L2 从计数器取 5，计数器走 6
      expect(plan.toPublish.length).assertEqual(2);
      expect(plan.toPublish[0].notifyId).assertEqual(4);
      expect(plan.toPublish[1].notifyId).assertEqual(5);
      expect(plan.nextRegistry.nextNotifyId).assertEqual(6);
      expect(plan.nextRegistry.notifyIds.get('L1')).assertEqual(4);
      expect(plan.nextRegistry.notifyIds.get('L2')).assertEqual(5);
    })

    it('planComputesTriggerSecondsWithMinimumOne', 0, () => {
      const registry = ArrivalNotifyRegistry.empty();
      const reminders = [
        // 差 90_000ms → 90 秒
        new ArrivalReminder('L1', NOW + 90_000, '阿夏'),
        // 差 60_001ms → ceil 61 秒
        new ArrivalReminder('L2', NOW + 60_001, '阿夏'),
        // 已过到达时刻 → max(1, 负数) = 1 秒（马上弹）
        new ArrivalReminder('L3', NOW - 5_000, '阿夏'),
        // 正好整秒边界 → 30 秒
        new ArrivalReminder('L4', NOW + 30_000, '阿夏')
      ];
      const plan = planArrivalReschedule(registry, reminders, NOW);
      expect(plan.toPublish[0].triggerInSeconds).assertEqual(90);
      expect(plan.toPublish[1].triggerInSeconds).assertEqual(61);
      expect(plan.toPublish[2].triggerInSeconds).assertEqual(1);
      expect(plan.toPublish[3].triggerInSeconds).assertEqual(30);
    })

    it('planKeepsExistingRegistryEntriesNotInReminders', 0, () => {
      // 只加不减（iOS rescheduleInTransit 同款）：不在途的信留号，避免复用串台
      const ids = new Map<string, number>();
      ids.set('L0', 1);
      const registry = new ArrivalNotifyRegistry(2, ids);
      const plan = planArrivalReschedule(registry,
        [new ArrivalReminder('L1', NOW + 1000, '阿夏')], NOW);
      expect(plan.toPublish.length).assertEqual(1);
      expect(plan.nextRegistry.notifyIds.get('L0')).assertEqual(1);
      expect(plan.nextRegistry.notifyIds.get('L1')).assertEqual(2);
    })

    it('planWithEmptyRemindersChangesNothing', 0, () => {
      const ids = new Map<string, number>();
      ids.set('L1', 1);
      const registry = new ArrivalNotifyRegistry(2, ids);
      const plan = planArrivalReschedule(registry, [], NOW);
      expect(plan.toPublish.length).assertEqual(0);
      expect(plan.nextRegistry.nextNotifyId).assertEqual(2);
      expect(plan.nextRegistry.notifyIds.get('L1')).assertEqual(1);
    })

    it('planSnapshotsPenPalNamePerLetter', 0, () => {
      const registry = ArrivalNotifyRegistry.empty();
      const reminders = [
        new ArrivalReminder('L1', NOW + 1000, '阿夏'),
        new ArrivalReminder('L2', NOW + 2000, '阿秋')
      ];
      const plan = planArrivalReschedule(registry, reminders, NOW);
      expect(plan.toPublish[0].penPalName).assertEqual('阿夏');
      expect(plan.toPublish[1].penPalName).assertEqual('阿秋');
    })
  })
}
