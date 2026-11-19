import XCTest
@testable import FlowCore

// ВАЖНО: HTML в этих тестах написан вручную по селекторам из Android-версии Flow,
// это не снимки настоящих страниц. Они проверяют, что код делает то, что задумано,
// но не доказывают, что вёрстка рутрекера по-прежнему совпадает с селекторами.
// Лучшая проверка — запуск приложения с реальным аккаунтом.

final class PercentEncodingTests: XCTestCase {
    func testWindows1251FormBody() {
        let body = PercentEncoding.formBody([("login", "Вход"), ("a b", "x&y")])
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "login=%C2%F5%EE%E4&a+b=x%26y")
    }

    func testQueryEncodingUTF8() {
        XCTAssertEqual(PercentEncoding.encode("ёж 1", encoding: .utf8, spaceAsPlus: false), "%D1%91%D0%B6%201")
    }

    func testDecodeDefaultsToWindows1251() {
        let data = "Привет".data(using: .windowsCP1251)!
        XCTAssertEqual(TextDecoding.decode(data, contentType: "text/html"), "Привет")
        XCTAssertEqual(TextDecoding.decode(Data("Привет".utf8), contentType: "text/html; charset=utf-8"), "Привет")
    }
}

final class TitleParsingTests: XCTestCase {
    func testTitleAndTags() {
        let raw = "Ubuntu 24.04 [amd64] [ISO]"
        XCTAssertEqual(ParserUtils.title(from: raw), "Ubuntu 24.04")
        XCTAssertEqual(ParserUtils.tags(from: raw), "[amd64] [ISO]")
    }

    func testFormatSize() {
        XCTAssertEqual(ParserUtils.formatSize(512), "512 B")
        XCTAssertEqual(ParserUtils.formatSize(1_610_612_736), "1.5 GB")
    }

    func testQueryParam() {
        XCTAssertEqual(ParserUtils.queryParam("viewtopic.php?t=123&start=30", "t"), "123")
        XCTAssertNil(ParserUtils.queryParam("viewtopic.php", "t"))
    }
}

final class SessionCookieTests: XCTestCase {
    private let url = URL(string: "https://rutracker.org/forum/login.php")!

    private func response(_ setCookie: String) -> HTTPResponse {
        HTTPResponse(url: url, status: 302, headers: ["Set-Cookie": setCookie])
    }

    func testSessionIsFoundAmongOtherCookies() {
        let header = "bb_tracking=tracking; Path=/, bb_session=test-session; Path=/forum/; HttpOnly; Secure"
        XCTAssertEqual(SessionCookie.token(from: response(header)), "bb_session=test-session")
    }

    func testUnrelatedEmptyAndExpiredCookiesAreIgnored() {
        for header in [
            "bb_tracking=tracking",
            "bb_session=; Path=/",
            "bb_session=deleted; Max-Age=0",
            "bb_session=deleted; Expires=Thu, 01 Jan 1970 00:00:00 GMT",
        ] {
            XCTAssertNil(SessionCookie.token(from: response(header)), header)
        }
    }
}

final class LoginParserTests: XCTestCase {
    private let loginURL = URL(string: "https://rutracker.org/forum/login.php")!

    private func captchaForm(src: String) -> String {
        """
        <form>
            <input type="hidden" name="cap_sid" value="sid123">
            <input type="text" name="cap_code_dynamic">
            <img src="\(src)">
        </form>
        """
    }

    func testCaptchaRequired() throws {
        let result = try LoginParser.parseFailure(
            html: captchaForm(src: "//static.example.org/captcha/1.jpg?a=1"),
            loginURL: loginURL
        )
        guard case .captchaRequired(let captcha) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(captcha.sid, "sid123")
        XCTAssertEqual(captcha.codeField, "cap_code_dynamic")
        XCTAssertEqual(captcha.imageURL.absoluteString, "https://static.example.org/captcha/1.jpg?a=1")
    }

    func testWrongPassword() throws {
        let result = try LoginParser.parseFailure(html: "<p>Неверный <b>пароль</b></p>", loginURL: loginURL)
        guard case .wrongCredentials(let captcha) = result else { return XCTFail("\(result)") }
        XCTAssertNil(captcha)
    }

    func testUnknownPagesAreErrors() {
        XCTAssertThrowsError(try LoginParser.parseFailure(html: "<form><input name='login_username'></form>", loginURL: loginURL)) {
            XCTAssertEqual($0 as? FlowError, .unknown)
        }
        XCTAssertThrowsError(try LoginParser.parseFailure(html: "<p>Service unavailable</p>", loginURL: loginURL)) {
            XCTAssertEqual($0 as? FlowError, .noData)
        }
    }
}

