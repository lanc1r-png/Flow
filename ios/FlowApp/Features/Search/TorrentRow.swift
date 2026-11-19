import FlowCore
import SwiftUI

struct TorrentRow: View {
    let torrent: TorrentSummary
    var showsCategory = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsCategory, let category = torrent.category {
                CategoryLine(category: category)
            }

            Text(torrent.title)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            if !torrent.tags.isEmpty {
                Text(torrent.tags)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 14) {
                if !torrent.size.isEmpty {
                    Label(torrent.size, systemImage: "internaldrive")
                }
                if let seeds = torrent.seeds {
                    Label("\(seeds)", systemImage: "arrow.up")
                        .foregroundStyle(.green)
                }
                if let leeches = torrent.leeches {
                    Label("\(leeches)", systemImage: "arrow.down")
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 0)
                if let status = torrent.status {
                    StatusBadge(status: status)
                }
            }
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .contentCard()
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StatusBadge: View {
    let status: TorrentStatus

    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .approved: return .green
        case .checking, .notApproved: return .orange
        case .closed, .consumed, .duplicate: return .red
        case .needEdit, .noDescription: return .yellow
        }
    }
}
