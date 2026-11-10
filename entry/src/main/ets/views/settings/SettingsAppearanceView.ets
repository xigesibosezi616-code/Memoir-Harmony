/**
 * 设置 →「外观」二级页（10_BUILD_MANUAL.md 6.1）。对应 iOS `SettingsAppearanceView.swift`。
 *
 * - 主题选择：推 6.2 的主题选择页（6.2 已接路由）
 * - 应用图标：推 6.2 的图标选择页（行值显示「跟随主题」/ 当前固定的图标名）
 * - 启动动画：开关（`showSplashAnimation`，与 iOS 键同名；EntryAbility 启动时
 *   合并算 `showSplash`，这里只写偏好，下次启动生效）
 * - 手记页：大屏 / 列表（`homeDisplayMode`，U07 R-HOME-11 默认大屏）；
 *   行尾值 + 上下小箭头，点值弹行尾小菜单（bindMenu 自定义内容，U19 R-SETTINGS-13：
 *   当前项前面打勾；2026-11-08 用户要求选项能划动选择——官方 Array<MenuElement>
 *   与系统菜单实测都只支持点击，改自绘菜单内容实现 iOS 式按住拖划选择；
 *   行图标跟着当前选的换，ICONS.md 178-179），
 *   当前模式的说明文案跟在行下
 * - 「语言」不在这页——一级页单列一行直通选择页（R-SETTINGS-02）
 * - 封条提醒天数 / Live Photo 同步不做（Q10 死设置）
 *
 * 路由：系统路由表（router_map.json → name `Appearance`）。
 */
import { uiMaterial } from '@kit.ArkUI';
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME, STORAGE_KEY_THEME_MANAGER, ThemeManager } from '../../theme/ThemeManager';
import { ThemePaper } from '../../theme/ThemePaper';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { AppPrefs, PREF_KEY_SHOW_SPLASH_ANIMATION,
  HOME_DISPLAY_MODE_SHOWCASE, HOME_DISPLAY_MODE_LIST } from '../../services/AppPrefs';

/** 手记页展示方式一行描述（大屏 / 列表 + 取值 + 说明词条） */
class HomeModeSpec {
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
export function SettingsAppearanceBuilder() {
  SettingsAppearanceView()
}

@Component
export struct SettingsAppearanceView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 启动动画开关（进页读偏好，之后只由 Toggle 改） */
  @State private splashOn: boolean = true;
  /** 手记页展示方式（showcase / list；非法值按大屏兜底，与 AppPrefs 同一约定） */
  @State private homeMode: string = HOME_DISPLAY_MODE_SHOWCASE;
  /** 手记页值切换按钮按压态（按压变淡反馈用） */
  @State private homeModeValuePressed: boolean = false;
  /** 手记页行尾小菜单显隐（bindMenu isShow，!! 双向：系统收起也回写 false） */
  @State private homeMenuShown: boolean = false;
  /** 手记页菜单拖划高亮行下标（-1 无高亮；按下/拖动实时跟手指） */
  @State private homeMenuPressedIndex: number = -1;
  /** 手记页菜单内容全局 top（vp，onAreaChange 缓存，拖划行定位用） */
  private homeMenuTopVp: number = 0;
  /** 应用图标选择（'' = 跟随主题；行值显示用） */
  @State private iconSelection: string = '';

  private navPathStack: NavPathStack = new NavPathStack();

