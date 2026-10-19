/**
 * 写日记时的「此时此地」：当前天气 + 温度 + 地名（10_BUILD_MANUAL.md 2.10）。
 * 对应 iOS `Services/WeatherManager.swift`。
 *
 * - 定位：`geoLocationManager.getCurrentLocation`（@kit.LocationKit，系统定位）
 * - 天气：彩云天气 v2.6 实况接口（HTTPS 直连；官方 WeatherServiceKit 仅面向
 *   系统应用开放，AGC 无三方开通入口，Q8 拍板改彩云）
 * - 地名：优先 `site.reverseGeocode`（@kit.MapKit 逆地理，字段全：省市区/街道/POI，
 *   区县、街道档位靠它），失败退 `geoLocationManager.getAddressesFromLocation`
 *   （Location Kit 逆地理，只到市级），再走精度三档归一化
 *   （`PlaceWeatherFormat.placeNameFromAddress`，纯函数可单测）
 * - 天气失败自动重试一次，仍失败置 `weatherFailed` + 错误码（域+码）上屏（R-PLACE-04）
 * - 权限被拒置 `locationDenied`，UI 引导去系统设置（R-PLACE-03）
 * - 页面持有方式：`@State` 观察第一层属性；异步收尾后调用方再 bump 一次
 *   状态确保最终态渲染（见 ComposeView.startPlaceWeatherFetch）
 */
import { geoLocationManager } from '@kit.LocationKit';
import { http } from '@kit.NetworkKit';
import { site } from '@kit.MapKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPrefs } from './AppPrefs';
import {
  caiyunSkyconToSFSymbol,
  placeNameFromAddress,
  PlaceAddressParts
} from './PlaceWeatherFormat';

const DOMAIN = 0x0000;
const TAG = 'LocationWeather';

/** 天气重试前的等待（iOS 同款 2 秒：弱网/冷启动偶发首次失败，立刻放弃太可惜） */
const WEATHER_RETRY_DELAY_MS = 2000;
/** 彩云请求超时（iOS weatherTimeout 同款 8 秒） */
const WEATHER_TIMEOUT_MS = 8000;
/** 彩云个人版 token（v2.6 URL 鉴权，客户端直连用） */
const CAIYUN_TOKEN = 'inem5bDevyywOwJv';
const CAIYUN_BASE = 'https://api.caiyunapp.com/v2.6/';

/** 彩云实况接口的原始 JSON 形状（字段可缺，逐个 typeof 校验后才用） */
interface CaiyunRealtimeRaw {
  status?: string;
  result?: CaiyunResultRaw;
}

interface CaiyunResultRaw {
  realtime?: CaiyunRealtimeDetailRaw;
}

interface CaiyunRealtimeDetailRaw {
  status?: string;
  temperature?: number;
  skycon?: string;
}

/** 彩云取数失败（业务层错误：状态不对 / 字段缺失），code 直接上屏（R-PLACE-04） */
class WeatherApiError extends Error {
  readonly code: string;
  constructor(code: string) {
    super(code);
    this.code = code;
  }
}

/** 彩云实况数据（校验通过后的严格模型） */
class CaiyunRealtime {
  readonly temperature: number;
  readonly skycon: string;
  constructor(temperature: number, skycon: string) {
    this.temperature = temperature;
    this.skycon = skycon;
  }
}

export class LocationWeatherManager {
  /** 天气图标标识（SF Symbol 名，Q7 跨端词表；渲染时 weatherSymbolRes 再映射） */
  weatherCode: string = '';
  /** 温度展示文本，如 "26°" */
  weatherInfo: string = '';
  /** 自动解析出的地名（精度档位决定粒度） */
  locationInfo: string = '';
  /** 天气取失败（区别于还没开始取）：UI 给重试入口（R-PLACE-04） */
  weatherFailed: boolean = false;
  /** 失败原因（域 + 码），直接显示在界面上（排查靠截图，不让用户接电脑抓日志） */
  lastWeatherError: string = '';
  /** 定位权限被拒（鸿蒙拒过不再弹窗，只能引导去系统设置，R-PLACE-03） */
  locationDenied: boolean = false;
  /** 正在获取中（UI 占位「正在获取此时此地…」） */
  isResolving: boolean = false;
  /** 当前坐标（地点选择器搜附近 POI 用） */
  latitude: number = 0;
  longitude: number = 0;
  private hasCoordinate: boolean = false;
  /** 去重：进行中的那次请求没完不再发起（避免同一毫秒并发两套取天气） */
  private running: boolean = false;

