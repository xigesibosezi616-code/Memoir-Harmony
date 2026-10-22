/**
 * 翻页阅读器的生产测量适配器（10_BUILD_MANUAL.md 3.5，R-READ-05）。
 *
 * 真排版走 `@ohos.graphics.text`：测量（`ReaderTextMeasurer`，分页器吃）与
 * 渲染（`buildBodyParagraph` / `buildWrappedParagraph`，页面视图画）用同一
 * 构造路径 —— 行数、行高天然一致，分页预算永远不会小于实绘高度。
 *
 * 行高口径：`lineHeightOf(fs, sp) = ceil(字体自然行高) + sp` —— 自然行高由
 * graphics.text 实测（不再用 1.5 倍估算），与 iOS 的 `Text.lineSpacing` 同义；
 * 渲染侧用 `heightOnly + heightScale` 把行高定死，测量/渲染一致。
 * 字体族：`serif` 在 graphics.text 里不是有效 family 名，会退默认无衬线；
 * 这里显式映射到 Noto Serif（西文）+ HarmonyOS Sans SC（中文回退，对齐 iOS
 * Georgia→PingFang 的字体链）。
 * 单位约定：接口进出 vp；graphics.text 一律物理 px（×density 换算）。
 */
import { text, common2D } from '@kit.ArkGraphics2D';
import { display } from '@kit.ArkUI';
import { HeightRun, ReaderLayout, ReaderTextMeasurer } from '../../models/ReaderPages';
import { ContentBlock, TextStyleRun } from '../../models/ContentBlock';
import { RichTextAppearance } from '../components/richtext/RichTextAppearance';
import { WrapFlowTextAdapter } from '../components/richtext/WrapFlowTextAdapter';

/** 一段文字里的一个格式片段（runs 切分后的无重叠区间；测量/渲染共用） */
class ReaderSegment {
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

/** 生产适配器：主题排版参数 + 屏幕密度；测量与渲染共用同一段落构造 */
export class ReaderTextAdapter implements ReaderTextMeasurer {
  private readonly appearance: RichTextAppearance;
  /** 物理像素 / vp */
  readonly density: number;
  private readonly charWidthCache: Map<number, number> = new Map<number, number>();
  /** 某字号在当前字体下的自然单行高度（vp），只量一次 */
  private readonly naturalHeightCache: Map<number, number> = new Map<number, number>();

  constructor(appearance: RichTextAppearance, density: number | undefined = undefined) {
    this.appearance = appearance;
    this.density = density ?? ReaderTextAdapter.screenDensity();
  }

  // ---- ReaderTextMeasurer ----

  /** 单行高度 = 字体自然行高 + 行距（iOS Text.lineSpacing 同义；
   *  不再用 1.5 倍估算，和 iOS 的 Georgia/PingFang 实际行高对齐） */
  lineHeightOf(fontSize: number, lineSpacing: number): number {
    return Math.ceil(this.naturalLineHeight(fontSize)) + lineSpacing;
  }

  /** 用 graphics.text 实测一行「国Ag」的自然行高；失败才退 1.35 倍字号 */
  private naturalLineHeight(fontSizeVp: number): number {
    const cached = this.naturalHeightCache.get(fontSizeVp);
    if (cached !== undefined) {
      return cached;
    }
    let natural = fontSizeVp * 1.35;
    try {
      const paragraph = this.rawParagraph('\u56fdAg', fontSizeVp);
      const measured = paragraph.getHeight() / this.density;
      if (measured > 0) {
        natural = measured;
      }
    } catch (err) {
      // 字体不可用：按 1.35 兜底（比旧的 1.5 更接近 iOS 实际行高）
    }
    this.naturalHeightCache.set(fontSizeVp, natural);
    return natural;
  }

