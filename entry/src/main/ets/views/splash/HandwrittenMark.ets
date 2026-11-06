/**
 * 手写的「m.」—— 桌面图标上那一笔，开场时一笔写出来，再落下句点（U09 R-APP-10）。
 * 对应 iOS `Views/Splash/HandwrittenMark.swift`（和 `Scripts/make_app_icon.py` 的
 * `STROKE` 是同一份数据）—— 🔴 改一处要改另一处，图标和开场才对得上。
 *
 * 画法：四段三次贝塞尔当中线，沿中线每隔 1 格盖一个圆（364 的格子），圆半径沿弧长
 * 插值、整体 ×1.35（用户在原粗细和加粗之间选了加粗）—— 一支圆头笔写出来的样子。
 * 时间表在 `Script`；🔴 声音 `rawfile/splash_write.wav` 按同一张表合成，改表要重出声音。
 */

/** 格子里的一个点 */
class Pt {
  x: number;
  y: number;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

/** 每段（起点、中点、终点）的笔宽半径，段内按弧长线性插值 */
class RadiusProfile {
  start: number;
  mid: number;
  end: number;

  constructor(start: number, mid: number, end: number) {
    this.start = start;
    this.mid = mid;
    this.end = end;
  }
}

/** 沿中线的一个取样圆 */
class MarkSample {
  point: Pt;
  radius: number;
  /** 从这一段起点走了多远（格子单位） */
  distance: number;

  constructor(point: Pt, radius: number, distance: number) {
    this.point = point;
    this.radius = radius;
    this.distance = distance;
  }
}

/** 笔画整体加粗（用户在原粗细和 1.35 倍之间选了加粗） */
export const MARK_WEIGHT: number = 1.35;

/** 起笔 → 第一个尖 → 底下的折角 → 第二个尖 → 收笔的小勾。每段 [起点, 控制点, 控制点, 终点] */
const SEGMENTS: Pt[][] = [
  [new Pt(66.25, 241.5), new Pt(89.25, 211.38), new Pt(136.0, 154.5), new Pt(174.62, 143.12)],
  [new Pt(174.62, 143.12), new Pt(175.31, 166.25), new Pt(161.25, 205.62), new Pt(163.56, 221.62)],
  [new Pt(163.56, 221.62), new Pt(194.69, 195.25), new Pt(219.94, 161.25), new Pt(248.38, 151.75)],
  [new Pt(248.38, 151.75), new Pt(249.44, 202.19), new Pt(249.0, 219.5), new Pt(257.19, 221.31)],
];

const RADII: RadiusProfile[] = [
  new RadiusProfile(6.975, 8.2, 8.934),
  new RadiusProfile(8.934, 10.091, 10.55),
  new RadiusProfile(10.55, 8.553, 10.066),
  new RadiusProfile(10.066, 10.288, 10.297),
];

/** 句点（写完 m 抬笔后落下） */
export const DOT_CENTER: Pt = new Pt(305.375, 228.75);
export const DOT_RADIUS: number = 12.2 * MARK_WEIGHT;

/** 整个字（含句点、含笔画粗细）在格子里占的框，画的时候按它缩放、居中 */
export const MARK_BOUNDS_X: number = 52.0;
export const MARK_BOUNDS_Y: number = 128.9;
export const MARK_BOUNDS_W: number = 321.9 - 52.0;
export const MARK_BOUNDS_H: number = 255.7 - 128.9;

/** 先密密地取参数点、量出弧长，再按等弧长每隔 1 格重取 */
function sampleSegment(index: number): MarkSample[] {
  const p: Pt[] = SEGMENTS[index];
  const dense = 600;
  const points: Pt[] = [];
  const cumulative: number[] = [0];
  for (let i = 0; i <= dense; i++) {
    const t = i / dense;
    const u = 1 - t;
    const a = u * u * u;
    const b = 3 * u * u * t;
    const c = 3 * u * t * t;
    const d = t * t * t;
    const point = new Pt(
      a * p[0].x + b * p[1].x + c * p[2].x + d * p[3].x,
      a * p[0].y + b * p[1].y + c * p[2].y + d * p[3].y
    );
    if (points.length > 0) {
      const last = points[points.length - 1];
      cumulative.push(cumulative[cumulative.length - 1] +
        Math.hypot(point.x - last.x, point.y - last.y));
    }
    points.push(point);
  }
  const total = cumulative[cumulative.length - 1];
  const r = RADII[index];
  const result: MarkSample[] = [];
  let j = 0;
  let s = 0;
  while (true) {
    const target = Math.min(s, total);
    while (j < cumulative.length - 2 && cumulative[j + 1] < target) {
      j++;
    }
    const span = cumulative[j + 1] - cumulative[j];
    const f = span > 0 ? (target - cumulative[j]) / span : 0;
    const point = new Pt(
      points[j].x + (points[j + 1].x - points[j].x) * f,
      points[j].y + (points[j + 1].y - points[j].y) * f
    );
    const u = target / total;
    const radius = u < 0.5
      ? r.start + (r.mid - r.start) * u / 0.5
      : r.mid + (r.end - r.mid) * (u - 0.5) / 0.5;
    result.push(new MarkSample(point, radius * MARK_WEIGHT, target));
    if (target >= total) {
      break;
    }
    s += 1;
  }
  return result;
}

/** 每段沿弧长每隔 1 格一个圆（屏幕上不到 1vp，看不出圆和圆的接缝） */
export const MARK_SAMPLES: MarkSample[][] = SEGMENTS.map((_seg: Pt[], i: number): MarkSample[] => sampleSegment(i));

/** 每段的长度（格子单位） */
export const MARK_LENGTHS: number[] = MARK_SAMPLES.map((line: MarkSample[]): number =>
  line.length > 0 ? line[line.length - 1].distance : 0);

/**
 * 开场写字的时间表（U09 R-APP-10）。🔴 `splash_write.wav` 按同一张表合成。
 */
export class MarkScript {
  /** 四段各写多久（秒）。按段长的 0.8 次方分（长的那段写得快一些），合计约 0.42 秒 */
  static readonly SEGMENT_DURATIONS: number[] = [0.142, 0.086, 0.113, 0.080];
  /** 段内快慢：一段里笔先快后慢，到拐角几乎停住（真写字时笔在尖角处会顿一下） */
  static readonly EASE: number = 0.85;
  /** 写完 m 抬笔、挪到句点的空当 */
  static readonly PEN_LIFT: number = 0.07;
  /** 句点：笔尖点下去，墨在这么短的时间里洇开 */
  static readonly DOT_DURATION: number = 0.05;
  /** 写完停一下再淡出：让人看清写好的字再进 App */
  static readonly HOLD: number = 0.35;

