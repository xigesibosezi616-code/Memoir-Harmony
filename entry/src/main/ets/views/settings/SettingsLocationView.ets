/**
 * 设置 →「位置与天气」二级页（10_BUILD_MANUAL.md 6.1）。
 * 对应 iOS `SettingsLocationView.swift`。
 *
 * - 记录位置：开关（`locationRecordingEnabled`，默认开；关掉只影响日记记不记地点，
 *   **天气照常获取**——iOS 注释同款）
 * - 位置精度：市 / 区县 / 街道三档（`locationPrecision`，默认 city），
 *   行尾值 + 上下小箭头，点值弹行尾小菜单（bindMenu 自定义内容，U19 R-SETTINGS-13：
 *   当前项前面打勾；2026-11-08 用户要求选项能划动选择——官方 Array<MenuElement>
 *   与系统菜单实测都只支持点击，改自绘菜单内容实现 iOS 式按住拖划选择）；
 *   当前档的说明文案跟在行下；开关关了整行收起
 *
 * 路由：系统路由表（router_map.json → name `LocationSettings`）。
 */
import { uiMaterial } from '@kit.ArkUI';
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AppPrefs, PREF_KEY_LOCATION_RECORDING_ENABLED,
  PREF_KEY_LOCATION_PRECISION } from '../../services/AppPrefs';
import { LOCATION_PRECISION_CITY, LOCATION_PRECISION_DISTRICT,
  LOCATION_PRECISION_STREET } from '../../services/PlaceWeatherFormat';

/** 一档位置精度（值 + 名 + 说明词条） */
class PrecisionSpec {
  readonly value: string;
  readonly nameRes: Resource;
  readonly detailRes: Resource;

  constructor(value: string, nameRes: Resource, detailRes: Resource) {
    this.value = value;
    this.nameRes = nameRes;
    this.detailRes = detailRes;
  }
}

@Builder
export function SettingsLocationBuilder() {
  SettingsLocationView()
}

