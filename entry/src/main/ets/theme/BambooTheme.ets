/**
 * 素笺主题（bamboo）。色值逐个抄 iOS `Theme/BambooTheme.swift`
 * （04_DESIGN_LANGUAGE.md 配色全表核对过）。
 * 旧 id `washi` 的映射见 ThemeManager（R-THEME-01）。
 */
import { AppTheme, FontInfo } from './AppTheme';

export class BambooTheme implements AppTheme {
  readonly id = 'bamboo';
  readonly nameRes: Resource = $r('app.string.s_abafd65e30'); // 素笺

  readonly background: ResourceColor = 0xFFFAF7F2;
  readonly cardBackground: ResourceColor = 0xFFFAF7F2;
  readonly surfaceBackground: ResourceColor = 0xFFF5F0E7;
  readonly sidebarBackground: ResourceColor = 0xFFF0EBE1;

  readonly textPrimary: ResourceColor = 0xFF3D3428;
  readonly textSecondary: ResourceColor = 0xFF8B7E6A;
  readonly textTertiary: ResourceColor = 0xFFC8BDA8;

  readonly border: ResourceColor = 0xFFE8E2D6;
  readonly borderAccent: ResourceColor = 0xFFD4C9B8;

  // 玻璃按钮：米白底上 66% 暖灰玻璃 + 90% 暖灰边框（素笺 cardBackground 与背景同色，
  // 白玻璃提亮在米白底上不可见，改暖灰降一档明度靠 1vp 边框成型；
  // 2026-10-16 真机可读性调优：alpha 55%→66% 且加深一档，玻璃片对米白底
  // ΔRGB ~9-17 → ~17-29，按钮成型更清楚（图标色见 CircleIconButton）
  readonly glassBackground: ResourceColor = 0xA8E0D8C6;
  readonly glassBorder: ResourceColor = 0xE6D4C9B8;

  // 列表卡：米白和纸底上纯白卡 + 暖墨柔影（备忘录浅色款「亮卡浮于浅底」）
  readonly listCardBackground: ResourceColor = 0xFFFFFFFF;
  readonly listCardShadow: ShadowOptions = { radius: 8, color: 0x143E3A33, offsetX: 0, offsetY: 2 };

  readonly accent: ResourceColor = 0xFF8B7E6A;
  readonly accentBackground: ResourceColor = 0xFFF0EBE1;

  readonly moodBackground: ResourceColor = 0xFFF0EBE1;
  readonly moodBorder: ResourceColor = 0xFFD4C9B8;
  readonly moodText: ResourceColor = 0xFF8B7E6A;

  readonly destructive: ResourceColor = 0xFFE8453A;

  readonly colorMode: 'dark' | 'unset' = 'unset';
  readonly mailboxImage: Resource = $r('app.media.mailbox_bamboo');

  readonly titleFont: FontInfo = new FontInfo(22, FontWeight.Normal, 'serif');
  readonly headingFont: FontInfo = new FontInfo(18, FontWeight.Normal, 'serif');
  readonly bodyFont: FontInfo = new FontInfo(14, FontWeight.Normal, 'serif');
  readonly captionFont: FontInfo = new FontInfo(12, FontWeight.Normal, '');
  readonly labelFont: FontInfo = new FontInfo(10, FontWeight.Normal, '');

  readonly bodyLineSpacing = 8;
  readonly letterSpacingWide = 3;
}
