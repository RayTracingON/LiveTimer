import Foundation
import SwiftData

extension ModelContainer {
    static let schema = Schema([
        ScheduleItem.self, CachedLive.self, CachedVenue.self,
        SubscribedIP.self, CachedPilgrimagePoint.self, WalletPassRecord.self, SeatNote.self,
    ])

    /// 正式容器。所有用户数据只存本机，没有账号，换设备不迁移（v1 有意取舍）。
    static func liveTimer() -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            // 本地库损坏时宁可重建也不能让 App 打不开；缓存可重拉，日程是用户数据，所以先备份一份。
            fatalError("SwiftData 容器初始化失败: \(error)")
        }
    }

    static func preview() -> ModelContainer {
        try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }
}
