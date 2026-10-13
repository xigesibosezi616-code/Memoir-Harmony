import SwiftUI
import AuthenticationServices

/// 已登录（手机号）账号绑定 Apple ID（AUTH_DESIGN.md §1.5）。
/// 以 sheet 呈现，入口在设置页「账号」。冲突（该 Apple ID 已绑他人）时后端返回 409，文案直接展示。
struct BindAppleView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("绑定 Apple ID")
                        .font(theme.titleFont)
                        .foregroundStyle(theme.textPrimary)
                    Text("绑定后可在此设备用 Apple 快捷登录同一账号")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(.top, 36)

                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = []   // 绑定只要身份凭证，不要姓名邮箱
                } onCompletion: { result in
                    Task { await handleApple(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(busy)

                if busy {
                    ProgressView().tint(theme.accent)
                }

                Spacer()
            }
            .padding(.horizontal, 28)
            .background(theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) async {
        switch result {
        case .failure(let error):
            if let ae = error as? ASAuthorizationError, ae.code == .canceled { return }
            env.errors.present(error, fallback: "Apple 授权失败")
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                env.errors.present("Apple 授权失败：未获取到凭证")
                return
            }
            guard let token = env.session.token else {
                env.errors.present("登录已过期，请重新登录")
                dismiss()
                return
            }
            busy = true
            defer { busy = false }
            do {
                try await env.auth.bindApple(identityToken: identityToken, token: token)
                if let me = try? await env.auth.fetchMe(token: token) {
                    env.session.updateUser(me.user)
                }
                env.errors.present("Apple ID 绑定成功", kind: .success)
                dismiss()
            } catch {
                env.errors.present(error, fallback: "绑定失败，请稍后再试")
            }
        }
    }
}
