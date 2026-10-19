/**
 * 位置与天气偏好调试页（10_BUILD_MANUAL.md 2.10 验收用，临时脚手架）。
 * 对应 iOS `Views/Settings/SettingsLocationView.swift` 的核心两项：
 * 「记录位置」开关 + 位置精度三档（市 / 区县 / 街道）。
 * 正式设置页属 6.1；届时重做设置结构，本页随其它 Debug 脚手架一起删。
 */
import { AppTheme } from '../theme/AppTheme';
import { BambooTheme } from '../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP, STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../services/ImmersiveChrome';
import { AppPrefs, PREF_KEY_LOCATION_PRECISION, PREF_KEY_LOCATION_RECORDING_ENABLED } from '../services/AppPrefs';
import {
  LOCATION_PRECISION_CITY,
  LOCATION_PRECISION_DISTRICT,
  LOCATION_PRECISION_STREET
} from '../services/PlaceWeatherFormat';

@Entry
@Component
struct LocationDebug {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @State recordingEnabled: boolean = true;
  @State precision: string = LOCATION_PRECISION_CITY;

  aboutToAppear(): void {
    this.recordingEnabled = AppPrefs.isLocationRecordingEnabled();
    this.precision = AppPrefs.currentLocationPrecision();
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // 标题 + 当前原始值（调试脚手架：直接看偏好里的真值）
          Column({ space: 4 }) {
            Text($r('app.string.s_ef86be8969'))
              .fontSize(this.theme.titleFont.size)
              .fontWeight(this.theme.titleFont.weight)
              .fontFamily(this.theme.titleFont.family)
              .fontColor(this.theme.textPrimary)
            Text(`${PREF_KEY_LOCATION_RECORDING_ENABLED}: ${this.recordingEnabled} · ` +
              `${PREF_KEY_LOCATION_PRECISION}: ${this.precision}`)
              .fontSize(this.theme.captionFont.size)
              .fontColor(this.theme.textTertiary)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 20 })

          // ---- 记录位置开关（R-PLACE-02；关掉后新日记只取天气不留地点）----
          Row() {
            Text($r('app.string.s_81d428a1d8'))
              .fontSize(this.theme.bodyFont.size)
              .fontWeight(this.theme.bodyFont.weight)
              .fontFamily(this.theme.bodyFont.family)
              .fontColor(this.theme.textPrimary)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.recordingEnabled })
              .selectedColor(this.theme.accent)
              .onChange((isOn: boolean): void => {
                this.recordingEnabled = isOn;
                AppPrefs.setLocationRecordingEnabled(isOn);
              })
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })

          // ---- 位置精度三档（只影响之后写的日记，已写的保持原样）----
          Text($r('app.string.s_4e6b4fffe0'))
            .fontSize(this.theme.bodyFont.size)
            .fontWeight(this.theme.bodyFont.weight)
            .fontFamily(this.theme.bodyFont.family)
            .fontColor(this.theme.textPrimary)
            .width('100%')
            .padding({ left: 20, right: 20, top: 8, bottom: 10 })

          Row({ space: 8 }) {
            this.precisionButton(LOCATION_PRECISION_CITY, $r('app.string.s_7c130d80b8'))
            this.precisionButton(LOCATION_PRECISION_DISTRICT, $r('app.string.s_328070e3ac'))
            this.precisionButton(LOCATION_PRECISION_STREET, $r('app.string.s_a671f238f1'))
          }
          .width('100%')
          .padding({ left: 20, right: 20 })

          // ---- 隐私说明（只影响之后写的；数据只存本地）----
          Text($r('app.string.s_81d3179a26'))
            .fontSize(this.theme.captionFont.size)
            .fontColor(this.theme.textTertiary)
            .width('100%')
            .padding({ left: 20, right: 20, top: 20 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: this.safeAreaTopVp, bottom: this.safeAreaBottomVp + 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }

  /** 精度档按钮：当前档描边强调（主题调试页同款样式） */
  @Builder
  private precisionButton(value: string, label: Resource) {
    Button(label)
      .fontSize(this.theme.bodyFont.size)
      .fontColor(this.precision === value ? this.theme.accent : this.theme.textSecondary)
      .backgroundColor(this.theme.surfaceBackground)
      .border({
        width: this.precision === value ? 2 : 1,
        color: this.precision === value ? this.theme.accent : this.theme.border
      })
      .borderRadius(10)
      .layoutWeight(1)
      .onClick((): void => {
        this.precision = value;
        AppPrefs.setLocationPrecision(value);
      })
  }
}
