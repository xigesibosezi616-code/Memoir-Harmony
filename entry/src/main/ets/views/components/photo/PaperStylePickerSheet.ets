/**
 * 相纸选择器（10_BUILD_MANUAL.md 2.6）。对应 iOS `PaperStylePickerView.swift`：
 * 以 sheet 弹出，横向滚动六张实际预览，点任意一张选定并回调（点完即插，无二次确认）。
 *
 * - 预览用的是**用户刚选的照片**（iOS 同款），所见即所得
 * - 会员款 2.6 全放开（用户拍板）：不显示锁标、不弹付费页；
 *   `isMember` 参数留给 7.2——接上判定后，会员款点按走 `onLockedPick` 弹付费页
 * - 选中的样式由调用方写 `PREF_KEY_DEFAULT_PAPER_STYLE`（下次预选，05 §3.5）
 */
import { image } from '@kit.ImageKit';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { PaperStyle, PhotoPosition } from '../../../models/ContentBlock';
import { PaperPreviewCard } from './PhotoPapers';

/** 六种相纸的展示顺序（iOS `PaperStyle.allCases` 同序） */
const PICKER_STYLES: PaperStyle[] = [
  PaperStyle.Original,
  PaperStyle.Polaroid,
  PaperStyle.WashiSticker,
  PaperStyle.MinimalCard,
  PaperStyle.FilmFrame,
  PaperStyle.LetterAttached
];

@Component
export struct PaperStylePickerSheet {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  /** 刚选好的照片（预览即成片） */
  pixelMap: image.PixelMap | undefined = undefined;
  /** 是否显示「放在左/右」分段（新照片插入时 true；换相纸不显示） */
  showPositionPicker: boolean = false;
  /** 选中的插入边（默认右边，2026-10-17 产品拍板） */
  @State private photoSide: PhotoPosition = PhotoPosition.Right;
  /** 点了某张相纸（调用方：写偏好 + 按所选边插入正文） */
  onSelect: (style: PaperStyle, position: PhotoPosition) => void =
    (_style: PaperStyle, _position: PhotoPosition): void => {};
  /** 取消 */
  onCancel: () => void = (): void => {};
  /** 会员判定（7.2 接上；2.6 恒 true 全放开） */
  isMember: boolean = true;
  /** 点中会员款但非会员（7.2 弹付费页；2.6 不会触发） */
  onLockedPick: (() => void) | undefined = undefined;

  build() {
    Column() {
      // 顶部标题（iOS：Georgia 18 主标题 + 12 辅说明）
      Column({ space: 4 }) {
        Text($r('app.string.s_16460eb17d'))
          .fontSize(18)
          .fontFamily('Georgia')
          .fontColor(this.theme.textPrimary)
        Text($r('app.string.s_bc369f65c9'))
          .fontSize(12)
          .fontColor(this.theme.textTertiary)
      }
      .padding({ top: 28 })

      // 插入选边（仅新照片；换相纸模式不显示）：默认右边
      if (this.showPositionPicker) {
        Row({ space: 10 }) {
          Text($r('app.string.s_7c3f9e2a'))
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
          Row() {
            this.positionOption(PhotoPosition.Left, $r('app.string.s_2e8d4f6b'))
            this.positionOption(PhotoPosition.Right, $r('app.string.s_9b5c1d3f'))
          }
          .borderRadius(17)
          .backgroundColor(this.theme.accentBackground)
          .padding(2)
        }
        .padding({ top: 14 })
      }

      // 横向滚动的样式预览（卡片统一 120×160 外框）
      Scroll() {
        Row({ space: 20 }) {
          ForEach(PICKER_STYLES, (style: PaperStyle) => {
            this.styleButton(style)
          }, (style: PaperStyle) => style)
        }
        .padding({ left: 24, right: 24, top: 16, bottom: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      Blank()

      // 取消按钮（iOS：15 号、次级文字色、通栏）
      Text($r('app.string.s_4d0b4688c7'))
        .fontSize(15)
        .fontColor(this.theme.textSecondary)
        .width('100%')
        .padding({ top: 14, bottom: 14 })
        .margin({ left: 24, right: 24, bottom: 28 })
        .textAlign(TextAlign.Center)
        .onClick((): void => {
          this.onCancel();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }

  /** 单张样式卡：预览 + 名称，点按即选定（会员锁 7.2 前不生效） */
  @Builder
  private styleButton(style: PaperStyle) {
    Column({ space: 10 }) {
      PaperPreviewCard({
        style: style,
        pixelMap: this.pixelMap
      })
      Text(this.styleName(style))
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
    }
    .onClick((): void => {
      if (!this.isMember && this.onLockedPick !== undefined) {
        this.onLockedPick();
        return;
      }
      this.onSelect(style, this.photoSide);
    })
  }

  /** 「左边 / 右边」分段选项（胶囊分段，选中态浅底高亮） */
  @Builder
  private positionOption(side: PhotoPosition, label: Resource) {
    Text(label)
      .fontSize(13)
      .fontColor(this.photoSide === side ? this.theme.textPrimary : this.theme.textSecondary)
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .borderRadius(15)
      .backgroundColor(this.photoSide === side ? this.theme.background : Color.Transparent)
      .onClick((): void => {
        this.photoSide = side;
      })
  }

  private styleName(style: PaperStyle): Resource {
    switch (style) {
      case PaperStyle.Original:
        return $r('app.string.s_cd0f3ad8dd');
      case PaperStyle.WashiSticker:
        return $r('app.string.s_105137838b');
      case PaperStyle.MinimalCard:
        return $r('app.string.s_234289679b');
      case PaperStyle.FilmFrame:
        return $r('app.string.s_c3915c323e');
      case PaperStyle.LetterAttached:
        return $r('app.string.s_975ac3e011');
      default:
        return $r('app.string.s_f4ae8c66ad');
    }
  }
}
