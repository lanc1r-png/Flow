import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .checking:
                ZStack {
                    AppBackground()
                    ProgressView()
                }
            case .signedOut:
                LoginView()
            case .signedIn:
                MainTabs()
            }
        }
        .task { await session.restore() }
    }
}

private enum AppTab: Hashable {
    case home
    case account
    case search
}

private struct MainTabs: View {
    @Environment(SessionStore.self) private var session
    @State private var selection: AppTab = .home
    @State private var forums = ForumStore()

    var body: some View {
        TabView(selection: $selection) {
            Tab("Главная", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Аккаунт", systemImage: "person.crop.circle", value: AppTab.account) {
                AccountView()
            }
            // Роль .search: на iOS 26 вкладка поиска оформляется системой отдельной стеклянной кнопкой.
            Tab("Поиск", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchView()
            }
        }
        .minimizeTabBarOnScroll()
        .environment(forums)
        .task { await forums.loadIfNeeded(session: session) }
    }
}
