import FlowCore
import SwiftUI

struct SearchView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = SearchViewModel()
    @State private var showsCategories = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    selectedChips
                    content
                }
            }
            .navigationTitle("Поиск")
            .navigationDestination(for: TorrentSummary.self) { summary in
                TopicView(summary: summary)
            }
            .searchable(text: $model.queryText, prompt: "Название раздачи")
            .onSubmit(of: .search) { model.search(session: session) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { categoriesButton }
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .sheet(isPresented: $showsCategories) {
                CategoryPickerView(model: model)
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
                description: Text("Введите название и нажмите «Найти» или выберите категории: игры, фильмы, музыка, книги…")
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

    @ViewBuilder
    private var selectedChips: some View {
        if !model.selectedNodes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.selectedNodes) { node in
                        Button {
                            model.remove(node)
                        } label: {
                            HStack(spacing: 6) {
                                Text(node.name)
                                    .lineLimit(1)
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.thinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Убрать категорию \(node.name)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private var categoriesButton: some View {
        Button {
            showsCategories = true
        } label: {
            Image(systemName: model.selectedNodes.isEmpty ? "square.grid.2x2" : "square.grid.2x2.fill")
        }
        .accessibilityLabel("Категории")
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
