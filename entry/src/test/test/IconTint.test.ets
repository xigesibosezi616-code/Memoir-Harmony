/**
 * 单色 SVG 染色矩阵单测（10_BUILD_MANUAL.md 1.6）。
 * 4×5 行优先：RGB 各行常数替换为目标色，alpha 行原样保留。
 */
import { describe, it, expect } from '@ohos/hypium';
import { tintMatrix } from '../../main/ets/theme/IconTint';

export default function iconTintTest() {
  describe('IconTintTest', () => {
    it('matrixHasTwentyEntries', 0, () => {
      expect(tintMatrix(0xFF8B7E6A).length).assertEqual(20);
    })

    it('tintsRedTarget', 0, () => {
      const m = tintMatrix(0xFFFF0000);
      // R 行：输出 = 1×目标 R
      expect(m[0]).assertEqual(0);
      expect(m[1]).assertEqual(0);
      expect(m[2]).assertEqual(0);
      expect(m[3]).assertEqual(0);
      expect(m[4]).assertEqual(1);
      // G 行
      expect(m[9]).assertEqual(0);
      // B 行
      expect(m[14]).assertEqual(0);
      // alpha 行：A' = A
      expect(m[15]).assertEqual(0);
      expect(m[16]).assertEqual(0);
      expect(m[17]).assertEqual(0);
      expect(m[18]).assertEqual(1);
      expect(m[19]).assertEqual(0);
    })

    it('tintsThemeAccentColor', 0, () => {
      // 素笺主题 accent 0xFF8B7E6A → R 139/255、G 126/255、B 106/255
      const m = tintMatrix(0xFF8B7E6A);
      expect(m[4].toFixed(6)).assertEqual((139 / 255).toFixed(6));
      expect(m[9].toFixed(6)).assertEqual((126 / 255).toFixed(6));
      expect(m[14].toFixed(6)).assertEqual((106 / 255).toFixed(6));
    })

    it('ignoresAlphaChannelOfTarget', 0, () => {
      // 目标色的 alpha 不参与染色（只染 RGB）
      const opaque = tintMatrix(0xFF123456);
      const translucent = tintMatrix(0x00123456);
      for (let i = 0; i < 20; i++) {
        expect(translucent[i]).assertEqual(opaque[i]);
      }
    })
  })
}
