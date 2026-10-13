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
                    Image(systemName: StampView.weatherSymbol(for: code))
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
