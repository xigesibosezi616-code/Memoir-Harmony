/**
 * 书架拖动换位的纯逻辑（10_BUILD_MANUAL.md 3.2，R-BOOK-06）。
 * 对应 iOS `ShelfGridView.swift` 的顺序操作（`order.move` / `nearestBookIndex` /
 * 边缘自动滚）与 `BookshelfView.swift` 的 `saveOrder`。不依赖 ArkUI —— 单测覆盖。
 */

/** 一条 sortOrder 落库改动（只写真变了的那几条，少写库少触发同步） */
export class SortOrderChange {
  readonly id: string;
  readonly sortOrder: number;

  constructor(id: string, sortOrder: number) {
    this.id = id;
    this.sortOrder = sortOrder;
  }
}

/**
 * 把 order[from] 挪到「离松手位置最近的那本书」to 的格子上：
 * 这本书落在 to 那一格，被挤开的区间整体向 from 方向让位。
 * 对应 iOS `order.move(fromOffsets:, toOffset: to > from ? to + 1 : to)`
 * （toOffset 按原数组坐标理解就是这个语义）。from === to 或越界返回原顺序的拷贝。
 */
export function moveItem(order: string[], from: number, to: number): string[] {
  const copy: string[] = [];
  for (const id of order) {
    copy.push(id);
  }
  if (from < 0 || from >= copy.length || to < 0 || to >= copy.length || from === to) {
    return copy;
  }
  const item = copy[from];
  copy.splice(from, 1);
  copy.splice(to, 0, item);
  return copy;
}

/**
 * 松手落库：新顺序里 sortOrder = 下标（0, 1, 2…），只挑真变了的那几条
 * （iOS `saveOrder`）。currentSortOrders 里没有的 id 按变了算，一并返回。
 */
export function changedSortOrders(order: string[],
  currentSortOrders: Record<string, number>): SortOrderChange[] {
  const changes: SortOrderChange[] = [];
  for (let i = 0; i < order.length; i++) {
    const id = order[i];
    const current = currentSortOrders[id];
    if (current === undefined || current !== i) {
      changes.push(new SortOrderChange(id, i));
    }
  }
  return changes;
}

/**
 * 离 (x, y) 最近的候选下标；候选为空返回 -1，平手取靠前的。
 * 按最近而不是「落在哪一格里」：松在缝里、或拖到最后一本后面，
 * 也有个确定的去处（iOS `nearestBookIndex`）。
 */
export function nearestIndex(centersX: number[], centersY: number[],
  x: number, y: number): number {
  if (centersX.length === 0 || centersX.length !== centersY.length) {
    return -1;
  }
  let best = 0;
  let bestDist = Number.MAX_VALUE;
  for (let i = 0; i < centersX.length; i++) {
    const dx = centersX[i] - x;
    const dy = centersY[i] - y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist < bestDist) {
      bestDist = dist;
      best = i;
    }
  }
  return best;
}

/** 手指进入可视区上下这个边缘带（vp）才开始自动滚（iOS zone = 70） */
export const AUTO_SCROLL_ZONE: number = 70;

/**
 * 边缘自动滚速度（vp / 拍）：越靠边越快，2~12 夹取（iOS `updateAutoScroll`）。
 * 上边缘带负（往上滚），下边缘带正，带外 0。
 */
export function autoScrollSpeed(fingerY: number, viewportTop: number,
  viewportBottom: number): number {
  const topBand = viewportTop + AUTO_SCROLL_ZONE;
  if (fingerY < topBand) {
    return -Math.min(12, Math.max(2, (topBand - fingerY) / 6));
  }
  const bottomBand = viewportBottom - AUTO_SCROLL_ZONE;
  if (fingerY > bottomBand) {
    return Math.min(12, Math.max(2, (fingerY - bottomBand) / 6));
  }
  return 0;
}

/** scrollTo 目标夹取：不滚出 [0, maxScroll]；内容不满一屏时一律 0 */
export function clampedScrollOffset(target: number, maxScroll: number): number {
  const cap = maxScroll > 0 ? maxScroll : 0;
  if (target < 0) {
    return 0;
  }
  return target > cap ? cap : target;
}

/** ease-in-out：拿起 / 转回的转角帧动画用（iOS `.smooth` 手感的近似） */
export function easeInOutCubic(t: number): number {
  if (t <= 0) {
    return 0;
  }
  if (t >= 1) {
    return 1;
  }
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}
