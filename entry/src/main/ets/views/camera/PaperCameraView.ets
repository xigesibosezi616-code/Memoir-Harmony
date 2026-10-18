/**
 * 尺素相机（10_BUILD_MANUAL.md 2.9）。对应 iOS `Views/Camera/PaperCameraView.swift`。
 *
 * **设计意图**（iOS 注释同款）：不是做一台拍立得（没人愿意等虚拟显影），
 * 而是借拍立得的「手感」——按下快门、一张相纸落到手里、顺手想写点什么。
 * 成像原图直出，零等待。
 *
 * - 取景框：黑色圆角机身包方形画面（鸿蒙无灵动岛，四周等厚黑边简化处理）；
 *   预览 XComponent 按 Profile 宽高比定尺寸防拉伸（faqs-arkui-700），
 *   外层裁成方形 = 所见即裁切范围
 * - 拍完：相纸以「递到手里」的小倾斜落在取景框里（±2.5° 随机）；
 *   预览 surface **不销毁**（销毁后重建 surfaceId 变了预览接不回），相纸盖在上面
 * - 闪光三态循环（自动→开→关，有闪光单元才显示）/ 变焦条（每跨半档轻震）/
 *   前后摄切换；震动走 vibrator 预设效果（haptic.effect.soft / hard）
 * - 相纸在相机里就选好（初值取偏好 `defaultPaperStyle`，确认时回写），
 *   拍完点「写下这一刻」回调产物；配对 / 存相册由页面接手
 * - 权限：开页申请相机（+ 麦克风，动态照片要带声）；相机被拒渲染
 *   「需要相机权限 + 去设置」引导态（跳系统应用信息页，录音面板同款）
 */
import { image } from '@kit.ImageKit';
import { curves, display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';
import { abilityAccessCtrl, bundleManager, common, Want } from '@kit.AbilityKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import {
  STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP
} from '../../services/ImmersiveChrome';
import { PaperStyle, paperStyleFromRaw } from '../../models/ContentBlock';
import { CameraSession, CameraShot, FlashSetting, nextFlashSetting } from '../../services/CameraSession';
import { decodeCenterSquare } from '../../services/CameraPhotoFiles';
import { AppPrefs, PREF_KEY_DEFAULT_PAPER_STYLE } from '../../services/AppPrefs';
import { PaperPreviewCard } from '../components/photo/PhotoPapers';

const DOMAIN = 0x0000;
const TAG = 'PaperCameraView';

/** 快门印泥红（iOS shutterRed 同款 0.76/0.24/0.19，呼应印章体系） */
const SHUTTER_RED: string = '#C23D30';
/** 取景框两侧留白（iOS 36pt 半宽） */
const FRAME_MARGIN: number = 18;
/** 取景框黑边厚度（鸿蒙无灵动岛，四边等厚） */
const VIEWFINDER_BEZEL: number = 14;
/** 变焦条拖动行程（vp；拖满从 1× 到上限，iOS 150pt 同值） */
const ZOOM_TRACK_VP: number = 150;
/** 相纸落到手里的轻微倾斜幅度（±°，iOS ±2.5） */
const PAPER_TILT_DEGREES: number = 2.5;
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

