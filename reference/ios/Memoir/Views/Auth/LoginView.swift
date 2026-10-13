import SwiftUI
import AuthenticationServices

/// 手机号验证码流程（AUTH_DESIGN.md §6）。两种模式共用同一套 UI：
/// - `.login`：手机号登录（含 Apple 登录入口），成功建立 session
/// - `.bindPhone`：Apple 注册的账号补绑手机号（需已登录），成功刷新 session.user
///
/// 以 sheet 呈现（入口在设置页「账号」），完成自动关闭。
/// 登录不强制：写日记永远不需要登录，这里只服务 AI 信件等云端能力。
struct LoginView: View {
    enum Mode {
        case login
        case bindPhone
    }

    /// ⚠️ 是 `@State` 而不是普通属性 —— Apple 登录若发现账号没有手机号，
    /// 会**就地切到 `.bindPhone`** 继续引导（见 `handleApple`），需要可变。
    @State private var mode: Mode

    init(mode: Mode = .login) {
        _mode = State(initialValue: mode)
    }

    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case phone, code
    }

    @State private var step: Step = .phone
    @State private var phone = ""
    @State private var code = ""
    @State private var busy = false
    /// 重发倒计时剩余秒数（由后端 retryAfter 驱动）
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text(titleText)
                        .font(theme.titleFont)
                        .foregroundStyle(theme.textPrimary)
                    Text(subtitleText)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(.top, 36)

                if step == .phone {
                    phoneField(theme: theme)
                } else {
                    codeField(theme: theme)
                }

                primaryButton(theme: theme)

                if step == .code {
                    resendButton(theme: theme)
                }

                if mode == .login && step == .phone {
                    appleSection(theme: theme)
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
            .onAppear { inputFocused = true }
            .onDisappear { countdownTask?.cancel() }
        }
    }

    private var titleText: String {
        switch mode {
        case .login:     return step == .phone ? "手机号登录" : "输入验证码"
        case .bindPhone: return step == .phone ? "绑定手机号" : "输入验证码"
        }
    }

    private var subtitleText: LocalizedStringKey {
        // LocalizedStringKey 的插值会生成 `验证码已发送至 %@` 这个 key，与 catalog 里的一致
        if step == .code { return "验证码已发送至 \(maskedPhone)" }
        switch mode {
        case .login:     return "未注册的手机号验证后自动创建账号"
        case .bindPhone: return "绑定后可在任何设备用手机号登录此账号"
        }
    }

    // MARK: - 输入区

    private func phoneField(theme: any AppTheme) -> some View {
        // prompt 显式上色：系统默认占位灰在奶油色背景上几乎不可见
        TextField("", text: $phone, prompt: Text("11 位手机号").foregroundStyle(theme.textSecondary))
            .keyboardType(.numberPad)
            .textContentType(.telephoneNumber)
            .font(theme.titleFont)
            .foregroundStyle(theme.textPrimary)
            .multilineTextAlignment(.center)
            .focused($inputFocused)
            .padding(.vertical, 14)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .onChange(of: phone) { _, new in
                // 只留数字，超长截断
                phone = String(new.filter(\.isNumber).prefix(11))
            }
    }

    private func codeField(theme: any AppTheme) -> some View {
        TextField("", text: $code, prompt: Text("6 位验证码").foregroundStyle(theme.textSecondary))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)   // 系统短信自动填充
            .font(theme.titleFont)
            .foregroundStyle(theme.textPrimary)
            .multilineTextAlignment(.center)
            .focused($inputFocused)
            .padding(.vertical, 14)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .onChange(of: code) { _, new in
                code = String(new.filter(\.isNumber).prefix(6))
                if code.count == 6 && !busy {
                    Task { await submitCode() }
                }
            }
    }

    // MARK: - 按钮

    private func primaryButton(theme: any AppTheme) -> some View {
        Button {
            Task {
                if step == .phone {
                    await sendCode()
                } else {
                    await submitCode()
                }
            }
        } label: {
            HStack {
                if busy {
                    ProgressView().tint(theme.background)
                }
                Text(step == .phone ? "获取验证码" : (mode == .login ? "登录" : "绑定"))
                    .font(theme.captionFont)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(primaryEnabled ? theme.accent : theme.accent.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(theme.background)
        }
        .disabled(!primaryEnabled)
    }

    private func resendButton(theme: any AppTheme) -> some View {
        Button {
            Task { await sendCode() }
        } label: {
            Text(countdown > 0 ? "重新发送（\(countdown)s）" : "重新发送")
                .font(theme.captionFont)
                .foregroundStyle(countdown > 0 ? theme.textTertiary : theme.accent)
        }
        .disabled(countdown > 0 || busy)
    }

    /// Apple 登录入口（仅登录模式）。需要 target 开启 Sign in with Apple capability。
    private func appleSection(theme: any AppTheme) -> some View {
        VStack(spacing: 16) {
            HStack {
                Rectangle().fill(theme.textTertiary.opacity(0.3)).frame(height: 0.5)
                Text("或")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
                Rectangle().fill(theme.textTertiary.opacity(0.3)).frame(height: 0.5)
            }
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                Task { await handleApple(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(busy)
        }
    }

    private var primaryEnabled: Bool {
        if busy { return false }
        switch step {
        case .phone: return isValidPhone
        case .code:  return code.count == 6
        }
    }

    private var isValidPhone: Bool {
        phone.count == 11 && phone.hasPrefix("1")
    }

    private var maskedPhone: String {
        guard phone.count == 11 else { return phone }
        return phone.prefix(3) + "****" + phone.suffix(4)
    }

    // MARK: - 动作

    private func sendCode() async {
        busy = true
        defer { busy = false }
        do {
            let retryAfter = try await env.auth.sendCode(phone: phone)
            step = .code
            code = ""
            startCountdown(retryAfter)
        } catch {
            env.errors.present(error, fallback: "验证码发送失败，请稍后再试")
            // 命中频控时按后端给的秒数恢复倒计时（如杀 App 重进后立刻点重发）
            if case AuthError.server(_, _, .some(let retryAfter)) = error {
                step = .code
                startCountdown(retryAfter)
            }
        }
    }

    private func submitCode() async {
        switch mode {
        case .login:     await login()
        case .bindPhone: await bindPhone()
        }
    }

    private func login() async {
        busy = true
        defer { busy = false }
        do {
            let resp = try await env.auth.login(phone: phone, code: code)
            env.session.establish(token: resp.token, user: resp.user)
            env.errors.present("登录成功", kind: .success)
            dismiss()
        } catch {
            env.errors.present(error, fallback: "登录失败，请稍后再试")
            code = ""
        }
    }

    private func bindPhone() async {
        guard let token = env.session.token else {
            env.errors.present("登录已过期，请重新登录")
            dismiss()
            return
        }
        busy = true
        defer { busy = false }
        do {
            let resp = try await env.auth.bindPhone(phone: phone, code: code, token: token)
            if resp.switchedAccount, let newToken = resp.token {
                // 🔴 这个手机号本来就属于用户自己的老账号，服务端已把当前空壳账号的
                // Apple 绑定转移过去并删掉了空壳 —— **本地 token 指向的身份已经不存在**，
                // 不换掉的话下一个请求就是 401。
                env.session.establish(token: newToken, user: resp.user)
                env.errors.present("已找回你的账号", kind: .success)
            } else {
                env.session.updateUser(resp.user)
                env.errors.present("手机号绑定成功", kind: .success)
            }
            dismiss()
        } catch {
            env.errors.present(error, fallback: "绑定失败，请稍后再试")
            code = ""
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) async {
        switch result {
        case .failure(let error):
            // 用户主动取消不打扰
            if let ae = error as? ASAuthorizationError, ae.code == .canceled { return }
            env.errors.present(error, fallback: "Apple 登录失败")
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                env.errors.present("Apple 登录失败：未获取到凭证")
                return
            }
            // Apple 只在首次授权返回姓名
            let name = [cred.fullName?.givenName, cred.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            busy = true
            defer { busy = false }
            do {
                let resp = try await env.auth.loginWithApple(
                    identityToken: identityToken,
                    displayName: name.isEmpty ? nil : name
                )
                env.session.establish(token: resp.token, user: resp.user)
                // 🔴 **Apple 账号没有手机号时，当场转入绑定流程，不要放用户走。**
                //
                // 手机号是账号的主锚点、必需项；Apple 只是可选的便捷入口。
                // 放着不管的话会出现最坏的情况：用户之前用手机号注册过，
                // 这次 Apple 登录建了个新空账号，他却以为「我的日记怎么没了」——
                // 2026-08-12 真实发生过。绑号那一步会把两者接回同一个账号
                // （服务端检测到手机号已属于老账号时会自动转移，见 bindPhone）。
                if resp.user.phone == nil {
                    env.errors.present("请绑定手机号以确保账号可找回", kind: .success)
                    withAnimation {
                        mode = .bindPhone
                        step = .phone
                        phone = ""
                        code = ""
                    }
                    return
                }
                env.errors.present("登录成功", kind: .success)
                dismiss()
            } catch {
                env.errors.present(error, fallback: "Apple 登录失败")
            }
        }
    }

    /// 绑定成功后拉最新 /me 刷新绑定列表
    private func refreshSessionUser() async {
        guard let token = env.session.token else { return }
        if let me = try? await env.auth.fetchMe(token: token) {
            env.session.updateUser(me.user)
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