  /** 有没有坐标可供地点选择器搜附近 */
  hasCoordinateForSearch(): boolean {
    return this.hasCoordinate;
  }

  /**
   * 草稿 / 已有内容恢复（R-ENTRY-05）：原样还原存草稿那一刻的快照，
   * **不重新定位**——重新取的话地点会悄悄变成现在的位置，日记就不是那天的此地了。
   */
  restore(weatherCode: string, weatherInfo: string, locationInfo: string): void {
    this.weatherCode = weatherCode;
    this.weatherInfo = weatherInfo;
    this.locationInfo = locationInfo;
    this.weatherFailed = false;
    this.lastWeatherError = '';
    this.locationDenied = false;
    this.isResolving = false;
  }

  /** 有没有可展示的内容（天气或地名，任一即算；iOS hasContent 同款） */
  hasDisplayContent(): boolean {
    return this.weatherCode.length > 0 || this.locationInfo.length > 0;
  }

  /**
   * 全流程：权限 → 定位 → 天气（失败重试一次）→ 逆地理（关了「记录位置」则跳过）。
   * 天气与地名各自独立成败：拿不到天气不影响记地名，反之亦然。
   */
  async requestLocationAndWeather(context: common.Context): Promise<void> {
    if (this.running) {
      return;
    }
    // 1. 定位权限（精确位置需 LOCATION + APPROXIMATELY_LOCATION 两条一起申请）
    const atManager = abilityAccessCtrl.createAtManager();
    const wanted: Array<Permissions> = [
      'ohos.permission.LOCATION',
      'ohos.permission.APPROXIMATELY_LOCATION'
    ];
    let granted = false;
    try {
      const result = await atManager.requestPermissionsFromUser(context, wanted);
      granted = result.authResults.length > 0;
      for (const code of result.authResults) {
        if (code !== 0) {
          granted = false;
        }
      }
    } catch (err) {
      const be = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'requestPermissions failed: %{public}d %{public}s',
        be.code, be.message ?? '');
      granted = false;
    }
    if (!granted) {
      // 拒过之后系统不再弹窗，UI 显示「去设置里开启」引导（R-PLACE-03）
      this.locationDenied = true;
      this.isResolving = false;
      return;
    }
    this.locationDenied = false;
    this.running = true;
    this.isResolving = true;
    try {
      // 2. 定位（默认优先级：日记只要公里级，不必导航级精度）
      const location = await geoLocationManager.getCurrentLocation();
      this.latitude = location.latitude;
      this.longitude = location.longitude;
      this.hasCoordinate = true;

      // 3. 天气（失败重试一次，错误码上屏）
      await this.fetchWeatherWithRetry();

      // 4. 逆地理（关掉「记录位置」时跳过——天气不受影响，用户可能只想要天气）
      if (AppPrefs.isLocationRecordingEnabled()) {
        this.locationInfo = await this.resolvePlaceName();
      } else {
        this.locationInfo = '';
      }
    } catch (err) {
      const be = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'location failed: %{public}d %{public}s',
        be.code, be.message ?? '');
    } finally {
      this.isResolving = false;
      this.running = false;
    }
  }

  /** 取天气：失败等 2 秒重试一次，仍失败置失败态 + 错误码（R-PLACE-04） */
  private async fetchWeatherWithRetry(): Promise<void> {
    let lastError = '';
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        const realtime = await this.fetchCaiyunRealtime();
        this.weatherCode = caiyunSkyconToSFSymbol(realtime.skycon);
        this.weatherInfo = `${Math.round(realtime.temperature)}°`;
        this.weatherFailed = false;
        this.lastWeatherError = '';
        hilog.info(DOMAIN, TAG, 'weather ok: %{public}s %{public}s skycon=%{public}s',
          this.weatherCode, this.weatherInfo, realtime.skycon);
        return;
      } catch (err) {
        if (err instanceof WeatherApiError) {
          lastError = err.code;
          hilog.error(DOMAIN, TAG, 'weather attempt %{public}d failed: %{public}s',
            attempt, err.code);
        } else {
          const be = err as BusinessError;
          lastError = `${be.code}`;
          hilog.error(DOMAIN, TAG, 'weather attempt %{public}d failed: %{public}d %{public}s',
            attempt, be.code, be.message ?? '');
        }
      }
      if (attempt === 1) {
        await LocationWeatherManager.sleep(WEATHER_RETRY_DELAY_MS);
      }
    }
    this.weatherFailed = true;
    this.lastWeatherError = lastError;
  }

  /** 彩云实况：HTTP GET → 校验 → 温度 + skycon；业务失败抛 WeatherApiError */
  private async fetchCaiyunRealtime(): Promise<CaiyunRealtime> {
    const client = http.createHttp();
    try {
      const url = `${CAIYUN_BASE}${CAIYUN_TOKEN}/${this.longitude},${this.latitude}/realtime`;
      const response = await client.request(url, {
        connectTimeout: WEATHER_TIMEOUT_MS,
        readTimeout: WEATHER_TIMEOUT_MS
      });
      if (response.responseCode !== 200) {
        throw new WeatherApiError(`caiyun http ${response.responseCode}`);
      }
      const body = response.result;
      if (typeof body !== 'string') {
        throw new WeatherApiError('caiyun non-string body');
      }
      const raw = JSON.parse(body) as CaiyunRealtimeRaw;
      if (raw.status !== 'ok' || raw.result === undefined || raw.result.realtime === undefined) {
        throw new WeatherApiError(`caiyun status ${raw.status ?? 'missing'}`);
      }
      const realtime = raw.result.realtime;
      if (typeof realtime.temperature !== 'number' || typeof realtime.skycon !== 'string') {
        throw new WeatherApiError('caiyun fields missing');
      }
      return new CaiyunRealtime(realtime.temperature, realtime.skycon);
    } finally {
      client.destroy();
    }
  }

  /**
   * 逆地理 + 精度归一化；失败只记日志（拿不到地名不算错，天气还在）。
   * 先走 Map Kit `site.reverseGeocode`（官方地图服务，字段最全：省市区/街道/POI，
   * 区县、街道档位靠它），失败或没解析出结果再退 Location Kit 逆地理（只到市级）。
   */
  private async resolvePlaceName(): Promise<string> {
    const precision = AppPrefs.currentLocationPrecision();
    try {
      const result = await site.reverseGeocode({
        location: { latitude: this.latitude, longitude: this.longitude },
        radius: 1000,
        language: 'zh'
      });
      const component = result.addressComponent;
      const firstPoi = result.pois !== undefined && result.pois.length > 0 ? result.pois[0] : undefined;
      const firstAoi = result.aois !== undefined && result.aois.length > 0 ? result.aois[0] : undefined;
      const firstRoad = result.roads !== undefined && result.roads.length > 0 ? result.roads[0] : undefined;
      const streetNumber = component.streetNumber;
      const parts: PlaceAddressParts = {
        // adminLevel1=省 / adminLevel2=市 / adminLevel3=区县（华为字段分层，对齐 GeoAddress 语义）
        administrativeArea: component.adminLevel1,
        locality: component.locality ?? component.adminLevel2,
        subLocality: component.adminLevel3 ?? component.subLocality1,
        // 街道档位最有记忆点的是 POI/地标名（iOS areasOfInterest 同款优先级）
        premises: firstPoi !== undefined ? firstPoi.name : (firstAoi !== undefined ? firstAoi.name : undefined),
        roadName: streetNumber !== undefined ? streetNumber.streetName :
          (firstRoad !== undefined ? firstRoad.name : undefined),
        subRoadName: streetNumber !== undefined ? streetNumber.streetNumber : undefined
      };
      const name = placeNameFromAddress(precision, parts);
      hilog.info(DOMAIN, TAG, 'map reverseGeocode: %{public}s -> %{public}s',
        result.addressDescription ?? '', name);
      if (name.length > 0) {
        return name;
      }
    } catch (err) {
      const be = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'map reverseGeocode failed: %{public}d %{public}s',
        be.code, be.message ?? '');
    }
    // 退路：Location Kit 逆地理（Map Kit 服务没开通时只有这条路，能拿到市级）
    try {
      const addresses = await geoLocationManager.getAddressesFromLocation({
        latitude: this.latitude,
        longitude: this.longitude,
        maxItems: 3
      });
      for (const address of addresses) {
        const parts: PlaceAddressParts = {
          administrativeArea: address.administrativeArea,
          locality: address.locality,
          subLocality: address.subLocality,
          premises: address.premises,
          roadName: address.roadName,
          subRoadName: address.subRoadName
        };
        const name = placeNameFromAddress(precision, parts);
        if (name.length > 0) {
          return name;
        }
      }
      return '';
    } catch (err) {
      const be = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'reverse geocode failed: %{public}d %{public}s',
        be.code, be.message ?? '');
      return '';
    }
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}
