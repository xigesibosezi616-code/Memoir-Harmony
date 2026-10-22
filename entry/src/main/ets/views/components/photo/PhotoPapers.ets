/**
 * 六种相纸（10_BUILD_MANUAL.md 2.6）。对应 iOS `Views/Components/PhotoPaper/` 下的
 * `*Paper.swift` + `PhotoPaperHelpers.swift`（占位图 / 相角三角 / 照片格子）。
 *
 * 尺寸 / 颜色 / 阴影逐项对照 iOS 源码；一处例外是 **格子尺寸只由「宽 × 比例」决定**
 * （R-PHOTO-09，iOS 三次修「照片被撑到极大」的教训）：
 * - 照片格（PhotoPaperGrid）：`aspectRatio(aspect)` 定死格子，内容 `objectFit(Cover)`
 *   满铺 + `clip`，像素再大也只是被裁，撑不大格子
 * - `aspect` = 照片宽高比（宽/高），取自解码后 PixelMap 实测值；比例一致时
 *   Cover = 精确铺满、零裁剪 —— 六种相纸（含宝丽来）都保证照片完整显示
 *   （2026-10-17 产品要求；iOS 宝丽来强制 1:1 + scaledToFill 裁剪属偏差，
 *   见 docs/harmony-spec/09_OPEN_QUESTIONS.md）
 * - 宽度由调用方用百分比给（正文卡片 46% / 预览卡固定 vp），不在滚动容器里测像素
 *
 * 会员降级（05 §3.5）：存会员款而非会员 → 渲染按宝丽来、存值不改写。
 * 判定入口 `effectivePaperStyle`（ContentBlock），本组件层只认传进来的最终样式。
 */
import { image } from '@kit.ImageKit';
import { LengthMetrics } from '@kit.ArkUI';
import { PaperStyle } from '../../../models/ContentBlock';

// ---- 颜色常量（iOS 源码逐项对照；#AARRGGBB） ----

/** 占位图底：#E8DDC9 50% */
const PLACEHOLDER_BG: string = '#80E8DDC9';
/** 占位图图标：#8A7E6C 70% */
const PLACEHOLDER_ICON: string = '#B38A7E6C';
/** 和风贴纸米白底 */
const WASHI_BG: string = '#FAF7F2';
/** 和风贴纸棕边 */
const WASHI_BORDER: string = '#B8AD9C';
/** 相角三角 #C8A87C 70% */
const CORNER_COLOR: string = '#B3C8A87C';
/** 极简卡片细边 */
const MINIMAL_BORDER: string = '#D4C9B8';
/** 胶片帧深棕底 */
const FILM_BG: string = '#2C1F15';
/** 胶片齿孔条底 */
const FILM_STRIP_BG: string = '#3D3428';
/** 胶片齿孔 */
const FILM_HOLE: string = '#FAF7F2';
/** 信纸附照胶带：#E8DDC9 55% */
const TAPE_COLOR: string = '#8CE8DDC9';

/** 无图时的退化比例（4:3，iOS 同款） */
export const FALLBACK_PHOTO_ASPECT: number = 4.0 / 3.0;

/** 由 PixelMap 读宽高比（宽/高）；读不到 / 非法 → 4:3 */
export function aspectOfPixelMap(pixelMap: image.PixelMap | undefined): number {
  if (pixelMap === undefined) {
    return FALLBACK_PHOTO_ASPECT;
  }
  try {
    const size = pixelMap.getImageInfoSync().size;
    if (size.width > 0 && size.height > 0) {
      return size.width / size.height;
    }
  } catch (err) {
    // 读不到尺寸按 4:3 兜底
  }
  return FALLBACK_PHOTO_ASPECT;
}

/** 通用占位格（照片未能加载时；iOS `PhotoPaperPlaceholder`） */
@Component
export struct PhotoPaperPlaceholder {
  build() {
    Stack() {
      SymbolGlyph($r('sys.symbol.picture'))
        .fontSize(28)
        .fontWeight(FontWeight.Lighter)
        .fontColor([PLACEHOLDER_ICON])
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PLACEHOLDER_BG)
  }
}

/**
 * 相纸里的「照片那一格」（R-PHOTO-09 核心）。格子尺寸只由 `aspect`（宽/高）决定：
 * `aspectRatio` 定死外框，照片 `Cover` 满铺裁剪，像素再大也撑不大格子。
 * 对应 iOS `PhotoPaperImageArea`（overlay 防撑大的 ArkUI 等价实现）。
 */
