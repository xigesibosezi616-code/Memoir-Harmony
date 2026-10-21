/**
 * 日记本封面（10_BUILD_MANUAL.md 3.1）。对应 iOS `Views/Home/BookCoverView.swift`
 * 与 `Shelf/ShelfBookView.swift`（鸿蒙侧合并为一个文件）。
 *
 * 没有照片 = 纯色亚麻（预渲染精修图 `cover_<color>_linen`，视觉细节全在 PNG 里，
 * 代码只叠标题与篇数）；有照片按版式（`CoverLayout`）分三种：
 * - **满版**：照片铺满，左侧书脊明暗 + 一道压痕、上下各压暗一层保证文字可读
 * - **白框**：米白纸封面，照片嵌上半部，书名写在照片下面
 * - **贴照片**：亚麻布面中间贴一张带白边、四角相角的照片，书名烫在下面
 *
 * 白框、贴照片各部分按封面宽度的比例摆，书架上的小书和（3.3 的）大预览长得一样。
 * 篇数一律按「这本书的实际篇数」传入，「全部日记」传全部篇数。
 */
import { image } from '@kit.ImageKit';
import { LengthMetrics } from '@kit.ArkUI';
import { BookColor, CoverLayout, coverDisplayName, isLightBookColor } from '../../models/Notebook';
import { PhotoPaperIO } from '../../services/PhotoPaperIO';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

/** 封面宽高比（iOS aspectRatio(0.73)） */
const COVER_ASPECT: number = 0.73;
/** 书口露出的宽度（vp）。格子要为它留出这么宽，书架上才对得齐 */
const PAGE_EDGE: number = 5;
/** 白框的纸与墨（iOS framedPaper / framedInk） */
const FRAMED_PAPER: string = '#F4EEE2';
const FRAMED_INK: string = '#3D3428';

/** 亚麻封面精修图（05 §4.1：8 色，素材已随 convert_materials 转入 media）。
 *  书架小书（BookCoverView）和 3.3 日记本主页大图（BookHeroView）共用 */
export function linenImageRes(color: BookColor): Resource {
  switch (color) {
    case BookColor.WineRed: return $r('app.media.cover_wine_red_linen');
    case BookColor.PineGreen: return $r('app.media.cover_pine_green_linen');
    case BookColor.PrussianBlue: return $r('app.media.cover_prussian_blue_linen');
    case BookColor.Eggplant: return $r('app.media.cover_eggplant_linen');
    case BookColor.AmberBrown: return $r('app.media.cover_amber_brown_linen');
    case BookColor.Charcoal: return $r('app.media.cover_charcoal_linen');
    case BookColor.Slate: return $r('app.media.cover_slate_linen');
    case BookColor.Ivory: return $r('app.media.cover_ivory_linen');
  }
}

@Component
export struct BookCoverView {
  /** 书名（原值；折行走 coverDisplayName） */
  @Prop name: string = '';
  @Prop entryCount: number = 0;
  @Prop color: BookColor = BookColor.WineRed;
  /** 照片封面文件名（journal_photos/ 裸名）；空 = 纯色亚麻 */
  @Prop @Watch('onPhotoSourceChange') coverPhotoFilename: string = '';
  /** 照片封面的版式；没有照片时不起作用 */
  @Prop layout: CoverLayout = CoverLayout.FullBleed;
  /** 封面宽（vp）。高 = 宽 / COVER_ASPECT，比例布局的基准 */
  @Prop coverWidthVp: number = 0;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @State private photoPixelMap: image.PixelMap | undefined = undefined;
  /** 照片加载失败（文件丢了等）：走纯色兜底，不留白块 */
  @State private photoFailed: boolean = false;

  aboutToAppear(): void {
    this.loadCoverPhoto();
  }

  build() {
    Stack() {
      if (this.hasPhoto()) {
        if (this.layout === CoverLayout.FullBleed) {
          this.fullBleedCover()
        } else if (this.layout === CoverLayout.Framed) {
          this.framedCover()
        } else {
          this.tipInCover()
        }
      } else {
        this.clothCover()
      }
    }
    .width(this.coverWidth())
    .height(this.coverWidth() / COVER_ASPECT)
    .shadow({
      radius: 10,
      color: '#33000000',
      offsetX: 2,
      offsetY: 6
    })
  }