  static writingDuration(): number {
    let sum = 0;
    for (const d of MarkScript.SEGMENT_DURATIONS) {
      sum += d;
    }
    return sum;
  }

  static dotStart(): number {
    return MarkScript.writingDuration() + MarkScript.PEN_LIFT;
  }

  /** 从开始写第一笔到写完停够的总时长 */
  static total(): number {
    return MarkScript.dotStart() + MarkScript.DOT_DURATION + MarkScript.HOLD;
  }

  /** 第几段写到了多远（格子单位）。段内走过的比例 = τ − ease·sin(2πτ)/(2π)，两头慢中间快 */
  static drawnLength(segment: number, time: number): number {
    let start = 0;
    for (let i = 0; i < segment; i++) {
      start += MarkScript.SEGMENT_DURATIONS[i];
    }
    const duration = MarkScript.SEGMENT_DURATIONS[segment];
    const tau = Math.min(Math.max((time - start) / duration, 0), 1);
    const progress = tau - MarkScript.EASE * Math.sin(2 * Math.PI * tau) / (2 * Math.PI);
    return MARK_LENGTHS[segment] * progress;
  }

  /** 句点洇开到多大（0…1）：笔尖一点下去就有一小团墨，随后很快洇满，不回弹 */
  static dotScale(time: number): number {
    const dotStart = MarkScript.dotStart();
    if (time < dotStart) {
      return 0;
    }
    const x = Math.min((time - dotStart) / MarkScript.DOT_DURATION, 1);
    return 0.4 + 0.6 * (1 - Math.pow(1 - x, 3));
  }
}

/** ink 是 ResourceColor，画布只收 string | number；当前四主题的墨色都是色值数字 */
function inkFillStyle(ink: ResourceColor): string | number {
  if (typeof ink === 'number' || typeof ink === 'string') {
    return ink;
  }
  // Resource 兜底：素笺的字色（四主题实际都不会走到这里）
  return '#8B7E6A';
}

/**
 * 把写到 `time` 秒时的样子画进 `width × height` 的画布（字按 bounds 等比铺满画布）。
 * ink 是主题字色（R-THEME-13 的表）。
 */
export function drawHandwrittenMark(ctx: CanvasRenderingContext2D, width: number, height: number,
  time: number, ink: ResourceColor): void {
  const scale = Math.min(width / MARK_BOUNDS_W, height / MARK_BOUNDS_H);
  const originX = (width - MARK_BOUNDS_W * scale) / 2 - MARK_BOUNDS_X * scale;
  const originY = (height - MARK_BOUNDS_H * scale) / 2 - MARK_BOUNDS_Y * scale;

  ctx.fillStyle = inkFillStyle(ink);
  ctx.beginPath();
  const fullCircle = 2 * Math.PI;
  for (let segment = 0; segment < MARK_SAMPLES.length; segment++) {
    const drawn = MarkScript.drawnLength(segment, time);
    if (drawn <= 0) {
      break;
    }
    const line = MARK_SAMPLES[segment];
    let last: MarkSample | undefined = undefined;
    for (const sample of line) {
      if (sample.distance > drawn) {
        break;
      }
      const cx = originX + sample.point.x * scale;
      const cy = originY + sample.point.y * scale;
      const r = sample.radius * scale;
      ctx.moveTo(cx + r, cy);
      ctx.arc(cx, cy, r, 0, fullCircle);
      last = sample;
    }
    // 笔尖：落在两个取样点之间时补一个圆，写的过程才是连续的
    let next: MarkSample | undefined = undefined;
    for (const sample of line) {
      if (sample.distance > drawn) {
        next = sample;
        break;
      }
    }
    if (last !== undefined && next !== undefined) {
      const f = (drawn - last.distance) / (next.distance - last.distance);
      const cx = originX + (last.point.x + (next.point.x - last.point.x) * f) * scale;
      const cy = originY + (last.point.y + (next.point.y - last.point.y) * f) * scale;
      const r = (last.radius + (next.radius - last.radius) * f) * scale;
      ctx.moveTo(cx + r, cy);
      ctx.arc(cx, cy, r, 0, fullCircle);
    }
  }
  const dot = MarkScript.dotScale(time);
  if (dot > 0) {
    const cx = originX + DOT_CENTER.x * scale;
    const cy = originY + DOT_CENTER.y * scale;
    const r = DOT_RADIUS * dot * scale;
    ctx.moveTo(cx + r, cy);
    ctx.arc(cx, cy, r, 0, fullCircle);
  }
  ctx.fill();
}
