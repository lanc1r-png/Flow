import FlowCore
import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session

    @State private var username = ""
    @State private var password = ""
    @State private var captcha: Captcha?
    @State private var captchaText = ""
    @State private var isLoading = false
    @State private var errorText: String?
    @FocusState private var focus: Field?

    private enum Field {
        case username, password, captcha
    }

    private var canSubmit: Bool {
        !username.isEmpty && !password.isEmpty && !isLoading && (captcha == nil || !captchaText.isEmpty)
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 24) {
                    header
                    form
                    Text("Неофициальный клиент. Не связан с rutracker.org.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
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

    private var form: some View {
        VStack(spacing: 14) {
            if let notice = session.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            TextField("Логин", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focus, equals: .username)
                .onSubmit { focus = .password }
                .padding(12)
                .contentCard(cornerRadius: 14)

            SecureField("Пароль", text: $password)
                .textContentType(.password)
                .submitLabel(captcha == nil ? .go : .next)
                .focused($focus, equals: .password)
                .onSubmit {
                    if captcha == nil {
                        submit()
                    } else {
                        focus = .captcha
                    }
                }
                .padding(12)
                .contentCard(cornerRadius: 14)

            if let captcha {
                VStack(spacing: 10) {
                    AsyncImage(url: captcha.imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            Label("Не удалось загрузить картинку", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                        default:
                            ProgressView()
                        }
                    }
                    .frame(maxHeight: 80)

                    TextField("Символы с картинки", text: $captchaText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focus, equals: .captcha)
                        .onSubmit(submit)
                        .padding(12)
                        .contentCard(cornerRadius: 14)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                ZStack {
                    Text("Войти").opacity(isLoading ? 0 : 1)
                    if isLoading { ProgressView() }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .glassButton(prominent: true)
            .disabled(!canSubmit)
        }
        .padding(20)
        .glassCard(cornerRadius: 28)
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        Task { await signIn() }
    }

    private func signIn() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let answer = captcha.map { CaptchaAnswer(captcha: $0, value: captchaText) }
        do {
            let result = try await session.signIn(username: username, password: password, captcha: answer)
            switch result {
            case .success:
                break
            case .wrongCredentials(let newCaptcha):
                errorText = "Неверный логин или пароль."
                captcha = newCaptcha
                captchaText = ""
            case .captchaRequired(let newCaptcha):
                errorText = "Введите символы с картинки."
                captcha = newCaptcha
                captchaText = ""
            }
        } catch {
            errorText = FlowError.userMessage(for: error)
        }
    }
}