  /** 有照片文件且没加载失败（还在加载时先走布面色占位，加载完成换照片重渲染） */
  private hasPhoto(): boolean {
    return this.coverPhotoFilename.length > 0 && !this.photoFailed;
  }

  private coverWidth(): number {
    return this.coverWidthVp;
  }

  private coverHeight(): number {
    return this.coverWidthVp / COVER_ASPECT;
  }

  /** 布面文字色：浅底（只有象牙白）用深棕，其余米白（iOS clothCover） */
  private clothTextColor(): string {
    return isLightBookColor(this.color) ? '#3D3428' : '#F5F0E6';
  }

  /** 照片封面换了（常驻的浮书 3.2 拿起另一本时）→ 清掉旧图重载，别沿用上一本的照片 */
  private onPhotoSourceChange(): void {
    this.photoPixelMap = undefined;
    this.photoFailed = false;
    this.loadCoverPhoto();
  }

  /** 加载照片封面（进程级缓存；失败置 photoFailed 走布面兜底） */
  private loadCoverPhoto(): void {
    if (this.coverPhotoFilename.length === 0) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    PhotoPaperIO.forFilesDir(context.filesDir)
      .loadImage(this.coverPhotoFilename)
      .then((pixelMap: image.PixelMap | undefined): void => {
        if (pixelMap === undefined) {
          this.photoFailed = true;
          return;
        }
        this.photoPixelMap = pixelMap;
      })
      .catch((): void => {
        this.photoFailed = true;
      });
  }

  // ---- 共用：标题与篇数 ----