final class SearchParserTests: XCTestCase {
    private let html = """
    <html><body>
    <div id="main_content_wrap">
      <table><tbody>
        <tr class="hl-tr">
          <td class="t-ico"><span class="tor-icon tor-approved">√</span></td>
          <td class="f-name-col"><div class="wbr"><a class="gen f" href="tracker.php?f=1105">Фильмы</a></div></td>
          <td class="t-title-col"><div class="wbr t-title"><a class="t-title" data-topic_id="6012345" href="viewtopic.php?t=6012345"><b>Ubuntu 24.04 [amd64] [ISO]</b></a></div></td>
          <td class="u-name-col"><div class="wbr u-name"><a href="tracker.php?pid=777">uploader</a></div></td>
          <td class="tor-size" data-ts_text="1610612736"><u>1610612736</u></td>
          <td><b class="seedmed">120</b></td>
          <td class="leechmed">15</td>
          <td class="small nowrap" style="padding: 3px 6px;" data-ts_text="1700000000"><p>19-Ноя-23</p></td>
        </tr>
      </tbody></table>
      <div class="bottom_info"><div class="nav"><p><b>2</b> из <b>5</b></p></div></div>
    </div>
    </body></html>
    """

    func testParsesRow() throws {
        let page = try SearchParser.parse(html)
        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.totalPages, 5)
        XCTAssertEqual(page.items.count, 1)

        let item = try XCTUnwrap(page.items.first)
        XCTAssertEqual(item.id, "6012345")
        XCTAssertEqual(item.title, "Ubuntu 24.04")
        XCTAssertEqual(item.tags, "[amd64] [ISO]")
        XCTAssertEqual(item.author, Author(id: "777", name: "uploader"))
        XCTAssertEqual(item.category, CategoryRef(id: "1105", name: "Фильмы"))
        XCTAssertEqual(item.status, .approved)
        XCTAssertEqual(item.size, "1.5 GB")
        XCTAssertEqual(item.seeds, 120)
        XCTAssertEqual(item.leeches, 15)
        XCTAssertEqual(item.date, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testEmptyPage() throws {
        let page = try SearchParser.parse("<html><body></body></html>")
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.totalPages, 1)
    }
}

final class TorrentParserTests: XCTestCase {
    private let html = """
    <html><body>
    <a id="logged-in-username" href="profile.php?mode=viewprofile&u=42">tester</a>
    <div class="nav w100 pad_2"><a href="index.php">Главная</a><a href="viewforum.php?f=1105">Фильмы</a></div>
    <a id="topic-title" href="viewtopic.php?t=6012345">Ubuntu 24.04 [amd64] [ISO]</a>
    <span id="tor-status-resp"><span class="tor-icon tor-approved">проверено</span></span>
    <span id="tor-size-humn">1.50 GB</span>
    <a class="magnet-link" href="magnet:?xt=urn:btih:ABCDEF&amp;dn=Ubuntu">magnet</a>
    <table class="forumline dl_list"><tbody><tr><td>
      <span class="seed">Сиды: <b>120</b></span> <span class="leech">Личи: <b>15</b></span>
    </td></tr></tbody></table>
    <table class="topic"><tbody id="post_1"><tr><td>
      <p class="nick">uploader</p>
      <div class="poster_btn"><a class="txtb" href="profile.php?mode=viewprofile&u=777">ЛС</a></div>
      <a class="p-link" href="#">19-Ноя-23 10:00</a>
      <div class="post_body" id="p-100">Описание<br>Вторая строка <var class="postImg postImgAligned img-right" title="https://example.com/poster.jpg"></var></div>
    </td></tr></tbody></table>
    </body></html>
    """

    func testParsesTopic() throws {
        let details = try TorrentParser.parse(html)
        XCTAssertEqual(details.id, "6012345")
        XCTAssertEqual(details.title, "Ubuntu 24.04")
        XCTAssertEqual(details.tags, "[amd64] [ISO]")
        XCTAssertEqual(details.author, Author(id: "777", name: "uploader"))
        XCTAssertEqual(details.category, CategoryRef(id: "1105", name: "Фильмы"))
        XCTAssertEqual(details.status, .approved)
        XCTAssertEqual(details.size, "1.50 GB")
        XCTAssertEqual(details.seeds, 120)
        XCTAssertEqual(details.leeches, 15)
        XCTAssertEqual(details.magnetLink, "magnet:?xt=urn:btih:ABCDEF&dn=Ubuntu")
        XCTAssertEqual(details.description, "Описание\nВторая строка")
        XCTAssertEqual(details.posterURL?.absoluteString, "https://example.com/poster.jpg")
        XCTAssertEqual(details.publishedText, "19-Ноя-23 10:00")
    }

