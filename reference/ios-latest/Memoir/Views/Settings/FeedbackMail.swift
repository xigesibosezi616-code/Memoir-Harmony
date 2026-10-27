import SwiftUI

/// 设置首页「反馈与建议」（2026-10-27）：用手机自己的邮件 App 写一封信到 connect@。行的名字和邮件主题是同一句
///
/// - 不接任何 SDK，也**不带日记内容和日志**；正文最底下只附一行版本号、系统版本、机型，方便我们查问题
/// - 手机上没有能接 mailto 的邮件 App（模拟器、删了「邮件」又没装别的）：把地址复制下来并提示一句（见 `SettingsView.writeToUs`）
@MainActor
enum FeedbackMail {
    /// 对外通用邮箱（support@ 是技术支持，这里是反馈与建议，用通用的）
    static let address = "connect@sinaratech.com.cn"

    static var url: URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = address
        c.queryItems = [
            URLQueryItem(name: "subject", value: NSLocalizedString("反馈与建议", bundle: .appLanguage, comment: "设置首页一行的名字，也是邮件主题")),
            // 上面空几行给用户写；分隔线下面是给我们看的
            URLQueryItem(name: "body", value: "\n\n\n——\n" + deviceLine),
        ]
        return c.url
    }

    /// 「Memoir 1.0 (4) · iOS 27.2 · iPhone18,1」—— 给我们看的，不翻译
    static var deviceLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Memoir \(version) (\(build)) · iOS \(UIDevice.current.systemVersion) · \(model)"
    }

    /// 机型代号（如 iPhone18,1）。`UIDevice.model` 只会说「iPhone」
    private static var model: String {
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
