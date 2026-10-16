/**
 * 肯特主题（kent）。色值逐个抄 iOS `Theme/KentTheme.swift`。
 * 旧 id `nordic` 的映射见 ThemeManager（R-THEME-01）。
 * 宽字距 2（素笺 / 皮革是 3）。
 */
import { AppTheme, FontInfo } from './AppTheme';

export class KentTheme implements AppTheme {
  readonly id = 'kent';
  readonly nameRes: Resource = $r('app.string.s_7ebd4ae074'); // 肯特

  readonly background: ResourceColor = 0xFFFFFFFF;
  readonly cardBackground: ResourceColor = 0xFFFFFFFF;
  readonly surfaceBackground: ResourceColor = 0xFFF8F8F8;
  readonly sidebarBackground: ResourceColor = 0xFF1A1A1A;

  readonly textPrimary: ResourceColor = 0xFF1A1A1A;
  readonly textSecondary: ResourceColor = 0xFF666666;
  readonly textTertiary: ResourceColor = 0xFF999999;

  readonly border: ResourceColor = 0xFFE5E5E5;
  readonly borderAccent: ResourceColor = 0xFF1A1A1A;

  // 玻璃按钮：纯白底上 66% 浅灰玻璃 + 70% 中灰边框（肯特 cardBackground 与背景同色，
  // 白玻璃在纯白底上不可见，靠灰底+边框成型；中灰边框保持极简风的克制对比；
  // 2026-10-16 真机可读性调优：alpha 55%→66% 且加深一档，玻璃片对纯白底
  // ΔRGB ~14 → ~24，按钮成型更清楚（图标色见 CircleIconButton）
  readonly glassBackground: ResourceColor = 0xA8DCDCDC;
  readonly glassBorder: ResourceColor = 0xB3999999;

  // 列表卡：纯白底上白卡，中性柔影成型（备忘录浅色款同款投影思路）
  readonly listCardBackground: ResourceColor = 0xFFFFFFFF;
  readonly listCardShadow: ShadowOptions = { radius: 8, color: 0x12000000, offsetX: 0, offsetY: 2 };

  readonly accent: ResourceColor = 0xFF1A1A1A;
  readonly accentBackground: ResourceColor = 0xFFF0F0F0;

  readonly moodBackground: ResourceColor = 0xFFF0F0F0;
  readonly moodBorder: ResourceColor = 0xFFE5E5E5;
  readonly moodText: ResourceColor = 0xFF1A1A1A;

  readonly destructive: ResourceColor = 0xFFE8453A;

  readonly colorMode: 'dark' | 'unset' = 'unset';
  readonly mailboxImage: Resource = $r('app.media.mailbox_kent');

  readonly titleFont: FontInfo = new FontInfo(22, FontWeight.Normal, 'serif');
  readonly headingFont: FontInfo = new FontInfo(18, FontWeight.Normal, 'serif');
  readonly bodyFont: FontInfo = new FontInfo(14, FontWeight.Normal, 'serif');
  readonly captionFont: FontInfo = new FontInfo(12, FontWeight.Normal, '');
  readonly labelFont: FontInfo = new FontInfo(10, FontWeight.Normal, '');

  readonly bodyLineSpacing = 8;
  readonly letterSpacingWide = 2;
}
