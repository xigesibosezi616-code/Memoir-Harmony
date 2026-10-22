/**
 * 调整构图（10_BUILD_MANUAL.md 3.4，R-BOOK-12）。对应 iOS `Shelf/CoverCropView.swift`。
 *
 * 封面比例（0.73）的取景框里拖动、双指缩放，框住的那一块就是封面：
 * - 照片永远铺满框：缩放不小于「刚好铺满」、拖动不会拖出空白 —— 存下来的封面没有黑边
 * - 双击回到居中、不放大（zoom 1 / offset 0，0.35s 平滑）
 * - 框外压暗 + 白边框，一眼看出封面会是哪一块；框的几何 / 夹取全在
 *   `models/CoverEdit.ets`（纯函数，单测覆盖）
 * - 点「完成」把取景框换算回原图区域（`cropRectFromView`）交给调用方烤盘
 *   （`NotebookCoverStore`），这里不做渲染
 *
 * 挂载方式：调用方（CoverEditorView）页面内全屏浮层条件挂载，不走路由
 * （相机 / 全屏照片同款挂法）。手势：Pan + Pinch 并行（iOS SimultaneousGesture），
 * Pinch 从手势起点记基准缩放（`e.scale` 是相对起点的值）。
 */
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  COVER_ASPECT,
  CoverCropRect,
  baseFillScale,
  clampCropOffsetX,
  clampCropOffsetY,
  clampCropZoom,
  cropRectFromView,
  cropWindowWidth
} from '../../models/CoverEdit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_BOTTOM_VP, STORAGE_KEY_SAFE_AREA_TOP_VP } from '../../services/ImmersiveChrome';

const DOMAIN = 0x0000;
const TAG = 'CoverCropOverlay';

/** 顶栏一行的高（取消 / 标题 / 完成） */
const TOP_BAR_ROW_HEIGHT_VP: number = 44;

/** 双击回中的动画时长（iOS withAnimation(.smooth(duration: 0.35))） */
const RESET_DURATION_MS: number = 350;

@Component
export struct CoverCropOverlay {
  /** 显示用的源（新选照片 = ≤2400 预览解码；已有封面 = 文件全尺寸解码） */
  pixelMap: image.PixelMap | undefined = undefined;
  /** 点「完成」：取景框换算回原图的区域（像素坐标），烤盘由调用方做 */
  onDone: (rect: CoverCropRect) => void = (_rect: CoverCropRect): void => {};
  onCancel: () => void = (): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 源图尺寸（px；aboutToAppear 异步量，量到才画交互层） */
  @State private imgWidth: number = 0;
  @State private imgHeight: number = 0;
  /** 容器尺寸（vp） */
  @State private containerWidthVp: number = 0;
  @State private containerHeightVp: number = 0;
  /** 已提交的缩放 / 偏移（手势结束才落） */
  @State private zoom: number = 1;
  @State private commitX: number = 0;
  @State private commitY: number = 0;
  /** 手势进行中的增量（Pan 位移 / Pinch 相对倍数） */
  @State private dragX: number = 0;
  @State private dragY: number = 0;
  @State private pinchScale: number = 1;

  /** Pinch 起点的已提交缩放（e.scale 相对起点，先记基准） */
  private pinchBaseZoom: number = 1;

  aboutToAppear(): void {
    if (this.pixelMap === undefined) {
      return;
    }
    this.pixelMap.getImageInfo().then((info: image.ImageInfo): void => {
      this.imgWidth = info.size.width;
      this.imgHeight = info.size.height;
    }).catch((err: Object): void => {
      hilog.error(DOMAIN, TAG, 'getImageInfo failed: %{public}s', JSON.stringify(err));
    });
  }

