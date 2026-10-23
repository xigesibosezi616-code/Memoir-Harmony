/**
 * 照片取色纯函数单测（10_BUILD_MANUAL.md 3.6，R-HOME-06）。
 *
 * 不变量：
 * - averageBgraRegion 是 **BGRA** 字节序（readPixels 固定 BGRA_8888）：
 *   字节 [0,0,255,255] 是红像素，返回 [255,0,0]——红蓝颠倒整张卡染色就错，
 *   橙天变蓝海
 * - 行距按缓冲区字节推算（容忍对齐填充），平均整个传入区域
 * - rgb↔hsb 往返一致；normalize 把亮度夹进 [0.38, 0.86]、饱和度夹进
 *   [0.20, 0.72]（夜景不死黑、雪景不等于没染）
 * - 深浅字判定用 BT.601 加权（不是 rgb 平均）
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  averageBgraRegion,
  hexToRgb,
  hsbToRgb,
  isLightHex,
  isLightRgb,
  normalizedTintHex,
  normalizedTintRgb,
  rgbToHex,
  rgbToHsb
} from '../../main/ets/services/DominantColor';

/** 造 BGRA 缓冲区：pixels 每项 [B, G, R, A] */
function bgraBuffer(pixels: number[][]): ArrayBuffer {
  const buffer = new ArrayBuffer(pixels.length * 4);
  const bytes = new Uint8Array(buffer);
  for (let i = 0; i < pixels.length; i++) {
    bytes[i * 4] = pixels[i][0];
    bytes[i * 4 + 1] = pixels[i][1];
    bytes[i * 4 + 2] = pixels[i][2];
    bytes[i * 4 + 3] = pixels[i][3];
  }
  return buffer;
}

