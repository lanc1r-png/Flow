import FlowCore
import SwiftUI

@MainActor
@Observable
final class ForumPageViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var items: [TorrentSummary] = []
    private(set) var subforums: [CategoryRef] = []
    private(set) var phase: Phase = .loading
    private(set) var isLoadingMore = false

    private var page = 0
    private var totalPages = 0

    func load(forumID: String, session: SessionStore) async {
        phase = .loading
        items = []
        subforums = []
        page = 0
        totalPages = 0
        do {
            let token = try session.requireToken()
            let result = try await session.client.forumPage(token: token, id: forumID, page: 1)
            items = result.topics
            subforums = result.subforums
            page = result.page
            totalPages = result.totalPages
            phase = .loaded
        } catch {
            if !session.handleSessionError(error), !(error is CancellationError) {
                phase = .failed(FlowError.userMessage(for: error))
            }
        }
    }

    func loadMoreIfNeeded(current item: TorrentSummary, forumID: String, session: SessionStore) {
        guard phase == .loaded, !isLoadingMore, page < totalPages, item.id == items.last?.id else { return }
        isLoadingMore = true
        let nextPage = page + 1
        Task { [weak self] in
            await self?.loadNext(forumID: forumID, page: nextPage, session: session)
        }
    }

    private func loadNext(forumID: String, page nextPage: Int, session: SessionStore) async {
        defer { isLoadingMore = false }
        do {
            let token = try session.requireToken()
            let result = try await session.client.forumPage(token: token, id: forumID, page: nextPage)
            let known = Set(items.map(\.id))
            items += result.topics.filter { !known.contains($0.id) }
            page = result.page
            totalPages = result.totalPages
        } catch {
            session.handleSessionError(error)
        }
    }
}

/// Страница форума: подфорумы и темы.
struct ForumPageView: View {
    let forumID: String
    let title: String

    @Environment(SessionStore.self) private var session
    @State private var model = ForumPageViewModel()

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(forumID: forumID, session: session) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Загружаю…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Не удалось загрузить раздел", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Повторить") {
                    Task { await model.load(forumID: forumID, session: session) }
                }
                .glassButton()
            }
        case .loaded:
            if model.items.isEmpty && model.subforums.isEmpty {
                ContentUnavailableView("Здесь пока пусто", systemImage: "tray")
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if !model.subforums.isEmpty {
                    sectionHeader("Подразделы")
                    ForEach(model.subforums, id: \.id) { subforum in
                        NavigationLink(value: subforum) {
                            NodeCard(title: subforum.name, subtitle: nil, iconName: title)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !model.items.isEmpty {
                    if !model.subforums.isEmpty { sectionHeader("Раздачи и темы") }
                    ForEach(model.items) { item in
                        NavigationLink(value: item) {
                            TorrentRow(torrent: item, showsCategory: false)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            model.loadMoreIfNeeded(current: item, forumID: forumID, session: session)
                        }
                    }
                }
                if model.isLoadingMore {
                    ProgressView().padding()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }
}
