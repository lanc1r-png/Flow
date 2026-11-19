import FlowCore
import Foundation
import Observation
import UIKit

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
@Observable
final class TopicViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var details: TorrentDetails?
    private(set) var phase: Phase = .loading
    private(set) var isDownloading = false
    private(set) var toast: String?
    private(set) var feedbackCount = 0
    var shareItem: ShareItem?

    var magnetURL: URL? {
        guard let magnet = details?.magnetLink else { return nil }
        if let url = URL(string: magnet) { return url }
        // Запасной путь для ссылок с неэкранированными символами.
        return magnet.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
    }

    func load(id: String, session: SessionStore) async {
        phase = .loading
        do {
            let token = try session.requireToken()
            details = try await session.client.torrent(token: token, id: id)
            phase = .loaded
        } catch {
            if !session.handleSessionError(error), !(error is CancellationError) {
                phase = .failed(FlowError.userMessage(for: error))
            }
        }
    }

    /// Скачивает `.torrent`, кладёт во временную папку и открывает системное меню «Поделиться»:
    /// оттуда файл можно отправить в торрент-клиент (например, iTorrent) или сохранить в «Файлы».
    func downloadTorrentFile(id: String, title: String, session: SessionStore) async {
        guard !isDownloading else { return }
        isDownloading = true
        defer { isDownloading = false }
        do {
            let token = try session.requireToken()
            let file = try await session.client.downloadTorrentFile(token: token, id: id, title: title)

            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("torrents", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(file.fileName)
            try file.data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch {
            if !session.handleSessionError(error) {
                showToast(FlowError.userMessage(for: error))
            }
        }
    }

    func copyMagnet() {
        guard let magnet = details?.magnetLink else { return }
        UIPasteboard.general.string = magnet
        feedbackCount += 1
        showToast("Magnet-ссылка скопирована")
    }

    func showToast(_ message: String) {
        toast = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if self?.toast == message { self?.toast = nil }
        }
    }
}
