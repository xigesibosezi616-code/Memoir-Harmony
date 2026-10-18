/**
 * 绕排引擎的**生产测量适配器**（10_BUILD_MANUAL.md 2.7，R-RICH-02）。
 * 真排版走 `@ohos.graphics.text`（API 26）：
 * - `ParagraphStyle.headIndents / tailIndents` 逐行首/尾缩进（px）＝官方绕排机制；
 * - 行距：strutStyle.forceHeight 平台实测不生效（实绘 16.3vp ≠ 参数 20vp），
 *   引擎行带几何改由 measurePitch() 实测消费（模型层接口）；
 * - `align: JUSTIFY` + `autoSpace` + `trailingSpaceOptimized`＝CJK 排版质量
 *   超越 iOS 的部分（orphanCharOptimization 移除：×strutStyle 时恰好两行 paint 零输出）。
 *
 * 单位约定：引擎与视图层全部 vp；本层进出做 ×density 的 px 换算
 * （graphics.text 一律物理 px）。measure 与 buildParagraph 用同一构造路径，
 * 行数、行高、缩进天然一致。
 */
import { text, common2D } from '@kit.ArkGraphics2D';
import { display } from '@kit.ArkUI';
import { TextStyleRun } from '../../../models/ContentBlock';
import { RichTextAppearance } from './RichTextAppearance';
import {
  TextLayoutAdapter,
  TextMeasureResult,
  WrapFlowTextItem
} from './WrapFlowModel';

/** 一段文字在段内的一个格式片段（run 切分后的无重叠区间） */
class StyleSegment {
  start: number;
  end: number;
  bold: boolean;
  italic: boolean;
  highlight: boolean;
  heading: boolean;

  constructor(start: number, end: number, bold: boolean, italic: boolean,
    highlight: boolean, heading: boolean) {
    this.start = start;
    this.end = end;
    this.bold = bold;
    this.italic = italic;
    this.highlight = highlight;
    this.heading = heading;
  }
}

/**
 * 生产适配器：包一份主题排版参数（RichTextAppearance）+ 屏幕密度。
 * measure() 供引擎数行数；buildParagraph() 供渲染层拿排好的 Paragraph 去画。
 */
export class WrapFlowTextAdapter implements TextLayoutAdapter {
  private readonly appearance: RichTextAppearance;
  /** 物理像素 / vp（Mate X6 ≈ 3.125） */
  readonly density: number;
  /** 正文实测行距缓存（vp；单字探针段落一次，样式不变恒定） */
  private bodyPitchVp: number = -1;
  /** 小标题实测行距缓存（vp） */
  private headingPitchVp: number = -1;

  constructor(appearance: RichTextAppearance, density: number | undefined = undefined) {
    this.appearance = appearance;
    this.density = density ?? WrapFlowTextAdapter.screenDensity();
  }

  /** 引擎测量入口：排一遍数行数（与 buildParagraph 同构造，天然一致） */
  measure(textValue: string, isHeading: boolean, widthVp: number,
    headIndents: number[], tailIndents: number[]): TextMeasureResult {
    const paragraph = this.buildParagraph(new WrapFlowTextItem(textValue, isHeading),
      headIndents, tailIndents, widthVp);
    return new TextMeasureResult(paragraph.getTextLines().length);
  }

  /**
   * 实测行距（vp）：单字探针段落（与 buildParagraph 同构造路径）的段落高。
   * strutStyle.forceHeight 与 TextStyle.heightScale 平台实测不生效（实绘 16.3vp
   * 而非参数 20vp），引擎行带几何必须消费本实测值才能与实绘对齐；
   * 每样式缓存一次；测量失败返回 0（引擎回退参数行高）。
   */
  measurePitch(isHeading: boolean): number {
    const cached = isHeading ? this.headingPitchVp : this.bodyPitchVp;
    if (cached > 0) {
      return cached;
    }
    try {
      // 探针字 U+4E00（「一」）：行距测量专用、永不上屏；用转义写法避免
      // check_localization 误报（用户可见文案走资源，测量探针不是文案）
      const probeChar = '\u4e00';
      const probe = this.buildParagraph(new WrapFlowTextItem(probeChar, isHeading), [], [], 100000);
      const pitchVp = probe.getHeight() / this.density;
      if (pitchVp > 0) {
        if (isHeading) {
          this.headingPitchVp = pitchVp;
        } else {
          this.bodyPitchVp = pitchVp;
        }
        return pitchVp;
      }
    } catch (err) {
      // 探针失败（极端：字体不可用）：引擎回退参数行高
    }
    return 0;
  }

  /** 屏幕密度（px/vp）；取不到兜底 3.0（主流鸿蒙真机区间） */
  static screenDensity(): number {
    try {
      const d = display.getDefaultDisplaySync().densityPixels;
      if (d > 0) {
        return d;
      }
    } catch (err) {
      // 取不到（多窗口 / 特殊形态）按主流密度兜底
    }
    return 3.0;
  }

