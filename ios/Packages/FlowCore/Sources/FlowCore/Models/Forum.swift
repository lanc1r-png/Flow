import Foundation

/// Узел дерева разделов: корневая категория («Игры»), форум («PlayStation 5») или подфорум.
public struct ForumNode: Identifiable, Hashable, Sendable, Codable {
    /// Для форумов — числовой id с сайта, для корневых категорий — `c-0`, `c-1`, …
    public let id: String
    public let name: String
    public let children: [ForumNode]

    public init(id: String, name: String, children: [ForumNode] = []) {
        self.id = id
        self.name = name
        self.children = children
    }

    public var isRoot: Bool { id.hasPrefix("c-") }

    /// Id всех вложенных узлов (без самого узла).
    public var descendantIDs: [String] {
        children.flatMap { [$0.id] + $0.descendantIDs }
    }

    /// Id форумов, по которым нужно искать, если выбран этот узел: он сам (если это форум) и всё, что внутри.
    public var forumIDs: [String] {
        (isRoot ? [] : [id]) + descendantIDs
    }
}

public struct ForumMatch: Identifiable, Hashable, Sendable {
    public let node: ForumNode
    /// Путь вида `Игры › PlayStation`.
    public let path: String

    public var id: String { node.id }
}

/// Дерево разделов рутрекера (страница `index.php?map=0`).
public struct ForumTree: Sendable, Codable {
    public let roots: [ForumNode]

    private struct Entry: Sendable {
        let node: ForumNode
        let rootName: String
        let path: String
    }

    private let entries: [Entry]
    private let byID: [String: Entry]

    public init(roots: [ForumNode]) {
        self.roots = roots
        var entries: [Entry] = []

        func visit(_ node: ForumNode, rootName: String, parentPath: String) {
            let path = parentPath.isEmpty ? node.name : parentPath + " › " + node.name
            if !node.isRoot {
                entries.append(Entry(node: node, rootName: rootName, path: path))
            }
            for child in node.children {
                visit(child, rootName: rootName, parentPath: path)
            }
        }
        for root in roots {
            visit(root, rootName: root.name, parentPath: "")
        }

        var index: [String: Entry] = [:]
        for entry in entries where index[entry.node.id] == nil {
            index[entry.node.id] = entry
        }
        self.entries = entries
        self.byID = index
    }

    private enum CodingKeys: String, CodingKey {
        case roots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(roots: try container.decode([ForumNode].self, forKey: .roots))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(roots, forKey: .roots)
    }

    /// Название корневой категории, в которой лежит форум.
    public func rootName(forForum id: String) -> String? {
        byID[id]?.rootName
    }

    public func node(id: String) -> ForumNode? {
        byID[id]?.node
    }

    /// Поиск форумов по части названия (без учёта регистра).
    public func search(_ text: String, limit: Int = 60) -> [ForumMatch] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var result: [ForumMatch] = []
        for entry in entries where entry.node.name.localizedCaseInsensitiveContains(query) {
            result.append(ForumMatch(node: entry.node, path: entry.path))
            if result.count >= limit { break }
        }
        return result
    }
}

/// Страница форума (`viewforum.php`).
public struct ForumPage: Sendable {
    public let id: String
    public let name: String
    public let page: Int
    public let totalPages: Int
    public let subforums: [CategoryRef]
    /// Темы форума. У обычных (не раздач) тем `status == nil`, размера и сидов нет.
    public let topics: [TorrentSummary]

    public init(
        id: String,
        name: String,
        page: Int,
        totalPages: Int,
        subforums: [CategoryRef],
        topics: [TorrentSummary]
    ) {
        self.id = id
        self.name = name
        self.page = page
        self.totalPages = totalPages
        self.subforums = subforums
        self.topics = topics
    }
}

// MARK: - Комментарии

public struct Comment: Identifiable, Hashable, Sendable {
    public let id: String
    public let author: Author?
    public let avatarURL: URL?
    /// Дата в том виде, как её показывает сайт.
    public let dateText: String
    public let text: String

    public init(id: String, author: Author?, avatarURL: URL?, dateText: String, text: String) {
        self.id = id
        self.author = author
        self.avatarURL = avatarURL
        self.dateText = dateText
        self.text = text
    }
}

public struct CommentsPage: Sendable {
    public let page: Int
    public let totalPages: Int
    public let comments: [Comment]

    public init(page: Int, totalPages: Int, comments: [Comment]) {
        self.page = page
        self.totalPages = totalPages
        self.comments = comments
    }
}
