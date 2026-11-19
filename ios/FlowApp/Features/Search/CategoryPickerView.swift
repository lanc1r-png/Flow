import FlowCore
import SwiftUI

/// Выбор категорий для поиска: корневая категория → форум → подфорум, либо поиск по названию.
struct CategoryPickerView: View {
    let model: SearchViewModel

    @Environment(ForumStore.self) private var forums
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Категории")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: ForumNode.self) { node in
                    ForumLevelView(node: node, model: model)
                }
                .searchable(text: $filter, prompt: "Найти раздел, например «PS5»")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Сбросить") { model.clearForums() }
                            .disabled(model.selectedNodes.isEmpty)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let tree = forums.tree {
            let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                rootList(tree)
            } else {
                matchList(tree.search(query))
            }
        } else if forums.loadError == nil {
            ProgressView("Загружаю разделы…")
        } else {
            ContentUnavailableView {
                Label("Не удалось загрузить разделы", systemImage: "wifi.exclamationmark")
            } description: {
                Text(forums.loadError ?? "")
            } actions: {
                Button("Повторить") { Task { await forums.retry(session: session) } }
                    .glassButton()
            }
        }
    }

    private func rootList(_ tree: ForumTree) -> some View {
        List(tree.roots) { root in
            NavigationLink(value: root) {
                PickerRow(
                    title: root.name,
                    subtitle: "Разделов: \(root.children.count)",
                    iconName: root.name,
                    state: model.state(of: root)
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
    }

    @ViewBuilder
    private func matchList(_ matches: [ForumMatch]) -> some View {
        if matches.isEmpty {
            ContentUnavailableView.search(text: filter)
        } else {
            List(matches) { match in
                Button {
                    model.toggle(match.node)
                } label: {
                    PickerRow(
                        title: match.node.name,
                        subtitle: match.path,
                        iconName: match.path,
                        state: model.state(of: match.node)
                    )
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
        }
    }
}

/// Один уровень дерева: можно выбрать узел целиком или спуститься глубже.
private struct ForumLevelView: View {
    let node: ForumNode
    let model: SearchViewModel

    var body: some View {
        List {
            Section {
                Button {
                    model.toggle(node)
                } label: {
                    PickerRow(
                        title: node.isRoot ? "Весь раздел" : "Весь форум со всеми подфорумами",
                        subtitle: node.name,
                        iconName: node.name,
                        state: model.state(of: node) == .full ? .full : .none
                    )
                }
                .buttonStyle(.plain)
            }

            Section {
                ForEach(node.children) { child in
                    if child.children.isEmpty {
                        Button {
                            model.toggle(child)
                        } label: {
                            PickerRow(title: child.name, subtitle: nil, iconName: nil, state: model.state(of: child))
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(value: child) {
                            PickerRow(
                                title: child.name,
                                subtitle: "Подфорумов: \(child.children.count)",
                                iconName: nil,
                                state: model.state(of: child)
                            )
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
        .navigationTitle(node.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PickerRow: View {
    let title: String
    let subtitle: String?
    /// Название, по которому подбирается иконка категории. `nil` — без иконки.
    let iconName: String?
    let state: SearchViewModel.SelectionState

    var body: some View {
        HStack(spacing: 12) {
            if let iconName {
                CategoryIcon(name: iconName, size: 34)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            indicator
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .full:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
        case .partial:
            Image(systemName: "circle.lefthalf.filled").foregroundStyle(.tint)
        case .none:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
}