  /** 字体族：iOS 正文 Georgia（西文）+ 中文回退 PingFang；
   *  鸿蒙对应 Noto Serif（西文）+ HarmonyOS Sans SC（中文）。
   *  graphics.text 不认 `serif` 这种 generic 名，必须给真实 family，否则整段退默认无衬线。 */
  private fontFamilies(): string[] {
    const family = this.appearance.fontFamily;
    if (family.length === 0 || family === 'serif') {
      return ['Noto Serif', 'HarmonyOS Sans SC'];
    }
    return [family];
  }

  charWidthOf(fontSize: number): number {
    const cached = this.charWidthCache.get(fontSize);
    if (cached !== undefined) {
      return cached;
    }
    try {
      // 探针字 U+4E00（「一」）：容量估算专用、不上屏；转义写法避免漏翻检查误报
      const probeChar = '\u4e00';
      const paragraph = this.plainParagraph(probeChar, fontSize, 0, 100000);
      const widthVp = paragraph.getLongestLine() / this.density;
      if (widthVp > 0) {
        this.charWidthCache.set(fontSize, widthVp);
        return widthVp;
      }
    } catch (err) {
      // 字体不可用：按全角字宽兜底（偏大 → 容量估算偏小 → 宁可多翻 below）
    }
    return fontSize;
  }

  heightOfStyled(textValue: string, runs: HeightRun[], width: number): number {
    if (textValue.length === 0) {
      return 0;
    }
    const paragraph = this.styledParagraph(textValue, ReaderTextAdapter.segmentsOfHeightRuns(textValue, runs),
      width);
    return Math.ceil(paragraph.getHeight() / this.density);
  }

