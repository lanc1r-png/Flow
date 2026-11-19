import Foundation
import SwiftSoup

/// Разбор страницы `viewtopic.php`. Селекторы взяты из `ParseTorrentUseCase.kt` и `ParseTopicPageUseCase.kt`.
enum TorrentParser {
    static func parse(_ html: String) throws -> TorrentDetails {
        let doc = try SwiftSoup.parse(html)

        let titleElement = try doc.select("#topic-title")
        guard let id = ParserUtils.queryParam(titleElement.attrOrEmpty("href"), "t") else {
            throw FlowError.noData
        }
        let titleWithTags = titleElement.textOrEmpty()

        let nickName = try doc.select(".nick").first()?.textOrEmpty() ?? ""
        let authorHref = try doc.select(".poster_btn").select(".txtb").first()?.attrOrEmpty("href") ?? ""
        let author: Author? = nickName.isEmpty
            ? nil
            : Author(id: ParserUtils.queryParam(authorHref, "u"), name: nickName)

        var category: CategoryRef?
        if let last = try doc.select(".nav.w100.pad_2").select("a").last(),
           let categoryId = ParserUtils.queryParam(last.attrOrEmpty("href"), "f") {
            category = CategoryRef(id: categoryId, name: last.textOrEmpty())
        }

        let magnet = try doc.select(".magnet-link").attrOrEmpty("href")

        let header = try doc.select("table.forumline.dl_list > tbody > tr")
        let seeds = try header.select(".seed > b").intValue()
        let leeches = try header.select(".leech > b").intValue()

        let status = ParserUtils.status(in: try doc.select("#tor-status-resp").first())

        let size: String
        if LoginParser.isAuthorized(html) {
            size = try doc.select("#tor-size-humn").textOrEmpty()
        } else {
            size = try doc.select(".attach_link > ul > li:nth-child(2)").textOrEmpty()
        }

        let firstPost = try doc.select("tbody[id^=post]").first()
        var description = ""
        var posterURL: URL?
        var publishedText: String?
        if let firstPost {
            if let body = try firstPost.select(".post_body").first() {
                description = PostTextExtractor.text(from: body)
            }
            let posterString = try firstPost.select(".postImg.postImgAligned.img-right").attrOrEmpty("title")
            if let url = URL(string: posterString), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                posterURL = url
            }
            let published = try firstPost.select(".p-link").textOrEmpty()
            publishedText = published.isEmpty ? nil : published
        }

        return TorrentDetails(
            id: id,
            title: ParserUtils.title(from: titleWithTags),
            tags: ParserUtils.tags(from: titleWithTags),
            author: author,
            category: category,
            status: status,
            size: size.isEmpty ? nil : size,
            seeds: seeds,
            leeches: leeches,
            magnetLink: magnet.isEmpty ? nil : magnet,
            description: description,
            posterURL: posterURL,
            publishedText: publishedText
        )
    }
}

/// Превращает тело сообщения в обычный текст: переносы строк сохраняются, картинки и разметка отбрасываются.
/// Полноценный разбор форматирования (цвета, спойлеры, цитаты) — задача следующих версий.
enum PostTextExtractor {
    private static let blockTags: Set<String> = [
        "div", "p", "ul", "ol", "li", "table", "tr", "hr", "blockquote", "pre", "h1", "h2", "h3", "h4",
    ]

    static func text(from element: Element) -> String {
        var out = ""
        walk(element, into: &out)
        let cleaned = out
            .replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func walk(_ node: Node, into out: inout String) {
        for child in node.getChildNodes() {
            if let textNode = child as? TextNode {
                out += textNode.getWholeText().replacingOccurrences(of: "\u{00A0}", with: " ")
            } else if let element = child as? Element {
                let tag = element.tagName().lowercased()
                if element.hasClass("q-wrap") {
                    // Цитата: каждую строку помечаем полоской.
                    var inner = ""
                    walk(element, into: &inner)
                    let quoted = inner
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { "▎ " + String($0) }
                        .joined(separator: "\n")
                    if !out.isEmpty, !out.hasSuffix("\n") { out += "\n" }
                    out += quoted + "\n"
                    continue
                }
                switch tag {
                case "br":
                    out += "\n"
                case "script", "style", "var", "img":
                    // На рутрекере картинки — это `<var class="postImg" title="URL">`.
                    continue
                default:
                    let isBlock = blockTags.contains(tag)
                    if isBlock, !out.isEmpty, !out.hasSuffix("\n") { out += "\n" }
                    walk(element, into: &out)
                    if isBlock, !out.hasSuffix("\n") { out += "\n" }
                }
            }
        }
    }
}
