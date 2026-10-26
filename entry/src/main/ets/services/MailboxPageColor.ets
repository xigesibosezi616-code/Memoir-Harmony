/**
 * 邮筒插画左上角 1 像素取色（10_BUILD_MANUAL.md 5.2）。对应 iOS
 * `PostBoxView.swift` 的 `UIImage.cornerColor`。
 *
 * 邮筒图不带透明底，拿左上角像素当整页底色才能严丝合缝（图外露一圈
 * 背景色差一点就看出一个框）。运行时取而不是写死色值：以后换图
 * （同名覆盖）不用跟着改代码。
 *
 * 读像素字节序 BGRA_8888（鸿蒙 `PixelMap.readPixels` 固定，与 iOS RGBA
 * 相反——DominantColor.ets 同款注意事项）。结果按主题 id 缓存。
 */
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'MailboxPageColor';

/** 主题 id → 左上角像素色（'#RRGGBB'），换图（同名覆盖）后重启即失效 */
const cache: Record<string, string> = {};

/**
 * 邮筒插画左上角 1 像素的颜色，'#RRGGBB'；解码失败返回 undefined
 * （调用方退回主题背景色）。
 */
export async function mailboxPageColor(context: common.Context,
  themeId: string, mailboxImage: Resource): Promise<string | undefined> {
  const hit = cache[themeId];
  if (hit !== undefined) {
    return hit;
  }
  let source: image.ImageSource | undefined = undefined;
  let pixelMap: image.PixelMap | undefined = undefined;
  try {
    // resId 重载（resource: Resource 重载 API 20 起废弃）
    const bytes: Uint8Array = await context.resourceManager.getMediaContent(mailboxImage.id);
    source = image.createImageSource(bytes.buffer);
    pixelMap = await source.createPixelMap();
    // 左上角 1 像素：BGRA_8888 紧排，4 字节
    const region: image.PositionArea = {
      pixels: new ArrayBuffer(4),
      offset: 0,
      stride: 4,
      region: { size: { width: 1, height: 1 }, x: 0, y: 0 }
    };
    await pixelMap.readPixels(region);
    const px = new Uint8Array(region.pixels);
    const b = px[0];
    const g = px[1];
    const r = px[2];
    const hex = `#${toHex2(r)}${toHex2(g)}${toHex2(b)}`;
    cache[themeId] = hex;
    return hex;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'mailbox page color failed themeId=%{public}s: %{public}s',
      themeId, JSON.stringify(err));
    return undefined;
  } finally {
    if (pixelMap !== undefined) {
      pixelMap.release();
    }
    if (source !== undefined) {
      source.release();
    }
  }
}

/**
 * 左上角像素是不是深色（0.299R + 0.587G + 0.114B 的 BT.601 加权 < 128）。
 * 预留给需要按页面底色深浅切换前景的场景（iOS 用它切状态栏字色）。
 */
export function isDarkHex(hex: string): boolean {
  const rgb = hexToRgb(hex);
  return 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2] < 128;
}

/** '#RRGGBB' → [r, g, b]；格式非法返回 [255, 255, 255]（当浅色） */
export function hexToRgb(hex: string): number[] {
  if (hex.length !== 7 || hex.charAt(0) !== '#') {
    return [255, 255, 255];
  }
  return [parseInt(hex.substring(1, 3), 16), parseInt(hex.substring(3, 5), 16),
    parseInt(hex.substring(5, 7), 16)];
}

function toHex2(v: number): string {
  const clamped = Math.max(0, Math.min(255, Math.round(v)));
  const s = clamped.toString(16);
  return s.length < 2 ? `0${s}` : s;
}
