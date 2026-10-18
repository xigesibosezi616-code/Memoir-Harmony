/**
 * 皮革主题（leather）。色值逐个抄 iOS `Theme/LeatherTheme.swift`。
 * 唯一的深色主题：`colorMode = 'dark'`，切到它时整个 App 走系统深色（R-THEME-03）。
 */
import { AppTheme, FontInfo } from './AppTheme';

export class LeatherTheme implements AppTheme {
  readonly id = 'leather';
  readonly nameRes: Resource = $r('app.string.s_b416882c45'); // 皮革

  readonly background: ResourceColor = 0xFF1C1410;
  readonly cardBackground: ResourceColor = 0xFF241C16;
  readonly surfaceBackground: ResourceColor = 0xFF2A2019;
  readonly sidebarBackground: ResourceColor = 0xFF140E0A;

  readonly textPrimary: ResourceColor = 0xFFD4C4A8;
  readonly textSecondary: ResourceColor = 0xFF8A7B6A;
  readonly textTertiary: ResourceColor = 0xFF7A6B5A;

  readonly border: ResourceColor = 0xFF3A2E25;
  // iOS `Color(hex: "#C8A87C").opacity(0.3)` → ARGB 30% alpha
  readonly borderAccent: ResourceColor = 0x4DC8A87C;

  // 玻璃按钮：深棕底上 30% 金色微亮玻璃 + 45% 金边（深色下用金调提亮，对齐 iOS 深色 .glass）
  readonly glassBackground: ResourceColor = 0x4DC8A87C;
  readonly glassBorder: ResourceColor = 0x73C8A87C;

  // 列表卡：深棕底上抬亮一档的卡面（投影深色下不可见，靠明度差成型，
  // 备忘录深色款同思路：深灰卡浮黑底）
  readonly listCardBackground: ResourceColor = 0xFF2A2019;
  readonly listCardShadow: ShadowOptions = { radius: 0, color: Color.Transparent };

  readonly accent: ResourceColor = 0xFFC8A87C;
  readonly accentBackground: ResourceColor = 0xFF241C16;

  readonly moodBackground: ResourceColor = 0xFF2D2219;
  readonly moodBorder: ResourceColor = 0xFF3A2E25;
  readonly moodText: ResourceColor = 0xFFC8A87C;

  readonly destructive: ResourceColor = 0xFFE8453A;

  /** Tab 栏划动光感：深色底白光层次清晰，保持系统默认观感 */
  readonly tabLightColor: ResourceColor = 0xFFFFFFFF;

  readonly colorMode: 'dark' | 'unset' = 'dark';
  readonly mailboxImage: Resource = $r('app.media.mailbox_leather');

  readonly titleFont: FontInfo = new FontInfo(22, FontWeight.Normal, 'serif');
  readonly headingFont: FontInfo = new FontInfo(18, FontWeight.Normal, 'serif');
  readonly bodyFont: FontInfo = new FontInfo(14, FontWeight.Normal, 'serif');
  readonly captionFont: FontInfo = new FontInfo(12, FontWeight.Normal, '');
  readonly labelFont: FontInfo = new FontInfo(10, FontWeight.Normal, '');

  readonly bodyLineSpacing = 8;
  readonly letterSpacingWide = 3;
}
