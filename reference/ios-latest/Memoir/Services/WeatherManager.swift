import SwiftUI
import CoreLocation
import WeatherKit

/// 定位记录的精细程度。用户在设置里选，只影响**之后**写的日记，已写的保持原样。
enum LocationPrecision: String, CaseIterable {
    /// 市级行政区：广州市
    case city
    /// 区县级：广州市 天河区
    case district
    /// 街道 / 地标店名：广州塔、天河区 天河路
    case street

    /// 见 `HomeDisplayMode.displayName`：常驻界面的文案用 `LocalizedStringKey`
    var displayName: LocalizedStringKey {
        switch self {
        case .city:     return "市"
        case .district: return "区县"
        case .street:   return "街道"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .city:     return "只记到城市，如「广州市」"
        case .district: return "记到区县，如「广州市 天河区」"
        case .street:   return "记到街道或地标，如「广州塔」"
        }
    }

    // MARK: 设置读写（UserDefaults key 与 SettingsView 的 @AppStorage 一致）
    static let storageKey = "locationPrecision"
    static let enabledKey = "locationRecordingEnabled"

    static var current: LocationPrecision {
        LocationPrecision(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .city
    }
    /// 默认开启：未设置过时 object(forKey:) 为 nil
    static var isRecordingEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}

/// 写日记时的「此时此地」：当前天气 + 温度 + 地名。
///
/// 天气走 WeatherKit（需要 `com.apple.developer.weatherkit` 权限 + 开发者后台开启 WeatherKit）；
/// 地名走 CLGeocoder 反地理编码，只取到城市/区一级 —— 日记不需要精确到街道，
/// 粗粒度也更符合「私密」的产品性格。
@Observable
class WeatherManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared
    private let geocoder = CLGeocoder()
    /// 正在跑的那次解析。用来去重，见 `locationManager(_:didUpdateLocations:)`
    private var resolveTask: Task<Void, Never>?

    /// 单次 WeatherKit 调用的超时。
    ///
    /// 🔴 **必须有。** `weather(for:)` 在鉴权失败后会**永久挂起、既不返回也不抛错**
    /// （2026-09-26 模拟器实测：失败后等了 20 分钟没有任何回音，App 进程还活着）。
    /// 没有超时的话 `resolve` 里的 `defer` 永远执行不到，界面就一直卡在
    /// 「正在获取此时此地…」，连重试入口都出不来 —— 用户看到的就是「天气功能是坏的」。
    private static let weatherTimeout: Duration = .seconds(12)

    /// 天气图标标识。
    ///
    /// **2026-08-08 起存的是 WeatherKit 自己给的 `symbolName`**（如 `sun.max.fill`）——
    /// 那就是苹果天气 App 在用的那套图标，比我们手工维护一张映射表准确得多，
    /// 也不会因为漏了某个天气类型就退化成一朵灰云。
    /// 旧日记里存的还是自定义代码（`clear` / `rain` …），`WeatherLocationBadge.weatherSymbol(for:)` 两种都认。
    var currentWeatherCode: String?
    /// 温度展示文本，如 "26°"
    var currentTemperature: String?
    /// 天气取失败了（区别于「还没开始取」）—— UI 据此给重试入口，
    /// 不然用户只会看到地点旁边空着一块，完全不知道发生了什么
    var weatherFailed = false
    /// 失败原因（`domain code`），直接显示在界面上。
    ///
    /// 🔴 **必须让用户看得见。** 以前只写进 `NSLog`，要排查就得让用户接上电脑抓日志 ——
    /// 「天气取不到」这个问题从 2026-07 拖到 09 月始终定位不了，卡的就是这一步：
    /// 谁都没拿到过那行错误码。现在直接摆在界面上，截图即可。
    var lastWeatherError: String?
    /// 定位权限被拒 / 被限制。
    ///
    /// 🔴 以前这种情况**什么都不做**：不提示、不记日志、连失败状态都不置，
    /// 用户点「记录天气与位置」毫无反应，看起来就是功能坏了。
    /// 而 iOS 的权限弹窗**只弹一次**，拒过之后永远是这个状态，只能去系统设置里改。
    var locationDenied = false
    /// 地名，如 "西安市"
    var currentPlaceName: String?
    /// 正在获取中（UI 显示占位）
    var isResolving = false
    /// 当前坐标 —— 手动挑选地点时用它搜附近 POI
    var currentCoordinate: CLLocationCoordinate2D?

