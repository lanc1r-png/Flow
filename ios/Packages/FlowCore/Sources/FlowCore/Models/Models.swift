import Foundation

public struct Author: Hashable, Sendable {
    public let id: String?
    public let name: String

    public init(id: String?, name: String) {
        self.id = id
        self.name = name
    }
}

public struct CategoryRef: Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Статус раздачи на трекере (иконка рядом с названием).
public enum TorrentStatus: String, Hashable, Sendable {
    case approved
    case checking
    case closed
    case consumed
    case duplicate
    case needEdit
    case noDescription
    case notApproved

    public var title: String {
        switch self {
        case .approved: return "проверено"
        case .checking: return "проверяется"
        case .closed: return "закрыто"
        case .consumed: return "поглощено"
        case .duplicate: return "повтор"
        case .needEdit: return "недооформлено"
        case .noDescription: return "не оформлено"
        case .notApproved: return "не проверено"
        }
    }
}

/// Строка в результатах поиска.
public struct TorrentSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let tags: String
    public let author: Author?
    public let category: CategoryRef?
    public let status: TorrentStatus?
    public let date: Date?
    public let size: String
    public let seeds: Int?
    public let leeches: Int?

    public init(
        id: String,
        title: String,
        tags: String,
        author: Author?,
        category: CategoryRef?,
        status: TorrentStatus?,
        date: Date?,
        size: String,
        seeds: Int?,
        leeches: Int?
    ) {
        self.id = id
        self.title = title
        self.tags = tags
        self.author = author
        self.category = category
        self.status = status
        self.date = date
        self.size = size
        self.seeds = seeds
        self.leeches = leeches
    }
}

public struct SearchPage: Sendable {
    public let page: Int
    public let totalPages: Int
    public let items: [TorrentSummary]

    public init(page: Int, totalPages: Int, items: [TorrentSummary]) {
        self.page = page
        self.totalPages = totalPages
        self.items = items
    }
}

/// Страница раздачи.
public struct TorrentDetails: Sendable {
    public let id: String
    public let title: String
    public let tags: String
    public let author: Author?
    public let category: CategoryRef?
    public let status: TorrentStatus?
    public let size: String?
    public let seeds: Int?
    public let leeches: Int?
    /// Magnet-ссылка. Рутрекер показывает её только авторизованным пользователям.
    public let magnetLink: String?
    /// Текст описания первого сообщения (без форматирования).
    public let description: String
    public let posterURL: URL?
    /// Дата первого сообщения в том виде, как её показывает сайт.
    public let publishedText: String?

    public init(
        id: String,
        title: String,
        tags: String,
        author: Author?,
        category: CategoryRef?,
        status: TorrentStatus?,
        size: String?,
        seeds: Int?,
        leeches: Int?,
        magnetLink: String?,
        description: String,
        posterURL: URL?,
        publishedText: String?
    ) {
        self.id = id
        self.title = title
        self.tags = tags
        self.author = author
        self.category = category
        self.status = status
        self.size = size
        self.seeds = seeds
        self.leeches = leeches
        self.magnetLink = magnetLink
        self.description = description
        self.posterURL = posterURL
        self.publishedText = publishedText
    }
}

/// Скачанный `.torrent`-файл.
public struct TorrentFile: Sendable {
    public let fileName: String
    public let data: Data

    public init(fileName: String, data: Data) {
        self.fileName = fileName
        self.data = data
    }
}

// MARK: - Поиск

/// Значения параметра `o` в `tracker.php`.
public enum SearchSort: String, CaseIterable, Identifiable, Hashable, Sendable {
    case date = "1"
    case title = "2"
    case downloaded = "4"
    case seeds = "10"
    case leeches = "11"
    case size = "7"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .date: return "По дате"
        case .title: return "По названию"
        case .downloaded: return "По скачиваниям"
        case .seeds: return "По сидам"
        case .leeches: return "По личам"
        case .size: return "По размеру"
        }
    }
}

/// Значения параметра `s` в `tracker.php`.
public enum SearchOrder: String, CaseIterable, Identifiable, Hashable, Sendable {
    case ascending = "1"
    case descending = "2"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ascending: return "По возрастанию"
        case .descending: return "По убыванию"
        }
    }
}

/// Значения параметра `tm` в `tracker.php`.
public enum SearchPeriod: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allTime = "-1"
    case today = "1"
    case threeDays = "3"
    case week = "7"
    case twoWeeks = "14"
    case month = "32"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .allTime: return "За всё время"
        case .today: return "За сегодня"
        case .threeDays: return "За 3 дня"
        case .week: return "За неделю"
        case .twoWeeks: return "За 2 недели"
        case .month: return "За месяц"
        }
    }
}

public struct SearchQuery: Hashable, Sendable {
    public var text: String
    public var sort: SearchSort
    public var order: SearchOrder
    public var period: SearchPeriod

    public init(
        text: String,
        sort: SearchSort = .date,
        order: SearchOrder = .descending,
        period: SearchPeriod = .allTime
    ) {
        self.text = text
        self.sort = sort
        self.order = order
        self.period = period
    }
}

// MARK: - Авторизация

public struct Captcha: Hashable, Sendable {
    /// Значение скрытого поля `cap_sid`.
    public let sid: String
    /// Имя поля, в которое вводится текст с картинки (`cap_code_...`).
    public let codeField: String
    public let imageURL: URL

    public init(sid: String, codeField: String, imageURL: URL) {
        self.sid = sid
        self.codeField = codeField
        self.imageURL = imageURL
    }
}

public struct CaptchaAnswer: Sendable {
    public let sid: String
    public let codeField: String
    public let value: String

    public init(sid: String, codeField: String, value: String) {
        self.sid = sid
        self.codeField = codeField
        self.value = value
    }

    public init(captcha: Captcha, value: String) {
        self.init(sid: captcha.sid, codeField: captcha.codeField, value: value)
    }
}

public struct Session: Sendable {
    /// Готовая строка для заголовка `Cookie`, например `bb_session=...`.
    public let token: String
    public let username: String?

    public init(token: String, username: String?) {
        self.token = token
        self.username = username
    }
}

public enum LoginResult: Sendable {
    case success(Session)
    case wrongCredentials(Captcha?)
    case captchaRequired(Captcha)
}

public struct UserInfo: Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}
