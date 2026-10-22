/**
 * 翻页阅读器的纯逻辑层（10_BUILD_MANUAL.md 3.5）。对应 iOS
 * `Reader/Paginator.swift`（版式常量在 `ReaderLayout`）+ `PageDataSource.swift`
 * + `ContentBlockRenderer.swift` 的 renderGroups 分组算法。
 *
 * - **先算后画**（R-READ-05）：`ReaderLayout` 的版式尺寸分页器和页面视图
 *   共用一份，两边各写一份数字就会有一页装不下、正文被静默截断。
 * - 文本测量走注入的 `ReaderTextMeasurer`（生产实现是 graphics.text 同构造
 *   段落，测量与渲染同一路径；单测用确定性 mock）。
 * - 全部纯函数 / 纯类，不依赖 ArkUI —— 单测见 ReaderPages.test.ets。
 */
import { JournalEntry } from './JournalEntry';
import { ContentBlock, ContentBlockType, TextStyleRun } from './ContentBlock';
import { readingOrderSort } from '../data/BookContentsLogic';

/**
 * 阅读器版式常量（vp / fp）。iOS `ReaderLayout` 同名同值；
 * 分页（`paginateEntry`）和页面视图（`views/reader/ReaderPageView`）共用。
 */
export class ReaderLayout {
  /** 页面左右留白 */
  static readonly hInset: number = 20;
  /** 内容顶部距安全区的距离（左上角悬浮返回按钮占安全区下 8~44，要让开） */
  static readonly topInset: number = 56;
  /** 内容底部距安全区的距离 */
  static readonly bottomInset: number = 30;

  /** 正文字号与行距 */
  static readonly bodyFontSize: number = 16;
  static readonly bodyLineSpacing: number = 8;
  /** 相邻内容块之间的间距（与页面视图的块间距一致） */
  static readonly blockSpacing: number = 12;
  /** 正文区顶部的额外留白 */
  static readonly bodyTopGap: number = 6;

  /** 续页顶部的小标题（提示当前在读哪一篇） */
  static readonly runningTitleFontSize: number = 11;
  static readonly runningTitleBottomGap: number = 10;
  /** 首页页眉与正文之间的间距 */
  static readonly headerBottomGap: number = 14;

  /** 页脚页码 */
  static readonly pageNumberFontSize: number = 11;
  static readonly pageNumberTopGap: number = 8;

  /** 照片块在页面中的标称高度（相纸样式；渲染侧同值封顶） */
  static readonly photoBlockHeight: number = 280;

  /** 测量与渲染的细微差异留的余量。宁可页底多一点空白，不能挤掉正文 */
  static readonly safetyMargin: number = 8;

  /** 小标题字号（格式见 TextStyleRun.heading） */
  static readonly headingFontSize: number = 20;

  /** 录音卡高度（AudioPlayerCard：36 圆钮 + 上下 12 内边距） */
  static readonly audioBlockHeight: number = 60;
  /** 痕迹行高度（12fp 小字 + 上 2 下 6 内边距） */
  static readonly traceBlockHeight: number = 25;

  /** 照片旁环绕文字的字号与行距（iOS ContentBlockRenderer LayoutConstants） */
  static readonly wrappedTextFontSize: number = 15;
  static readonly wrappedLineSpacing: number = 11;
  /** 照片宽度占正文宽比例（iOS ContentBlockRenderer photoWidthRatio） */
  static readonly photoWidthRatio: number = 0.45;
  /** 照片与环绕文字的间距 */
  static readonly photoTextGap: number = 12;

  /** 大屏单列封顶（vp）：页宽超过它时居中收窄。iOS 整窗即页；鸿蒙展开大屏
   *  不限宽会让照片卡超出 280 标称预算、正文被截断，故封顶（书页感也更好） */
  static readonly maxPageWidth: number = 420;
}

/**
 * 文本测量器：分页与渲染共用的唯一边界（生产实现
 * `views/reader/ReaderTextAdapter`，graphics.text 同构造段落；单测用 mock）。
 * 全部 vp；返回值向上取整（偏大无妨——页底留白，偏小才会截断正文）。
 */
