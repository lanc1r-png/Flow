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
    case account
    case search
}

private struct MainTabs: View {
    @State private var selection: AppTab = .search

    var body: some View {
        TabView(selection: $selection) {
            Tab("Аккаунт", systemImage: "person.crop.circle", value: AppTab.account) {
                AccountView()
            }
            // Роль .search: на iOS 26 вкладка поиска оформляется системой отдельной стеклянной кнопкой.
            Tab("Поиск", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchView()
            }
        }
        .minimizeTabBarOnScroll()
    }
}
