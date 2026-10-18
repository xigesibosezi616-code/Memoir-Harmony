/**
 * 绕排引擎数据模型（10_BUILD_MANUAL.md 2.7，R-RICH-02）。
 *
 * 纯数据 / 纯接口，不依赖 ArkUI 与 graphics.text —— 引擎几何逻辑全部在这层之上，
 * 单测用 mock 测量器即可覆盖锚定语义 / 条带切分 / 跨块续排 / 多照片串联。
 *
 * 排版机制：graphics.text `ParagraphStyle.headIndents / tailIndents`（API 26，
 * 逐行首 / 尾缩进数组）——照片左侧 → 该段受影响行 headIndent = 照片右边 + 间距；
 * 右侧 → tailIndent = 容器右边 - 照片左边 + 间距。数组末位必须归 0
 * （实际行数超出数组长度时，超出行取数组末位值）。
 */
import { PaperStyle } from '../../../models/ContentBlock';
import { PhotoPosition, TextStyleRun } from '../../../models/ContentBlock';

/** 无图时的退化比例（4:3，与 PhotoPapers.FALLBACK_PHOTO_ASPECT 一致） */
export const FALLBACK_PHOTO_ASPECT: number = 4.0 / 3.0;

/** 照片与文字的间距（vp，iOS photoGap 同款） */
export const WRAP_FLOW_PHOTO_GAP: number = 12;

/** 照片顶边相对锚定段首行的下沉量（vp，iOS +4 同款） */
export const WRAP_FLOW_PHOTO_TOP_INSET: number = 4;

/**
 * 相纸卡片外框尺寸（vp）：只由「外框宽 × 照片比例 × 相纸样式」决定。
 * 公式与 `PhotoPapers.ets` 六种组件的布局逐项对应（格子 aspectRatio 定高、
 * chrome 加 padding / 留白）；引擎用它预算占位矩形，渲染组件按同宽度摆放即可严丝合缝。
 */
export function photoCardMetrics(cardWidth: number, photoAspect: number, style: PaperStyle): CardSize {
  const aspect = photoAspect > 0 ? photoAspect : FALLBACK_PHOTO_ASPECT;
  const w = cardWidth;
  let h: number;
  switch (style) {
    case PaperStyle.Original:
      // 原图：整卡即照片格
      h = w / aspect;
      break;
    case PaperStyle.Polaroid:
      // 宝丽来：四周 8 白边 + 底部 28 白边，格子宽 = w-16
      h = (w - 16) / aspect + 16 + 28;
      break;
    case PaperStyle.WashiSticker:
      // 和风贴纸：四周 6 边距，格子宽 = w-12
      h = (w - 12) / aspect + 12;
      break;
    case PaperStyle.MinimalCard:
      // 极简卡片：整卡即照片格（细边框不占尺寸）
      h = w / aspect;
      break;
    case PaperStyle.FilmFrame:
      // 胶片帧：四周 6 边距 + 两条 14 齿孔条 + 两个 4 间距，格子宽 = w-48
      h = (w - 12 - 2 * (14 + 4)) / aspect + 12;
      break;
    default:
      // 信纸附照：四周 4 白边，格子宽 = w-8
      h = (w - 8) / aspect + 8;
      break;
  }
  return new CardSize(w, h);
}

/** 相纸卡片外框尺寸 */
export class CardSize {
  width: number;
  height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }
}

/**
 * 文本块按 \n 拆出的**行段落**（05 §3.3：heading 是「整段格式」，段 = \n 分隔的行；
 * TextKit 语义同款——块内 \n 分行、每行独立字号 / 行高 / 格式）。
 * 一个块可拆出多段（heading 段 + 正文段混排），照片锚定语义不变（锚块后首段）。
 */
export class TextPart {
  /** 行段落文本（不含 \n；可为空 = 空行） */
  text: string;
  /** 本段在块文本内的起点（UTF-16） */
  localStart: number;
  /** 是否小标题段（本段范围内任一 run 标 heading） */
  isHeading: boolean;
  /** 格式区间（已切片平移，相对本段 text） */
  runs: TextStyleRun[];

  constructor(text: string, localStart: number, isHeading: boolean, runs: TextStyleRun[]) {
    this.text = text;
    this.localStart = localStart;
    this.isHeading = isHeading;
    this.runs = runs;
  }
}

/**
 * 文本块 → 行段落数组（\n 拆分；runs 按段切片平移、字段全量拷贝；
 * 逐段 isHeading = 该段范围内任一 run 标 heading）。
 * 编辑器侧另用 localStart 与块区间起点求和得到模型偏移（光标 / 命中映射）。
 */
export function textPartsOfBlock(text: string, runs: TextStyleRun[]): TextPart[] {
  const parts: TextPart[] = [];
  let start = 0;
  for (let i = 0; i <= text.length; i++) {
    if (i < text.length && text.charCodeAt(i) !== 10) {
      continue;
    }
    const partRuns: TextStyleRun[] = [];
    let isHeading = false;
    for (const run of runs) {
      const rs = Math.max(run.location, start);
      const re = Math.min(run.location + run.length, i);
      if (run.heading === true && run.location < i && run.location + run.length > start) {
        isHeading = true;
      }
      if (re > rs) {
        const sliced = new TextStyleRun(rs - start, re - rs);
        if (run.bold === true) {
          sliced.bold = true;
        }
        if (run.italic === true) {
          sliced.italic = true;
        }
        if (run.heading === true) {
          sliced.heading = true;
        }
        if (run.highlight === true) {
          sliced.highlight = true;
        }
        if (run.writtenAt !== undefined) {
          sliced.writtenAt = run.writtenAt;
        }
        if (run.struckAt !== undefined) {
          sliced.struckAt = run.struckAt;
        }
        partRuns.push(sliced);
      }
    }
    parts.push(new TextPart(text.substring(start, i), start, isHeading, partRuns));
    start = i + 1;
  }
  return parts;
}

