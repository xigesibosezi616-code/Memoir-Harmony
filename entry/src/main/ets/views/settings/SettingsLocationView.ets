/**
 * 设置 →「位置与天气」二级页（10_BUILD_MANUAL.md 6.1）。
 * 对应 iOS `SettingsLocationView.swift`。
 *
 * - 记录位置：开关（`locationRecordingEnabled`，默认开；关掉只影响日记记不记地点，
 *   **天气照常获取**——iOS 注释同款）
 * - 位置精度：市 / 区县 / 街道三档（`locationPrecision`，默认 city），
 *   行尾值 + 上下小箭头，点击弹行尾小菜单（bindMenu，U19 R-SETTINGS-13：
 *   当前项前面打勾、点菜单内外收起）；当前档的说明文案跟在行下；开关关了整行收起
 *
 * 路由：系统路由表（router_map.json → name `LocationSettings`）。
 */
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
      SymbolGlyph($r('sys.symbol.compass'))
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
      Row({ space: 4 }) {
        Text(this.currentPrecision().nameRes)
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textTertiary)
        Column() {
          SymbolGlyph($r('sys.symbol.chevron_up'))
            .fontSize(7)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textTertiary])
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(7)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textTertiary])
        }
      }
      .alignItems(VerticalAlign.Center)
      .bindMenu(this.precisionMenu, {
        placement: Placement.BottomLeft,
        backgroundColor: this.theme.settingsCardBackground,
        borderRadius: 14
      })
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
  }

  /** 行尾小菜单（值下方弹出）：当前项前面打勾；点菜单内选项 / 点菜单外都收起（bindMenu 内建） */
  @Builder
  private precisionMenu() {
    Column() {
      ForEach(this.precisions, (spec: PrecisionSpec) => {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.accent])
            .width(16)
            .visibility(spec.value === this.currentPrecision().value ?
              Visibility.Visible : Visibility.Hidden)
          Text(spec.nameRes)
            .fontSize(15)
            .fontColor(this.theme.textPrimary)
            .maxLines(1)
        }
        .padding({ left: 14, right: 20, top: 12, bottom: 12 })
        .width('100%')
        .onClick((): void => {
          this.setPrecision(spec.value);
        })
      }, (spec: PrecisionSpec) => spec.value)
    }
    .width(150)
    .alignItems(HorizontalAlign.Start)
  }

  /** 落偏好并刷新行值（ActionSheet 各项 action 里各自调用） */
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