    func testMissingMagnetIsNil() throws {
        let withoutMagnet = html.replacingOccurrences(of: "class=\"magnet-link\"", with: "class=\"other\"")
        XCTAssertNil(try TorrentParser.parse(withoutMagnet).magnetLink)
    }
}

// MARK: - Клиент с подменой сети

private final class MockTransport: HTTPTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private let handler: @Sendable (URLRequest) -> HTTPResponse

    init(handler: @escaping @Sendable (URLRequest) -> HTTPResponse) {
        self.handler = handler
    }

    func send(_ request: URLRequest, followRedirects: Bool) async throws -> HTTPResponse {
        requests.append(request)
        return handler(request)
    }
}

final class ClientTests: XCTestCase {
    private let authorizedPage = "<a id='logged-in-username' href='profile.php?u=42'>tester</a>"

    func testLoginSuccessSendsCp1251FormAndVerifiesSession() async throws {
        let page = authorizedPage
        let transport = MockTransport { request in
            let url = request.url!
            if url.path.hasSuffix("login.php") {
                return HTTPResponse(url: url, status: 302, headers: ["Set-Cookie": "bb_session=abc; Path=/forum/; HttpOnly"])
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "bb_session=abc")
            return HTTPResponse(url: url, status: 200, data: page.data(using: .windowsCP1251)!)
        }
        let client = RuTrackerClient(transport: transport)

        let result = try await client.login(username: "user", password: "пароль")
        guard case .success(let session) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(session.token, "bb_session=abc")
        XCTAssertEqual(session.username, "tester")

        let body = String(decoding: transport.requests[0].httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.hasPrefix("login_username=user&login_password="))
        XCTAssertTrue(body.contains("login=%C2%F5%EE%E4"))
    }

    func testCloudflareChallengeIsRecognized() async {
        let page = "<html><title>Just a moment...</title><body>Enable JavaScript and cookies to continue</body></html>"
        let client = RuTrackerClient(transport: MockTransport {
            HTTPResponse(url: $0.url!, status: 403, headers: ["Content-Type": "text/html; charset=UTF-8"], data: Data(page.utf8))
        })
        do {
            _ = try await client.search(token: "x", query: SearchQuery(text: "a"))
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? FlowError, .challenge)
        }
    }

    func testUserAgentIsSent() async throws {
        let transport = MockTransport { HTTPResponse(url: $0.url!, status: 200, data: Data("<p>x</p>".utf8)) }
        let client = RuTrackerClient(transport: transport, userAgent: "TestAgent/1.0")
        _ = try await client.currentUser(token: "bb_session=1")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "User-Agent"), "TestAgent/1.0")
    }

    func testUnexpectedLoginPageProducesDiagnostics() async throws {
        let transport = MockTransport { request in
            HTTPResponse(
                url: request.url!,
                status: 200,
                headers: ["Set-Cookie": "bb_ssl=1; Path=/"],
                data: Data("<p>Service unavailable</p>".utf8)
            )
        }
        do {
            _ = try await RuTrackerClient(transport: transport).login(username: "u", password: "secret")
            XCTFail("Ожидалась ошибка")
        } catch FlowError.unexpectedPage(let details) {
            XCTAssertTrue(details.contains("HTTP 200"))
            XCTAssertTrue(details.contains("Set-Cookie: bb_ssl"))
            XCTAssertTrue(details.contains("Service unavailable"))
            XCTAssertFalse(details.contains("secret"))
        }
    }

    func testSearchBuildsQueryAndRequiresAuthorization() async throws {
        let page = authorizedPage
        let transport = MockTransport { request in
            HTTPResponse(url: request.url!, status: 200, data: Data(page.utf8))
        }
        let client = RuTrackerClient(transport: transport)
        _ = try await client.search(
            token: "bb_session=abc",
            query: SearchQuery(text: "ubuntu", sort: .seeds, order: .descending, period: .week),
            page: 3
        )
        let url = try XCTUnwrap(transport.requests.first?.url?.absoluteString)
        XCTAssertEqual(url, "https://rutracker.org/forum/tracker.php?nm=ubuntu&o=10&s=2&tm=7&start=100")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Cookie"), "bb_session=abc")

        let loggedOut = MockTransport { HTTPResponse(url: $0.url!, status: 200, data: Data("<form></form>".utf8)) }
        do {
            _ = try await RuTrackerClient(transport: loggedOut).search(token: "x", query: SearchQuery(text: "a"))
            XCTFail("Ожидалась ошибка авторизации")
        } catch {
            XCTAssertEqual(error as? FlowError, .unauthorized)
        }
    }

    func testDownloadValidatesTorrentFile() async throws {
        let torrent = Data("d8:announce3:abce".utf8)
        let ok = RuTrackerClient(transport: MockTransport { HTTPResponse(url: $0.url!, status: 200, data: torrent) })
        let file = try await ok.downloadTorrentFile(token: "x", id: "1", title: "Фильм: часть 1")
        XCTAssertEqual(file.fileName, "Фильм_ часть 1.torrent")
        XCTAssertEqual(file.data, torrent)

        let html = RuTrackerClient(transport: MockTransport {
            HTTPResponse(url: $0.url!, status: 200, data: Data("<form><input name='login_username'></form>".utf8))
        })
        do {
            _ = try await html.downloadTorrentFile(token: "x", id: "1", title: "t")
            XCTFail("Ожидалась ошибка авторизации")
        } catch {
            XCTAssertEqual(error as? FlowError, .unauthorized)
        }
    }
}

