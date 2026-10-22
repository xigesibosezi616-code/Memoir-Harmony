/**
 * 封面编辑的纯逻辑（10_BUILD_MANUAL.md 3.4）。对应 iOS
 * `Models/CoverLayout.swift` 的会员判断、`Models/MembershipRules.swift` 的
 * `CoverEdit.needsMembership`、`Shelf/NotebookCoverStore.swift` 的常量、
 * `Shelf/CoverCropView.swift` 的取景几何。
 *
 * 全部是无副作用函数 / 常量，可单测；解码与烤盘在 `NotebookCoverStore.ets`，
 * 界面在 `CoverEditorView.ets` / `CoverCropOverlay.ets`。
 */
import { CoverLayout } from './Notebook';

/** 封面宽高比（宽 / 高，iOS `NotebookCoverStore.aspect`，与 BookCoverView 一致） */
export const COVER_ASPECT: number = 0.73;

/** 烤盘宽度（px）：封面文件最宽 1200（iOS `pixelWidth`） */
export const COVER_PIXEL_WIDTH: number = 1200;

/** 相册原始字节解码上限（长边 px）。4800 万像素全解近 200MB，2400 绰绰有余（iOS 同值） */
export const COVER_SOURCE_MAX_EDGE: number = 2400;

/** 副标题上限：主页大图上一行放得下（iOS `CoverEdit.subtitleMaxLength`） */
export const SUBTITLE_MAX_LENGTH: number = 24;

/** 构图最大缩放（iOS `maxZoom`） */
export const CROP_MAX_ZOOM: number = 4;

/** 构图取景框的横向留白（左右各 24，iOS windowSize 的 -48） */
export const CROP_WINDOW_H_MARGIN: number = 48;

/** 构图取景框的竖向预留（顶部工具栏 + 底部提示文字，iOS windowSize 的 -120） */
export const CROP_WINDOW_V_RESERVED: number = 120;

/**
 * 编辑过程中照片这一项的改动（iOS `CoverPhotoDraft`，关联值换成会话文件名）。
 * 「落盘时机」与 iOS 有偏差（用户拍板，见 PROGRESS 3.4）：iOS 点「应用」才写盘，
 * 鸿蒙构图完成即落盘成正式文件，`Replaced` 直接持有文件名；取消编辑删掉会话文件。
 */
export enum CoverPhotoDraftKind {
  /** 沿用原来的（原来可能就没有） */
  Unchanged = 'Unchanged',
  /** 换了新的（已落盘成会话文件） */
  Replaced = 'Replaced',
  /** 去掉照片，改用纯色亚麻封面 */
  Removed = 'Removed'
}

/** 原图上的矩形（像素坐标；构图完成时由取景框换算回来） */
export class CoverCropRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;

  constructor(x: number, y: number, width: number, height: number) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

/** 烤盘输出尺寸（px） */
export class CoverRenderSize {
  readonly width: number;
  readonly height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }
}

// ---- 副标题 ----

/** 存库前的副标题：只去首尾空白（空 = 没有副标题） */
export function cleanSubtitle(raw: string): string {
  return raw.trim();
}

/**
 * 副标题按 Unicode 码点截到上限（iOS `String.prefix` 按字素簇不拆字符；
 * 码点截断不拆代理对，emoji face 等 ZWJ 序列可能被截开 —— 输入框按码点计数
 * 提示，与 `String.length` 的 UTF-16 口径记为偏差，见 PROGRESS 3.4）
 */
export function truncateSubtitle(raw: string): string {
  let result = '';
  let count = 0;
  let i = 0;
  while (i < raw.length && count < SUBTITLE_MAX_LENGTH) {
    const codePoint = raw.codePointAt(i);
    if (codePoint === undefined) {
      break;
    }
    result += String.fromCodePoint(codePoint);
    i += codePoint > 0xFFFF ? 2 : 1;
    count++;
  }
  return result;
}

// ---- 版式的可见性与会员 ----

/** 颜色栏标题选哪个：没照片叫「或者选一种颜色」，贴照片叫「布面颜色」（R-BOOK-13） */
export function colorSectionTitleKey(hasPhoto: boolean): string {
  return hasPhoto ? 's_9f0103656b' : 's_e7ec4d5c09';
}

/** 免费的只有满版；白框、贴照片要会员（iOS `CoverLayout.isMemberOnly`） */
export function isMemberOnlyCoverLayout(layout: CoverLayout): boolean {
  return layout !== CoverLayout.FullBleed;
}

