/**
 * 拿在手里的书（10_BUILD_MANUAL.md 3.2，R-BOOK-06/07）：有厚度、能同轴转 ——
 * iOS `ShelfBook3D`（`ShelfBookView.swift`）的移植。
 *
 * - 封面 / 书脊是同一个长方体的两个面，各自按 `BookBoxProjection` 的矩阵投影
 *   （绕同一根轴、同一个透视），交界才对得上；背过去的面不画
 * - 转角由外部逐帧驱动（angleRad）：投影矩阵不能直接插值（线性插值两个旋转
 *   矩阵，书会先缩小再变大），插值的永远是角度，每一帧按角度重算投影（iOS
 *   `Animatable.angle` 同款）
 * - 书脊颜色 R-BOOK-07：白框 = 纸色（#DCD3C2）；贴照片 / 纯色 = 布面颜色；
 *   满版照片 = 照片主色 —— 主色提取是 3.6 的卡片，先按 iOS 无缩略图时的兜底
 *   走布面色，3.6 接上后替换
 * - 常驻挂载（调用方保持透明度 0.01）：浮书首次挂载渲染管线要现编译（实测
 *   ~367ms），页面加载时就挂出来，第一次拿起才不卡；不透明度 0.01 仍参与
 *   栅格化，被内容盖住的节点才不栅格化
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { matrix4 } from '@kit.ArkUI';
import { BookColor, CoverLayout, bookColorHex } from '../../models/Notebook';
import {
  BookBoxFace,
  bookBoxFaceMatrix,
  bookBoxFaceVisible
} from '../../models/BookBoxProjection';
import { ShelfBookView } from './BookCoverView';

/** 书的厚度（vp）。iOS `ShelfBook3D.depth` = 14 */
const BOOK_DEPTH: number = 14;

/** 白框的书脊：纸面精装，书脊也是纸（iOS #DCD3C2） */
const FRAMED_SPINE_COLOR: string = '#DCD3C2';

/** 书脊上下各一道烫线的颜色（iOS #D9C08A，透明度 0.45） */
const SPINE_BAND_COLOR: string = '#D9C08A';

/** 封面宽高比（与 ShelfBookView 一致） */
const COVER_ASPECT: number = 0.73;

/** 书口宽度（vp，与 ShelfBookView 一致）：整本书宽 = 封面宽 + 5 */
const PAGE_EDGE: number = 5;

@Component
export struct ShelfBook3DView {
  @Prop name: string = '';
  @Prop entryCount: number = 0;
  @Prop color: BookColor = BookColor.Ivory;
  @Prop coverPhotoFilename: string = '';
  @Prop layout: CoverLayout = CoverLayout.FullBleed;
  /** 整本书的宽（vp，含书口那 5vp），与格子里的书相同 */
  @Prop bookWidthVp: number = 0;
  /** 绕竖轴的转角（弧度）。0 = 正面 */
  @Prop angleRad: number = 0;

  build() {
    // 两个面都锚在容器左上角（TopStart），矩阵里的 faceCenter / boxCenter 与之配套
    Stack({ alignContent: Alignment.TopStart }) {
      if (bookBoxFaceVisible(BookBoxFace.Spine, this.angleRad)) {
        this.spineFace()
      }
      if (bookBoxFaceVisible(BookBoxFace.Cover, this.angleRad)) {
        Stack() {
          ShelfBookView({
            name: this.name,
            entryCount: this.entryCount,
            color: this.color,
            coverPhotoFilename: this.coverPhotoFilename,
            layout: this.layout,
            bookWidthVp: this.bookWidthVp
          })
        }
        .transform3D(this.faceTransform(BookBoxFace.Cover))
      }
    }
    .width(this.bookWidthVp)
    .height(this.coverHeight())
  }

  /** 书脊：封面色压一层圆脊的明暗（中间略亮、两边暗），上下各一道烫线（iOS `BookSpine`） */
  @Builder
  private spineFace() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.spineColor())
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 90,
          colors: [['#61000000', 0], ['#0FFFFFFF', 0.5], ['#47000000', 1]] as [ResourceColor, number][]
        })
      Column() {
        Column()
          .width('100%')
          .height(1)
          .backgroundColor(SPINE_BAND_COLOR)
          .opacity(0.45)
        Blank()
        Column()
          .width('100%')
          .height(1)
          .backgroundColor(SPINE_BAND_COLOR)
          .opacity(0.45)
      }
      .width('100%')
      .height('100%')
      .padding({ top: 16, bottom: 16 })
    }
    .width(BOOK_DEPTH)
    .height(this.coverHeight())
    .transform3D(this.faceTransform(BookBoxFace.Spine))
  }

  private coverWidth(): number {
    return this.bookWidthVp - PAGE_EDGE;
  }

  private coverHeight(): number {
    return this.coverWidth() / COVER_ASPECT;
  }

  /** 面的投影矩阵：这里算出的是行主序行向量 16 数，`matrix4.init` 按列主序读
   * 恰好等于它的转置（列向量约定），直接喂即可 */
  private faceTransform(face: BookBoxFace): matrix4.Matrix4Transit {
    const m = bookBoxFaceMatrix(face, this.angleRad, this.coverWidth(), this.coverHeight(), BOOK_DEPTH);
    hilog.debug(0x0000, 'ShelfBook3D',
      'DBG face=%{public}d angle=%{public}s m=%{public}s',
      face, String(Math.round(this.angleRad * 1000) / 1000),
      JSON.stringify([m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7],
        m[8], m[9], m[10], m[11], m[12], m[13], m[14], m[15]]
        .map((v: number): number => Math.round(v * 10000) / 10000)));
    return matrix4.init([m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7],
      m[8], m[9], m[10], m[11], m[12], m[13], m[14], m[15]]);
  }

  /** 书脊颜色跟着封面走（R-BOOK-07 / iOS `spineColor`） */
  private spineColor(): string {
    if (this.coverPhotoFilename.length === 0) {
      return bookColorHex(this.color);
    }
    if (this.layout === CoverLayout.Framed) {
      return FRAMED_SPINE_COLOR;
    }
    // 满版照片 = 照片主色（3.6）；贴照片 / 主色未接 = 布面颜色（iOS 无缩略图兜底同款）
    return bookColorHex(this.color);
  }
}
