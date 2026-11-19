import SwiftUI

struct AccountView: View {
    @Environment(SessionStore.self) private var session

    private var username: String {
        if case .signedIn(let name) = session.state, let name, !name.isEmpty {
            return name
        }
        return "Аккаунт"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                Form {
                    Section {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(username).font(.headline)
                                Text("rutracker.org").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section {
                        Button("Выйти", role: .destructive) {
                            session.signOut()
                        }
                    }

                    Section("О приложении") {
                        Text("Flow — неофициальный клиент. Приложение не связано с rutracker.org и не скачивает сами раздачи: оно получает .torrent-файлы и magnet-ссылки, а загружает их ваш торрент-клиент.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Аккаунт")
        }
    }
}
