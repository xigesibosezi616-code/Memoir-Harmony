/**
 * 「此时此地」纯函数单测（10_BUILD_MANUAL.md 2.10）。
 * conditionTypeToSFSymbol：WeatherServiceKit ConditionType（数字）→ SF Symbol 名
 * （Q7 跨端词表）；placeNameFromAddress：精度三档的地名归一化与降级链。
 * 纯函数不 import 任何 kit —— HMS kit 类型本地单测 import 不了，收 number/散参。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  LOCATION_PRECISION_CITY,
  LOCATION_PRECISION_DISTRICT,
  LOCATION_PRECISION_STREET,
  caiyunSkyconToSFSymbol,
  conditionTypeToSFSymbol,
  placeNameFromAddress,
  PlaceAddressParts
} from '../../main/ets/services/PlaceWeatherFormat';
import { AppPrefs } from '../../main/ets/services/AppPrefs';

/** 广州一套完整地址（区县 / 街道档共用底料） */
function fullAddress(): PlaceAddressParts {
  return {
    administrativeArea: '广东省',
    locality: '广州市',
    subLocality: '天河区',
    premises: '广州塔',
    roadName: '天河路',
    subRoadName: '10号'
  };
}

export default function placeWeatherFormatTest() {
  describe('PlaceWeatherFormatTest', () => {
    // ---- conditionTypeToSFSymbol（天气码 = SF Symbol 名，Q7 词表） ----

    it('sunnyAndClearMapToSunMax', 0, () => {
      expect(conditionTypeToSFSymbol(1)).assertEqual('sun.max'); // SUNNY
      expect(conditionTypeToSFSymbol(2)).assertEqual('sun.max'); // MOSTLY_SUNNY
      expect(conditionTypeToSFSymbol(33)).assertEqual('sun.max'); // CLEAR
      expect(conditionTypeToSFSymbol(34)).assertEqual('sun.max'); // MOSTLY_CLEAR
    })

    it('partlyCloudyMapsToCloudSun', 0, () => {
      expect(conditionTypeToSFSymbol(3)).assertEqual('cloud.sun'); // PARTLY_SUNNY
      expect(conditionTypeToSFSymbol(4)).assertEqual('cloud.sun'); // INTERMITTENT_CLOUDS
      expect(conditionTypeToSFSymbol(35)).assertEqual('cloud.sun'); // PARTLY_CLOUDY
    })

    it('overcastFamilyMapsToCloud', 0, () => {
      expect(conditionTypeToSFSymbol(6)).assertEqual('cloud'); // MOSTLY_CLOUDY
      expect(conditionTypeToSFSymbol(7)).assertEqual('cloud'); // CLOUDY
      expect(conditionTypeToSFSymbol(8)).assertEqual('cloud'); // OVERCAST
      expect(conditionTypeToSFSymbol(75)).assertEqual('cloud'); // OVERCAST_NIGHT
    })

    it('rainGradesMapByIntensity', 0, () => {
      expect(conditionTypeToSFSymbol(46)).assertEqual('cloud.drizzle'); // LIGHT_RAIN
      expect(conditionTypeToSFSymbol(47)).assertEqual('cloud.rain'); // MODERATE_RAIN
      expect(conditionTypeToSFSymbol(48)).assertEqual('cloud.heavyrain'); // HEAVY_RAIN
      expect(conditionTypeToSFSymbol(51)).assertEqual('cloud.heavyrain'); // SEVERE_STORM
    })

    it('snowThunderFogWindHazeHaveOwnSymbols', 0, () => {
      expect(conditionTypeToSFSymbol(22)).assertEqual('cloud.snow'); // SNOW
      expect(conditionTypeToSFSymbol(15)).assertEqual('cloud.bolt'); // T_STORMS
      expect(conditionTypeToSFSymbol(45)).assertEqual('cloud.bolt'); // THUNDERSHOWER_WITH_HAIL
      expect(conditionTypeToSFSymbol(11)).assertEqual('cloud.fog'); // FOG
      expect(conditionTypeToSFSymbol(73)).assertEqual('cloud.fog'); // HEAVY_FOGGY
      expect(conditionTypeToSFSymbol(32)).assertEqual('wind'); // WINDY
      expect(conditionTypeToSFSymbol(71)).assertEqual('sun.haze'); // HEAVY_HAZE
      expect(conditionTypeToSFSymbol(67)).assertEqual('sun.haze'); // SANDSTORM
    })

    it('hotColdNightMoonHaveOwnSymbols', 0, () => {
      expect(conditionTypeToSFSymbol(30)).assertEqual('thermometer.sun'); // HOT
      expect(conditionTypeToSFSymbol(31)).assertEqual('thermometer.snowflake'); // COLD
      expect(conditionTypeToSFSymbol(37)).assertEqual('moon.stars'); // HAZY_MOONLIGHT
    })

    it('undefinedAndUnknownFallBackToCloud', 0, () => {
      expect(conditionTypeToSFSymbol(0)).assertEqual('cloud'); // UNDEFINED
      expect(conditionTypeToSFSymbol(999)).assertEqual('cloud'); // 未来新增类型
      expect(conditionTypeToSFSymbol(-1)).assertEqual('cloud');
    })

    // ---- caiyunSkyconToSFSymbol（彩云 skycon → SF Symbol 名，Q7 词表） ----

    it('caiyunClearMapsByDayNight', 0, () => {
      expect(caiyunSkyconToSFSymbol('CLEAR_DAY')).assertEqual('sun.max');
      expect(caiyunSkyconToSFSymbol('CLEAR_NIGHT')).assertEqual('moon.stars');
      expect(caiyunSkyconToSFSymbol('PARTLY_DAY')).assertEqual('cloud.sun');
      expect(caiyunSkyconToSFSymbol('PARTLY_NIGHT')).assertEqual('cloud.moon');
    })

    it('caiyunRainGradesMapByIntensity', 0, () => {
      expect(caiyunSkyconToSFSymbol('LIGHT_RAIN')).assertEqual('cloud.rain');
      expect(caiyunSkyconToSFSymbol('MODERATE_RAIN')).assertEqual('cloud.rain');
      expect(caiyunSkyconToSFSymbol('HEAVY_RAIN')).assertEqual('cloud.heavyrain');
      expect(caiyunSkyconToSFSymbol('STORM')).assertEqual('cloud.heavyrain');
    })

    it('caiyunSnowFogHazeWindHaveOwnSymbols', 0, () => {
      expect(caiyunSkyconToSFSymbol('LIGHT_SNOW')).assertEqual('cloud.snow');
      expect(caiyunSkyconToSFSymbol('HEAVY_SNOW')).assertEqual('cloud.snow');
      expect(caiyunSkyconToSFSymbol('STORM_SNOW')).assertEqual('cloud.snow');
      expect(caiyunSkyconToSFSymbol('FOG')).assertEqual('cloud.fog');
      expect(caiyunSkyconToSFSymbol('HEAVY_HAZE')).assertEqual('sun.haze');
      expect(caiyunSkyconToSFSymbol('SAND')).assertEqual('sun.haze');
      expect(caiyunSkyconToSFSymbol('WIND')).assertEqual('wind');
    })

    it('caiyunUnknownSkyconFallsBackToCloud', 0, () => {
      expect(caiyunSkyconToSFSymbol('')).assertEqual('cloud');
      expect(caiyunSkyconToSFSymbol('SOMETHING_NEW')).assertEqual('cloud');
    })

    // ---- placeNameFromAddress（精度三档 + 降级链） ----

    it('cityLevelPrefersLocality', 0, () => {
      expect(placeNameFromAddress(LOCATION_PRECISION_CITY, fullAddress())).assertEqual('广州市');
    })

    it('cityLevelFallsBackToAdministrativeArea', 0, () => {
      const parts = fullAddress();
      parts.locality = undefined; // 直辖市场景 locality 可能为空
      expect(placeNameFromAddress(LOCATION_PRECISION_CITY, parts)).assertEqual('广东省');

      const bare: PlaceAddressParts = { administrativeArea: '重庆市' };
      expect(placeNameFromAddress(LOCATION_PRECISION_CITY, bare)).assertEqual('重庆市');
    })

    it('districtLevelJoinsCityAndDistrict', 0, () => {
      expect(placeNameFromAddress(LOCATION_PRECISION_DISTRICT, fullAddress()))
        .assertEqual('广州市 天河区');
    })

    it('districtLevelFallsBackToCity', 0, () => {
      const parts = fullAddress();
      parts.subLocality = undefined; // 郊野可能没有区县
      expect(placeNameFromAddress(LOCATION_PRECISION_DISTRICT, parts)).assertEqual('广州市');
    })

    it('streetLevelPrefersPremises', 0, () => {
      // 地标 / 楼宇优先（街道级最有记忆点的信息，iOS areasOfInterest 同款优先级）
      expect(placeNameFromAddress(LOCATION_PRECISION_STREET, fullAddress()))
        .assertEqual('广州塔');
    })

    it('streetLevelUsesRoadWhenNoPremises', 0, () => {
      const parts = fullAddress();
      parts.premises = undefined;
      expect(placeNameFromAddress(LOCATION_PRECISION_STREET, parts))
        .assertEqual('天河区 天河路10号');
    })

    it('streetLevelFallsBackToDistrictThenCity', 0, () => {
      // 街道字段全空：先退到区县（iOS [district, street] compactMap 的同款结果）
      const parts = fullAddress();
      parts.premises = undefined;
      parts.roadName = undefined;
      parts.subRoadName = undefined;
      expect(placeNameFromAddress(LOCATION_PRECISION_STREET, parts))
        .assertEqual('天河区');

      // 区县也没有：退到「市」
      const bare: PlaceAddressParts = { locality: '广州市' };
      expect(placeNameFromAddress(LOCATION_PRECISION_STREET, bare)).assertEqual('广州市');
    })

    it('emptyAddressReturnsEmptyString', 0, () => {
      const empty: PlaceAddressParts = {};
      expect(placeNameFromAddress(LOCATION_PRECISION_CITY, empty)).assertEqual('');
      expect(placeNameFromAddress(LOCATION_PRECISION_DISTRICT, empty)).assertEqual('');
      expect(placeNameFromAddress(LOCATION_PRECISION_STREET, empty)).assertEqual('');
    })

    it('unknownPrecisionBehavesLikeCity', 0, () => {
      // 旧数据 / 手改坏了的精度值不崩，按默认市档
      expect(placeNameFromAddress('bogus', fullAddress())).assertEqual('广州市');
    })

    // ---- AppPrefs 精度归一化（旧数据兜底） ----

    it('appPrefsNormalizesPrecision', 0, () => {
      expect(AppPrefs.normalizedLocationPrecision('city'))
        .assertEqual(LOCATION_PRECISION_CITY);
      expect(AppPrefs.normalizedLocationPrecision('district'))
        .assertEqual(LOCATION_PRECISION_DISTRICT);
      expect(AppPrefs.normalizedLocationPrecision('street'))
        .assertEqual(LOCATION_PRECISION_STREET);
      expect(AppPrefs.normalizedLocationPrecision(''))
        .assertEqual(LOCATION_PRECISION_CITY);
      expect(AppPrefs.normalizedLocationPrecision('nonsense'))
        .assertEqual(LOCATION_PRECISION_CITY);
    })
  })
}