/**
 * 这次保存要不要会员（R-MEMBER-06，iOS `CoverEdit.needsMembership`）：
 * **新选了**会员版式，而且保存后封面上有照片（没照片时版式不起作用）。
 * 原来已经用着的会员版式不算 —— 到期后改个副标题、换个颜色，不该被拦。
 * - `originalLayout`：这本原来的版式；新建日记本传 undefined
 * - `hasExistingPhoto`：这本原来有没有照片封面
 */
export function needsMembershipCoverLayout(layout: CoverLayout,
  originalLayout: CoverLayout | undefined, photo: CoverPhotoDraftKind,
  hasExistingPhoto: boolean): boolean {
  if (!isMemberOnlyCoverLayout(layout)) {
    return false;
  }
  if (originalLayout !== undefined && layout === originalLayout) {
    return false;
  }
  switch (photo) {
    case CoverPhotoDraftKind.Replaced:
      return true;
    case CoverPhotoDraftKind.Removed:
      return false;
    default:
      return hasExistingPhoto;
  }
}

// ---- 构图几何（iOS `CoverCropView` 的私有几何，pt → vp 1:1） ----

/**
 * 取景框宽（vp）：封面比例，左右各留 24，上下给提示文字留位置。
 * 高 = 宽 / COVER_ASPECT 由 CoverCropOverlay 按 aspectRatio 推，这里只出宽。
 */
export function cropWindowWidth(containerWidth: number, containerHeight: number): number {
  const width = Math.max(1,
    Math.min(containerWidth - CROP_WINDOW_H_MARGIN,
      (containerHeight - CROP_WINDOW_V_RESERVED) * COVER_ASPECT));
  return width;
}

/** 「刚好铺满取景框」的缩放（图 px → 屏幕 vp；取 max 才不留白，iOS baseScale） */
export function baseFillScale(imageWidth: number, imageHeight: number,
  windowWidth: number, windowHeight: number): number {
  if (imageWidth <= 0 || imageHeight <= 0) {
    return 1;
  }
  return Math.max(windowWidth / imageWidth, windowHeight / imageHeight);
}

/** 缩放夹取：不小于「刚好铺满」（1）、不大于 4 倍 */
export function clampCropZoom(zoom: number): number {
  return Math.min(Math.max(zoom, 1), CROP_MAX_ZOOM);
}

/** 水平拖动范围：图的左右边不能拖进取景框（不露空白），iOS clampOffset 的 x 分量 */
export function clampCropOffsetX(value: number, zoom: number, base: number,
  imageWidth: number, windowWidth: number): number {
  const maxX = Math.max(0, (imageWidth * base * zoom - windowWidth) / 2);
  return Math.min(Math.max(value, -maxX), maxX);
}

/** 竖直拖动范围（同上，y 分量） */
export function clampCropOffsetY(value: number, zoom: number, base: number,
  imageHeight: number, windowHeight: number): number {
  const maxY = Math.max(0, (imageHeight * base * zoom - windowHeight) / 2);
  return Math.min(Math.max(value, -maxY), maxY);
}

/**
 * 取景框换算回原图上的区域（像素坐标，iOS `finish` 的换算）：
 * `k = base × zoom`（图 px → 屏幕 vp），窗口中心 = 图中心 − 偏移 / k。
 * 返回的矩形比例即 COVER_ASPECT，烤盘时直接 `PixelMap.crop`。
 */
export function cropRectFromView(imageWidth: number, imageHeight: number,
  windowWidth: number, windowHeight: number, zoom: number,
  offsetX: number, offsetY: number): CoverCropRect {
  const base = baseFillScale(imageWidth, imageHeight, windowWidth, windowHeight);
  const k = base * zoom;
  const width = windowWidth / k;
  const height = windowHeight / k;
  const centerX = imageWidth / 2 - offsetX / k;
  const centerY = imageHeight / 2 - offsetY / k;
  return new CoverCropRect(centerX - width / 2, centerY - height / 2, width, height);
}

/**
 * 烤盘输出尺寸（iOS `render` 的 outSize）：宽 = min(1200, 裁块宽)（原图更小不放大），
 * 高按封面比例推（与裁块实际高度的差 ≤ 取整误差，画布比例恒定不变形）。
 */
export function coverRenderSize(cropWidth: number): CoverRenderSize {
  const width = Math.max(1, Math.min(COVER_PIXEL_WIDTH, Math.round(cropWidth)));
  const height = Math.max(1, Math.round(width / COVER_ASPECT));
  return new CoverRenderSize(width, height);
}
