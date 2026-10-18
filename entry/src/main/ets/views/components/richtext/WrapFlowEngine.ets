/**
 * 绕排引擎（10_BUILD_MANUAL.md 2.7，R-RICH-02）——纯几何，无 SDK 依赖。
 *
 * 对应 iOS `RichTextView.swift` L180-291（layoutPhotos / computeFrames / exclusionPaths），
 * 机制换成鸿蒙官方逐行缩进：照片矩形先算（宽 46% × 比例 → 高，无循环依赖），
 * 文字段顺序排版，受照片遮挡的行收 headIndent / tailIndent，
 * 照片比锚定段高时后续段落自动续排（活跃照片表），同车道多照片全局串联防重叠。
 *
 * 与 iOS 的差异（有意为之）：
 * - iOS 靠 exclusionPaths 迭代 4 次收敛；这里照片几何与文字行高都先验已知，
 *   一次顺序扫描即收敛 —— 无迭代、确定性、可单测。
 * - 行高统一（正文 / 小标题各一套），段落高 = 行数 × 行高。
 */
import { PhotoPosition } from '../../../models/ContentBlock';
import {
  TextLayoutAdapter,
  WrapFlowItem,
  WrapFlowPhotoItem,
  WrapFlowResult,
  WrapFlowTextItem,
  WrappedParagraphRect,
  WrappedPhotoRect,
  WRAP_FLOW_PHOTO_GAP,
  WRAP_FLOW_PHOTO_TOP_INSET
} from './WrapFlowModel';

/** 行高为零 / 宽度非法时兜底，避免除零与死循环 */
const MIN_LINE_HEIGHT: number = 1;
const MIN_WIDTH: number = 1;
/** 浮点容差（vp）：照片底边恰好在行边界上时不算遮挡该行 */
const EPS: number = 0.01;

/**
 * 一次绕排布局的参数。
 * bodyLineHeight / headingLineHeight 来自 RichTextAppearance；photoGap / photoTopInset
 * 暴露成参数便于单测微调（生产传 WrapFlowModel 里的常量）。
 */
export class WrapFlowParams {
  /** 正文行高（vp） */
  bodyLineHeight: number;
  /** 小标题行高（vp） */
  headingLineHeight: number;
  /** 照片与文字间距（vp） */
  photoGap: number;
  /** 照片顶边相对锚定段首行的下沉（vp） */
  photoTopInset: number;

  constructor(bodyLineHeight: number, headingLineHeight: number,
    photoGap: number = WRAP_FLOW_PHOTO_GAP, photoTopInset: number = WRAP_FLOW_PHOTO_TOP_INSET) {
    this.bodyLineHeight = Math.max(bodyLineHeight, MIN_LINE_HEIGHT);
    this.headingLineHeight = Math.max(headingLineHeight, MIN_LINE_HEIGHT);
    this.photoGap = Math.max(photoGap, 0);
    this.photoTopInset = Math.max(photoTopInset, 0);
  }
}

/** 绕排引擎：无状态，layout() 可重复调用（宽度变化 / 换边重排） */
export class WrapFlowEngine {
  private readonly params: WrapFlowParams;
  private readonly adapter: TextLayoutAdapter;

  constructor(params: WrapFlowParams, adapter: TextLayoutAdapter) {
    this.params = params;
    this.adapter = adapter;
  }

  /**
   * 顺序扫描布局：
   * 1. 照片项 → 占位矩形（左 x=0 / 右 x=W-卡宽；y = 锚定流位置+下沉 与
   *    同车道上一张底边+间距 取大），挂进活跃照片表；
   * 2. 文本项 → 按活跃照片算逐行缩进（照片覆盖到的行才缩，数组末位归 0），
   *    交测量器数行数，段落高 = 行数 × 行高，推进流游标；
   * 3. 照片底边越过游标即出活跃表（之后的段落不再缩）。
   */
  layout(items: WrapFlowItem[], containerWidth: number): WrapFlowResult {
    const width = Math.max(containerWidth, MIN_WIDTH);
    const paragraphs: WrappedParagraphRect[] = [];
    const photos: WrappedPhotoRect[] = [];
    const active: WrappedPhotoRect[] = [];
    let leftLaneBottom = -Number.MAX_VALUE;
    let rightLaneBottom = -Number.MAX_VALUE;
    let y = 0;

    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (item instanceof WrapFlowPhotoItem) {
        const card = item.card;
        const anchorY = y;
        const laneBottom = item.lane === PhotoPosition.Left ? leftLaneBottom : rightLaneBottom;
        const photoY = Math.max(anchorY + this.params.photoTopInset, laneBottom + this.params.photoGap);
        const photoX = item.lane === PhotoPosition.Left ? 0 : width - card.width;
        const rect = new WrappedPhotoRect(item.blockId, item.lane, photoX, photoY, card.width, card.height);
        photos.push(rect);
        active.push(rect);
        if (item.lane === PhotoPosition.Left) {
          leftLaneBottom = rect.bottom();
        } else {
          rightLaneBottom = rect.bottom();
        }
        continue;
      }
      const textItem = item as WrapFlowTextItem;
      // 行距以实绘实测为准（strut/heightScale 平台可能不生效）；测不到回退参数行高
      const fallbackLH = textItem.isHeading ? this.params.headingLineHeight : this.params.bodyLineHeight;
      const lineHeight = this.linePitchOf(textItem.isHeading, fallbackLH);
      const indents = this.lineIndents(active, y, lineHeight, width);
      const measure = this.adapter.measure(textItem.text, textItem.isHeading, width,
        indents.head, indents.tail);
      const lineCount = Math.max(measure.lineCount, 1);
      paragraphs.push(new WrappedParagraphRect(i, y, lineHeight, lineCount,
        indents.head, indents.tail));
      y += lineCount * lineHeight;
      // 底边不高于新游标的照片不再影响后续段落
      let a = 0;
      while (a < active.length) {
        if (active[a].bottom() <= y + EPS) {
          active.splice(a, 1);
        } else {
          a++;
        }
      }
    }

