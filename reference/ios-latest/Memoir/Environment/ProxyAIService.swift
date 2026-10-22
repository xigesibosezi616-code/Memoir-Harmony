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

    /// 邮票夹：`GET /me/stamps`（余额只认服务端，这里只是提前问一声）
    func fetchStamps() async throws -> StampWallet {
        try await sendAuthorized(HTTPRequest.get(baseURL.appending(path: "me/stamps")), as: StampsDTO.self).wallet
    }

    /// 领这一包：`POST /me/stamps/claim`
    func claimStamps() async throws -> StampWallet {
        try await sendAuthorized(
            try HTTPRequest.postJSON(baseURL.appending(path: "me/stamps/claim"), body: EmptyBody()),
            as: StampsDTO.self
        ).wallet
    }

    /// 现在能寄的世界笔友：`GET /penpals`
    func fetchAvailablePenPals() async throws -> Set<String> {
        Set(try await sendAuthorized(HTTPRequest.get(baseURL.appending(path: "penpals")), as: AvailablePenPalsDTO.self).available)
    }

    /// 寄给一位世界笔友：`POST /penpal-letter`。三问模型（筛查 ‖ 写信 → 校对），给足时间
    func generatePenPalLetter(_ context: PenPalLetterContext) async throws -> PenPalLetterDraft {
        var request = try HTTPRequest.postJSON(baseURL.appending(path: "penpal-letter"), body: PenPalLetterRequestDTO(context: context))
        request.timeout = Self.timeout
        let resp = try await sendAuthorized(request, as: PenPalLetterResponseDTO.self)
        guard !resp.letter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.generationFailed("来信内容为空")
        }
        return PenPalLetterDraft(letter: resp.letter, translation: resp.translation, remember: resp.remember,
                                 danger: resp.danger, postage: resp.postage, generatedAt: resp.generatedAt, balance: resp.balance)
    }

    /// 带上登录态发出去，错误统一翻成 `AIServiceError`
    private func sendAuthorized<T: Decodable>(_ request: HTTPRequest, as type: T.Type) async throws -> T {
        guard let token = session.token else {
            throw AIServiceError.notLoggedIn
        }
        var request = request
        request.headers["Authorization"] = "Bearer \(token)"
        do {
            return try await http.send(request)
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
            return .rateLimit(reason: envelope?.reason, retryAfter: envelope?.retryAfter.map(TimeInterval.init),
                              penPalName: penPalName, nextPackAt: envelope?.nextPackAt)
        }
        if envelope?.reason == "member_required" { return .memberRequired }
        if envelope?.reason == "unknown_pen_pal" { return .penPalUnavailable }
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
    /// 同一个 id 服务端只写一封、只扣一张邮票（2026-10-16）
    let clientLetterId: String?

    init(context: LetterContext) {
        clientLetterId = context.clientLetterID?.uuidString
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

/// `GET /me/stamps` / `POST /me/stamps/claim`，对齐 `StampsResponse`
private struct StampsDTO: Decodable {
    let balance: Int
    let cap: Int
    let nextPackAt: Date
    let packReady: Bool
    let isMember: Bool

    var wallet: StampWallet {
        StampWallet(balance: balance, cap: cap, nextPackAt: nextPackAt, packReady: packReady, isMember: isMember)
    }
}

private struct EmptyBody: Encodable {}

private struct AvailablePenPalsDTO: Decodable {
    let available: [String]
}

/// 对齐 `PenPalLetterBody`
private struct PenPalLetterRequestDTO: Encodable {
    struct Entry: Encodable {
        let title: String
        let textContent: String
        let date: Date
        let mood: String?
    }
    struct Note: Encodable {
        let text: String
        let date: Date
    }

    let clientLetterId: String
    let penPalId: String
    let entries: [Entry]
    let dominantMood: String?
    let readerLanguage: String
    let memory: [Note]

    init(context: PenPalLetterContext) {
        clientLetterId = context.clientLetterID.uuidString
        penPalId = context.penPalID
        entries = context.entries.map { Entry(title: $0.title, textContent: $0.textContent, date: $0.date, mood: $0.mood) }
        dominantMood = context.dominantMood
        // 译文用日记写的语言（认不出来用尺素的应用语言），同 `LetterRequestDTO`
        readerLanguage = LetterLanguage.forLetter(texts: context.entries.map { "\($0.title)\n\($0.textContent)" })
        memory = context.memory.map { Note(text: $0.text, date: $0.notedAt) }
    }
}

/// 对齐 `PenPalLetterResponse`
private struct PenPalLetterResponseDTO: Decodable {
    let letter: String
    let translation: String
    let remember: [String]
    let danger: Bool
    let postage: Int
    let generatedAt: Date
    let balance: Int
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
        // 2026-10-16 起才有（老服务端不给）
        let clientLetterId: String?
        let penPalId: String?
        let translation: String?
        let danger: Bool?

        var summary: LetterSummary? {
            guard !body.isEmpty else { return nil }
            return LetterSummary(
                body: body,
                fromCharacter: fromCharacter,
                generatedAt: generatedAt,
                clientLetterID: clientLetterId.flatMap(UUID.init(uuidString:)),
                penPalID: penPalId,
                translation: translation,
                danger: danger ?? false
            )
        }
    }
}
