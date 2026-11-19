import Foundation

public struct HTTPResponse: Sendable {
    public let url: URL
    public let status: Int
    public let headers: [String: String]
    public let data: Data

    public init(url: URL, status: Int, headers: [String: String] = [:], data: Data = Data()) {
        self.url = url
        self.status = status
        self.headers = headers
        self.data = data
    }

    /// Поиск заголовка без учёта регистра.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public var text: String {
        TextDecoding.decode(data, contentType: header("Content-Type"))
    }
}

/// Тонкая обёртка над сетью, чтобы клиент можно было тестировать без интернета.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest, followRedirects: Bool) async throws -> HTTPResponse
}

/// Транспорт на `URLSession`.
///
/// Куки не хранятся в общем хранилище: токен сессии клиент передаёт сам через заголовок `Cookie`,
/// так аккаунты не смешиваются, а `Set-Cookie` остаётся доступным для разбора.
public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest, followRedirects: Bool) async throws -> HTTPResponse {
        let delegate: (any URLSessionTaskDelegate)? = followRedirects ? nil : NoRedirectDelegate()
        let (data, response) = try await session.data(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse else {
            throw FlowError.badResponse(-1)
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }
        return HTTPResponse(
            url: http.url ?? request.url ?? URL(fileURLWithPath: "/"),
            status: http.statusCode,
            headers: headers,
            data: data
        )
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
