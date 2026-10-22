import Foundation

/// App 内选定语言对应的 Locale。
///
/// **日期格式必须跟着 App 语言走，不能用 `.autoupdatingCurrent`** ——
/// 尺素允许在设置里单独选语言，系统是日文、App 选了法文时，
/// 用 `.autoupdatingCurrent` 会出现「法语界面配日文日期」这种拼接感（2026-08-08 修）。
/// ⚠️ 不再是 private —— `StatsView` 用它给 `ListFormatter` 定语言
/// （「A、B、C」还是「A, B, and C」由 locale 决定）。改这里注意其他调用方。
var appLocale: Locale {
    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
    return lang.isEmpty ? .autoupdatingCurrent : Locale(identifier: lang)
}

extension Date {
    func yearMonthKey(locale: Locale = appLocale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        let lang = locale.language.languageCode?.identifier ?? "zh"
        if lang == "zh" {
            formatter.dateFormat = "yyyy年M月"
        } else {
            formatter.dateFormat = "MMMM yyyy"
        }
        return formatter.string(from: self)
    }

    // 保留无参版本向后兼容
    var yearMonthKey: String {
        yearMonthKey()
    }

    func dayAndWeekday(locale: Locale = appLocale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        let lang = locale.language.languageCode?.identifier ?? "zh"
        if lang == "zh" {
            formatter.dateFormat = "M月d日 EEEE"
        } else {
            formatter.dateFormat = "MMM d, yyyy · EEEE"
        }
        return formatter.string(from: self)
    }

    var dayAndWeekday: String {
        dayAndWeekday()
    }

    func shortDate(locale: Locale = appLocale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        let lang = locale.language.languageCode?.identifier ?? "zh"
        if lang == "zh" {
            formatter.dateFormat = "M月d日"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: self)
    }

    var shortDate: String {
        shortDate()
    }

    /// "APRIL 2026" / "2026年4月"
    var monthYearUppercased: String {
        let f = DateFormatter()
        f.locale = appLocale
        let lang = f.locale.language.languageCode?.identifier ?? "zh"
        f.dateFormat = lang == "zh" ? "yyyy年M月" : "MMMM yyyy"
        return f.string(from: self).uppercased()
    }

    /// 零填充日期数字："05"
    var dayString: String {
        let f = DateFormatter()
        f.dateFormat = "dd"
        return f.string(from: self)
    }

    /// 星期全名："星期三" / "Wednesday"
    var weekdayString: String {
        let f = DateFormatter()
        f.locale = appLocale
        f.dateFormat = "EEEE"
        return f.string(from: self)
    }

    /// 日期十位数字："0", "1", "2", "3"
    var dayTens: String {
        let day = Calendar.current.component(.day, from: self)
        return String(format: "%d", day / 10)
    }

    /// 日期个位数字："0"-"9"
    var dayOnes: String {
        let day = Calendar.current.component(.day, from: self)
        return String(format: "%d", day % 10)
    }
}
