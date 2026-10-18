/**
 * 富文本排版参数（10_BUILD_MANUAL.md 2.5）。对应 iOS `Theme` 里的富文本配置。
 *
 * 三套主题各一份：正文字号、荧光笔色从 iOS 主题搬来；
 * 行高由字号推导（×1.43 + (行距-8)），保持 v1 真机调过的「14fp→20fp 行高」手感，
 * 素笺正文升 17fp（R-ENTRY-12）后按同一比例放大。
 */
import { AppTheme } from '../../../theme/AppTheme';
import { Ink } from '../../../models/ContentBlock';
import { RichFormatFlags } from '../../../models/RichDocument';

/** 主题主文字色加透明度（工具条按钮亮灯底色用）。非数字色原样返回 */
export function colorWithAlpha(color: ResourceColor, alpha: number): ResourceColor {
  if (typeof color === 'number') {
    return (color & 0xFFFFFF) | ((alpha & 0xFF) << 24);
  }
  return color;
}

/**
 * 墨色加透明度（0~1）：划掉的字变淡用（iOS `withAlphaComponent(0.42)`）。
 * 支持 '#RRGGBB' / '#AARRGGBB' 字符串与 0xAARRGGBB 数字色；其余形态原样返回。
 */
export function inkColorWithAlpha(color: ResourceColor, alpha: number): ResourceColor {
  const byte = Math.round(Math.min(Math.max(alpha, 0), 1) * 255);
  if (typeof color === 'number') {
    return (color & 0xFFFFFF) | (byte << 24);
  }
  if (typeof color === 'string') {
    const hex = color.slice(1);
    if (color.startsWith('#') && (hex.length === 6 || hex.length === 8)) {
      const rgb = hex.length === 6 ? hex : hex.slice(2);
      return '#' + byte.toString(16).padStart(2, '0') + rgb;
    }
  }
  return color;
}

/** 这个颜色是不是透明的（编辑器读回时判断「有没有荧光笔」） */
export function isTransparentColor(color: ResourceColor | undefined): boolean {
  if (color === undefined) {
    return true;
  }
  if (typeof color === 'string') {
    return color === 'transparent' || color === '#00000000';
  }
  if (typeof color === 'number') {
    // 0xAARRGGBB：Color.Transparent / 0x00000000 的 alpha 字节都是 0
    return (color >>> 24) === 0;
  }
  return false;
}

/** 一套主题的富文本排版参数（fp） */
export class RichTextAppearance {
  /** 正文字号（素笺 17，皮革 / 肯特 14） */
  fontSize: number;
  /** 正文行高：round(fontSize × 1.43 + (行距 - 8)) —— v1 调优值的等比放大 */
  bodyLineHeight: number;
  /** 小标题字号：round(fontSize × 1.25) */
  headingFontSize: number;
  /** 小标题行高：round(headingFontSize × 1.36) */
  headingLineHeight: number;
  /** 荧光笔色（每主题一支，iOS 同款） */
  highlightColor: ResourceColor;
  /** 荧光笔色块圆角：round(fontSize × 0.16) */
  highlightRadius: number;
  /** 正文 / 小标题文字颜色 */
  textColor: ResourceColor;
  /** 字体族（Q6 未定：先系统衬线占位） */
  fontFamily: string;
  /** 补记的墨色（R-INK-04：之后添的字换一种墨）。三主题 iOS 同款，默认肯特 */
  laterInkColor: ResourceColor = '#34507A';
  /** 痕迹行 / 补记段标的小字颜色（iOS `labelColor` = theme.textTertiary） */
  labelColor: ResourceColor = Color.Gray;
  /** 墨迹干湿的基准时刻（日记写下时刻，Unix 秒）。undefined = 还在写的新稿（一律不干） */
  inkBaseSec: number | undefined = undefined;

  constructor(fontSize: number, lineSpacing: number, highlightColor: ResourceColor,
    textColor: ResourceColor, fontFamily: string) {
    this.fontSize = fontSize;
    this.bodyLineHeight = Math.round(fontSize * 1.43 + (lineSpacing - 8));
    this.headingFontSize = Math.round(fontSize * 1.25);
    this.headingLineHeight = Math.round(this.headingFontSize * 1.36);
    this.highlightColor = highlightColor;
    this.highlightRadius = Math.round(fontSize * 0.16);
    this.textColor = textColor;
    this.fontFamily = fontFamily;
  }

