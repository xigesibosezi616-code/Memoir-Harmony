import SwiftUI

/// 「此时此地」标记 —— 天气图标 + 温度 + 地名。
///
/// 写日记页、详情页、日记本卡片共用同一个组件，保证三处视觉一致。
/// 三项数据都可缺省（天气拿到了地名没拿到，或反之），缺哪项就少显示哪项；
/// 全空时渲染为空，调用方无需自己判空。
struct WeatherLocationBadge: View {
    let weatherCode: String?
    /// 温度文本，如 "26°"
    let weatherInfo: String?
    /// 地名，如 "西安市"
    let locationInfo: String?

    var font: Font = .system(size: 12)
    var color: Color = .secondary
    var iconSize: CGFloat = 11

    static func hasContent(_ weatherCode: String?, _ weatherInfo: String?, _ locationInfo: String?) -> Bool {
        weatherCode?.isEmpty == false || weatherInfo?.isEmpty == false || locationInfo?.isEmpty == false
    }

    private var isEmpty: Bool {
        !Self.hasContent(weatherCode, weatherInfo, locationInfo)
    }

    var body: some View {
        if isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                if let code = weatherCode, !code.isEmpty {
                    Image(systemName: Self.weatherSymbol(for: code))
                        .font(.system(size: iconSize))
                }
                if let temp = weatherInfo, !temp.isEmpty {
                    Text(temp)
                        .font(font)
                }
                if let place = locationInfo, !place.isEmpty {
                    // 天气与地名之间用间隔点；只有地名时不显示点
                    if weatherCode?.isEmpty == false || weatherInfo?.isEmpty == false {
                        Text("·")
                            .font(font)
                            .opacity(0.6)
                    }
                    Image(systemName: "location.fill")
                        .font(.system(size: iconSize - 1))
                        .opacity(0.75)
                    Text(place)
                        .font(font)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(color)
        }
    }
}

extension WeatherLocationBadge {
    /// 天气代码 → SF Symbol 名（2026-10-17 从删掉的 `StampView` 挪过来）。
    ///
    /// 新日记存的就是 WeatherKit 给的 SF Symbol 名，原样用；旧日记里存的还是自定义代码（`clear` / `rain` …），这里换算。
    /// 判定方式是「这个名字是不是一个真的 SF Symbol」，而不是维护一张新旧对照表 ——
    /// 后者每加一种天气都要改两处，迟早漏。
    static func weatherSymbol(for code: String) -> String {
        if UIImage(systemName: code) != nil {
            return code
        }
        switch code {
        case "clear": return "sun.max"
        case "partlyCloudy": return "cloud.sun"
        case "mostlyCloudy", "cloudy": return "cloud"
        case "rain": return "cloud.rain"
        case "heavyRain": return "cloud.heavyrain"
        case "drizzle": return "cloud.drizzle"
        case "snow": return "cloud.snow"
        case "thunderstorms": return "cloud.bolt"
        case "fog": return "cloud.fog"
        case "wind": return "wind"
        case "haze": return "sun.haze"
        case "hot": return "thermometer.sun"
        case "frigid": return "thermometer.snowflake"
        default: return "cloud"
        }
    }
}
