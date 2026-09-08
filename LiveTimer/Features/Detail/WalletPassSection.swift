import SwiftUI
import SwiftData
import PassKit

/// 演出详情底部的「添加到 Apple Wallet」区块。
///
/// 三条 Apple 规则：按钮必须用系统控件（不能自绘、不能改配色）；不能用置灰表示「已添加」，
/// 而是换成跳转钱包；远程配置关掉时整个入口隐藏。
struct WalletPassSection: View {
    let live: CachedLive

    @Environment(\.modelContext) private var context
    @Environment(RemoteConfig.self) private var config
    @Environment(\.openURL) private var openURL
    @State private var manager = PassManager()

    var body: some View {
        if config.walletPassEnabled, PassManager.canAddPasses, live.status != .cancelled {
            VStack(spacing: 6) {
                content
                // 必须有：这张卡不是入场券
                Text("※ 这是行程提醒卡，不是入场券")
                    .font(Theme.F.tag)
                    .foregroundStyle(Theme.C.textTertiary)
            }
            .task(id: live.id) { await manager.load(liveId: live.id) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.state {
        case .idle, .loading:
            ProgressView().frame(height: 44)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(Theme.F.caption)
                .foregroundStyle(Theme.C.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .ready(let pass):
            if manager.isInWallet {
                Button {
                    if let url = manager.walletURL { openURL(url) }
                } label: {
                    Label("在钱包中查看", systemImage: "wallet.pass")
                        .font(Theme.F.body)
                        .foregroundStyle(Theme.C.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.C.surfaceRaised))
                }
                .buttonStyle(.plain)
            } else {
                // SwiftUI 原生控件，不需要包 UIViewControllerRepresentable
                AddPassToWalletButton([pass]) { added in
                    manager.didFinishAdding(added: added, liveId: live.id, context: context)
                }
                .addPassToWalletButtonStyle(.black)
                .frame(height: 48)
            }
        }
    }
}
