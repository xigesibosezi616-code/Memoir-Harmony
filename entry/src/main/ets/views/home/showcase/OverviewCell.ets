/**
 * 总览里的一格（10_BUILD_MANUAL.md 3.6 + U06 R-HOME-08）。对应 iOS
 * `Views/Home/Overview/OverviewCell.swift`：缩小了的大卡片，越密越简。
 *
 * - 一屏 4 篇：小一号的大卡片（照片 58%，下缘溶进底色；标题 / 日期·心情 /
 *   两行正文）
 * - 一屏 16 篇：方形照片 + 标题一行 + 「17日 周六」一行，不做溶边
 * - 一屏 64 篇：整格照片 + 左下角几号（底下垫 0→38% 暗渐变）
 *
 * 🔴 一屏可能有六七十格、滚动时不停新建，这里什么都不重算（文字取
 * digest，照片后台解 `EntryPhotoStore`，底色随照片一起算好）；
 * 16 / 64 篇照片解好直接出来，4 篇淡入 0.2 秒（U06 R-HOME-10）。
 * 格子大小用相对布局（'100%'），不用 GeometryReader 量。
 */
import { image } from '@kit.ImageKit';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { EntryDigest, ShowcaseZoomLevel, zoomCornerRadius,
  zoomPhotoPixels } from '../../../models/ShowcaseDigest';
import { EntryPhoto, EntryPhotoStore } from '../../../services/EntryPhotoStore';
import { moodLabelRes } from '../../components/MoodBadge';
import { isDefaultMoodKey } from '../../../models/Mood';
import { cardTintGradient, colorToArgb, dissolveEndColor,
  moodCoverGradient, resolveTintHex, TintTextColors,
  tintTextColorsFor } from './ShowcasePalette';

/** 四篇格子的照片区高度占比（iOS `height * 0.58`） */
const CARD_COVER_RATIO: number = 0.58;

@Component
export struct OverviewCell {
  /** 显示数据（digestOf 算好的，不在格子里解正文） */
  digest: EntryDigest = new EntryDigest('', '', '', '', '', '', '', 0, '', '', 0);
  /** 1 = 四篇、2 = 十六篇、3 = 六十四篇 */
  zoom: number = ShowcaseZoomLevel.Four;
  /** 点一格打开那篇 */
  onOpen: (id: string) => void = (_id: string): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  @State private pixelMap: image.PixelMap | undefined = undefined;
  @State private tintHex: string = '#808080';
  @State private photoLoaded: boolean = false;

