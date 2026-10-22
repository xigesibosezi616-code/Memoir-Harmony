import SwiftUI

/// 设置 →「账户」二级页。
///
/// 🔴 **「未绑定手机号」的红色警告不在这里，而是留在一级页的账户卡上。**
/// 它是 2026-08-12 账号分裂事故的直接对策 —— 收进二级页等于把它取消了，
/// 用户根本不会点进来才发现自己有风险。这里只保留可操作的入口本身。
struct SettingsAccountView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var showBindPhone = false
    @State private var showChangePhone = false
    @State private var showBindApple = false
    @State private var showLogoutConfirm = false
    @State private var showDeleteAccount = false
    @State private var showNicknameEditor = false
    @State private var nicknameDraft = ""
    @State private var isSavingNickname = false

    var body: some View {
        let theme = themeManager.current
        SettingsSubpage(title: "账户") {
            if let user = env.session.user, env.session.isLoggedIn {
                Section {
                    // 昵称：后端 PATCH /me 的 displayName
                    Button {
                        nicknameDraft = user.displayName ?? ""
                        showNicknameEditor = true
                    } label: {
                        HStack {
                            // 不用 textformat：那个符号在中文 locale 下会渲染成汉字「格式」，
                            // 摆在「昵称」左边像是多了一个标签。signature 也更贴书信的调性。
                            SettingsRow(icon: "signature", title: "昵称", theme: theme)
                            Spacer()
                            Text(user.displayName?.isEmpty == false ? user.displayName! : "未设置")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .listRowBackground(theme.cardBackground)

                    // 手机号 —— **账号的主锚点，必需项**。
                    // Apple 只是可选的便捷登录方式：换设备时若只有 Apple 而没有手机号，
                    // 一旦 Apple ID 不可用就再也找不回账号。
                    if user.phone == nil {
                        Button {
                            showBindPhone = true
                        } label: {
                            HStack {
                                SettingsRow(icon: "exclamationmark.triangle", title: "绑定手机号", theme: theme)
                                Spacer()
                                Text("未绑定")
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.destructive)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                        .listRowBackground(theme.cardBackground)

                        Text("手机号是账号的唯一凭据。不绑定的话，换手机或 Apple ID 不可用时将无法找回账号。")
                            .font(theme.labelFont)
                            .foregroundStyle(theme.destructive)
                            .listRowBackground(theme.cardBackground)
                    } else {
                        Button {
                            showChangePhone = true
                        } label: {
                            HStack {
                                SettingsRow(icon: "iphone", title: "手机号", theme: theme)
                                Spacer()
                                Text(user.maskedPhone ?? "")
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.textTertiary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                        .listRowBackground(theme.cardBackground)
                    }

                    // Apple ID 绑定状态
                    if user.bindings.contains(where: { $0.provider == "apple" }) {
                        HStack {
                            SettingsRow(icon: "applelogo", title: "Apple ID", theme: theme)
                            Spacer()
                            Text("已绑定")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                        }
                        .listRowBackground(theme.cardBackground)
                    } else {
                        Button {
                            showBindApple = true
                        } label: {
                            HStack {
                                SettingsRow(icon: "applelogo", title: "绑定 Apple ID", theme: theme)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                        .listRowBackground(theme.cardBackground)
                    }
                }

                Section {
                    Button {
                        showLogoutConfirm = true
                    } label: {
                        SettingsRow(icon: "rectangle.portrait.and.arrow.right", title: "退出登录", theme: theme)
                    }
                    .listRowBackground(theme.cardBackground)
                }

                // 注销账号（上架清单 A9：Apple 要求 App 内必须能注销）。单独一组、放在最下面，
                // 用红色和退出登录区分开 —— 一个是暂时离开，一个是永久删除
                Section {
                    Button {
                        showDeleteAccount = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.destructive)
                                .frame(width: 20)
                            Text("注销账号")
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.destructive)
                        }
                    }
                    .listRowBackground(theme.cardBackground)
                } footer: {
                    Text("注销只删除我们服务器上的账号和来信记录，你的日记不受影响。")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
        .sheet(isPresented: $showBindPhone) {
            LoginView(mode: .bindPhone)
        }
        .sheet(isPresented: $showChangePhone) {
            ChangePhoneView()
        }
        .sheet(isPresented: $showBindApple) {
            BindAppleView()
        }
        .sheet(isPresented: $showDeleteAccount) {
            DeleteAccountView()
        }
        // 退出登录 / 注销之后这页就空了，退回上一级，别把用户留在一张白页上
        .onChange(of: env.session.isLoggedIn) { _, loggedIn in
            if !loggedIn { dismiss() }
        }
        .alert("昵称", isPresented: $showNicknameEditor) {
            TextField("给自己起个名字", text: $nicknameDraft)
            Button("取消", role: .cancel) { }
            Button("保存") { Task { await saveNickname() } }
        } message: {
            Text("笔友写信时会这样称呼你。留空则不设置。")
        }
        .confirmationDialog("退出登录后，AI 来信等云端能力将不可用，本地日记不受影响。", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                env.session.clear()
            }
        }
    }

    /// 保存昵称。后端 `PATCH /me` 只回 `{ok:true}`，所以成功后就地改本地快照，
    /// 不为一个字段再跑一趟 `GET /me`（下次进设置页的 `.task` 会与服务端对齐）。
    private func saveNickname() async {
        guard let token = env.session.token, !isSavingNickname else { return }
        isSavingNickname = true
        defer { isSavingNickname = false }

        let trimmed = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await env.auth.updateDisplayName(trimmed, token: token)
            if var user = env.session.user {
                user.displayName = trimmed.isEmpty ? nil : trimmed
                env.session.updateUser(user)
            }
        } catch {
            env.errors.present(error, fallback: "昵称保存失败")
        }
    }
}
