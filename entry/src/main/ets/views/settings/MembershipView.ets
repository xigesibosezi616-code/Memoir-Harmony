/**
 * 设置 →「尺素会员」页（U10，用户裁决 2026-11-07：会员行连会员页骨架一起做）。
 * 对应 iOS `MembershipStatusView` / 付费页。
 *
 * 骨架空态（Stage 7 IAP 接入后点亮：会员状态、有效期、恢复购买、付费页）。
 * 页底 / 卡片用设置分层配色（R-SETTINGS-08）。
 *
 * 路由：系统路由表（router_map.json → name `Membership`）。
 */
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { PostingRun } from '../../models/LetterPostingFlightGeometry';
import { WaxSeal } from '../postbox/WaxSeal';

/** 骨架态火漆印直径（和付费页那枚是同一枚） */
const SEAL_SIZE_VP: number = 64;

@Builder
export function MembershipBuilder() {
  MembershipView()
}

@Component
export struct MembershipView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 火漆印面：用户昵称首字（「素」兜底） */
  @State private sealMark: string = '素';

  private navPathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        // 骨架空态：火漆印 + 尺素会员 + 一句说明（Stage 7 IAP 后点亮）
        Column({ space: 14 }) {
          WaxSeal({ sizeVp: SEAL_SIZE_VP, mark: this.sealMark })
          Text($r('app.string.s_7402638ab2'))
            .fontSize(this.theme.titleFont.size)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.textPrimary)
          Text($r('app.string.s_cf9d76b498'))
            .fontSize(this.theme.captionFont.size)
            .fontColor(this.theme.textTertiary)

          // 底部：手势条让位
          Column().width('100%').height(this.safeAreaBottomVp + 32)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 64 })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.safeAreaTopVp })
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.settingsPageBackground)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      const session = this.env.session;
      const user = session !== undefined && session.isLoggedIn() ? session.user : null;
      this.sealMark = PostingRun.sealMarkOf(user !== null ? user.displayName : undefined);
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题（各二级页同款） ----

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
        Text($r('app.string.s_7402638ab2'))
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
}
