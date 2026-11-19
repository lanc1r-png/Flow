import Foundation

public enum FlowError: Error, LocalizedError, Equatable {
    /// Нет токена или сайт показал страницу входа.
    case unauthorized
    case forbidden
    case notFound
    case noData
    case unknown
    case blockedForRegion
    case onModeration
    /// Вместо `.torrent` сайт вернул что-то другое.
    case invalidTorrentFile
    case badResponse(Int)
    /// Неожиданный ответ сайта. Внутри — диагностика (код ответа, куки по именам, начало текста страницы).
    case unexpectedPage(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Нужно войти в аккаунт."
        case .forbidden:
            return "Доступ запрещён."
        case .notFound:
            return "Раздача не найдена."
        case .noData:
            return "Сайт вернул страницу, которую не удалось разобрать."
        case .unknown:
            return "Неизвестная ошибка. Возможно, сайт изменил вёрстку."
        case .blockedForRegion:
            return "Раздача недоступна для вашего региона."
        case .onModeration:
            return "Раздача ожидает проверки модератором."
        case .invalidTorrentFile:
            return "Сайт вернул не .torrent-файл."
        case .badResponse(let code):
            return "Сайт ответил ошибкой \(code)."
        case .unexpectedPage(let details):
            return "Сайт вернул неожиданный ответ. Скопируйте текст ниже и пришлите разработчику.\n\n\(details)"
        }
    }

    /// Текст ошибки для показа пользователю: отдельно обрабатывает сетевые сбои.
    public static func userMessage(for error: Error) -> String {
        if let flowError = error as? FlowError {
            return flowError.errorDescription ?? "Ошибка."
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "Нет подключения к интернету."
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
                 .secureConnectionFailed, .dnsLookupFailed:
                return "Не удалось подключиться к rutracker.org. Возможно, сайт заблокирован в вашей сети."
            default:
                return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    public var isUnauthorized: Bool {
        self == .unauthorized
    }
}
