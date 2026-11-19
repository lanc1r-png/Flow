import FlowCore
import Foundation
import Observation

/// Состояние входа и общий клиент рутрекера для всего приложения.
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

    let client = RuTrackerClient()
    private(set) var token: String?

    private let keychain = KeychainStore(service: "app.flow.rutracker.client")
    private let tokenAccount = "session-token"
    private let usernameKey = "username"

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
        } catch {
            // Нет сети или сайт недоступен — токен не трогаем, чтобы не разлогинивать зря.
            state = .signedIn(username: savedName)
        }
    }

    func signIn(username: String, password: String, captcha: CaptchaAnswer?) async throws -> LoginResult {
        let result = try await client.login(username: username, password: password, captcha: captcha)
        if case .success(let session) = result {
            let name = session.username ?? username
            keychain.write(session.token, account: tokenAccount)
            UserDefaults.standard.set(name, forKey: usernameKey)
            token = session.token
            notice = nil
            state = .signedIn(username: name)
        }
        return result
    }

    func signOut() {
        notice = nil
        clearSession()
    }

    /// Сайт ответил, что мы не авторизованы: возвращаем пользователя на экран входа.
    func handleUnauthorized() {
        notice = "Сессия истекла. Войдите снова."
        clearSession()
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
