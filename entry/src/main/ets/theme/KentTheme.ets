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
