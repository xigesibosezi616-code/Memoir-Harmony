import SwiftUI
import UIKit

enum StampMode: String, CaseIterable {
    case weather, mood, emoji, none
}

struct StampView: View {
    let moodName: String  // 中文显示名，如 "平静"、"焦虑"

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "#B8AD9C"), lineWidth: 2)
                .frame(width: 56, height: 56)

            VStack(spacing: 1) {
                ForEach(Array(moodName.enumerated()), id: \.offset) { _, char in
                    Text(String(char))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "#6B5E4A"))
                }
            }
        }
    }

    /// 天气图标名。**要同时认两种存法**：
    /// - 2026-08-08 起：WeatherKit 自己的 `symbolName`（如 `sun.max.fill`）—— 直接就是 SF Symbol，原样用
    /// - 在那之前：我们手工映射的自定义代码（`clear` / `rain` …）—— 走下面的 switch
    ///
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