  /** 左上的书名（纯色、满版用）。名字是用户数据，不查翻译表；折行走 coverDisplayName */
  @Builder
  private cornerTitle(textColor: string, shadowColor: string) {
    Column() {
      Text(coverDisplayName(this.name))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.theme.titleFont.family)
        .fontColor(textColor)
        .textShadow({
          radius: 1,
          color: shadowColor,
          offsetX: 0,
          offsetY: 0.5
        })
        .maxLines(3)
        .lineSpacing(LengthMetrics.vp(4))
        .textAlign(TextAlign.Start)
        .padding({
          left: 16,
          right: 16,
          top: 28
        })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  /** 左下的篇数：小圆点 + 数字（iOS countBadge） */
  @Builder
  private countBadge(textColor: string, opacity: number) {
    Row({ space: 4 }) {
      Circle({ width: 5, height: 5 })
        .fill(textColor)
        .opacity(0.55)
      Text(`${this.entryCount}`)
        .fontSize(11)
        .fontFamily(this.theme.titleFont.family)
        .fontColor(textColor)
        .opacity(opacity)
    }
  }

  /** 左下角的篇数（多数版式共用：定位到封面左下） */
  @Builder
  private bottomCount(textColor: string, opacity: number) {
    Column() {
      this.countBadge(textColor, opacity)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.End)
    .padding({ left: 16, bottom: 14 })
  }

  /** 书脊处的明暗 + 一道压痕（精装书封面靠近书脊处的那条凹槽，iOS hinge） */
  @Builder
  private hinge(strength: number) {
    Column() {
      Row() {
        Column()
          .width(9)
          .height('100%')
          .linearGradient({
            angle: 90,
            colors: [
              [`rgba(0,0,0,${0.45 * strength})`, 0],
              [`rgba(0,0,0,${0.12 * strength})`, 1]
            ] as [ResourceColor, number][]
          })
        Column()
          .width(0.8)
          .height('100%')
          .backgroundColor(`rgba(0,0,0,${0.22 * strength})`)
        Column()
          .width(0.6)
          .height('100%')
          .backgroundColor('rgba(255,255,255,0.22)')
      }
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 纯色亚麻 ----

  @Builder
  private clothCover() {
    Stack() {
      Image(linenImageRes(this.color))
        .objectFit(ImageFit.Cover)
        .width('100%')
        .height('100%')
      this.cornerTitle(this.clothTextColor(),
        isLightBookColor(this.color) ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.4)')
      this.bottomCount(this.clothTextColor(), 0.65)
    }
    .width('100%')
    .height('100%')
  }

  // ---- 满版 ----

  @Builder
  private fullBleedCover() {
    Stack() {
      if (this.photoPixelMap !== undefined) {
        Image(this.photoPixelMap)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      } else {
        // 加载中先铺布面色，避免闪白
        Image(linenImageRes(this.color))
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      }
      // 上下压暗：上面给标题、下面给篇数，在任何照片上都读得清；中间留给照片本身
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            ['rgba(0,0,0,0.42)', 0],
            ['rgba(0,0,0,0)', 0.45],
            ['rgba(0,0,0,0)', 0.75],
            ['rgba(0,0,0,0.32)', 1]
          ] as [ResourceColor, number][]
        })
      this.hinge(1)
      this.cornerTitle('#F5F0E6', 'rgba(0,0,0,0.55)')
      this.bottomCount('#F5F0E6', 0.8)
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .borderRadius(2.5)
    .border({ width: 0.6, color: 'rgba(0,0,0,0.18)' })
  }

  // ---- 白框 ----

  @Builder
  private framedCover() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [['#F8F3EA', 0], [FRAMED_PAPER, 1]] as [ResourceColor, number][]
        })
      Column() {
        // 抬头：篇数 + 一道细线（参考图的刊头）
        Row() {
          this.countBadge(FRAMED_INK, 0.6)
        }
        .height(this.coverHeight() * 0.11)
        Row()
          .width('100%')
          .height(0.5)
          .backgroundColor(FRAMED_INK)
          .opacity(0.35)
        // 照片：方形（封面宽 − 左右页边，iOS margin = w × 0.1）
        Stack() {
          if (this.photoPixelMap !== undefined) {
            Image(this.photoPixelMap)
              .objectFit(ImageFit.Cover)
              .width('100%')
              .height('100%')
          } else {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('#E8DDC9')
          }
        }
        .width(this.coverWidth() * 0.8)
        .height(this.coverWidth() * 0.8)
        .margin({ top: this.coverHeight() * 0.03 })
        Text(coverDisplayName(this.name))
          .fontSize(Math.max(10, this.coverWidth() * 0.1))
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.theme.titleFont.family)
          .fontColor(FRAMED_INK)
          .maxLines(2)
          .lineSpacing(LengthMetrics.vp(2))
          .margin({ top: this.coverHeight() * 0.04 })
      }
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: this.coverWidth() * 0.1,
        right: this.coverWidth() * 0.1
      })
      this.hinge(0.35)
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .borderRadius(2.5)
    .border({ width: 0.5, color: 'rgba(0,0,0,0.12)' })
  }

  // ---- 贴照片 ----

  /** 烫在布面上的颜色：象牙白布面压深棕（像压痕），其余烫金（iOS foil） */
  private foilColor(): string {
    return isLightBookColor(this.color) ? '#6B5A3E' : '#D9C08A';
  }

  /** 贴照片的照片板宽（连白边在内） */
  private plateWidth(): number {
    return this.coverWidth() * 0.6;
  }

  /** 相角三角形路径：贴照片板的四角，corner = 板宽 × 0.15（iOS MountedPhoto） */
  private cornerTriangle(left: boolean, top: boolean): string {
    const w = this.plateWidth();
    const h = w * 1.1;
    const c = w * 0.15;
    if (left && top) {
      return `M 0 0 L ${c} 0 L 0 ${c} Z`;
    }
    if (!left && top) {
      return `M ${w} 0 L ${w - c} 0 L ${w} ${c} Z`;
    }
    if (left && !top) {
      return `M 0 ${h} L ${c} ${h} L 0 ${h - c} Z`;
    }
    return `M ${w} ${h} L ${w - c} ${h} L ${w} ${h - c} Z`;
  }

  @Builder
  private tipInCover() {
    Stack() {
      Image(linenImageRes(this.color))
        .objectFit(ImageFit.Cover)
        .width('100%')
        .height('100%')
      Column() {
        // 贴照片：带白边 + 四角相角（iOS MountedPhoto）
        Stack() {
          // 白边相纸底
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#F6F1E6')
            .shadow({
              radius: 1.5,
              color: 'rgba(0,0,0,0.32)',
              offsetX: 0,
              offsetY: 1
            })
          // 照片嵌在白边里（边宽 = 板宽 × 0.05）
          Stack() {
            if (this.photoPixelMap !== undefined) {
              Image(this.photoPixelMap)
                .objectFit(ImageFit.Cover)
                .width('100%')
                .height('100%')
            } else {
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor('#E8DDC9')
            }
          }
          .width('100%')
          .height('100%')
          .padding(this.plateWidth() * 0.05)
          // 四角相角：深色小三角压住照片的角
          Path()
            .commands(this.cornerTriangle(true, true))
            .width('100%')
            .height('100%')
            .fill('rgba(43,37,33,0.92)')
          Path()
            .commands(this.cornerTriangle(false, true))
            .width('100%')
            .height('100%')
            .fill('rgba(43,37,33,0.92)')
          Path()
            .commands(this.cornerTriangle(true, false))
            .width('100%')
            .height('100%')
            .fill('rgba(43,37,33,0.92)')
          Path()
            .commands(this.cornerTriangle(false, false))
            .width('100%')
            .height('100%')
            .fill('rgba(43,37,33,0.92)')
        }
        .width(this.plateWidth())
        .height(this.plateWidth() * 1.1)
        .margin({ top: this.coverHeight() * 0.13 })
        // 书名烫在照片下面
        Text(coverDisplayName(this.name))
          .fontSize(Math.max(10, this.coverWidth() * 0.1))
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.theme.titleFont.family)
          .fontColor(this.foilColor())
          .textShadow({
            radius: 0.5,
            color: isLightBookColor(this.color) ? 'rgba(0,0,0,0.08)' : 'rgba(0,0,0,0.35)',
            offsetX: 0,
            offsetY: 1
          })
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .padding({
            left: this.coverWidth() * 0.12,
            right: this.coverWidth() * 0.12
          })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
  }
}