@Component
export struct PaperCameraView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  /** 拍完点「写下这一刻」：原始产物 + 裁过的方图（显示用）+ 选中的相纸样式 */
  onCapture: (shot: CameraShot, squarePixelMap: image.PixelMap, style: PaperStyle) => void =
    (_shot: CameraShot, _squarePixelMap: image.PixelMap, _style: PaperStyle): void => {};
  /** 关闭（✕ / 权限引导取消都走它；页面收浮层） */
  onCancel: () => void = (): void => {};

  @State private permissionDenied: boolean = false;
  @State private sessionFailed: boolean = false;
  /** 会话已起（预览可见、快门可按） */
  @State private authorized: boolean = false;
  /** 拍到的方图；非 undefined 时取景框变为相纸审阅态 */
  @State private shotPixelMap: image.PixelMap | undefined = undefined;
  @State private capturing: boolean = false;
  /** 快门白闪 */
  @State private flashOn: boolean = false;
  @State private flashSetting: FlashSetting = FlashSetting.Auto;
  /** 当前镜头有无闪光单元（前摄通常没有；决定显不显示闪光键） */
  @State private flashAvailable: boolean = false;
  @State private selectedPaper: PaperStyle = PaperStyle.Polaroid;
  @State private showPaperStrip: boolean = false;
  @State private zoomRatio: number = 1;
  /** 相纸落下时的轻微倾斜（每次拍照随机，避免每次一模一样） */
  @State private paperTilt: number = 0;
  /** 取景画面宽高比（Profile 实测值；XComponent 按它定高防拉伸） */
  @State private previewAspect: number = 4 / 3;

  private capturedShot: CameraShot | undefined = undefined;
  private session: CameraSession = new CameraSession();
  private surfaceController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private surfaceReady: boolean = false;
  private permissionReady: boolean = false;
  private openingSession: boolean = false;
  private dragStartZoom: number = 1;
  /** 上一次触发震动的半档位（每跨 0.5× 响一下） */
  private lastHapticStep: number = 2;
  /** 相纸选中后延时收条（让高亮先被看见） */
  private stripCloseTimer: number = -1;
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
    this.requestCameraPermissions();
  }

  aboutToDisappear(): void {
    this.clearStripTimer();
    this.session.close();
  }

  build() {
    Stack() {
      // 主题底（延伸到状态栏 / 手势条底下）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme.background)
        .expandSafeArea([SafeAreaType.SYSTEM])

      Column() {
        this.viewfinder()

        // 品牌字样（iOS brandMark：尺素 + 记录此刻 / 这一刻已经落在纸上）
        Column({ space: 3 }) {
          Text($r('app.string.s_87d04c6c61'))
            .fontSize(this.theme.titleFont.size)
            .fontWeight(this.theme.titleFont.weight)
            .fontFamily(this.theme.titleFont.family)
            .fontColor(this.theme.textPrimary)
            .letterSpacing(this.theme.letterSpacingWide)
          Text(this.shotPixelMap !== undefined ?
            $r('app.string.s_95a69206f7') : $r('app.string.s_e5e80726bd'))
            .fontSize(this.theme.labelFont.size)
            .fontWeight(this.theme.labelFont.weight)
            .fontFamily(this.theme.labelFont.family)
            .fontColor(this.theme.textTertiary)
        }
        .margin({ top: 16 })

        if (this.shotPixelMap === undefined) {
          this.captureControls()
        } else {
          this.reviewControls()
        }

        Blank()

        this.bottomBar()
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.safeAreaTopVp + 12,
        left: FRAME_MARGIN,
        right: FRAME_MARGIN,
        bottom: this.safeAreaBottomVp
      })

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

  /** 方形画面边长（屏宽 - 两侧留白 - 两侧黑边） */
  private frameSide(): number {
    return this.screenWidthVp - FRAME_MARGIN * 2 - VIEWFINDER_BEZEL * 2;
  }

  @Builder
  private viewfinder() {
    // 机身：黑边 + 圆角 + 投影；画面方形居中裁切
    Stack() {
      Stack() {
        // 预览常驻（审阅态被相纸盖住；surface 不销毁，重拍即回）
        XComponent({ type: XComponentType.SURFACE, controller: this.surfaceController })
          .onLoad((): void => {
            this.onSurfaceReady();
          })
          .width(this.frameSide())
          .height(this.frameSide() / this.previewAspect)
          .visibility(this.authorized && this.shotPixelMap === undefined ?
            Visibility.Visible : Visibility.Hidden)

        // 未授权 / 会话失败：引导态盖在预览位上
        if (!this.authorized) {
          this.viewfinderPlaceholder()
        }

        // 拍完：照片以相纸形态落下（白框 + 底部留白 + 小倾斜）
        if (this.shotPixelMap !== undefined) {
          this.paperPrint()
        }

        // 变焦条：画面右缘竖排（预览可见且设备支持变焦才显示）
        if (this.authorized && this.shotPixelMap === undefined) {
          this.zoomSlider()
        }
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
      Image(this.shotPixelMap)
        .objectFit(ImageFit.Cover)
        .width(this.frameSide() - 24)
        .height((this.frameSide() - 24) * 0.82)
        .borderRadius(2)
        .draggable(false)
        .margin({ top: 8 })
      Blank()
    }
    .width(this.frameSide() - 12)
    .height(this.frameSide() - 12)
    .backgroundColor('#FAFAFA')
    .borderRadius(6)
    .rotate({ angle: this.paperTilt })
    .shadow({ radius: 8, color: '#40000000', offsetY: 4 })
    // 相纸「落到手里」：从底部浮起
    .transition(
      TransitionEffect.move(TransitionEdge.BOTTOM)
        .animation({ curve: PAPER_CURVE })
        .combine(TransitionEffect.OPACITY)
    )
  }

  /** 变焦条：上下拖动改变倍率，每跨半档轻震一次（iOS zoomSlider 同款） */
  @Builder
  private zoomSlider() {
    Column() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.theme.textSecondary])
        .opacity(0.55)
      Blank()
      Text(`${this.zoomRatio.toFixed(1)}×`)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.textSecondary)
      Blank()
      SymbolGlyph($r('sys.symbol.minus'))
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.theme.textSecondary])
        .opacity(0.55)
    }
    .padding({ top: 14, bottom: 14 })
    .width(42)
    .height(ZOOM_TRACK_VP)
    .borderRadius(21)
    .backgroundColor(this.theme.cardBackground)
    .border({ width: 0.8, color: this.theme.border })
    .shadow({ radius: 6, color: '#14000000', offsetY: 3 })
    .position({ x: this.frameSide() - 50, y: this.frameSide() / 2 - ZOOM_TRACK_VP / 2 })
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Vertical })
        .onActionStart((): void => {
          this.dragStartZoom = this.zoomRatio;
        })
        .onActionUpdate((event: GestureEvent): void => {
          const span = this.session.maxZoomRatio() - 1;
          if (span <= 0) {
            return;
          }
          // 向上拖 = 放大；整条行程走完 1× 到上限
          const delta = -event.offsetY / ZOOM_TRACK_VP * span;
          const next = Math.min(this.session.maxZoomRatio(),
            Math.max(1, this.dragStartZoom + delta));
          this.zoomRatio = next;
          this.session.setZoom(next);
          const step = Math.round(next * 2);
          if (step !== this.lastHapticStep) {
            this.lastHapticStep = step;
            this.haptic('haptic.effect.soft');
          }
        })
    )
  }

  // ---- 控制行 ----

  /** 拍照行：关闭 | 快门 | 翻转（iOS captureControls 同款） */
  @Builder
  private captureControls() {
    Row({ space: 26 }) {
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
    .margin({ top: 14 })
  }

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
    .borderRadius(26)
    .backgroundColor(this.theme.cardBackground)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      action();
    })
  }

  // ---- 底部工具条（闪光 + 相纸入口 + 铺开的相纸条） ----

  @Builder
  private bottomBar() {
    Column() {
      Row({ space: 10 }) {
        // 闪光三态（有闪光单元才显示）
        if (this.flashAvailable) {
          this.toolChip(this.flashIcon(), this.flashLabel(),
            this.flashSetting !== FlashSetting.Off, false, (): void => {
              this.cycleFlash();
            })
        }
        this.toolChip($r('sys.symbol.rectangle_stack'), this.paperName(this.selectedPaper),
          this.showPaperStrip, true, (): void => {
            this.togglePaperStrip();
          })
      }
      .padding({ top: 10, bottom: 10 })

      // 相纸条：从工具条底下「推」出来（有方向感才像抽屉）
      if (this.showPaperStrip) {
        this.paperStrip()
      }
    }
    .clip(true)
  }

  /** 工具条胶囊按钮：图标 + 文字，选中态主题强调色反白（iOS toolChip 同款） */
  @Builder
  private toolChip(iconRes: Resource, label: Resource, highlighted: boolean,
    withChevron: boolean, action: () => void) {
    Row({ space: 5 }) {
      SymbolGlyph(iconRes)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor([highlighted ? this.theme.background : this.theme.textSecondary])
      Text(label)
        .fontSize(13)
        .fontColor(highlighted ? this.theme.background : this.theme.textSecondary)
      if (withChevron) {
        SymbolGlyph($r('sys.symbol.chevron_up'))
          .fontSize(9)
          .fontWeight(FontWeight.Medium)
          .fontColor([highlighted ? this.theme.background : this.theme.textSecondary])
          // 铺开时箭头转向下方，指示「再点一下收起」
          .rotate({ angle: this.showPaperStrip ? 180 : 0 })
      }
    }
    .padding({ left: 13, right: 13, top: 7, bottom: 7 })
    .borderRadius(17)
    .backgroundColor(highlighted ? this.theme.accent : this.theme.cardBackground)
    .onClick((): void => {
      action();
    })
  }

  /** 相纸选择条（横向滚动；预览用刚拍到的方图，所见即所得） */
  @Builder
  private paperStrip() {
    Scroll() {
      Row({ space: 20 }) {
        ForEach(CAMERA_PAPER_STYLES, (style: PaperStyle) => {
          Column({ space: 8 }) {
            PaperPreviewCard({
              style: style,
              pixelMap: this.shotPixelMap
            })
              .border({
                width: this.selectedPaper === style ? 2 : 0,
                color: this.theme.accent,
                radius: 10
              })
              .opacity(this.selectedPaper === style ? 1 : 0.55)
            Text(this.paperName(style))
              .fontSize(12)
              .fontColor(this.selectedPaper === style ?
                this.theme.textSecondary : this.theme.textTertiary)
          }
          .onClick((): void => {
            this.pickPaper(style);
          })
        }, (style: PaperStyle) => style)
      }
      .padding({ left: 24, right: 24, top: 8, bottom: 8 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    // 抽屉方向感：从工具条底下推出来（原挂在 Builder 调用点上，Builder 返回 void 链不上）
    .transition(
      TransitionEffect.move(TransitionEdge.BOTTOM)
        .animation({ curve: PAPER_CURVE })
        .combine(TransitionEffect.OPACITY)
    )
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
    };
    this.session.open(context, this.surfaceId).then((ok: boolean): void => {
      this.openingSession = false;
      if (!ok) {
        this.sessionFailed = true;
        return;
      }
      this.authorized = true;
      this.previewAspect = this.session.previewAspect;
      this.flashAvailable = this.session.hasFlashUnit();
      this.session.setFlash(this.flashSetting);
    }).catch((): void => {
      this.openingSession = false;
      this.sessionFailed = true;
    });
  }

  /** 拍到一张：解码中心方形 → 相纸落入取景框 */
  private async handleShot(shot: CameraShot): Promise<void> {
    const square = await decodeCenterSquare(shot.stillBuffer);
    this.capturing = false;
    if (square === undefined) {
      hilog.error(DOMAIN, TAG, 'decodeCenterSquare failed, stay in capture mode');
      return;
    }
    this.capturedShot = shot;
    this.paperTilt = Math.random() * PAPER_TILT_DEGREES * 2 - PAPER_TILT_DEGREES;
    this.getUIContext().animateTo({ curve: PAPER_CURVE }, (): void => {
      this.shotPixelMap = square;
    });
  }

  private capture(): void {
    if (!this.authorized || this.capturing || this.shotPixelMap !== undefined) {
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
  }

  private retake(): void {
    this.capturedShot = undefined;
    this.shotPixelMap = undefined;
  }

  /** 「写下这一刻」：回写默认相纸偏好，交产物给页面插入（文件链由页面跑） */
  private confirmShot(): void {
    const shot = this.capturedShot;
    const square = this.shotPixelMap;
    if (shot === undefined || square === undefined) {
      return;
    }
    this.clearStripTimer();
    AppPrefs.putString(PREF_KEY_DEFAULT_PAPER_STYLE, this.selectedPaper);
    this.session.close();
    this.onCapture(shot, square, this.selectedPaper);
  }

  private closeCamera(): void {
    this.clearStripTimer();
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
      this.session.setZoom(this.zoomRatio);
    }).catch((): void => {
      // 翻转失败保持原样
    });
  }

  private cycleFlash(): void {
    this.haptic('haptic.effect.soft');
    this.flashSetting = nextFlashSetting(this.flashSetting);
    this.session.setFlash(this.flashSetting);
  }

  private togglePaperStrip(): void {
    this.haptic('haptic.effect.soft');
    this.clearStripTimer();
    this.getUIContext().animateTo({ curve: PAPER_CURVE }, (): void => {
      this.showPaperStrip = !this.showPaperStrip;
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

  /** 轻震（vibrator 预设效果；失败静默——震动只是手感，不构成功能） */
  private haptic(effectId: string): void {
    const preset: vibrator.VibratePreset = { type: 'preset', effectId: effectId, count: 1 };
    vibrator.startVibration(preset, { usage: 'touch' }).catch((): void => {
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

  // ---- 文案 / 图标映射 ----

  private flashIcon(): Resource {
    switch (this.flashSetting) {
      case FlashSetting.On:
        return $r('sys.symbol.camera_flash');
      case FlashSetting.Off:
        return $r('sys.symbol.camera_flash_slash');
      default:
        return $r('sys.symbol.camera_flash_auto');
    }
  }

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
