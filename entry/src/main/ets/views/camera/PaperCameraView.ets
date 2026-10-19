/**
 * 尺素相机（10_BUILD_MANUAL.md 2.9）。对应 iOS `Views/Camera/PaperCameraView.swift`。
 *
 * **设计意图**（iOS 注释同款）：不是做一台拍立得（没人愿意等虚拟显影），
 * 而是借拍立得的「手感」——按下快门、一张相纸落到手里、顺手想写点什么。
 * 成像原图直出，零等待。
 *
 * - 取景框（灵动岛机型）：黑色机身从挖孔里长出来——机身顶边只比挖孔顶高 2、
 *   画面顶边越过挖孔底再留 9（iOS `PaperCameraView.swift` 同款贴合逻辑），
 *   四边黑边同厚且不薄于 31（iOS 新版参考：厚边相机机身，四边均匀）。
 *   挖孔矩形取 `display.getCutoutInfo` 精确值（faqs-arkui-274；挖孔不属于避让区，
 *   按状态栏高度估会把机身撑得过大）；进场时机身从包住挖孔的黑药丸弹开
 *   （spring 0.45/0.84 同款），并按官方范式隐藏状态栏（退场还原）。
 *   无挖孔机型（平板等）走普通布局：机身在状态栏下、四边等厚黑边。
 *   预览 XComponent 按 Profile 宽高比定尺寸防拉伸（faqs-arkui-700），
 *   外层裁成方形 = 所见即裁切范围
 * - 排版（iOS 新版参考 + 华为相机式变焦条）：品牌「尺素」居页面中部；
 *   变焦条是磨砂胶囊（系统磨砂材质 + 黑色透明罩），档位华为式自适应
 *   （超广角 0.5× / 1× / 3.5× / 5× / 10×，设备范围够才给），点档位芯片
 *   立即点亮、画面走官方 setSmoothZoom 平滑过渡（贝塞尔曲线，不支持时退
 *   setZoomRatio），整条横向拖动自由变焦（最近档高亮实时倍率，跨档轻震）。
 *   连续变焦走官方手势模式（Scan Kit 官方示例同款）：范围查一次缓存、
 *   每次手势更新直接 setZoom（HAL 1-2 帧生效自动合并），0.1 步进才刷标签；
 *   取景框内双指捏合同款自由变焦；
 *   快门行贴在闪光 / 相纸工具条上方；工具条居中收在底部（选中态近黑胶囊
 *   反白，平时裸灰字，无图标）
 * - 拍完：相纸从取景框顶「出纸口」打印出来（打印机吐纸 460ms 快出缓停），
 *   快照先行——快门瞬间抓取景帧先上纸（surface 快照 ~50ms 出纸），
 *   抓不到退白纸先行；显影蒙层在吐纸途中渐褪（打印机边走边印——
 *   2026-10-19 用户反馈「出纸后照片才跳出来」的修法：相纸带着影像出），
 *   真 50MP 解码完成后对快照交叉淡入（同景同框，观感是显影变清晰）；
 *   落定 ±2.5° 随机微倾；
 *   预览 surface **不销毁**（销毁后重建 surfaceId 变了预览接不回），相纸盖在上面
 * - 闪光三选托盘（自动/闪光开/闪光关，有闪光单元才显示）/ 前后摄切换；
 *   震动走 vibrator 预设效果（haptic.effect.soft / hard）
 * - 相纸在相机里就选好（初值取偏好 `defaultPaperStyle`，确认时回写），
 *   拍完点「写下这一刻」回调产物；配对 / 存相册由页面接手
 * - 权限：开页申请相机（+ 麦克风，动态照片要带声）；相机被拒渲染
 *   「需要相机权限 + 去设置」引导态（跳系统应用信息页，录音面板同款）
 */
import { image } from '@kit.ImageKit';
import { curves, display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';
import { abilityAccessCtrl, bundleManager, common, Want } from '@kit.AbilityKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import {
  STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_CUTOUT_LEFT_VP,
  STORAGE_KEY_CUTOUT_TOP_VP,
  STORAGE_KEY_CUTOUT_WIDTH_VP,
  STORAGE_KEY_CUTOUT_HEIGHT_VP,
  IslandBodyGeometry,
  systemBarContentColorFor
} from '../../services/ImmersiveChrome';
import { PaperStyle, paperStyleFromRaw } from '../../models/ContentBlock';
import {
  CameraSession,
  CameraShot,
  FlashSetting,
  nearestZoomPreset,
  formatZoomLabel,
  zoomPresetsForRange
} from '../../services/CameraSession';
import { decodeCenterSquare } from '../../services/CameraPhotoFiles';
import { AppPrefs, PREF_KEY_DEFAULT_PAPER_STYLE } from '../../services/AppPrefs';
import { PaperPreviewCard } from '../components/photo/PhotoPapers';

const DOMAIN = 0x0000;
const TAG = 'PaperCameraView';

/** 快门印泥红（iOS shutterRed 同款 0.76/0.24/0.19，呼应印章体系） */
const SHUTTER_RED: string = '#C23D30';
/** 取景框两侧留白（iOS 新版参考 16） */
const FRAME_MARGIN: number = 16;
/** 取景框黑边厚度（机身左右 / 底部；顶部由挖孔几何决定） */
const VIEWFINDER_BEZEL: number = 14;
/** 灵动岛机身黑边下限：四边同厚且不薄于这条（iOS 新版参考 ~31） */
const ISLAND_BEZEL_MIN: number = 31;
/** 变焦条磨砂胶囊：黑色透明罩 + 系统磨砂材质（华为相机式） */
const ZOOM_BAR_TINT: string = '#59000000';
/** 变焦条未选中档位文案（磨砂底上的暖白） */
const ZOOM_BAR_TEXT: string = '#E8E1D7';
/** 拖动自由变焦：横向拖 80vp 倍率翻一倍（乘法映射，系统相机同款跟手感） */
const ZOOM_DRAG_VP_PER_OCTAVE: number = 80;
/** 变焦 UI 上限：档位最大 10×，拖动 / 捏合同沿（超出档位的纯数码段不做） */
const ZOOM_UI_MAX_RATIO: number = 10;
/** 平滑变焦走数轮询周期（ms）：真值轮询驱动悬浮数字泡，与画面帧率同量级 */
const SMOOTH_ZOOM_POLL_MS: number = 32;
/** 相纸落到手里的轻微倾斜幅度（±°，iOS ±2.5） */
const PAPER_TILT_DEGREES: number = 2.5;
/** 机身从药丸展开的弹簧（iOS spring(response 0.45, dampingFraction 0.84) 同款） */
const EXPAND_CURVE = curves.springMotion(0.45, 0.84);
/** 相机内可选的相纸顺序（与相纸选择器同序） */
const CAMERA_PAPER_STYLES: PaperStyle[] = [
  PaperStyle.Original,
  PaperStyle.Polaroid,
  PaperStyle.WashiSticker,
  PaperStyle.MinimalCard,
  PaperStyle.FilmFrame,
  PaperStyle.LetterAttached
];
/** 按压 / 落纸弹簧曲线 */
const PRESS_CURVE = curves.springCurve(0, 1, 420, 28);
const PAPER_CURVE = curves.springCurve(0, 1, 340, 26);
/** 出纸曲线：快出缓停（打印机吐纸的利落感） */
const PRINT_EJECT_CURVE = curves.cubicBezierCurve(0.22, 0.85, 0.24, 1);
/** 吐纸时长：相纸从取景框顶的「出纸口」滑入的到位时间 */
const PRINT_EJECT_MS: number = 460;
/** 显影时长：出纸后白蒙层褪去、影像浮现（拍立得显影感） */
const PRINT_DEVELOP_MS: number = 560;

