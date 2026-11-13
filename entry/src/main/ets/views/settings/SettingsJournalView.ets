/**
 * 设置 →「日记」二级页（10_BUILD_MANUAL.md 6.1）。对应 iOS `SettingsJournalView.swift`。
 *
 * - 照片相纸样式：推「默认相纸样式」选择页（DefaultPaperStylePickerView），
 *   行值显示当前默认相纸（插照片时预选的那个；05 §3.5）
 * - 拍照方式：尺素相机 / 华为相机两档（问题四；Harmony 专属，iOS 无此项），
 *   行尾值 + 上下小箭头，点值弹行尾小菜单（bindMenu 自定义内容，样式与交互
 *   对齐「位置与天气」页位置精度行——含 iOS 式按住拖划选择；B 攻坚结论：
 *   onDisappear 强制归零兜底，任何路径收起后下次必能重开）
 * - 日记印章 / 封条提醒天数不做（Q10：印章待产品决定、封条提醒死设置）
 * - 「写作统计」不在这页——它是内容页，一级页单列一行（R-SETTINGS-02）
 *
 * 路由：系统路由表（router_map.json → name `JournalSettings`）。
 */
import { uiMaterial } from '@kit.ArkUI';
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AppPrefs, PREF_KEY_DEFAULT_PAPER_STYLE,
  CAMERA_MODE_APP, CAMERA_MODE_SYSTEM } from '../../services/AppPrefs';
import { PaperStyle, paperStyleFromRaw } from '../../models/ContentBlock';

/** 一档拍照方式（值 + 名） */
class CameraModeSpec {
  readonly value: string;
  readonly nameRes: Resource;

  constructor(value: string, nameRes: Resource) {
    this.value = value;
    this.nameRes = nameRes;
  }
}

@Builder
export function SettingsJournalBuilder() {
  SettingsJournalView()
}

