import SwiftUI

// Liquid Glass (iOS 26+) подключается только там, где SDK его знает (`#if compiler(>=6.2)` — это Xcode 26+)
// и система его поддерживает. На iOS 18–25 те же элементы рисуются обычными материалами.
//
// Правило оформления: стекло — для слоя управления (карточка входа, кнопки действий, всплывающие плашки),
// а строки списка с контентом остаются на материалах, чтобы длинные списки не тормозили.

extension View {
    /// Стеклянная карточка.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    /// Стеклянная капсула (плашки, уведомления).
    @ViewBuilder
    func glassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
        #else
        self.background(.ultraThinMaterial, in: Capsule())
        #endif
    }

    /// Карточка для строк с контентом — обычный материал.
    func contentCard(cornerRadius: CGFloat = 18) -> some View {
        background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Стеклянная кнопка. На старых версиях iOS — обычные системные стили.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            legacyButton(prominent: prominent)
        }
        #else
        legacyButton(prominent: prominent)
        #endif
    }

    /// Панель вкладок сворачивается при прокрутке (iOS 26+), на старых версиях ничего не меняется.
    @ViewBuilder
    func minimizeTabBarOnScroll() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    private func legacyButton(prominent: Bool) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Мягкий цветной фон, чтобы стеклу было что преломлять.
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.indigo.opacity(0.35),
                Color.blue.opacity(0.18),
                Color.teal.opacity(0.28),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .background(Color(.systemBackground))
        .ignoresSafeArea()
    }
}
