import Foundation
import CoreLocation
import SwiftUI

/// 路程：信从你这里到笔友那里、回信再回来，要多久（2026-10-15 定，见 `Docs/WORLD_PENPALS.md`「路程」）。
///
/// **在本机算，位置不上传**。分档是跨端规则 —— 鸿蒙必须跑同一组用例、得出同一档（U01 附标准答案）：
/// - 西安 → 斯图尔特岛 ≈ 10,790 km → 两三天
/// - 西安 → 京都 ≈ 2,450 km → 一天之内
enum PenPalTravel {
    /// 地球平均半径（公里）
    static let earthRadiusKilometers = 6371.0088

    /// 回信多久到。范围内随机，到了才知道 —— 现实里也没人知道信哪天到
    enum ReplyTime: Equatable {
        /// 自己起名的那一位：没有住址，就在身边
        case ownPenPal
        /// 3000 公里以内
        case near
        /// 3000–9000 公里
        case middle
        /// 9000 公里以上
        case far
        /// 南极，多远都一样
        case antarctic
        /// 不知道你在哪（没给定位权限）
        case unknownDistance

        /// 寄出到回信到达，几个小时
        var hours: ClosedRange<Double> {
            switch self {
            case .ownPenPal: return 2...6
            case .near: return 6...24
            case .middle, .unknownDistance: return 18...48
            case .far: return 36...72
            case .antarctic: return 72...120
            }
        }

        /// 名片上的说法。不报具体小时数，像问邮局「大概几天」
        var label: LocalizedStringKey {
            switch self {
            case .ownPenPal: return "几个小时就回"
            case .near: return "一天之内回信"
            case .middle, .unknownDistance: return "一两天回信"
            case .far: return "两三天回信"
            case .antarctic: return "三到五天回信"
            }
        }
    }

    /// 这一档里均匀随机一个到达时刻。`timeScale` 是开发时的加速倍率（见 `LetterDelivery.debugTimeScale`），正式包恒为 1
    static func arrivalDate(sentAt: Date, replyTime: ReplyTime, timeScale: Double = 1) -> Date {
        let hours = Double.random(in: replyTime.hours)
        return sentAt.addingTimeInterval(hours * 3600 / max(timeScale, 1))
    }

    static func replyTime(to penPal: PenPal, from user: CLLocationCoordinate2D?) -> ReplyTime {
        if penPal.isAntarctic { return .antarctic }
        guard let user else { return .unknownDistance }
        let distance = distanceKilometers(user, penPal.location)
        if distance < 3000 { return .near }
        if distance < 9000 { return .middle }
        return .far
    }

    /// 两点之间的大圆距离（公里，haversine）
    static func distanceKilometers(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let φ1 = a.latitude * .pi / 180
        let φ2 = b.latitude * .pi / 180
        let dφ = φ2 - φ1
        let dλ = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * earthRadiusKilometers * asin(min(1, h.squareRoot()))
    }

    /// 大圆上从 a 走到 b、走了 `fraction`（0…1）的那一点 —— 画在航线上的「在路上的信」用
    static func point(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, fraction: Double) -> CLLocationCoordinate2D {
        let φ1 = a.latitude * .pi / 180, λ1 = a.longitude * .pi / 180
        let φ2 = b.latitude * .pi / 180, λ2 = b.longitude * .pi / 180
        let d = distanceKilometers(a, b) / earthRadiusKilometers
        guard d > 1e-9 else { return a }
        let t = min(max(fraction, 0), 1)
        let wa = sin((1 - t) * d) / sin(d)
        let wb = sin(t * d) / sin(d)
        let x = wa * cos(φ1) * cos(λ1) + wb * cos(φ2) * cos(λ2)
        let y = wa * cos(φ1) * sin(λ1) + wb * cos(φ2) * sin(λ2)
        let z = wa * sin(φ1) + wb * sin(φ2)
        return CLLocationCoordinate2D(
            latitude: atan2(z, (x * x + y * y).squareRoot()) * 180 / .pi,
            longitude: atan2(y, x) * 180 / .pi
        )
    }
}

/// 笔友那里此刻：几点、白天还是夜里、什么季节
enum PenPalLocalTime {
    enum Season {
        case spring, summer, autumn, winter

        var label: LocalizedStringKey {
            switch self {
            case .spring: return "春天"
            case .summer: return "夏天"
            case .autumn: return "秋天"
            case .winter: return "冬天"
            }
        }
    }

    /// 「15:20」—— 按 App 语言的习惯写（12 / 24 小时制跟着语言走）
    static func clock(of penPal: PenPal, at date: Date, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.timeZone = TimeZone(identifier: penPal.timeZone) ?? .current
        return date.formatted(style)
    }

    static func isDaytime(of penPal: PenPal, at date: Date) -> Bool {
        let hour = calendar(for: penPal).component(.hour, from: date)
        return (6..<18).contains(hour)
    }

    /// 他那里的季节。南半球和北半球相反；回归线之间（新加坡、内罗毕）没有四季，不写
    static func season(of penPal: PenPal, at date: Date) -> Season? {
        let latitude = penPal.coordinate.lat
        guard abs(latitude) >= 23.5 else { return nil }
        let month = calendar(for: penPal).component(.month, from: date)
        let northern: Season = switch month {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
        guard latitude < 0 else { return northern }
        switch northern {
        case .spring: return .autumn
        case .summer: return .winter
        case .autumn: return .spring
        case .winter: return .summer
        }
    }

    private static func calendar(for penPal: PenPal) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: penPal.timeZone) ?? .current
        return calendar
    }
}
