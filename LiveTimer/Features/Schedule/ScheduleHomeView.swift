import SwiftUI
import SwiftData

enum ScheduleViewMode: String, CaseIterable, Identifiable {
    case week = "周", list = "列表"
    var id: String { rawValue }
}

/// 日程首页：周视图（默认）/ 列表视图。月视图是 P1。
struct ScheduleHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScheduleItem.startAt) private var items: [ScheduleItem]
    @Binding var toast: ToastMessage?
    @Binding var selectedTab: RootTab

    @State private var mode: ScheduleViewMode = .week
    /// 相对本周的偏移；0 = 本周。TabView 分页用它做 selection。
    @State private var weekOffset = 0
    @State private var swipeDirection = 1
    @State private var selectedItem: ScheduleItem?
    @State private var newEventAt: Date?
    @State private var listAnchorDay: Date?

    private let calendar = Calendar.jst

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    switch mode {
                    case .week: weekPager
                    case .list: DayListView(items: items, anchorDay: listAnchorDay, onSelect: { selectedItem = $0 })
                    }
                }
            }
            .background(Theme.C.background)
            .navigationTitle(monthTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 2) {
                        Button { swipeDirection = -1; withAnimation { weekOffset -= 1 } } label: { Image(systemName: "chevron.left") }
                        Button("今天") { swipeDirection = weekOffset > 0 ? -1 : 1; withAnimation { weekOffset = 0 } }
                            .disabled(weekOffset == 0)
                        Button { swipeDirection = 1; withAnimation { weekOffset += 1 } } label: { Image(systemName: "chevron.right") }
                    }
                    .tint(Theme.C.accent)
                    .disabled(mode != .week)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("视图", selection: $mode) {
                        ForEach(ScheduleViewMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            .sheet(item: $selectedItem) { item in
                ScheduleItemDetailSheet(item: item, toast: $toast)
            }
            .sheet(item: $newEventAt) { date in
                NewCustomEventSheet(startAt: date, toast: $toast)
            }
        }
    }

    /// 不用 TabView(.page)：它嵌在 NavigationStack 里会把页面内容往下顶出一大块空白。改用横向滑动切周。
    private var weekPager: some View {
        WeekGridView(
            weekStart: weekStart(offset: weekOffset),
            items: items(inWeek: weekOffset),
            onSelect: { selectedItem = $0 },
            onLongPressEmpty: { newEventAt = $0 },
            onExpandDay: { day in listAnchorDay = day; mode = .list }
        )
        .id(weekOffset)
        .transition(.asymmetric(insertion: .move(edge: swipeDirection >= 0 ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: swipeDirection >= 0 ? .leading : .trailing).combined(with: .opacity)))
        .simultaneousGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    swipeDirection = value.translation.width < 0 ? 1 : -1
                    withAnimation(.easeInOut(duration: 0.25)) { weekOffset += swipeDirection }
                }
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            EmptyStateView(
                icon: "calendar",
                title: "日历还是空的",
                message: "从地图上找到想去的演出，点「加入日程」就会排进这里。撞车的场次会直接标出来。\n数据只存在这台设备上，换设备不会迁移。",
                actionTitle: "去地图看看",
                action: { selectedTab = .map }
            )
            Button("或者先记一条自定义安排") { newEventAt = defaultNewEventDate() }
                .font(Theme.F.caption)
                .tint(Theme.C.textTertiary)
            Spacer()
        }
    }

    // MARK: - helpers

    private func weekStart(offset: Int) -> Date {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeek) ?? thisWeek
    }

    private func items(inWeek offset: Int) -> [ScheduleItem] {
        let start = weekStart(offset: offset)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return items.filter { $0.startAt < end && $0.effectiveEndAt > start }
    }

    private var monthTitle: String {
        let start = weekStart(offset: weekOffset)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = DateOnly.jst
        f.dateFormat = "yyyy年M月"
        return mode == .week ? f.string(from: start) : "我的日程"
    }

    private func defaultNewEventDate() -> Date {
        calendar.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
    }
}

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSinceReferenceDate }
}
