import FlowCore
import Foundation
import Observation

/// Состояние входа и общий клиент рутрекера для всего приложения.
///
/// Рутрекер закрыт проверкой Cloudflare, поэтому вход выполняется во встроенном браузере (см. `WebLoginView`).
/// Приложение забирает оттуда куки (`bb_session`, `cf_clearance` и другие) и User-Agent и дальше ходит на сайт само.
@MainActor
@Observable
final class SessionStore {
    enum State {
        case checking
        case signedOut
        case signedIn(username: String?)
    }

    private(set) var state: State = .checking
    /// Сообщение на экране входа (например, «сессия истекла»).
    var notice: String?

    private(set) var client: RuTrackerClient
    private(set) var token: String?

    private let keychain = KeychainStore(service: "app.flow.rutracker.client")
    private let tokenAccount = "session-token"
    private let usernameKey = "username"
    private let userAgentKey = "userAgent"

    init() {
        client = RuTrackerClient(userAgent: UserDefaults.standard.string(forKey: "userAgent"))
    }

    /// Вызывается при запуске: проверяет, что сохранённый токен ещё работает.
    func restore() async {
        guard let saved = keychain.read(account: tokenAccount) else {
            state = .signedOut
            return
        }
        token = saved
        let savedName = UserDefaults.standard.string(forKey: usernameKey)
        do {
            if let user = try await client.currentUser(token: saved) {
                state = .signedIn(username: user.name.isEmpty ? savedName : user.name)
            } else {
                notice = "Сессия истекла. Войдите снова."
                clearSession()
            }
        } catch FlowError.challenge {
            notice = "Сайт запросил проверку браузером. Войдите снова."
            clearSession()
        } catch {
            // Нет сети или сайт недоступен — токен не трогаем, чтобы не разлогинивать зря.
            state = .signedIn(username: savedName)
        }
    }

    /// Завершает вход, выполненный во встроенном браузере: проверяет куки и сохраняет сессию.
    /// Возвращает `false`, если сайт не подтвердил, что мы авторизованы.
    func completeWebLogin(cookieHeader: String, userAgent: String) async throws -> Bool {
        let agent = userAgent.isEmpty ? nil : userAgent
        let candidate = RuTrackerClient(userAgent: agent)
        guard let user = try await candidate.currentUser(token: cookieHeader) else {
            return false
        }
        client = candidate
        keychain.write(cookieHeader, account: tokenAccount)
        UserDefaults.standard.set(agent, forKey: userAgentKey)
        UserDefaults.standard.set(user.name, forKey: usernameKey)
        token = cookieHeader
        notice = nil
        state = .signedIn(username: user.name.isEmpty ? nil : user.name)
        return true
    }

    func signOut() {
        notice = nil
        clearSession()
    }

    /// Разбирает ошибки, из-за которых нужно войти заново (истёкшая сессия, проверка Cloudflare).
    /// Возвращает `true`, если ошибка обработана и экран переключён на вход.
    @discardableResult
    func handleSessionError(_ error: Error) -> Bool {
        guard let flowError = error as? FlowError else { return false }
        switch flowError {
        case .unauthorized:
            notice = "Сессия истекла. Войдите снова."
        case .challenge:
            notice = "Сайт запросил проверку браузером. Войдите снова — это обновит проверку."
        default:
            return false
        }
        clearSession()
        return true
    }

    func requireToken() throws -> String {
        guard let token else { throw FlowError.unauthorized }
        return token
    }

    private func clearSession() {
        keychain.delete(account: tokenAccount)
        token = nil
        state = .signedOut
    }
}
