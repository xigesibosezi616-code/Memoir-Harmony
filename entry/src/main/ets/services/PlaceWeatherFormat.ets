/**
 * 「此时此地」纯函数层（10_BUILD_MANUAL.md 2.10）。
 * 对应 iOS `Services/WeatherManager.swift` 的 `placeName(from:precision:)` 与
 * WeatherKit `symbolName` 的等价物 —— 鸿蒙侧天气来自 WeatherServiceKit，
 * 其 `ConditionType` 是数字枚举，这里映射成 SF Symbol 名（Q7 跨端词表：
 * 天气码存 iOS 的 SF Symbol 名，两边渲染各自映射，备份互通）。
 *
 * 本文件**不 import 任何 kit**：ConditionType 收 number、skycon 收 string、地址字段收散参，
 * 本地单测（hvigor test）不依赖 HMS SDK 也能跑（kit 类型本地 import 会挂）。
 */

/** 位置精度：市（默认） */
export const LOCATION_PRECISION_CITY = 'city';
/** 位置精度：区县 */
export const LOCATION_PRECISION_DISTRICT = 'district';
/** 位置精度：街道 / 地标 */
export const LOCATION_PRECISION_STREET = 'street';

/**
 * WeatherServiceKit `ConditionType`（数字）→ SF Symbol 名。
 *
 * 与 iOS 侧约定一致：`weatherCode` 存 SF Symbol 名，渲染时
 * `weatherSymbolRes` 再映射到 sys.symbol。漏网的类型落 `cloud`
 * （iOS 老手工表漏映射时晴天变阴天的教训，见 WeatherManager.swift 尾注）。
 */
export function conditionTypeToSFSymbol(type: number): string {
  switch (type) {
    // 晴（白天）
    case 1: // SUNNY
    case 2: // MOSTLY_SUNNY
    case 33: // CLEAR
    case 34: // MOSTLY_CLEAR
      return 'sun.max';
    // 多云转晴
    case 3: // PARTLY_SUNNY
    case 4: // INTERMITTENT_CLOUDS
    case 35: // PARTLY_CLOUDY
    case 36: // INTERMITTENT_CLOUDS_NIGHT
      return 'cloud.sun';
    // 霞 / 霾天日光
    case 5: // HAZY_SUNSHINE
      return 'sun.haze';
    // 阴
    case 6: // MOSTLY_CLOUDY
    case 7: // CLOUDY
    case 8: // OVERCAST
    case 38: // MOSTLY_CLOUDY_NIGHT
    case 75: // OVERCAST_NIGHT
      return 'cloud';
    // 晴（夜间）
    case 37: // HAZY_MOONLIGHT
      return 'moon.stars';
    // 雾
    case 11: // FOG
    case 68: // DENSE_FOGGY
    case 69: // MODERATE_FOGGY
    case 73: // HEAVY_FOGGY
    case 74: // SEVERE_FOGGY
      return 'cloud.fog';
    // 阵雨 / 雨
    case 12: // SHOWERS
    case 13: // MOSTLY_CLOUDY_WITH_SHOWERS
    case 14: // PARTLY_SUNNY_WITH_SHOWERS
    case 18: // RAIN
    case 39: // PARTLY_CLOUDY_WITH_SHOWERS
    case 40: // MOSTLY_CLOUDY_WITH_SHOWERS_NIGHT
    case 47: // MODERATE_RAIN
    case 57: // LIGHT_TO_MODERATE_RAIN
    case 58: // MODERATE_TO_HEAVY_RAIN
      return 'cloud.rain';
    // 小雨 / 毛毛雨
    case 46: // LIGHT_RAIN
      return 'cloud.drizzle';
    // 大雨 / 暴雨
    case 48: // HEAVY_RAIN
    case 49: // STORM
    case 50: // HEAVY_STORM
    case 51: // SEVERE_STORM
    case 59: // HEAVY_RAIN_TO_STORM
    case 60: // STORM_TO_HEAVY_STORM
    case 61: // HEAVY_TO_SEVERE_STORM
      return 'cloud.heavyrain';
    // 雷雨（含夜间雷阵、雷雨冰雹）
    case 15: // T_STORMS
    case 16: // MOSTLY_CLOUDY_WITH_T_STORMS
    case 17: // PARTLY_SUNNY_WITH_T_STORMS
    case 41: // PARTLY_CLOUDY_WITH_T_STORMS
    case 42: // MOSTLY_CLOUDY_WITH_T_STORMS_NIGHT
    case 45: // THUNDERSHOWER_WITH_HAIL
      return 'cloud.bolt';
    // 雪
    case 19: // FLURRIES
    case 20: // MOSTLY_CLOUDY_WITH_FLURRIES
    case 21: // PARTLY_SUNNY_WITH_FLURRIES
    case 22: // SNOW
    case 23: // MOSTLY_CLOUDY_WITH_SNOW
    case 29: // RAIN_AND_SNOW
    case 43: // MOSTLY_CLOUDY_WITH_FLURRIES_NIGHT
    case 44: // MOSTLY_CLOUDY_WITH_SNOW_NIGHT
    case 52: // LIGHT_SNOW
    case 53: // MODERATE_SNOW
    case 54: // HEAVY_SNOW
    case 55: // SNOWSTORM
    case 62: // LIGHT_TO_MODERATE_SNOW
    case 63: // MODERATE_TO_HEAVY_SNOW
    case 64: // HEAVY_SNOW_TO_SNOWSTORM
    case 76: // BLOWING_SNOW
      return 'cloud.snow';
    // 冻雨 / 冰粒 / 雨夹雪
    case 24: // ICE
    case 25: // SLEET
    case 26: // FREEZING_RAIN
      return 'cloud.snow';
    // 热 / 冷 / 风
    case 30: // HOT
      return 'thermometer.sun';
    case 31: // COLD
      return 'thermometer.snowflake';
    case 32: // WINDY
      return 'wind';
    // 沙 / 尘 / 霾
    case 56: // DUST_STORM
    case 65: // DUST
    case 66: // SAND
    case 67: // SANDSTORM
    case 70: // MODERATE_HAZE
    case 71: // HEAVY_HAZE
    case 72: // SEVERE_HAZE
      return 'sun.haze';
    default:
      // 0 UNDEFINED 及未来新增类型：通用云
      return 'cloud';
  }
}

