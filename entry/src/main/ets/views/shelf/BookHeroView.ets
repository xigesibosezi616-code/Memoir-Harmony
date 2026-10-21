/**
 * 日记本主页顶部的大图（10_BUILD_MANUAL.md 3.3，R-BOOK-09/14）。
 * 对应 iOS `Views/Home/BookHome/BookHeroView.swift`。高度由外面定
 * （约屏高六成，参考图 ① / ④）。和书架上的封面一一对应，四种版式：
 *
 * - **满版**：照片铺满，往下渐渐融进页面底色；书名用正文色写在融化的那一段上；
 *   顶部压一层浅暗，状态栏和返回键在亮照片上也看得清
 * - **白框**：整幅米白纸，照片嵌在中间，书名写在照片下面 —— 一页杂志
 * - **贴照片**：布面铺满，正中贴一张带白边、压着相角的照片，书名烫在下面
 * - **纯色亚麻**：布面放大铺满（取封面图中间偏上那块，压边框 / 书脊阴影 /
 *   烫标都裁在外面），书名像烫在布面正中，上下各一道细线
 *
 * 只有满版往下渐隐；其余三种底边干净地收住（深色布渐隐到米白会混出脏粉色）。
 */
import { image } from '@kit.ImageKit';
import { BookColor, CoverLayout, isLightBookColor } from '../../models/Notebook';
import { PhotoPaperIO } from '../../services/PhotoPaperIO';
import { linenImageRes } from './BookCoverView';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

/** 满版底部融进页面底色的那一段有多高（iOS fadeHeight） */
const FADE_HEIGHT: number = 150;
/** 满版顶部压暗的高（亮照片上状态栏 / 返回键看得清） */
const TOP_DIM_HEIGHT: number = 140;
/** 上面压着状态栏和返回键，版式内容从这往下排（iOS topClearance） */
const TOP_CLEARANCE: number = 104;
/** 白框的纸与墨（与书架封面一致，iOS framedPaper / framedInk） */
const FRAMED_PAPER: string = '#F4EEE2';
const FRAMED_INK: string = '#3D3428';

@Component
export struct BookHeroView {
  /** 书名（「全部日记」由调用方翻译好再传进来） */
  @Prop title: string = '';
  /** 副标题；'' = 不显示 */
  @Prop subtitle: string = '';
  @Prop color: BookColor = BookColor.Ivory;
  /** 照片封面文件名（journal_photos/ 裸名）；空 = 纯色布面 */
  @Prop @Watch('onPhotoSourceChange') coverPhotoFilename: string = '';
  /** 照片封面的版式；没有照片时不起作用 */
  @Prop layout: CoverLayout = CoverLayout.FullBleed;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @State private photoPixelMap: image.PixelMap | undefined = undefined;
  /** 照片加载失败（文件丢了等）：走布面兜底，不留白块 */
  @State private photoFailed: boolean = false;
  /** 容器尺寸（vp）：贴照片的板宽按可用高度反推（iOS GeometryReader） */
  @State private heroWidthVp: number = 0;
  @State private heroHeightVp: number = 0;

  aboutToAppear(): void {
    this.loadCoverPhoto();
  }

  build() {
    Stack() {
      if (this.style() === 'fullBleed') {
        this.fullBleedHero()
      } else if (this.style() === 'framed') {
        this.framedHero()
      } else if (this.style() === 'tipIn') {
        this.tipInHero()
      } else {
        this.clothHero()
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const w: Length = newArea.width;
      const h: Length = newArea.height;
      if (typeof w === 'number') {
        this.heroWidthVp = w;
      }
      if (typeof h === 'number') {
        this.heroHeightVp = h;
      }
    })
  }

  // ---- 版式判定（iOS style：没照片一律布面） ----

  private style(): string {
    if (this.coverPhotoFilename.length === 0 || this.photoFailed) {
      return 'cloth';
    }
    if (this.layout === CoverLayout.FullBleed) {
      return 'fullBleed';
    }
    if (this.layout === CoverLayout.Framed) {
      return 'framed';
    }
    return 'tipIn';
  }

