import FlowCore
import Foundation
import Observation

/// Дерево разделов рутрекера. Нужно для выбора категорий в поиске, для главной страницы
/// и для подписей «Игры», «Фильмы» и т. д. в результатах. Хранится на устройстве, обновляется раз в две недели.
@MainActor
@Observable
final class ForumStore {
    private(set) var tree: ForumTree?
    private(set) var isLoading = false
    private(set) var loadError: String?

    private struct CachedTree: Codable {
        let savedAt: Date
        let tree: ForumTree
    }

    private static let maxAge: TimeInterval = 14 * 24 * 60 * 60

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("forum-tree.json")
    }

    func rootName(forForum id: String) -> String? {
        tree?.rootName(forForum: id)
    }

    func loadIfNeeded(session: SessionStore) async {
        guard tree == nil, !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let cached = readCache()
        if let cached, Date().timeIntervalSince(cached.savedAt) < Self.maxAge {
            tree = cached.tree
            return
        }
        do {
            let token = try session.requireToken()
            let fresh = try await session.client.forumTree(token: token)
            tree = fresh
            writeCache(fresh)
        } catch {
            if let cached {
                // Устаревшее дерево лучше, чем никакого.
                tree = cached.tree
            } else if !session.handleSessionError(error), !(error is CancellationError) {
                loadError = FlowError.userMessage(for: error)
            }
        }
    }

    func retry(session: SessionStore) async {
        loadError = nil
        await loadIfNeeded(session: session)
    }

    private func readCache() -> CachedTree? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedTree.self, from: data)
    }

    private func writeCache(_ tree: ForumTree) {
        guard let url = cacheURL,
              let data = try? JSONEncoder().encode(CachedTree(savedAt: Date(), tree: tree)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