/** 彩云天气 `skycon`（字符串）→ SF Symbol 名（彩云 v2.6 实况接口的天气现象码） */
export function caiyunSkyconToSFSymbol(skycon: string): string {
  switch (skycon) {
    case 'CLEAR_DAY':
      return 'sun.max';
    case 'CLEAR_NIGHT':
      return 'moon.stars';
    case 'PARTLY_DAY':
      return 'cloud.sun';
    case 'PARTLY_NIGHT':
      return 'cloud.moon';
    case 'CLOUDY':
      return 'cloud';
    case 'LIGHT_RAIN':
    case 'MODERATE_RAIN':
      return 'cloud.rain';
    case 'HEAVY_RAIN':
    case 'STORM':
      return 'cloud.heavyrain';
    case 'LIGHT_SNOW':
    case 'MODERATE_SNOW':
    case 'HEAVY_SNOW':
    case 'STORM_SNOW':
      return 'cloud.snow';
    case 'FOG':
      return 'cloud.fog';
    case 'LIGHT_HAZE':
    case 'MODERATE_HAZE':
    case 'HEAVY_HAZE':
    case 'DUST':
    case 'SAND':
      return 'sun.haze';
    case 'WIND':
      return 'wind';
    default:
      return 'cloud';
  }
}

/** 逆地理地址的可用字段（GeoAddress 的散参快照，纯函数不依赖 kit 类型） */
export interface PlaceAddressParts {
  /** 省 / 直辖市（兜底用） */
  administrativeArea?: string;
  /** 市（city 档首选） */
  locality?: string;
  /** 区县 */
  subLocality?: string;
  /** 街区 / 楼宇（street 档首选，最接近 iOS areasOfInterest 的字段） */
  premises?: string;
  /** 街道名 */
  roadName?: string;
  /** 门牌 / 支路 */
  subRoadName?: string;
}

/**
 * 按精度档位组装地名（iOS `placeName(from:precision:)` 同款逻辑）。
 * 每档都留降级路径：取不到就退上一级，绝不返回半截；全空返回 ''。
 */
export function placeNameFromAddress(precision: string, parts: PlaceAddressParts): string {
  const city = firstNonEmpty(parts.locality, parts.administrativeArea);
  const district = firstNonEmpty(parts.subLocality);
  const cityDistrict = joinNonEmpty(' ', [city, district]);

  if (precision === LOCATION_PRECISION_STREET) {
    // 街区 / 楼宇优先（street 档最有记忆点的信息，对应 iOS areasOfInterest）
    const poi = firstNonEmpty(parts.premises);
    if (poi.length > 0) {
      return poi;
    }
    const street = joinNonEmpty('', [parts.roadName, parts.subRoadName]);
    const withStreet = joinNonEmpty(' ', [district, street]);
    if (withStreet.length > 0) {
      return withStreet;
    }
    if (cityDistrict.length > 0) {
      return cityDistrict;
    }
    return city;
  }

  if (precision === LOCATION_PRECISION_DISTRICT) {
    return cityDistrict.length > 0 ? cityDistrict : city;
  }

  // LOCATION_PRECISION_CITY（默认档）
  return city;
}

/** 第一个非空串；空串与 undefined 跳过，全空返回 '' */
function firstNonEmpty(...values: (string | undefined)[]): string {
  for (const value of values) {
    if (value !== undefined && value.length > 0) {
      return value;
    }
  }
  return '';
}

/** 用分隔符拼接非空串；全空返回 '' */
function joinNonEmpty(separator: string, values: (string | undefined)[]): string {
  const kept: string[] = [];
  for (const value of values) {
    if (value !== undefined && value.length > 0) {
      kept.push(value);
    }
  }
  return kept.join(separator);
}
