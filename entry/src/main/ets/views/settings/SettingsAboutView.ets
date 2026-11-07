/**
 * 设置 →「关于」二级页（10_BUILD_MANUAL.md 5.8 + 6.7 合规展示）。
 * 对应 iOS `Views/Settings/SettingsAboutView.swift`。
 *
 * - 6.7：隐私政策 / 用户协议两行推内置阅读页（rawfile 正文，不联网，R-APP-04）；
 *   ICP 备案号与主办单位页中展示（R-APP-05，常量见 `environment/ComplianceInfo.ets`）；
 *   页底 Memoir / by Sinara 品牌落款（品牌名不翻译）
 *
 * - 版本行常驻（值取 hvigor 生成的 BuildProfile.VERSION_NAME，官方「获取构建参数」）
 * - 「测试构建」分组只在测试包（debug 构建）里存在：BuildProfile.DEBUG 编译期定死，
 *   **正式（release）构建里回信加速开关不存在、不生效**（5.8 验收）
 * - 回信加速：1 分钟 ≈ 1 天（6 小时 ≈ 15 秒、3 天 ≈ 3 分钟），默认开
 *   （iOS 2026-10-17 产品要求：测试的人不会去「关于」里找开关），
 *   只影响开启后寄出的信（到达时刻寄出时就已算好）
 * - 偏好走 AppPrefs（`debugFastLetterDelivery`，与 iOS 键同名）
 *
 * 路由：系统路由表（router_map.json → name `About`），设置页关于行推入。
 */
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AppPrefs } from '../../services/AppPrefs';
import { LetterDelivery } from '../../models/LetterDelivery';
import BuildProfile from 'entry/BuildProfile';
import { ComplianceInfo } from '../../environment/ComplianceInfo';

@Builder
export function SettingsAboutBuilder() {
  SettingsAboutView()
}

@Component
export struct SettingsAboutView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 回信加速开关（仅测试包渲染；初始值进页时从偏好读，之后只由 Toggle 改） */
  @State private fastDeliveryOn: boolean = true;

  private navPathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 20 }) {
            // 合规展示组（6.7）。iOS 注释原话：两行必须真能点开（上架清单 A6），
            // 审核必查、链接打不开直接拒；正文走 rawfile 不联网（R-APP-04）
            Column() {
              this.legalRow($r('app.string.s_8c276c1fea'), $r('sys.symbol.info_shield'), 'Privacy')
              this.rowDivider()
              this.legalRow($r('app.string.s_0399ad7167'), $r('sys.symbol.doc_text'), 'Terms')
              this.rowDivider()
              this.versionRow()
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor(this.theme.settingsCardBackground)

            // ICP 备案号与主办单位（R-APP-05：国内合规硬性要求；footer 不是行——给监管看的）
            Column({ space: 3 }) {
              Text(ComplianceInfo.ICP_LICENSE)
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textTertiary)
              Text(ComplianceInfo.COMPANY_NAME)
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textTertiary)
            }
            .alignItems(HorizontalAlign.Center)
            .width('100%')
            .padding({ top: 4 })

            // 「测试构建」分组：只在测试包里存在（5.8 验收：正式构建里搜不到这个开关）
            if (LetterDelivery.isTestBuild) {
              Text($r('app.string.s_ea5026fc0f'))
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textTertiary)
                .letterSpacing(this.theme.letterSpacingWide)
                .padding({ left: 8 })

              Row({ space: 10 }) {
                Text($r('app.string.s_f93c4db3ab'))
                  .fontSize(this.theme.bodyFont.size)
                  .fontWeight(this.theme.bodyFont.weight)
                  .fontFamily(this.theme.bodyFont.family)
                  .fontColor(this.theme.textPrimary)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.fastDeliveryOn })
                  .selectedColor(this.theme.accent)
                  .onChange((isOn: boolean) => {
                    this.fastDeliveryOn = isOn;
                    AppPrefs.setDebugFastLetterDelivery(isOn);
                  })
              }
              .width('100%')
              .padding({ top: 15, bottom: 15, left: 20, right: 20 })
              .alignItems(VerticalAlign.Center)
              .borderRadius(16)
              .backgroundColor(this.theme.settingsCardBackground)
              .width('100%')

              Text($r('app.string.s_bdfe921dd3'))
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textTertiary)
                .padding({ left: 8, right: 8 })
            }

            // 页底品牌落款（iOS：Memoir / by Sinara；品牌名不翻译）
            Column({ space: 4 }) {
              Text('Memoir')
                .fontSize(this.theme.captionFont.size)
                .fontWeight(this.theme.captionFont.weight)
                .fontFamily(this.theme.captionFont.family)
                .fontColor(this.theme.textTertiary)
              Text('by Sinara')
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textTertiary)
            }
            .alignItems(HorizontalAlign.Center)
            .width('100%')
            .padding({ top: 8 })

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
      this.fastDeliveryOn = AppPrefs.isDebugFastLetterDeliveryOn();
    })
  }

  // ---- 行零件 ----

  /** 协议行（6.7）：图标 + 标题 + chevron，点了推内置阅读页（Privacy / Terms） */
  @Builder
  private legalRow(titleRes: Resource, iconRes: Resource, routeName: string) {
    Row({ space: 10 }) {
      SymbolGlyph(iconRes)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text(titleRes)
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textTertiary])
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.navPathStack.pushPathByName(routeName, '');
    })
  }

  /** 组内分隔线（SettingsTabView rowDivider 同款：左端对齐行文字 = 卡内边距 20 + 图标 20 + 间距 10） */
  @Builder
  private rowDivider() {
    Divider()
      .color(this.theme.border)
      .strokeWidth(0.5)
      .margin({ left: 50, right: 20 })
  }

  /** 版本行（常驻；值取构建参数） */
  @Builder
  private versionRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_989d1affa0'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      Text(BuildProfile.VERSION_NAME)
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
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
        Text($r('app.string.s_bed172efc9'))
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
      // 纯展示层全宽盖在按钮行上，触摸穿透给下面的返回钮
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(TOP_BAR_ROW_HEIGHT_VP)
    .margin({ bottom: TOP_BAR_CONTENT_GAP_VP })
  }
}
