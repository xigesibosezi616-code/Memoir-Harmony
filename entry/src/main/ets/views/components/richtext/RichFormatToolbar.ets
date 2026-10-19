/**
 * 富文本格式工具条（10_BUILD_MANUAL.md 2.5）。视觉沿用初版（iOS 对照）：
 * 通栏主题底 + 顶部 0.5 Divider，居中四盏灯 38×44 圆角 8，
 * 亮灯 = 主文字色 10% 透明底（colorWithAlpha）。
 *
 * 本轮保留的三项改进：
 * - 贴键盘：官方配方 window.on('keyboardHeightChange')（FAQ「如何实现键盘上方自定义工具栏」）
 *   —— 键盘弹出时底部内边距归零（随 RESIZE_WITH_CARET 压缩自然贴键盘顶，无大空隙），
 *   收起时落回手势条安全区上沿
 * - 灯态由工具条直连 RichBodyController 镜像成内部 @State：灯变化只重渲染工具条，
 *   不再触发页面整棵 build（点按卡顿根因）
 * - 按压 0ms 弹簧缩放反馈（静止态视觉不变，只改点按手感）
 */
import { window } from '@kit.ArkUI';
import { curves } from '@kit.ArkUI';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../../services/ImmersiveChrome';
import { PHOTO_LIMIT_PER_ENTRY, AUDIO_LIMIT_PER_ENTRY } from '../../../models/ContentBlock';
import { RichBodyController, RichFormatKind } from './RichBodyEditor';
import { colorWithAlpha } from './RichTextAppearance';

/** 按压反馈弹簧曲线：快速压扁 + 轻微回弹（velocity, mass, stiffness, damping） */
const PRESS_CURVE = curves.springCurve(0, 1, 420, 28);

/** 一盏格式灯：图标 + 无障碍标签 + 亮灭 */
@Component
struct RichFormatButton {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Prop isOn: boolean;
  /** 不可用（如照片满 5 张 / 录音满 3 段）：降透明度、不响应；成员不能叫 enabled（撞 .enabled() 属性方法）。
   * 必须 @Prop：父级 photoEnabled / audioEnabled 是 @State，普通成员只在构建时取一次值，
   * 满 3 段后 mic 键不置灰（真机实测回归） */
  @Prop buttonEnabled: boolean = true;
  @State pressed: boolean = false;
  iconRes: Resource = $r('sys.symbol.bold');
  labelRes: Resource = $r('app.string.s_f670b2adc0');
  onTap: () => void = (): void => {};

  build() {
    Row() {
      SymbolGlyph(this.iconRes)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textPrimary])
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .width(38)
    .height(44)
    .borderRadius(8)
    // 亮灯：主文字色 10% 透明度打底（iOS 同款轻底色）
    .backgroundColor(this.isOn ? colorWithAlpha(this.theme.textPrimary, 0x1A)
      : (this.pressed ? colorWithAlpha(this.theme.textPrimary, 0x0F) : Color.Transparent))
    .scale({ x: this.pressed ? 0.92 : 1, y: this.pressed ? 0.92 : 1 })
    .animation({ curve: PRESS_CURVE })
    .opacity(this.buttonEnabled ? 1 : 0.3)
    .accessibilityText(this.labelRes)
    .onClick((): void => {
      if (this.buttonEnabled) {
        this.onTap();
      }
    })
    .onTouch((event: TouchEvent): void => {
      if (!this.buttonEnabled) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
  }
}

/** 四盏灯一排（加粗 / 斜体 / 小标题 / 荧光笔，顺序与 iOS 一致），初版通栏样式 */
@Component
export struct RichFormatToolbar {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  controller: RichBodyController = new RichBodyController();
  /** 键盘弹出（keyboardHeightChange 高度 > 0）：底部内边距归零贴键盘，否则留安全区 */
  @State keyboardOpen: boolean = false;
  /** 灯态镜像（内部 @State：controller.onFlagsChange 里刷新，只重渲染本组件） */
  @State isBoldOn: boolean = false;
  @State isItalicOn: boolean = false;
  @State isHeadingOn: boolean = false;
  @State isHighlightOn: boolean = false;
  /** 照片按钮可否按（满 5 张置灰，05 §3.6） */
  @State photoEnabled: boolean = true;
  /** 录音按钮可否按（满 3 段置灰，R-ENTRY-08） */
  @State audioEnabled: boolean = true;
  /** 点拍照按钮（页面开尺素相机，2.9） */
  onCameraButtonTap: () => void = (): void => {};
  /** 点照片按钮（页面接相册选图 → 选相纸，2.6） */
  onPhotoButtonTap: () => void = (): void => {};
  /** 点录音按钮（页面先申请麦克风权限 → 开录音面板，2.7） */
  onMicButtonTap: () => void = (): void => {};
  /** 主窗口句柄（键盘高度监听用；aboutToDisappear 注销） */
  private mainWindow: window.Window | undefined = undefined;