  aboutToAppear(): void {
    const store = EntryPhotoStore.shared();
    const cover = this.digest.cover;
    if (cover.length > 0) {
      const pixels = zoomPhotoPixels(this.zoom);
      const exact = store.cached(cover, pixels);
      const any = exact !== undefined ? exact : store.anyCached(cover);
      if (any !== undefined) {
        this.pixelMap = any.pixelMap;
        this.tintHex = any.tintHex;
        this.photoLoaded = true;
      }
      const known = store.knownTint(cover);
      if (known !== undefined) {
        this.tintHex = known;
      } else if (!this.photoLoaded) {
        this.tintHex = resolveTintHex(undefined, undefined,
          this.digest.moodColorHex, this.theme);
      }
      if (exact === undefined) {
        store.load(cover, pixels).then((photo: EntryPhoto | undefined): void => {
          if (photo === undefined || this.pixelMap !== undefined) {
            return;
          }
          if (this.zoom === ShowcaseZoomLevel.Four) {
            // 一屏四篇格子大、少：照片淡入 0.2s（16/64 篇直接出来，
            // 几十格各放动画会把主线程占满——U06 R-HOME-10）
            this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
              this.pixelMap = photo.pixelMap;
              this.tintHex = photo.tintHex;
              this.photoLoaded = true;
            });
          } else {
            this.pixelMap = photo.pixelMap;
            this.tintHex = photo.tintHex;
            this.photoLoaded = true;
          }
        }).catch((): void => {
        });
      }
    } else {
      this.tintHex = resolveTintHex(undefined, undefined,
        this.digest.moodColorHex, this.theme);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 底色：tint 72%→94% 叠页面底（合成不透明；iOS 同算法，垫页面底色）
      Column()
        .width('100%')
        .height('100%')
        .linearGradient(this.tintGradient())

      if (this.zoom === ShowcaseZoomLevel.Four) {
        this.cardBody()
      } else if (this.zoom === ShowcaseZoomLevel.Sixteen) {
        this.tileBody()
      } else {
        this.chipBody()
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(zoomCornerRadius(this.zoom))
    .clip(true)
    .border({
      width: this.zoom === ShowcaseZoomLevel.SixtyFour ? 0.5 : 0.8,
      color: 0x2EFFFFFF // 白 18% 细边
    })
    .accessibilityText(this.cellAccessibilityText())
    .onClick((): void => {
      this.onOpen(this.digest.id);
    })
  }

  // ---- 一屏 4 篇：小一号的大卡片 ----

  @Builder
  private cardBody() {
    Column() {
      // 照片区（58%）：照片 / 心情色渐变 + 下缘溶进底色（U06：一屏只有四格，
      // 溶得起来）。overlay 渐到与底色逐像素一致的不透明色，无缝
      Stack() {
        this.cover()
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [
              [Color.Transparent, 0.72],
              [this.dissolveMidColor(), 0.9],
              [this.dissolveEnd(), 1]
            ]
          })
      }
      .width('100%')
      .height(`${CARD_COVER_RATIO * 100}%`)
      .clip(true)

      Column({ space: 4 }) {
        Text(this.titleText())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily('serif')
          .fontColor(this.textColors().title)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 4 }) {
          Text(this.digest.dayWithWeekday)
            .fontSize(11)
            .fontColor(this.textColors().meta)
            .maxLines(1)
          if (this.moodLabelText() !== undefined) {
            Text('·')
              .fontSize(11)
              .fontColor(this.textColors().meta)
            Text(this.moodLabelText())
              .fontSize(11)
              .fontColor(this.textColors().meta)
              .maxLines(1)
          }
        }
        .width('100%')
        if (this.digest.preview.length > 0) {
          Text(this.digest.preview)
            .fontSize(12)
            .fontColor(this.textColors().body)
            .lineHeight(16)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12, top: 2, bottom: 8 })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  // ---- 一屏 16 篇：方形照片 + 标题 + 几号 ----

  @Builder
  private tileBody() {
    Column() {
      // 不做溶边（十六格各一次离屏太费）：照片和字条直接分开，小格子里看着反而干净
      Stack() {
        this.cover()
      }
      .aspectRatio(1)
      .width('100%')
      .clip(true)
      Column({ space: 1 }) {
        Text(this.titleText())
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontFamily('serif')
          .fontColor(this.textColors().title)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.digest.dayWithWeekday)
          .fontSize(9)
          .fontColor(this.textColors().meta)
          .maxLines(1)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  // ---- 一屏 64 篇：整格照片 + 几号 ----

  @Builder
  private chipBody() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Stack() {
        this.cover()
      }
      .width('100%')
      .height('100%')
      // 几号底下的暗渐变：浅色照片上也看得清（有照片 38%，心情色底 12%）
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: this.photoLoaded
            ? [[Color.Transparent, 0.5], [0x61000000, 1]]
            : [[Color.Transparent, 0.5], [0x1F000000, 1]]
        })
      Text(`${this.digest.day}`)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .padding({ left: 4, bottom: 3 })
    }
    .width('100%')
    .height('100%')
  }

  // ---- 共用 ----

  /** 照片铺满；没照片是心情色的渐变；还在解就先空着（不闪底色） */
  @Builder
  private cover() {
    if (this.pixelMap !== undefined) {
      Image(this.pixelMap)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .interpolation(ImageInterpolation.Medium)
        .transition(TransitionEffect.OPACITY)
    } else if (this.digest.cover.length === 0) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: this.moodGradientColors()
        })
    }
  }

  private tintArgb(): number {
    const parsed = colorToArgb(this.tintHex);
    return parsed === undefined ? 0xFF808080 : parsed;
  }

  private pageBgArgb(): number {
    const bg = colorToArgb(this.theme.background);
    return bg === undefined ? 0xFFFFFFFF : bg;
  }

  private tintGradient(): LinearGradientOptions {
    const colors = cardTintGradient(this.tintArgb(), this.pageBgArgb());
    return {
      angle: 180,
      colors: [[colors[0], 0], [colors[1], 1]]
    };
  }

  /** 照片下缘溶进底色：渐到与底色在照片区底缘同色（合成色严丝合缝） */
  private dissolveEnd(): ResourceColor {
    return dissolveEndColor(this.tintArgb(), this.pageBgArgb(), CARD_COVER_RATIO);
  }

  /** 溶解中段：底缘色 35% 透明（对应 iOS mask 的 90% 处白 35%） */
  private dissolveMidColor(): ResourceColor {
    const end = dissolveEndColor(this.tintArgb(), this.pageBgArgb(), CARD_COVER_RATIO);
    return (end & 0x00FFFFFF) | 0x59000000;
  }

  private moodGradientColors(): Array<[ResourceColor, number]> {
    const colors = moodCoverGradient(this.tintArgb(), this.pageBgArgb());
    return [[colors[0], 0], [colors[1], 1]];
  }

  private textColors(): TintTextColors {
    return tintTextColorsFor(this.tintHex);
  }

  /** 标题：有标题用标题，都空显示「无题」 */
  private titleText(): ResourceStr {
    if (this.digest.title.length > 0) {
      return this.digest.title;
    }
    return $r('app.string.s_6a576f3bf9');
  }

  private moodLabelText(): ResourceStr | undefined {
    if (this.digest.moodKey.length === 0) {
      return undefined;
    }
    if (isDefaultMoodKey(this.digest.moodKey)) {
      const res = moodLabelRes(this.digest.moodKey);
      if (res !== undefined) {
        return res;
      }
    }
    return this.digest.moodKey;
  }

  /** 读屏：日期, 标题（iOS `accessibilityText`） */
  private cellAccessibilityText(): string {
    const title = this.digest.title.length > 0
      ? this.digest.title : '';
    const parts: string[] = [this.digest.dayAndWeekday, title];
    return parts.filter((part: string): boolean => part.length > 0).join(', ');
  }
}
