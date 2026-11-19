import FlowCore
import SwiftUI

struct SearchView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = SearchViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                content
            }
            .navigationTitle("Поиск")
            .navigationDestination(for: TorrentSummary.self) { summary in
                TopicView(summary: summary)
            }
            .searchable(text: $model.queryText, prompt: "Название раздачи")
            .onSubmit(of: .search) { model.search(session: session) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .onChange(of: model.filterSignature) {
                model.refreshIfSearched(session: session)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "Поиск раздач",
                systemImage: "magnifyingglass",
                description: Text("Введите название и нажмите «Найти».")
            )
        case .loading:
            ProgressView("Ищу…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Не удалось выполнить поиск", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Повторить") { model.search(session: session) }
                    .glassButton()
            }
        case .loaded:
            if model.items.isEmpty {
                ContentUnavailableView.search(text: model.queryText)
            } else {
                results
            }
        }
    }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(model.items) { item in
                    NavigationLink(value: item) {
                        TorrentRow(torrent: item)
                    }
                    .buttonStyle(.plain)
                    .onAppear { model.loadMoreIfNeeded(current: item, session: session) }
                }
                if model.isLoadingMore {
                    ProgressView().padding()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Сортировка", selection: $model.sort) {
                ForEach(SearchSort.allCases) { Text($0.title).tag($0) }
            }
            Picker("Порядок", selection: $model.order) {
                ForEach(SearchOrder.allCases) { Text($0.title).tag($0) }
            }
            Picker("Период", selection: $model.period) {
                ForEach(SearchPeriod.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Фильтры поиска")
    }
}
