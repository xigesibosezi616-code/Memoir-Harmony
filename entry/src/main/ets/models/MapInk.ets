/**
 * 地图上的墨色（U01 决策 15）：**跟着地图的白天黑夜走，不跟主题**（`MapDaylight`）。
 * 对应 iOS `PenPalMapMarks.swift` 的 `MapInk`。
 *
 * - 夜里的地图是深色，墨点、名字、航线就得是浅的才看得见；白天反过来
 * - 收件人用的邮戳色跟主题（素笺朱红 / 皮革赭黄 / 肯特灰蓝），夜里调亮一点
 * - 颜色一律存 `0xAARRGGBB` 数值：Map Kit 的航线要数值色，
 *   ArkUI 的 `ResourceColor` 也收数值，两边共用一套
 */

/** 「#RRGGBB」→ `0xFFRRGGBB`（postmarkInkHex / LetterPalette 的产物是这种写法） */
export function hexToArgb(hex: string): number {
  let digits = hex.startsWith('#') ? hex.substring(1) : hex;
  if (digits.length === 8) {
    return parseInt(digits, 16);
  }
  if (digits.length === 6) {
    return (0xFF000000 | parseInt(digits, 16)) >>> 0;
  }
  return 0xFF000000;
}

/** 换透明度：`alpha` 0…1（0.85 = 85% 不透明） */
export function withAlpha(argb: number, alpha: number): number {
  const a = Math.round(Math.min(Math.max(alpha, 0), 1) * 255);
  return ((a << 24) | (argb & 0x00FFFFFF)) >>> 0;
}

/** 往白色里掺 `fraction`（0…1）：夜里的邮戳色调亮一点（iOS `mix(with: .white, by:)` 同款） */
export function mixWithWhite(argb: number, fraction: number): number {
  const t = Math.min(Math.max(fraction, 0), 1);
  const r = argb & 0x00FF0000;
  const g = argb & 0x0000FF00;
  const b = argb & 0x000000FF;
  const mixedR = Math.round((r >> 16) * (1 - t) + 255 * t);
  const mixedG = Math.round((g >> 8) * (1 - t) + 255 * t);
  const mixedB = Math.round(b * (1 - t) + 255 * t);
  return ((argb & 0xFF000000) | (mixedR << 16) | (mixedG << 8) | mixedB) >>> 0;
}

/** 地图墨色一组（决策 15：夜里浅墨、白天深墨；收件人邮戳色跟主题） */
export class MapInk {
  /** 笔友的墨点、「你」 */
  readonly dot: number;
  /** 墨点外面那一圈 */
  readonly ring: number;
  /** 名字标签的底 */
  readonly tagPaper: number;
  /** 正在看、还没选的那一条航线 */
  readonly route: number;
  /** 收件人：墨点、航线、在路上的信 */
  readonly post: number;

  constructor(dot: number, ring: number, tagPaper: number, route: number, post: number) {
    this.dot = dot;
    this.ring = ring;
    this.tagPaper = tagPaper;
    this.route = route;
    this.post = post;
  }
}

/** 夜里的深墨（iOS 同值） */
export const MAP_INK_DARK: number = 0xFF2B241E;
/** 白天的浅墨（iOS 同值） */
export const MAP_INK_LIGHT: number = 0xFFF6F1E6;

/** 按白天黑夜取一组墨色；`postInkHex` 是 `postmarkInkHex(themeId)` 的产物 */
export function mapInkOf(night: boolean, postInkHex: string): MapInk {
  const postInk = hexToArgb(postInkHex);
  if (night) {
    return new MapInk(
      MAP_INK_LIGHT,
      MAP_INK_DARK,
      withAlpha(MAP_INK_DARK, 0.85),
      withAlpha(MAP_INK_LIGHT, 0.5),
      mixWithWhite(postInk, 0.35));
  }
  return new MapInk(
    MAP_INK_DARK,
    MAP_INK_LIGHT,
    withAlpha(MAP_INK_LIGHT, 0.92),
    withAlpha(MAP_INK_DARK, 0.35),
    postInk);
}