  fittingLength(textValue: string, runs: HeightRun[], width: number, height: number): number {
    const len = textValue.length;
    if (len === 0) {
      return 0;
    }
    // 二分：最大的 n 使前缀高度 ≤ height（前缀高度随 n 单调不减）
    let lo = 0;
    let hi = len;
    while (lo < hi) {
      const mid = Math.ceil((lo + hi) / 2);
      if (this.heightOfStyled(textValue.substring(0, mid), runs, width) <= height) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    // 退到完整字符边界（不劈开代理对）
    if (lo > 0 && lo < len) {
      const prev = textValue.charCodeAt(lo - 1);
      if (prev >= 0xD800 && prev <= 0xDBFF) {
        lo--;
      }
    }
    return lo;
  }

  heightOfPlain(textValue: string, fontSize: number, lineSpacing: number, width: number): number {
    if (textValue.length === 0) {
      return 0;
    }
    const paragraph = this.plainParagraph(textValue, fontSize, lineSpacing, width);
    return Math.ceil(paragraph.getHeight() / this.density);
  }

  // ---- 渲染构造（页面视图用；与测量同一路径） ----

  /** 全宽正文段（16/8，heading 20fp）：fullText 组、photoWithText 的 below */
  buildBodyParagraph(block: ContentBlock, widthVp: number): text.Paragraph {
    const textValue = block.text ?? '';
    return this.styledParagraph(textValue,
      ReaderTextAdapter.segmentsOfRuns(textValue, block.styles ?? []), widthVp);
  }

  /** 照片旁环绕段（15/11，heading 20fp）：photoWithText 的 beside */
  buildWrappedParagraph(block: ContentBlock, widthVp: number): text.Paragraph {
    const textValue = block.text ?? '';
    const segments = ReaderTextAdapter.segmentsOfRuns(textValue, block.styles ?? []);
    return this.styledParagraphAt(textValue, segments, widthVp,
      ReaderLayout.wrappedTextFontSize, ReaderLayout.wrappedLineSpacing);
  }

  // ---- 段落构造唯一路径 ----

  /** 正文几何（16/8）的带格式段（测量 heightOfStyled 与渲染共用） */
  private styledParagraph(textValue: string, segments: ReaderSegment[],
    widthVp: number): text.Paragraph {
    return this.styledParagraphAt(textValue, segments, widthVp,
      ReaderLayout.bodyFontSize, ReaderLayout.bodyLineSpacing);
  }

  /** 指定字号 / 行距的带格式段：heightOnly 让 heightScale 生效（ArkTS 的
   *  heightScale 只在 heightOnly=true 时有效），格式逐段 pushStyle */
  private styledParagraphAt(textValue: string, segments: ReaderSegment[], widthVp: number,
    fontSizeVp: number, lineSpacingVp: number): text.Paragraph {
    const app = this.appearance;
    const ink = WrapFlowTextAdapter.parseColor(app.textColor, 0xFF, 0x33, 0x2A, 0x24);
    const highlight = WrapFlowTextAdapter.parseColor(app.highlightColor, 0x99, 0xF4, 0xD4, 0x6A);
    const fontPx = fontSizeVp * this.density;
    const headingFontPx = ReaderLayout.headingFontSize * this.density;
    const family: string[] = this.fontFamilies();
    const basePitchVp = this.lineHeightOf(fontSizeVp, lineSpacingVp);
    const paragraphStyle: text.ParagraphStyle = {
      textStyle: {
        color: ink,
        fontSize: fontPx,
        fontFamilies: family,
        fontWeight: text.FontWeight.W400,
        halfLeading: true,
        heightOnly: true,
        heightScale: basePitchVp / fontSizeVp
      },
      align: text.TextAlign.LEFT,
      autoSpace: true
    };
    const builder = new text.ParagraphBuilder(paragraphStyle, new text.FontCollection());
    if (segments.length === 0) {
      builder.pushStyle(this.segmentStyle(false, false, false, false, ink, highlight,
        fontPx, headingFontPx, fontSizeVp, lineSpacingVp, family));
      builder.addText(textValue);
    } else {
      for (const seg of segments) {
        builder.pushStyle(this.segmentStyle(seg.bold, seg.italic, seg.highlight, seg.heading,
          ink, highlight, fontPx, headingFontPx, fontSizeVp, lineSpacingVp, family));
        builder.addText(textValue.substring(seg.start, seg.end));
      }
    }
    const paragraph = builder.build();
    paragraph.layoutSync(Math.max(1, widthVp) * this.density);
    return paragraph;
  }

  /** 单行自然高度探针：不设 heightOnly / strut，量到的就是字体自己的行高 */
  private rawParagraph(textValue: string, fontSizeVp: number): text.Paragraph {
    const ink = WrapFlowTextAdapter.parseColor(this.appearance.textColor, 0xFF, 0x33, 0x2A, 0x24);
    const fontPx = fontSizeVp * this.density;
    const family: string[] = this.fontFamilies();
    const style: text.TextStyle = {
      color: ink,
      fontSize: fontPx,
      fontFamilies: family,
      fontWeight: text.FontWeight.W400,
      halfLeading: true
    };
    const paragraphStyle: text.ParagraphStyle = {
      textStyle: style,
      align: text.TextAlign.LEFT
    };
    const builder = new text.ParagraphBuilder(paragraphStyle, new text.FontCollection());
    builder.pushStyle(style);
    builder.addText(textValue);
    const paragraph = builder.build();
    paragraph.layoutSync(100000);
    return paragraph;
  }

  /** 单一样式段（无格式）：heightOfPlain / charWidthOf 探针用 */
  private plainParagraph(textValue: string, fontSizeVp: number, lineSpacingVp: number,
    widthVp: number): text.Paragraph {
    const app = this.appearance;
    const ink = WrapFlowTextAdapter.parseColor(app.textColor, 0xFF, 0x33, 0x2A, 0x24);
    const fontPx = fontSizeVp * this.density;
    const family: string[] = this.fontFamilies();
    const pitchVp = this.lineHeightOf(fontSizeVp, lineSpacingVp);
    const paragraphStyle: text.ParagraphStyle = {
      textStyle: {
        color: ink,
        fontSize: fontPx,
        fontFamilies: family,
        fontWeight: text.FontWeight.W400,
        halfLeading: true,
        heightOnly: true,
        heightScale: pitchVp / fontSizeVp
      },
      align: text.TextAlign.LEFT
    };
    const builder = new text.ParagraphBuilder(paragraphStyle, new text.FontCollection());
    builder.addText(textValue);
    const paragraph = builder.build();
    paragraph.layoutSync(Math.max(1, widthVp) * this.density);
    return paragraph;
  }

  /** 片段 → TextStyle（heading 20fp 加粗衬线 = iOS Georgia-Bold；荧光笔底色）。
   *  行高按每个片段的字号各自算（heading 行更高），与 iOS 混排行高一致 */
  private segmentStyle(bold: boolean, italic: boolean, highlight: boolean, heading: boolean,
    ink: common2D.Color, highlightColor: common2D.Color, fontPx: number, headingFontPx: number,
    fontSizeVp: number, lineSpacingVp: number, family: string[]): text.TextStyle {
    const segFontVp = heading ? ReaderLayout.headingFontSize : fontSizeVp;
    const segFontPx = heading ? headingFontPx : fontPx;
    const segPitchVp = this.lineHeightOf(segFontVp, lineSpacingVp);
    const style: text.TextStyle = {
      color: ink,
      fontSize: segFontPx,
      fontFamilies: family,
      fontWeight: bold || heading ? text.FontWeight.W700 : text.FontWeight.W400,
      fontStyle: italic ? text.FontStyle.ITALIC : text.FontStyle.NORMAL,
      halfLeading: true,
      heightOnly: true,
      heightScale: segPitchVp / segFontVp
    };
    if (highlight) {
      style.backgroundRect = {
        color: highlightColor,
        leftTopRadius: this.appearance.highlightRadius * this.density,
        rightTopRadius: this.appearance.highlightRadius * this.density,
        rightBottomRadius: this.appearance.highlightRadius * this.density,
        leftBottomRadius: this.appearance.highlightRadius * this.density
      };
    }
    return style;
  }

  // ---- runs → 片段 ----

  /** 渲染用：完整 TextStyleRun[] → 无重叠片段（粗/斜/荧光/小标题全字段） */
  static segmentsOfRuns(textValue: string, runs: TextStyleRun[]): ReaderSegment[] {
    const len = textValue.length;
    if (len === 0) {
      return [];
    }
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
    const segments: ReaderSegment[] = [];
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
      segments.push(new ReaderSegment(start, end, bold, italic, highlight, heading));
    }
    return segments;
  }

