/**
 * 封面编辑纯逻辑单测（10_BUILD_MANUAL.md 3.4）。
 * 覆盖：副标题清洗 / 码点截断、会员版式判断全矩阵（R-MEMBER-06）、
 * 构图取景几何（窗口宽、铺满缩放、缩放 / 偏移夹取、取景框 → 原图区域）、
 * 烤盘尺寸（不放大）。对应 iOS `CoverCropView` / `MembershipRules.swift`。
 */
import { describe, it, expect } from '@ohos/hypium';
import { CoverLayout } from '../../main/ets/models/Notebook';
import {
  CROP_MAX_ZOOM,
  CoverPhotoDraftKind,
  cleanSubtitle,
  clampCropOffsetX,
  clampCropOffsetY,
  clampCropZoom,
  colorSectionTitleKey,
  coverRenderSize,
  cropRectFromView,
  cropWindowWidth,
  baseFillScale,
  isMemberOnlyCoverLayout,
  needsMembershipCoverLayout,
  truncateSubtitle,
  SUBTITLE_MAX_LENGTH
} from '../../main/ets/models/CoverEdit';

export default function coverEditTest() {
  describe('CoverEditTest', () => {
    // ---- 副标题 ----

    it('cleanSubtitleTrimsWhitespace', 0, () => {
      expect(cleanSubtitle('  2025 · 京都\n')).assertEqual('2025 · 京都');
      expect(cleanSubtitle('   ')).assertEqual('');
    })

    it('truncateSubtitleKeepsShortText', 0, () => {
      expect(truncateSubtitle('2025 · 京都')).assertEqual('2025 · 京都');
    })

    it('truncateSubtitleCutsAtLimitByCodePoint', 0, () => {
      const input = '一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十';
      expect(truncateSubtitle(input).length).assertEqual(SUBTITLE_MAX_LENGTH);
      expect(truncateSubtitle(input)).assertEqual(input.substring(0, 24));
    })

    it('truncateSubtitleDoesNotSplitSurrogatePairs', 0, () => {
      // 23 个汉字 + 一个 emoji（代理对占 2 个 UTF-16 单元）：emoji 完整保留，不拆半个
      const prefix = '一二三四五六七八九十一二三四五六七八九十一二三';
      const input = `${prefix}🍁`;
      const result = truncateSubtitle(input);
      expect(result).assertEqual(input);
      expect(result.length).assertEqual(25); // 23 汉字 + 2 单元 emoji
    })

    it('truncateSubtitleCutsAfterFullEmoji', 0, () => {
      // 24 个汉字 + emoji：正好 24 码点，emoji 截掉
      const prefix = '一二三四五六七八九十一二三四五六七八九十一二三四';
      expect(truncateSubtitle(`${prefix}🍁`)).assertEqual(prefix);
    })

    // ---- 版式与会员（R-MEMBER-06） ----

    it('colorSectionTitleKeyByPhotoState', 0, () => {
      expect(colorSectionTitleKey(false)).assertEqual('s_e7ec4d5c09');
      expect(colorSectionTitleKey(true)).assertEqual('s_9f0103656b');
    })

    it('onlyFullBleedIsFree', 0, () => {
      expect(isMemberOnlyCoverLayout(CoverLayout.FullBleed)).assertFalse();
      expect(isMemberOnlyCoverLayout(CoverLayout.Framed)).assertTrue();
      expect(isMemberOnlyCoverLayout(CoverLayout.TipIn)).assertTrue();
    })

    it('needsMembershipFalseForFreeLayout', 0, () => {
      expect(needsMembershipCoverLayout(CoverLayout.FullBleed, undefined,
        CoverPhotoDraftKind.Replaced, false)).assertFalse();
    })

    it('needsMembershipFalseWhenLayoutUnchanged', 0, () => {
      // 原来就用着的会员版式：到期后改副标题也不拦
      expect(needsMembershipCoverLayout(CoverLayout.Framed, CoverLayout.Framed,
        CoverPhotoDraftKind.Unchanged, true)).assertFalse();
      expect(needsMembershipCoverLayout(CoverLayout.TipIn, CoverLayout.TipIn,
        CoverPhotoDraftKind.Replaced, true)).assertFalse();
    })

    it('needsMembershipByPhotoDraft', 0, () => {
      // 新选了会员版式（原来不是）：看照片改动三态
      expect(needsMembershipCoverLayout(CoverLayout.Framed, CoverLayout.FullBleed,
        CoverPhotoDraftKind.Replaced, false)).assertTrue();
      expect(needsMembershipCoverLayout(CoverLayout.Framed, CoverLayout.FullBleed,
        CoverPhotoDraftKind.Removed, true)).assertFalse();
      // 没动照片：原来有照片才拦（版式在照片上才起作用）
      expect(needsMembershipCoverLayout(CoverLayout.Framed, CoverLayout.FullBleed,
        CoverPhotoDraftKind.Unchanged, true)).assertTrue();
      expect(needsMembershipCoverLayout(CoverLayout.Framed, CoverLayout.FullBleed,
        CoverPhotoDraftKind.Unchanged, false)).assertFalse();
    })

    it('needsMembershipCreateModeNewPhoto', 0, () => {
      // 新建日记本（originalLayout = nil）+ 会员版式 + 新照片 → 拦
      expect(needsMembershipCoverLayout(CoverLayout.TipIn, undefined,
        CoverPhotoDraftKind.Replaced, false)).assertTrue();
    })

    // ---- 构图几何（iOS CoverCropView） ----

    it('cropWindowWidthPicksTheSmallerConstraint', 0, () => {
      // 宽裕（390×844）：受横留白限制 → 390 − 48 = 342
      expect(cropWindowWidth(390, 844)).assertEqual(342);
      // 竖着很紧（390×400）：高度约束赢 → (400 − 120) × 0.73 = 204.4
      expect(cropWindowWidth(390, 400)).assertEqual(204.4);
      // 横向极窄（200×400）：横留白约束赢 → 200 − 48 = 152
      expect(cropWindowWidth(200, 400)).assertEqual(152);
      // 极端小容器不塌成负数
      expect(cropWindowWidth(10, 10)).assertEqual(1);
    })

    it('baseFillScaleCoversWindowWithoutBlank', 0, () => {
      // 横图进竖窗：按高铺满（640 / 800 = 0.8）
      expect(baseFillScale(1000, 800, 342, 640)).assertEqual(0.8);
      // 竖图进竖窗：按宽铺满（342 / 1000）
      expect(baseFillScale(1000, 2000, 342, 468.5)).assertEqual(0.342);
      // 非法尺寸兜底 1
      expect(baseFillScale(0, 0, 342, 468.5)).assertEqual(1);
    })

    it('clampCropZoomBetweenOneAndMax', 0, () => {
      expect(clampCropZoom(0.2)).assertEqual(1);
      expect(clampCropZoom(1)).assertEqual(1);
      expect(clampCropZoom(2.5)).assertEqual(2.5);
      expect(clampCropZoom(9)).assertEqual(CROP_MAX_ZOOM);
    })

    it('clampCropOffsetKeepsImageOverWindow', 0, () => {
      // 图 1000×2000 px、窗 342×468.5 vp、base 0.342、zoom 1：宽正好铺满（可拖范围 0），高有余量
      expect(clampCropOffsetX(50, 1, 0.342, 1000, 342)).assertEqual(0);
      const maxY = (2000 * 0.342 - 468.5) / 2;
      expect(clampCropOffsetY(maxY + 100, 1, 0.342, 2000, 468.5)).assertEqual(maxY);
      expect(clampCropOffsetY(-maxY - 100, 1, 0.342, 2000, 468.5)).assertEqual(-maxY);
    })

    it('cropRectFromViewCenteredCoversWholeImage', 0, () => {
      // 图比例与窗口一致（1000×1370 vs 342×468.5，均 0.73）：居中不缩不放 = 整张图
      const rect = cropRectFromView(1000, 1370, 342, 468.5, 1, 0, 0);
      expect(Math.round(rect.x)).assertEqual(0);
      expect(Math.round(rect.y)).assertEqual(0);
      expect(Math.round(rect.width)).assertEqual(1000);
      expect(Math.round(rect.height)).assertEqual(1370);
    })

    it('cropRectFromViewZoomHalvesRect', 0, () => {
      // 放大 2 倍：取景框在原图上只框住一半宽（仍是中心）
      const rect = cropRectFromView(1000, 1370, 342, 468.5, 2, 0, 0);
      expect(Math.round(rect.x)).assertEqual(250);
      expect(Math.round(rect.width)).assertEqual(500);
      expect(Math.round(rect.height)).assertEqual(685);
    })

    it('cropRectFromViewOffsetShiftsCenterOppositely', 0, () => {
      // 往右拖 50vp（图跟着右移）→ 取景中心在原图上左移。
      // 浮点运算顺序不同会有 ~1e-14 尾差，按容差比
      const base = baseFillScale(1000, 1370, 342, 468.5); // 0.342
      const rect = cropRectFromView(1000, 1370, 342, 468.5, 1, 50, 0);
      const expectedX = (1000 - 342 / base) / 2 - 50 / base;
      expect(Math.abs(rect.x - expectedX) < 1e-9).assertTrue();
      // 窗口 468.5 不是整 0.73 比例：高方向差 0.06px 的余量，按公式比
      const expectedY = (1370 - 468.5 / base) / 2;
      expect(Math.abs(rect.y - expectedY) < 1e-9).assertTrue();
    })

    it('cropRectFromViewTooWideImageCropsSides', 0, () => {
      // 横图（2000×1000）：铺满按高走，左右各裁掉一截，取景框比例跟窗口走
      const rect = cropRectFromView(2000, 1000, 342, 468.5, 1, 0, 0);
      const base = baseFillScale(2000, 1000, 342, 468.5); // 0.4685（按高）
      const expectedX = (2000 - 342 / base) / 2;
      expect(Math.abs(rect.x - expectedX) < 1e-9).assertTrue();
      expect(Math.round(rect.y)).assertEqual(0);
      expect(Math.abs(rect.width / rect.height - 342 / 468.5) < 1e-9).assertTrue();
    })

    // ---- 烤盘尺寸 ----

    it('coverRenderSizeCapsAtPixelWidth', 0, () => {
      const size = coverRenderSize(2400);
      expect(size.width).assertEqual(1200);
      expect(size.height).assertEqual(1644); // round(1200 / 0.73)
    })

    it('coverRenderSizeDoesNotUpscale', 0, () => {
      // 像素不够按实际存，不放大（R-BOOK-12）
      const size = coverRenderSize(800.4);
      expect(size.width).assertEqual(800);
      expect(size.height).assertEqual(1096);
    })

    it('coverRenderSizeNeverCollapses', 0, () => {
      const size = coverRenderSize(0);
      expect(size.width).assertEqual(1);
      expect(size.height).assertEqual(1);
    })
  })
}
