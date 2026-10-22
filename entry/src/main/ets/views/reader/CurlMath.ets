/**
 * 翻页纯逻辑（10_BUILD_MANUAL.md 3.5）。
 * 华为阅读真机实测（1080px 屏，Mate X6）结论：
 *
 * 注（2026-10-23）：手势已统一走整页卷曲；下面「边折」只保留折缝几何公式，
 * 背面镜像 / 纸张半透由 `PageCurlNode` 绘制（不再是无背面的竖直切缝）。
 *
 * 边折（任意位置起手，统一整页卷曲）：折缝是贯穿全高的竖直直线
 * - 折缝跟手 = 拖拽增量半速（foldFromDrag）：从平出发，页缘起手
 *   退化为华为实测「对折中点」——forward 折缝 (W + 手指x) / 2，
 *   backward 上一页左缘固定在 0、折缝 = 手指x / 2
 * - 折缝右侧完整露出下一页（文字全对比度），仅叠一条
 *   「折缝处陡降至 9% 黑 → +20px 峰值 10% 黑 → +237px 衰减到 0」的
 *   纸底暗化渐变；折缝左侧当前页仅在最后 ~6px 有轻微压暗
 * - backward 是 forward 的镜像：折缝左侧是上一页，暗化渐变落在上一页，
 *   当前页只在折缝右侧留 ~6px 微暗缘（PageCurlNode 按 direction 反转）
 * - 首尾页越界用 boundaryFold：从页缘折起一小条（饱和阻尼，最多 0.16W），
 *   松手回弹，不换页
 *
 * 角卷（从屏角起手，华为实测 hc/hbl 抓拍 + 官方 A-K 模型）：
 * - 弧形折痕从抓取角向触点延伸；翻起部分显示背面
 *   （当前页截图镜像倒置 + 暗化，hc4 多模态确认）
 * - 抓角区 = 距屏角双轴 0.25 屏宽（(1050,120)=角、(1000,2000)=边，
 *   实测校准）；触点约束在 0.7 屏宽圆内（官方 0.6，华为 (600,700) 实测放宽）
 * - pathA = 折痕曲线这侧的当前页平面；pathC = 折痕曲线与弦 I-D 间的
 *   「背面带」（镜像内容 + 暗化）；曲线另一侧透出目标页
 * - 背面反射矩阵 = 对折线 E-H 的标准反射（把 F 映到 A，代数已验证）
 * 常量均按 1080px 实测值换算成页宽比例，任意分辨率自适应。
 */

/** 翻页方向：forward = 左滑看下一页；backward = 右滑回上一页 */
export enum PageCurlDirection {
  Forward = 'forward',
  Backward = 'backward'
}

/** 翻页模式：边折（竖直折缝）或角卷（A-K 圆锥卷页） */
export enum PageCurlMode {
  Edge = 'edge',
  Corner = 'corner'
}

/** 角卷抓取的屏角（forward 右角 / backward 左角） */
export enum PageCurlCorner {
  TopRight = 'topRight',
  BottomRight = 'bottomRight',
  TopLeft = 'topLeft',
  BottomLeft = 'bottomLeft'
}

/** 角落判定区：距屏角双轴 0.25 屏宽内算角落（Mate X6 实测校准） */
export const CORNER_ZONE_RATIO = 0.25;

/** 角卷触点约束圆半径比例（官方样例 0.6；华为真机实测 (600,700) 不被
 * 约束 —— 0.6 会浅 74px，跟手感到位取 0.7 屏宽） */
export const TOUCH_CIRCLE_RATIO = 0.7;

/** 渐变峰值距折缝的宽度比例（实测 20px @ 1080px 屏） */
export const CURL_PEAK_RATIO = 20 / 1080;

/** 渐变总宽比例（折缝 → 完全消失；实测 237px @ 1080px 屏） */
export const CURL_GRADIENT_RATIO = 237 / 1080;

/** 折缝左侧微暗缘宽比例（实测 6px @ 1080px 屏） */
export const CURL_EDGE_RATIO = 6 / 1080;