    let total = y;
    for (let p = 0; p < photos.length; p++) {
      if (photos[p].bottom() > total) {
        total = photos[p].bottom();
      }
    }
    return new WrapFlowResult(paragraphs, photos, total);
  }

  /**
   * 段落实际行距：优先测量器实测。引擎行带几何若按参数行高而实绘行距不同
   * （strutStyle.forceHeight / TextStyle.heightScale 平台实测不生效时的 16.3vp≠20vp），
   * 照片锚定随游标漂移、遮挡行带与实绘行错位——照片被「推走」且底缘遮字。
   * 测量器给不出（≤0）回退参数行高。
   */
  private linePitchOf(isHeading: boolean, fallback: number): number {
    const measured = this.adapter.measurePitch(isHeading);
    return measured > 0 ? measured : fallback;
  }

  /**
   * 一段文字的逐行缩进：遍历活跃照片，把照片覆盖到的行标上
   * 「照片右边 + 间距」（左）或「容器宽 - 照片左边 + 间距」（右），
   * 同行多照片取最大；末位补 0（实际行数超出数组时超出行取末位值）。
   */
  private lineIndents(active: WrappedPhotoRect[], paragraphY: number, lineHeight: number,
    width: number): LineIndents {
    // 第一遍：算受影响的最大行号，避免稀疏数组空洞
    let maxLine = -1;
    for (let p = 0; p < active.length; p++) {
      const photo = active[p];
      if (photo.bottom() <= paragraphY + EPS) {
        continue;
      }
      // 行带 [L*lh,(L+1)*lh) 与照片 [y,bottom) 有重叠即遮挡：
      // 首遮挡行 = floor((顶边+容差)/行高)（顶边贴行界不计），负数（照片从上一段
      // 就开始）夹到 0；末遮挡行 = ceil((底边-容差)/行高)-1（底边贴行界不计）
      const firstLine = Math.max(0, Math.floor((photo.y - paragraphY + EPS) / lineHeight));
      const lastLine = Math.ceil((photo.bottom() - paragraphY - EPS) / lineHeight) - 1;
      if (lastLine < firstLine) {
        continue;
      }
      if (lastLine + 1 > maxLine) {
        maxLine = lastLine + 1;
      }
    }
    const headOut: number[] = [];
    const tailOut: number[] = [];
    // maxLine = 末遮挡行+1：行 0..lastLine 共 maxLine 个条目
    for (let line = 0; line < maxLine; line++) {
      headOut.push(0);
      tailOut.push(0);
    }
    // 第二遍：按照片逐行取最大缩进
    for (let p = 0; p < active.length; p++) {
      const photo = active[p];
      if (photo.bottom() <= paragraphY + EPS) {
        continue;
      }
      const firstLine = Math.max(0, Math.floor((photo.y - paragraphY + EPS) / lineHeight));
      const lastLine = Math.ceil((photo.bottom() - paragraphY - EPS) / lineHeight) - 1;
      if (lastLine < firstLine) {
        continue;
      }
      const indent = photo.lane === PhotoPosition.Left
        ? photo.right() + this.params.photoGap
        : width - photo.x + this.params.photoGap;
      for (let line = firstLine; line <= lastLine; line++) {
        if (photo.lane === PhotoPosition.Left) {
          if (indent > headOut[line]) {
            headOut[line] = indent;
          }
        } else {
          if (indent > tailOut[line]) {
            tailOut[line] = indent;
          }
        }
      }
    }
    // 末位归 0：实际行数超出数组长度时，超出行取数组末位值
    headOut.push(0);
    tailOut.push(0);
    return new LineIndents(headOut, tailOut);
  }
}

/** lineIndents 的打包返回（ArkTS 不支持解构与元组） */
class LineIndents {
  head: number[];
  tail: number[];

  constructor(head: number[], tail: number[]) {
    this.head = head;
    this.tail = tail;
  }
}
