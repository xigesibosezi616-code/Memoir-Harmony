import Foundation

/// 真实 AI 来信服务 —— 走自家后端（`POST /letter`），后端再调 DeepSeek。
///
/// **为什么不直连 DeepSeek**：API key 绝不能进客户端；而且 prompt 是产品核心资产，
/// 放服务端才能随时迭代、不用发版。客户端只发日记内容，拿回一封信。
struct ProxyAIService: AIService {
    let baseURL: URL
    let http: HTTPClient
    /// 取 JWT 用；生成来信是受保护接口
    let session: UserSession

    /// 生成一封信可能要十几秒（LLM 出字慢），超时给足
    private static let timeout: TimeInterval = 90

    func generateLetter(for context: LetterContext) async throws -> LetterDraft {
        guard let token = session.token else {
            throw AIServiceError.notLoggedIn
        }

        var request = try HTTPRequest.postJSON(
            baseURL.appending(path: "letter"),
            body: LetterRequestDTO(context: context),
            headers: ["Authorization": "Bearer \(token)"]
        )
        request.timeout = Self.timeout

        do {
            let resp: LetterResponseDTO = try await http.send(request)
            guard !resp.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIServiceError.generationFailed("来信内容为空")
            }
            return LetterDraft(body: resp.body, fromCharacter: resp.fromCharacter)
        } catch let e as AIServiceError {
            throw e
        } catch {
            throw Self.mapError(error, session: session, penPalName: context.penPalName)
        }
    }

    /// 补领：把服务端已经写好的信拉回来（协议注释里有为什么需要它）
    func fetchLetters(limit: Int = 20) async throws -> [LetterSummary] {
        guard let token = session.token else {
            throw AIServiceError.notLoggedIn
        }
        var url = baseURL.appending(path: "letters")
        url.append(queryItems: [URLQueryItem(name: "limit", value: String(limit))])
        var request = HTTPRequest.get(url, headers: ["Authorization": "Bearer \(token)"])
        request.timeout = 30

        do {
            let resp: LetterListDTO = try await http.send(request)
            return resp.letters.compactMap(\.summary)
        } catch let e as AIServiceError {
            throw e
        } catch {
            throw Self.mapError(error, session: session)
        }
    }

    /// 来信节奏：`GET /me/rhythm`（判定权只在服务端，这里只是提前问一声）
    func fetchRhythm() async throws -> LetterRhythm {
        guard let token = session.token else {
            throw AIServiceError.notLoggedIn
        }
        var request = HTTPRequest.get(baseURL.appending(path: "me/rhythm"), headers: ["Authorization": "Bearer \(token)"])
        request.timeout = 15

        do {
            let resp: RhythmDTO = try await http.send(request)
            return LetterRhythm(canRequestNow: resp.canRequestNow, reason: resp.reason,
                                nextLetterAt: resp.nextLetterAt, tier: resp.tier)
        } catch let e as AIServiceError {
            throw e
        } catch {
            throw Self.mapError(error, session: session)
        }
    }

    /// 把 HTTP 层错误翻成 AIServiceError；后端的中文文案能直接展示给用户。
    private static func mapError(_ error: any Error, session: UserSession, penPalName: String = "") -> AIServiceError {
        guard case HTTPError.status(let code, let body) = error else {
            if let httpError = error as? HTTPError {
                return .network(httpError)
            }
            return .generationFailed(error.localizedDescription)
        }

        let envelope = body.flatMap {
            try? JSONDecoder.iso8601.decode(APIErrorEnvelope.self, from: $0)
        }

        // 登录过期：清掉本地登录态，UI 自然回到未登录
        if code == 401 {
            session.clear()
            return .notLoggedIn
        }
        if code == 429 {
            return .rateLimit(reason: envelope?.reason, retryAfter: envelope?.retryAfter.map(TimeInterval.init), penPalName: penPalName)
        }
        if let message = envelope?.error.message {
            return .generationFailed(message)
        }
        return .network(.status(code: code, body: body))
    }
}

// MARK: - 协议类型（与 Backend/shared/src/types.ts 对齐）

/// ⚠️ 不发 `userName`：昵称由服务端从 `users.display_name` 取，客户端传值不被采信。
private struct LetterRequestDTO: Encodable {
    struct Entry: Encodable {
        let title: String
        let textContent: String
        let date: Date
        let mood: String?
    }

    let entries: [Entry]
    let triggerKind: String
    let dominantMood: String?
    let penPalName: String
    let language: String

    init(context: LetterContext) {
        entries = context.entries.map {
            Entry(title: $0.title, textContent: $0.textContent, date: $0.date, mood: $0.mood)
        }
        triggerKind = context.triggerKind.rawValue
        dominantMood = context.dominantMood
        penPalName = context.penPalName
        // 回信语言跟着日记写的语言走，认不出来用尺素的应用语言（见 `LetterLanguage`）。
        // ⚠️ 以前这里取的是 `Locale.current`（系统语言），系统英文的用户写中文日记收到了英文信
        language = LetterLanguage.forLetter(texts: context.entries.map { "\($0.title)\n\($0.textContent)" })
    }
}

/// `GET /me/rhythm`，对齐 `RhythmResponse`
private struct RhythmDTO: Decodable {
    let tier: String
    let nextLetterAt: Date?
    let canRequestNow: Bool
    let reason: String
}

private struct LetterResponseDTO: Decodable {
    let body: String
    let fromCharacter: String
}

private struct LetterListDTO: Decodable {
    let letters: [Item]

    struct Item: Decodable {
        let body: String
        let fromCharacter: String
        /// 后端发的带毫秒，由 `JSONDecoder.iso8601` 统一处理（见那里的注释）
        let generatedAt: Date

        var summary: LetterSummary? {
            guard !body.isEmpty else { return nil }
            return LetterSummary(body: body, fromCharacter: fromCharacter, generatedAt: generatedAt)
        }
    }
}