export interface ReaderTextMeasurer {
  /** 一段带格式文字在 `width` 宽度下排完的高度（heading 段用大字号，与渲染一致） */
  heightOfStyled(text: string, runs: HeightRun[], width: number): number;
  /** `text` 在 `width × height` 的框里从头能排下多少字符（UTF-16，
   *  已退到完整字符边界，不会把 emoji 之类的组合字符从中间劈开） */
  fittingLength(text: string, runs: HeightRun[], width: number, height: number): number;
  /** 单行高度（字号行高 + 行距；0 行距 = 纯行高） */
  lineHeightOf(fontSize: number, lineSpacing: number): number;
  /** 一个参考字符（「字」）在该字号下的宽度 —— 环绕容量的每行字数估算用 */
  charWidthOf(fontSize: number): number;
  /** 无格式文字按字号 / 行距在 `width` 宽度下排完的高度（页眉标题用） */
  heightOfPlain(text: string, fontSize: number, lineSpacing: number, width: number): number;
}

/** 高度测量关心的格式片段（TextStyleRun 的精简投影；只有 heading 影响高度） */
export class HeightRun {
  location: number;
  length: number;
  heading: boolean;

  constructor(location: number, length: number, heading: boolean) {
    this.location = location;
    this.length = length;
    this.heading = heading;
  }
}

/** 一个渲染组（iOS ContentBlockRenderer.RenderGroup 同构） */
export enum ReaderGroupKind {
  /** 全宽文本块 */
  FullText = 'fullText',
  /** 文字环绕照片：beside（照片旁，按容量截断）+ below（照片下方，可无） */
  PhotoWithText = 'photoWithText',
  /** 无环绕文字的独立照片（相邻照片 / 开头照片） */
  StandalonePhoto = 'standalonePhoto',
  /** 录音（单独一行的播放卡片） */
  Audio = 'audio',
  /** 痕迹（取下的照片 / 删去的录音） */
  Trace = 'trace'
}

/** 一页正文里的一个渲染组 */
export class ReaderRenderGroup {
  readonly kind: ReaderGroupKind;
  /** fullText 的文本块 */
  readonly textBlock: ContentBlock | undefined;
  /** photoWithText 照片旁的环绕文字（已按容量截断，带格式） */
  readonly besideBlock: ContentBlock | undefined;
  /** photoWithText 照片下方的剩余文字（可无，带格式） */
  readonly belowBlock: ContentBlock | undefined;
  /** photoWithText / standalonePhoto 的照片块 */
  readonly photoBlock: ContentBlock | undefined;
  /** audio / trace 的块本体 */
  readonly anchorBlock: ContentBlock | undefined;

  private constructor(kind: ReaderGroupKind, textBlock: ContentBlock | undefined,
    besideBlock: ContentBlock | undefined, belowBlock: ContentBlock | undefined,
    photoBlock: ContentBlock | undefined, anchorBlock: ContentBlock | undefined) {
    this.kind = kind;
    this.textBlock = textBlock;
    this.besideBlock = besideBlock;
    this.belowBlock = belowBlock;
    this.photoBlock = photoBlock;
    this.anchorBlock = anchorBlock;
  }

  /** 全宽文本块 */
  static fullText(block: ContentBlock): ReaderRenderGroup {
    return new ReaderRenderGroup(ReaderGroupKind.FullText, block, undefined, undefined,
      undefined, undefined);
  }

  /** 文字环绕照片 */
  static photoWithText(beside: ContentBlock, photo: ContentBlock,
    below: ContentBlock | undefined): ReaderRenderGroup {
    return new ReaderRenderGroup(ReaderGroupKind.PhotoWithText, undefined, beside, below,
      photo, undefined);
  }

  /** 独立照片 */
  static standalonePhoto(photo: ContentBlock): ReaderRenderGroup {
    return new ReaderRenderGroup(ReaderGroupKind.StandalonePhoto, undefined, undefined,
      undefined, photo, undefined);
  }

