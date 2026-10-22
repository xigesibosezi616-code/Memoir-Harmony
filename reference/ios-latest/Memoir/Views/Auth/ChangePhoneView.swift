import SwiftUI

/// 换绑手机号。
///
/// ## 为什么要验两次
///
/// **旧号证明「是本人」，新号证明「这号是你的」，缺一不可。**
/// 只验新号的话，捡到一台已解锁手机的人就能把账号改绑到自己名下；
/// 只验旧号的话，用户可能把账号绑到一个打错的号上，从此再也登不回来。
///
/// 两个验证码都走 `/auth/send-code`（与登录同一套防刷），
/// 最后由 `POST /me/bindings/phone/change` 一次性校验并换绑。
struct ChangePhoneView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        /// 给当前手机号发码，验证是本人
        case verifyOld
        /// 输入新手机号并发码
        case newPhone
    }

    @State private var step: Step = .verifyOld
    @State private var oldCode = ""
    @State private var newPhone = ""
    @State private var newCode = ""
    @State private var busy = false
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?
    /// 旧号验证码是否已发出 —— 没发过就不该让用户在那儿填
    @State private var oldCodeSent = false

    private var currentPhone: String { env.session.user?.phone ?? "" }
    private var maskedCurrent: String { env.session.user?.maskedPhone ?? "" }

    private var canSubmit: Bool {
        switch step {
        case .verifyOld: oldCode.count == 6 && !busy
        case .newPhone:  newPhone.count == 11 && newCode.count == 6 && !busy
        }
    }

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .verifyOld: oldSection(theme: theme)
                    case .newPhone:  newSection(theme: theme)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Text(step == .verifyOld ? "下一步" : "确认换绑")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSubmit ? theme.accent : theme.textTertiary.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("换绑手机号")
                        .font(theme.labelFont)
                        .tracking(theme.letterSpacingWide)
                        .foregroundStyle(theme.textSecondary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("取消").font(theme.labelFont).foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
        .onDisappear { countdownTask?.cancel() }
    }

    // MARK: - 第一步：验证当前手机号

    @ViewBuilder
    private func oldSection(theme: any AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("先验证当前手机号")
                .font(theme.headingFont)
                .foregroundStyle(theme.textPrimary)
            // 脱敏手机号是用户数据，不进本地化表
            Text(maskedCurrent)
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
        }

        HStack(spacing: 10) {
            TextField("验证码", text: $oldCode)
                .keyboardType(.numberPad)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .padding(12)
                .background(theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: oldCode) { _, v in
                    if v.count > 6 { oldCode = String(v.prefix(6)) }
                }

            Button {
                Task { await sendCode(to: currentPhone) }
            } label: {
                Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                    .font(theme.labelFont)
                    .foregroundStyle(countdown > 0 ? theme.textTertiary : theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(countdown > 0 || busy)
        }

        if !oldCodeSent {
            Text("点「获取验证码」，我们会发送到你当前绑定的手机号。")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: - 第二步：新手机号

    @ViewBuilder
    private func newSection(theme: any AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("输入新手机号")
                .font(theme.headingFont)
                .foregroundStyle(theme.textPrimary)
            Text("换绑后，请用新手机号登录。")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
        }

        TextField("新手机号", text: $newPhone)
            .keyboardType(.numberPad)
            .font(theme.bodyFont)
            .foregroundStyle(theme.textPrimary)
            .padding(12)
            .background(theme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: newPhone) { _, v in
                if v.count > 11 { newPhone = String(v.prefix(11)) }
            }

        HStack(spacing: 10) {
            TextField("验证码", text: $newCode)
                .keyboardType(.numberPad)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .padding(12)
                .background(theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: newCode) { _, v in
                    if v.count > 6 { newCode = String(v.prefix(6)) }
                }

            Button {
                Task { await sendCode(to: newPhone) }
            } label: {
                Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                    .font(theme.labelFont)
                    .foregroundStyle(countdown > 0 || newPhone.count != 11 ? theme.textTertiary : theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(countdown > 0 || busy || newPhone.count != 11)
        }
    }

    // MARK: - 动作

    private func sendCode(to phone: String) async {
        guard !phone.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let cooldown = try await env.auth.sendCode(phone: phone)
            if step == .verifyOld { oldCodeSent = true }
            startCountdown(cooldown)
            env.errors.present("验证码已发送", kind: .success)
        } catch {
            env.errors.present(error, fallback: "验证码发送失败")
        }
    }

    private func submit() async {
        switch step {
        case .verifyOld:
            // 旧码这一步只做本地暂存 —— 服务端要求两个码一起校验，
            // 提前单独消费掉的话，用户在第二步失败就得重发旧码，白白多一次短信
            withAnimation { step = .newPhone }
            countdownTask?.cancel()
            countdown = 0
        case .newPhone:
            guard let token = env.session.token else {
                env.errors.present("登录已过期，请重新登录")
                dismiss()
                return
            }
            busy = true
            defer { busy = false }
            do {
                let user = try await env.auth.changePhone(
                    oldCode: oldCode, newPhone: newPhone, newCode: newCode, token: token
                )
                env.session.updateUser(user)
                env.errors.present("手机号已换绑", kind: .success)
                dismiss()
            } catch {
                env.errors.present(error, fallback: "换绑失败，请稍后再试")
                newCode = ""
            }
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
