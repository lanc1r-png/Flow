import FlowCore
import SwiftUI

/// Иконка и цвет корневой категории — по ключевым словам в названии.
enum CategoryStyle {
    static func icon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("аним") || n.contains("мульт") { return "sparkles.tv" }
        if n.contains("кино") || n.contains("фильм") || n.contains("видео") || n.contains("сериал") { return "film" }
        if n.contains("музык") || n.contains("hi-res") || n.contains("lossless") { return "music.note" }
        if n.contains("игр") { return "gamecontroller" }
        if n.contains("программ") || n.contains("софт") || n.contains("дизайн") { return "macwindow" }
        if n.contains("книг") || n.contains("журнал") || n.contains("литератур") { return "book" }
        if n.contains("спорт") { return "figure.run" }
        if n.contains("обуч") { return "graduationcap" }
        if n.contains("мобил") { return "iphone" }
        if n.contains("новост") { return "newspaper" }
        return "folder"
    }

    static func color(for name: String) -> Color {
        let n = name.lowercased()
        if n.contains("аним") || n.contains("мульт") { return .pink }
        if n.contains("кино") || n.contains("фильм") || n.contains("видео") || n.contains("сериал") { return .red }
        if n.contains("музык") || n.contains("hi-res") || n.contains("lossless") { return .purple }
        if n.contains("игр") { return .green }
        if n.contains("программ") || n.contains("софт") || n.contains("дизайн") { return .blue }
        if n.contains("книг") || n.contains("журнал") || n.contains("литератур") { return .brown }
        if n.contains("спорт") { return .orange }
        if n.contains("обуч") { return .teal }
        let palette: [Color] = [.indigo, .mint, .cyan, .orange, .teal, .blue]
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }
}

/// Цветная плашка с названием категории.
struct CategoryChip: View {
    let title: String

    var body: some View {
        let color = CategoryStyle.color(for: title)
        Label(title, systemImage: CategoryStyle.icon(for: title))
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// Строка «плашка корневой категории + название форума».
struct CategoryLine: View {
    let category: CategoryRef
    @Environment(ForumStore.self) private var forums

    var body: some View {
        HStack(spacing: 6) {
            if let root = forums.rootName(forForum: category.id) {
                CategoryChip(title: root)
                    .layoutPriority(1)
                Text(category.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                CategoryChip(title: category.name)
            }
        }
        .font(.caption)
    }
}

/// Круглая иконка категории.
struct CategoryIcon: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        let color = CategoryStyle.color(for: name)
        Image(systemName: CategoryStyle.icon(for: name))
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: Circle())
    }
}