  /** 录音卡片 */
  static audio(block: ContentBlock): ReaderRenderGroup {
    return new ReaderRenderGroup(ReaderGroupKind.Audio, undefined, undefined, undefined,
      undefined, block);
  }

  /** 痕迹行 */
  static trace(block: ContentBlock): ReaderRenderGroup {
    return new ReaderRenderGroup(ReaderGroupKind.Trace, undefined, undefined, undefined,
      undefined, block);
  }
}

/** 页的种类 */
export enum ReaderPageKind {
  /** 正文页（首页带页眉，续页带小标题） */
  Content = 'content',
  /** 结尾页「已读完所有日记」 */
  Ending = 'ending'
}

/** 一页（iOS `PageData` 同构；渲染态、不持久化） */
export class ReaderPage {
  readonly kind: ReaderPageKind;
  readonly entry: JournalEntry;
  /** 本篇第几页（0 起；ending 页无意义） */
  readonly pageIndex: number;
  /** 本篇共几页 */
  readonly totalPages: number;
  /** 本页渲染组（正文页） */
  readonly groups: ReaderRenderGroup[];

  constructor(kind: ReaderPageKind, entry: JournalEntry, pageIndex: number,
    totalPages: number, groups: ReaderRenderGroup[]) {
    this.kind = kind;
    this.entry = entry;
    this.pageIndex = pageIndex;
    this.totalPages = totalPages;
    this.groups = groups;
  }
}

/** 页面几何（vp；分页与页面视图共用，视图按同一尺寸画） */
export class ReaderGeometry {
  /** 整页宽高（含安全区外） */
  pageWidth: number;
  pageHeight: number;
  safeTop: number;
  safeBottom: number;

  constructor(pageWidth: number, pageHeight: number, safeTop: number, safeBottom: number) {
    this.pageWidth = pageWidth;
    this.pageHeight = pageHeight;
    this.safeTop = safeTop;
    this.safeBottom = safeBottom;
  }

  /** 正文可用宽度（页面视图照片宽度也按它算，两边必须一致） */
  contentWidth(): number {
    const pageW = Math.min(this.pageWidth, ReaderLayout.maxPageWidth);
    return Math.max(0, pageW - ReaderLayout.hInset * 2);
  }

  /** 一页里留给「页眉/小标题 + 正文」的高度（iOS contentAreaHeight 同款扣减） */
  contentAreaHeight(measurer: ReaderTextMeasurer): number {
    return this.pageHeight - this.safeTop - this.safeBottom
      - ReaderLayout.topInset - ReaderLayout.bottomInset
      - ReaderLayout.pageNumberTopGap
      - measurer.lineHeightOf(ReaderLayout.pageNumberFontSize, 0)
      - ReaderLayout.bodyTopGap - ReaderLayout.safetyMargin;
  }
}

/** 页眉的版式数字（iOS DiaryPageHeader.Metrics 同名同值）。改字号 / 间距时
 *  `estimateHeaderHeight` 会自动跟上，但**加新的一行元素要同步加进去**，否则首页装不下 */
export class ReaderHeaderMetrics {
  static readonly monthFontSize: number = 11;
  static readonly monthBottomGap: number = 4;
  static readonly dayTensFontSize: number = 36;
  static readonly dayOnesFontSize: number = 56;
  static readonly dayTopGap: number = 2;
  /** 印章是固定 56vp 的圆（见 StampView），与日期数字并排 */
  static readonly stampSize: number = 56;
  static readonly weekdayFontSize: number = 13;
  static readonly weekdayTopGap: number = 2;
  static readonly weekdayBottomGap: number = 16;
  static readonly dividerWidth: number = 32;
  static readonly dividerBottomGap: number = 20;
  static readonly titleFontSize: number = 22;
  static readonly titleLineSpacing: number = 4;
  static readonly titleBottomGap: number = 10;
  static readonly tagFontSize: number = 11;
  static readonly tagVerticalPadding: number = 3;
}