  /** 照片封面换了（条件挂载换本时）→ 清掉旧图重载，别沿用上一本的照片 */
  private onPhotoSourceChange(): void {
    this.photoPixelMap = undefined;
    this.photoFailed = false;
    this.loadCoverPhoto();
  }

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

  // ---- 布面（纯色亚麻，也垫在贴照片底下） ----

  /** 布面铺满：精修图放大 1.25、锚在中间偏上，压边框 / 书脊阴影 / 烫标都裁在外面 */
  @Builder
  private clothBackground() {
    Image(linenImageRes(this.color))
      .objectFit(ImageFit.Cover)
      .width('100%')
      .height('100%')
      .scale({ x: 1.25, y: 1.25, centerX: '50%', centerY: '42%' })
  }

  /** 烫在布面上的颜色：象牙白布面压深棕（像压痕），其余烫金（iOS foil） */
  private foilColor(): string {
    return isLightBookColor(this.color) ? '#6B5A3E' : '#D9C08A';
  }

  /** 布面居中标题：上下各一道细线，书名像烫在布面正中（iOS clothTitle） */
  @Builder
  private clothTitle() {
    Column({ space: 14 }) {
      Row()
        .width(36)
        .height(0.8)
        .backgroundColor(this.foilColor())
        .opacity(0.7)
      Text(this.title)
        .fontSize(28)
        .fontWeight(FontWeight.Normal)
        .fontFamily(this.theme.titleFont.family)
        .fontColor(this.foilColor())
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .minFontSize(20)
        .textShadow({
          radius: 0.5,
          color: isLightBookColor(this.color) ? 'rgba(0,0,0,0.08)' : 'rgba(0,0,0,0.35)',
          offsetX: 0,
          offsetY: 1
        })
        .padding({ left: 40, right: 40 })
      Row()
        .width(36)
        .height(0.8)
        .backgroundColor(this.foilColor())
        .opacity(0.7)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.foilColor())
          .opacity(0.85)
          .letterSpacing(2.4)
          .maxLines(1)
      }
    }
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private clothHero() {
    Stack() {
      this.clothBackground()
      Column() {
        this.clothTitle()
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      // 干净地收在一条边上：底边一点暗影 + 一道细亮线（浅布亮线强、深布弱）
      this.cleanBottomEdge(isLightBookColor(this.color))
    }
  }

  /** 底边收边：一点暗影 + 一道细亮线，像封面的下沿（非满版共用） */
  @Builder
  private cleanBottomEdge(lightBase: boolean) {
    Column() {
      Column()
        .width('100%')
        .height(22)
        .linearGradient({
          angle: 180,
          colors: [
            ['rgba(0,0,0,0)', 0],
            [`rgba(0,0,0,${lightBase ? 0.08 : 0.22})`, 1]
          ] as [ResourceColor, number][]
        })
      Row()
        .width('100%')
        .height(0.5)
        .backgroundColor(Color.White)
        .opacity(lightBase ? 0.5 : 0.12)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .position({ x: 0, y: '100%' })
    .translate({ y: -22.5 })
  }

  // ---- 满版 ----

  @Builder
  private fullBleedHero() {
    Stack() {
      if (this.photoPixelMap !== undefined) {
        Image(this.photoPixelMap)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      } else {
        // 加载中先铺布面色，避免闪白
        this.clothBackground()
      }
      // 顶部压暗：状态栏、返回键压在亮照片上也看得清
      Column()
        .width('100%')
        .height(TOP_DIM_HEIGHT)
        .linearGradient({
          angle: 180,
          colors: [['rgba(0,0,0,0.28)', 0], ['rgba(0,0,0,0)', 1]] as [ResourceColor, number][]
        })
      // 融进页面底色，和下面的目录接成一体（参考图 ④）
      Column()
        .width('100%')
        .height(FADE_HEIGHT)
        .linearGradient({
          angle: 180,
          colors: this.fadeColors()
        })
      // 书名 + 副标题写在融化的那一段上
      Column({ space: 8 }) {
        Text(this.title)
          .fontSize(30)
          .fontWeight(FontWeight.Normal)
          .fontFamily(this.theme.titleFont.family)
          .fontColor(this.theme.textPrimary)
          .maxLines(2)
          .minFontSize(21)
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.textSecondary)
            .letterSpacing(2.4)
            .maxLines(1)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 22, right: 22, bottom: 14 })
      .position({ x: 0, y: '100%' })
      .translate({ y: -14 })
    }
  }

  /** 渐隐色标：主题背景 0 → 0.85 → 1（iOS 三档 stops；主题色统一数字色，可叠 alpha） */
  private fadeColors(): [ResourceColor, number][] {
    const bg = this.theme.background;
    const base = typeof bg === 'number' ? bg : 0xFFFAF7F2;
    return [
      [(base & 0x00FFFFFF) | 0x00000000, 0],
      [(base & 0x00FFFFFF) | 0xD9000000, 0.7],
      [(base & 0x00FFFFFF) | 0xFF000000, 1]
    ] as [ResourceColor, number][];
  }

  // ---- 白框 ----

  @Builder
  private framedHero() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [['#F8F3EA', 0], [FRAMED_PAPER, 1]] as [ResourceColor, number][]
        })
      Column() {
        Row()
          .width('100%')
          .height(0.5)
          .backgroundColor(FRAMED_INK)
          .opacity(0.3)
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
        .aspectRatio(1)
        .clip(true)
        .margin({ top: 16 })
        Text(this.title)
          .fontSize(28)
          .fontWeight(FontWeight.Normal)
          .fontFamily(this.theme.titleFont.family)
          .fontColor(FRAMED_INK)
          .maxLines(2)
          .minFontSize(20)
          .margin({ top: 18 })
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(FRAMED_INK)
            .opacity(0.6)
            .letterSpacing(2.4)
            .maxLines(1)
            .margin({ top: 8 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 26, right: 26, top: TOP_CLEARANCE, bottom: 30 })
      this.cleanBottomEdge(true)
    }
  }

  // ---- 贴照片 ----

  /**
   * 贴照片的照片板宽（连白边在内）。照片 + 书名要塞进导航栏以下的那段里：
   * 宽度按可用高度反推，免得矮屏上挤出去（iOS tipInContent）。
   * 还没量到时先用宽度的 52% 占位，量到后重排。
   */
  private plateWidthVp(): number {
    const byWidth = this.heroWidthVp > 0 ? this.heroWidthVp * 0.52 : 0;
    if (this.heroHeightVp > 0) {
      const available = this.heroHeightVp - TOP_CLEARANCE - 130;
      const byHeight = available > 0 ? available / 1.1 : 0;
      if (byHeight > 0 && (byWidth === 0 || byHeight < byWidth)) {
        return byHeight;
      }
    }
    return byWidth > 0 ? byWidth : 180;
  }

  @Builder
  private tipInHero() {
    Stack() {
      this.clothBackground()
      Column({ space: 22 }) {
        this.mountedPhoto()
        this.clothTitle()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: TOP_CLEARANCE, left: 40, right: 40 })
      this.cleanBottomEdge(isLightBookColor(this.color))
    }
  }

  /** 带白边 + 四角相角的照片（iOS MountedPhoto），板宽随容器可用高度反推 */
  @Builder
  private mountedPhoto() {
    Stack() {
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
      .padding(this.plateWidthVp() * 0.05)
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
    .width(this.plateWidthVp())
    .height(this.plateWidthVp() * 1.1)
  }

  /** 相角三角形路径：贴照片板的四角（iOS MountedPhoto，corner = 板宽 × 0.15） */
  private cornerTriangle(left: boolean, top: boolean): string {
    const w = this.plateWidthVp();
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
}