  /** 素笺 / 皮革 / 肯特各自的排版参数（字号与荧光笔色是 iOS 主题同款） */
  static forTheme(theme: AppTheme): RichTextAppearance {
    let appearance: RichTextAppearance;
    switch (theme.id) {
      case 'bamboo':
        appearance = new RichTextAppearance(17, 10, '#99F4D46A', theme.textPrimary, theme.bodyFont.family);
        break;
      case 'leather':
        appearance = new RichTextAppearance(14, 8, '#8CB8862B', theme.textPrimary, theme.bodyFont.family);
        break;
      case 'kent':
        appearance = new RichTextAppearance(14, 8, '#B3FFE15A', theme.textPrimary, theme.bodyFont.family);
        break;
      default:
        // 未配排版参数的主题：按正文字号推导，荧光笔暂用强调色打底
        appearance = new RichTextAppearance(theme.bodyFont.size, theme.bodyLineSpacing,
          theme.accentBackground, theme.textPrimary, theme.bodyFont.family);
        break;
    }
    // 墨迹 2.8：补记墨色三主题 iOS 同款（素笺 #3E5470 / 皮革 #A9B9CC / 肯特 #34507A），
    // 痕迹小字色 = theme.textTertiary（iOS labelColor）
    if (theme.id === 'bamboo') {
      appearance.laterInkColor = '#3E5470';
    } else if (theme.id === 'leather') {
      appearance.laterInkColor = '#A9B9CC';
    } else {
      appearance.laterInkColor = '#34507A';
    }
    appearance.labelColor = theme.textTertiary;
    return appearance;
  }

  /** 编辑器基础样式（typingStyle / 装载空文档 / 占位符字号共用） */
  baseTextStyle(): RichEditorTextStyle {
    return {
      fontSize: this.fontSize,
      fontWeight: FontWeight.Normal,
      fontFamily: this.fontFamily,
      fontColor: this.textColor,
      lineHeight: this.bodyLineHeight,
      halfLeading: true,
      textBackgroundStyle: {
        color: Color.Transparent,
        radius: this.highlightRadius
      }
    };
  }

  /**
   * 一组格式 → 编辑器文字样式。
   * **恒带 textBackgroundStyle**（没荧光笔也写透明色）：
   * updateSpanStyle 按区间整体替换样式，不带它擦不掉已划的荧光笔。
   * 墨迹（2.8）：补记的字换 laterInkColor（R-INK-04）；划掉的字变淡 + 删除线
   * （iOS `StyledText`：isAddendum ? laterInkColor : textColor，struck → 0.42 + 删除线）。
   */
  textStyleFor(flags: RichFormatFlags): RichEditorTextStyle {
    let ink: ResourceColor = this.textColor;
    if (flags.writtenAt !== undefined && this.inkBaseSec !== undefined &&
      Ink.isAddendum(flags.writtenAt, this.inkBaseSec)) {
      ink = this.laterInkColor;
    }
    if (flags.struckAt !== undefined) {
      ink = inkColorWithAlpha(ink, 0.42);
    }
    const style: RichEditorTextStyle = {
      fontSize: flags.heading ? this.headingFontSize : this.fontSize,
      fontWeight: flags.heading || flags.bold ? FontWeight.Bold : FontWeight.Normal,
      fontFamily: this.fontFamily,
      fontColor: ink,
      lineHeight: flags.heading ? this.headingLineHeight : this.bodyLineHeight,
      halfLeading: true,
      fontStyle: flags.italic ? FontStyle.Italic : FontStyle.Normal,
      textBackgroundStyle: {
        color: flags.highlight ? this.highlightColor : Color.Transparent,
        radius: this.highlightRadius
      }
    };
    if (flags.struckAt !== undefined) {
      style.decoration = {
        type: TextDecorationType.LineThrough,
        color: ink
      };
    }
    return style;
  }
}
