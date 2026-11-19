import FlowCore
import SwiftUI

/// Главная: разделы трекера. Корневая категория → форум → подфорумы и список раздач.
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ForumStore.self) private var forums

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                content
            }
            .navigationTitle("Главная")
            .navigationDestination(for: ForumNode.self) { node in
                if node.isRoot {
                    SectionView(node: node)
                } else {
                    ForumPageView(forumID: node.id, title: node.name)
                }
            }
            .navigationDestination(for: CategoryRef.self) { category in
                ForumPageView(forumID: category.id, title: category.name)
            }
            .navigationDestination(for: TorrentSummary.self) { summary in
                TopicView(summary: summary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let tree = forums.tree {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(tree.roots) { root in
                        NavigationLink(value: root) {
                            NodeCard(title: root.name, subtitle: "Разделов: \(root.children.count)", iconName: root.name)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
}

/// Форумы одной корневой категории.
private struct SectionView: View {
    let node: ForumNode

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(node.children) { forum in
                        NavigationLink(value: forum) {
                            NodeCard(
                                title: forum.name,
                                subtitle: forum.children.isEmpty ? nil : "Подфорумов: \(forum.children.count)",
                                iconName: node.name
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle(node.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NodeCard: View {
    let title: String
    let subtitle: String?
    /// Название корневой категории — по нему подбираются иконка и цвет.
    let iconName: String

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(name: iconName)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .contentCard()
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
