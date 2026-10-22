import Foundation

/// 应用级依赖容器 —— 所有"可替换实现"的服务从这里取。
///
/// 当前只有 `ai`（Mock / Proxy 切换点）。后续会扩展：
/// - `letterStore: LetterStore` —— 来信状态机的数据访问
/// - `notifications: NotificationScheduler` —— 本地推送
/// 等
///
/// 注入方式：在 `MemoirApp` 中用 `@State` 持有一个实例，通过 `.environment(appEnvironment)`
/// 挂到根视图；View 端用 `@Environment(AppEnvironment.self) private var env` 读取。
@Observable
final class AppEnvironment {
    let ai: AIService
    let errors: ErrorPresenter
    let http: HTTPClient
    let auth: AuthService
    let session: UserSession
    /// CloudKit 同步的真实状态。**设置页据此判断要不要警告用户「数据还没上云」** ——
    /// 别再用「系统登没登 iCloud」冒充同步正常（2026-08-12 的数据丢失就是这么来的）。
    let cloudSync: CloudSyncMonitor

    /// `ai` / `auth` 传 nil 时用真后端实现（`BackendConfig.apiBaseURL`）。
    /// 想离线开发 UI 就显式注入 `MockAIService()` / `MockAuthService()`。
    init(
        ai: AIService? = nil,
        errors: ErrorPresenter = ErrorPresenter(),
        http: HTTPClient = URLSessionHTTPClient(),
        auth: AuthService? = nil,
        session: UserSession = UserSession(),
        cloudSync: CloudSyncMonitor = CloudSyncMonitor()
    ) {
        self.errors = errors
        self.http = http
        self.session = session
        self.cloudSync = cloudSync
        self.auth = auth ?? LiveAuthService(baseURL: BackendConfig.apiBaseURL, http: http)
        // ProxyAIService 需要 session 取 token，所以必须在 session 之后构造
        self.ai = ai ?? ProxyAIService(
            baseURL: BackendConfig.apiBaseURL,
            http: http,
            session: session
        )
    }
}
