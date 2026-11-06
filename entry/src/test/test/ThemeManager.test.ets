/**
 * ThemeManager 纯逻辑单测（10_BUILD_MANUAL.md 1.1）。
 *
 * 只测纯函数与不变量：旧 id 归一（R-THEME-01）、按 id 取主题、
 * 深色主题强制应用级深色 / 其余跟随系统（R-THEME-03）、宽字距按主题、
 * App 图标规则（R-THEME-06：跟随 / 固定 / 一并换 vs 仅换）。
 * 不碰偏好读写与应用明暗（需要 UIAbility 环境，真机 ohosTest 再覆盖）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { ThemeManager } from '../../main/ets/theme/ThemeManager';
import { BambooTheme } from '../../main/ets/theme/BambooTheme';
import { LeatherTheme } from '../../main/ets/theme/LeatherTheme';
import { KentTheme } from '../../main/ets/theme/KentTheme';
import { PolarTheme } from '../../main/ets/theme/PolarTheme';

export default function themeManagerTest() {
  describe('ThemeManagerTest', () => {
    // R-THEME-01：2026-09-16 主题改名，旧 id 读出来先归一再用
    it('canonicalThemeIdMapsLegacyIds', 0, () => {
      expect(ThemeManager.canonicalThemeId('washi')).assertEqual('bamboo');
      expect(ThemeManager.canonicalThemeId('nordic')).assertEqual('kent');
    })

    it('canonicalThemeIdKeepsCurrentIds', 0, () => {
      expect(ThemeManager.canonicalThemeId('bamboo')).assertEqual('bamboo');
      expect(ThemeManager.canonicalThemeId('leather')).assertEqual('leather');
      expect(ThemeManager.canonicalThemeId('kent')).assertEqual('kent');
      expect(ThemeManager.canonicalThemeId('polar')).assertEqual('polar');
    })

    it('canonicalThemeIdPassesUnknownThrough', 0, () => {
      expect(ThemeManager.canonicalThemeId('someUnknownId')).assertEqual('someUnknownId');
    })

    it('themeForReturnsMatchingInstances', 0, () => {
      expect(ThemeManager.themeFor('bamboo') instanceof BambooTheme).assertTrue();
      expect(ThemeManager.themeFor('leather') instanceof LeatherTheme).assertTrue();
      expect(ThemeManager.themeFor('kent') instanceof KentTheme).assertTrue();
      expect(ThemeManager.themeFor('polar') instanceof PolarTheme).assertTrue();
      // 旧 id 归一后同样取到对应主题
      expect(ThemeManager.themeFor('washi') instanceof BambooTheme).assertTrue();
      expect(ThemeManager.themeFor('nordic') instanceof KentTheme).assertTrue();
      // 未知 id 落到素笺兜底（与 iOS switch default 一致）
      expect(ThemeManager.themeFor('someUnknownId') instanceof BambooTheme).assertTrue();
    })

    // R-THEME-03：皮革 / 极夜深色主题强制 dark，其余 unset 跟随系统
    it('leatherForcesDarkOthersFollowSystem', 0, () => {
      expect(ThemeManager.themeFor('leather').colorMode).assertEqual('dark');
      expect(ThemeManager.themeFor('polar').colorMode).assertEqual('dark');
      expect(ThemeManager.themeFor('bamboo').colorMode).assertEqual('unset');
      expect(ThemeManager.themeFor('kent').colorMode).assertEqual('unset');
    })

    // 宽字距：素笺 / 皮革 3，肯特 / 极夜 2（04_DESIGN_LANGUAGE.md）
    it('wideLetterSpacingPerTheme', 0, () => {
      expect(ThemeManager.themeFor('bamboo').letterSpacingWide).assertEqual(3);
      expect(ThemeManager.themeFor('leather').letterSpacingWide).assertEqual(3);
      expect(ThemeManager.themeFor('kent').letterSpacingWide).assertEqual(2);
      expect(ThemeManager.themeFor('polar').letterSpacingWide).assertEqual(2);
    })

    // R-THEME-06：空串 = 跟随主题（默认）；固定了就用固定的
    it('iconFollowAndResolveRules', 0, () => {
      expect(ThemeManager.isFollowingIcon('')).assertTrue();
      expect(ThemeManager.isFollowingIcon('leather')).assertFalse();
      // 跟随时当前图标 = 主题的图标；固定时忽略主题
      expect(ThemeManager.resolvedIconId('', 'leather')).assertEqual('leather');
      expect(ThemeManager.resolvedIconId('kent', 'leather')).assertEqual('kent');
    })

    // R-THEME-05/06：一并更换图标 = 回跟随；仅更换主题 = 跟随态先把当前图标固定下来
    it('iconSelectionAfterSwitchRules', 0, () => {
      // 跟随态 + 一并换：仍跟随（真正的切换由 applyAppIcon 做）
      expect(ThemeManager.iconSelectionAfterSwitch('', 'leather', true)).assertEqual('');
      // 跟随态 + 仅换主题：把当前主题的图标固定下来，换完主题它不跟着变
      expect(ThemeManager.iconSelectionAfterSwitch('', 'leather', false)).assertEqual('leather');
      // 固定态 + 仅换主题：保持固定值不动
      expect(ThemeManager.iconSelectionAfterSwitch('kent', 'leather', false)).assertEqual('kent');
      // 固定态 + 一并换：回到跟随
      expect(ThemeManager.iconSelectionAfterSwitch('kent', 'leather', true)).assertEqual('');
    })
  })
}