@Component
export struct PhotoPaperGrid {
  pixelMap: image.PixelMap | undefined = undefined;
  /** 没有照片时的示例图（相纸选择器统一展示纸感用；正文不传） */
  sampleRes: Resource | undefined = undefined;
  aspect: number = FALLBACK_PHOTO_ASPECT;
  cornerRadius: number = 0;

  build() {
    Stack() {
      if (this.pixelMap !== undefined) {
        Image(this.pixelMap)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
          .draggable(false)
      } else if (this.sampleRes !== undefined) {
        Image(this.sampleRes)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
          .draggable(false)
      } else {
        PhotoPaperPlaceholder()
      }
    }
    .width('100%')
    .aspectRatio(this.aspect)
    .borderRadius(this.cornerRadius)
    .clip(true)
  }
}

/** 相角装饰三角（iOS `CornerTriangle`）。corner：0=左上 1=右上 2=左下 3=右下 */
@Component
struct CornerTriangle {
  corner: number = 0;
  /** 相角边长（vp）；成员不能叫 size（撞 .size() 属性方法） */
  triSize: number = 14;

  build() {
    Path()
      .width(this.triSize)
      .height(this.triSize)
      .commands(this.commands())
      .fill(CORNER_COLOR)
  }

  private commands(): string {
    const s = this.triSize;
    switch (this.corner) {
      case 0:
        return `M0 0 L${s} 0 L0 ${s} Z`;
      case 1:
        return `M${s} 0 L0 0 L${s} ${s} Z`;
      case 2:
        return `M0 ${s} L${s} ${s} L0 0 Z`;
      default:
        return `M${s} ${s} L0 ${s} L${s} 0 Z`;
    }
  }
}

/** 四角相角（和风贴纸用） */
@Component
struct PaperCorners {
  /** 相角边长（vp）；成员不能叫 size（撞 .size() 属性方法） */
  cornerSize: number = 14;

  build() {
    Column() {
      Row() {
        CornerTriangle({ corner: 0, triSize: this.cornerSize })
        Blank()
        CornerTriangle({ corner: 1, triSize: this.cornerSize })
      }
      .width('100%')
      Blank()
      Row() {
        CornerTriangle({ corner: 2, triSize: this.cornerSize })
        Blank()
        CornerTriangle({ corner: 3, triSize: this.cornerSize })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }
}

/** 1. 原图：无相框无装饰，仅 4vp 圆角微裁 */
@Component
struct OriginalPaper {
  pixelMap: image.PixelMap | undefined = undefined;
  photoAspect: number = FALLBACK_PHOTO_ASPECT;

  build() {
    PhotoPaperGrid({
      pixelMap: this.pixelMap,
      aspect: this.photoAspect,
      cornerRadius: 4
    })
  }
}

/** 2. 宝丽来：白色厚边框 + 底部 28vp 留白，照片区按片比例（不裁剪，见文件头） */
@Component
struct PolaroidPaper {
  pixelMap: image.PixelMap | undefined = undefined;
  photoAspect: number = FALLBACK_PHOTO_ASPECT;

  build() {
    Column({ space: 0 }) {
      PhotoPaperGrid({ pixelMap: this.pixelMap, aspect: this.photoAspect })
      Column()
        .width('100%')
        .height(28)
        .backgroundColor(Color.White)
    }
    .width('100%')
    .padding(8)
    .backgroundColor(Color.White)
    .shadow({ radius: 3, color: '#1F000000', offsetY: 2 })
  }
}

/** 3. 和风贴纸：米白底 + 棕色细边 + 四角相角装饰 */
@Component
struct WashiPaper {
  pixelMap: image.PixelMap | undefined = undefined;
  photoAspect: number = FALLBACK_PHOTO_ASPECT;

  build() {
    Stack() {
      Column() {
        PhotoPaperGrid({ pixelMap: this.pixelMap, aspect: this.photoAspect })
      }
      .width('100%')
      .padding(6)
      .backgroundColor(WASHI_BG)
      .border({ width: 0.8, color: WASHI_BORDER })
      PaperCorners({ cornerSize: 14 })
    }
    .width('100%')
    .shadow({ radius: 3, color: '#14000000', offsetY: 2 })
  }
}

/** 4. 极简卡片：8vp 圆角 + 0.5vp 细边，无额外修饰 */
@Component
struct MinimalCardPaper {
  pixelMap: image.PixelMap | undefined = undefined;
  photoAspect: number = FALLBACK_PHOTO_ASPECT;

  build() {
    Column() {
      PhotoPaperGrid({ pixelMap: this.pixelMap, aspect: this.photoAspect, cornerRadius: 8 })
    }
    .width('100%')
    .border({ width: 0.5, color: MINIMAL_BORDER, radius: 8 })
    .shadow({ radius: 2, color: '#0F000000', offsetY: 1 })
  }
}

/** 5. 胶片帧：两侧胶卷齿孔 + 深棕底色 */
@Component
struct FilmFramePaper {
  pixelMap: image.PixelMap | undefined = undefined;
  photoAspect: number = FALLBACK_PHOTO_ASPECT;

  build() {
    Flex({ direction: FlexDirection.Row, space: { main: LengthMetrics.vp(4) }, alignItems: ItemAlign.Stretch }) {
      FilmPerforationStrip()
      PhotoPaperGrid({ pixelMap: this.pixelMap, aspect: this.photoAspect })
      FilmPerforationStrip()
    }
    .width('100%')
    .padding(6)
    .backgroundColor(FILM_BG)
    .shadow({ radius: 4, color: '#2E000000', offsetY: 2 })
  }
}

/** 胶卷齿孔条（8 孔，占满相纸全高） */
@Component
struct FilmPerforationStrip {
  build() {
    Column({ space: 4 }) {
      ForEach([0, 1, 2, 3, 4, 5, 6, 7], (_: number) => {
        Row()
          .width(6)
          .height(4)
          .borderRadius(1)
          .backgroundColor(FILM_HOLE)
      }, (_: number) => '')
    }
    .width(14)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(FILM_STRIP_BG)
  }
}

/** 6. 信纸附照：薄白边 + 较深阴影 + 左上角「胶带」 */
@Component
struct LetterAttachedPaper {
  pixelMap: image.PixelMap | undefined = undefined;
  photoAspect: number = FALLBACK_PHOTO_ASPECT;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        PhotoPaperGrid({ pixelMap: this.pixelMap, aspect: this.photoAspect })
      }
      .width('100%')
      .padding(4)
      .backgroundColor(Color.White)
      .shadow({ radius: 6, color: '#33000000', offsetX: 1, offsetY: 3 })
      // 左上角模拟胶带（iOS：50×16，-20°，偏移 -8/-4）
      Column()
        .width(50)
        .height(16)
        .backgroundColor(TAPE_COLOR)
        .rotate({ angle: -20 })
        .offset({ x: -8, y: -4 })
        .shadow({ radius: 1, color: '#14000000', offsetY: 1 })
    }
    .width('100%')
  }
}