    /// 是否已拿到可展示的内容
    var hasContent: Bool {
        currentWeatherCode != nil || currentPlaceName != nil
    }

    override init() {
        super.init()
        locationManager.delegate = self
        // 日记只需要城市级精度，低精度更省电也更快
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocationAndWeather() {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationDenied = false
            isResolving = true
            locationManager.requestLocation()
        case .denied, .restricted:
            // 🔴 这里以前是「什么都不做」，用户点了没反应。iOS 不会再弹第二次权限，
            // 只能引导他去系统设置。界面据此显示「去设置里开启」
            locationDenied = true
            isResolving = false
            NSLog("🔴[Weather] 定位权限不可用 status=%d（被拒或受限，需去系统设置开启）", status.rawValue)
        @unknown default:
            break
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        // 一次请求常常收到多次回调（`.task` 主动请求 + 授权变更回调各触发一次），
        // 不去重的话会并发跑两套取天气 —— 日志里看到的就是同一毫秒两条失败
        guard resolveTask == nil else { return }
        resolveTask = Task { [weak self] in
            await self?.resolve(at: location)
            self?.resolveTask = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // 同样用 NSLog + 完整 error：定位失败会连带天气一起没有，
        // 排查时必须能一眼分清「是定位就没成功」还是「定位成了、天气失败」
        let ns = error as NSError
        NSLog("🔴[Weather] 定位失败 domain=%@ code=%ld error=%@",
              ns.domain, ns.code, String(describing: error))
        isResolving = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            isResolving = true
            manager.requestLocation()
        }
    }

    // MARK: - 解析

    /// 天气与地名各自独立成败：拿不到天气不影响记地名，反之亦然。
    private func resolve(at location: CLLocation) async {
        defer { isResolving = false }
        currentCoordinate = location.coordinate

        await fetchWeather(at: location)

        // 关掉「记录位置」时不做反地理编码 —— 天气不受影响（用户可能只想要天气不想留地点）
        guard LocationPrecision.isRecordingEnabled else {
            currentPlaceName = nil
            return
        }

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let mark = placemarks.first {
                currentPlaceName = Self.placeName(from: mark, precision: LocationPrecision.current)
            }
        } catch {
            let ns = error as NSError
            NSLog("🔴[Weather] 地名解析失败 domain=%@ code=%ld", ns.domain, ns.code)
        }
    }