  /** 测量用：HeightRun[] → 无重叠片段（只有 heading 影响高度） */
  static segmentsOfHeightRuns(textValue: string, runs: HeightRun[]): ReaderSegment[] {
    const len = textValue.length;
    if (len === 0) {
      return [];
    }
    const segments: ReaderSegment[] = [];
    let cursor = 0;
    const sorted: HeightRun[] = [];
    for (const run of runs) {
      if (run.heading && run.length > 0) {
        sorted.push(run);
      }
    }
    sorted.sort((a: HeightRun, b: HeightRun): number => a.location - b.location);
    for (const run of sorted) {
      const start = Math.min(Math.max(run.location, 0), len);
      const end = Math.min(Math.max(run.location + run.length, 0), len);
      if (end <= start || start < cursor) {
        continue; // 越界 / 重叠的片段跳过
      }
      if (start > cursor) {
        segments.push(new ReaderSegment(cursor, start, false, false, false, false));
      }
      segments.push(new ReaderSegment(start, end, false, false, false, true));
      cursor = end;
    }
    if (cursor < len) {
      segments.push(new ReaderSegment(cursor, len, false, false, false, false));
    }
    return segments;
  }

  /** 屏幕密度（px/vp）；取不到兜底 3.0 */
  static screenDensity(): number {
    try {
      const d = display.getDefaultDisplaySync().densityPixels;
      if (d > 0) {
        return d;
      }
    } catch (err) {
      // 取不到按主流密度兜底
    }
    return 3.0;
  }
}