/** 引擎输入项的基类（文本段 / 照片锚点二选一，instanceof 区分） */
export class WrapFlowItem {
}

/** 文本段输入：一段正文或一段小标题（小标题整段，R-RICH-07） */
export class WrapFlowTextItem extends WrapFlowItem {
  /** 段落原文（不含锚点字符；锚点由前面的照片项表达） */
  text: string;
  /** 是否小标题段（决定行高；任一 run 标 heading 即整段） */
  isHeading: boolean;
  /** 字符格式区间（UTF-16，相对本段 text；引擎只算几何，渲染层消费） */
  runs: TextStyleRun[];

  constructor(text: string, isHeading: boolean, runs: TextStyleRun[] = []) {
    super();
    this.text = text;
    this.isHeading = isHeading;
    this.runs = runs;
  }
}

/** 照片锚点输入：浮在其后第一个文本段开头（iOS 锚定语义） */
export class WrapFlowPhotoItem extends WrapFlowItem {
  /** 照片块 id（结果里凭它对回块本体） */
  blockId: string;
  /** 左 / 右侧（创建时定死，R-PHOTO-06） */
  lane: PhotoPosition;
  /** 相纸卡片外框（宽已含 46% 比例换算，高由 photoCardMetrics 算好传入） */
  card: CardSize;

  constructor(blockId: string, lane: PhotoPosition, card: CardSize) {
    super();
    this.blockId = blockId;
    this.lane = lane;
    this.card = card;
  }
}

/** 一次文本测量的结果（引擎只关心行数；高 = 行数 × 行高由引擎推导） */
export class TextMeasureResult {
  lineCount: number;

  constructor(lineCount: number) {
    this.lineCount = lineCount;
  }
}

/**
 * 文本测量适配器：引擎与真实排版解耦的唯一边界。
 * 真实实现包 `@ohos.graphics.text`（ParagraphBuilder + headIndents/tailIndents +
 * layoutSync → 行数）；单测用等宽字符 mock。
 * 约定：可用宽度 = width - headIndents[行] - tailIndents[行]，行号超出数组取末位。
 */
export interface TextLayoutAdapter {
  /** 测一段文字在给定宽度与逐行缩进下的行数 */
  measure(text: string, isHeading: boolean, width: number,
    headIndents: number[], tailIndents: number[]): TextMeasureResult;
  /**
   * 实测该样式的行距（vp，单行段落高）。
   * 引擎的行带几何（y 推进 / 照片遮挡行带 / 照片锚定）必须以实绘行距为准——
   * strutStyle.forceHeight 与 TextStyle.heightScale 平台实测可能不生效，
   * 若仍按参数行高推几何，照片锚定与遮挡带会和实绘错位（漂移 + 遮字）。
   * 返回 ≤0 表示测量不可用，引擎回退参数行高。
   */
  measurePitch(isHeading: boolean): number;
}

/** 引擎输出的照片占位矩形（容器坐标系，vp） */
export class WrappedPhotoRect {
  blockId: string;
  lane: PhotoPosition;
  /** 左上角 x（左照片 = 0，右照片 = 容器宽 - 卡宽） */
  x: number;
  /** 左上角 y（锚定段首行 + TOP_INSET，或同车道上一张底边 + GAP，取大者） */
  y: number;
  width: number;
  height: number;

  constructor(blockId: string, lane: PhotoPosition, x: number, y: number, width: number, height: number) {
    this.blockId = blockId;
    this.lane = lane;
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }

  /** 底边 */
  bottom(): number {
    return this.y + this.height;
  }

  /** 右边 */
  right(): number {
    return this.x + this.width;
  }
}

/** 引擎输出的段落排版区（容器坐标系，vp） */
export class WrappedParagraphRect {
  /** 对应输入 items 的下标（渲染层凭它取回文字 / 样式） */
  itemIndex: number;
  /** 段落顶边 y */
  y: number;
  /** 行高（正文 / 小标题各一套） */
  lineHeight: number;
  /** 行数 */
  lineCount: number;
  /** 段落高 = lineCount × lineHeight */
  height: number;
  /** 逐行首缩进（末位已归 0，直接喂 ParagraphStyle.headIndents） */
  headIndents: number[];
  /** 逐行尾缩进（末位已归 0，直接喂 ParagraphStyle.tailIndents） */
  tailIndents: number[];

  constructor(itemIndex: number, y: number, lineHeight: number, lineCount: number,
    headIndents: number[], tailIndents: number[]) {
    this.itemIndex = itemIndex;
    this.y = y;
    this.lineHeight = lineHeight;
    this.lineCount = lineCount;
    this.height = lineCount * lineHeight;
    this.headIndents = headIndents;
    this.tailIndents = tailIndents;
  }
}

/** 一次绕排布局的完整结果 */
export class WrapFlowResult {
  /** 全部段落排版区（按文档序） */
  paragraphs: WrappedParagraphRect[];
  /** 全部照片占位矩形（按文档序） */
  photos: WrappedPhotoRect[];
  /** 内容总高（文字流末尾与最深照片底边的较大者） */
  totalHeight: number;

  constructor(paragraphs: WrappedParagraphRect[], photos: WrappedPhotoRect[], totalHeight: number) {
    this.paragraphs = paragraphs;
    this.photos = photos;
    this.totalHeight = totalHeight;
  }
}
