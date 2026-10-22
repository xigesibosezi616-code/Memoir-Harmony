import Foundation
import CoreLocation

/// 你大概在哪 —— 世界笔友地图上的「你」、信要走多远、地图该是白天还是夜里，都靠它。
///
/// - **只在本机用，不上传**（产品定：位置不离开手机）
/// - 只要「大致位置」（`kCLLocationAccuracyReduced`，几公里的精度），记下来时再取整到 0.1°（约 10 公里）
/// - 记一份在本机：下次打开地图不用等定位，「你」立刻就在
/// - 不主动弹权限框：地图上有一行「打开定位」，用户点了才问（天气那边问过、给过的话直接用）
@Observable
final class ApproximateLocation: NSObject, CLLocationManagerDelegate {
    /// 取整后的坐标；nil = 还不知道（没给权限，或者还没定到）
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var authorization: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()
    private static let storageKey = "penPalMapLastLocation"

    override init() {
        authorization = manager.authorizationStatus
        coordinate = Self.loadSaved()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// 能用定位就定一次（进地图页时调）
    func refresh() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    /// 用户点了「打开定位」
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            refresh()
        }
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        refresh()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let rounded = CLLocationCoordinate2D(
            latitude: (location.coordinate.latitude * 10).rounded() / 10,
            longitude: (location.coordinate.longitude * 10).rounded() / 10
        )
        coordinate = rounded
        UserDefaults.standard.set([rounded.latitude, rounded.longitude], forKey: Self.storageKey)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 定不到就用上次记下的（或者没有「你」），不打扰用户
        let ns = error as NSError
        NSLog("⚠️ [ApproximateLocation] 定位失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
    }

    private static func loadSaved() -> CLLocationCoordinate2D? {
        guard let pair = UserDefaults.standard.array(forKey: storageKey) as? [Double], pair.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
    }
}
