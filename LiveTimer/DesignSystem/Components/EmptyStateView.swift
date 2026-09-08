import SwiftUI

/// 需求里提到的三种空状态用同一个类型承载。
/// 空状态比起「什么都没有」，更重要的是告诉用户下一步该做什么，所以一定带一个动作。
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.C.accent.opacity(0.7))

            Text(title)
                .font(Theme.F.sectionTitle)
                .foregroundStyle(Theme.C.textPrimary)

            Text(message)
                .font(Theme.F.body)
                .foregroundStyle(Theme.C.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.F.cardTitle)
                        .foregroundStyle(Theme.C.background)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Theme.C.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
