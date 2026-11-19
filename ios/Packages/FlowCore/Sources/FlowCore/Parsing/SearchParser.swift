import Foundation
import SwiftSoup

/// Разбор страницы `tracker.php`. Селекторы взяты из `GetSearchPageUseCase.kt` в Android-версии.
enum SearchParser {
    static func parse(_ html: String) throws -> SearchPage {
        let doc = try SwiftSoup.parse(html)

        let navigation = try doc.select("#main_content_wrap > div.bottom_info > div.nav > p:nth-child(1)")
        let currentPage = try navigation.select("b:nth-child(1)").intValue() ?? 1
        let totalPages = try navigation.select("b:nth-child(2)").intValue() ?? 1

        var items: [TorrentSummary] = []
        for row in try doc.select(".hl-tr").array() {
            let titleLink = try row.select(".t-title > a")
            let id = titleLink.attrOrEmpty("data-topic_id")
            guard !id.isEmpty else { continue }

            let titleWithTags = titleLink.textOrEmpty()

            let authorLink = try row.select(".u-name > a")
            let authorName = authorLink.textOrEmpty()
            let author: Author? = authorName.isEmpty
                ? nil
                : Author(id: ParserUtils.queryParam(authorLink.attrOrEmpty("href"), "pid"), name: authorName)

            let categoryLink = try row.select(".f")
            var category: CategoryRef?
            if let categoryId = ParserUtils.queryParam(categoryLink.attrOrEmpty("href"), "f") {
                category = CategoryRef(id: categoryId, name: categoryLink.textOrEmpty())
            }

            let sizeElement = try row.select(".tor-size")
            let size: String
            if let bytes = Int64(sizeElement.attrOrEmpty("data-ts_text")) {
                size = ParserUtils.formatSize(bytes)
            } else {
                size = sizeElement.textOrEmpty()
            }

            let dateText = try row.select("[style]").attrOrEmpty("data-ts_text")
            let date = Double(dateText).map { Date(timeIntervalSince1970: $0) }

            items.append(
                TorrentSummary(
                    id: id,
                    title: ParserUtils.title(from: titleWithTags),
                    tags: ParserUtils.tags(from: titleWithTags),
                    author: author,
                    category: category,
                    // Если статус не распознан, Android-версия считает раздачу «проверяется».
                    status: ParserUtils.status(in: row) ?? .checking,
                    date: date,
                    size: size,
                    seeds: try row.select(".seedmed").intValue(),
                    leeches: try row.select(".leechmed").intValue()
                )
            )
        }
        return SearchPage(page: currentPage, totalPages: totalPages, items: items)
    }
}
