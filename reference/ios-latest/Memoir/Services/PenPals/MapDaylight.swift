import Foundation
import CoreLocation

/// 世界笔友地图的白天黑夜（2026-10-15 产品定）：**你这里天黑了，地图就是夜里的深色；天亮了是浅色**。
/// 三套主题一样，和主题深浅无关 —— 地图是窗外的世界，不是纸。
///
/// - 知道你大概在哪：按太阳的高度算。太阳落到地平线下 6°（民用晨昏蒙影，天真正黑下来）算夜里 ——
///   十月的北京六点多就黑了，六月要到八点；用固定钟点会在夏天傍晚天还亮着时就变黑
/// - 不知道（没给定位权限）：按这台手机的时区，18:00–6:00 算夜里
///
/// 跨端规则：鸿蒙要跑同一组用例得出同一结果（U01 附标准答案）
enum MapDaylight {
    /// 太阳低于地平线这么多度算「天黑了」
    static let nightBelowDegrees = -6.0

    static func isNight(at date: Date, location: CLLocationCoordinate2D?, timeZone: TimeZone = .current) -> Bool {
        if let location {
            return solarElevation(at: date, latitude: location.latitude, longitude: location.longitude) < nightBelowDegrees
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        return hour < 6 || hour >= 18
    }

    /// 太阳高度角（度）。NOAA 的简化算法，误差在 0.1° 以内，判断天黑天亮足够
    static func solarElevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        let rad = Double.pi / 180
        // 距 J2000.0 的天数
        let n = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0
        let meanLongitude = (280.460 + 0.985_647_4 * n).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = (357.528 + 0.985_600_3 * n).truncatingRemainder(dividingBy: 360) * rad
        let eclipticLongitude = (meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly)) * rad
        let obliquity = (23.439 - 0.000_000_4 * n) * rad
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        // 格林尼治恒星时（小时）→ 当地恒星时（弧度）
        let gmst = (18.697_374_558 + 24.065_709_824_419_08 * n).truncatingRemainder(dividingBy: 24)
        let localSidereal = (gmst * 15 + longitude) * rad
        let hourAngle = localSidereal - rightAscension
        let φ = latitude * rad
        return asin(sin(φ) * sin(declination) + cos(φ) * cos(declination) * cos(hourAngle)) / rad
    }
}
