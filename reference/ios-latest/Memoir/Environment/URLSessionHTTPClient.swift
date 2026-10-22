import Foundation

/// 基于 `URLSession.shared` 的 `HTTPClient` 默认实现。
///
/// **职责边界**：
/// - 把 `HTTPRequest` 翻译为 `URLRequest` 并执行
/// - 把 URLSession 各种失败（断网、超时、取消、4xx/5xx、decode 失败）统一映射为 `HTTPError`
/// - 不做 retry / 缓存 / 日志（按 CLAUDE.md "不要自由发挥"，调用方按需）
struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, decoder: JSONDecoder = .iso8601) {
        self.session = session
        self.decoder = decoder
    }

    func send<Response: Decodable>(_ request: HTTPRequest) async throws -> Response {
        let data = try await sendRaw(request)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw HTTPError.decoding(error)
        }
    }

    func sendRaw(_ request: HTTPRequest) async throws -> Data {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = request.timeout
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                // 理论不可达：HTTP(S) 请求一定返回 HTTPURLResponse
                throw HTTPError.transport(URLError(.badServerResponse))
            }
            guard (200..<300).contains(http.statusCode) else {
                throw HTTPError.status(code: http.statusCode, body: data)
            }
            return data
        } catch let e as HTTPError {
            throw e
        } catch let urlError as URLError {
            throw Self.map(urlError)
        } catch {
            throw HTTPError.transport(error)
        }
    }

    /// 把 URLError 转成更可读的 HTTPError 分类。
    private static func map(_ urlError: URLError) -> HTTPError {
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost:
            return .offline
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .badURL, .unsupportedURL:
            return .badURL
        default:
            return .transport(urlError)
        }
    }
}