// MARK: - Разделы, комментарии

final class ForumTests: XCTestCase {
    private let treeHTML = """
    <div class="tree-root">
      <div>
        <span class="c-title" title="Игры">Игры</span>
        <ul>
          <li><div><a href="viewforum.php?f=10">PC</a></div>
              <ul><li><a href="viewforum.php?f=11">Action</a></li></ul></li>
          <li><div><a href="viewforum.php?f=20">PlayStation</a></div></li>
        </ul>
      </div>
    </div>
    <div class="tree-root">
      <div>
        <span class="c-title" title="Музыка">Музыка</span>
        <ul><li><div><a href="viewforum.php?f=30">Рок</a></div></li></ul>
      </div>
    </div>
    """

    func testForumTree() throws {
        let tree = try ForumTreeParser.parse(treeHTML)
        XCTAssertEqual(tree.roots.map(\.name), ["Игры", "Музыка"])
        XCTAssertEqual(tree.roots.map(\.id), ["c-0", "c-1"])
        let games = tree.roots[0]
        XCTAssertEqual(games.children.map(\.id), ["10", "20"])
        XCTAssertEqual(games.children[0].children.map(\.id), ["11"])
        XCTAssertEqual(games.forumIDs, ["10", "11", "20"])
        XCTAssertEqual(tree.rootName(forForum: "11"), "Игры")
        XCTAssertEqual(tree.rootName(forForum: "30"), "Музыка")
        XCTAssertNil(tree.rootName(forForum: "999"))
    }

    func testForumTreeSearchAndCoding() throws {
        let tree = try ForumTreeParser.parse(treeHTML)
        let matches = tree.search("playstation")
        XCTAssertEqual(matches.map(\.node.id), ["20"])
        XCTAssertEqual(matches.first?.path, "Игры › PlayStation")

        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(ForumTree.self, from: data)
        XCTAssertEqual(decoded.roots, tree.roots)
        XCTAssertEqual(decoded.rootName(forForum: "11"), "Игры")
    }

    func testEmptyTreeIsError() {
        XCTAssertThrowsError(try ForumTreeParser.parse("<p>nothing</p>"))
    }

    func testForumIDFromHref() {
        XCTAssertEqual(ParserUtils.forumID(from: "viewforum.php?f=7"), "7")
        XCTAssertEqual(ParserUtils.forumID(from: "#f-123"), "123")
        XCTAssertEqual(ParserUtils.forumID(from: "55"), "55")
        XCTAssertNil(ParserUtils.forumID(from: "index.php"))
    }

