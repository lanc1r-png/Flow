import FlowCore
import SwiftUI

@MainActor
@Observable
final class CommentsViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var comments: [Comment] = []
    private(set) var phase: Phase = .loading
    private(set) var isLoadingMore = false

    private var page = 0
    private var totalPages = 0

    func load(topicID: String, session: SessionStore) async {
        phase = .loading
        comments = []
        page = 0
        totalPages = 0
        do {
            let token = try session.requireToken()
            let result = try await session.client.comments(token: token, topicId: topicID, page: 1)
            comments = result.comments
            page = result.page
            totalPages = result.totalPages
            phase = .loaded
        } catch {
            if !session.handleSessionError(error), !(error is CancellationError) {
                phase = .failed(FlowError.userMessage(for: error))
            }
        }
    }

    func loadMoreIfNeeded(current comment: Comment, topicID: String, session: SessionStore) {
        guard phase == .loaded, !isLoadingMore, page < totalPages, comment.id == comments.last?.id else { return }
        isLoadingMore = true
        let nextPage = page + 1
        Task { [weak self] in
            await self?.loadNext(topicID: topicID, page: nextPage, session: session)
        }
    }

    private func loadNext(topicID: String, page nextPage: Int, session: SessionStore) async {
        defer { isLoadingMore = false }
        do {
            let token = try session.requireToken()
            let result = try await session.client.comments(token: token, topicId: topicID, page: nextPage)
            let known = Set(comments.map(\.id))
            comments += result.comments.filter { !known.contains($0.id) }
            page = result.page
            totalPages = result.totalPages
        } catch {
            session.handleSessionError(error)
        }
    }
}

/// Комментарии к раздаче. Только чтение.
struct CommentsView: View {
    let topicID: String
    let title: String

    @Environment(SessionStore.self) private var session
    @State private var model = CommentsViewModel()

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .navigationTitle("Комментарии")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(topicID: topicID, session: session) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Загружаю комментарии…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Не удалось загрузить комментарии", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Повторить") {
                    Task { await model.load(topicID: topicID, session: session) }
                }
                .glassButton()
            }
        case .loaded:
            if model.comments.isEmpty {
                ContentUnavailableView(
                    "Комментариев пока нет",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(title)
                )
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(model.comments) { comment in
                    CommentCard(comment: comment)
                        .onAppear {
                            model.loadMoreIfNeeded(current: comment, topicID: topicID, session: session)
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
}

private struct CommentCard: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 1) {
                    Text(comment.author?.name ?? "Аноним")
                        .font(.subheadline.weight(.semibold))
                    if !comment.dateText.isEmpty {
                        Text(comment.dateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if !comment.text.isEmpty {
                Text(comment.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }

    private var avatar: some View {
        Group {
            if let url = comment.avatarURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 36)
            .background(.quaternary, in: Circle())
    }
}
