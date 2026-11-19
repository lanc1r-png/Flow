import FlowCore
import SwiftUI

struct TopicView: View {
    let summary: TorrentSummary

    @Environment(SessionStore.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var model = TopicViewModel()

    private var title: String { model.details?.title ?? summary.title }
    private var tags: String { model.details?.tags ?? summary.tags }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    stats
                    commentsLink
                    descriptionSection
                }
                .padding(16)
            }
        }
        .navigationTitle("Раздача")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actionBar }
        .overlay(alignment: .top) { toast }
        .animation(.snappy, value: model.toast)
        .sheet(item: $model.shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .sensoryFeedback(.success, trigger: model.feedbackCount)
        .task { await model.load(id: summary.id, session: session) }
    }

    // MARK: - Разделы

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let poster = model.details?.posterURL {
                AsyncImage(url: poster) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .frame(maxHeight: 280)
                .frame(maxWidth: .infinity)
            }

            Text(title)
                .font(.title3.bold())
                .textSelection(.enabled)

            if !tags.isEmpty {
                Text(tags)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let category = model.details?.category ?? summary.category {
                CategoryLine(category: category)
            }
            if let author = model.details?.author ?? summary.author {
                Label(author.name, systemImage: "person")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let published = model.details?.publishedText {
                Label(published, systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .contentCard(cornerRadius: 20)
    }

    private var stats: some View {
        HStack(spacing: 10) {
            StatTile(title: "Размер", value: model.details?.size ?? summary.size, color: .primary)
            StatTile(title: "Сиды", value: count(model.details?.seeds ?? summary.seeds), color: .green)
            StatTile(title: "Личи", value: count(model.details?.leeches ?? summary.leeches), color: .red)
            if let status = model.details?.status ?? summary.status {
                StatTile(title: "Статус", value: status.title, color: .secondary)
            }
        }
    }

    private var commentsLink: some View {
        NavigationLink {
            CommentsView(topicID: summary.id, title: title)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(.tint)
                Text("Комментарии")
                    .font(.body.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .contentCard(cornerRadius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var descriptionSection: some View {
        switch model.phase {
        case .loading:
            ProgressView("Загружаю описание…")
                .frame(maxWidth: .infinity)
                .padding(24)
        case .failed(let message):
            VStack(spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Повторить") {
                    Task { await model.load(id: summary.id, session: session) }
                }
                .glassButton()
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .contentCard(cornerRadius: 20)
        case .loaded:
            if let description = model.details?.description, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .contentCard(cornerRadius: 20)
            }
        }
    }

    // MARK: - Кнопки действий

    private var actionBar: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await model.downloadTorrentFile(id: summary.id, title: title, session: session)
                }
            } label: {
                ZStack {
                    Label("Скачать .torrent", systemImage: "arrow.down.doc")
                        .opacity(model.isDownloading ? 0 : 1)
                    if model.isDownloading { ProgressView() }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .glassButton(prominent: true)
            .disabled(model.isDownloading)

            HStack(spacing: 8) {
                Button {
                    openMagnet()
                } label: {
                    Label("Открыть magnet", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .glassButton()

                Button {
                    model.copyMagnet()
                } label: {
                    Label("Копировать", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .glassButton()
            }
            .disabled(model.magnetURL == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func openMagnet() {
        guard let url = model.magnetURL else { return }
        openURL(url) { accepted in
            if !accepted {
                model.showToast("Нет приложения, которое открывает magnet-ссылки. Скопируйте ссылку.")
            }
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let message = model.toast {
            Text(message)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCapsule()
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func count(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .contentCard(cornerRadius: 14)
    }
}
