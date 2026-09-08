import SwiftUI
import SwiftData
import GoogleMaps

@main
struct LiveTimerApp: App {
    private let container = ModelContainer.liveTimer()

    init() {
        // Key 由 Config/Secrets.xcconfig → Info.plist(GMSApiKey) 注入，不写在源码里。
        if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !key.isEmpty {
            GMSServices.provideAPIKey(key)
        } else {
            assertionFailure("GMSApiKey 缺失：请创建 Config/Secrets.xcconfig")
        }
    }
    @State private var remoteConfig = RemoteConfig()
    @State private var sync = LiveCatalogSync()
    @State private var pilgrimage = PilgrimageStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(remoteConfig)
                .environment(sync)
                .environment(pilgrimage)
                .task {
                    await remoteConfig.refresh()
                    await sync.sync(context: container.mainContext)
                    if remoteConfig.pilgrimageLayerEnabled { await pilgrimage.refreshIfStale(context: container.mainContext) }
                    #if DEBUG
                    // 截图 / 调试用：`-debugSeedSchedule YES` 把缓存里最早的一场演出加进日程，
                    // 再放一条和它重叠的假 Live（无 sourceRef，同步不会动它），用来看冲突描边。
                    if UserDefaults.standard.bool(forKey: "debugSeedSchedule"),
                       let first = try? container.mainContext.fetch(FetchDescriptor<CachedLive>(sortBy: [SortDescriptor(\.startAt)])).first {
                        let item = ScheduleStore.add(live: first, in: container.mainContext).item
                        let fake = ScheduleItem(kind: .live, title: "重なるライブ（テスト）", subtitle: "冲突样式验证",
                                                startAt: item.startAt.addingTimeInterval(1800),
                                                endAt: item.startAt.addingTimeInterval(1800 + 2 * 3600),
                                                locationName: "Zepp DiverCity")
                        container.mainContext.insert(fake)
                        let hotel = ScheduleItem(kind: .hotel, title: "ホテル 2泊", startAt: Calendar.jst.startOfDay(for: item.startAt),
                                                 endAt: Calendar.jst.startOfDay(for: item.startAt).addingTimeInterval(2 * 86400),
                                                 isAllDayBand: true, locationName: "新宿")
                        container.mainContext.insert(hotel)
                        try? container.mainContext.save()
                    }
                    #endif
                }
        }
        .modelContainer(container)
    }
}
