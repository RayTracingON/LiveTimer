import Foundation
import SwiftData
import Observation
import CoreLocation

/// IP 订阅与巡礼地标缓存。
/// 刷新策略：先拉很轻的 /lite 比较 modified，变了才拉全量 detail（几百个点）。
@MainActor
@Observable
final class PilgrimageStore {
    struct Progress: Equatable {
        var subjectId: Int
        var stage: String
    }

    private(set) var progress: Progress?
    private(set) var lastError: String?
    /// 上一次订阅的过滤结果，用来给用户一个交代（拉了多少、留了多少）。
    private(set) var lastFilterSummary: String?

    private let anitabi = AnitabiAPI.shared
    static let refreshInterval: TimeInterval = 7 * 86400
    /// 只保留距离演出场馆这么近的地标。一部作品动辄几百个点，
    /// 全存下来地图会被跟这趟远征无关的点淹没。
    static let radiusMeters: CLLocationDistance = 100_000

    /// 订阅：写 SubscribedIP → 后台拉全量地标 → 落 CachedPilgrimagePoint。
    func subscribe(_ entry: LiveTimerAPI.IpCatalogEntry, context: ModelContext) async {
        let id = entry.bangumiSubjectId
        progress = Progress(subjectId: id, stage: "正在读取作品信息…")
        defer { progress = nil }
        do {
            let lite = try await anitabi.lite(subjectId: id)
            let existing = fetchSubscribed(id, context: context)
            let ip = existing ?? SubscribedIP(
                bangumiSubjectId: id,
                titleOriginal: entry.titleOriginal ?? lite.title ?? "#\(id)",
                titleCn: entry.titleCn ?? lite.cn,
                coverUrl: entry.coverUrl ?? lite.cover,
                themeColorHex: entry.themeColor ?? lite.color,
                defaultLatitude: entry.defaultGeo?.first ?? lite.geo?.first ?? 35.68,
                defaultLongitude: entry.defaultGeo?.last ?? lite.geo?.last ?? 139.76,
                pointCount: entry.pointCount ?? lite.pointsLength ?? 0)
            if existing == nil { context.insert(ip) }
            try context.save()
            try await pullPoints(for: ip, lite: lite, force: true, context: context)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 移除订阅。地标缓存一起删；已加入日程的该作品条目按参数决定。
    func unsubscribe(_ ip: SubscribedIP, deleteScheduleItems: Bool, context: ModelContext) {
        let id = ip.bangumiSubjectId
        try? context.delete(model: CachedPilgrimagePoint.self, where: #Predicate { $0.subjectId == id })
        if deleteScheduleItems {
            try? context.delete(model: ScheduleItem.self, where: #Predicate { $0.sourceSubjectId == id })
        }
        context.delete(ip)
        try? context.save()
    }

    /// 手动下拉刷新 / 每 7 天一次的后台检查。
    func refreshIfStale(context: ModelContext, force: Bool = false) async {
        let ips = (try? context.fetch(FetchDescriptor<SubscribedIP>())) ?? []
        for ip in ips {
            let stale = ip.pointsFetchedAt.map { Date().timeIntervalSince($0) > Self.refreshInterval } ?? true
            guard force || stale else { continue }
            do {
                let lite = try await anitabi.lite(subjectId: ip.bangumiSubjectId)
                if force || (lite.modified ?? 0) > (ip.anitabiModified ?? -1) {
                    try await pullPoints(for: ip, lite: lite, force: force, context: context)
                } else {
                    ip.pointsFetchedAt = Date()
                    try? context.save()
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - internals

    private func pullPoints(for ip: SubscribedIP, lite: AnitabiAPI.Lite, force: Bool, context: ModelContext) async throws {
        progress = Progress(subjectId: ip.bangumiSubjectId, stage: "正在拉取 \(lite.pointsLength ?? ip.pointCount) 个地标…")
        guard let points = try await anitabi.pointsDetail(subjectId: ip.bangumiSubjectId, force: force) else { return }
        let id = ip.bangumiSubjectId
        try? context.delete(model: CachedPilgrimagePoint.self, where: #Predicate { $0.subjectId == id })

        let anchors = scheduleVenues(context: context)
        var withGeo = 0
        var kept = 0
        for p in points {
            // 没有坐标的地标没法上图，跳过。
            guard let geo = p.geo, geo.count == 2 else { continue }
            withGeo += 1
            guard isNearSchedule(latitude: geo[0], longitude: geo[1], anchors: anchors) else { continue }
            context.insert(CachedPilgrimagePoint(
                id: p.id, subjectId: id, name: p.name ?? p.cn ?? p.id, nameCn: p.cn,
                imageUrl: AnitabiAPI.imageBase(from: p.image), episode: p.ep, seconds: p.s,
                latitude: geo[0], longitude: geo[1], origin: p.origin, originURL: p.originURL))
            kept += 1
        }
        ip.anitabiModified = lite.modified
        ip.pointsFetchedAt = Date()
        ip.pointCount = kept
        if let cover = lite.cover { ip.coverUrl = cover }
        try context.save()

        if withGeo == 0, !points.isEmpty {
            lastError = "anitabi 返回了 \(points.count) 个地标但都没有坐标，无法上图"
        } else if anchors.isEmpty {
            lastFilterSummary = "日程里还没有演出，已保留全部 \(kept) 个地标"
        } else if kept < withGeo {
            lastFilterSummary = "\(withGeo) 个地标中，保留了场馆 100km 内的 \(kept) 个"
        } else {
            lastFilterSummary = "保留了 \(kept) 个地标"
        }
    }

    /// 过滤基准：用户日程里演出的场馆坐标。日程为空时返回空数组 = 不过滤。
    private func scheduleVenues(context: ModelContext) -> [CLLocation] {
        let items = (try? context.fetch(FetchDescriptor<ScheduleItem>())) ?? []
        return items
            .filter { $0.kind == .live }
            .compactMap { item in
                guard let lat = item.latitude, let lng = item.longitude else { return nil }
                return CLLocation(latitude: lat, longitude: lng)
            }
    }

    private func isNearSchedule(latitude: Double, longitude: Double, anchors: [CLLocation]) -> Bool {
        guard !anchors.isEmpty else { return true }   // 没有基准点就不过滤
        let point = CLLocation(latitude: latitude, longitude: longitude)
        return anchors.contains { $0.distance(from: point) <= Self.radiusMeters }
    }

    private func fetchSubscribed(_ id: Int, context: ModelContext) -> SubscribedIP? {
        (try? context.fetch(FetchDescriptor<SubscribedIP>(predicate: #Predicate { $0.bangumiSubjectId == id })))?.first
    }
}
