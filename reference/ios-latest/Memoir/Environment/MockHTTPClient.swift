import Foundation

/// 测试 / Mock 服务用的 `HTTPClient` 实现。
///
/// 用法：
/// 1. **预设响应**：`MockHTTPClient(stub: .data(json))` —— 任何请求都返回这段数据
/// 2. **预设错误**：`MockHTTPClient(stub: .failure(.offline))` —— 任何请求都抛错
/// 3. **按 URL 路由**：`MockHTTPClient(router: { req in ... })` —— 自己根据请求决定返回
///
/// 也支持模拟延迟（`simulatedDelay`），方便压测"AI 生成中"loading UI。
final class MockHTTPClient: HTTPClient {

    enum Stub {
        case data(Data)
        case failure(HTTPError)
    }

    /// 简单模式：固定 stub
    var stub: Stub
    /// 进阶模式：按 request 自定义路由（优先级高于 stub）
    var router: ((HTTPRequest) -> Stub)?
    /// 模拟网络延迟（秒），默认 0
    var simulatedDelay: TimeInterval = 0

    /// 记录历史请求，方便单测断言
    private(set) var sentRequests: [HTTPRequest] = []

    init(stub: Stub = .failure(.transport(NSError(domain: "MockHTTPClient", code: -1))),
         simulatedDelay: TimeInterval = 0,
         router: ((HTTPRequest) -> Stub)? = nil) {
        self.stub = stub
        self.simulatedDelay = simulatedDelay
        self.router = router
    }

    func send<Response: Decodable>(_ request: HTTPRequest) async throws -> Response {
        let data = try await sendRaw(request)
        do {
            return try JSONDecoder.iso8601.decode(Response.self, from: data)
        } catch {
            throw HTTPError.decoding(error)
        }
    }

    func sendRaw(_ request: HTTPRequest) async throws -> Data {
        sentRequests.append(request)
        if simulatedDelay > 0 {
            try await Task.sleep(for: .seconds(simulatedDelay))
        }
        let resolved = router?(request) ?? stub
        switch resolved {
        case .data(let data):
            return data
        case .failure(let error):
            throw error
        }
    }
}