@Component
export struct SettingsLocationView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 记录位置开关（进页读偏好，之后只由 Toggle 改） */
  @State private recordingOn: boolean = true;
  /** 位置精度三档（city / district / street；非法值按 city 兜底） */
  @State private precision: string = LOCATION_PRECISION_CITY;
  /** 位置精度值切换按钮按压态（按压变淡反馈用） */
  @State private precisionValuePressed: boolean = false;
  /** 位置精度行尾小菜单显隐（bindMenu isShow，!! 双向：系统收起也回写 false） */
  @State private locationMenuShown: boolean = false;
  /** 位置精度菜单拖划高亮行下标（-1 无高亮；按下/拖动实时跟手指） */
  @State private locationMenuPressedIndex: number = -1;
  /** 位置精度菜单内容全局 top（vp，onAreaChange 缓存，拖划行定位用） */
  private locationMenuTopVp: number = 0;

  private navPathStack: NavPathStack = new NavPathStack();

  /** 三档固定顺序：市 → 区县 → 街道（精细程度递增；iOS allCases 同序） */
  private readonly precisions: PrecisionSpec[] = [
    new PrecisionSpec(LOCATION_PRECISION_CITY,
      $r('app.string.s_7c130d80b8'), $r('app.string.s_1335fc30b7')),
    new PrecisionSpec(LOCATION_PRECISION_DISTRICT,
      $r('app.string.s_328070e3ac'), $r('app.string.s_24f71d98ec')),
    new PrecisionSpec(LOCATION_PRECISION_STREET,
      $r('app.string.s_a671f238f1'), $r('app.string.s_ff12ea562c'))
  ];

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 20 }) {
            Column() {
              this.recordingRow()
              if (this.recordingOn) {
                Divider()
                  .color(this.theme.border)
                  .strokeWidth(0.5)
                  .margin({ left: 20 })
                this.precisionRow()
                Text(this.currentPrecision().detailRes)
                  .fontSize(this.theme.labelFont.size)
                  .fontWeight(this.theme.labelFont.weight)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textTertiary)
                  .padding({ left: 20, right: 20, bottom: 14, top: 2 })
                  .width('100%')
              }
            }
            .borderRadius(16)
            .backgroundColor(this.theme.settingsCardBackground)
            .width('100%')

            // footer：位置只在本机、改动只影响之后的日记（iOS 同款）
            Text($r('app.string.s_81d3179a26'))
              .fontSize(this.theme.labelFont.size)
              .fontWeight(this.theme.labelFont.weight)
              .fontFamily(this.theme.labelFont.family)
              .fontColor(this.theme.textTertiary)
              .padding({ left: 8, right: 8 })

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
      this.recordingOn = AppPrefs.isLocationRecordingEnabled();
      this.precision = AppPrefs.currentLocationPrecision();
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
        Text($r('app.string.s_ef86be8969'))
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

  // ---- 记录位置开关（关掉只影响地点，天气照常） ----

  @Builder
  private recordingRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.local'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_81d428a1d8'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.recordingOn })
        .selectedColor(this.theme.accent)
        .onChange((isOn: boolean) => {
          this.recordingOn = isOn;
          AppPrefs.setLocationRecordingEnabled(isOn);
        })
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
  }

  // ---- 位置精度（行尾值 + 上下小箭头 + 行尾小菜单，U19 R-SETTINGS-13） ----

  @Builder
  private precisionRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.scope'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_4e6b4fffe0'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      // 值切换按钮：玻璃小胶囊（settings 各页返回钮同款配方：glassBackground 底 +
      //  0.5vp glassBorder + textPrimary 文字，2026-11-08 用户反馈按钮看不清后逐主题拉明度差）
      //  + 按压变淡反馈，让用户一眼看出可以点这里切换
      Row({ space: 4 }) {
        Text(this.currentPrecision().nameRes)
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
      .opacity(this.precisionValuePressed ? 0.6 : 1)
      .animation({ duration: 100, curve: Curve.FastOutSlowIn })
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) {
          this.precisionValuePressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.precisionValuePressed = false;
        }
      })
      .onClick((): void => {
        this.locationMenuShown = true;
      })
      // 行尾小菜单（U19 R-SETTINGS-13）：bindMenu 自定义内容受控弹出（isShow 自
      // API 18 支持 !! 双向绑定），容器仍是系统 Menu——定位/收起/THIN 沉浸光感
      // 全官方（MenuOptions 继承 ContextMenuOptions，systemMaterial 可用）
      .bindMenu(!!this.locationMenuShown, this.locationMenuBuilder, {
        systemMaterial: new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN
        })
      })
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
  }

  // ---- 行尾小菜单内容：iOS 式按住拖划选择（2026-11-08 用户要求「能划动选择」；
  //  官方 Array<MenuElement> 菜单与系统菜单实测都只支持点击选择，自绘内容补齐） ----

  @Builder
  private locationMenuBuilder() {
    Column() {
      ForEach(this.precisions, (spec: PrecisionSpec, index: number) => {
        Column() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor([spec.value === this.precision ?
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
          .backgroundColor(this.locationMenuPressedIndex === index ?
            this.theme.menuPressedBackground : Color.Transparent)
        }
        .width('100%')
        .height(48)
        .padding({ left: 4, right: 4 })
        .justifyContent(FlexAlign.Center)
      }, (spec: PrecisionSpec) => spec.value)
    }
    .width(188)
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      const y = newArea.globalPosition.y;
      if (typeof y === 'number') {
        this.locationMenuTopVp = y;
      }
    })
    .onTouch((event: TouchEvent): void => {
      this.locationMenuTouch(event);
    })
  }

  /** 拖划选择：按下/拖动时高亮手指所在行，抬手选中该行并收起（iOS 菜单同款交互；
   *  划出菜单抬手不选中，菜单由系统保持/点外收起） */
  private locationMenuTouch(event: TouchEvent): void {
    if (event.changedTouches.length === 0) {
      return;
    }
    const touch = event.changedTouches[0];
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      this.locationMenuPressedIndex = this.locationMenuRowIndexAt(touch.windowY);
    } else if (event.type === TouchType.Up) {
      const index = this.locationMenuRowIndexAt(touch.windowY);
      if (index >= 0) {
        this.setPrecision(this.precisions[index].value);
      }
      this.locationMenuPressedIndex = -1;
      this.locationMenuShown = false;
    } else if (event.type === TouchType.Cancel) {
      this.locationMenuPressedIndex = -1;
      this.locationMenuShown = false;
    }
  }

  /** 手指全局 y → 菜单行下标（48vp 定高行；不在行区返回 -1） */
  private locationMenuRowIndexAt(windowY: number): number {
    const index = Math.floor((windowY - this.locationMenuTopVp) / 48);
    if (index >= 0 && index < this.precisions.length) {
      return index;
    }
    return -1;
  }

  /** 落偏好并刷新行值（菜单抬手选中时调用） */
  private setPrecision(precision: string): void {
    this.precision = precision;
    AppPrefs.setLocationPrecision(precision);
  }

  /** 当前精度档（存值不在名单按市兜底，与 AppPrefs 同一约定） */
  private currentPrecision(): PrecisionSpec {
    const normalized = AppPrefs.normalizedLocationPrecision(this.precision);
    if (normalized === LOCATION_PRECISION_DISTRICT) {
      return this.precisions[1];
    }
    if (normalized === LOCATION_PRECISION_STREET) {
      return this.precisions[2];
    }
    return this.precisions[0];
  }
}
