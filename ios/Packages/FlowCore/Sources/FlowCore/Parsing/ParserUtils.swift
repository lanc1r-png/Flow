import Foundation
import SwiftSoup

// Хелперы, повторяющие `Utils.kt` из Android-версии Flow.

extension Elements {
    func textOrEmpty() -> String {
        (try? text()) ?? ""
    }

    func attrOrEmpty(_ key: String) -> String {
        (try? attr(key)) ?? ""
    }

    func intValue() -> Int? {
        Int(textOrEmpty().trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension Element {
    func textOrEmpty() -> String {
        (try? text()) ?? ""
    }

    func attrOrEmpty(_ key: String) -> String {
        (try? attr(key)) ?? ""
    }
}

enum ParserUtils {
    /// Достаёт значение параметра из ссылки вида `viewtopic.php?t=123&start=30`.
    static func queryParam(_ href: String, _ key: String) -> String? {
        guard let question = href.firstIndex(of: "?") else { return nil }
        let query = href[href.index(after: question)...]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2, parts[0] == key {
                let value = String(parts[1])
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// `Ubuntu 24.04 [amd64] [ISO]` → название без квадратных скобок.
    static func title(from titleWithTags: String) -> String {
        var result = replacing(pattern: "\\[[^\\]]*\\]", in: titleWithTags, with: "")
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.replacingOccurrences(of: "[", with: "")
        result = result.replacingOccurrences(of: "]", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `Ubuntu 24.04 [amd64] [ISO]` → `[amd64] [ISO]`.
    static func tags(from titleWithTags: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\[[^\\]]*\\]") else { return "" }
        let range = NSRange(titleWithTags.startIndex..., in: titleWithTags)
        return regex.matches(in: titleWithTags, range: range)
            .compactMap { Range($0.range, in: titleWithTags).map { String(titleWithTags[$0]) } }
            .joined(separator: " ")
    }

    static func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let exponent = min(Int(log(Double(bytes)) / log(1024.0)), 6)
        let prefixes = Array("KMGTPE")
        let value = Double(bytes) / pow(1024.0, Double(exponent))
        return String(format: "%.1f", value) + " \(prefixes[exponent - 1])B"
    }

    static func status(in element: Element?) -> TorrentStatus? {
        guard let element else { return nil }
        func has(_ css: String) -> Bool {
            ((try? element.select(css))?.isEmpty() == false)
        }
        if has(".tor-dup") { return .duplicate }
        if has(".tor-not-approved") { return .notApproved }
        if has(".tor-checking") { return .checking }
        if has(".tor-approved") { return .approved }
        if has(".tor-need-edit") { return .needEdit }
        if has(".tor-closed") { return .closed }
        if has(".tor-no-desc") { return .noDescription }
        if has(".tor-consumed") { return .consumed }
        return nil
    }

    private static func replacing(pattern: String, in string: String, with template: String) -> String {
        string.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
}

/// Проверки текста страницы раздачи (как в `Utils.kt`).
enum TopicChecks {
    static func exists(_ html: String) -> Bool {
        !html.contains("Тема не найдена")
            && !html.contains("Тема находится в мусорке")
            && !html.contains("Ошибочный запрос: не указан topic_id")
    }

    static func isModerated(_ html: String) -> Bool {
        html.contains("Раздача ожидает проверки модератором")
    }

    static func isBlockedForRegion(_ html: String) -> Bool {
        html.contains("Извините, раздача недоступна для вашего региона")
    }
}

extension ParserUtils {
    /// Только цифры из строки: `tr-123` → `123`.
    static func digits(_ string: String) -> String {
        string.filter { $0.isASCII && $0.isNumber }
    }

    /// Id форума из ссылки: `viewforum.php?f=7`, `tracker.php?f=7`, `#f-7` или просто `7`.
    static func forumID(from href: String) -> String? {
        if let id = queryParam(href, "f"), !digits(id).isEmpty, digits(id) == id { return id }
        let parts = href.split(whereSeparator: { !($0.isASCII && $0.isNumber) })
        return parts.last.map(String.init)
    }
}
