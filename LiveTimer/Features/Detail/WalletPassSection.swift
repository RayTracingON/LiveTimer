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
    @State private var seat = PassSeatInput()
    @State private var showingSeatSheet = false

    var body: some View {
        if config.walletPassEnabled, PassManager.canAddPasses, live.status != .cancelled {
            VStack(spacing: 10) {
                seatRow
                content
                // 必须有：这张卡不是入场券
                Text("※ 这是行程提醒卡，不是入场券")
                    .font(Theme.F.tag)
                    .foregroundStyle(Theme.C.textTertiary)
            }
            .task(id: live.id) {
                seat = SeatNote.find(liveId: live.id, in: context)?.seat ?? PassSeatInput()
                await manager.load(liveId: live.id, seat: seat, context: context)
            }
            .sheet(isPresented: $showingSeatSheet) {
                SeatInputSheet(seat: $seat, isSaving: manager.isUpdatingSeat) { edited in
                    seat = edited
                    SeatNote.save(edited, liveId: live.id, in: context)
                    Task { await manager.applySeat(edited.isEmpty ? nil : edited, liveId: live.id, context: context) }
                }
            }
        }
    }

    /// 座位入口。填过就显示卡面上那行字，没填过提示可以填。
    private var seatRow: some View {
        Button { showingSeatSheet = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "chair.lounge")
                    .foregroundStyle(Theme.C.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(seat.isEmpty ? "填写座位 / 整理番号" : seat.displayLabel)
                        .font(Theme.F.caption)
                        .foregroundStyle(Theme.C.textSecondary)
                    if !seat.isEmpty {
                        Text(seat.displayText)
                            .font(Theme.F.cardTitle)
                            .foregroundStyle(Theme.C.textPrimary)
                    }
                }
                Spacer()
                Text(seat.isEmpty ? "可选" : "修改")
                    .font(Theme.F.caption)
                    .foregroundStyle(Theme.C.accent)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.C.textTertiary)
            }
            .padding(.horizontal, Theme.M.cardPadding)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.C.surface))
        }
        .buttonStyle(.plain)
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
