import FlowCore
import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var queryText = ""
    var sort: SearchSort = .date
    var order: SearchOrder = .descending
    var period: SearchPeriod = .allTime
    /// Выбранные категории и форумы для поиска.
    private(set) var selectedNodes: [ForumNode] = []

    private(set) var items: [TorrentSummary] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false

    private var page = 0
    private var totalPages = 0
    private var activeQuery: SearchQuery?
    private var searchTask: Task<Void, Never>?

    /// Меняется при изменении сортировки, порядка, периода или категорий — по нему view перезапускает поиск.
    var filterSignature: String {
        "\(sort.rawValue)|\(order.rawValue)|\(period.rawValue)|" + selectedNodes.map(\.id).joined(separator: ",")
    }

    /// Id всех форумов, по которым ищем (выбранные узлы вместе с вложенными).
    var forumIDs: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for node in selectedNodes {
            for id in node.forumIDs where seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
    }

    // MARK: - Категории

    enum SelectionState {
        case none
        case partial
        case full
    }

    func state(of node: ForumNode) -> SelectionState {
        if selectedNodes.contains(where: { $0.id == node.id }) { return .full }
        let inside = Set(node.descendantIDs)
        if selectedNodes.contains(where: { inside.contains($0.id) }) { return .partial }
        return .none
    }

    func toggle(_ node: ForumNode) {
        if let index = selectedNodes.firstIndex(where: { $0.id == node.id }) {
            selectedNodes.remove(at: index)
        } else {
            selectedNodes.append(node)
        }
    }

    func remove(_ node: ForumNode) {
        selectedNodes.removeAll { $0.id == node.id }
    }

    func clearForums() {
        selectedNodes = []
    }

    // MARK: - Поиск

    func search(session: SessionStore) {
        let text = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = forumIDs
        guard !text.isEmpty || !ids.isEmpty else { return }
        let query = SearchQuery(text: text, sort: sort, order: order, period: period, forumIDs: ids)

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.loadFirstPage(query: query, session: session)
        }
    }

    /// Повторяет последний поиск с новыми параметрами (если поиск уже выполнялся или выбраны категории).
    func refreshIfSearched(session: SessionStore) {
        let hasText = !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasText && selectedNodes.isEmpty {
            // Всё сброшено — возвращаемся к пустому экрану поиска.
            searchTask?.cancel()
            items = []
            page = 0
            totalPages = 0
            activeQuery = nil
            phase = .idle
            return
        }
        guard activeQuery != nil || phase != .idle || !selectedNodes.isEmpty else { return }
        search(session: session)
    }

    func loadMoreIfNeeded(current item: TorrentSummary, session: SessionStore) {
        guard phase == .loaded,
              !isLoadingMore,
              page < totalPages,
              item.id == items.last?.id,
              let query = activeQuery else { return }

        isLoadingMore = true
        let nextPage = page + 1
        Task { [weak self] in
            await self?.loadNextPage(query: query, page: nextPage, session: session)
        }
    }

    // MARK: - Загрузка

    private func loadFirstPage(query: SearchQuery, session: SessionStore) async {
        phase = .loading
        items = []
        page = 0
        totalPages = 0
        isLoadingMore = false
        do {
            let token = try session.requireToken()
            let result = try await session.client.search(token: token, query: query, page: 1)
            guard !Task.isCancelled else { return }
            items = result.items
            page = result.page
            totalPages = result.totalPages
            activeQuery = query
            phase = .loaded
        } catch {
            handle(error, session: session)
        }
    }

    private func loadNextPage(query: SearchQuery, page nextPage: Int, session: SessionStore) async {
        defer { isLoadingMore = false }
        do {
            let token = try session.requireToken()
            let result = try await session.client.search(token: token, query: query, page: nextPage)
            guard activeQuery == query else { return }
            let known = Set(items.map(\.id))
            items += result.items.filter { !known.contains($0.id) }
            page = result.page
            totalPages = result.totalPages
        } catch {
            // Ошибка догрузки не должна ломать уже показанные результаты.
            session.handleSessionError(error)
        }
    }

    private func handle(_ error: Error, session: SessionStore) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return
        }
        if session.handleSessionError(error) {
            return
        }
        phase = .failed(FlowError.userMessage(for: error))
    }
}
