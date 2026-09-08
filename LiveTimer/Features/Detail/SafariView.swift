import SwiftUI
import SafariServices

/// 购票外链用 SFSafariViewController，不做交易本身。
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        // 不再设置 preferredControlTintColor：iOS 26 起废弃，着色会干扰系统的背景效果
        return SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
