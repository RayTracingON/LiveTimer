import Foundation
import SwiftData
import Observation

/// 演出 / 场馆缓存同步。
/// 首次全量拉未来 60 天；之后用 updatedSince 增量拉。墓碑记录删缓存，但**不删**用户已加入日程的条目，只标失效。
@MainActor
@Observable
final class LiveCatalogSync {
    private(set) var isSyncing = false
    private(set) var isOffline = false
    private(set) var lastError: String?
    private(set) var lastSyncedAt: Date?

    private let api: LiveTimerAPI
    private let defaults: UserDefaults
    private static let cursorKey = "livesSync.updatedSince"
    private static let lastSyncKey = "livesSync.lastSyncedAt"
    static let initialWindowDays = 60

    init(api: LiveTimerAPI = .production, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        lastSyncedAt = defaults.object(forKey: Self.lastSyncKey) as? Date
    }

    var hasSyncedOnce: Bool { defaults.object(forKey: Self.cursorKey) != nil }

    /// 启动、下拉刷新、回到前台时调。同一时刻只跑一次。
    func sync(context: ModelContext, force: Bool = false) async {
        guard !isSyncing else { return }
        if !force, let last = lastSyncedAt, Date().timeIntervalSince(last) < 60 { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let cursor = defaults.object(forKey: Self.cursorKey) as? Date
            var newestUpdatedAt = cursor ?? .distantPast

            if let cursor {
                newestUpdatedAt = max(newestUpdatedAt, try await pullIncremental(since: cursor, context: context))
            } else {
                newestUpdatedAt = max(newestUpdatedAt, try await pullInitial(context: context))
            }
            try await pullVenueStats(context: context)
            try context.save()

            // 游标回退 1 秒：后端 updatedAt 截断到秒、比较用 >=，重复拿到一两条按 id 幂等覆盖即可。
            defaults.set(newestUpdatedAt.addingTimeInterval(-1), forKey: Self.cursorKey)
            defaults.set(Date(), forKey: Self.lastSyncKey)
            lastSyncedAt = Date()
            isOffline = false
            lastError = nil
        } catch let error as APIError {
            isOffline = error.isRetryable
            lastError = error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 清掉缓存与游标，下次同步重新全量拉。设置页「清除缓存」用。
    func resetCache(context: ModelContext) {
        try? context.delete(model: CachedLive.self)
        try? context.delete(model: CachedVenue.self)
        try? context.save()
        defaults.removeObject(forKey: Self.cursorKey)
        defaults.removeObject(forKey: Self.lastSyncKey)
        lastSyncedAt = nil
    }

    // MARK: - pulls

    private func pullInitial(context: ModelContext) async throws -> Date {
        let from = Date()
        let to = Calendar.jst.date(byAdding: .day, value: Self.initialWindowDays, to: from) ?? from
        var offset = 0
        var newest = Date.distantPast
        while true {
            let page = try await api.lives(from: from, to: to, limit: 200, offset: offset)
            for dto in page.items {
                newest = max(newest, dto.updatedAt)
                upsert(dto, context: context)
            }
            offset += page.items.count
            if page.items.isEmpty || offset >= page.total { break }
        }
        return newest == .distantPast ? Date() : newest
    }

    private func pullIncremental(since: Date, context: ModelContext) async throws -> Date {
        var offset = 0
        var newest = since
        while true {
            let page = try await api.lives(updatedSince: since, limit: 200, offset: offset)
            for dto in page.items {
                newest = max(newest, dto.updatedAt)
                upsert(dto, context: context)
            }
            offset += page.items.count
            if page.items.isEmpty || offset >= page.total { break }
        }
        return newest
    }

    /// 场馆列表带 upcomingLiveCount / nextLiveAt，地图图层 A 和场馆详情用。
    private func pullVenueStats(context: ModelContext) async throws {
        var offset = 0
        while true {
            let page = try await api.venues(hasUpcomingLives: true, limit: 200, offset: offset)
            for dto in page.items { upsert(dto, context: context) }
            offset += page.items.count
            if page.items.isEmpty || offset >= page.total { break }
        }
    }

    // MARK: - upserts

    func upsert(_ dto: LiveTimerAPI.Live, context: ModelContext) {
        let id = dto.id
        let existing = (try? context.fetch(FetchDescriptor<CachedLive>(predicate: #Predicate { $0.id == id })))?.first

        if dto.isTombstone {
            if let existing { context.delete(existing) }
            markScheduleItemsInvalid(sourceRef: id, context: context)
            return
        }
        guard let title = dto.title, let startAt = dto.startAt, let venue = dto.venue else { return }

        let lineup = (dto.lineup ?? []).sorted { $0.billingOrder < $1.billingOrder }.map {
            LineupEntry(id: $0.artist.id, name: $0.artist.name, nameCn: $0.artist.nameCn, nameLatin: $0.artist.nameLatin,
                        type: $0.artist.type, imageUrl: $0.artist.imageUrl, isHeadliner: $0.isHeadliner,
                        billingOrder: $0.billingOrder)
        }
        let lineupJSON = (try? JSONEncoder().encode(lineup)) ?? Data()

        if let existing {
            existing.title = title
            existing.subtitle = dto.subtitle
            existing.venueId = venue.id
            existing.venueName = venue.name
            existing.venueAddress = venue.address
            existing.venueLatitude = venue.lat
            existing.venueLongitude = venue.lng
            existing.nearestStation = venue.nearestStation
            existing.openAt = dto.openAt
            existing.startAt = startAt
            existing.endAt = dto.endAt
            existing.priceAdvance = dto.priceAdvance
            existing.priceDoor = dto.priceDoor
            existing.hasDrinkFee = dto.hasDrinkFee ?? false
            existing.drinkFee = dto.drinkFee
            existing.ticketUrl = dto.ticketUrl
            existing.ticketVendor = dto.ticketVendor
            existing.coverImageUrl = dto.coverImageUrl
            existing.summary = dto.description
            existing.statusRaw = dto.status ?? LiveStatus.scheduled.rawValue
            existing.tags = dto.tags ?? []
            existing.lineupJSON = lineupJSON
            existing.updatedAt = dto.updatedAt
            existing.cachedAt = Date()
        } else {
            context.insert(CachedLive(
                id: id, title: title, subtitle: dto.subtitle, venueId: venue.id, venueName: venue.name,
                venueAddress: venue.address, venueLatitude: venue.lat, venueLongitude: venue.lng,
                nearestStation: venue.nearestStation, openAt: dto.openAt, startAt: startAt, endAt: dto.endAt,
                priceAdvance: dto.priceAdvance, priceDoor: dto.priceDoor, hasDrinkFee: dto.hasDrinkFee ?? false,
                drinkFee: dto.drinkFee, ticketUrl: dto.ticketUrl, ticketVendor: dto.ticketVendor,
                coverImageUrl: dto.coverImageUrl, summary: dto.description,
                statusRaw: dto.status ?? LiveStatus.scheduled.rawValue, tags: dto.tags ?? [],
                lineupJSON: lineupJSON, updatedAt: dto.updatedAt))
        }
        // 已加入日程的条目同步最新时间/场馆，改期、换场馆时周日历跟着变。
        refreshScheduleItems(from: dto, context: context)
    }

    func upsert(_ dto: LiveTimerAPI.Venue, context: ModelContext) {
        let id = dto.id
        let existing = (try? context.fetch(FetchDescriptor<CachedVenue>(predicate: #Predicate { $0.id == id })))?.first
        if dto.isTombstone {
            if let existing { context.delete(existing) }
            return
        }
        guard let name = dto.name, let address = dto.address, let lat = dto.lat, let lng = dto.lng else { return }
        if let existing {
            existing.name = name
            existing.address = address
            existing.prefecture = dto.prefecture
            existing.latitude = lat
            existing.longitude = lng
            existing.nearestStation = dto.nearestStation
            existing.upcomingLiveCount = dto.upcomingLiveCount ?? existing.upcomingLiveCount
            existing.nextLiveAt = dto.nextLiveAt ?? existing.nextLiveAt
            existing.updatedAt = dto.updatedAt
        } else {
            context.insert(CachedVenue(id: id, name: name, address: address, prefecture: dto.prefecture, latitude: lat,
                                       longitude: lng, nearestStation: dto.nearestStation,
                                       upcomingLiveCount: dto.upcomingLiveCount ?? 0, nextLiveAt: dto.nextLiveAt,
                                       updatedAt: dto.updatedAt))
        }
    }

    private func markScheduleItemsInvalid(sourceRef: String, context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<ScheduleItem>(predicate: #Predicate { $0.sourceRef == sourceRef }))) ?? []
        for item in items where !item.isSourceInvalid {
            item.isSourceInvalid = true
            item.updatedAt = Date()
        }
    }

    private func refreshScheduleItems(from dto: LiveTimerAPI.Live, context: ModelContext) {
        let ref = dto.id
        let items = (try? context.fetch(FetchDescriptor<ScheduleItem>(predicate: #Predicate { $0.sourceRef == ref }))) ?? []
        guard !items.isEmpty, let startAt = dto.startAt, let venue = dto.venue else { return }
        for item in items {
            let open = dto.openAt ?? startAt
            let changed = item.startAt != open || item.locationName != venue.name || item.isSourceInvalid
                || item.endAt != (dto.endAt ?? startAt.addingTimeInterval(ScheduleItem.assumedDuration))
            if changed {
                item.startAt = open
                item.endAt = dto.endAt ?? startAt.addingTimeInterval(ScheduleItem.assumedDuration)
                item.title = dto.title ?? item.title
                item.locationName = venue.name
                item.locationAddress = venue.address
                item.latitude = venue.lat
                item.longitude = venue.lng
                item.externalUrl = dto.ticketUrl
                item.isSourceInvalid = dto.status == LiveStatus.cancelled.rawValue
                item.updatedAt = Date()
            }
        }
    }
}