/** 首尾页越界最大折入比例（0.16 屏宽；再拖也只会到这条线，像纸被手指顶住） */
export const BOUNDARY_MAX_RATIO = 0.16;

function clampValue(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(v, lo), hi);
}

/**
 * 拖拽 → 折缝 x（px）。折缝从「平」出发、按拖拽增量半速跟手：
 * - forward（左滑看下一页）：fold = W − (startX − fingerX) / 2。
 *   起手时 fold = W（未翻）；页缘起手（startX = W）精确退化为华为实测
 *   「对折中点」公式 fold = (W + fingerX) / 2
 * - backward（右滑回上一页）：fold = (fingerX − startX) / 2。
 *   起手时 fold = 0（未翻）；页缘起手（startX = 0）退化为实测 fold = fingerX / 2
 * 中间任意位置起手都从平开始跟手，不瞬间跳到半翻状态
 * （角卷时代中间起手 = 页角突现，与手指脱节，用户报「无法翻页」的根因）。
 * 返回值夹在 [0, viewWidth]；viewWidth 非法时按 1 处理不越界。
 */
export function foldFromDrag(direction: PageCurlDirection, viewWidth: number,
  startX: number, fingerX: number): number {
  const w = Math.max(1, viewWidth);
  const raw = direction === PageCurlDirection.Forward
    ? w - (startX - fingerX) / 2
    : (fingerX - startX) / 2;
  return clampValue(raw, 0, w);
}

/**
 * 首尾页越界阻尼：手指位移 → 实际折入量（px）。
 * 起点 1:1 跟手，越拖越沉，最多 BOUNDARY_MAX_RATIO 屏宽 —— 像纸被页缘顶住，
 * 松手后 autoFlip(false) 原路弹回，不换页。
 */
export function boundaryOverscroll(distancePx: number, viewWidth: number): number {
  const w = Math.max(1, viewWidth);
  const max = BOUNDARY_MAX_RATIO * w;
  const d = Math.max(0, distancePx);
  return max * (1 - Math.exp(-d / max));
}

/** 首尾页越界折缝：forward 末页从右缘往左折，backward 首页从左缘往右折 */
export function boundaryFold(forward: boolean, viewWidth: number,
  startX: number, currentX: number): number {
  const w = Math.max(1, viewWidth);
  const distance = forward ? startX - currentX : currentX - startX;
  const pull = boundaryOverscroll(distance, w);
  return forward ? clampValue(w - pull, 0, w) : clampValue(pull, 0, w);
}

/** 补完缓动：快起慢收（甩出去后纸自己摊平） */
export function easeOutCubic(t: number): number {
  const x = clampValue(t, 0, 1);
  const inv = 1 - x;
  return 1 - inv * inv * inv;
}

/** 回弹缓动：两端慢中间快（纸被页缘拉回去，落位不硬） */
export function easeInOutCubic(t: number): number {
  const x = clampValue(t, 0, 1);
  if (x < 0.5) {
    return 4 * x * x * x;
  }
  return 1 - Math.pow(-2 * x + 2, 3) / 2;
}

/**
 * 补完 / 回弹时长（ms）：距离越远越久，松手速度越快越短；夹在 140~420ms。
 * 用时间基插值，120Hz / 掉帧都不会改变整体时长（替代按帧衰减 14% 的旧算法）。
 */
export function flipDurationMs(distancePx: number, viewWidthPx: number,
  velocityPxPerSec: number, commit: boolean): number {
  const w = Math.max(1, viewWidthPx);
  const travel = Math.min(1, Math.abs(distancePx) / w);
  const speed = Math.min(1, Math.abs(velocityPxPerSec) / (w * 1.8));
  const base = commit ? 300 : 260;
  const raw = base * (0.55 + 0.45 * travel) * (1 - 0.5 * speed);
  return Math.round(clampValue(raw, 140, 420));
}

// ---- 角卷（A-K 模型，官方仿真翻页样例同式；左/下角为镜像推广） ----