/** 吐纸启动后多久开始显影（打印机边走边印：蒙层在吐纸途中渐褪） */
const PRINT_DEVELOP_DELAY_MS: number = 120;

/** 真片交叉淡入时长（盖过快照垫层，观感是显影变清晰） */
const PHOTO_SWAP_MS: number = 320;

/** 换位交叉淡切：相纸抽屉与拍摄控件组互换插槽时的进出场转场 */
function controlSwapTransition(): TransitionEffect {
  return TransitionEffect.translate({ y: 18 })
    .animation({ curve: PAPER_CURVE })
    .combine(TransitionEffect.OPACITY
      .animation({ curve: PAPER_CURVE }));
}

/** 闪光托盘与单 chip 互换：轻缩放淡切（同一根弹簧曲线，底部小控件不做大位移） */
function flashTrayTransition(): TransitionEffect {
  return TransitionEffect.OPACITY
    .animation({ curve: PAPER_CURVE })
    .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 })
      .animation({ curve: PAPER_CURVE }));
}

@Component
export struct PaperCameraView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @StorageProp(STORAGE_KEY_CUTOUT_LEFT_VP) cutoutLeftVp: number = 0;
  @StorageProp(STORAGE_KEY_CUTOUT_TOP_VP) cutoutTopVp: number = 0;
  @StorageProp(STORAGE_KEY_CUTOUT_WIDTH_VP) cutoutWidthVp: number = 0;
  @StorageProp(STORAGE_KEY_CUTOUT_HEIGHT_VP) cutoutHeightVp: number = 0;
  /** 拍完点「写下这一刻」：原始产物 + 裁过的方图（显示用）+ 选中的相纸样式 */
  onCapture: (shot: CameraShot, squarePixelMap: image.PixelMap, style: PaperStyle) => void =
    (_shot: CameraShot, _squarePixelMap: image.PixelMap, _style: PaperStyle): void => {};
  /** 关闭（✕ / 权限引导取消都走它；页面收浮层） */
  onCancel: () => void = (): void => {};

  @State private permissionDenied: boolean = false;
  @State private sessionFailed: boolean = false;
  /** 会话已起（预览可见、快门可按） */
  @State private authorized: boolean = false;
  /** 相纸已出（审阅态；白纸先行，影像解码到位后再显影上去） */
  @State private paperEjected: boolean = false;
  /** 拍到的方图；解码完成后落到已出的相纸上 */
  @State private shotPixelMap: image.PixelMap | undefined = undefined;
  /** 快照先行：快门瞬间抓的取景帧（真片解码完成后换掉并释放） */
  @State private previewFramePixelMap: image.PixelMap | undefined = undefined;
  /** 真片显影：false=快照在显，true=真片交叉淡入盖过快照 */
  @State private realPhotoRevealed: boolean = false;
  /** 出纸显影中：白蒙层盖着影像，吐纸到位后褪去（拍立得显影） */
  @State private printDeveloping: boolean = false;
  @State private capturing: boolean = false;
  /** 快门白闪 */
  @State private flashOn: boolean = false;
  @State private flashSetting: FlashSetting = FlashSetting.Auto;
  /** 当前镜头有无闪光单元（前摄通常没有；决定显不显示闪光键） */
  @State private flashAvailable: boolean = false;
  @State private selectedPaper: PaperStyle = PaperStyle.Polaroid;
  @State private showPaperStrip: boolean = false;
  /** 闪光三选托盘展开中（与相纸抽屉互斥，一次只开一个） */
  @State private flashTrayOpen: boolean = false;
  /** 当前倍率（非渲染态：全精度记账，UI 只看下面两个渲染态，避免逐 0.1 重渲染整条） */
  private zoomRatio: number = 1;
  /** 落位档（±0.05 内算落位；高亮对应档位圆钮）；自由倍率（如 2.4×）为 -1，由数字泡显示 */
  @State private zoomSettledPreset: number = 1;
  /** 变焦数字泡文案（拖动 / 捏合 / 平滑变焦中的实时倍率；空串 = 隐藏） */
  @State private zoomBubbleLabel: string = '';
  /**
   * 变焦档位缓存：会话起来 / 翻转后刷一次（范围查询离热路径——
   * 拖动每个手势更新都重渲染，逐次查 `getZoomRatioRange` 会卡 UI）
   */
  @State private zoomPresetList: number[] = [1];
  /** 变焦范围缓存 [min, max]（会话起来 / 翻转后刷；拖动 / 捏合夹取用） */
  private zoomMinCached: number = 1;
  private zoomMaxCached: number = 5;
  /** 手势起始倍率（拖条 / 捏合记账，官方示例 baseZoom 同款） */
  private gestureStartZoomRatio: number = 1;
  /** 连续变焦精确终值（会话用全精度，标签只显示 0.1 步进；收尾精确下发） */
  private continuousZoomTarget: number = 1;
  /** 最近一次跨过的预设档（跨档轻震用） */
  private lastNearestPreset: number = 1;
  /** 平滑变焦走数轮询定时器（-1 = 无）；新交互 / 组件卸载时收口 */
  private smoothZoomPollTimer: number = -1;
  /** 平滑变焦走数目标倍率（-1 = 无进行中的走数；与轮询定时器配套） */
  private smoothZoomTargetRatio: number = -1;
  /** 相纸落下时的轻微倾斜（每次拍照随机，避免每次一模一样） */
  @State private paperTilt: number = 0;
  /** 取景画面宽高比（Profile 实测值；XComponent 按它定高防拉伸） */
  @State private previewAspect: number = 4 / 3;
  /** 机身展开：false = 收成挖孔大小的黑药丸，true = 满幅取景框（进场动画） */
  @State private expanded: boolean = false;

  private capturedShot: CameraShot | undefined = undefined;
  /** 白纸先行留下的解码任务（「写下这一刻」抢在解码完成前点下时等它） */
  private decodePromise: Promise<image.PixelMap | undefined> | undefined = undefined;
  /** 「写下这一刻」在真片路上点下时的等待队列（真片到了 / 收纸时解锁） */
  private shotWaiters: Array<(value: void) => void> = [];
  /** 真片交叉淡入后收走快照垫层的延时（淡完再释放，防渲染中的 pixelmap 被回收） */
  private swapReleaseTimer: number = -1;
  private session: CameraSession = new CameraSession();
  private surfaceController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private surfaceReady: boolean = false;
  private permissionReady: boolean = false;
  private openingSession: boolean = false;
  /** 相纸选中后延时收条（让高亮先被看见） */
  private stripCloseTimer: number = -1;
  /** 闪光选中后延时收托盘（让高亮先被看见） */
  private flashTrayCloseTimer: number = -1;
  private screenWidthVp: number = 360;

  aboutToAppear(): void {
    // 默认相纸取偏好（上次选的），解析不了退宝丽来
    const raw = AppPrefs.getString(PREF_KEY_DEFAULT_PAPER_STYLE, PaperStyle.Polaroid);
    const parsed = paperStyleFromRaw(raw);
    this.selectedPaper = parsed !== undefined ? parsed : PaperStyle.Polaroid;
    try {
      this.screenWidthVp = this.getUIContext().px2vp(display.getDefaultDisplaySync().width);
    } catch (err) {
      // 取不到屏宽（极端场景）：按 360 兜底
    }
    // 灵动岛机型：藏状态栏（官方范式）+ 机身从挖孔里的黑药丸弹开，再并行起会话
    this.setSystemBarsForCamera(true);
    if (this.hasIsland()) {
      this.getUIContext().animateTo({ curve: EXPAND_CURVE }, (): void => {
        this.expanded = true;
      });
    } else {
      this.expanded = true;
    }
    this.requestCameraPermissions();
  }

  aboutToDisappear(): void {
    this.cancelSmoothZoomCount();
    clearTimeout(this.swapReleaseTimer);
    this.swapReleaseTimer = -1;
    this.releasePreviewFrame();
    this.clearStripTimer();
    this.clearFlashTrayTimer();
    this.setSystemBarsForCamera(false);
    this.session.close();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 主题底（延伸到状态栏 / 手势条底下）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme.background)
        .expandSafeArea([SafeAreaType.SYSTEM])

      Column() {
        this.viewfinder()

        // 品牌字样：页面中部（取景框与变焦行之间的留白中央，iOS 新版参考）
        Column({ space: 3 }) {
          Text($r('app.string.s_87d04c6c61'))
            .fontSize(18)
            .fontWeight(this.theme.titleFont.weight)
            .fontFamily(this.theme.titleFont.family)
            .fontColor(this.theme.textPrimary)
            .letterSpacing(this.theme.letterSpacingWide)
            // 字距尾空让「尺素」视觉重心左偏：右挪半个字距，与下方小字对齐
            .offset({ x: this.theme.letterSpacingWide / 2 })
          Text(this.paperEjected ?
            $r('app.string.s_95a69206f7') : $r('app.string.s_e5e80726bd'))
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.textTertiary)
        }
        .margin({ top: 66 })
        .translate({ y: this.expanded ? 0 : 40 })
        .opacity(this.expanded ? 1 : 0)

        // 相纸抽屉打开 = 换位不遮挡：抽屉占用变焦条 + 快门行的原位
        // （互斥渲染，任何屏宽都不会盖住快门——2026-10-19 产品反馈「弹层过大
        // 遮挡拍摄键」的结构性修法；选完 220ms 自动收条回到拍摄位）
        if (this.showPaperStrip) {
          Column() {
            this.paperStrip()
          }
          .translate({ y: this.expanded ? 0 : 40 })
          .opacity(this.expanded ? 1 : 0)
          .transition(controlSwapTransition())
        } else if (!this.paperEjected) {
          Column() {
            this.zoomRow()
            this.captureControls()
          }
          .translate({ y: this.expanded ? 0 : 40 })
          .opacity(this.expanded ? 1 : 0)
          .transition(controlSwapTransition())
        } else {
          Column() {
            this.reviewControls()
          }
          .translate({ y: this.expanded ? 0 : 40 })
          .opacity(this.expanded ? 1 : 0)
          .transition(controlSwapTransition())
        }

        Blank()

        Column() {
          this.bottomBar()
        }
        .margin({ bottom: 16 })
        .translate({ y: this.expanded ? 0 : 60 })
        .opacity(this.expanded ? 1 : 0)
      }
      .width('100%')
      .height('100%')
      .padding({
        // 灵动岛机型机身自己贴挖孔（顶到屏幕顶起算）；普通机型照旧让开状态栏
        top: this.hasIsland() ? 0 : this.safeAreaTopVp + 12,
        left: FRAME_MARGIN,
        right: FRAME_MARGIN,
        bottom: this.safeAreaBottomVp
      })

      // 相纸抽屉已改内流式换位（见上 showPaperStrip 分支），不再浮层覆盖

      // 快门白闪（不挡触摸）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.White)
        .opacity(this.flashOn ? 0.85 : 0)
        .expandSafeArea([SafeAreaType.SYSTEM])
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    // 浮层转场（页面内条件浮层同款：淡入 + 轻微放大进场）
    .transition(
      TransitionEffect.OPACITY
        .animation({ curve: Curve.EaseOut, duration: 250 })
        .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 })
          .animation({ curve: Curve.EaseOut, duration: 250 }))
    )
  }

  // ---- 取景框 ----

  /** 灵动岛机型（有挖孔矩形）？ */
  private hasIsland(): boolean {
    return this.cutoutHeightVp > 0;
  }

  /** 挖孔贴合几何（缓存当帧；StorageProp 变了自然重算） */
  private islandGeometry(): IslandBodyGeometry {
    return IslandBodyGeometry.compute(this.screenWidthVp,
      this.cutoutLeftVp, this.cutoutTopVp, this.cutoutWidthVp, this.cutoutHeightVp);
  }

  /** 灵动岛机身统一黑边厚：四边同厚，取顶黑边与 31 的较大值（iOS 新版参考：厚边机身） */
  private islandBezel(): number {
    return Math.max(this.islandGeometry().topBezel, ISLAND_BEZEL_MIN);
  }

  /** 方形画面边长（悬浮机身：屏宽 - 两侧留白 - 两侧黑边；灵动岛机型黑边 = 顶黑边） */
  private frameSide(): number {
    const bezel: number = this.hasIsland() ? this.islandBezel() : VIEWFINDER_BEZEL;
    return this.screenWidthVp - FRAME_MARGIN * 2 - bezel * 2;
  }

  @Builder
  private viewfinder() {
    if (this.hasIsland()) {
      this.islandViewfinder()
    } else {
      this.plainViewfinder()
    }
  }

  /** 普通机型：等厚黑边机身，居中悬浮 */
  @Builder
  private plainViewfinder() {
    Stack() {
      Stack() {
        this.viewfinderContent()
      }
      .width(this.frameSide())
      .height(this.frameSide())
      .clip(true)
      .backgroundColor('#0D0D0D')
    }
    .padding(VIEWFINDER_BEZEL)
    .backgroundColor(Color.Black)
    .borderRadius(VIEWFINDER_BEZEL + 16)
    .clip(true)
    .shadow({ radius: 18, color: '#2E000000', offsetY: 8 })
  }

  /** 灵动岛机型：机身贴住挖孔，四边黑边同厚（= 顶黑边）；收起 = 包住挖孔的黑药丸 */
  @Builder
  private islandViewfinder() {
    // 外层固定占位（高 = 屏幕顶 → 机身底）：动画期间下方元素不跳动（iOS 同款）
    Column() {
      Stack({ alignContent: Alignment.Top }) {
        Stack() {
          this.viewfinderContent()
        }
        .width(this.frameSide())
        .height(this.frameSide())
        .margin({ top: this.islandBezel() })
        .clip(true)
        .backgroundColor('#0D0D0D')
        .opacity(this.expanded ? 1 : 0)
      }
      .width(this.expanded ?
        this.frameSide() + this.islandBezel() * 2 : this.islandGeometry().pillWidth)
      .height(this.expanded ?
        this.islandBezel() * 2 + this.frameSide() : this.islandGeometry().pillHeight)
      .margin({
        top: this.expanded ? this.islandGeometry().bodyTop : this.islandGeometry().pillTop,
        left: this.expanded ? 0 : this.islandGeometry().pillLeft - FRAME_MARGIN
      })
      .backgroundColor(Color.Black)
      .borderRadius(this.expanded ?
        this.islandBezel() + 16 : this.islandGeometry().pillHeight / 2)
      .clip(true)
      .shadow({ radius: 18, color: '#2E000000', offsetY: 8 })
    }
    .width('100%')
    .height(this.islandGeometry().bodyTop +
      this.islandBezel() * 2 + this.frameSide())
  }

  /** 取景画面：预览 surface + 占位 + 相纸 + 变焦条，方形裁切 */
  @Builder
  private viewfinderContent() {
    Stack() {
      // 预览常驻（审阅态被相纸盖住；surface 不销毁，重拍即回）
      XComponent({ type: XComponentType.SURFACE, controller: this.surfaceController })
        .onLoad((): void => {
          this.onSurfaceReady();
        })
        .width(this.frameSide())
        .height(this.frameSide() / this.previewAspect)
        .visibility(this.authorized && !this.paperEjected ?
          Visibility.Visible : Visibility.Hidden)

      // 未授权 / 会话失败：引导态盖在预览位上
      if (!this.authorized) {
        this.viewfinderPlaceholder()
      }

      // 拍完：相纸落下（白纸先行，影像解码到位后显影上来）
      if (this.paperEjected) {
        this.paperPrint()
      }
    }
    .width(this.frameSide())
    .height(this.frameSide())
    .clip(true)
    .backgroundColor('#0D0D0D')
    // 取景框内双指捏合自由变焦（官方 Scan Kit 示例同款：scale × 起始倍率，逐次下发）
    .gesture(
      PinchGesture({ fingers: 2 })
        .onActionStart((): void => {
          if (!this.canZoomFreely()) {
            return;
          }
          this.gestureStartZoomRatio = this.zoomRatio;
        })
        .onActionUpdate((event: GestureEvent): void => {
          if (!this.canZoomFreely()) {
            return;
          }
          this.applyContinuousZoom(this.gestureStartZoomRatio * event.scale);
        })
        .onActionEnd((): void => {
          if (!this.canZoomFreely()) {
            return;
          }
          this.endContinuousZoom();
        })
        .onActionCancel((): void => {
          if (!this.canZoomFreely()) {
            return;
          }
          this.endContinuousZoom();
        })
    )
  }

  /** 自由变焦可用：会话在跑且不在相纸审阅态 */
  private canZoomFreely(): boolean {
    return this.authorized && !this.paperEjected;
  }

  /** 未授权 / 会话失败的占位（权限被拒给「去设置」引导） */
  @Builder
  private viewfinderPlaceholder() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.camera'))
        .fontSize(26)
        .fontWeight(FontWeight.Lighter)
        .fontColor(['#8CFFFFFF'])
      if (this.permissionDenied) {
        Text($r('app.string.s_6210f62fdd'))
          .fontSize(14)
          .fontColor('#8CFFFFFF')
        Text($r('app.string.s_1f2998c9c8'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E6FFFFFF')
          .padding({ top: 4, bottom: 4, left: 12, right: 12 })
          .borderRadius(14)
          .backgroundColor('#33FFFFFF')
          .onClick((): void => {
            this.openAppSettings();
          })
      } else if (this.sessionFailed) {
        Text($r('app.string.s_83e94c92d7'))
          .fontSize(14)
          .fontColor('#8CFFFFFF')
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#1F1F1F')
  }

  /** 相纸：白框包裹方形照片，底部留白更厚（iOS paperPrint 同款） */
  @Builder
  private paperPrint() {
    Column() {
      Stack() {
        if (this.shotPixelMap === undefined && this.previewFramePixelMap === undefined) {
          // 白纸先行：解码未完成时照片位是空白相纸（与显影蒙层同色，到位无感替换）
          Column()
            .width(this.frameSide() - 24)
            .height((this.frameSide() - 24) * 0.82)
            .borderRadius(2)
            .backgroundColor('#F7F6F2')
        } else if (this.previewFramePixelMap !== undefined) {
          // 快照垫层：吐纸途中即显影可见，真片交叉淡入后收走
          Image(this.previewFramePixelMap)
            .objectFit(ImageFit.Cover)
            .width(this.frameSide() - 24)
            .height((this.frameSide() - 24) * 0.82)
            .borderRadius(2)
            .draggable(false)
        }
        if (this.shotPixelMap !== undefined) {
          // 真片层：交叉淡入盖过快照（同景同框，观感是显影变清晰）
          Image(this.shotPixelMap)
            .objectFit(ImageFit.Cover)
            .width(this.frameSide() - 24)
            .height((this.frameSide() - 24) * 0.82)
            .borderRadius(2)
            .draggable(false)
            .opacity(this.realPhotoRevealed ? 1 : 0)
        }
        // 显影白蒙层：出纸时盖着影像，吐纸到位后渐褪（拍立得显影感）
        Column()
          .width(this.frameSide() - 24)
          .height((this.frameSide() - 24) * 0.82)
          .borderRadius(2)
          .backgroundColor('#F7F6F2')
          .opacity(this.printDeveloping ? 1 : 0)
      }
      .margin({ top: 8 })
      Blank()
    }
    .width(this.frameSide() - 12)
    .height(this.frameSide() - 12)
    .backgroundColor('#FAFAFA')
    .borderRadius(6)
    .rotate({ angle: this.paperTilt })
    .shadow({ radius: 8, color: '#40000000', offsetY: 4 })
    // 打印机吐纸：相纸从取景框顶「出纸口」滑入（外层 clip 裁掉槽外部分），
    // 到位后显影 + 落定微倾；重拍离场快速淡出（不倒吸回纸口）
    .transition(
      TransitionEffect.asymmetric(
        TransitionEffect.move(TransitionEdge.TOP)
          .animation({ duration: PRINT_EJECT_MS, curve: PRINT_EJECT_CURVE }),
        TransitionEffect.OPACITY
          .animation({ duration: 180, curve: Curve.EaseOut })
      )
    )
  }

  /** 可用变焦档位：缓存值（会话起来 / 翻转后 `refreshZoomModel()` 刷新） */
  private zoomPresets(): number[] {
    return this.zoomPresetList;
  }

  /**
   * 刷新变焦模型缓存：范围一次查齐（`zoomRange` 内部已是会话级缓存），
   * 档位按范围自适应算好存下——拖动 / 捏合热路径零 JNI，不卡 UI。
   */
  private refreshZoomModel(): void {
    const range = this.session.zoomRange();
    // UI 上限沿 10×：设备范围上探到 100× 的纯数码段没有档位支撑，拖 / 捏 / 档位同沿
    this.zoomMinCached = Math.min(1, range[0]);
    this.zoomMaxCached = Math.min(Math.max(1, range[1]), ZOOM_UI_MAX_RATIO);
    const presets = zoomPresetsForRange(this.zoomMinCached, this.zoomMaxCached);
    this.zoomPresetList = presets.length > 0 ? presets : [1];
  }

  /** 预设档位文案：整数不带小数（1 / 3 / 5），半档保留一位（1.5） */
  private zoomPresetLabel(preset: number): string {
    return preset % 1 === 0 ? preset.toFixed(0) : preset.toFixed(1);
  }

  private selectZoomPreset(preset: number): void {
    if (Math.abs(this.zoomRatio - preset) < 0.05) {
      return;
    }
    this.haptic('haptic.effect.soft');
    this.lastNearestPreset = preset;
    // 华为相机同款：画面走官方平滑变焦（setSmoothZoom 贝塞尔曲线）缓过去，
    // 数字泡轮询真值跟着走（1×→5× 中间的 1.2× / 4.7×…全有）；不支持才同步跳
    const smooth: boolean = this.session.smoothZoomTo(preset);
    if (smooth) {
      this.startSmoothZoomCount(preset);
    } else {
      this.cancelSmoothZoomCount();
      this.setZoomUiValue(preset);
    }
  }

  /**
   * 平滑变焦走数：官方 `setSmoothZoom` 没有逐帧倍率回调
   * （`smoothZoomInfoAvailable` 只报总时长），32ms 轮询同步 `getZoomRatio()`
   * 真值驱动数字泡——数字与画面逐帧同走；到位 / 超时 / 失败按目标收口。
   */
  private startSmoothZoomCount(target: number): void {
    this.cancelSmoothZoomCount();
    this.smoothZoomTargetRatio = target;
    let ticks: number = 0;
    const tick = (): void => {
      if (this.smoothZoomTargetRatio !== target) {
        return; // 已被拖动 / 新档位 / 翻转接管
      }
      ticks += 1;
      const current: number = this.session.getCurrentZoom();
      if (current <= 0 || Math.abs(current - target) < 0.03 || ticks >= 90) {
        this.cancelSmoothZoomCount();
        this.setZoomUiValue(target);
        return;
      }
      this.setZoomUiValue(current);
      this.smoothZoomPollTimer = setTimeout(tick, SMOOTH_ZOOM_POLL_MS);
    };
    this.smoothZoomPollTimer = setTimeout(tick, SMOOTH_ZOOM_POLL_MS);
  }

  /** 停掉平滑变焦走数轮询（新交互接管 / 组件卸载） */
  private cancelSmoothZoomCount(): void {
    this.smoothZoomTargetRatio = -1;
    if (this.smoothZoomPollTimer >= 0) {
      clearTimeout(this.smoothZoomPollTimer);
      this.smoothZoomPollTimer = -1;
    }
  }

  /**
   * 变焦 UI 单一写口：倍率落位（±0.05）点亮对应档位圆钮、收起数字泡；
   * 自由倍率（2.4×）圆钮全灰、数字泡显示实时值——两个渲染态都只在变化时写，
   * 拖动 / 走数的高频更新不再逐 0.1 重渲染整条磨砂胶囊。
   */
  private setZoomUiValue(ratio: number): void {
    this.zoomRatio = ratio;
    const settled: number = this.settledZoomPreset(ratio);
    if (settled !== this.zoomSettledPreset) {
      this.zoomSettledPreset = settled;
    }
    const label: string = settled >= 0 ? '' : formatZoomLabel(ratio);
    if (label !== this.zoomBubbleLabel) {
      this.zoomBubbleLabel = label;
    }
  }

  /** 落位档（±0.05 内算落位）；自由倍率返回 -1 */
  private settledZoomPreset(ratio: number): number {
    const presets: number[] = this.zoomPresetList;
    for (let i = 0; i < presets.length; i++) {
      if (Math.abs(presets[i] - ratio) < 0.05) {
        return presets[i];
      }
    }
    return -1;
  }

  /**
   * 变焦条（华为相机式磨砂胶囊）：档位点按切换；整条横向拖动自由变焦，
   * 跨档轻震；上限跟随机型能力。变焦中（拖动 / 平滑走数）胶囊上方悬浮
   * 数字泡实时走数（自由倍率常驻，落位档位才收起）——数字不再在档位格间跳。
   */
  @Builder
  private zoomRow() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 磨砂挂内层 Stack 背景，黑罩挂 Row 背景：同一组件上材质层会盖住 backgroundColor，
      // 拆两层才能「磨砂在下、黑罩在上」；拖动手势挂胶囊本体
      Stack() {
        Row({ space: 4 }) {
          ForEach(this.zoomPresets(), (preset: number) => {
            if (this.zoomSettledPreset === preset) {
              this.zoomSelectedPill(`${this.zoomPresetLabel(preset)}×`)
            } else {
              Text(`${this.zoomPresetLabel(preset)}×`)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(ZOOM_BAR_TEXT)
                .padding({ left: 9, right: 9, top: 9, bottom: 9 })
                .onClick((): void => {
                  this.selectZoomPreset(preset);
                })
            }
          }, (preset: number) => `${preset}`)
        }
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
        .backgroundColor(ZOOM_BAR_TINT)
        .borderRadius(20)
      }
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius(20)
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 2 })
          .onActionStart((): void => {
            this.gestureStartZoomRatio = this.zoomRatio;
          })
          .onActionUpdate((event: GestureEvent): void => {
            // 乘法映射（80vp 一倍程）：起点倍率 × 2^(位移/80)，细腻不跳段
            this.applyContinuousZoom(
              this.gestureStartZoomRatio *
              Math.pow(2, event.offsetX / ZOOM_DRAG_VP_PER_OCTAVE));
          })
          .onActionEnd((): void => {
            this.endContinuousZoom();
          })
          .onActionCancel((): void => {
            this.endContinuousZoom();
          })
      )
      if (this.zoomBubbleLabel !== '') {
        Text(`${this.zoomBubbleLabel}×`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(ZOOM_BAR_TEXT)
          .backgroundColor(ZOOM_BAR_TINT)
          .borderRadius(14)
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .offset({ y: -46 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 140 }))
      }
    }
    .margin({ top: 69 })
  }

  /** 选中档圆钮：磨砂底上的亮钮，底色反深字（华为相机式） */
  @Builder
  private zoomSelectedPill(label: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.textPrimary)
    }
    .width(32)
    .height(32)
    .borderRadius(16)
    .backgroundColor(this.theme.background)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 连续变焦（拖条 / 捏合共用，官方手势模式）：每次手势更新把目标直接
   * `setZoom` 下发（HAL 1-2 帧生效自动合并，官方示例同款不节流）；
   * 全精度记 `continuousZoomTarget`，标签 0.1 步进才写 @State（重渲染降一个量级），跨档轻震。
   */
  private applyContinuousZoom(target: number): void {
    const clamped: number = Math.min(Math.max(target, this.zoomMinCached), this.zoomMaxCached);
    this.continuousZoomTarget = clamped;
    this.session.setZoom(clamped);
    // 拖动接管：停掉平滑变焦走数轮询（若有），数字泡改由拖动真值驱动
    if (this.smoothZoomPollTimer >= 0 || this.smoothZoomTargetRatio >= 0) {
      this.cancelSmoothZoomCount();
    }
    const rounded: number = Math.round(clamped * 10) / 10;
    if (Math.abs(rounded - this.zoomRatio) < 0.001) {
      return;
    }
    this.setZoomUiValue(rounded);
    const nearest: number = nearestZoomPreset(rounded, this.zoomPresetList);
    if (nearest !== this.lastNearestPreset) {
      this.lastNearestPreset = nearest;
      this.haptic('haptic.effect.soft');
    }
  }

  /** 连续变焦收尾：把精确终值再下发一次（收口） */
  private endContinuousZoom(): void {
    this.session.setZoom(this.continuousZoomTarget);
  }

  // ---- 控制行 ----

  /** 拍照行：关闭 | 快门 | 翻转（iOS 新版参考：✕/翻转裸图标无底色，间距收紧） */
  @Builder
  private captureControls() {
    Row({ space: 13 }) {
      this.circleButton($r('sys.symbol.xmark'), (): void => {
        this.closeCamera();
      })
      // 快门：印泥红实心 + 白色内圈；按压缩放反馈
      Stack() {
        Column()
          .width(74)
          .height(74)
          .borderRadius(37)
          .backgroundColor(SHUTTER_RED)
          .shadow({ radius: 10, color: '#73C23D30', offsetY: 4 })
        Column()
          .width(62)
          .height(62)
          .borderRadius(31)
          .border({ width: 2, color: '#59FFFFFF' })
      }
      .scale({ x: this.capturing ? 0.9 : 1, y: this.capturing ? 0.9 : 1 })
      .animation({ curve: PRESS_CURVE })
      .opacity(this.authorized ? 1 : 0.4)
      .onClick((): void => {
        this.capture();
      })
      .accessibilityText($r('app.string.s_3da4b3651a'))
      this.circleButton($r('sys.symbol.switch_camera'), (): void => {
        this.flipCamera();
      })
    }
    .margin({ top: 18 })
  }

  /** 审阅行：重拍 | 写下这一刻（iOS reviewControls 同款） */
  @Builder
  private reviewControls() {
    Row({ space: 14 }) {
      Row() {
        Text($r('app.string.s_41c3719d6a'))
          .fontSize(15)
          .fontColor(this.theme.textSecondary)
      }
      .width(96)
      .height(48)
      .borderRadius(24)
      .backgroundColor(this.theme.cardBackground)
      .justifyContent(FlexAlign.Center)
      .onClick((): void => {
        this.retake();
      })

      Row() {
        Text($r('app.string.s_a9d57f8585'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.background)
      }
      .width(152)
      .height(48)
      .borderRadius(24)
      .backgroundColor(this.theme.accent)
      .justifyContent(FlexAlign.Center)
      .onClick((): void => {
        this.confirmShot();
      })
    }
    .margin({ top: 69 })
  }

  /** ✕ / 翻转：裸灰色图标（iOS 新版参考无底色），圆形热区保住好点按 */
  @Builder
  private circleButton(iconRes: Resource, action: () => void) {
    Row() {
      SymbolGlyph(iconRes)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
    }
    .width(52)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      action();
    })
  }

  // ---- 底部工具条（闪光 + 相纸入口） ----

  /** 工具条：居中收在底部（iOS 新版参考），选中态近黑胶囊反白 */
  @Builder
  private bottomBar() {
    Row({ space: 22 }) {
      // 闪光三态（有闪光单元才显示）：点开是「自动/闪光开/闪光关」三选托盘
      if (this.flashAvailable) {
        if (this.flashTrayOpen) {
          Row() {
            this.flashTray()
          }
          .transition(flashTrayTransition())
        } else {
          Row() {
            this.flashChip()
          }
          .transition(flashTrayTransition())
        }
      }
      this.paperChip()
    }
    .padding({ top: 10, bottom: 10 })
  }

  /** 闪光三选托盘：自动 / 闪光开 / 闪光关（iOS 同款三态，点选即生效即收） */
  @Builder
  private flashTray() {
    Row({ space: 4 }) {
      this.flashSegment(FlashSetting.Auto)
      this.flashSegment(FlashSetting.On)
      this.flashSegment(FlashSetting.Off)
    }
  }

  /** 托盘里的单个选项：选中近黑胶囊反白，未选裸灰字 */
  @Builder
  private flashSegment(setting: FlashSetting) {
    Text(this.flashOptionLabel(setting))
      .fontSize(13)
      .fontWeight(this.flashSetting === setting ?
        FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.flashSetting === setting ?
        this.theme.background : this.theme.textSecondary)
      .padding({ left: 13, right: 13, top: 7, bottom: 7 })
      .borderRadius(17)
      .backgroundColor(this.flashSetting === setting ?
        this.theme.textPrimary : Color.Transparent)
      .onClick((): void => {
        this.pickFlash(setting);
      })
  }

  /**
   * 闪光 chip（收起态）：选中态近黑胶囊反白、平时裸灰字。
   * ⚠️ @Builder 按值传参不刷新 UI（官方 faqs-arkui-1078）——chip 直读
   * this.flashLabel() / this.flashSetting，状态一变局部即重渲。
   */
  @Builder
  private flashChip() {
    Row({ space: 5 }) {
      Text(this.flashLabel())
        .fontSize(13)
        .fontColor(this.flashSetting !== FlashSetting.Off ?
          this.theme.background : this.theme.textSecondary)
    }
    .padding({ left: 13, right: 13, top: 7, bottom: 7 })
    .borderRadius(17)
    .backgroundColor(this.flashSetting !== FlashSetting.Off ?
      this.theme.textPrimary : Color.Transparent)
    .onClick((): void => {
      this.openFlashTray();
    })
  }

  /**
   * 相纸 chip（底部常驻）：直读 this.selectedPaper / this.showPaperStrip——
   * 选完相纸 chip 文案即变（此前经 toolChip 按值传参被冻结在初始「宝丽来」）。
   */
  @Builder
  private paperChip() {
    Row({ space: 5 }) {
      Text(this.paperName(this.selectedPaper))
        .fontSize(13)
        .fontColor(this.showPaperStrip ?
          this.theme.background : this.theme.textSecondary)
      SymbolGlyph($r('sys.symbol.chevron_up'))
        .fontSize(9)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.showPaperStrip ?
          this.theme.background : this.theme.textSecondary])
        // 铺开时箭头转向下方，指示「再点一下收起」
        .rotate({ angle: this.showPaperStrip ? 180 : 0 })
    }
    .padding({ left: 13, right: 13, top: 7, bottom: 7 })
    .borderRadius(17)
    .backgroundColor(this.showPaperStrip ?
      this.theme.textPrimary : Color.Transparent)
    .onClick((): void => {
      this.togglePaperStrip();
    })
  }

  /** 相纸选择条（横向滚动；预览用刚拍到的方图，所见即所得） */
  @Builder
  private paperStrip() {
    Scroll() {
      Row({ space: 14 }) {
        ForEach(CAMERA_PAPER_STYLES, (style: PaperStyle) => {
          Column({ space: 6 }) {
            PaperPreviewCard({
              style: style,
              pixelMap: this.shotPixelMap
            })
              // 边框恒宽（未选中透明）——选中时不会把卡片顶得跳一下
              .border({
                width: 2,
                color: this.selectedPaper === style ?
                  this.theme.accent : Color.Transparent,
                radius: 10
              })
              .scale({
                x: this.selectedPaper === style ? 1.0 : 0.94,
                y: this.selectedPaper === style ? 1.0 : 0.94
              })
              .opacity(this.selectedPaper === style ? 1 : 0.6)
              .animation({ curve: PAPER_CURVE })
            Text(this.paperName(style))
              .fontSize(12)
              .fontWeight(this.selectedPaper === style ?
                FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.selectedPaper === style ?
                this.theme.textSecondary : this.theme.textTertiary)
          }
          .onClick((): void => {
            this.pickPaper(style);
          })
        }, (style: PaperStyle) => style)
      }
      .padding({ left: 20, right: 20, top: 10, bottom: 8 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    // 进出场转场在外层包装 Column 上（controlSwapTransition），这里不再叠加
  }

  // ---- 动作 ----

  private async requestCameraPermissions(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      this.sessionFailed = true;
      return;
    }
    let cameraGranted = false;
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      // 相机必给；麦克风顺带申请（动态照片要带声），被拒不拦相机
      const result = await atManager.requestPermissionsFromUser(context,
        ['ohos.permission.CAMERA', 'ohos.permission.MICROPHONE']);
      for (let i = 0; i < result.permissions.length; i++) {
        if (result.permissions[i] === 'ohos.permission.CAMERA' && result.authResults[i] === 0) {
          cameraGranted = true;
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'request camera permission failed: %{public}s', JSON.stringify(err));
    }
    if (!cameraGranted) {
      this.permissionDenied = true;
      return;
    }
    this.permissionReady = true;
    this.tryOpenSession();
  }

  /** 预览 surface 就绪（XComponent onLoad） */
  private onSurfaceReady(): void {
    this.surfaceId = this.surfaceController.getXComponentSurfaceId();
    this.surfaceReady = true;
    this.tryOpenSession();
  }

  /** 权限 + surface 都齐了才起会话（两个条件到达顺序不定） */
  private tryOpenSession(): void {
    if (!this.surfaceReady || !this.permissionReady || this.openingSession) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined || this.surfaceId.length === 0) {
      return;
    }
    this.openingSession = true;
    this.session.onShot = (shot: CameraShot): void => {
      this.handleShot(shot);
    };
    this.session.onCaptureFailed = (): void => {
      // 拍照 / 提取失败：取景不中断，快门可再按
      this.capturing = false;
      // 快照先行已出纸但没等到真片：收纸退回拍摄态
      if (this.paperEjected && this.capturedShot === undefined) {
        this.retake();
      }
    };
    this.session.open(context, this.surfaceId,
      Math.round(this.getUIContext().vp2px(this.frameSide()))).then((ok: boolean): void => {
      this.openingSession = false;
      if (!ok) {
        this.sessionFailed = true;
        return;
      }
      this.authorized = true;
      this.previewAspect = this.session.previewAspect;
      // 档位 / 范围缓存一次刷好（此后拖动 / 捏合热路径零查询）
      this.refreshZoomModel();
      this.flashAvailable = this.session.hasFlashUnit();
      this.session.setFlash(this.flashSetting);
    }).catch((): void => {
      this.openingSession = false;
      this.sessionFailed = true;
    });
  }

  /** 拍到一张：真片解码后落到相纸上（快照 / 白纸已先行出纸） */
  private async handleShot(shot: CameraShot): Promise<void> {
    this.capturing = false;
    this.capturedShot = shot;
    this.resolveShotWaiters();
    this.decodePromise = decodeCenterSquare(shot.stillBuffer);
    if (!this.paperEjected) {
      // 快照没抓到：白纸先行兜底
      this.printDeveloping = true;
      this.paperTilt = 0;
      this.getUIContext().animateTo({ curve: PAPER_CURVE }, (): void => {
        this.paperEjected = true;
      });
      // 毫秒计时：相纸出片上屏（快门→此处 = 用户感知的拍照延迟）
      this.session.markPaperShown();
      this.startEjectAnimations();
    }
    const square = await this.decodePromise;
    // 已重拍 / 已确认收场：丢弃本次解码
    if (this.capturedShot !== shot) {
      return;
    }
    if (square === undefined) {
      hilog.error(DOMAIN, TAG, 'decodeCenterSquare failed, stay in capture mode');
      this.retake();
      return;
    }
    // 真片上纸 + 交叉淡入盖过快照（同景同框，观感是显影变清晰）
    this.shotPixelMap = square;
    this.revealRealPhoto();
    this.session.markPhotoOnPaper();
  }

  /** 快门瞬间抓取景帧先上纸（真 50MP 成像 ~0.8s，先让相纸有图） */
  private async ejectWithPreviewFrame(): Promise<void> {
    const frame = await this.grabPreviewFrame();
    // 拍摄已失败 / 相纸已出（白纸兜底抢先）：快照作废
    if (!this.capturing || this.paperEjected) {
      if (frame !== undefined) {
        frame.release().catch((): void => {});
      }
      return;
    }
    if (frame === undefined) {
      return;
    }
    this.previewFramePixelMap = frame;
    // 出纸是直的（先不倾），显影蒙层先盖满
    this.printDeveloping = true;
    this.paperTilt = 0;
    this.getUIContext().animateTo({ curve: PAPER_CURVE }, (): void => {
      this.paperEjected = true;
    });
    // 毫秒计时：快照先行出纸（用户看到相纸的第一刻）
    this.session.markPaperShown();
    this.startEjectAnimations();
  }

  /** 抓取景器当前帧（surface 快照）并居中裁方（与取景框所见一致） */
  private async grabPreviewFrame(): Promise<image.PixelMap | undefined> {
    if (this.surfaceId.length === 0) {
      return undefined;
    }
    try {
      const full = await image.createPixelMapFromSurface(this.surfaceId);
      const size = full.getImageInfoSync().size;
      const side = Math.min(size.width, size.height);
      await full.crop({
        size: { width: side, height: side },
        x: Math.floor((size.width - side) / 2),
        y: Math.floor((size.height - side) / 2)
      } as image.Region);
      return full;
    } catch (err) {
      // 快照失败（机型 / 时机不支持）不算拍照失败：白纸先行兜底
      return undefined;
    }
  }

  /** 释放快照帧（真片换下 / 收纸时调用，防泄漏） */
  private releasePreviewFrame(): void {
    const frame = this.previewFramePixelMap;
    this.previewFramePixelMap = undefined;
    if (frame !== undefined) {
      frame.release().catch((): void => {});
    }
  }

  /** 真片已到 / 已收纸：解锁「写下这一刻」的等待者 */
  private resolveShotWaiters(): void {
    const waiters = this.shotWaiters;
    this.shotWaiters = [];
    for (const resolve of waiters) {
      resolve();
    }
  }

  /** 出纸动画：显影蒙层吐纸途中渐褪（打印机边走边印）+ 相纸落定微倾（±2.5° 随机） */
  private startEjectAnimations(): void {
    this.getUIContext().animateTo(
      { duration: PRINT_DEVELOP_MS, delay: PRINT_DEVELOP_DELAY_MS, curve: Curve.EaseOut },
      (): void => {
        this.printDeveloping = false;
      });
    this.getUIContext().animateTo({ delay: PRINT_EJECT_MS + 40, curve: PAPER_CURVE }, (): void => {
      this.paperTilt = Math.random() * PAPER_TILT_DEGREES * 2 - PAPER_TILT_DEGREES;
    });
  }

  /** 真片显影：交叉淡入盖过快照垫层，淡完再收垫层（防渲染中的 pixelmap 被释放） */
  private revealRealPhoto(): void {
    this.getUIContext().animateTo(
      { duration: PHOTO_SWAP_MS, curve: Curve.EaseOut },
      (): void => {
        this.realPhotoRevealed = true;
      });
    const snapshot = this.previewFramePixelMap;
    if (snapshot === undefined) {
      return;
    }
    clearTimeout(this.swapReleaseTimer);
    this.swapReleaseTimer = setTimeout((): void => {
      this.swapReleaseTimer = -1;
      if (this.previewFramePixelMap === snapshot) {
        this.releasePreviewFrame();
      }
    }, PHOTO_SWAP_MS + 180);
  }

  private capture(): void {
    if (!this.authorized || this.capturing || this.paperEjected) {
      return;
    }
    this.capturing = true;
    this.haptic('haptic.effect.hard');
    // 快门白闪：快进快出
    this.getUIContext().animateTo({ duration: 60, curve: Curve.EaseIn }, (): void => {
      this.flashOn = true;
    });
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut, delay: 60 }, (): void => {
      this.flashOn = false;
    });
    this.session.capture();
    // 快照先行：取景帧立刻上纸，真片解码完成后换掉
    this.ejectWithPreviewFrame();
  }

  private retake(): void {
    clearTimeout(this.swapReleaseTimer);
    this.swapReleaseTimer = -1;
    this.capturedShot = undefined;
    this.decodePromise = undefined;
    this.shotPixelMap = undefined;
    this.realPhotoRevealed = false;
    this.releasePreviewFrame();
    this.paperEjected = false;
    this.printDeveloping = false;
    this.resolveShotWaiters();
  }

  /** 「写下这一刻」：回写默认相纸偏好，交产物给页面插入（文件链由页面跑） */
  private async confirmShot(): Promise<void> {
    if (!this.paperEjected) {
      return;
    }
    if (this.capturedShot === undefined && this.capturing) {
      // 快照先行的窗口里点下：等真片到（拍摄没失败就一定会来）
      await new Promise<void>((resolve: (value: void) => void): void => {
        this.shotWaiters.push(resolve);
      });
    }
    const shot = this.capturedShot;
    if (shot === undefined) {
      return;
    }
    // 抢在解码完成前点下：等解码（白纸先行留给解码的窗口，通常已就绪）
    let square = this.shotPixelMap;
    if (square === undefined && this.decodePromise !== undefined) {
      square = await this.decodePromise;
      if (square !== undefined && this.capturedShot === shot) {
        // 抢先落片（视图即将离场，handleShot 靠 capturedShot 守卫让路）
        this.shotPixelMap = square;
        this.revealRealPhoto();
        this.session.markPhotoOnPaper();
      }
    }
    if (square === undefined) {
      return;
    }
    // 让 handleShot 的解码续段跳过 UI 动画（视图即将拆）
    this.capturedShot = undefined;
    clearTimeout(this.swapReleaseTimer);
    this.swapReleaseTimer = -1;
    this.clearStripTimer();
    this.clearFlashTrayTimer();
    AppPrefs.putString(PREF_KEY_DEFAULT_PAPER_STYLE, this.selectedPaper);
    this.session.close();
    this.onCapture(shot, square, this.selectedPaper);
  }

  private closeCamera(): void {
    this.clearStripTimer();
    this.clearFlashTrayTimer();
    this.session.close();
    this.onCancel();
  }

  /** 前后摄切换：换镜头后重查闪光 / 重新应用闪光与变焦 */
  private flipCamera(): void {
    this.haptic('haptic.effect.soft');
    this.session.flip().then((ok: boolean): void => {
      if (!ok) {
        return;
      }
      this.previewAspect = this.session.previewAspect;
      this.flashAvailable = this.session.hasFlashUnit();
      this.session.setFlash(this.flashSetting);
      // 新镜头范围不同：刷缓存档位，倍率回 1×（系统相机同款）
      this.refreshZoomModel();
      this.cancelSmoothZoomCount();
      this.continuousZoomTarget = 1;
      this.lastNearestPreset = 1;
      this.session.setZoom(1);
      this.setZoomUiValue(1);
    }).catch((): void => {
      // 翻转失败保持原样
    });
  }

  /** 三态 → 文案（自动 / 闪光开 / 闪光关，iOS 同款） */
  private flashOptionLabel(setting: FlashSetting): Resource {
    switch (setting) {
      case FlashSetting.On:
        return $r('app.string.s_f2a27892d0');
      case FlashSetting.Off:
        return $r('app.string.s_2a8f9bcff7');
      default:
        return $r('app.string.s_4afad87755');
    }
  }

  /** 展开闪光三选托盘（与相纸抽屉互斥） */
  private openFlashTray(): void {
    this.haptic('haptic.effect.soft');
    this.clearStripTimer();
    this.clearFlashTrayTimer();
    this.getUIContext().animateTo({ curve: PAPER_CURVE }, (): void => {
      this.showPaperStrip = false;
      this.flashTrayOpen = true;
    });
  }

  /** 托盘里点选闪光态：即生效，稍延收托盘（让选中高亮先被看见） */
  private pickFlash(setting: FlashSetting): void {
    this.clearFlashTrayTimer();
    if (this.flashSetting !== setting) {
      this.haptic('haptic.effect.soft');
      this.getUIContext().animateTo({ curve: PAPER_CURVE }, (): void => {
        this.flashSetting = setting;
      });
      this.session.setFlash(setting);
    }
    this.flashTrayCloseTimer = setTimeout((): void => {
      this.getUIContext().animateTo({ curve: PAPER_CURVE }, (): void => {
        this.flashTrayOpen = false;
      });
    }, 220);
  }

  private clearFlashTrayTimer(): void {
    if (this.flashTrayCloseTimer >= 0) {
      clearTimeout(this.flashTrayCloseTimer);
      this.flashTrayCloseTimer = -1;
    }
  }

  private togglePaperStrip(): void {
    // 白纸先行的审阅态：影像解码没到位不开条（预览卡是普通字段，开了不会再刷出来）
    if (this.paperEjected && this.shotPixelMap === undefined) {
      return;
    }
    this.haptic('haptic.effect.soft');
    this.clearStripTimer();
    this.clearFlashTrayTimer();
    this.getUIContext().animateTo({ curve: PAPER_CURVE }, (): void => {
      this.showPaperStrip = !this.showPaperStrip;
      this.flashTrayOpen = false;
    });
  }

  private pickPaper(style: PaperStyle): void {
    this.haptic('haptic.effect.soft');
    this.selectedPaper = style;
    // 选完稍延后收条：让选中态高亮先被看见
    this.clearStripTimer();
    this.stripCloseTimer = setTimeout((): void => {
      this.getUIContext().animateTo({ curve: PAPER_CURVE }, (): void => {
        this.showPaperStrip = false;
      });
    }, 220);
  }

  private clearStripTimer(): void {
    if (this.stripCloseTimer >= 0) {
      clearTimeout(this.stripCloseTimer);
      this.stripCloseTimer = -1;
    }
  }

  /** 轻震（vibrator 预设效果；机型没有该预设（Mate X6 无 haptic.effect.*）退毫秒短震，再失败静默——震动只是手感，不构成功能） */
  private haptic(effectId: string): void {
    const preset: vibrator.VibratePreset = { type: 'preset', effectId: effectId, count: 1 };
    vibrator.startVibration(preset, { usage: 'touch' }).catch((): void => {
      const fallback: vibrator.VibrateTime = {
        type: 'time',
        duration: effectId === 'haptic.effect.hard' ? 24 : 12
      };
      vibrator.startVibration(fallback, { usage: 'touch' }).catch((): void => {
      });
    });
  }

  /**
   * 相机开 / 关：灵动岛机型按官方范式隐藏状态栏（faqs-arkui-274，机身贴挖孔后
   * 状态栏文字会压在黑色机身上，藏掉最干净），退场还原；
   * 藏失败时状态文字反白兜底（白字浮在黑色机身上仍可读）。
   * 普通机型（无挖孔）状态栏照常显示、颜色不动。
   */
  private setSystemBarsForCamera(active: boolean): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const island: boolean = active && this.hasIsland();
    let restore: string = '#000000';
    if (typeof this.theme.background === 'number') {
      restore = systemBarContentColorFor(this.theme.background);
    } else if (this.theme.colorMode === 'dark') {
      restore = '#FFFFFF';
    }
    window.getLastWindow(context).then((win: window.Window): void => {
      const names: Array<'status' | 'navigation'> = island ? ['navigation'] : ['status', 'navigation'];
      win.setWindowSystemBarEnable(names).catch((): void => {
        // 藏不了：反白兜底已备好，不拦相机
      });
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: island ? '#FFFFFF' : restore
      }).catch((): void => {
        // 极端场景设不上：不拦相机
      });
    }).catch((): void => {
      // 取不到窗口：不拦相机
    });
  }

  /** 「去设置」：跳系统设置的本应用信息页（application_info_entry，录音面板同款） */
  private openAppSettings(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      return;
    }
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo): void => {
        const want: Want = {
          bundleName: 'com.huawei.hmos.settings',
          abilityName: 'com.huawei.hmos.settings.MainAbility',
          uri: `application_info_entry/${info.name}`
        };
        context.startAbility(want).catch((): void => {
          // 跳转失败（极端场景）：留在引导态
        });
      }).catch((): void => {
        // 取不到包信息：留在引导态
      });
  }

  // ---- 文案映射 ----

  private flashLabel(): Resource {
    switch (this.flashSetting) {
      case FlashSetting.On:
        return $r('app.string.s_f2a27892d0');
      case FlashSetting.Off:
        return $r('app.string.s_2a8f9bcff7');
      default:
        return $r('app.string.s_4afad87755');
    }
  }

  private paperName(style: PaperStyle): Resource {
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