/** 页眉高度估算（iOS DiaryPageHeader.estimatedHeight 同款）：供分页器给首页正文留位置。
 *  偏大无妨（首页底部多点留白），偏小才会挤掉正文 */
export function estimateHeaderHeight(entry: JournalEntry, width: number,
  measurer: ReaderTextMeasurer): number {
  const m = ReaderHeaderMetrics;
  let h = 0;
  h += measurer.lineHeightOf(m.monthFontSize, 0) + m.monthBottomGap;
  h += m.dayTopGap + Math.max(measurer.lineHeightOf(m.dayOnesFontSize, 0), m.stampSize);
  h += m.weekdayTopGap + measurer.lineHeightOf(m.weekdayFontSize, 0) + m.weekdayBottomGap;
  h += 1 + m.dividerBottomGap;
  if (entry.title.length > 0) {
    h += measurer.heightOfPlain(entry.title, m.titleFontSize, m.titleLineSpacing, width);
    h += m.titleBottomGap;
  }
  if (entry.tags.length > 0) {
    h += measurer.lineHeightOf(m.tagFontSize, 0) + m.tagVerticalPadding * 2;
  }
  return Math.ceil(h);
}

// ---- 文本块切分辅助 ----

/** UTF-16 下标退到完整字符边界（不把代理对从中间劈开） */
function retreatToCharBoundary(text: string, index: number): number {
  if (index > 0 && index < text.length) {
    const prev = text.charCodeAt(index - 1);
    if (prev >= 0xD800 && prev <= 0xDBFF) {
      return index - 1;
    }
  }
  return index;
}

/** 文本块 → 高度测量用的格式投影（只有 heading 影响高度；粗斜体不改变行高） */
function heightRunsOf(block: ContentBlock): HeightRun[] {
  const runs = block.styles;
  if (runs === undefined) {
    return [];
  }
  const out: HeightRun[] = [];
  for (const run of runs) {
    if (run.heading === true && run.length > 0) {
      out.push(new HeightRun(run.location, run.length, true));
    }
  }
  return out;
}

/** 复制一段格式的可选标志与时间字段到 `target`（字段全量拷贝） */
function copyRunFlags(source: TextStyleRun, target: TextStyleRun): void {
  if (source.bold === true) {
    target.bold = true;
  }
  if (source.italic === true) {
    target.italic = true;
  }
  if (source.heading === true) {
    target.heading = true;
  }
  if (source.highlight === true) {
    target.highlight = true;
  }
  if (source.writtenAt !== undefined) {
    target.writtenAt = source.writtenAt;
  }
  if (source.struckAt !== undefined) {
    target.struckAt = source.struckAt;
  }
}

/** 把 `block.styles` 里落在 [start, start+len) 的段裁出来放到 `target`（格式跟着拆） */
function copySlicedStyles(source: ContentBlock, target: ContentBlock, start: number, len: number): void {
  const runs = source.styles;
  if (runs === undefined || len <= 0) {
    return;
  }
  const sliced: TextStyleRun[] = [];
  for (const run of runs) {
    const rs = Math.max(run.location, start);
    const re = Math.min(run.location + run.length, start + len);
    if (re <= rs) {
      continue;
    }
    const moved = new TextStyleRun(rs - start, re - rs);
    copyRunFlags(run, moved);
    sliced.push(moved);
  }
  if (sliced.length > 0) {
    target.styles = sliced;
  }
}

/** 把多个文本块合并成一个（"\n" 连接，格式按偏移平移；iOS renderGroups 的 merged 同款） */
function mergeTextBlocks(parts: ContentBlock[], makeId: () => string): ContentBlock {
  let text = '';
  const mergedRuns: TextStyleRun[] = [];
  for (const part of parts) {
    const partText = part.text ?? '';
    if (text.length > 0) {
      text += '\n';
    }
    const offset = text.length;
    text += partText;
    const runs = part.styles;
    if (runs !== undefined) {
      for (const run of runs) {
        const moved = new TextStyleRun(run.location + offset, run.length);
        copyRunFlags(run, moved);
        mergedRuns.push(moved);
      }
    }
  }
  const merged = ContentBlock.makeText(makeId(), text);
  if (mergedRuns.length > 0) {
    merged.styles = mergedRuns;
  }
  return merged;
}