    /// 取当前天气。**失败会重试一次** —— WeatherKit 首次调用要跟服务端换令牌，
    /// 弱网或冷启动时偶发失败，一次性放弃太可惜（用户看到的就是"天气又没了"）。
    private func fetchWeather(at location: CLLocation, isRetry: Bool = false) async {
        do {
            let weather = try await weatherWithTimeout(at: location)
            let current = weather.currentWeather
            // 直接用 WeatherKit 给的 symbolName —— 苹果天气 App 用的就是这套图标
            currentWeatherCode = current.symbolName
            let celsius = current.temperature.converted(to: .celsius).value
            currentTemperature = "\(Int(celsius.rounded()))°"
            weatherFailed = false
            lastWeatherError = nil
            NSLog("🟢[Weather] %@ %@ condition=%@",
                  current.symbolName, currentTemperature ?? "?", String(describing: current.condition))
        } catch {
            // ⚠️ **必须打完整的 error，不能只打 localizedDescription** ——
            // WeatherKit 的 localizedDescription 基本都是「操作无法完成」这种没信息量的话，
            // 只有 domain + code 才能区分是权限没配、签名不对、还是限流/网络。
            //
            // 🔴 **而且必须用 `NSLog` 而不是 `print`。**
            // `print` 只有在 Xcode 连着调试时才看得见；用户平时是**在手机上点图标**打开
            // App 写日记的，那种情况下 `print` 什么都不输出 ——
            // 「天气排查需要一行真机日志」这件事从 2026-07 拖到 08 月始终拿不到日志，
            // 一半原因就在这里：不是没打，是打了也看不到。
            // NSLog 进系统日志，不连 Xcode 也能用 Console.app / `log stream --device` 抓。
            let ns = error as NSError
            NSLog("🔴[Weather] 获取失败%@ domain=%@ code=%ld error=%@",
                  isRetry ? "（重试仍失败）" : "，2 秒后重试",
                  ns.domain, ns.code, String(describing: error))

            guard isRetry else {
                try? await Task.sleep(for: .seconds(2))
                await fetchWeather(at: location, isRetry: true)
                return
            }

            weatherFailed = true
            // 摆到界面上给用户看，不必再去抓日志
            lastWeatherError = "\(ns.domain) \(ns.code)"
            NSLog("🔴[Weather] 排查顺序：① 真机还是模拟器（模拟器签名拿不到 WeatherKit 授权，必失败）"
                + " ② 描述文件里有没有 com.apple.developer.weatherkit"
                + " ③ 开发者后台 App ID 是否勾了 WeatherKit 且已同意条款"
                + " ④ 是否触发限流（免费额度 50 万次/月）")
        }
    }

    /// 给 WeatherKit 调用套一层超时，原因见 `weatherTimeout`。
    ///
    /// 超时后原来那个请求仍挂在后台（WeatherKit 不响应取消），但它已经不挡着界面了。
    private func weatherWithTimeout(at location: CLLocation) async throws -> Weather {
        try await withThrowingTaskGroup(of: Weather.self) { group in
            let service = weatherService
            group.addTask { try await service.weather(for: location) }
            group.addTask {
                try await Task.sleep(for: Self.weatherTimeout)
                throw WeatherTimeoutError()
            }
            guard let first = try await group.next() else { throw WeatherTimeoutError() }
            group.cancelAll()
            return first
        }
    }

    /// 按精度档位从 placemark 组装地名。每档都留了降级路径：
    /// 直辖市 locality 可能为空、郊野可能没有街道，取不到就退到上一级，绝不返回空串。
    static func placeName(from mark: CLPlacemark, precision: LocationPrecision) -> String? {
        let city = mark.locality ?? mark.administrativeArea
        let district = mark.subLocality ?? mark.subAdministrativeArea

        switch precision {
        case .city:
            return city

        case .district:
            return [city, district].compactMap { $0 }.joined(separator: " ").nilIfEmpty ?? city

        case .street:
            // 地标 / 店名优先（如「广州塔」），这是街道级最有记忆点的信息
            if let poi = mark.areasOfInterest?.first, !poi.isEmpty {
                return poi
            }
            let street = [mark.thoroughfare, mark.subThoroughfare]
                .compactMap { $0 }
                .joined()
            let parts = [district, street.nilIfEmpty].compactMap { $0 }
            return parts.joined(separator: " ").nilIfEmpty
                ?? [city, district].compactMap { $0 }.joined(separator: " ").nilIfEmpty
                ?? city
        }
    }

    // 原先这里有个 `mapCondition(_:)`，把 `WeatherCondition` 手工映射成自定义代码。
    // 2026-08-08 删除：改用 WeatherKit 自己的 `symbolName` 之后它就没有调用方了。
    // 那张手工表还有个毛病 —— WeatherCondition 有几十种取值，漏掉的一律落进
    // `default: "cloudy"`，晴天也可能显示成阴天。苹果给的 symbolName 不会出这种事。
}

/// WeatherKit 超时。单独一个类型，这样界面上显示的错误码一眼能区分
/// 「超时」和 WeatherKit 自己抛的错（如 `WDSJWTAuthenticatorServiceListener.Errors 2` 是鉴权失败）
struct WeatherTimeoutError: LocalizedError {
    var errorDescription: String? { "WeatherKit timeout" }
}
