/**
 * ImmersiveChrome 纯函数单测（10_BUILD_MANUAL.md 1.6）。
 * 系统栏内容色按背景感知亮度（BT.601，R-HOME-06）推导：<128 白字、>=128 黑字。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  vpFromPx,
  perceivedLuminance,
  systemBarContentColorFor,
  IslandBodyGeometry
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

    it('islandGeometryHugsCutout', 0, () => {
      // 典型居中挖孔：机身顶 = 挖孔顶 - 2；顶黑边 = 越过挖孔底再留 9
      const g = IslandBodyGeometry.compute(360, 175, 13, 10, 9);
      expect(g.bodyTop).assertEqual(11);
      expect(g.topBezel).assertEqual(13 + 9 + 9 - 11);
      // 药丸整圈包住挖孔（四周各 4）
      expect(g.pillTop).assertEqual(9);
      expect(g.pillHeight).assertEqual(17);
      expect(g.pillWidth).assertEqual(18);
      // 药丸水平居中在挖孔上
      expect(g.pillLeft + g.pillWidth / 2).assertEqual(175 + 10 / 2);
    })

    it('islandGeometryClampsToScreenEdges', 0, () => {
      // 挖孔贴屏幕顶：机身顶 / 药丸顶都不出屏
      const top = IslandBodyGeometry.compute(360, 175, 0, 10, 9);
      expect(top.bodyTop).assertEqual(0);
      expect(top.pillTop).assertEqual(0);
      // 挖孔贴屏幕左缘：药丸左边不出屏（居中被夹回 0）
      const left = IslandBodyGeometry.compute(360, 0, 13, 10, 9);
      expect(left.pillLeft).assertEqual(0);
      // 挖孔贴右缘：药丸右边不出屏
      const right = IslandBodyGeometry.compute(360, 350, 13, 10, 9);
      expect(right.pillLeft + right.pillWidth <= 360).assertTrue();
    })

    it('islandGeometryKeepsMinimumTopBezel', 0, () => {
      // 极端扁挖孔（高 0）：顶黑边保底 12，不允许比侧黑边还薄出离谱
      const g = IslandBodyGeometry.compute(360, 175, 0, 2, 0);
      expect(g.topBezel >= 12).assertTrue();
    })
  })
}
