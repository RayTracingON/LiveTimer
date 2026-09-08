import Foundation
import SwiftData

/// 对 ScheduleItem 的写操作集中在这里，页面只调用不直接 insert。
enum ScheduleStore {

    struct AddResult {
        let item: ScheduleItem
        /// 加进去后和哪些 Live 条目重叠（只有 Live 之间才算真冲突）。
        let conflicts: [ScheduleItem]
    }

    static func existingItem(forLive liveId: String, in context: ModelContext) -> ScheduleItem? {
        (try? context.fetch(FetchDescriptor<ScheduleItem>(predicate: #Predicate { $0.sourceRef == liveId }))
            .first { $0.kind == .live })
    }

    /// 演出加入日程。startAt 取开场（人到场的时间），endAt 未知时按开演 + 2 小时估。
    @discardableResult
    static func add(live: CachedLive, in context: ModelContext) -> AddResult {
        if let existing = existingItem(forLive: live.id, in: context) {
            return AddResult(item: existing, conflicts: liveConflicts(for: existing, in: context))
        }
        let start = live.openAt ?? live.startAt
        let item = ScheduleItem(
            kind: .live,
            title: live.title,
            subtitle: live.lineup.isEmpty ? live.subtitle : live.artistNames,
            startAt: start,
            endAt: live.endAt ?? live.startAt.addingTimeInterval(ScheduleItem.assumedDuration),
            note: "開場 \(Fmt.time.string(from: start)) / 開演 \(Fmt.time.string(from: live.startAt))",
            locationName: live.venueName,
            locationAddress: live.venueAddress,
            latitude: live.venueLatitude,
            longitude: live.venueLongitude,
            sourceRef: live.id,
            externalUrl: live.ticketUrl)
        context.insert(item)
        try? context.save()
        return AddResult(item: item, conflicts: liveConflicts(for: item, in: context))
    }

    @discardableResult
    static func addCustom(title: String, startAt: Date, endAt: Date, note: String?, locationName: String?,
                          in context: ModelContext) -> ScheduleItem {
        let item = ScheduleItem(kind: .custom, title: title, startAt: startAt, endAt: endAt, note: note,
                                locationName: locationName)
        context.insert(item)
        try? context.save()
        return item
    }

    /// 酒店：跨夜住宿恒为全天横条。
    @discardableResult
    static func addHotel(name: String, address: String?, latitude: Double?, longitude: Double?, checkIn: Date, checkOut: Date,
                         url: String?, phone: String?, in context: ModelContext) -> ScheduleItem {
        let nights = max(1, Calendar.jst.dateComponents([.day], from: Calendar.jst.startOfDay(for: checkIn),
                                                        to: Calendar.jst.startOfDay(for: checkOut)).day ?? 1)
        let item = ScheduleItem(kind: .hotel, title: name, subtitle: "\(nights) 泊",
                                startAt: Calendar.jst.startOfDay(for: checkIn),
                                endAt: Calendar.jst.startOfDay(for: checkOut),
                                isAllDayBand: true, note: phone.map { "TEL \($0)" },
                                locationName: name, locationAddress: address, latitude: latitude, longitude: longitude,
                                sourceRef: nil, externalUrl: url)
        context.insert(item)
        try? context.save()
        return item
    }

    /// 巡礼地标：默认 1 小时。
    @discardableResult
    static func addPilgrimage(point: CachedPilgrimagePoint, workTitle: String, at startAt: Date, in context: ModelContext) -> ScheduleItem {
        let item = ScheduleItem(kind: .pilgrimage, title: point.nameCn ?? point.name, subtitle: workTitle,
                                startAt: startAt, endAt: startAt.addingTimeInterval(3600),
                                note: point.episodeText,
                                locationName: point.name, latitude: point.latitude, longitude: point.longitude,
                                sourceRef: point.id, sourceSubjectId: point.subjectId, externalUrl: point.originURL)
        context.insert(item)
        try? context.save()
        return item
    }

    static func remove(_ item: ScheduleItem, in context: ModelContext) {
        context.delete(item)
        try? context.save()
    }

    /// 同一天内、时间重叠、且都是 Live 的条目。酒店和 Live 重叠是正常的，不算。
    static func liveConflicts(for item: ScheduleItem, in context: ModelContext) -> [ScheduleItem] {
        guard item.kind == .live else { return [] }
        let all = (try? context.fetch(FetchDescriptor<ScheduleItem>())) ?? []
        return all.filter { other in
            other.id != item.id && other.kind == .live && !other.isAllDayBand
                && other.interval.intersects(item.interval)
        }
    }
}
