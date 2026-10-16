/**
 * 「此时此地」标记 —— 天气图标 + 温度 + 地名（10_BUILD_MANUAL.md 2.3）。
 * 对应 iOS `Views/Components/WeatherLocationBadge.swift`。
 *
 * 三项数据都可缺省（天气拿到了地名没拿到，或反之），缺哪项就少显示哪项；
 * 全空时渲染为空，调用方无需自己判空。字号 / 颜色 / 图标大小由调用方传
 * （和纸版式用自己的色板，普通版式走主题 token）。
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

/** 有没有可显示的内容（和纸版式决定「|」分隔符要不要出） */
export function weatherBadgeHasContent(weatherCode: string, weatherInfo: string, locationInfo: string): boolean {
  return weatherCode.length > 0 || weatherInfo.length > 0 || locationInfo.length > 0;
}

/**
 * 天气图标映射（Q7 跨端词表：iOS 存 WeatherKit 的 SF Symbol 名，老版本存
 * 手工代码 clear / rain…）。鸿蒙渲染时映射到最接近的 sys.symbol 天气图标，
 * 认不出的显示通用云图标。
 */
export function weatherSymbolRes(code: string): Resource {
  switch (code) {
    // 晴（白天）
    case 'sun.max': case 'sun.max.fill': case 'sunrise': case 'sunset': case 'clear':
      return $r('sys.symbol.sun_max');
    // 晴（夜间）
    case 'moon': case 'moon.fill': case 'moon.stars': case 'moon.stars.fill':
      return $r('sys.symbol.moon_z_fill');
    // 多云转晴
    case 'cloud.sun': case 'cloud.sun.fill': case 'partlyCloudy':
      return $r('sys.symbol.cloud_and_sun_fill');
    // 阴
    case 'cloud': case 'cloud.fill': case 'mostlyCloudy': case 'cloudy':
      return $r('sys.symbol.cloud');
    // 雨
    case 'cloud.rain': case 'rain':
      return $r('sys.symbol.moderate_rain');
    case 'cloud.heavyrain': case 'heavyRain':
      return $r('sys.symbol.heavy_rain');
    case 'cloud.drizzle': case 'drizzle':
      return $r('sys.symbol.light_rain');
    // 雪
    case 'cloud.snow': case 'snow':
      return $r('sys.symbol.cloud_snow');
    // 雷雨
    case 'cloud.bolt': case 'thunderstorms':
      return $r('sys.symbol.cloud_heavy_storm');
    // 雾
    case 'cloud.fog': case 'fog':
      return $r('sys.symbol.foggy');
    // 风 / 霾 / 热 / 冷
    case 'wind':
      return $r('sys.symbol.wind');
    case 'sun.haze': case 'haze':
      return $r('sys.symbol.haze');
    case 'thermometer.sun': case 'hot':
      return $r('sys.symbol.thermometer');
    case 'thermometer.snowflake': case 'frigid':
      return $r('sys.symbol.thermometer_snowflake');
    default:
      return $r('sys.symbol.cloud');
  }
}

@Component
export struct WeatherLocationBadge {
  /** 天气标识（iOS SF Symbol 名或老代码，见 weatherSymbolRes） */
  weatherCode: string = '';
  /** 温度文本，如 "26°" */
  weatherInfo: string = '';
  /** 地名，如 "西安市" */
  locationInfo: string = '';
  /** 文字字号（fp） */
  fontSize: number = 12;
  /** 文字与图标颜色 */
  fontColor: ResourceColor = 0xFF8B7E6A;
  /** 天气图标字号（fp）；定位图标比它小 1（iOS 同款） */
  iconSize: number = 11;

  build() {
    if (weatherBadgeHasContent(this.weatherCode, this.weatherInfo, this.locationInfo)) {
      Row({ space: 4 }) {
        if (this.weatherCode.length > 0) {
          SymbolGlyph(weatherSymbolRes(this.weatherCode))
            .fontSize(this.iconSize)
            .fontColor([this.fontColor])
        }
        if (this.weatherInfo.length > 0) {
          Text(this.weatherInfo)
            .fontSize(this.fontSize)
            .fontColor(this.fontColor)
        }
        if (this.locationInfo.length > 0) {
          // 天气与地名之间用间隔点；只有地名时不显示点（iOS 同款）
          if (this.weatherCode.length > 0 || this.weatherInfo.length > 0) {
            Text('·')
              .fontSize(this.fontSize)
              .fontColor(this.fontColor)
              .opacity(0.6)
          }
          SymbolGlyph($r('sys.symbol.position'))
            .fontSize(this.iconSize - 1)
            .fontColor([this.fontColor])
            .opacity(0.75)
          Text(this.locationInfo)
            .fontSize(this.fontSize)
            .fontColor(this.fontColor)
            .maxLines(1)
        }
      }
    }
  }
}
