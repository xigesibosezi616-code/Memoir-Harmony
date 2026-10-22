import Foundation
import CoreLocation

/// 世界笔友名册里的一位（2026-10，见 `Docs/WORLD_PENPALS.md`）。
///
/// 来自打包进 App 的 `penpals.json` —— **iOS 和鸿蒙用同一份文件**，两端读同一份数据，不靠文字转述。
/// 人设和提示词只在服务端；这里只有客户端显示和算路程要用的东西。
struct PenPal: Identifiable, Hashable, Decodable {
    /// 稳定 id，和服务端人设、`letters.pen_pal_id`、备份包一致。定了就不改
    let id: String
    /// 只有姓。按 App 语言取（如朴 / 박、陈 / Tan）
    let surname: LocalizedText
    /// ISO 3166 地区码：国家名由系统按 App 语言给出；`AQ` 是南极
    let region: String
    let coordinate: Coordinate
    /// IANA 时区，名片上「他那里此刻几点」
    let timeZone: String
    /// 他写信用的语言
    let nativeLanguage: String
    /// 寄给他要贴几张邮票（南极 2 张，其余 1 张）
    let postage: Int
    /// 名片上的地名（「斯图尔特岛」）
    let place: LocalizedText
    /// 名片上的一句话
    let card: LocalizedText

    struct Coordinate: Hashable, Decodable {
        let lat: Double
        let lon: Double
    }

    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon)
    }

    var isAntarctic: Bool { region == "AQ" }
}

/// 名册里的多语言文字：`{"zh-Hans": "…", "en": "…", "default": "…"}`。
///
/// 按 App 语言取；没有这种语言就退回英文，再退回 `default`。
/// 地名、名片七种语言都写了；上线前请各地熟悉的人审校（WORLD_PENPALS 第 7 步）
struct LocalizedText: Hashable, Decodable {
    let values: [String: String]

    init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: String].self)
    }

    func resolved(for locale: Locale) -> String {
        let language = PenPalRoster.languageKey(for: locale)
        return values[language] ?? values["en"] ?? values["default"] ?? values.values.first ?? ""
    }
}

enum PenPalRoster {
    /// 全部世界笔友，按名册里的顺序
    static let all: [PenPal] = load()

    /// 世界笔友的总开关。2026-10-16 读信翻面确认后打开。
    ///
    /// 真正能寄哪几位由服务端说了算（`GET /penpals`）：服务端还没部署、或者查不到时一位都没有，名片上写「即将开放」。
    /// 要临时关掉世界笔友，改回 `false`：地图照常能看、能翻名片，收件人只剩自己起名的那一位
    static let canSendToWorldPenPals = true

    static func penPal(id: String) -> PenPal? {
        all.first { $0.id == id }
    }

    private struct File: Decodable {
        let version: Int
        let penPals: [PenPal]
    }

    private static func load() -> [PenPal] {
        guard let url = Bundle.main.url(forResource: "penpals", withExtension: "json") else {
            NSLog("🔴 [PenPalRoster] 包里找不到 penpals.json")
            assertionFailure("penpals.json 没有打进包里")
            return []
        }
        do {
            let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
            return file.penPals
        } catch {
            let ns = error as NSError
            NSLog("🔴 [PenPalRoster] 名册读不出来 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            assertionFailure("penpals.json 格式不对：\(error)")
            return []
        }
    }

    /// App 语言 → 名册里的键（zh-Hans / zh-Hant / en / ja / ko / fr / es）
    static func languageKey(for locale: Locale) -> String {
        let id = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if id.hasPrefix("zh") { return id.contains("Hant") ? "zh-Hant" : "zh-Hans" }
        return locale.language.languageCode?.identifier ?? "en"
    }
}
