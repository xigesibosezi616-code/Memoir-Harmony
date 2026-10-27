import Foundation

/// 用户给自己那位笔友起的名字。
///
/// 2026-10-24 产品定：**名字只能由用户自己起，不再有默认名**（原来默认「青鸟」，界面上任何地方都不再出现）。
/// - 存在 `@AppStorage(PenPalName.storageKey)`，默认空串 = 还没起名
/// - 首启必须起名才能进（`OnboardingView`）；老用户还没起名的，打开 App 时补起一次（`PenPalNamingSheet`）
/// - 万一哪里还是空的（比如刚从备份恢复），显示和寄信都叫「笔友」
enum PenPalName {
    static let storageKey = "penPalName"
    /// 够写一个名字；后端 `pen_pal_name` / `from_character` 是 VARCHAR(32)
    static let maxLength = 16

    /// 2026-10-24 之前的默认名。老用户若还是它，当作没起名、请他起一次 —— 代码里只有这里还留着这两个字
    private static let legacyDefault = "青鸟"

    /// 用户输入整理后的名字（去首尾空白、截到上限）；空串 = 没起
    static func normalized(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
    }

    /// 还没起名：空的，或者还是旧的默认名
    static func needsNaming(_ stored: String) -> Bool {
        let name = normalized(stored)
        return name.isEmpty || name == legacyDefault
    }

    /// 显示、寄信都用这个：没起名时叫「笔友」
    static func display(_ stored: String) -> String {
        needsNaming(stored)
            ? NSLocalizedString("笔友", bundle: .appLanguage, comment: "还没给笔友起名时，对笔友的称呼")
            : normalized(stored)
    }
}
