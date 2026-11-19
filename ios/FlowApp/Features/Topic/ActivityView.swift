import SwiftUI
import UIKit

/// Системное меню «Поделиться». Через него `.torrent` отправляется в торрент-клиент или в «Файлы».
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