  aboutToAppear(): void {
    this.controller.onFlagsChange = (): void => {
      this.syncLamps();
    };
    this.syncLamps();
    // 官方贴键盘配方：监听键盘高度（RESIZE_WITH_CARET 下页面已压到键盘上方，
    // 键盘弹出时把底部安全区内边距归零即可贴住键盘顶，消除 ~安全区高度的大空隙）
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      window.getLastWindow(context).then((win: window.Window): void => {
        this.mainWindow = win;
        win.on('keyboardHeightChange', (height: number): void => {
          this.keyboardOpen = height > 0;
        });
      }).catch((): void => {
        // 取不到窗口（极端场景）：保持安全区内边距，不阻塞功能
      });
    }
  }

  aboutToDisappear(): void {
    if (this.mainWindow !== undefined) {
      this.mainWindow.off('keyboardHeightChange');
      this.mainWindow = undefined;
    }
  }

  private syncLamps(): void {
    this.isBoldOn = this.controller.isBold;
    this.isItalicOn = this.controller.isItalic;
    this.isHeadingOn = this.controller.isHeading;
    this.isHighlightOn = this.controller.isHighlighted;
    this.photoEnabled = this.controller.photoCount() < PHOTO_LIMIT_PER_ENTRY;
    this.audioEnabled = this.controller.audioCount() < AUDIO_LIMIT_PER_ENTRY;
  }

  build() {
    Column() {
      Divider()
        .strokeWidth(0.5)
        .color(this.theme.border)
      // 2026-10-19 真机回归：键 42 + 间距 4 时内容 ~342vp 超出屏宽余量
      // （345.6−40 内边距 = 305.6），录音键被顶到屏幕边缘。收窄为
      // 键 38 + 间距 3 + 分隔线边距 8 + 条内边距 16 → 内容 ~303.5vp，
      // 345.6−32 = 313.6 内放得下，两侧余 ~10vp（写日记 / 编辑页共用）
      Row({ space: 3 }) {
        RichFormatButton({
          iconRes: $r('sys.symbol.bold'),
          labelRes: $r('app.string.s_f670b2adc0'),
          isOn: this.isBoldOn,
          onTap: (): void => {
            this.controller.toggle(RichFormatKind.Bold);
          }
        })
        RichFormatButton({
          iconRes: $r('sys.symbol.italic'),
          labelRes: $r('app.string.s_af5a2c8bff'),
          isOn: this.isItalicOn,
          onTap: (): void => {
            this.controller.toggle(RichFormatKind.Italic);
          }
        })
        RichFormatButton({
          iconRes: $r('sys.symbol.textformat_size_square'),
          labelRes: $r('app.string.s_bb7874b421'),
          isOn: this.isHeadingOn,
          onTap: (): void => {
            this.controller.toggle(RichFormatKind.Heading);
          }
        })
        RichFormatButton({
          iconRes: $r('sys.symbol.highlighter_line'),
          labelRes: $r('app.string.s_67a01a5a15'),
          isOn: this.isHighlightOn,
          onTap: (): void => {
            this.controller.toggle(RichFormatKind.Highlight);
          }
        })
        // 拍照（2.9）：四灯右侧分隔线后先拍照键再相册键（iOS 工具条顺序 camera → photo → mic）
        Divider()
          .vertical(true)
          .strokeWidth(0.5)
          .color(colorWithAlpha(this.theme.textTertiary, 0x40))
          .height(20)
          .margin({ left: 8, right: 8 })
        RichFormatButton({
          iconRes: $r('sys.symbol.camera'),
          labelRes: $r('app.string.s_3da4b3651a'),
          isOn: false,
          buttonEnabled: this.photoEnabled,
          onTap: (): void => {
            this.onCameraButtonTap();
          }
        })
        // 相册（2.6）
        RichFormatButton({
          iconRes: $r('sys.symbol.picture'),
          labelRes: $r('app.string.s_7945500987'),
          isOn: false,
          buttonEnabled: this.photoEnabled,
          onTap: (): void => {
            this.onPhotoButtonTap();
          }
        })
        // 录音（2.7）：照片键右边（iOS 工具条顺序 photo → mic）
        RichFormatButton({
          iconRes: $r('sys.symbol.mic'),
          labelRes: $r('app.string.s_3ba60ad590'),
          isOn: false,
          buttonEnabled: this.audioEnabled,
          onTap: (): void => {
            this.onMicButtonTap();
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .backgroundColor(this.theme.background)
    .padding({
      left: 16,
      right: 16,
      bottom: this.keyboardOpen ? 0 : this.safeAreaBottomVp
    })
  }
}
