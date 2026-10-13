import SwiftUI

/// 用户可见错误 / 提示的顶部 toast 卡片。
///
/// 配色克制（低饱和暖调，Aesop 风），不用荧光红/绿。
/// 后续可改成读 `ThemeManager`，本步先自包含、不引入额外依赖。
struct ErrorToastView: View {
    let toast: ErrorPresenter.Toast
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
            Text(toast.message)
                .font(.system(size: 14))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.95))
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: String {
        switch toast.kind {
        case .error:   "exclamationmark.circle"
        case .info:    "info.circle"
        case .success: "checkmark.circle"
        }
    }

    private var accent: Color {
        switch toast.kind {
        case .error:   Color(red: 0.55, green: 0.27, blue: 0.23) // 赭红
        case .info:    Color(red: 0.30, green: 0.33, blue: 0.38) // 墨灰蓝
        case .success: Color(red: 0.32, green: 0.40, blue: 0.31) // 橄榄绿
        }
    }
}
