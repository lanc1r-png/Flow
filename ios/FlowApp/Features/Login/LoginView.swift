import FlowCore
import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session

    @State private var showWebLogin = false
    @State private var isVerifying = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 24) {
                    header
                    card
                    Text("Неофициальный клиент. Не связан с rutracker.org.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showWebLogin) {
            WebLoginSheet { result in
                showWebLogin = false
                Task { await verify(result) }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Flow")
                .font(.largeTitle.bold())
            Text("Вход в аккаунт рутрекера")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 48)
    }

    private var card: some View {
        VStack(spacing: 14) {
            Text("Рутрекер защищён проверкой браузера, поэтому вход выполняется на самом сайте. Войдите там как обычно, окно закроется само.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let notice = session.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                errorText = nil
                showWebLogin = true
            } label: {
                ZStack {
                    Label("Войти через rutracker.org", systemImage: "safari")
                        .opacity(isVerifying ? 0 : 1)
                    if isVerifying { ProgressView() }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .glassButton(prominent: true)
            .disabled(isVerifying)
        }
        .padding(20)
        .glassCard(cornerRadius: 28)
    }

    private func verify(_ result: WebLoginResult) async {
        isVerifying = true
        defer { isVerifying = false }
        do {
            let ok = try await session.completeWebLogin(
                cookieHeader: result.cookieHeader,
                userAgent: result.userAgent
            )
            if !ok {
                errorText = "Вход не подтвердился. Попробуйте ещё раз."
            }
        } catch {
            errorText = FlowError.userMessage(for: error)
        }
    }
}