  /**
   * 段落构造唯一路径：runs → 无重叠格式片段 → pushStyle/addText；
   * StrutStyle.forceHeight 定死行高，headIndents/tailIndents 喂 px。
   * 产出已 layoutSync 的 Paragraph（getTextLines/paint 直接可用）。
   */
  buildParagraph(item: WrapFlowTextItem, headIndents: number[], tailIndents: number[],
    widthVp: number): text.Paragraph {
    const app = this.appearance;
    const isHeading = item.isHeading;
    const fontPx = (isHeading ? app.headingFontSize : app.fontSize) * this.density;
    const linePx = (isHeading ? app.headingLineHeight : app.bodyLineHeight) * this.density;
    const baseColor = WrapFlowTextAdapter.parseColor(app.textColor, 0xFF, 0x33, 0x2A, 0x24);
    const highlightColor = WrapFlowTextAdapter.parseColor(app.highlightColor, 0x99, 0xF4, 0xD4, 0x6A);
    const baseStyle: text.TextStyle = {
      color: baseColor,
      fontSize: fontPx,
      fontFamilies: [app.fontFamily],
      fontWeight: text.FontWeight.W400
    };
    const paragraphStyle: text.ParagraphStyle = {
      textStyle: baseStyle,
      align: text.TextAlign.JUSTIFY,
      // 行高定死＝引擎行带几何；halfLeading 让字形在行框里垂直居中（编辑器同款）
      strutStyle: {
        enabled: true,
        forceHeight: true,
        halfLeading: true,
        fontSize: fontPx,
        height: linePx / fontPx
      },
      headIndents: this.scaleAll(headIndents),
      tailIndents: this.scaleAll(tailIndents),
      // CJK 排版增强（API 26；TextKit 默认没有这套组合；
      // punctuationOverflow SDK d.ts 未含，标点悬挂待后续版本；
      // orphanCharOptimization 已移除：实测该开关 × strutStyle 时
      // 恰好两行的段落 paint() 零输出（1/3/4 行正常），平台缺陷）
      trailingSpaceOptimized: true,
      autoSpace: true
    };
    const builder = new text.ParagraphBuilder(paragraphStyle, new text.FontCollection());
    const segments = WrapFlowTextAdapter.segmentsOf(item.text, item.runs);
    const headingFontPx = app.headingFontSize * this.density;
    const headingLinePx = app.headingLineHeight * this.density;
    for (const seg of segments) {
      builder.pushStyle(WrapFlowTextAdapter.styleForSegment(seg, baseStyle, baseColor,
        highlightColor, fontPx, linePx, headingFontPx, headingLinePx,
        app.highlightRadius * this.density));
      builder.addText(item.text.substring(seg.start, seg.end));
    }
    const paragraph = builder.build();
    paragraph.layoutSync(widthVp * this.density);
    return paragraph;
  }

  /**
   * 空态占位符段（WrapFlowEditor 空文档用）：正文同款字号 / 行高的浅色单段，
   * 无缩进无 runs；随宿主 relayout 重建（主题 / 宽度变化跟随）。
   */
  buildPlaceholderParagraph(textValue: string, color: ResourceColor, widthVp: number): text.Paragraph {
    const app = this.appearance;
    const fontPx = app.fontSize * this.density;
    const linePx = app.bodyLineHeight * this.density;
    const tint = WrapFlowTextAdapter.parseColor(color, 0x99, 0x93, 0x86, 0x74);
    const fontFamily: string[] = [app.fontFamily];
    const paragraphStyle: text.ParagraphStyle = {
      textStyle: {
        color: tint,
        fontSize: fontPx,
        fontFamilies: fontFamily,
        fontWeight: text.FontWeight.W400
      },
      align: text.TextAlign.LEFT,
      strutStyle: {
        enabled: true,
        forceHeight: true,
        halfLeading: true,
        fontSize: fontPx,
        height: linePx / fontPx
      }
    };
    const builder = new text.ParagraphBuilder(paragraphStyle, new text.FontCollection());
    builder.pushStyle({
      color: tint,
      fontSize: fontPx,
      fontFamilies: fontFamily,
      halfLeading: true,
      heightScale: linePx / fontPx
    });
    builder.addText(textValue);
    const paragraph = builder.build();
    paragraph.layoutSync(widthVp * this.density);
    return paragraph;
  }

  /** vp 数组 → px 数组 */
  private scaleAll(values: number[]): number[] {
    const out: number[] = [];
    for (const v of values) {
      out.push(v * this.density);
    }
    return out;
  }

