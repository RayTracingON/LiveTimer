import SwiftUI
import SwiftData

enum RootTab: Hashable {
    case schedule, map, discover, me
}

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(LiveCatalogSync.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    /// 调试用：`-initialTab map` 启动参数可直接落到某个 Tab（截图 / UI 自动化）。
    @State private var selectedTab: RootTab = {
        switch UserDefaults.standard.string(forKey: "initialTab") {
        case "map": return .map
        case "discover": return .discover
        case "me": return .me
        default: return .schedule
        }
    }()
    @State private var toast: ToastMessage?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("日程", systemImage: "calendar", value: RootTab.schedule) {
                ScheduleHomeView(toast: $toast, selectedTab: $selectedTab)
            }
            Tab("地图", systemImage: "map", value: RootTab.map) {
                MapScreen(toast: $toast)
            }
            Tab("发现", systemImage: "music.note.list", value: RootTab.discover) {
                LivesListView(toast: $toast)
            }
            Tab("我的", systemImage: "person.crop.circle", value: RootTab.me) {
                SettingsView(toast: $toast)
            }
        }
        .tint(Theme.C.accent)
        .environment(\.calendar, .jst)
        .environment(\.timeZone, DateOnly.jst)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .preferredColorScheme(.dark)
        .toast($toast)
        .fullScreenCover(isPresented: .init(get: { !hasCompletedOnboarding }, set: { if !$0 { hasCompletedOnboarding = true } })) {
            OnboardingView { hasCompletedOnboarding = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await sync.sync(context: context) } }
        }
    }
}