export default function dominantColorTest() {
  describe('DominantColor', () => {
    // ---- BGRA 字节序（🔴 最关键：R/B 不能颠倒）----

    it('bgraByteOrderRedIsNotBlue', 0, () => {
      // 字节 [B=0,G=0,R=255,A=255] = 红像素 → [255,0,0]
      const red = averageBgraRegion(bgraBuffer([[0, 0, 255, 255]]), 1, 1);
      expect(red[0]).assertEqual(255);
      expect(red[1]).assertEqual(0);
      expect(red[2]).assertEqual(0);
      // 字节 [B=255,G=0,R=0,A=255] = 蓝像素 → [0,0,255]
      const blue = averageBgraRegion(bgraBuffer([[255, 0, 0, 255]]), 1, 1);
      expect(blue[0]).assertEqual(0);
      expect(blue[2]).assertEqual(255);
    })

    it('bgraAveragesWholeRegion', 0, () => {
      // 2×1：一半红一半蓝 → [128, 0, 128]（四舍五入）
      const avg = averageBgraRegion(
        bgraBuffer([[0, 0, 255, 255], [255, 0, 0, 255]]), 2, 1);
      expect(avg[0]).assertEqual(128);
      expect(avg[1]).assertEqual(0);
      expect(avg[2]).assertEqual(128);
    })

    it('bgraRowStrideFromBufferLengthIgnoresPadding', 0, () => {
      // 2 行、每行 4 字节有效 + 2 字节填充：填充不参与平均
      const buffer = new ArrayBuffer(12);
      const bytes = new Uint8Array(buffer);
      const rows: number[][] = [[10, 20, 30, 255], [10, 20, 30, 255]];
      for (let row = 0; row < 2; row++) {
        for (let x = 0; x < 4; x++) {
          bytes[row * 6 + x] = rows[row][x];
        }
        bytes[row * 6 + 4] = 250; // 填充字节，不该被算进去
        bytes[row * 6 + 5] = 250;
      }
      const avg = averageBgraRegion(buffer, 1, 2);
      // B=10 G=20 R=30
      expect(avg[0]).assertEqual(30);
      expect(avg[1]).assertEqual(20);
      expect(avg[2]).assertEqual(10);
    })

    it('bgraInvalidInputFallsBackToGray', 0, () => {
      const gray = averageBgraRegion(bgraBuffer([[0, 0, 255, 255]]), 0, 1);
      expect(gray[0]).assertEqual(128);
      expect(gray[1]).assertEqual(128);
      expect(gray[2]).assertEqual(128);
      // 缓冲区比 width×rows×4 还小 → 灰
      const tooSmall = averageBgraRegion(new ArrayBuffer(4), 2, 1);
      expect(tooSmall[0]).assertEqual(128);
    })

    // ---- rgb ↔ hsb ----

    it('rgbToHsbKnownColors', 0, () => {
      const red = rgbToHsb(255, 0, 0);
      expect(red[0]).assertEqual(0);
      expect(red[1]).assertEqual(1);
      expect(red[2]).assertEqual(1);
      const blue = rgbToHsb(0, 0, 255);
      expect(blue[0]).assertEqual(240);
      expect(blue[1]).assertEqual(1);
      const green = rgbToHsb(0, 255, 0);
      expect(green[0]).assertEqual(120);
      const black = rgbToHsb(0, 0, 0);
      expect(black[1]).assertEqual(0);
      expect(black[2]).assertEqual(0);
      const white = rgbToHsb(255, 255, 255);
      expect(white[1]).assertEqual(0);
      expect(white[2]).assertEqual(1);
    })

    it('hsbToRgbKnownColors', 0, () => {
      const red = hsbToRgb(0, 1, 1);
      expect(red[0]).assertEqual(255);
      expect(red[1]).assertEqual(0);
      expect(red[2]).assertEqual(0);
      const blue = hsbToRgb(240, 1, 1);
      expect(blue[0]).assertEqual(0);
      expect(blue[2]).assertEqual(255);
      // 灰：s=0 时 hsbToRgb(h,0,v) = v 的灰
      const gray = hsbToRgb(0, 0, 0.5);
      expect(gray[0]).assertEqual(128);
      expect(gray[1]).assertEqual(128);
      expect(gray[2]).assertEqual(128);
    })

    it('hsbRoundTripKeepsHue', 0, () => {
      // 三个代表色往返：hue 偏差 < 1°
      const hues: number[] = [20, 120, 260];
      for (const hue of hues) {
        const rgb = hsbToRgb(hue, 0.6, 0.8);
        const back = rgbToHsb(rgb[0], rgb[1], rgb[2]);
        const delta = Math.abs(back[0] - hue);
        expect(Math.min(delta, 360 - delta) < 1).assertTrue();
        expect(Math.abs(back[2] - 0.8) < 0.01).assertTrue();
      }
    })

    // ---- normalize（iOS 同款修色）----

    it('normalizeLiftsNightshotsOutOfBlack', 0, () => {
      // 死黑照片：亮度提到 0.38、饱和度提到 0.20 → [97, 78, 78]
      const tint = normalizedTintRgb(0, 0, 0);
      expect(tint[0]).assertEqual(97);
      expect(tint[1]).assertEqual(78);
      expect(tint[2]).assertEqual(78);
    })

    it('normalizeCapsSnowAtMaxBrightnessAndKeepsSaturationFloor', 0, () => {
      // 雪白照片：亮度压到 0.86、饱和度抬到 0.20（不然染了等于没染）
      const tint = normalizedTintRgb(255, 255, 255);
      expect(tint[0]).assertEqual(219);
      expect(tint[1]).assertEqual(175);
      expect(tint[2]).assertEqual(175);
    })

    it('normalizeKeepsMidrangeColorsAlmostUntouched', 0, () => {
      // 中等暖色（V≈0.7 在区间内、S 被 ×1.4 但仍 < 0.72 上限的部分）
      const tint = normalizedTintRgb(200, 120, 80);
      const hsb = rgbToHsb(200, 120, 80);
      const back = rgbToHsb(tint[0], tint[1], tint[2]);
      expect(Math.abs(back[0] - hsb[0]) < 1).assertTrue();
      expect(back[2] > 0.5 && back[2] < 0.8).assertTrue();
    })

    it('normalizedTintHexMatchesRgb', 0, () => {
      expect(normalizedTintHex(0, 0, 0)).assertEqual('#614e4e');
      expect(normalizedTintHex(255, 255, 255)).assertEqual('#dbafaf');
    })

    // ---- hex ----

    it('hexToRgbAndBack', 0, () => {
      const red = hexToRgb('#ff0000');
      expect(red !== undefined).assertTrue();
      expect(red![0]).assertEqual(255);
      expect(red![2]).assertEqual(0);
      expect(rgbToHex(255, 0, 0)).assertEqual('#ff0000');
      expect(rgbToHex(0, 128, 255)).assertEqual('#0080ff');
      expect(rgbToHex(300, -5, 12.4)).assertEqual('#ff000c'); // 钳到 [0,255] 再取整
      // 非法输入
      expect(hexToRgb('ff0000') === undefined).assertTrue();
      expect(hexToRgb('#12345') === undefined).assertTrue();
      expect(hexToRgb('#zzz') === undefined).assertTrue();
    })

    // ---- 深浅字判定（BT.601）----

    it('isLightRgbUsesBt601NotPlainAverage', 0, () => {
      expect(isLightRgb(255, 255, 255)).assertTrue();
      expect(isLightRgb(0, 0, 0)).assertFalse();
      // 纯绿：BT.601 = 0.587 < 0.6 → 深底（浅字）；
      // 简单平均也是 0.333，此例两者一致，但绿通道超 0.6/0.587 的边界由它守护
      expect(isLightRgb(0, 255, 0)).assertFalse();
      expect(isLightRgb(220, 255, 220)).assertTrue();
      // 饱和蓝：BT.601 权重低，哪怕 b=255 也不算亮 → 深字不会压在蓝底上看不清
      expect(isLightRgb(0, 0, 255)).assertFalse();
      expect(isLightRgb(240, 240, 200)).assertTrue();
    })

    it('isLightHexFallsBackToLightOnInvalid', 0, () => {
      expect(isLightHex('#ffffff')).assertTrue();
      expect(isLightHex('#000000')).assertFalse();
      // 非法 hex 按偏亮兜底（深字压浅底至少可读）
      expect(isLightHex('nope')).assertTrue();
    })
  })
}