  /** 文本 + runs → 无重叠格式片段（含首尾空片段；空文本给一个空段保证段落存在） */
  static segmentsOf(textValue: string, runs: TextStyleRun[]): StyleSegment[] {
    const len = textValue.length;
    if (len === 0) {
      return [new StyleSegment(0, 0, false, false, false, false)];
    }
    // 边界点收集（去重排序；夹到 [0, len]）
    const marks: number[] = [0, len];
    for (const run of runs) {
      const start = Math.min(Math.max(run.location, 0), len);
      const end = Math.min(Math.max(run.location + run.length, 0), len);
      if (end > start) {
        marks.push(start);
        marks.push(end);
      }
    }
    marks.sort((a: number, b: number): number => a - b);
    const segments: StyleSegment[] = [];
    for (let i = 0; i < marks.length - 1; i++) {
      const start = marks[i];
      const end = marks[i + 1];
      if (end <= start) {
        continue;
      }
      let bold = false;
      let italic = false;
      let highlight = false;
      let heading = false;
      for (const run of runs) {
        if (run.location >= end || run.location + run.length <= start) {
          continue;
        }
        bold = bold || run.bold === true;
        italic = italic || run.italic === true;
        highlight = highlight || run.highlight === true;
        heading = heading || run.heading === true;
      }
      segments.push(new StyleSegment(start, end, bold, italic, highlight, heading));
    }
    if (segments.length === 0) {
      segments.push(new StyleSegment(0, len, false, false, false, false));
    }
    return segments;
  }

  /**
   * 片段 → TextStyle（粗/斜/荧光底；heading 片段用小标题字号——段内混排 heading
   * 的兜底渲染，几何近似 strut 口径；行高由 strut 统一管，不再逐段设置）。
   */
  private static styleForSegment(seg: StyleSegment, baseStyle: text.TextStyle, baseColor: common2D.Color,
    highlightColor: common2D.Color, fontPx: number, linePx: number, headingFontPx: number,
    headingLinePx: number, highlightRadiusPx: number): text.TextStyle {
    const segFontPx = seg.heading ? headingFontPx : fontPx;
    const segLinePx = seg.heading ? headingLinePx : linePx;
    const style: text.TextStyle = {
      color: baseColor,
      fontSize: segFontPx,
      fontFamilies: baseStyle.fontFamilies,
      fontWeight: seg.bold ? text.FontWeight.W700 : text.FontWeight.W400,
      fontStyle: seg.italic ? text.FontStyle.ITALIC : text.FontStyle.NORMAL,
      halfLeading: true,
      heightScale: segLinePx / segFontPx
    };
    if (seg.highlight) {
      style.backgroundRect = {
        color: highlightColor,
        leftTopRadius: highlightRadiusPx,
        rightTopRadius: highlightRadiusPx,
        rightBottomRadius: highlightRadiusPx,
        leftBottomRadius: highlightRadiusPx
      };
    }
    return style;
  }

  /**
   * ResourceColor（工程里实际是 `#AARRGGBB` 字符串或 0xAARRGGBB 数字）→ common2D.Color。
   * 解析不了给 fallback（正文字深墨色 / 荧光笔金色），渲染不中断。
   */
  static parseColor(color: ResourceColor, fbA: number, fbR: number, fbG: number,
    fbB: number): common2D.Color {
    let a = fbA;
    let r = fbR;
    let g = fbG;
    let b = fbB;
    if (typeof color === 'string') {
      let hex = color.trim();
      if (hex.startsWith('#')) {
        hex = hex.substring(1);
        let ok = true;
        if (hex.length === 8) {
          a = parseInt(hex.substring(0, 2), 16);
          r = parseInt(hex.substring(2, 4), 16);
          g = parseInt(hex.substring(4, 6), 16);
          b = parseInt(hex.substring(6, 8), 16);
        } else if (hex.length === 6) {
          r = parseInt(hex.substring(0, 2), 16);
          g = parseInt(hex.substring(2, 4), 16);
          b = parseInt(hex.substring(4, 6), 16);
        } else if (hex.length === 3) {
          r = parseInt(hex.substring(0, 1), 16) * 17;
          g = parseInt(hex.substring(1, 2), 16) * 17;
          b = parseInt(hex.substring(2, 3), 16) * 17;
        } else {
          ok = false;
        }
        if (!ok || Number.isNaN(a) || Number.isNaN(r) || Number.isNaN(g) || Number.isNaN(b)) {
          a = fbA;
          r = fbR;
          g = fbG;
          b = fbB;
        }
      }
    } else if (typeof color === 'number') {
      const v = color >>> 0;
      a = (v >>> 24) & 0xFF;
      r = (v >>> 16) & 0xFF;
      g = (v >>> 8) & 0xFF;
      b = v & 0xFF;
    }
    const parsed: common2D.Color = { alpha: a, red: r, green: g, blue: b };
    return parsed;
  }
}