/** 在字符数 `cap` 处把文本块切成前后两段（cap 退到完整字符边界）。
 *  后段为空返回 undefined */
function splitBlockAtCharCount(block: ContentBlock, cap: number,
  makeId: () => string): [ContentBlock, ContentBlock | undefined] {
  const text = block.text ?? '';
  let n = Math.min(cap, text.length);
  n = retreatToCharBoundary(text, n);
  const head = ContentBlock.makeText(makeId(), text.substring(0, n));
  copySlicedStyles(block, head, 0, n);
  if (n >= text.length) {
    return [head, undefined];
  }
  const tail = ContentBlock.makeText(makeId(), text.substring(n));
  copySlicedStyles(block, tail, n, text.length - n);
  return [head, tail];
}

/** 一个块的分页高度（不含块间距；iOS Paginator.height 同款） */
function heightFor(block: ContentBlock, width: number, measurer: ReaderTextMeasurer): number {
  switch (block.type) {
    case ContentBlockType.Photo:
      return ReaderLayout.photoBlockHeight;
    case ContentBlockType.Audio:
      return ReaderLayout.audioBlockHeight;
    case ContentBlockType.Trace:
      return ReaderLayout.traceBlockHeight;
    case ContentBlockType.Text:
    default: {
      const text = block.text ?? '';
      if (text.length === 0) {
        // 空文本块在渲染时也占一行
        return measurer.heightOfStyled(' ', [], width);
      }
      return measurer.heightOfStyled(text, heightRunsOf(block), width);
    }
  }
}

/** 把文本块在 `height` 内能排下的部分切出来（iOS Paginator.split 同款）；
 *  切不出（一个字都放不下 / 整段都放得下）返回 undefined */
function splitTextBlock(block: ContentBlock, fittingHeight: number, width: number,
  measurer: ReaderTextMeasurer, makeId: () => string): [ContentBlock, ContentBlock | undefined] | undefined {
  const text = block.text ?? '';
  let n = measurer.fittingLength(text, heightRunsOf(block), width, fittingHeight);
  if (n <= 0 || n >= text.length) {
    return undefined;
  }
  // 断点恰好落在换行符之后时，head 带上尾部换行会多量出一行空行（本页放不下却放了）
  if (text.charCodeAt(n - 1) === 0x0A) {
    n--;
    if (n <= 0) {
      return undefined;
    }
  }
  // 正好断在换行处时，续页开头会多出一个空行 —— 跳过那个换行
  const tailStart = text.charCodeAt(n) === 0x0A ? n + 1 : n;
  const head = ContentBlock.makeText(makeId(), text.substring(0, n));
  copySlicedStyles(block, head, 0, n);
  if (tailStart >= text.length) {
    return [head, undefined];
  }
  const tail = ContentBlock.makeText(makeId(), text.substring(tailStart));
  copySlicedStyles(block, tail, tailStart, text.length - tailStart);
  return [head, tail];
}

/** paginateEntry 的攒页状态：ArkTS 不支持嵌套函数，收敛成类方法（语义不变） */
class EntryPageBuilder {
  readonly firstCapacity: number;
  readonly fullCapacity: number;
  readonly width: number;
  readonly measurer: ReaderTextMeasurer;
  readonly pages: ContentBlock[][] = [];
  current: ContentBlock[] = [];
  used = 0;

  constructor(firstCapacity: number, fullCapacity: number, width: number, measurer: ReaderTextMeasurer) {
    this.firstCapacity = firstCapacity;
    this.fullCapacity = fullCapacity;
    this.width = width;
    this.measurer = measurer;
  }

  /** 当前页的正文容量：第 0 页扣掉页眉，其余是整页 */
  capacity(): number {
    return this.pages.length === 0 ? this.firstCapacity : this.fullCapacity;
  }