/**
 * 书架上的一本书：封面 + 右侧露出的一条书口（纸页厚度，iOS `ShelfBookView`）。
 * 格子里的书和（3.2 拿起的）浮书都用这一个视图——两者必须长得一模一样。
 */
@Component
export struct ShelfBookView {
  @Prop name: string = '';
  @Prop entryCount: number = 0;
  @Prop color: BookColor = BookColor.Ivory;
  @Prop coverPhotoFilename: string = '';
  @Prop layout: CoverLayout = CoverLayout.FullBleed;
  /** 整本书的宽（vp，含书口那 5vp）；封面宽 = 它 − 5 */
  @Prop bookWidthVp: number = 0;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 纸页块和封面一样大，往右错开一点，只露出右边一条（书口）
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#ECE4D3')
          .borderRadius(2)
          .shadow({
            radius: 2.5,
            color: '#33000000',
            offsetX: 1,
            offsetY: 1
          })
        // 一页页纸叠起来的细纹，只画在露出来的最右边
        Row({ space: 0.9 }) {
          Column().width(0.4).height('100%').backgroundColor('rgba(0,0,0,0.11)')
          Column().width(0.4).height('100%').backgroundColor('rgba(0,0,0,0.09)')
          Column().width(0.4).height('100%').backgroundColor('rgba(0,0,0,0.07)')
          Column().width(0.4).height('100%').backgroundColor('rgba(0,0,0,0.05)')
        }
        .height('100%')
        .padding({ top: 2, bottom: 2 })
      }
      .width(this.coverWidth())
      .height(this.coverWidth() / COVER_ASPECT - 6)
      .offset({ x: PAGE_EDGE })
      // 封面本体（iOS 的第二道小投影挂在这层，Stack 单 shadow 会覆盖）
      Stack() {
        BookCoverView({
          name: this.name,
          entryCount: this.entryCount,
          color: this.color,
          coverPhotoFilename: this.coverPhotoFilename,
          layout: this.layout,
          coverWidthVp: this.coverWidth()
        })
      }
      .shadow({
        radius: 3,
        color: '#1F000000',
        offsetX: 0,
        offsetY: 2
      })
    }
    .width(this.bookWidthVp)
    .height(this.coverWidth() / COVER_ASPECT)
  }

  private coverWidth(): number {
    return this.bookWidthVp - PAGE_EDGE;
  }
}
