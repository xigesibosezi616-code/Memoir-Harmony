/**
 * 极夜主题（polar，2026-10-17 产品定）。色值逐个抄 iOS `Theme/PolarTheme.swift`。
 * 底是真正的 #000000——OLED 屏上黑色的像素直接熄灭；卡片、浮层只比底色抬一点点。
 * 字不用纯白（#E5E5EA），满屏纯白字在黑底上晃眼；强调色是肯特图标内框的那支蓝（#8FA8BF）。
 * 深色主题（colorMode = 'dark'，同皮革）、宽字距 2（同肯特）。
 */
import { AppTheme, FontInfo } from './AppTheme';

export class PolarTheme implements AppTheme {
  readonly id = 'polar';
  readonly nameRes: Resource = $r('app.string.s_1bb8716350'); // 极夜

  readonly background: ResourceColor = 0xFF000000;
  readonly cardBackground: ResourceColor = 0xFF0E0E10;
  readonly surfaceBackground: ResourceColor = 0xFF1C1C1E;
  readonly sidebarBackground: ResourceColor = 0xFF000000;
  /** 设置页底（U10 R-SETTINGS-08：纯黑） */
  readonly settingsPageBackground: ResourceColor = 0xFF000000;
  /** 设置分组卡（U10 R-SETTINGS-08：1C1C1E，与全局 cardBackground 0E0E10 不同） */
  readonly settingsCardBackground: ResourceColor = 0xFF1C1C1E;
  /** 设置大标题（U10 R-SETTINGS-08：FFFFFF） */
  readonly settingsTitleColor: ResourceColor = 0xFFFFFFFF;

  readonly textPrimary: ResourceColor = 0xFFE5E5EA;
  readonly textSecondary: ResourceColor = 0xFF8E8E93;
  readonly textTertiary: ResourceColor = 0xFF636366;

  readonly border: ResourceColor = 0xFF2C2C2E;
  // iOS `Color(hex: "#8FA8BF").opacity(0.35)` → ARGB 35% alpha
  readonly borderAccent: ResourceColor = 0x598FA8BF;

  // 玻璃按钮：纯黑底上 30% 蓝调微亮玻璃 + 45% 蓝边（对齐皮革深色范式的金调提亮做法）
  readonly glassBackground: ResourceColor = 0x4D8FA8BF;
  readonly glassBorder: ResourceColor = 0x738FA8BF;

  // 列表卡：贴 cardBackground（0E0E10，只比纯黑底抬一点）；
  // 深色下投影不可见，无影，靠明度微差 + EntryRowView 的 0.5 描边成型（同皮革）
  readonly listCardBackground: ResourceColor = 0xFF0E0E10;
  readonly listCardShadow: ShadowOptions = { radius: 0, color: Color.Transparent };

  readonly accent: ResourceColor = 0xFF8FA8BF;
  readonly accentBackground: ResourceColor = 0xFF1C1C1E;
  readonly markInk: ResourceColor = 0xFF8FA8BF;

  readonly moodBackground: ResourceColor = 0xFF1C1C1E;
  readonly moodBorder: ResourceColor = 0xFF2C2C2E;
  readonly moodText: ResourceColor = 0xFF8FA8BF;

  readonly destructive: ResourceColor = 0xFFFF453A;

  /** Tab 栏划动光感：纯黑底白光层次清晰（同皮革深色范式） */
  readonly tabLightColor: ResourceColor = 0xFFFFFFFF;

  readonly colorMode: 'dark' | 'unset' = 'dark';
  readonly mailboxImage: Resource = $r('app.media.mailbox_polar');

  readonly titleFont: FontInfo = new FontInfo(22, FontWeight.Normal, 'serif');
  readonly headingFont: FontInfo = new FontInfo(18, FontWeight.Normal, 'serif');
  readonly bodyFont: FontInfo = new FontInfo(14, FontWeight.Normal, 'serif');
  readonly captionFont: FontInfo = new FontInfo(12, FontWeight.Normal, '');
  readonly labelFont: FontInfo = new FontInfo(10, FontWeight.Normal, '');

  readonly bodyLineSpacing = 8;
  readonly letterSpacingWide = 2;
}