  /** 两种展示方式固定顺序：大屏在前（默认值），列表在后（iOS Picker 顺序同款） */
  private readonly homeModes: HomeModeSpec[] = [
    new HomeModeSpec(HOME_DISPLAY_MODE_SHOWCASE,
      $r('app.string.s_1ab35f0df8'), $r('app.string.s_41984afcd9')),
    new HomeModeSpec(HOME_DISPLAY_MODE_LIST,
      $r('app.string.s_d46f82fdf0'), $r('app.string.s_755eaf62bd'))
  ];

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 20 }) {
            // 主题 + 应用图标 + 启动动画
            Column() {
              this.themeRow()
              Divider()
                .color(this.theme.border)
                .strokeWidth(0.5)
                .margin({ left: 20 })
              this.appIconRow()
              Divider()
                .color(this.theme.border)
                .strokeWidth(0.5)
                .margin({ left: 20 })
              this.splashRow()
            }
            .borderRadius(16)
            .backgroundColor(this.theme.settingsCardBackground)
            .width('100%')

            // 手记页展示方式（当前模式的说明文案跟在行下）
            Column() {
              this.homeModeRow()
              Text(this.currentHomeMode().detailRes)
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

            // 大屏模式的长按指定封面提示（iOS footer 同款）
            Text($r('app.string.s_1ffe69200e'))
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
      this.splashOn = AppPrefs.getBool(PREF_KEY_SHOW_SPLASH_ANIMATION, true);
      this.homeMode = AppPrefs.currentHomeDisplayMode();
      this.refreshIconSelection();
    })
    .onShown((): void => {
      // 从图标选择页返回时刷新行值（onReady 只在首次挂载时跑）
      this.refreshIconSelection();
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
        Text($r('app.string.s_09b58aa342'))
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

  // ---- 主题选择（6.2 接路由；本卡先立行） ----

  @Builder
  private themeRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.paintbrush'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_ad8012ee9f'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textTertiary])
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.navPathStack.pushPathByName('ThemePicker', '');
    })
  }

  // ---- 应用图标（行值：跟随主题 / 当前固定的图标名；6.2 图标选择页） ----

  @Builder
  private appIconRow() {
    Row({ space: 10 }) {
      // 鸿蒙官方 symbol 无 app.badge（resource-name-check 实证），四宫格是最接近「应用图标」的官方图标
      SymbolGlyph($r('sys.symbol.square_grid_2x2'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_f93d423da3'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      Text(this.iconSelectionValueRes())
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
      this.navPathStack.pushPathByName('AppIconPicker', '');
    })
  }

  /** 行值词条：跟随主题显示「跟随主题」，固定了显示那个图标（=主题）的名字 */
  private iconSelectionValueRes(): Resource {
    for (const paper of ThemePaper.all) {
      if (this.iconSelection === paper.id) {
        return paper.nameRes;
      }
    }
    return $r('app.string.s_cb7f4c5817');
  }

  /** 从 ThemeManager 读当前图标选择（'' = 跟随主题） */
  private refreshIconSelection(): void {
    const manager = AppStorage.get<ThemeManager>(STORAGE_KEY_THEME_MANAGER);
    this.iconSelection = manager !== undefined ? manager.appIconSelection : '';
  }

  // ---- 启动动画开关 ----

  @Builder
  private splashRow() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.wand_and_stars'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_72d04e5cd0'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.splashOn })
        .selectedColor(this.theme.accent)
        .onChange((isOn: boolean) => {
          this.splashOn = isOn;
          AppPrefs.putBool(PREF_KEY_SHOW_SPLASH_ANIMATION, isOn);
        })
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
  }

  // ---- 手记页展示方式：行尾值 + 上下小箭头 + 行尾小菜单（U19 R-SETTINGS-13） ----

  @Builder
  private homeModeRow() {
    Row({ space: 10 }) {
      SymbolGlyph(this.homeModeIcon())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.theme.textSecondary])
        .width(20)
      Text($r('app.string.s_712c2ff8d3'))
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      // 值切换按钮：玻璃小胶囊（settings 各页返回钮同款配方：glassBackground 底 +
      //  0.5vp glassBorder + textPrimary 文字，2026-11-08 用户反馈按钮看不清后逐主题拉明度差）
      //  + 按压变淡反馈，让用户一眼看出可以点这里切换
      Row({ space: 4 }) {
        Text(this.currentHomeMode().nameRes)
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
      .opacity(this.homeModeValuePressed ? 0.6 : 1)
      .animation({ duration: 100, curve: Curve.FastOutSlowIn })
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) {
          this.homeModeValuePressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.homeModeValuePressed = false;
        }
      })
      .onClick((): void => {
        this.homeMenuShown = true;
      })
      // 行尾小菜单（U19 R-SETTINGS-13）：bindMenu 自定义内容受控弹出（isShow 自
      // API 18 支持 !! 双向绑定），容器仍是系统 Menu——定位/收起/THIN 沉浸光感
      // 全官方（MenuOptions 继承 ContextMenuOptions，systemMaterial 可用）
      .bindMenu(!!this.homeMenuShown, this.homeMenuBuilder, {
        systemMaterial: new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN
        })
      })
    }
    .width('100%')
    .padding({ top: 15, bottom: 15, left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
  }

  /** 手记页行图标：大屏 rectangle_on_rectangle / 列表 list_bullet（跟着当前选的换） */
  private homeModeIcon(): Resource {
    if (this.homeMode === HOME_DISPLAY_MODE_LIST) {
      return $r('sys.symbol.list_bullet');
    }
    return $r('sys.symbol.rectangle_on_rectangle');
  }

  // ---- 行尾小菜单内容：iOS 式按住拖划选择（2026-11-08 用户要求「能划动选择」；
  //  官方 Array<MenuElement> 菜单与系统菜单实测都只支持点击选择，自绘内容补齐） ----

  @Builder
  private homeMenuBuilder() {
    Column() {
      ForEach(this.homeModes, (mode: HomeModeSpec, index: number) => {
        Column() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor([mode.value === this.homeMode ?
                this.theme.textPrimary : Color.Transparent])
              .width(20)
            Text(mode.nameRes)
              .fontSize(16)
              .fontColor(this.theme.textPrimary)
          }
          .width('100%')
          .height(40)
          .padding({ left: 14 })
          .alignItems(VerticalAlign.Center)
          .borderRadius(12)
          .backgroundColor(this.homeMenuPressedIndex === index ?
            this.theme.menuPressedBackground : Color.Transparent)
        }
        .width('100%')
        .height(48)
        .padding({ left: 4, right: 4 })
        .justifyContent(FlexAlign.Center)
      }, (mode: HomeModeSpec) => mode.value)
    }
    .width(188)
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      const y = newArea.globalPosition.y;
      if (typeof y === 'number') {
        this.homeMenuTopVp = y;
      }
    })
    .onTouch((event: TouchEvent): void => {
      this.homeMenuTouch(event);
    })
  }

  /** 拖划选择：按下/拖动时高亮手指所在行，抬手选中该行并收起（iOS 菜单同款交互；
   *  划出菜单抬手不选中，菜单由系统保持/点外收起） */
  private homeMenuTouch(event: TouchEvent): void {
    if (event.changedTouches.length === 0) {
      return;
    }
    const touch = event.changedTouches[0];
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      this.homeMenuPressedIndex = this.homeMenuRowIndexAt(touch.windowY);
    } else if (event.type === TouchType.Up) {
      const index = this.homeMenuRowIndexAt(touch.windowY);
      if (index >= 0) {
        this.setHomeMode(this.homeModes[index].value);
      }
      this.homeMenuPressedIndex = -1;
      this.homeMenuShown = false;
    } else if (event.type === TouchType.Cancel) {
      this.homeMenuPressedIndex = -1;
      this.homeMenuShown = false;
    }
  }

  /** 手指全局 y → 菜单行下标（48vp 定高行；不在行区返回 -1） */
  private homeMenuRowIndexAt(windowY: number): number {
    const index = Math.floor((windowY - this.homeMenuTopVp) / 48);
    if (index >= 0 && index < this.homeModes.length) {
      return index;
    }
    return -1;
  }

  /** 落偏好并刷新行值（菜单抬手选中时调用） */
  private setHomeMode(mode: string): void {
    this.homeMode = mode;
    AppPrefs.setHomeDisplayMode(mode);
  }

  /** 当前展示方式（存值不在名单按大屏兜底，与 AppPrefs 同一约定） */
  private currentHomeMode(): HomeModeSpec {
    if (this.homeMode === HOME_DISPLAY_MODE_LIST) {
      return this.homeModes[1];
    }
    return this.homeModes[0];
  }
}