/**
 * 相纸分发器：按传入的**最终样式**（会员降级由调用方先算好，见 `effectivePaperStyle`）
 * 分发到六种相纸。六种都按片原始比例（完整显示，见文件头）。
 */
@Component
export struct PhotoPaperCard {
  style: PaperStyle = PaperStyle.Polaroid;
  pixelMap: image.PixelMap | undefined = undefined;
  photoAspect: number = FALLBACK_PHOTO_ASPECT;

  build() {
    if (this.style === PaperStyle.Original) {
      OriginalPaper({ pixelMap: this.pixelMap, photoAspect: this.photoAspect })
    } else if (this.style === PaperStyle.Polaroid) {
      PolaroidPaper({ pixelMap: this.pixelMap, photoAspect: this.photoAspect })
    } else if (this.style === PaperStyle.WashiSticker) {
      WashiPaper({ pixelMap: this.pixelMap, photoAspect: this.photoAspect })
    } else if (this.style === PaperStyle.MinimalCard) {
      MinimalCardPaper({ pixelMap: this.pixelMap, photoAspect: this.photoAspect })
    } else if (this.style === PaperStyle.FilmFrame) {
      FilmFramePaper({ pixelMap: this.pixelMap, photoAspect: this.photoAspect })
    } else {
      LetterAttachedPaper({ pixelMap: this.pixelMap, photoAspect: this.photoAspect })
    }
  }
}

/**
 * 相纸选择器里的预览卡（默认 120×160 外框，iOS `PaperPreviewCard`）。
 * 与正文渲染的区别：预览横排视觉一致 → 外框固定、照片按各样式固定尺寸 Cover 裁剪。
 * cardWidth 可等比缩放整卡（相机横条传小号 96，书写页 sheet 用默认 120）。
 */
@Component
export struct PaperPreviewCard {
  style: PaperStyle = PaperStyle.Polaroid;
  pixelMap: image.PixelMap | undefined = undefined;
  /** 无照片时的示例图（选择器用） */
  sampleRes: Resource | undefined = undefined;
  cardWidth: number = 120;

  /** 内部尺寸按 cardWidth/120 等比缩放（边框、阴影等描边类不缩放） */
  private scaleDim(v: number): number {
    return v * this.cardWidth / 120;
  }

