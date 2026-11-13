/**
 * 地图墨色单测（U01 决策 15）：夜里的地图深色、墨点要浅才看得见；白天反过来。
 * 色值与 iOS `PenPalMapMarks.swift` 逐一对（#2B241E / #F6F1E6）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { hexToArgb, withAlpha, mixWithWhite, mapInkOf, MapInk,
  MAP_INK_DARK, MAP_INK_LIGHT } from '../../main/ets/models/MapInk';

export default function mapInkTest() {
  describe('MapInkTest', () => {
    it('hexToArgbParsesSixDigits', 0, () => {
      expect(hexToArgb('#2B241E')).assertEqual(0xFF2B241E);
      expect(hexToArgb('#F6F1E6')).assertEqual(0xFFF6F1E6);
      expect(hexToArgb('#B5473A')).assertEqual(0xFFB5473A);
    })

    it('hexToArgbKeepsEightDigits', 0, () => {
      expect(hexToArgb('#802B241E')).assertEqual(0x802B241E);
    })

    it('withAlphaReplacesAlphaChannel', 0, () => {
      expect(withAlpha(0xFF2B241E, 1)).assertEqual(0xFF2B241E);
      expect(withAlpha(0xFF2B241E, 0)).assertEqual(0x002B241E);
      // 0.85 × 255 = 216.75 → 217
      expect(withAlpha(0xFF2B241E, 0.85)).assertEqual(0xD92B241E);
    })

    it('withAlphaClamps', 0, () => {
      expect(withAlpha(0xFF2B241E, 5)).assertEqual(0xFF2B241E);
      expect(withAlpha(0xFF2B241E, -5)).assertEqual(0x002B241E);
    })

    it('mixWithWhiteLightens', 0, () => {
      // 纯红往白掺一半：红通道本来就满（255 不变），绿蓝 0 → 127.5 → 128
      const mixed = mixWithWhite(0xFFFF0000, 0.5);
      expect((mixed >> 16) & 0xFF).assertEqual(255);
      expect((mixed >> 8) & 0xFF).assertEqual(128);
      expect(mixed & 0xFF).assertEqual(128);
      // fraction 0 原样、1 全白
      expect(mixWithWhite(0xFF2B241E, 0)).assertEqual(0xFF2B241E);
      expect(mixWithWhite(0xFF2B241E, 1)).assertEqual(0xFFFFFFFF);
    })

    it('nightInkIsLightOnDark', 0, () => {
      const ink: MapInk = mapInkOf(true, '#B5473A');
      expect(ink.dot).assertEqual(MAP_INK_LIGHT);
      expect(ink.ring).assertEqual(MAP_INK_DARK);
      expect(ink.tagPaper).assertEqual(0xD92B241E); // 深墨 85%
      expect(ink.route).assertEqual(0x80F6F1E6); // 浅墨 50%
      // 邮戳色调亮：朱红 #B5473A 往白掺 35% → #CF877F
      expect(ink.post).assertEqual(0xFFCF877F);
    })

    it('dayInkIsDarkOnLight', 0, () => {
      const ink: MapInk = mapInkOf(false, '#B5473A');
      expect(ink.dot).assertEqual(MAP_INK_DARK);
      expect(ink.ring).assertEqual(MAP_INK_LIGHT);
      expect(ink.tagPaper).assertEqual(0xEBF6F1E6); // 浅墨 92%
      expect(ink.route).assertEqual(0x592B241E); // 深墨 35%
      // 白天邮戳色原样
      expect(ink.post).assertEqual(0xFFB5473A);
    })
  })
}
