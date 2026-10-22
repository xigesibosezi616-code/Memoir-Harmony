import Foundation

/// 网络层抽象边界。背后可切 `URLSessionHTTPClient`（真）/ `MockHTTPClient`（测试 + Mock 服务）。
///
/// 通过 `AppEnvironment.http` 注入，由 AI 服务、未来天气/OpenAI 调用方共用。
/// **不做**：业务 model、retry、缓存、日志、自动展示错误（解耦，由调用方决定）。
protocol HTTPClient {
    /// 发起请求并 JSON 解码为 `Response` 类型。
    func send<Response: Decodable>(_ request: HTTPRequest) async throws -> Response

    /// 发起请求只取 `Data`（不需要解码 / 二进制下载场景）。
    func sendRaw(_ request: HTTPRequest) async throws -> Data
}

// MARK: - 请求模型

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct HTTPRequest {
    var url: URL
    var method: HTTPMethod = .get
    var headers: [String: String] = [:]
    var body: Data? = nil
    /// 单次请求超时（秒），默认 30。
    var timeout: TimeInterval = 30

    // MARK: 常用便利构造器

    static func get(_ url: URL, headers: [String: String] = [:]) -> HTTPRequest {
        HTTPRequest(url: url, method: .get, headers: headers)
    }

    /// POST + JSON body。自动加 Content-Type: application/json。
    static func postJSON<Body: Encodable>(
        _ url: URL,
        body: Body,
        headers: [String: String] = [:],
        encoder: JSONEncoder = .iso8601
    ) throws -> HTTPRequest {
        var allHeaders = headers
        allHeaders["Content-Type"] = "application/json"
        let data = try encoder.encode(body)
        return HTTPRequest(url: url, method: .post, headers: allHeaders, body: data)
    }

    /// PATCH + JSON body（局部更新，如 `PATCH /me` 只改昵称）。
    static func patchJSON<Body: Encodable>(
        _ url: URL,
        body: Body,
        headers: [String: String] = [:],
        encoder: JSONEncoder = .iso8601
    ) throws -> HTTPRequest {
        var allHeaders = headers
        allHeaders["Content-Type"] = "application/json"
        let data = try encoder.encode(body)
        return HTTPRequest(url: url, method: .patch, headers: allHeaders, body: data)
    }
}

// MARK: - 错误模型

/// 统一网络错误。实现 `LocalizedError` 让 `ErrorPresenter.present(_:fallback:)` 直接展示。
enum HTTPError: LocalizedError {
    case badURL
    case offline
    case timeout
    case cancelled
    /// 4xx / 5xx 状态码。body 用于 debug，UI 一般不展示。
    case status(code: Int, body: Data?)
    /// JSON decode 失败。
    case decoding(any Error)
    /// 其它 URLSession / 系统层错误兜底。
    case transport(any Error)

    var errorDescription: String? {
        switch self {
        // 这些会经 ErrorPresenter 显示给用户 —— `Text(String)` 不查本地化表，
        // 必须显式 NSLocalizedString（`.appLanguage` 而非 `.main`，见 Bundle+AppLanguage）
        case .badURL:
            return NSLocalizedString("请求地址无效", bundle: .appLanguage, comment: "网络错误")
        case .offline:
            return NSLocalizedString("网络未连接，请检查 Wi-Fi 或蜂窝数据", bundle: .appLanguage, comment: "网络错误")
        case .timeout:
            return NSLocalizedString("请求超时，稍后再试", bundle: .appLanguage, comment: "网络错误")
        case .cancelled:
            return NSLocalizedString("请求已取消", bundle: .appLanguage, comment: "网络错误")
        case .status(let code, _):
            return String(format: NSLocalizedString("服务器响应异常（%lld）", bundle: .appLanguage, comment: "网络错误，%lld 是 HTTP 状态码"), code)
        case .decoding:
            return NSLocalizedString("响应数据格式错误", bundle: .appLanguage, comment: "网络错误")
        case .transport(let underlying):  return underlying.localizedDescription
        }
    }
}

// MARK: - JSONEncoder/Decoder 默认配置

extension JSONEncoder {
    /// 全项目网络层共用的 encoder：日期 ISO8601。
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    /// 全项目网络层共用的 decoder：日期 ISO8601。
    ///
    /// 🔴 **不能用内置的 `.iso8601` 策略。**
    /// 后端的日期一律是 `new Date(...).toISOString()`，**一定带毫秒**（`…:30.123Z`），
    /// 而内置策略不认小数秒 —— 哪个响应里只要出现一个 `let x: Date`，
    /// **整条解码都会失败**，而且报的是「数据损坏」这种看不出所以然的错。
    /// 这里两种格式都认。
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = ISO8601DateFormatter.memoirDate(from: raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "无法解析 ISO8601 日期：\(raw)"
                ))
            }
            return date
        }
        return d
    }()
}

extension ISO8601DateFormatter {
    /// 带小数秒的（后端实际发的就是这种）
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 不带小数秒的（手写的、或别的服务发来的）
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 两种 ISO8601 都认：先按带小数秒试，再退回不带的
    static func memoirDate(from raw: String) -> Date? {
        withFraction.date(from: raw) ?? plain.date(from: raw)
    }
}