  /** 往当前页再放一个高 h 的块，已用高度要加多少（块与块之间有间距） */
  cost(h: number): number {
    return this.current.length === 0 ? h : h + ReaderLayout.blockSpacing;
  }

  /** 当前页是一张空的续页 —— 再往后挪也不会有更大的地方了 */
  onBlankContinuationPage(): boolean {
    return this.current.length === 0 && this.pages.length > 0;
  }

  /** 续页不产出空页；第 0 页即使一个块都没放下也要出（它有页眉） */
  flush(): void {
    if (this.current.length === 0 && this.pages.length > 0) {
      return;
    }
    this.pages.push(this.current);
    this.current = [];
    this.used = 0;
  }

  place(block: ContentBlock): void {
    this.used += this.cost(heightFor(block, this.width, this.measurer));
    this.current.push(block);
  }

  /** 照片放不下时，从当前页尾部取走可随行挪页的最后一个文本块（环绕锚点，连同高度回退） */
  takeCompanion(): ContentBlock | undefined {
    const last = this.current.length > 0 ? this.current[this.current.length - 1] : undefined;
    if (last === undefined || last.type !== ContentBlockType.Text) {
      return undefined;
    }
    if (heightFor(last, this.width, this.measurer) + ReaderLayout.blockSpacing
      + ReaderLayout.photoBlockHeight > this.fullCapacity) {
      return undefined;
    }
    this.current.pop();
    this.used -= this.cost(heightFor(last, this.width, this.measurer));
    return last;
  }
}

/**
 * 一篇的分页（iOS Paginator.paginate 逐行同款移植）：
 * - 第 0 页扣页眉，续页扣小标题
 * - 文本块按真实排版测高，放不下就在能排下的位置断开，余下接下一页
 * - 照片不可分割，放不下就连同前一个文本块（环绕锚点）一起挪下一页
 * - 正文为空也至少产出一页（只有页眉）
 */
export function paginateEntry(entry: JournalEntry, geometry: ReaderGeometry,
  measurer: ReaderTextMeasurer, makeId: () => string): ReaderPage[] {
  const width = geometry.contentWidth();
  const area = geometry.contentAreaHeight(measurer);
  const firstCapacity = Math.max(0, area
    - estimateHeaderHeight(entry, width, measurer)
    - ReaderLayout.headerBottomGap);
  const fullCapacity = area
    - measurer.lineHeightOf(ReaderLayout.runningTitleFontSize, 0)
    - ReaderLayout.runningTitleBottomGap;
  const twoLines = measurer.lineHeightOf(ReaderLayout.bodyFontSize, ReaderLayout.bodyLineSpacing) * 2;

  const builder = new EntryPageBuilder(firstCapacity, fullCapacity, width, measurer);

  for (const block of entry.contentBlocks) {
    // 录音、痕迹：一行，不可拆。放不下就挪到下一页
    if (block.type === ContentBlockType.Audio || block.type === ContentBlockType.Trace) {
      if (builder.used + builder.cost(heightFor(block, width, measurer)) > builder.capacity()
        && !builder.onBlankContinuationPage()) {
        builder.flush();
      }
      builder.place(block);
      continue;
    }
    if (block.type === ContentBlockType.Photo) {
      if (builder.used + builder.cost(ReaderLayout.photoBlockHeight) <= builder.capacity()
        || builder.onBlankContinuationPage()) {
        builder.place(block);
        continue;
      }
      // 放不下：照片要带上紧挨着它的前一个文本块（环绕锚点）一起挪下一页，
      // 只搬照片的话新页上它就成了没有文字的孤图。那段文字本身太长就不带了。
      const companion = builder.takeCompanion();
      builder.flush();
      if (companion !== undefined) {
        builder.place(companion);
      }
      builder.place(block);
      continue;
    }

    // 文本块：放得下就整段放；放不下就在本页能排下的位置断开，余下的接着排
    let rest: ContentBlock | undefined = block;
    while (rest !== undefined) {
      const h = heightFor(rest, width, measurer);
      if (builder.used + builder.cost(h) <= builder.capacity()) {
        builder.place(rest);
        rest = undefined;
        continue;
      }
      const room = builder.capacity() - builder.used
        - (builder.current.length === 0 ? 0 : ReaderLayout.blockSpacing);
      const parts: [ContentBlock, ContentBlock | undefined] | undefined
        = room >= twoLines ? splitTextBlock(rest, room, width, measurer, makeId) : undefined;
      if (parts !== undefined) {
        builder.place(parts[0]);
        builder.flush();
        rest = parts[1];
      } else if (builder.onBlankContinuationPage()) {
        // 一整页都切不出东西（理论上不会发生）：硬放，保证循环一定前进
        builder.place(rest);
        rest = undefined;
      } else {
        // 本页剩余不足两行：整段挪到下一页
        builder.flush();
      }
    }
  }
  builder.flush();

  const pages = builder.pages;
  const total = pages.length;
  const out: ReaderPage[] = [];
  for (let i = 0; i < total; i++) {
    out.push(new ReaderPage(ReaderPageKind.Content, entry, i, total,
      renderGroupsOf(pages[i], width, measurer, makeId)));
  }
  return out;
}

