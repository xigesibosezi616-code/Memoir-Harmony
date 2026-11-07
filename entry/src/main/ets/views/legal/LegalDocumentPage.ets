/**
 * 隐私政策 / 用户协议的路由页（10_BUILD_MANUAL.md 6.7；R-APP-04）。
 * 设置 → 关于 →「隐私政策 / 用户协议」行推入（iOS：NavigationLink 直推阅读页）。
 *
 * 鸿蒙把 1.5 已有的覆盖层 `LegalDocumentView` 包进 NavDestination；
 * 两条路由各在 Builder 创建期**固定一个文档**（不依赖 onReady 晚于首帧的时序
 * 再传参——普通成员变量创建后不随状态更新，创建期定死才可靠）。
 * 顶栏（居中标题 + 左上角关闭）由 LegalDocumentView 自带，关闭 = 出栈。
 *
 * 路由：系统路由表（router_map.json → name `Privacy` / `Terms`）。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { LegalDocument } from './LegalDocument';
import { LegalDocumentView } from './LegalDocumentView';

@Builder
export function PrivacyPageBuilder() {
  LegalDocumentPage({ fixedDoc: LegalDocument.Privacy })
}

@Builder
export function TermsPageBuilder() {
  LegalDocumentPage({ fixedDoc: LegalDocument.Terms })
}

@Component
export struct LegalDocumentPage {
  /** 固定文档：路由 Builder 创建期定死（隐私政策 / 用户协议） */
  fixedDoc: LegalDocument = LegalDocument.Privacy;

  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  private navPathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      LegalDocumentView({
        document: this.fixedDoc,
        onClose: (): void => {
          this.navPathStack.pop();
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.background)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
    })
  }
}