    func testForumPage() throws {
        let html = """
        <div id="pagination"><p><b>2</b> из <b>5</b></p></div>
        <h1 class="maintitle">Игры PC</h1>
        <h4 class="forumlink"><a href="viewforum.php?f=11">Action</a></h4>
        <table class="vf-table forum"><tbody>
          <tr><td class="topicSep">Раздел</td></tr>
          <tr class="hl-tr"><td id="555"></td>
            <td><a class="tt-text">Game [PC] [2024]</a>
              <span class="seedmed">10</span> <span class="leechmed">2</span>
              <span class="f-dl">1.5&nbsp;GB</span>
              <a class="topicAuthor" href="profile.php?mode=viewprofile&amp;u=7">bob</a>
              <span class="tor-approved"></span></td></tr>
          <tr class="hl-tr"><td id="556"></td><td><a class="tt-text">Обсуждение</a></td></tr>
        </tbody></table>
        """
        let page = try ForumPageParser.parse(html, forumID: "10")
        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.totalPages, 5)
        XCTAssertEqual(page.name, "Игры PC")
        XCTAssertEqual(page.subforums, [CategoryRef(id: "11", name: "Action")])
        XCTAssertEqual(page.topics.count, 2)
        let first = page.topics[0]
        XCTAssertEqual(first.id, "555")
        XCTAssertEqual(first.title, "Game")
        XCTAssertEqual(first.tags, "[PC] [2024]")
        XCTAssertEqual(first.size, "1.5 GB")
        XCTAssertEqual(first.seeds, 10)
        XCTAssertEqual(first.leeches, 2)
        XCTAssertEqual(first.author, Author(id: "7", name: "bob"))
        XCTAssertEqual(first.status, .approved)
        XCTAssertEqual(first.category, CategoryRef(id: "10", name: "Игры PC"))
        let second = page.topics[1]
        XCTAssertNil(second.status)
        XCTAssertEqual(second.title, "Обсуждение")
    }

    func testCommentsSkipDescriptionAndFormatQuotes() throws {
        let html = """
        <div id="pagination"><table><tbody><tr><td><p><b>1</b> из <b>3</b></p></td></tr></tbody></table></div>
        <table>
        <tbody id="post_1"><tr>
          <td><p class="nick">Автор</p></td>
          <td><a class="p-link">01-Янв-24 10:00</a>
              <div class="post_body" id="p-111">Описание <a class="magnet-link" href="magnet:?xt=urn:btih:1">m</a></div></td>
        </tr></tbody>
        <tbody id="post_2"><tr>
          <td><p class="nick">Вася</p>
              <div class="avatar"><img src="https://example.com/a.png"></div>
              <span class="poster_btn"><a class="txtb" href="profile.php?mode=viewprofile&amp;u=5">ЛС</a></span></td>
          <td><a class="p-link">02-Янв-24 11:30</a>
              <div class="post_body" id="p-222">Привет!<br><div class="q-wrap"><div class="q-head">Автор писал(а):</div><div class="q">цитата</div></div>ответ</div></td>
        </tr></tbody>
        </table>
        """
        let page = try CommentsParser.parse(html)
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.totalPages, 3)
        XCTAssertEqual(page.comments.count, 1)
        let comment = try XCTUnwrap(page.comments.first)
        XCTAssertEqual(comment.id, "222")
        XCTAssertEqual(comment.author, Author(id: "5", name: "Вася"))
        XCTAssertEqual(comment.avatarURL, URL(string: "https://example.com/a.png"))
        XCTAssertEqual(comment.dateText, "02-Янв-24 11:30")
        XCTAssertEqual(comment.text, "Привет!\n▎ Автор писал(а):\n▎ цитата\nответ")
    }

    func testClientSearchAddsForumsAndLoadsComments() async throws {
        let authorized = "<a id='logged-in-username' href='profile.php?u=42'>tester</a>"
        let transport = MockTransport { request in
            HTTPResponse(url: request.url!, status: 200, data: Data(authorized.utf8))
        }
        let client = RuTrackerClient(transport: transport)
        _ = try await client.search(
            token: "bb_session=abc",
            query: SearchQuery(text: "x", forumIDs: ["1", "2"])
        )
        let searchURL = try XCTUnwrap(transport.requests.first?.url)
        let items = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first { $0.name == "f" }?.value, "1,2")

        let page = try await client.comments(token: "bb_session=abc", topicId: "9", page: 2)
        XCTAssertTrue(page.comments.isEmpty)
        let commentsURL = try XCTUnwrap(transport.requests.last?.url?.absoluteString)
        XCTAssertEqual(commentsURL, "https://rutracker.org/forum/viewtopic.php?t=9&start=30")

        let loggedOut = MockTransport { HTTPResponse(url: $0.url!, status: 200, data: Data("<p>x</p>".utf8)) }
        do {
            _ = try await RuTrackerClient(transport: loggedOut).comments(token: "x", topicId: "9")
            XCTFail("Ожидалась ошибка авторизации")
        } catch {
            XCTAssertEqual(error as? FlowError, .unauthorized)
        }
    }
}