/**
 * 一页的块 → 渲染组（iOS ContentBlockRenderer.renderGroups 同款两指针扫描）。
 * 分页已把照片连同锚文本放进同一页，这里组成 photoWithText 并按环绕容量把文字
 * 切成 beside / below —— beside 被容量截住（约排满照片高度），渲染不会超出
 * 分页时按全宽测出的预算（R-READ-05）。
 */
export function renderGroupsOf(blocks: ContentBlock[], width: number,
  measurer: ReaderTextMeasurer, makeId: () => string): ReaderRenderGroup[] {
  // 照片旁能容纳的字数（iOS estimatedCapacity 同款）：照片高度可塞行数 × 每行字数。
  // 极端窄宽退回 120 字下限。
  const lineH = measurer.lineHeightOf(ReaderLayout.wrappedTextFontSize, ReaderLayout.wrappedLineSpacing);
  const lines = Math.max(1, Math.floor(ReaderLayout.photoBlockHeight / lineH));
  const textW = Math.max(1, width * (1 - ReaderLayout.photoWidthRatio) - ReaderLayout.photoTextGap);
  const charW = Math.max(1, measurer.charWidthOf(ReaderLayout.wrappedTextFontSize));
  const charsPerLine = Math.max(1, Math.floor(textW / charW));
  const estimatedCapacity = Math.max(lines * charsPerLine, 120);

  const groups: ReaderRenderGroup[] = [];
  let i = 0;
  while (i < blocks.length) {
    const block = blocks[i];

    // 录音、痕迹：正文里单独一行
    if (block.type === ContentBlockType.Audio) {
      groups.push(ReaderRenderGroup.audio(block));
      i++;
      continue;
    }
    if (block.type === ContentBlockType.Trace) {
      groups.push(ReaderRenderGroup.trace(block));
      i++;
      continue;
    }
    // 没有前置文本锚点的照片（相邻照片 / 开头照片）→ 独立渲染，绝不丢弃
    if (block.type === ContentBlockType.Photo) {
      groups.push(ReaderRenderGroup.standalonePhoto(block));
      i++;
      continue;
    }

    // 当前是文本块：检查下一个是不是照片
    if (i + 1 < blocks.length && blocks[i + 1].type === ContentBlockType.Photo) {
      const photoBlock = blocks[i + 1];
      // 汇总可用于环绕的文本（当前块起，向后累加文本块直到字数够或遇到照片/录音）
      const mergedParts: ContentBlock[] = [block];
      let mergedLength = (block.text ?? '').length;
      // lastConsumed 指向最后一个被并入的块（无并入时 = 照片块下标）
      let lastConsumed = i + 1;
      let j = i + 2;
      while (mergedLength < estimatedCapacity && j < blocks.length) {
        const nxt = blocks[j];
        if (nxt.type !== ContentBlockType.Text) {
          break; // 遇到下一张照片 / 录音，停止合并
        }
        // 该文本块紧跟着照片 → 它是下一张照片的锚点，不能被吞并（否则照片变孤儿）
        if (j + 1 < blocks.length && blocks[j + 1].type === ContentBlockType.Photo) {
          break;
        }
        mergedLength += 1 + (nxt.text ?? '').length; // "\n" 连接
        mergedParts.push(nxt);
        lastConsumed = j;
        j++;
      }
      // 切分 beside / below：合并文本按容量截断，剩余放照片下方
      const merged = mergeTextBlocks(mergedParts, makeId);
      const cap = Math.min(estimatedCapacity, (merged.text ?? '').length);
      const parts = splitBlockAtCharCount(merged, cap, makeId);
      groups.push(ReaderRenderGroup.photoWithText(parts[0], photoBlock, parts[1]));
      i = lastConsumed + 1;
    } else {
      // 普通全宽文本块
      groups.push(ReaderRenderGroup.fullText(block));
      i++;
    }
  }
  return groups;
}