/** 平面点 */
export class CurlPoint {
  x: number;
  y: number;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

/** A-K 角卷全点：A 触点、F 抓取角、E/H 折线与两缘交点、
 * C/J 折线延点、B/K 折缘交点、D/I 曲线中点 */
export class CurlGeometry {
  A: CurlPoint = new CurlPoint(0, 0);
  F: CurlPoint = new CurlPoint(0, 0);
  B: CurlPoint = new CurlPoint(0, 0);
  C: CurlPoint = new CurlPoint(0, 0);
  D: CurlPoint = new CurlPoint(0, 0);
  E: CurlPoint = new CurlPoint(0, 0);
  H: CurlPoint = new CurlPoint(0, 0);
  I: CurlPoint = new CurlPoint(0, 0);
  J: CurlPoint = new CurlPoint(0, 0);
  K: CurlPoint = new CurlPoint(0, 0);
  /** |A-F|：卷起程度 */
  aToF: number = 0;
}

/** 抓取角坐标 */
export function cornerPoint(corner: PageCurlCorner, viewWidth: number,
  viewHeight: number): CurlPoint {
  const W = Math.max(1, viewWidth);
  const H = Math.max(1, viewHeight);
  switch (corner) {
    case PageCurlCorner.TopRight:
      return new CurlPoint(W, 0);
    case PageCurlCorner.BottomRight:
      return new CurlPoint(W, H);
    case PageCurlCorner.TopLeft:
      return new CurlPoint(0, 0);
    default:
      return new CurlPoint(0, H);
  }
}

/** 起手点是否落在角落区（方向须匹配：forward 右角 / backward 左角；
 * 不匹配或不在区内回 undefined = 边折）。实测校准：(1050,120) 右上角、
 * (1000,2000) 边缘、(1050,1200) 边缘 */
export function cornerAtStart(forward: boolean, startX: number, startY: number,
  viewWidth: number, viewHeight: number): PageCurlCorner | undefined {
  const W = Math.max(1, viewWidth);
  const H = Math.max(1, viewHeight);
  const zone = CORNER_ZONE_RATIO * W;
  const nearTop = startY < zone;
  const nearBottom = startY > H - zone;
  if (!nearTop && !nearBottom) {
    return undefined;
  }
  if (forward) {
    if (startX < W - zone) {
      return undefined;
    }
    return nearTop ? PageCurlCorner.TopRight : PageCurlCorner.BottomRight;
  }
  if (startX > zone) {
    return undefined;
  }
  return nearTop ? PageCurlCorner.TopLeft : PageCurlCorner.BottomLeft;
}

/** 官方触点约束：A 限制在 0.6 屏宽圆内（圆心在角侧缘上），
 * 限制卷页程度；tx 超出 sqrt 定义域时夹回，不出 NaN */
export function constrainTouchPoint(corner: PageCurlCorner, touchX: number, touchY: number,
  viewWidth: number, viewHeight: number): CurlPoint {
  const W = Math.max(1, viewWidth);
  const H = Math.max(1, viewHeight);
  const r = TOUCH_CIRCLE_RATIO * W;
  const left = corner === PageCurlCorner.TopLeft || corner === PageCurlCorner.BottomLeft;
  const bottom = corner === PageCurlCorner.BottomRight || corner === PageCurlCorner.BottomLeft;
  const cx = left ? r : W - r;
  let tx = clampValue(touchX, 0, W);
  if (tx < cx - r) {
    tx = cx - r;
  }
  if (tx > cx + r) {
    tx = cx + r;
  }
  const root = Math.sqrt(Math.max(0, r * r - (tx - cx) * (tx - cx)));
  let ty: number;
  if (bottom) {
    const minY = H - root;
    ty = touchY >= minY ? Math.min(touchY, H) : minY;
  } else {
    const maxY = root;
    ty = touchY <= maxY ? Math.max(touchY, 0) : maxY;
  }
  return new CurlPoint(tx, ty);
}

/** 两线交点（p1p2 × p3p4；平行时回中点兜底） */
function lineIntersect(p1: CurlPoint, p2: CurlPoint, p3: CurlPoint, p4: CurlPoint): CurlPoint {
  const d1x = p2.x - p1.x;
  const d1y = p2.y - p1.y;
  const d2x = p4.x - p3.x;
  const d2y = p4.y - p3.y;
  const denom = d1x * d2y - d1y * d2x;
  if (Math.abs(denom) < 1e-6) {
    return new CurlPoint((p1.x + p2.x) / 2, (p1.y + p2.y) / 2);
  }
  const t = ((p3.x - p1.x) * d2y - (p3.y - p1.y) * d2x) / denom;
  return new CurlPoint(p1.x + t * d1x, p1.y + t * d1y);
}

/** A-K 全点计算（官方 calcPointsXY 同式）。A 与 F 同轴时微扰避开除零。
 * 折线 = A-F 垂直平分线；E/H 为其与两缘交点，B/K 为折缘交点，
 * D/I 为 pathA 贝塞尔曲线中点（quadTo 半程点） */
export function computeCurlGeometry(corner: PageCurlCorner, A: CurlPoint,
  viewWidth: number, viewHeight: number): CurlGeometry {
  const W = Math.max(1, viewWidth);
  const H = Math.max(1, viewHeight);
  const g = new CurlGeometry();
  const F = cornerPoint(corner, W, H);
  g.A = A;
  g.F = F;
  let ax = A.x;
  let ay = A.y;
  if (Math.abs(ax - F.x) < 1) {
    ax = F.x + (ax >= F.x ? 1 : -1);
  }
  if (Math.abs(ay - F.y) < 1) {
    ay = F.y + (ay >= F.y ? 1 : -1);
  }
  const fx = F.x;
  const fy = F.y;
  const gx = (ax + fx) / 2;
  const gy = (ay + fy) / 2;
  g.E = new CurlPoint(gx - (fy - gy) * (fy - gy) / (fx - gx), fy);
  g.H = new CurlPoint(fx, gy - (fx - gx) * (fx - gx) / (fy - gy));
  g.C = new CurlPoint(g.E.x - (fx - g.E.x) / 2, fy);
  g.J = new CurlPoint(fx, g.H.y - (fy - g.H.y) / 2);
  const A2 = new CurlPoint(ax, ay);
  g.B = lineIntersect(A2, g.E, g.C, g.J);
  g.K = lineIntersect(A2, g.H, g.C, g.J);
  g.D = new CurlPoint((g.C.x + 2 * g.E.x + g.B.x) / 4, (2 * g.E.y + g.C.y + g.B.y) / 4);
  g.I = new CurlPoint((g.J.x + 2 * g.H.x + g.K.x) / 4, (2 * g.H.y + g.J.y + g.K.y) / 4);
  g.aToF = Math.hypot(ax - fx, ay - fy);
  return g;
}

/** 折线反射矩阵 9 值（行主序）：对折线 E-H 的标准反射，
 * 把正面翻成背面（F 恰好映到 A，代数已验证；四角通用） */
export function reflectionMatrixValues(geo: CurlGeometry): number[] {
  const eh = Math.hypot(geo.F.x - geo.E.x, geo.H.y - geo.F.y);
  if (eh < 1e-6) {
    return [1, 0, 0, 0, 1, 0, 0, 0, 1];
  }
  const sin0 = (geo.F.x - geo.E.x) / eh;
  const cos0 = (geo.H.y - geo.F.y) / eh;
  return [-(1 - 2 * sin0 * sin0), 2 * sin0 * cos0, 0,
    2 * sin0 * cos0, 1 - 2 * sin0 * sin0, 0,
    0, 0, 1];
}

/** 角卷进度：|A-F| / 屏对角线（0 = 未卷，1 = A 拖到对角） */
export function cornerProgress(corner: PageCurlCorner, A: CurlPoint,
  viewWidth: number, viewHeight: number): number {
  const W = Math.max(1, viewWidth);
  const H = Math.max(1, viewHeight);
  const F = cornerPoint(corner, W, H);
  return Math.hypot(A.x - F.x, A.y - F.y) / Math.hypot(W, H);
}
