import SwiftUI

/// 可选的 App 图标。
///
/// ## 加一个新图标要动的三处（**新增主题时照着做**）
///
/// 1. 在 `Scripts/make_app_icon.py` 的 `THEMES` 里加一行（底色、字色 = `ThemePickerView` 的两个色块）再跑，
///    生成 `Memoir/AppIcons/<名字>Icon.icon`（Icon Composer 分层图标）和设置页预览图。
///    🔴 不要再用 `.appiconset` 放单张 PNG：iOS 26 起系统会给单色字的 PNG 图标自动套玻璃，字色发灰、边发虚
/// 2. pbxproj 的 `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` 里**追加**这个名字
///    （空格分隔；**漏了这步图标不会被打包**，`setAlternateIconName` 会在运行时报错）
/// 3. 在下面的 `allCases` 里加一条 case，填好 `alternateName` / `themeID` / `previewAsset`
///
/// ⚠️ **主图标（`AppIcon`）的 `alternateName` 必须是 `nil`**。
/// iOS 用 `nil` 表示「恢复默认图标」，写成 `"AppIcon"` 会直接失败。
///
/// ⚠️ **case 名就是存进 UserDefaults 的值**（`rawValue`）。2026-09-16 随主题改名
/// 从 `washi` / `nordic` 改成了 `bamboo` / `kent`，旧值靠 `ThemeManager.canonicalThemeID` 归一。
/// 同一次把图片资源也改了名（`NordicIcon` → `KentIcon`、`AppIconPreview_Washi` →
/// `AppIconPreview_Bamboo`…），pbxproj 的 `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
/// 已同步更新。
///
/// 🔴 **代价**：iOS 自己记着当前生效的 `alternateIconName`。改名之前就选了肯特图标的设备，
/// 升级后系统找不到 `NordicIcon`，桌面图标会退回主图标 ——
/// 到 设置 → 外观 → 应用图标 里重选一次即可恢复。内测期只有两台设备，没有做开机自动纠正
/// （那样会在启动时弹一次系统提示，更扰人）。
enum AppIconOption: String, CaseIterable, Identifiable {
    case bamboo
    case leather
    case kent
    case polar

    var id: String { rawValue }

    /// 传给 `setAlternateIconName` 的名字。**主图标是 `nil`**（见类型注释）
    var alternateName: String? {
        switch self {
        case .bamboo:  return nil            // = Assets 里的 AppIcon
        case .leather: return "LeatherIcon"
        case .kent:    return "KentIcon"
        case .polar:   return "PolarIcon"
        }
    }

    /// 对应哪个主题 —— 「跟随主题」模式靠它把主题 id 映射到图标
    var themeID: String {
        switch self {
        case .bamboo:  return "bamboo"
        case .leather: return "leather"
        case .kent:    return "kent"
        case .polar:   return "polar"
        }
    }

    /// 设置页里的预览图。
    ///
    /// **不能直接显示 appiconset** —— 那是给系统用的，`UIImage(named:)` 取不到。
    /// 每个图标在 Assets 里另放一份同名 imageset 作为预览。
    var previewAsset: String {
        switch self {
        case .bamboo:  return "AppIconPreview_Bamboo"
        case .leather: return "AppIconPreview_Leather"
        case .kent:    return "AppIconPreview_Kent"
        case .polar:   return "AppIconPreview_Polar"
        }
    }

    /// 与主题名保持一致（见 `ThemePaper.all`）。
    /// 图标是跟着主题走的，两处叫法不一样会让用户以为是两个东西
    var displayName: LocalizedStringKey {
        switch self {
        case .bamboo:  return "素笺"
        case .leather: return "皮革"
        case .kent:    return "肯特"
        case .polar:   return "极夜"
        }
    }

    /// 当前主题该配哪个图标；没有对应图标时退回主图标
    static func forTheme(_ themeID: String) -> AppIconOption {
        allCases.first { $0.themeID == themeID } ?? .bamboo
    }

    /// 系统当前实际生效的图标（用于让设置页显示真实状态，
    /// 而不是我们以为的状态 —— 两者可能不一致，比如某次切换失败了）
    /// 改名前系统里可能还记着的旧备用图标名。**上架后可以删。**
    private static let legacyAlternateNames: [String: AppIconOption] = ["NordicIcon": .kent]

    @MainActor
    static var current: AppIconOption {
        let name = UIApplication.shared.alternateIconName
        if let name, let legacy = legacyAlternateNames[name] { return legacy }
        return allCases.first { $0.alternateName == name } ?? .bamboo
    }
}