/** 阅读器整本页面：日记展平 + 末尾结尾页（iOS PageDataSource.rebuild 同款） */
export function buildReaderPages(entries: JournalEntry[], geometry: ReaderGeometry,
  measurer: ReaderTextMeasurer, makeId: () => string): ReaderPage[] {
  const ordered = readingOrderSort(entries); // R-READ-01：从早到晚
  const pages: ReaderPage[] = [];
  for (const entry of ordered) {
    const entryPages = paginateEntry(entry, geometry, measurer, makeId);
    for (const page of entryPages) {
      pages.push(page);
    }
  }
  // 整本最后一篇（最新的那篇）末尾追加 ending 页
  if (ordered.length > 0) {
    const last = ordered[ordered.length - 1];
    pages.push(new ReaderPage(ReaderPageKind.Ending, last, 0, 1, []));
  }
  return pages;
}

/** 跳到某篇首页的下标（找不到回 0；iOS rebuild 的跳转同款） */
export function indexOfEntryFirstPage(pages: ReaderPage[], entryId: string): number {
  for (let i = 0; i < pages.length; i++) {
    const page = pages[i];
    if (page.kind === ReaderPageKind.Content && page.pageIndex === 0
      && page.entry.id === entryId) {
      return i;
    }
  }
  return 0;
}

/** 重排锚点：当前页属于哪篇、篇内第几页（结尾页单独记 kind） */
export class ReaderPageAnchor {
  readonly entryId: string;
  readonly pageIndex: number;
  readonly kind: ReaderPageKind;

  constructor(entryId: string, pageIndex: number, kind: ReaderPageKind) {
    this.entryId = entryId;
    this.pageIndex = pageIndex;
    this.kind = kind;
  }
}

/** 取当前页的锚点（翻页中途 / 空页返回 undefined） */
export function pageAnchorOf(pages: ReaderPage[], index: number): ReaderPageAnchor | undefined {
  if (index < 0 || index >= pages.length) {
    return undefined;
  }
  const page = pages[index];
  return new ReaderPageAnchor(page.entry.id,
    page.kind === ReaderPageKind.Ending ? 0 : page.pageIndex, page.kind);
}

/** 重排后找回原来的阅读位置：精确匹配（篇 + 页号 / 结尾页）；
 *  重排后页数变少就退到该篇最后一页；篇没了回第 0 页（R-READ-05 同一套页模型） */
export function indexOfPageAnchor(pages: ReaderPage[], anchor: ReaderPageAnchor): number {
  let fallback = -1;
  for (let i = 0; i < pages.length; i++) {
    const page = pages[i];
    if (page.entry.id !== anchor.entryId || page.kind !== anchor.kind) {
      continue;
    }
    if (anchor.kind === ReaderPageKind.Ending) {
      return i;
    }
    if (page.pageIndex === anchor.pageIndex) {
      return i;
    }
    if (fallback < 0 || page.pageIndex > pages[fallback].pageIndex) {
      fallback = i;
    }
  }
  return fallback >= 0 ? fallback : 0;
}
