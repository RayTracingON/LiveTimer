import SwiftUI

/// 页面7-a: 首次启动引导。
/// 这里不申请任何权限，把权限请求推迟到真正需要的那一刻(导出日历、注册通知)。
struct OnboardingView: View {
    let onFinish: () -> Void

    private struct Page: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
        let tint: Color
    }

    private let pages: [Page] = [
        Page(icon: "music.note.list",
             title: "全国的演出\n汇成一条时间线",
             body: "把散落在各家 livehouse 的演出信息，按周排进你的日历。",
             tint: Theme.C.accent),
        Page(icon: "calendar.badge.plus",
             title: "想去的演出\n一键加进日程",
             body: "同一天撞车的场次会在日历上直接标出来。数据只存在这台设备上，换设备不会迁移。",
             tint: Theme.C.accentAlt),
        Page(icon: "map.fill",
             title: "地图上\n找场馆和落脚点",
             body: "演出场馆、酒店和巡礼地点放在同一张地图上，远征路线一眼看清。",
             tint: Theme.C.kind(.custom))
    ]

    @State private var index = 0

    var body: some View {
        ZStack {
            Theme.C.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $index) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                        VStack(spacing: 20) {
                            Spacer()
                            Image(systemName: page.icon)
                                .font(.system(size: 64, weight: .light))
                                .foregroundStyle(page.tint)
                            Text(page.title)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(Theme.C.textPrimary)
                                .multilineTextAlignment(.center)
                            Text(page.body)
                                .font(Theme.F.body)
                                .foregroundStyle(Theme.C.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 36)
                            Spacer()
                        }
                        .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if index < pages.count - 1 {
                        withAnimation { index += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(index < pages.count - 1 ? "下一步" : "开始使用")
                        .font(Theme.F.cardTitle)
                        .foregroundStyle(Theme.C.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.C.accent))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

                Button("跳过", action: onFinish)
                    .font(Theme.F.caption)
                    .tint(Theme.C.textTertiary)
                    .padding(.bottom, 20)
            }
        }
    }
}

#Preview {
    OnboardingView {}
}