  build() {
    Stack() {
      if (this.pixelMap !== undefined && this.imgWidth > 0 && this.containerWidthVp > 0) {
        // 照片：铺满取景框起（base × zoom ≥ 铺满），偏移实时夹取（不露空白）
        Image(this.pixelMap)
          .objectFit(ImageFit.Fill)
          .width(this.imgWidth * this.baseScaleVp() * this.liveZoom())
          .height(this.imgHeight * this.baseScaleVp() * this.liveZoom())
          .offset({ x: this.liveOffsetX(), y: this.liveOffsetY() })

        // 框外压暗（四块，一眼看出封面会是哪一块）
        this.dimmingRects()

        // 取景框白边（cornerRadius 3，iOS 同值）
        Column()
          .width(this.windowWidthVp())
          .height(this.windowHeightVp())
          .borderRadius(3)
          .border({ width: 1, color: '#D9FFFFFF' })
          .hitTestBehavior(HitTestMode.None)
      }

      // 底部提示（28 底距 + 安全区）
      Column() {
        Text($r('app.string.s_6b19c847d8'))
          .fontSize(13)
          .fontColor('#A6FFFFFF')
          .margin({ bottom: 28 + this.safeAreaBottomVp })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.End)
      .hitTestBehavior(HitTestMode.None)

      this.topBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const w: Length = newArea.width;
      const h: Length = newArea.height;
      if (typeof w === 'number') {
        this.containerWidthVp = w;
      }
      if (typeof h === 'number') {
        this.containerHeightVp = h;
      }
    })
    .gesture(
      // Pan + Pinch 并行（iOS SimultaneousGesture）+ 双击回中
      GestureGroup(GestureMode.Parallel,
        PanGesture({ fingers: 1, distance: 1 })
          .onActionUpdate((event: GestureEvent): void => {
            this.dragX = event.offsetX;
            this.dragY = event.offsetY;
          })
          .onActionEnd((): void => {
            this.settlePan();
          })
          .onActionCancel((): void => {
            this.settlePan();
          }),
        PinchGesture({ fingers: 2 })
          .onActionStart((event: GestureEvent): void => {
            this.pinchBaseZoom = this.zoom;
            this.pinchScale = 1;
          })
          .onActionUpdate((event: GestureEvent): void => {
            this.pinchScale = event.scale;
          })
          .onActionEnd((event: GestureEvent): void => {
            // 缩小之后原来的位置可能露出空白，收回到边界内（iOS 同款）
            this.zoom = clampCropZoom(this.pinchBaseZoom * event.scale);
            this.commitX = clampCropOffsetX(this.commitX, this.zoom, this.baseScaleVp(),
              this.imgWidth, this.windowWidthVp());
            this.commitY = clampCropOffsetY(this.commitY, this.zoom, this.baseScaleVp(),
              this.imgHeight, this.windowHeightVp());
            this.pinchScale = 1;
          })
          .onActionCancel((): void => {
            this.pinchScale = 1;
          }),
        TapGesture({ count: 2 })
          .onAction((): void => {
            // 双击回中、不放大（zoom 1 / offset 0）
            this.getUIContext().animateTo({ duration: RESET_DURATION_MS, curve: Curve.EaseInOut }, (): void => {
              this.zoom = 1;
              this.commitX = 0;
              this.commitY = 0;
            });
          })
      )
    )
  }

  // ---- 顶栏：取消 / 调整构图 / 完成 ----

  @Builder
  private topBar() {
    Stack() {
      Row() {
        Text($r('app.string.s_4d0b4688c7'))
          .fontSize(16)
          .fontColor('#F5F0E6')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick((): void => {
            this.onCancel();
          })
        Blank()
        Text($r('app.string.s_33246f6a5e'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor('#F5F0E6')
          .letterSpacing(this.theme.letterSpacingWide)
        Blank()
        Text($r('app.string.s_33246f6a5e'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.canFinish() ? '#F5F0E6' : '#66F5F0E6')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick((): void => {
            this.finish();
          })
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 4, right: 4 })
      // Stack 里不定位子项居中在整块（状态栏 + 44 行）上，会顶进状态栏
      // 半格（CoverEditorView 同款真机反馈）—— margin 压回状态栏下面
      .margin({ top: this.safeAreaTopVp })
    }
    .width('100%')
    .height(this.safeAreaTopVp + TOP_BAR_ROW_HEIGHT_VP)
    .position({ x: 0, y: 0 })
  }

  /** 框外压暗：窗口四周四块黑 60%（Stack 居中布局，窗口居中于容器） */
  @Builder
  private dimmingRects() {
    Column()
      .width(this.containerWidthVp)
      .height(Math.max(0, this.windowTopVp()))
      .backgroundColor('#99000000')
      .position({ x: 0, y: 0 })
      .hitTestBehavior(HitTestMode.None)
    Column()
      .width(this.containerWidthVp)
      .height(Math.max(0, this.containerHeightVp - this.windowBottomVp()))
      .backgroundColor('#99000000')
      .position({ x: 0, y: this.windowBottomVp() })
      .hitTestBehavior(HitTestMode.None)
    Column()
      .width(Math.max(0, this.windowLeftVp()))
      .height(this.windowHeightVp())
      .backgroundColor('#99000000')
      .position({ x: 0, y: this.windowTopVp() })
      .hitTestBehavior(HitTestMode.None)
    Column()
      .width(Math.max(0, this.containerWidthVp - this.windowRightVp()))
      .height(this.windowHeightVp())
      .backgroundColor('#99000000')
      .position({ x: this.windowRightVp(), y: this.windowTopVp() })
      .hitTestBehavior(HitTestMode.None)
  }

  // ---- 手势收尾 / 完成 ----

  /** Pan 结束：增量夹取后并入已提交值 */
  private settlePan(): void {
    const z = this.liveZoom();
    this.commitX = clampCropOffsetX(this.commitX + this.dragX, z, this.baseScaleVp(),
      this.imgWidth, this.windowWidthVp());
    this.commitY = clampCropOffsetY(this.commitY + this.dragY, z, this.baseScaleVp(),
      this.imgHeight, this.windowHeightVp());
    this.dragX = 0;
    this.dragY = 0;
  }

  private canFinish(): boolean {
    return this.imgWidth > 0 && this.containerWidthVp > 0;
  }

  /** 取景框换算回原图区域，交给调用方烤盘（iOS finish 的换算） */
  private finish(): void {
    if (!this.canFinish()) {
      return;
    }
    const rect = cropRectFromView(this.imgWidth, this.imgHeight,
      this.windowWidthVp(), this.windowHeightVp(), this.zoom, this.commitX, this.commitY);
    this.onDone(rect);
  }

  // ---- 几何（纯函数在 models/CoverEdit.ets） ----

  private windowWidthVp(): number {
    return cropWindowWidth(this.containerWidthVp, this.containerHeightVp);
  }

  private windowHeightVp(): number {
    return this.windowWidthVp() / COVER_ASPECT;
  }

  private windowLeftVp(): number {
    return (this.containerWidthVp - this.windowWidthVp()) / 2;
  }

  private windowTopVp(): number {
    return (this.containerHeightVp - this.windowHeightVp()) / 2;
  }

  private windowRightVp(): number {
    return this.windowLeftVp() + this.windowWidthVp();
  }

  private windowBottomVp(): number {
    return this.windowTopVp() + this.windowHeightVp();
  }

  /** 「刚好铺满取景框」的缩放（图 px → 屏幕 vp） */
  private baseScaleVp(): number {
    return baseFillScale(this.imgWidth, this.imgHeight,
      this.windowWidthVp(), this.windowHeightVp());
  }

  private liveZoom(): number {
    return clampCropZoom(this.zoom * this.pinchScale);
  }

  private liveOffsetX(): number {
    return clampCropOffsetX(this.commitX + this.dragX, this.liveZoom(), this.baseScaleVp(),
      this.imgWidth, this.windowWidthVp());
  }

  private liveOffsetY(): number {
    return clampCropOffsetY(this.commitY + this.dragY, this.liveZoom(), this.baseScaleVp(),
      this.imgHeight, this.windowHeightVp());
  }
}
