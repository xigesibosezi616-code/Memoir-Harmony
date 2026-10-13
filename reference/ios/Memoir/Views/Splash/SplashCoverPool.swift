import Foundation

/// 启动封面池 —— **按当前主题取一张静态封面**。把图片放进目录就生效，不用改代码。
///
/// ## 怎么加 / 换封面
///
/// 放进 **`Memoir/Resources/SplashCovers/`**，按主题 ID 命名：
///
/// | 文件名 | 主题 | 背景色（图片底色应与之一致） |
/// |---|---|---|
/// | `splash_washi.*`   | 和纸 | `#FAF7F2` 米白 |
/// | `splash_leather.*` | 皮革 | `#1C1410` 深棕 |
/// | `splash_nordic.*`  | 北欧 | `#FFFFFF` 纯白 |
///
/// 本项目用的是 Xcode 的**文件系统同步文件夹**，目录下的文件会自动成为 target 资源 ——
/// 不需要手动勾 Target Membership，也不用动 `project.pbxproj`。
/// 支持 `png` / `jpg` / `jpeg` / `heic`。
///
/// **某个主题缺图就不显示开场**，直接进 App —— 不会崩，也不会白屏一下。
///
/// ## ⚠️ 关于图片底色
///
/// 封面是 `.scaledToFit` 铺的，比例对不上时上下（或左右）会留白，
/// **留白处填的是主题背景色**。所以图片自身的底色必须与上表一致，否则会看到一圈色差。
enum SplashCoverPool {

    /// 封面放在这个子目录下。找不到该目录时会退回扫描 bundle 根目录 ——
    /// 「拖进 Xcode」有两种落法：蓝色 folder reference 保留目录结构，
    /// 而文件系统同步文件夹会把资源**平铺**到 bundle 根。两种都要认。
    static let directoryName = "SplashCovers"

    static let supportedExtensions = ["png", "jpg", "jpeg", "heic"]

    /// 主题 ID 存在 UserDefaults 的哪个 key —— **必须与 `ThemeManager` 保持一致**。
    ///
    /// 这里直接读 UserDefaults 而不是走 `ThemeManager` 实例，是为了让 `MemoirApp`
    /// 在 `@State` 初值里就能判断"这次启动要不要显示开场"（那个时机还拿不到 environment）。
    private static let themeKey = "selectedTheme"
    private static let defaultThemeID = "bamboo"

    /// 当前主题 ID（与 `ThemeManager.currentThemeID` 同源）
    static var currentThemeID: String {
        UserDefaults.standard.string(forKey: themeKey) ?? defaultThemeID
    }

    /// 当前主题的封面；没有就是 nil（调用方据此跳过开场）
    static var coverForCurrentTheme: URL? {
        cover(for: currentThemeID)
    }

    /// 指定主题的封面文件。四种扩展名依次找，找不到返回 nil。
    static func cover(for themeID: String) -> URL? {
        let base = "splash_\(themeID)"
        for ext in supportedExtensions {
            // 先按子目录找（folder reference 的落法），再找 bundle 根（同步文件夹的落法）
            if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: directoryName)
                ?? Bundle.main.url(forResource: base, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}