@Component
export struct SettingsJournalView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 当前默认相纸（行值；进页读偏好，默认宝丽来，05 §3.5） */
  @State private paperStyle: PaperStyle = PaperStyle.Polaroid;
  /** 拍照方式（行值；进页读偏好，默认尺素相机；非法值按尺素相机兜底） */
  @State private cameraMode: string = CAMERA_MODE_APP;
  /** 拍照方式值切换按钮按压态（按压变淡反馈用） */
  @State private cameraValuePressed: boolean = false;
  /** 拍照方式行尾小菜单显隐（bindMenu isShow，!! 双向） */
  @State private cameraMenuShown: boolean = false;
  /** 拍照方式菜单拖划高亮行下标（-1 无高亮；按下/拖动实时跟手指） */
  @State private cameraMenuPressedIndex: number = -1;
  /** 拍照方式菜单内容全局 top（vp，onAreaChange 缓存，拖划行定位用） */
  private cameraMenuTopVp: number = 0;

  private navPathStack: NavPathStack = new NavPathStack();

  /** 两档固定顺序：尺素相机 → 华为相机 */
  private readonly cameraModes: CameraModeSpec[] = [
    new CameraModeSpec(CAMERA_MODE_APP, $r('app.string.s_7caa485caf')),
    new CameraModeSpec(CAMERA_MODE_SYSTEM, $r('app.string.s_7c9eb079ae'))
  ];

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 20 }) {
            Column() {
              this.paperStyleRow()
              Divider()
                .color(this.theme.border)
                .strokeWidth(0.5)
                .margin({ left: 20 })
              this.cameraModeRow()
              Text($r('app.string.s_07bbd7147c'))
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textTertiary)
                .padding({ left: 20, right: 20, bottom: 14, top: 2 })
                .width('100%')
            }
            .borderRadius(16)
            .backgroundColor(this.theme.settingsCardBackground)
            .width('100%')

            // 底部：手势条让位
            Column().width('100%').height(this.safeAreaBottomVp + 32)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 24, right: 24 })
        }
        .width('100%')
        .layoutWeight(1)
        // 🔴 Scroll 设高度限制后内容小于视口默认居中（官方 FAQ faqs-arkui-725）——必须显式顶对齐
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.safeAreaTopVp })
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.settingsPageBackground)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      this.cameraMode = AppPrefs.currentCameraMode();
    })
    // 从相纸选择页返回时本页未销毁——onShown 每次露出都重读偏好，行值不滞留旧值
    .onShown((): void => {
      const stored = paperStyleFromRaw(
        AppPrefs.getString(PREF_KEY_DEFAULT_PAPER_STYLE, PaperStyle.Polaroid));
      // 非法值按宝丽来兜底（旧数据 / 手改坏了不崩；05 §3.5）
      this.paperStyle = stored === undefined ? PaperStyle.Polaroid : stored;
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题（SettingsAccountView 同款） ----

  @Builder
  private topBar() {
    Stack() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textPrimary])
        }
        .width(34)
        .height(34)
        .padding(0)
        .backgroundColor(this.theme.glassBackground)
        .border({ width: 0.5, color: this.theme.glassBorder })
        .onClick((): void => {
          this.navPathStack.pop();
        })
        Blank()
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text($r('app.string.s_bf50d67138'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textSecondary)
          .letterSpacing(this.theme.letterSpacingWide)
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(TOP_BAR_ROW_HEIGHT_VP)
    .margin({ bottom: TOP_BAR_CONTENT_GAP_VP })
  }

  // ---- 照片相纸样式（插照片预选；推选择页） ----

  @Builder
  private paperStyleRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.picture'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_775660537d'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      Text(this.paperStyleName())
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textTertiary])
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.navPathStack.pushPathByName('DefaultPaperStyle', '');
    })
  }

  /** 相纸显示名（PaperStylePickerSheet 同一张映射表） */
  private paperStyleName(): Resource {
    switch (this.paperStyle) {
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
      case PaperStyle.Polaroid:
      default:
        return $r('app.string.s_f4ae8c66ad');
    }
  }

  // ---- 相机切换（2026-11-12 工单四更名，旧名「拍照方式」；行尾值 + 上下小箭头 + 行尾小菜单） ----

  @Builder
  private cameraModeRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.camera'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_45bf60a6c6'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      // 值切换按钮：玻璃小胶囊（位置精度行同款配方）+ 按压变淡反馈
      Row({ space: 4 }) {
        Text(this.currentCameraMode().nameRes)
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textPrimary)
        Column() {
          SymbolGlyph($r('sys.symbol.chevron_up'))
            .fontSize(8)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textPrimary])
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(8)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textPrimary])
        }
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 8, top: 5, bottom: 5 })
      .borderRadius(13)
      .backgroundColor(this.theme.glassBackground)
      .border({ width: 0.5, color: this.theme.glassBorder })
      .opacity(this.cameraValuePressed ? 0.6 : 1)
      .animation({ duration: 100, curve: Curve.FastOutSlowIn })
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) {
          this.cameraValuePressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.cameraValuePressed = false;
        }
      })
      .onClick((): void => {
        this.cameraMenuShown = true;
      })
      // 行尾小菜单（bindMenu 受控弹出；onDisappear 强制归零兜底——B 攻坚结论：
      // 任何路径收起都回写 false，下次 false→true 跳变必触发重开）
      .bindMenu(!!this.cameraMenuShown, this.cameraMenuBuilder, {
        systemMaterial: new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN
        }),
        onDisappear: (): void => {
          this.cameraMenuShown = false;
        }
      })
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
  }

  // ---- 行尾小菜单内容：iOS 式按住拖划选择（位置精度菜单同款） ----

  @Builder
  private cameraMenuBuilder() {
    Column() {
      ForEach(this.cameraModes, (spec: CameraModeSpec, index: number) => {
        Column() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor([spec.value === this.cameraMode ?
                this.theme.textPrimary : Color.Transparent])
              .width(20)
            Text(spec.nameRes)
              .fontSize(16)
              .fontColor(this.theme.textPrimary)
          }
          .width('100%')
          .height(40)
          .padding({ left: 14 })
          .alignItems(VerticalAlign.Center)
          .borderRadius(12)
          .backgroundColor(this.cameraMenuPressedIndex === index ?
            this.theme.menuPressedBackground : Color.Transparent)
        }
        .width('100%')
        .height(48)
        .padding({ left: 4, right: 4 })
        .justifyContent(FlexAlign.Center)
      }, (spec: CameraModeSpec) => spec.value)
    }
    .width(188)
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      const y = newArea.globalPosition.y;
      if (typeof y === 'number') {
        this.cameraMenuTopVp = y;
      }
    })
    .onTouch((event: TouchEvent): void => {
      this.cameraMenuTouch(event);
    })
  }

  /** 拖划选择：按下/拖动时高亮手指所在行，抬手选中该行并收起；划出菜单抬手不选中 */
  private cameraMenuTouch(event: TouchEvent): void {
    if (event.changedTouches.length === 0) {
      return;
    }
    const touch = event.changedTouches[0];
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      this.cameraMenuPressedIndex = this.cameraMenuRowIndexAt(touch.windowY);
    } else if (event.type === TouchType.Up) {
      const index = this.cameraMenuRowIndexAt(touch.windowY);
      if (index >= 0) {
        this.setCameraMode(this.cameraModes[index].value);
      }
      this.cameraMenuPressedIndex = -1;
      this.cameraMenuShown = false;
    } else if (event.type === TouchType.Cancel) {
      this.cameraMenuPressedIndex = -1;
      this.cameraMenuShown = false;
    }
  }

  /** 手指全局 y → 菜单行下标（48vp 定高行；不在行区返回 -1） */
  private cameraMenuRowIndexAt(windowY: number): number {
    const index = Math.floor((windowY - this.cameraMenuTopVp) / 48);
    if (index >= 0 && index < this.cameraModes.length) {
      return index;
    }
    return -1;
  }

  /** 落偏好并刷新行值（菜单抬手选中时调用） */
  private setCameraMode(mode: string): void {
    this.cameraMode = mode;
    AppPrefs.setCameraMode(mode);
  }

  /** 当前拍照方式档（存值不在名单按尺素相机兜底，与 AppPrefs 同一约定） */
  private currentCameraMode(): CameraModeSpec {
    return AppPrefs.normalizedCameraMode(this.cameraMode) === CAMERA_MODE_SYSTEM
      ? this.cameraModes[1] : this.cameraModes[0];
  }
}
