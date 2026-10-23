/**
 * 大屏模式的配色计算（10_BUILD_MANUAL.md 3.6，R-HOME-06）。
 * 对应 iOS `ShowcaseView` 的 `tint` 链 + `UIColor.isLightColor`。
 *
 * 卡片底色 = 照片主色渐变叠在页面底色上（半透明），ArkUI 画渐变只能给
 * 具体色值——主题背景全是数字色（0xAARRGGBB，三主题实测），这里把
 * 「tint @ alpha 叠页面底」**预先合成成不透明色**再交给 linearGradient，
 * 照片下缘的溶解渐变才能和底色逐像素一致（无缝；盖近似色块会留分界，
 * iOS 注释里踩过）。
 */
import { AppTheme } from '../../../theme/AppTheme';
import { isLightHex } from '../../../services/DominantColor';

/** ResourceColor（数字 / '#RRGGBB'）→ 0xAARRGGBB；解析不了返回 undefined */
export function colorToArgb(color: ResourceColor): number | undefined {
  if (typeof color === 'number') {
    return color;
  }
  if (typeof color === 'string') {
    return parseHexColor(color);
  }
  return undefined;
}

/** '#RGB' / '#RRGGBB' / '#AARRGGBB' → 0xAARRGGBB；不合法返回 undefined */
export function parseHexColor(hex: string): number | undefined {
  let raw = hex;
  if (raw.length > 0 && raw[0] === '#') {
    raw = raw.substring(1);
  }
  if (raw.length === 3) {
    raw = `${raw[0]}${raw[0]}${raw[1]}${raw[1]}${raw[2]}${raw[2]}`;
  }
  if (raw.length === 6) {
    raw = `FF${raw}`;
  }
  if (raw.length !== 8) {
    return undefined;
  }
  const value = Number.parseInt(raw, 16);
  return Number.isNaN(value) ? undefined : value;
}

/**
 * 「fg @ alpha 叠在 base 上」合成不透明色（0xFF 前缀）。iOS 的
 * `tint.opacity(a)` 叠页面底色的等价物。fg/base 传 0xRRGGBB / 0xAARRGGBB。
 */
export function blendOver(fgArgb: number, alpha: number, baseArgb: number): number {
  const clamped = Math.min(1, Math.max(0, alpha));
  const fr = (fgArgb >> 16) & 0xFF;
  const fg = (fgArgb >> 8) & 0xFF;
  const fb = fgArgb & 0xFF;
  const br = (baseArgb >> 16) & 0xFF;
  const bg = (baseArgb >> 8) & 0xFF;
  const bb = baseArgb & 0xFF;
  const r = Math.round(fr * clamped + br * (1 - clamped));
  const g = Math.round(fg * clamped + bg * (1 - clamped));
  const b = Math.round(fb * clamped + bb * (1 - clamped));
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

/** 大屏卡片的底色梯度：tint 72% → 94% 叠页面底（合成不透明，[上, 下]） */
export function cardTintGradient(tintArgb: number, pageBgArgb: number): number[] {
  return [blendOver(tintArgb, 0.72, pageBgArgb), blendOver(tintArgb, 0.94, pageBgArgb)];
}

/**
 * 照片下缘溶解渐变的**底端色**：卡片底色梯度在照片区底缘（占卡高 ratio
 * 处）的取值。溶解 overlay 从透明渐到这个不透明色，和底色严丝合缝。
 */
export function dissolveEndColor(tintArgb: number, pageBgArgb: number,
  ratio: number): number {
  const alpha = 0.72 + (0.94 - 0.72) * Math.min(1, Math.max(0, ratio));
  return blendOver(tintArgb, alpha, pageBgArgb);
}

/** 没照片时的心情色斜向渐变（70% → 30%，叠页面底） */
export function moodCoverGradient(moodArgb: number, pageBgArgb: number): number[] {
  return [blendOver(moodArgb, 0.7, pageBgArgb), blendOver(moodArgb, 0.3, pageBgArgb)];
}

/**
 * 染色偏亮用深字、偏暗用浅字（iOS `TextColors`）。🔴 不能用主题文字色：
 * 那套是给纸面底设计的，压在深蓝夜景染出的底上会糊。
 */
export class TintTextColors {
  readonly title: number;
  readonly meta: number;
  readonly body: number;

  constructor(light: boolean) {
    if (light) {
      this.title = 0xFF1A1A1A;   // Color(white: 0.10)
      this.meta = 0xFF666666;    // Color(white: 0.40)
      this.body = 0xFF424242;    // Color(white: 0.26)
    } else {
      this.title = 0xFFFFFFFF;
      this.meta = 0xFFD1D1D1;    // Color(white: 0.82)
      this.body = 0xFFF0F0F0;    // Color(white: 0.94)
    }
  }
}

/** 染色（'#RRGGBB'）压深字还是浅字；非法色按偏亮兜底（深字更安全） */
export function tintTextColorsFor(tintHex: string): TintTextColors {
  return new TintTextColors(isLightHex(tintHex));
}

/**
 * 大屏卡片整体染色链（R-HOME-06）：照片主色 → 已知照片底色 →
 * 心情色（digest 已兜底预设色）→ 主题 accent。返回 '#RRGGBB'。
 */
export function resolveTintHex(photoTintHex: string | undefined,
  knownTintHex: string | undefined, moodColorHex: string,
  theme: AppTheme): string {
  if (photoTintHex !== undefined && photoTintHex.length > 0) {
    return photoTintHex;
  }
  if (knownTintHex !== undefined && knownTintHex.length > 0) {
    return knownTintHex;
  }
  if (moodColorHex.length > 0) {
    return moodColorHex;
  }
  const accent = colorToArgb(theme.accent);
  if (accent !== undefined) {
    return `#${(accent & 0xFFFFFF).toString(16).padStart(6, '0')}`;
  }
  return '#808080';
}
