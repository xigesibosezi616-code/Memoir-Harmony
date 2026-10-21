/**
 * 书架拖动换位纯逻辑单测（10_BUILD_MANUAL.md 3.2）。
 * 覆盖：moveItem 落点语义（前移 / 后移都落在目标格）、只写变了的 sortOrder、
 * 最近格判定（含缝里 / 平手）、边缘自动滚速度（带内带外 / 夹取）、滚动目标夹取、
 * ease-in-out 端点。对应 iOS `ShelfGridView.swift` 的顺序操作。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  AUTO_SCROLL_ZONE,
  SortOrderChange,
  autoScrollSpeed,
  changedSortOrders,
  clampedScrollOffset,
  easeInOutCubic,
  moveItem,
  nearestIndex
} from '../../main/ets/models/ShelfDrag';

export default function shelfDragTest() {
  describe('ShelfDragTest', () => {
    it('moveItemForwardLandsOnTargetSlot', 0, () => {
      // A 拖到 C（下标 2）上松手：A 落在 C 的旧格（下标 2），B 让位到 0
      const result = moveItem(['a', 'b', 'c', 'd', 'e'], 0, 2);
      expect(result.join(',')).assertEqual('b,c,a,d,e');
    })

    it('moveItemBackwardLandsOnTargetSlot', 0, () => {
      // E 拖到 C（下标 2）上松手：E 落在 C 的旧格，C/D 顺次后移
      const result = moveItem(['a', 'b', 'c', 'd', 'e'], 4, 2);
      expect(result.join(',')).assertEqual('a,b,e,c,d');
    })

    it('moveItemAdjacentSwap', 0, () => {
      expect(moveItem(['a', 'b', 'c'], 0, 1).join(',')).assertEqual('b,a,c');
      expect(moveItem(['a', 'b', 'c'], 2, 1).join(',')).assertEqual('a,c,b');
    })

    it('moveItemSameSlotReturnsSameOrder', 0, () => {
      const result = moveItem(['a', 'b', 'c'], 1, 1);
      expect(result.join(',')).assertEqual('a,b,c');
    })

    it('moveItemOutOfBoundsReturnsCopy', 0, () => {
      expect(moveItem(['a', 'b'], -1, 0).join(',')).assertEqual('a,b');
      expect(moveItem(['a', 'b'], 0, 9).join(',')).assertEqual('a,b');
      expect(moveItem([], 0, 0).length).assertEqual(0);
    })

    it('moveItemDoesNotMutateInput', 0, () => {
      const order: string[] = ['a', 'b', 'c'];
      const result = moveItem(order, 0, 2);
      expect(order.join(',')).assertEqual('a,b,c');
      expect(result.join(',')).assertEqual('b,c,a');
    })

    it('changedSortOrdersOnlyReportsChanged', 0, () => {
      // 新顺序 [b, a, c]：b 0、a 1 都变了；c 仍是 2，不写
      const current: Record<string, number> = { 'a': 0, 'b': 1, 'c': 2 };
      const changes = changedSortOrders(['b', 'a', 'c'], current);
      expect(changes.length).assertEqual(2);
      expect(changes[0].id).assertEqual('b');
      expect(changes[0].sortOrder).assertEqual(0);
      expect(changes[1].id).assertEqual('a');
      expect(changes[1].sortOrder).assertEqual(1);
    })

    it('changedSortOrdersAllMatchReturnsEmpty', 0, () => {
      const current: Record<string, number> = { 'a': 0, 'b': 1 };
      expect(changedSortOrders(['a', 'b'], current).length).assertEqual(0);
    })

    it('changedSortOrdersHandlesSparseLegacyValues', 0, () => {
      // 老数据 sortOrder 全是 0：挪成 [b, c, a] 只需要写 c→1、a→2
      //（b 的 0 已是目标下标，iOS saveOrder 同样跳过 sortOrder == index 的条目），
      // 落库后 b:0 c:1 a:2 排序正好是 [b, c, a]
      const current: Record<string, number> = { 'a': 0, 'b': 0, 'c': 0 };
      const changes = changedSortOrders(['b', 'c', 'a'], current);
      expect(changes.length).assertEqual(2);
      expect(changes[0].id).assertEqual('c');
      expect(changes[0].sortOrder).assertEqual(1);
      expect(changes[1].id).assertEqual('a');
      expect(changes[1].sortOrder).assertEqual(2);
    })

    it('changedSortOrdersMissingIdReported', 0, () => {
      const changes = changedSortOrders(['x'], {});
      expect(changes.length).assertEqual(1);
      expect(changes[0].id).assertEqual('x');
      expect(changes[0].sortOrder).assertEqual(0);
    })

    it('changedSortOrdersEmptyOrderReturnsEmpty', 0, () => {
      expect(changedSortOrders([], { 'a': 0 }).length).assertEqual(0);
    })

    it('nearestIndexPicksClosest', 0, () => {
      // 格子中心 (0,0) (100,0)：松手在 (60, 5)，离第二个更近
      expect(nearestIndex([0, 100], [0, 0], 60, 5)).assertEqual(1);
      expect(nearestIndex([0, 100], [0, 0], 40, -20)).assertEqual(0);
    })

    it('nearestIndexEmptyReturnsMinusOne', 0, () => {
      expect(nearestIndex([], [], 10, 10)).assertEqual(-1);
    })

    it('nearestIndexTiePicksFirst', 0, () => {
      expect(nearestIndex([0, 20], [0, 0], 10, 0)).assertEqual(0);
    })

    it('nearestIndexMismatchedAxesReturnsMinusOne', 0, () => {
      expect(nearestIndex([0, 20], [0], 10, 0)).assertEqual(-1);
    })

    it('autoScrollSpeedZeroInsideBand', 0, () => {
      // 视口 [0, 800]：安全带是 (70, 730)，带内不滚
      expect(autoScrollSpeed(400, 0, 800)).assertEqual(0);
      expect(autoScrollSpeed(70, 0, 800)).assertEqual(0);
      expect(autoScrollSpeed(730, 0, 800)).assertEqual(0);
    })

    it('autoScrollSpeedTopBandNegativeAndClamped', 0, () => {
      // 刚进带（70 内）= 最小速度 2；越靠边越快，远超带外夹到 12
      expect(autoScrollSpeed(69, 0, 800)).assertClose(-2, 0.0001);
      expect(autoScrollSpeed(34, 0, 800)).assertClose(-6, 0.0001);
      expect(autoScrollSpeed(-500, 0, 800)).assertEqual(-12);
    })

    it('autoScrollSpeedBottomBandPositiveAndClamped', 0, () => {
      expect(autoScrollSpeed(731, 0, 800)).assertClose(2, 0.0001);
      expect(autoScrollSpeed(766, 0, 800)).assertClose(6, 0.0001);
      expect(autoScrollSpeed(2000, 0, 800)).assertEqual(12);
    })

    it('autoScrollSpeedZoneMatchesIos', 0, () => {
      expect(AUTO_SCROLL_ZONE).assertEqual(70);
    })

    it('clampedScrollOffsetBounds', 0, () => {
      expect(clampedScrollOffset(-5, 300)).assertEqual(0);
      expect(clampedScrollOffset(50, 300)).assertEqual(50);
      expect(clampedScrollOffset(999, 300)).assertEqual(300);
      // 内容不满一屏：maxScroll < 0 → 恒 0
      expect(clampedScrollOffset(50, -20)).assertEqual(0);
      expect(clampedScrollOffset(50, 0)).assertEqual(0);
    })

    it('easeInOutCubicEndpointsAndMiddle', 0, () => {
      expect(easeInOutCubic(0)).assertEqual(0);
      expect(easeInOutCubic(1)).assertEqual(1);
      expect(easeInOutCubic(-0.5)).assertEqual(0);
      expect(easeInOutCubic(1.5)).assertEqual(1);
      expect(easeInOutCubic(0.5)).assertClose(0.5, 0.0001);
    })
  })
}
