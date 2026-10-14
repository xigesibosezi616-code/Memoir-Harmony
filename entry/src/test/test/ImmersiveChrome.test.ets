/**
 * ImmersiveChrome 纯函数单测（10_BUILD_MANUAL.md 1.6）。
 * 系统栏内容色按背景感知亮度（BT.601，R-HOME-06）推导：<128 白字、>=128 黑字。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  vpFromPx,
  perceivedLuminance,
  systemBarContentColorFor
} from '../../main/ets/services/ImmersiveChrome';

export default function immersiveChromeTest() {
  describe('ImmersiveChromeTest', () => {
    it('vpFromPxDividesByDensity', 0, () => {
      expect(vpFromPx(100, 2).toFixed(6)).assertEqual('50.000000');
      expect(vpFromPx(135, 3).toFixed(6)).assertEqual('45.000000');
    })

    it('vpFromPxGuardsInvalidDensity', 0, () => {
      expect(vpFromPx(100, 0)).assertEqual(0);
      expect(vpFromPx(100, -1)).assertEqual(0);
    })

    it('perceivedLuminanceUsesBt601', 0, () => {
      // 纯红 0.299×255≈76.2
      expect(perceivedLuminance(0xFFFF0000).toFixed(3)).assertEqual('76.245');
      // 纯白 255
      expect(perceivedLuminance(0xFFFFFFFF).toFixed(3)).assertEqual('255.000');
      // 忽略 alpha 通道
      expect(perceivedLuminance(0x00FFFFFF).toFixed(3)).assertEqual('255.000');
    })

    it('contentColorBoundaryAt128', 0, () => {
      // 灰 0x80=128：不小于 128 → 黑字
      expect(perceivedLuminance(0xFF808080).toFixed(3)).assertEqual('128.000');
      expect(systemBarContentColorFor(0xFF808080)).assertEqual('#000000');
      // 灰 0x7F=127：低于 128 → 白字
      expect(perceivedLuminance(0xFF7F7F7F).toFixed(3)).assertEqual('127.000');
      expect(systemBarContentColorFor(0xFF7F7F7F)).assertEqual('#FFFFFF');
    })

    it('contentColorFollowsLightAndDarkBackgrounds', 0, () => {
      // 主题背景（米白 0xFFFAF7F2）→ 黑字
      expect(systemBarContentColorFor(0xFFFAF7F2)).assertEqual('#000000');
      // 深底 → 白字
      expect(systemBarContentColorFor(0xFF202020)).assertEqual('#FFFFFF');
    })
  })
}