  build() {
    Stack() {
      if (this.style === PaperStyle.Original) {
        // 原图：108×130，仅 4vp 圆角
        PhotoPaperGrid({ pixelMap: this.pixelMap, sampleRes: this.sampleRes, aspect: 108 / 130, cornerRadius: this.scaleDim(4) })
          .width(this.scaleDim(108))
      } else if (this.style === PaperStyle.Polaroid) {
        // 宝丽来：104×104 + 底部 32 白边 + 四周 8 白边
        Column({ space: 0 }) {
          PhotoPaperGrid({ pixelMap: this.pixelMap, sampleRes: this.sampleRes, aspect: 1.0 })
            .width(this.scaleDim(104))
          Column().width(this.scaleDim(104)).height(this.scaleDim(32)).backgroundColor(Color.White)
        }
        .padding(this.scaleDim(8))
        .backgroundColor(Color.White)
        .shadow({ radius: 3, color: '#1F000000', offsetY: 2 })
      } else if (this.style === PaperStyle.WashiSticker) {
        // 和风贴纸：照片 108×120 + 棕边 + 相角（12）
        Stack() {
          PhotoPaperGrid({ pixelMap: this.pixelMap, sampleRes: this.sampleRes, aspect: 108 / 120 })
            .width(this.scaleDim(108))
            .padding(this.scaleDim(6))
            .backgroundColor(WASHI_BG)
            .border({ width: 0.8, color: WASHI_BORDER })
          PaperCorners({ cornerSize: this.scaleDim(12) })
        }
        .width(this.scaleDim(120))
        .height(this.scaleDim(132))
        .shadow({ radius: 3, color: '#14000000', offsetY: 2 })
      } else if (this.style === PaperStyle.MinimalCard) {
        // 极简卡片：108×130 + 8vp 圆角细边
        PhotoPaperGrid({ pixelMap: this.pixelMap, sampleRes: this.sampleRes, aspect: 108 / 130, cornerRadius: this.scaleDim(8) })
          .width(this.scaleDim(108))
          .border({ width: 0.5, color: MINIMAL_BORDER, radius: this.scaleDim(8) })
          .shadow({ radius: 2, color: '#0F000000', offsetY: 1 })
      } else if (this.style === PaperStyle.FilmFrame) {
        // 胶片帧：齿孔条（7 孔）+ 照片 76×110
        Flex({ direction: FlexDirection.Row, space: { main: LengthMetrics.vp(this.scaleDim(4)) }, alignItems: ItemAlign.Stretch }) {
          PreviewPerforationStrip({ stripWidth: this.scaleDim(12) })
          PhotoPaperGrid({ pixelMap: this.pixelMap, sampleRes: this.sampleRes, aspect: 76 / 110 })
            .width(this.scaleDim(76))
          PreviewPerforationStrip({ stripWidth: this.scaleDim(12) })
        }
        .height(this.scaleDim(122))
        .padding(this.scaleDim(6))
        .backgroundColor(FILM_BG)
        .shadow({ radius: 4, color: '#2E000000', offsetY: 2 })
      } else {
        // 信纸附照：照片 104×128 + 胶带 42×14
        Stack({ alignContent: Alignment.TopStart }) {
          PhotoPaperGrid({ pixelMap: this.pixelMap, sampleRes: this.sampleRes, aspect: 104 / 128 })
            .width(this.scaleDim(104))
            .padding(this.scaleDim(4))
            .backgroundColor(Color.White)
            .shadow({ radius: 6, color: '#33000000', offsetX: 1, offsetY: 3 })
          Column()
            .width(this.scaleDim(42))
            .height(this.scaleDim(14))
            .backgroundColor(TAPE_COLOR)
            .rotate({ angle: -20 })
            .offset({ x: this.scaleDim(-6), y: this.scaleDim(-3) })
            .shadow({ radius: 1, color: '#14000000', offsetY: 1 })
        }
      }
    }
    .width(this.scaleDim(120))
    .height(this.scaleDim(160))
    .alignContent(Alignment.Center)
  }
}

/** 预览卡用的齿孔条（7 孔，默认 12vp 宽；stripWidth 随整卡等比缩放） */
@Component
struct PreviewPerforationStrip {
  stripWidth: number = 12;

  build() {
    Column({ space: this.stripWidth / 3 }) {
      ForEach([0, 1, 2, 3, 4, 5, 6], (_: number) => {
        Row()
          .width(this.stripWidth * 5 / 12)
          .height(this.stripWidth / 4)
          .borderRadius(this.stripWidth / 12)
          .backgroundColor(FILM_HOLE)
      }, (_: number) => '')
    }
    .width(this.stripWidth)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(FILM_STRIP_BG)
  }
}
