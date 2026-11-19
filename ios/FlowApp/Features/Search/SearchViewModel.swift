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

    private(set) var items: [TorrentSummary] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false

    private var page = 0
    private var totalPages = 0
    private var activeQuery: SearchQuery?
    private var searchTask: Task<Void, Never>?

    /// Меняется при изменении сортировки, порядка или периода — по нему view перезапускает поиск.
    var filterSignature: String {
        "\(sort.rawValue)|\(order.rawValue)|\(period.rawValue)"
    }

    func search(session: SessionStore) {
        let text = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let query = SearchQuery(text: text, sort: sort, order: order, period: period)

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.loadFirstPage(query: query, session: session)
        }
    }

    /// Повторяет последний поиск с новыми параметрами сортировки (если поиск уже выполнялся).
    func refreshIfSearched(session: SessionStore) {
        guard activeQuery != nil || phase != .idle else { return }
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
            if (error as? FlowError) == .unauthorized {
                session.handleUnauthorized()
            }
        }
    }

    private func handle(_ error: Error, session: SessionStore) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return
        }
        if (error as? FlowError) == .unauthorized {
            session.handleUnauthorized()
            return
        }
        phase = .failed(FlowError.userMessage(for: error))
    }
}
