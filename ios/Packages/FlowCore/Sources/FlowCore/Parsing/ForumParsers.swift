import Foundation
import SwiftSoup

/// Разбор страницы `index.php?map=0`. Повторяет `GetForumUseCase.kt` из Android-версии Flow.
enum ForumTreeParser {
    static func parse(_ html: String) throws -> ForumTree {
        let doc = try SwiftSoup.parse(html)
        var roots: [ForumNode] = []

        for (index, rootElement) in try doc.select(".tree-root").array().enumerated() {
            let titleElement = try rootElement.select(".c-title")
            var name = titleElement.attrOrEmpty("title")
            if name.isEmpty { name = titleElement.textOrEmpty() }
            if name.isEmpty { name = "Раздел \(index + 1)" }

            var forums = try positionalForums(in: rootElement)
            if forums.isEmpty {
                // Запасной путь, если вёрстка изменилась: все ссылки на форумы подряд.
                for anchor in try rootElement.select("a").array() {
                    guard let id = ParserUtils.forumID(from: anchor.attrOrEmpty("href")) else { continue }
                    forums.append(ForumNode(id: id, name: anchor.textOrEmpty()))
                }
            }
            roots.append(ForumNode(id: "c-\(index)", name: name, children: forums))
        }

        guard !roots.isEmpty else { throw FlowError.noData }
        return ForumTree(roots: roots)
    }

    /// Те же позиции элементов, что в Android-версии: `child(0).child(1).children()`.
    private static func positionalForums(in root: Element) throws -> [ForumNode] {
        let top = root.children().array()
        guard let first = top.first else { return [] }
        let firstChildren = first.children().array()
        guard firstChildren.count > 1 else { return [] }

        var forums: [ForumNode] = []
        for forumElement in firstChildren[1].children().array() {
            let parts = forumElement.children().array()
            guard let head = parts.first,
                  let anchor = try head.select("a").first(),
                  let id = ParserUtils.forumID(from: anchor.attrOrEmpty("href")) else { continue }

            var subforums: [ForumNode] = []
            if parts.count > 1 {
                for subElement in parts[1].children().array() {
                    guard let subAnchor = try subElement.select("a").first(),
                          let subID = ParserUtils.forumID(from: subAnchor.attrOrEmpty("href")) else { continue }
                    var subName = subAnchor.textOrEmpty()
                    if subName.isEmpty { subName = subElement.textOrEmpty() }
                    subforums.append(ForumNode(id: subID, name: subName))
                }
            }
            forums.append(ForumNode(id: id, name: anchor.textOrEmpty(), children: subforums))
        }
        return forums
    }
}

/// Разбор страницы `viewforum.php`. Повторяет `GetCategoryPageUseCase.kt` из Android-версии Flow.
enum ForumPageParser {
    static func parse(_ html: String, forumID: String) throws -> ForumPage {
        let doc = try SwiftSoup.parse(html)

        let navigation = try doc.select("#pagination > p:nth-child(1)")
        let currentPage = try navigation.select("b:nth-child(1)").intValue() ?? 1
        let totalPages = try navigation.select("b:nth-child(2)").intValue() ?? 1
        let forumName = try doc.select(".maintitle").first()?.textOrEmpty() ?? ""

        var subforums: [CategoryRef] = []
        for anchor in try doc.select(".forumlink > a").array() {
            guard let id = ParserUtils.queryParam(anchor.attrOrEmpty("href"), "f") else { continue }
            subforums.append(CategoryRef(id: id, name: anchor.textOrEmpty()))
        }

        let category = CategoryRef(id: forumID, name: forumName)
        var topics: [TorrentSummary] = []
        for row in try doc.select("table.vf-table.forum tr.hl-tr").array() {
            var id = ParserUtils.digits(try row.select("td").attrOrEmpty("id"))
            if id.isEmpty { id = ParserUtils.digits(row.id()) }
            guard !id.isEmpty else { continue }

            let authorLink = try row.select("a.topicAuthor")
            var authorName = authorLink.textOrEmpty()
            var authorID: String?
            if authorName.isEmpty {
                authorName = try row.select(".vf-col-author").textOrEmpty()
            } else {
                authorID = ParserUtils.queryParam(authorLink.attrOrEmpty("href"), "u")
            }
            let author: Author? = authorName.isEmpty ? nil : Author(id: authorID, name: authorName)

            let fullTitle = try row.select(".tt-text").textOrEmpty()
            let status = ParserUtils.status(in: row)
            let size = try row.select(".f-dl").textOrEmpty().replacingOccurrences(of: "\u{00A0}", with: " ")

            topics.append(
                TorrentSummary(
                    id: id,
                    title: status == nil ? fullTitle : ParserUtils.title(from: fullTitle),
                    tags: status == nil ? "" : ParserUtils.tags(from: fullTitle),
                    author: author,
                    category: category,
                    status: status,
                    date: nil,
                    size: size,
                    seeds: try row.select(".seedmed").intValue(),
                    leeches: try row.select(".leechmed").intValue()
                )
            )
        }

        return ForumPage(
            id: forumID,
            name: forumName,
            page: currentPage,
            totalPages: totalPages,
            subforums: subforums,
            topics: topics
        )
    }
}

/// Разбор сообщений темы. Повторяет `ParseCommentsPageUseCase.kt` из Android-версии Flow.
enum CommentsParser {
    static func parse(_ html: String) throws -> CommentsPage {
        let doc = try SwiftSoup.parse(html)

        let navigation = try doc.select("#pagination p:nth-child(1)")
        let currentPage = try navigation.select("b:nth-child(1)").intValue() ?? 1
        let totalPages = try navigation.select("b:nth-child(2)").intValue() ?? 1

        var comments: [Comment] = []
        for post in try doc.select("tbody[id^=post]").array() {
            // Первое сообщение раздачи (с magnet-ссылкой) — это описание, а не комментарий.
            let magnet = try post.select(".magnet-link").attrOrEmpty("href")
            if !magnet.isEmpty { continue }

            guard let body = try post.select(".post_body").first() else { continue }
            var id = body.attrOrEmpty("id")
            if id.hasPrefix("p-") { id = String(id.dropFirst(2)) }
            if id.isEmpty { id = ParserUtils.digits(post.id()) }
            guard !id.isEmpty else { continue }

            let name = try post.select(".nick").first()?.textOrEmpty() ?? ""
            let profileHref = try post.select(".poster_btn").select(".txtb").first()?.attrOrEmpty("href") ?? ""
            let author: Author? = name.isEmpty
                ? nil
                : Author(id: ParserUtils.queryParam(profileHref, "u"), name: name)

            var avatarURL: URL?
            let avatar = try post.select(".avatar > img").attrOrEmpty("src")
            if let url = URL(string: avatar), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                avatarURL = url
            }

            comments.append(
                Comment(
                    id: id,
                    author: author,
                    avatarURL: avatarURL,
                    dateText: try post.select(".p-link").textOrEmpty(),
                    text: PostTextExtractor.text(from: body)
                )
            )
        }
        return CommentsPage(page: currentPage, totalPages: totalPages, comments: comments)
    }
}
