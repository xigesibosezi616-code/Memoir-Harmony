import Foundation

extension Bundle {
    /// App 内选定语言对应的 `.lproj` bundle。
    ///
    /// **不能用 `Bundle.main`** —— 那走的是**系统**语言，而尺素允许在设置里单独选语言
    /// （没有「跟随系统」这个选项）。用 main 的话，用户把 App 语言设成日文、系统仍是中文时，
    /// 这里取出来的还是中文。
    ///
    /// SwiftUI 的 `Text("字面量")` 靠 `.environment(\.locale)` 自动解决这件事；
    /// **需要拿到 `String` 交给非 Text 的调用方时**（`ErrorPresenter.present(_:)`、
    /// `CrisisHelpCard` 的热线文案这类）才需要它，配合 `NSLocalizedString(_:bundle:comment:)` 用。
    static var appLanguage: Bundle {
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        guard !lang.isEmpty,
              let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}
