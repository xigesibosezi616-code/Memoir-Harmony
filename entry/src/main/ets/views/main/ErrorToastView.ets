/**
 * 用户可见错误 / 提示的顶部 toast 卡片（10_BUILD_MANUAL.md 1.6）。
 * 对应 iOS `Environment/ErrorToastView.swift`。
 *
 * 配色克制（低饱和暖调，Aesop 风），不用荧光红/绿：
 * 赭红 / 墨灰蓝 / 橄榄绿三色取自 iOS（RGB 逐值换算成 ARGB 数值）。
 * 图标用 Tabler filled SVG（alert-circle / info-circle / circle-check），
 * 染色矩阵统一处理（`IconTint.tintMatrix`）。
 * 出现 / 消失动画（顶部滑入 0.35s 弹簧）挂在 MainTabsView 的挂载点上。
 */
import { ToastData, ErrorToastKind } from '../../environment/ErrorPresenter';
import { tintMatrix } from '../../theme/IconTint';

/** 前景：白 0.95（iOS `.white.opacity(0.95)` → 0.95×255≈242） */
const TOAST_FOREGROUND: number = 0xF2FFFFFF;
/** 错误底色：赭红 Color(red: 0.55, green: 0.27, blue: 0.23) */
const TOAST_ACCENT_ERROR: number = 0xFF8C453B;
/** 中性底色：墨灰蓝 Color(red: 0.30, green: 0.33, blue: 0.38) */
const TOAST_ACCENT_INFO: number = 0xFF4D5461;
/** 成功底色：橄榄绿 Color(red: 0.32, green: 0.40, blue: 0.31) */
const TOAST_ACCENT_SUCCESS: number = 0xFF52664F;

@Component
export struct ErrorToastView {
  @Prop toast: ToastData = new ToastData('', ErrorToastKind.Error);
  onDismiss: () => void = (): void => {};

  build() {
    Row({ space: 10 }) {
      Image(this.iconRes())
        .width(15)
        .height(15)
        .supportSvg2(true)
        .colorFilter(new ColorFilter(tintMatrix(TOAST_FOREGROUND)))
      Text(this.toast.message)
        .fontSize(14)
        .fontColor(TOAST_FOREGROUND)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
      Blank()
    }
    .alignItems(VerticalAlign.Center)
    .padding({ top: 12, bottom: 12, left: 16, right: 16 })
    .backgroundColor(this.accentColor())
    .borderRadius(14)
    .shadow({ radius: 12, offsetY: 4, color: 'rgba(0,0,0,0.12)' })
    .width('100%')
    .onClick((): void => {
      this.onDismiss();
    })
  }

  private iconRes(): Resource {
    switch (this.toast.kind) {
      case ErrorToastKind.Info:
        return $r('app.media.toast_info');
      case ErrorToastKind.Success:
        return $r('app.media.toast_check');
      default:
        return $r('app.media.toast_alert');
    }
  }

  private accentColor(): number {
    switch (this.toast.kind) {
      case ErrorToastKind.Info:
        return TOAST_ACCENT_INFO;
      case ErrorToastKind.Success:
        return TOAST_ACCENT_SUCCESS;
      default:
        return TOAST_ACCENT_ERROR;
    }
  }
}
