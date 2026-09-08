import SwiftUI

/// 加入日程的反馈。需求要求「明确的成功反馈」，
/// 但冲突提示不能打断，所以 toast 只承载肯定结果和一句轻提醒。
struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    var detail: String?
    var icon: String = "checkmark.circle.fill"
    var tint: Color = Theme.C.accentAlt

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool { lhs.id == rhs.id }
}

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: message.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(message.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.text)
                    .font(Theme.F.cardTitle)
                    .foregroundStyle(Theme.C.textPrimary)
                if let detail = message.detail {
                    Text(detail)
                        .font(Theme.F.caption)
                        .foregroundStyle(Theme.C.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.C.surfaceRaised)
                .overlay {
                    RoundedRectangle(cornerRadius: 12).stroke(message.tint.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        }
        .padding(.horizontal, Theme.M.screenPadding)
    }
}

extension View {
    /// 出现在不挡标签栏的位置，过一会自动收回。
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        overlay(alignment: .bottom) {
            if let current = message.wrappedValue {
                ToastView(message: current)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: current.id) {
                        try? await Task.sleep(for: .seconds(2.4))
                        withAnimation(.easeOut(duration: 0.25)) { message.wrappedValue = nil }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message.wrappedValue)
    }
}
