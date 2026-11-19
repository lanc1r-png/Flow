import Foundation

/// Клиент рутрекера. Повторяет сетевой слой Android-версии Flow (`RuTrackerInnerApiImpl`):
/// те же адреса, параметры и способ авторизации.
public final class RuTrackerClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://rutracker.org/forum/")!

    private let transport: any HTTPTransport
    private let baseURL: URL
    /// Кодировка значений в адресной строке. Android-версия отправляет UTF-8 и поиск по русским словам работает.
    /// Если на реальном сайте запросы с кириллицей вернут мусор, переключите на `.windowsCP1251`.
    private let queryEncoding: String.Encoding
    /// User-Agent браузера, в котором пройдена проверка Cloudflare. Кука `cf_clearance` привязана к нему.
    private let userAgent: String?

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        baseURL: URL = RuTrackerClient.defaultBaseURL,
        queryEncoding: String.Encoding = .utf8,
        userAgent: String? = nil
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.queryEncoding = queryEncoding
        self.userAgent = userAgent
    }

    // MARK: - Авторизация

    /// Вход по логину и паролю. Если сайт требует капчу, вернёт `.captchaRequired`,
    /// после чего вход нужно повторить, передав `captcha`.
    public func login(
        username: String,
        password: String,
        captcha: CaptchaAnswer? = nil
    ) async throws -> LoginResult {
        var form: [(String, String)] = [
            ("login_username", username),
            ("login_password", password),
            ("login", "Вход"),
        ]
        if let captcha {
            form.append(("cap_sid", captcha.sid))
            form.append((captcha.codeField, captcha.value))
        }

        let loginURL = makeURL("login.php")
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.httpBody = PercentEncoding.formBody(form)
        request.setValue("application/x-www-form-urlencoded; charset=windows-1251", forHTTPHeaderField: "Content-Type")
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }

        // Сессия приходит в ответе на сам POST, до редиректа на форум, поэтому редиректы не выполняем.
        let response = try await transport.send(request, followRedirects: false)
        if Self.isChallenge(response) { throw FlowError.challenge }

        if let token = SessionCookie.token(from: response) {
            // Как и в Android-версии, не считаем вход успешным, пока главная страница не подтвердит авторизацию.
            guard let user = try await currentUser(token: token) else {
                throw FlowError.unknown
            }
            return .success(Session(token: token, username: user.name))
        }
        do {
            return try LoginParser.parseFailure(html: response.text, loginURL: loginURL)
        } catch let error as FlowError where error == .noData || error == .unknown {
            throw FlowError.unexpectedPage(Self.diagnostics(for: response))
        }
    }

    /// Описание ответа без секретов: значения кук и пароль сюда не попадают.
    static func diagnostics(for response: HTTPResponse) -> String {
        var lines = ["HTTP \(response.status), \(response.url.absoluteString)"]
        if let type = response.header("Content-Type") { lines.append("Content-Type: \(type)") }
        if let location = response.header("Location") { lines.append("Location: \(location)") }
        if let raw = response.header("Set-Cookie"),
           let regex = try? NSRegularExpression(pattern: "(?:^|,\\s*)([A-Za-z0-9_.\\-]+)=") {
            let range = NSRange(raw.startIndex..., in: raw)
            let names = regex.matches(in: raw, range: range).compactMap { match -> String? in
                Range(match.range(at: 1), in: raw).map { String(raw[$0]) }
            }
            lines.append("Set-Cookie: " + (names.isEmpty ? "(пусто)" : names.joined(separator: ", ")))
        } else {
            lines.append("Set-Cookie: нет")
        }
        lines.append("Размер: \(response.data.count) байт")
        lines.append("Текст: " + LoginParser.pageSnippet(response.text))
        return lines.joined(separator: "\n")
    }

    /// Возвращает пользователя, если токен рабочий, иначе `nil`.
    public func currentUser(token: String) async throws -> UserInfo? {
        let html = try await fetchHTML(makeURL("index.php"), token: token)
        guard LoginParser.isAuthorized(html) else { return nil }
        return UserInfo(name: LoginParser.username(from: html) ?? "")
    }

    // MARK: - Поиск

    /// Поиск раздач. Страницы нумеруются с 1, на странице до 50 раздач.
    public func search(token: String, query: SearchQuery, page: Int = 1) async throws -> SearchPage {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = makeURL("tracker.php", query: [
            ("nm", text.isEmpty ? nil : text),
            ("o", query.sort.rawValue),
            ("s", query.order.rawValue),
            ("tm", query.period.rawValue),
            ("start", page > 1 ? String(50 * (page - 1)) : nil),
        ])
        let html = try await fetchHTML(url, token: token)
        guard LoginParser.isAuthorized(html) else { throw FlowError.unauthorized }
        return try SearchParser.parse(html)
    }

    // MARK: - Раздача

    public func torrent(token: String, id: String) async throws -> TorrentDetails {
        let html = try await fetchHTML(makeURL("viewtopic.php", query: [("t", id)]), token: token)
        guard TopicChecks.exists(html) else { throw FlowError.notFound }
        if TopicChecks.isModerated(html) { throw FlowError.onModeration }
        if TopicChecks.isBlockedForRegion(html) { throw FlowError.blockedForRegion }
        return try TorrentParser.parse(html)
    }

    /// Скачивает `.torrent`. `title` нужен только для имени файла.
    public func downloadTorrentFile(token: String, id: String, title: String) async throws -> TorrentFile {
        let response = try await transport.send(
            makeGet(makeURL("dl.php", query: [("t", id)]), token: token),
            followRedirects: true
        )
        if Self.isChallenge(response) { throw FlowError.challenge }
        try Self.check(status: response.status)

        // Корректный .torrent — это bencode-словарь, он начинается с буквы `d`.
        guard response.data.first == UInt8(ascii: "d") else {
            let text = response.text
            if text.contains("login_username") || !LoginParser.isAuthorized(text) {
                throw FlowError.unauthorized
            }
            throw FlowError.invalidTorrentFile
        }
        return TorrentFile(fileName: Self.fileName(title: title, id: id), data: response.data)
    }

    // MARK: - Внутреннее

    private func fetchHTML(_ url: URL, token: String?) async throws -> String {
        let response = try await transport.send(makeGet(url, token: token), followRedirects: true)
        if Self.isChallenge(response) { throw FlowError.challenge }
        try Self.check(status: response.status)
        return response.text
    }

    private func makeGet(_ url: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token {
            request.setValue(token, forHTTPHeaderField: "Cookie")
        }
        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        return request
    }

    func makeURL(_ path: String, query: [(String, String?)] = []) -> URL {
        var string = baseURL.absoluteString
        if !string.hasSuffix("/") { string += "/" }
        string += path

        var pairs: [String] = []
        for (key, value) in query {
            guard let value else { continue }
            pairs.append("\(key)=\(PercentEncoding.encode(value, encoding: queryEncoding, spaceAsPlus: false))")
        }
        if !pairs.isEmpty {
            string += "?" + pairs.joined(separator: "&")
        }
        return URL(string: string)!
    }

    /// Страница-заглушка Cloudflare с проверкой браузером.
    static func isChallenge(_ response: HTTPResponse) -> Bool {
        guard response.status == 403 || response.status == 503 else { return false }
        let text = response.text
        return text.contains("Just a moment") || text.contains("challenge-platform") || text.contains("cf-chl")
    }

    static func check(status: Int) throws {
        switch status {
        case 200..<400: return
        case 401: throw FlowError.unauthorized
        case 403: throw FlowError.forbidden
        case 404: throw FlowError.notFound
        default: throw FlowError.badResponse(status)
        }
    }

    static func fileName(title: String, id: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = title.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "t\(id)" : String(cleaned.prefix(100))
        return base + ".torrent"
    }
}
