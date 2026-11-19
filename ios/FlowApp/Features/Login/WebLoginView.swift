import SwiftUI
import WebKit

/// Результат входа во встроенном браузере.
struct WebLoginResult {
    /// Строка для заголовка `Cookie`: сессия рутрекера и куки Cloudflare.
    let cookieHeader: String
    let userAgent: String
}

/// Окно с настоящим браузером. Рутрекер закрыт проверкой Cloudflare, которую обычный сетевой клиент пройти не может,
/// поэтому пользователь входит на сайте сам (в том числе вводит капчу), а приложение забирает получившуюся сессию.
struct WebLoginSheet: View {
    let onFinished: (WebLoginResult) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebLoginView(onFinished: onFinished)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Вход на rutracker.org")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                }
        }
    }
}

private struct WebLoginView: UIViewRepresentable {
    let onFinished: (WebLoginResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Как у мобильного Safari: сайты и Cloudflare лучше принимают такой User-Agent.
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/604.1"

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.attach(webView)
        webView.load(URLRequest(url: URL(string: "https://rutracker.org/forum/login.php")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// Раз в секунду проверяет, появилась ли сессионная кука после входа.
    final class Coordinator: NSObject {
        private let onFinished: (WebLoginResult) -> Void
        private weak var webView: WKWebView?
        private var timer: Timer?
        private var finished = false

        init(onFinished: @escaping (WebLoginResult) -> Void) {
            self.onFinished = onFinished
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.check()
            }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        private func check() {
            guard !finished, let webView else { return }
            // Пока открыта страница входа, считаем, что вход ещё не завершён.
            let path = webView.url?.path ?? ""
            guard !path.isEmpty, !path.hasSuffix("login.php") else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.finished else { return }
                let siteCookies = cookies.filter { $0.domain.hasSuffix("rutracker.org") && !$0.value.isEmpty }
                guard siteCookies.contains(where: { $0.name == "bb_session" && $0.value != "deleted" }) else { return }
                let header = siteCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

                webView.evaluateJavaScript("navigator.userAgent") { [weak self] value, _ in
                    guard let self, !self.finished else { return }
                    self.finished = true
                    self.stop()
                    self.onFinished(WebLoginResult(cookieHeader: header, userAgent: (value as? String) ?? ""))
                }
            }
        }
    }
}
