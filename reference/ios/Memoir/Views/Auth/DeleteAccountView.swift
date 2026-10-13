import SwiftUI
import AuthenticationServices

/// 注销账号（上架清单 A9，Apple 审核指南 5.1.1(v)：支持注册账号的 App 必须提供 App 内注销）。
///
/// 三步：说清楚删什么、不删什么 → 证明是本人 → 最后确认一次。
///
/// ## 为什么要再验一次身份
/// 登录态只说明「这台手机登录着」，不说明「操作的是本人」。捡到一台解锁手机的人，
/// 不该能一键删掉别人的账号和全部来信 —— 和换绑手机号同一个道理（见 `ChangePhoneView`）。
/// 绑了手机号就发验证码；绑了 Apple ID 也可以重新走一次 Apple 登录，
/// 这时拿到的授权码还要交给服务端去吊销 Apple 授权（Apple 的硬性要求）。
///
/// ## 删什么、不删什么（文案必须讲清楚）
/// 只删**我们服务器上**的账号数据。日记、照片、录音、已经收到的信都在用户自己的手机和 iCloud 里，
/// 我们本来就拿不到，注销后照样在 —— 别让用户以为点一下日记就没了，也别让他以为日记跟着删了。
struct DeleteAccountView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        /// 说明删什么、不删什么
        case explain
        /// 验证是本人
        case verify
    }

    @State private var step: Step = .explain
    @State private var code = ""
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var busy = false
    /// Apple 验证通过后拿到的凭证，等最后确认时一起交给服务端
    @State private var appleProof: (identityToken: String, authorizationCode: String?)?
    @State private var showFinalConfirm = false
    /// 出错时直接写在这一页上。App 的提示条挂在根视图，**会被这个弹出页挡住**（模拟器实测：
    /// 验证码错了，用户只看到输入框被清空，看不到为什么）
    @State private var inlineError: String?

    /// 进页面时的账号快照。注销成功后登录态马上清空，没有快照的话
    /// 页面会在滑走的动画里塌掉一半（手机号那段先消失）—— 模拟器实测
    @State private var account: UserDTO?
    private var user: UserDTO? { account ?? env.session.user }
    private var hasPhone: Bool { user?.phone != nil }
    private var hasApple: Bool { user?.bindings.contains { $0.provider == "apple" } ?? false }

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch step {
                    case .explain: explainSection(theme: theme)
                    case .verify:  verifySection(theme: theme)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("注销账号")
                        .font(theme.labelFont)
                        .tracking(theme.letterSpacingWide)
                        .foregroundStyle(theme.textSecondary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("取消").font(theme.labelFont).foregroundStyle(theme.textSecondary)
                    }
                    .disabled(busy)
                }
            }
            .confirmationDialog("确定要注销账号吗？此操作无法撤销。", isPresented: $showFinalConfirm, titleVisibility: .visible) {
                Button("注销账号", role: .destructive) {
                    Task { await submit() }
                }
                Button("取消", role: .cancel) {
                    // 取消时丢掉 Apple 凭证：下次要重新验证，别让一份旧凭证一直挂着
                    appleProof = nil
                }
            }
        }
        .interactiveDismissDisabled(busy)
        .onAppear { if account == nil { account = env.session.user } }
        .onDisappear { countdownTask?.cancel() }
    }

    // MARK: - 第一步：说明

    @ViewBuilder
    private func explainSection(theme: any AppTheme) -> some View {
        Text("注销前，请先读一下")
            .font(theme.headingFont)
            .foregroundStyle(theme.textPrimary)

        notice(
            theme: theme,
            icon: "trash",
            title: "会被删除",
            text: "我们服务器上关于你的全部数据：尺素账号、绑定的手机号和 Apple ID、昵称、笔友称呼，以及来信记录。",
            tint: theme.destructive
        )
        notice(
            theme: theme,
            icon: "book.closed",
            title: "不会被删除",
            text: "这台手机和你 iCloud 里的日记、照片、录音，以及已经收到的信。它们是你自己的，注销后照样都在。",
            tint: theme.accent
        )
        notice(
            theme: theme,
            icon: "arrow.uturn.backward",
            title: "无法恢复",
            text: "注销后账号不能找回。之后用同一个手机号可以重新注册，但那会是一个全新的账号。",
            tint: theme.textSecondary
        )

        Button {
            withAnimation { step = .verify }
        } label: {
            Text("我已了解，继续")
                .font(theme.bodyFont)
                .foregroundStyle(theme.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(theme.destructive)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private func notice(theme: any AppTheme, icon: String, title: LocalizedStringKey,
                        text: LocalizedStringKey, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(text)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 第二步：验证是本人

    @ViewBuilder
    private func verifySection(theme: any AppTheme) -> some View {
        Text("先验证是你本人")
            .font(theme.headingFont)
            .foregroundStyle(theme.textPrimary)

        if hasPhone {
            VStack(alignment: .leading, spacing: 10) {
                Text("验证码会发送到你当前绑定的手机号")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                // 脱敏手机号是用户数据，不进本地化表
                Text(verbatim: user?.maskedPhone ?? "")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)

                HStack(spacing: 10) {
                    TextField("验证码", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                        .padding(12)
                        .background(theme.surfaceBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onChange(of: code) { _, v in
                            if v.count > 6 { code = String(v.prefix(6)) }
                            if !v.isEmpty { inlineError = nil }
                        }

                    Button {
                        Task { await sendCode() }
                    } label: {
                        Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                            .font(theme.labelFont)
                            .foregroundStyle(countdown > 0 ? theme.textTertiary : theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(countdown > 0 || busy)
                }

                Button {
                    appleProof = nil
                    showFinalConfirm = true
                } label: {
                    Text("注销账号")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(code.count == 6 && !busy ? theme.destructive : theme.textTertiary.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(code.count != 6 || busy)
                .padding(.top, 4)
            }
        }

        if hasApple {
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    if hasPhone { Text("或者用 Apple 验证") } else { Text("用你绑定的 Apple ID 验证") }
                }
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = []   // 只要身份凭证，不要姓名邮箱
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(busy)
            }
            .padding(.top, hasPhone ? 10 : 0)
        }

        if let inlineError {
            Text(verbatim: inlineError)   // 服务端文案或已翻译好的兜底文案，不再查表
                .font(theme.captionFont)
                .foregroundStyle(theme.destructive)
                .fixedSize(horizontal: false, vertical: true)
        }

        if busy {
            HStack {
                Spacer()
                ProgressView().tint(theme.accent)
                Spacer()
            }
        }
    }

    /// 错误写在页面上（见 `inlineError`）
    private func showError(_ error: Error?, fallback: String) {
        inlineError = (error as? LocalizedError)?.errorDescription ?? fallback
    }

    // MARK: - 动作

    private func sendCode() async {
        guard let phone = user?.phone else { return }
        inlineError = nil
        busy = true
        defer { busy = false }
        do {
            let cooldown = try await env.auth.sendCode(phone: phone)
            startCountdown(cooldown)
            // 不弹「验证码已发送」：提示条会被这个弹出页挡住，倒计时开始走就是反馈
        } catch {
            showError(error, fallback: NSLocalizedString("验证码发送失败", bundle: .appLanguage, comment: "注销账号：发码失败"))
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .failure(let error):
            if let ae = error as? ASAuthorizationError, ae.code == .canceled { return }
            let ns = error as NSError
            NSLog("❌ [DeleteAccount] Apple 授权失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            showError(error, fallback: NSLocalizedString("Apple 授权失败", bundle: .appLanguage, comment: "Apple 登录授权失败"))
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                showError(nil, fallback: NSLocalizedString("Apple 授权失败：未获取到凭证", bundle: .appLanguage, comment: "Apple 登录没拿到 identityToken"))
                return
            }
            inlineError = nil
            // 授权码只能用一次、几分钟内有效 —— 服务端拿它吊销 Apple 授权
            let authorizationCode = cred.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            appleProof = (identityToken, authorizationCode)
            showFinalConfirm = true
        }
    }

    private func submit() async {
        guard let token = env.session.token else {
            env.errors.present(NSLocalizedString("登录已过期，请重新登录", bundle: .appLanguage, comment: "登录态失效"))
            dismiss()
            return
        }
        let request: DeleteAccountRequest
        if let appleProof {
            request = DeleteAccountRequest(code: nil, appleIdentityToken: appleProof.identityToken,
                                           appleAuthorizationCode: appleProof.authorizationCode)
        } else {
            request = DeleteAccountRequest(code: code, appleIdentityToken: nil, appleAuthorizationCode: nil)
        }

        busy = true
        defer { busy = false }
        do {
            let result = try await env.auth.deleteAccount(request, token: token)
            NSLog("✅ [DeleteAccount] 账号已注销 appleRevoked=%@", result.appleRevoked ? "true" : "false")
            // 服务器上的账号已经没了：本地登录态一并清掉。日记等本地数据一律不动
            env.session.clear()
            env.errors.present(NSLocalizedString("账号已注销", bundle: .appLanguage, comment: "注销账号成功"), kind: .success)
            dismiss()
        } catch {
            let ns = error as NSError
            NSLog("❌ [DeleteAccount] 注销失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            showError(error, fallback: NSLocalizedString("注销失败，请稍后再试", bundle: .appLanguage, comment: "注销账号失败"))
            // 验证码可能已被消费（错误次数也会累计），失败后让用户重新输入；Apple 凭证也作废
            code = ""
            appleProof = nil
        }
    }

    private func startCountdown(_ seconds: Int) {
        countdownTask?.cancel()
        countdown = seconds
        countdownTask = Task { @MainActor in
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                countdown -= 1
            }
        }
    }
}
