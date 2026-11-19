import Foundation
import SwiftSoup

/// Разбор ответа `login.php`. Логика взята из `LoginUseCase.kt`.
enum LoginParser {
    static func isAuthorized(_ html: String) -> Bool {
        html.contains("logged-in-username")
    }

    static func username(from html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html),
              let element = try? doc.select("#logged-in-username").first() else {
            return nil
        }
        let name = element.textOrEmpty()
        return name.isEmpty ? nil : name
    }

    /// Начало видимого текста страницы — для диагностики.
    static func pageSnippet(_ html: String, limit: Int = 400) -> String {
        let text = (try? SwiftSoup.parse(html).text()) ?? html
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(limit))
    }

    /// Вызывается, когда в ответе на вход не оказалось сессионной куки.
    static func parseFailure(html: String, loginURL: URL) throws -> LoginResult {
        let doc = try SwiftSoup.parse(html)
        let captcha = parseCaptcha(doc, loginURL: loginURL)
        let pageText = (try? doc.text()) ?? ""

        let wrongCredentialsMarkers = ["неверный пароль", "неверное имя пользователя"]
        if wrongCredentialsMarkers.contains(where: { pageText.range(of: $0, options: .caseInsensitive) != nil }) {
            return .wrongCredentials(captcha)
        }
        if let captcha {
            return .captchaRequired(captcha)
        }
        if !(try doc.select("#login-form, .login-form, input[name=login_username]").isEmpty()) {
            throw FlowError.unknown
        }
        throw FlowError.noData
    }

    private static func parseCaptcha(_ doc: Document, loginURL: URL) -> Captcha? {
        let sid = (try? doc.select("input[name=cap_sid]").attr("value")) ?? ""
        let codeField = (try? doc.select("input[name^=cap_code_]").attr("name")) ?? ""
        let source = (try? doc.select("img[src*=/captcha/]").attr("src")) ?? ""
        guard !sid.isEmpty, !codeField.isEmpty, !source.isEmpty,
              let url = URL(string: source, relativeTo: loginURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return Captcha(sid: sid, codeField: codeField, imageURL: url)
    }
}

/// Достаёт сессионную куку из заголовка `Set-Cookie`.
enum SessionCookie {
    static let name = "bb_session"

    static func token(from response: HTTPResponse) -> String? {
        guard let raw = response.header("Set-Cookie"), raw.contains(name) else { return nil }

        let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": raw], for: response.url)
        if let cookie = cookies.last(where: { $0.name == name }) {
            if cookie.value.isEmpty { return nil }
            if let expires = cookie.expiresDate, expires <= Date() { return nil }
            return "\(name)=\(cookie.value)"
        }

        // Запасной путь: Foundation отбрасывает куки с чужим доменом (например, при работе через зеркало).
        guard !raw.contains("Max-Age=0"), !raw.contains("1970"),
              let range = raw.range(of: "\(name)=([^;,\\s]+)", options: .regularExpression) else {
            return nil
        }
        let pair = String(raw[range])
        return pair == "\(name)=deleted" ? nil : pair
    }
}
