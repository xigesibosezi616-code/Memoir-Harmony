/**
 * 心情徽标（10_BUILD_MANUAL.md 2.2 记录页列表行）。对应 iOS
 * `Views/Components/MoodBadge.swift`：小胶囊，有心情色走色底白字，
 * 没有色 token 走 moodBackground/moodText。显示名：默认心情 key 查
 * `mood.*` 译文（R-LANG-09），查不到 / 自定义心情显示原名。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { isDefaultMoodKey } from '../../models/Mood';

/** 默认心情 key → 显示名资源（与 MoodSelector 同一张映射表，R-LANG-09） */
function moodLabelRes(key: string): Resource | undefined {
  switch (key) {
    case 'calm': return $r('app.string.s_cb2d681e91');       // 平静
    case 'productive': return $r('app.string.s_b2c510fd6a'); // 充实
    case 'reflective': return $r('app.string.s_287dbc9adc'); // 沉思
    case 'joyful': return $r('app.string.s_840d2718da');     // 喜悦
    case 'low': return $r('app.string.s_824e119909');        // 低落
    case 'anxious': return $r('app.string.s_f685ba2f14');    // 焦虑
    case 'grateful': return $r('app.string.s_83c6e3fd12');   // 感恩
    case 'excited': return $r('app.string.s_ee7391e94f');    // 期待
    case 'tired': return $r('app.string.s_d63d98608d');      // 疲惫
    case 'peaceful': return $r('app.string.s_1d72fd4c59');   // 安宁
    case 'nostalgic': return $r('app.string.s_fdc1a10b4f');  // 怀念
    case 'hopeful': return $r('app.string.s_5fdfe71cba');    // 希望
    default: return undefined;
  }
}

/** '#RRGGBB' → 0xAARRGGBB（alpha 0–1）；非法输入返回 undefined */
export function hexWithAlpha(hex: string, alpha: number): number | undefined {
  if (hex.length !== 7 || hex[0] !== '#') {
    return undefined;
  }
  const rgb = Number.parseInt(hex.substring(1, 7), 16);
  if (Number.isNaN(rgb)) {
    return undefined;
  }
  const a = Math.round(alpha * 255);
  return (a << 24) | rgb;
}

@Component
export struct MoodBadge {
  /** 心情 key（默认）或自定义名 */
  name: string = '';
  /** 心情色 '#RRGGBB'，空串走主题 token */
  colorHex: string = '';
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Text(this.displayText())
      .fontSize(this.theme.labelFont.size)
      .fontWeight(this.theme.labelFont.weight)
      .fontFamily(this.theme.labelFont.family)
      .fontColor(this.textColor())
      .letterSpacing(this.theme.letterSpacingWide)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(this.badgeBackgroundColor())
      .borderRadius(12)
      .border({ width: 0.5, color: this.badgeBorderColor() })
  }

  /** 显示名：默认 key 查 mood.* 译文；自定义心情原名 */
  private displayText(): ResourceStr {
    if (isDefaultMoodKey(this.name)) {
      const res = moodLabelRes(this.name);
      if (res !== undefined) {
        return res;
      }
    }
    return this.name;
  }

  private hasColor(): boolean {
    return this.colorHex.length === 7 && this.colorHex[0] === '#';
  }

  /** iOS：有色 → Color(hex).opacity(0.6) 底；无色 → moodBackground。
   *  🔴 不叫 backgroundColor()：会撞 CustomComponent 基类同名属性方法（编译错误） */
  private badgeBackgroundColor(): ResourceColor {
    if (this.hasColor()) {
      const tinted = hexWithAlpha(this.colorHex, 0.6);
      if (tinted !== undefined) {
        return tinted;
      }
    }
    return this.theme.moodBackground;
  }

  /** iOS：有色 → Color(hex).opacity(0.8) 边；无色 → moodBorder。命名同理避开基类 */
  private badgeBorderColor(): ResourceColor {
    if (this.hasColor()) {
      const tinted = hexWithAlpha(this.colorHex, 0.8);
      if (tinted !== undefined) {
        return tinted;
      }
    }
    return this.theme.moodBorder;
  }

  /** iOS：有色 → 白 0.9；无色 → moodText */
  private textColor(): ResourceColor {
    if (this.hasColor()) {
      return 0xE6FFFFFF;
    }
    return this.theme.moodText;
  }
}
