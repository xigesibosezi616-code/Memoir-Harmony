/**
 * 照片底部主色 + 感知亮度（10_BUILD_MANUAL.md 3.6，R-HOME-06）。对应 iOS
 * `Views/Components/DominantColor.swift` + `ShowcaseView.swift` 的 `isLightColor`。
 *
 * - 只取照片**底部三分之一**的平均色：文字区紧接在图片下缘，取那一带的
 *   颜色才能接得上；全图平均会「天空是蓝的、文字区却土黄」
 * - 平均色天生偏灰偏暗，两步修成「能用的染色」：饱和度 ×1.4 收进
 *   [0.20, 0.72]、亮度收进 [0.38, 0.86] —— 否则夜景染出死黑（字看不清）、
 *   雪景染了等于没染
 * - 深浅字判定用 ITU-R BT.601 加权感知亮度，不是 (r+g+b)/3 ——
 *   人眼对绿最敏感、对蓝最迟钝，平均会把饱和的蓝判成「亮」，压白字就看不清
 *
 * 全部纯函数：像素平均、色值换算单测跑穿；读像素在 EntryPhotoStore 后台做。
 */

/**
 * 一个像素区域（**BGRA_8888** 紧排——鸿蒙 `PixelMap.readPixels` 固定按
 * BGRA 写入缓冲区，与 iOS 的 RGBA 相反，红蓝两个下标不能照抄）的平均色。
 * EntryPhotoStore 传「底部三分之一」的区域进来，所以这里平均整个缓冲区。
 * 行距按缓冲区实际字节推算（容忍对齐填充）。
 */
export function averageBgraRegion(buffer: ArrayBuffer, width: number,
  rows: number): number[] {
  const bytes = new Uint8Array(buffer);
  if (width <= 0 || rows <= 0 || bytes.length < width * rows * 4) {
    return [128, 128, 128];
  }
  const rowStride = Math.floor(buffer.byteLength / rows);
  let r = 0;
  let g = 0;
  let b = 0;
  let count = 0;
  for (let row = 0; row < rows; row++) {
    const rowStart = row * rowStride;
    for (let x = 0; x < width; x++) {
      const offset = rowStart + x * 4;
      b += bytes[offset];
      g += bytes[offset + 1];
      r += bytes[offset + 2];
      count++;
    }
  }
  if (count === 0) {
    return [128, 128, 128];
  }
  return [Math.round(r / count), Math.round(g / count), Math.round(b / count)];
}

/** RGB（0-255）→ HSB（h 0-360、s 0-1、v 0-1） */
export function rgbToHsb(r: number, g: number, b: number): number[] {
  const rr = r / 255;
  const gg = g / 255;
  const bb = b / 255;
  const max = Math.max(rr, gg, bb);
  const min = Math.min(rr, gg, bb);
  const delta = max - min;
  let h = 0;
  if (delta > 0) {
    if (max === rr) {
      h = 60 * (((gg - bb) / delta) % 6);
    } else if (max === gg) {
      h = 60 * ((bb - rr) / delta + 2);
    } else {
      h = 60 * ((rr - gg) / delta + 4);
    }
    if (h < 0) {
      h += 360;
    }
  }
  const s = max <= 0 ? 0 : delta / max;
  return [h, s, max];
}

/** HSB → RGB（0-255） */
export function hsbToRgb(h: number, s: number, v: number): number[] {
  const c = v * s;
  const hp = ((h % 360) + 360) % 360 / 60;
  const x = c * (1 - Math.abs(hp % 2 - 1));
  let r = 0;
  let g = 0;
  let b = 0;
  if (hp < 1) {
    r = c; g = x;
  } else if (hp < 2) {
    r = x; g = c;
  } else if (hp < 3) {
    g = c; b = x;
  } else if (hp < 4) {
    g = x; b = c;
  } else if (hp < 5) {
    r = x; b = c;
  } else {
    r = c; b = x;
  }
  const m = v - c;
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}

/** 平均色 → 染色：饱和度 ×1.4 收 [0.20, 0.72]、亮度收 [0.38, 0.86]（iOS normalize 同款） */
export function normalizedTintRgb(r: number, g: number, b: number): number[] {
  const hsb = rgbToHsb(r, g, b);
  const saturation = Math.min(Math.max(hsb[1] * 1.4, 0.20), 0.72);
  const brightness = Math.min(Math.max(hsb[2], 0.38), 0.86);
  return hsbToRgb(hsb[0], saturation, brightness);
}

/** '#RRGGBB' → [r, g, b]；非法输入 undefined */
export function hexToRgb(hex: string): number[] | undefined {
  if (hex.length !== 7 || hex[0] !== '#') {
    return undefined;
  }
  const rgb = Number.parseInt(hex.substring(1, 7), 16);
  if (Number.isNaN(rgb)) {
    return undefined;
  }
  return [(rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF];
}

/** [r, g, b]（0-255）→ '#RRGGBB' */
export function rgbToHex(r: number, g: number, b: number): string {
  const toHex = (v: number): string => {
    const clamped = Math.min(255, Math.max(0, Math.round(v)));
    const text = clamped.toString(16);
    return text.length < 2 ? '0' + text : text;
  };
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
}

/** 平均色 → 染色（'#RRGGBB'，入口用） */
export function normalizedTintHex(r: number, g: number, b: number): string {
  const tint = normalizedTintRgb(r, g, b);
  return rgbToHex(tint[0], tint[1], tint[2]);
}

/** BT.601 感知亮度是否偏亮（> 0.6）—— 决定压在这个颜色上的文字用深色还是浅色 */
export function isLightRgb(r: number, g: number, b: number): boolean {
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6;
}

/** 染色 hex 的深浅判定（入口用）；非法 hex 按偏亮兜底（深字在浅底，至少可读） */
export function isLightHex(hex: string): boolean {
  const rgb = hexToRgb(hex);
  if (rgb === undefined) {
    return true;
  }
  return isLightRgb(rgb[0], rgb[1], rgb[2]);
}
