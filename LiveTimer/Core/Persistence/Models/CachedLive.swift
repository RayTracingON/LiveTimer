import Foundation
import SwiftData

/// 镜像后端 Live，供离线查看。venue 的展示字段一并冗余，详情页不用再关联查询。
@Model
final class CachedLive {
    @Attribute(.unique) var id: String
    var title: String
    var subtitle: String?
    var venueId: String
    var venueName: String
    var venueAddress: String
    var venueLatitude: Double
    var venueLongitude: Double
    var nearestStation: String?
    var openAt: Date?
    var startAt: Date
    var endAt: Date?
    var priceAdvance: Int?
    var priceDoor: Int?
    var hasDrinkFee: Bool
    var drinkFee: Int?
    var ticketUrl: String?
    var ticketVendor: String?
    var coverImageUrl: String?
    var summary: String?
    var statusRaw: String
    var tags: [String]
    /// 精简 lineup 直接存 JSON，不建关联表。
    var lineupJSON: Data
    var updatedAt: Date
    var cachedAt: Date

    init(id: String, title: String, subtitle: String?, venueId: String, venueName: String, venueAddress: String,
         venueLatitude: Double, venueLongitude: Double, nearestStation: String?, openAt: Date?, startAt: Date,
         endAt: Date?, priceAdvance: Int?, priceDoor: Int?, hasDrinkFee: Bool, drinkFee: Int?, ticketUrl: String?,
         ticketVendor: String?, coverImageUrl: String?, summary: String?, statusRaw: String, tags: [String],
         lineupJSON: Data, updatedAt: Date) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.venueId = venueId
        self.venueName = venueName
        self.venueAddress = venueAddress
        self.venueLatitude = venueLatitude
        self.venueLongitude = venueLongitude
        self.nearestStation = nearestStation
        self.openAt = openAt
        self.startAt = startAt
        self.endAt = endAt
        self.priceAdvance = priceAdvance
        self.priceDoor = priceDoor
        self.hasDrinkFee = hasDrinkFee
        self.drinkFee = drinkFee
        self.ticketUrl = ticketUrl
        self.ticketVendor = ticketVendor
        self.coverImageUrl = coverImageUrl
        self.summary = summary
        self.statusRaw = statusRaw
        self.tags = tags
        self.lineupJSON = lineupJSON
        self.updatedAt = updatedAt
        self.cachedAt = Date()
    }

    var status: LiveStatus { LiveStatus(rawValue: statusRaw) ?? .scheduled }

    var lineup: [LineupEntry] {
        (try? JSONDecoder().decode([LineupEntry].self, from: lineupJSON)) ?? []
    }

    var artistNames: String {
        let names = lineup.map(\.name)
        return names.isEmpty ? title : names.joined(separator: " / ")
    }

    var headlineText: String { lineup.isEmpty ? title : artistNames }

    var ticketURL: URL? { ticketUrl.flatMap(URL.init(string:)) }
    var coverURL: URL? { coverImageUrl.flatMap(URL.init(string:)) }

    /// 「¥6,500」或「¥6,500 / 当日 ¥7,000」。
    var priceText: String {
        func yen(_ v: Int) -> String { "¥" + v.formatted(.number.grouping(.automatic)) }
        switch (priceAdvance, priceDoor) {
        case let (a?, d?) where a != d: return "前売 \(yen(a)) / 当日 \(yen(d))"
        case let (a?, _): return yen(a)
        case let (nil, d?): return "当日 \(yen(d))"
        default: return "票价未定"
        }
    }

    var effectiveEndAt: Date { endAt ?? startAt.addingTimeInterval(ScheduleItem.assumedDuration) }
}

/// lineup 里的一条，和后端 §2.3 的精简 Artist 对齐。
nonisolated struct LineupEntry: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var nameCn: String?
    var nameLatin: String?
    var type: String?
    var imageUrl: String?
    var isHeadliner: Bool
    var billingOrder: Int
}

nonisolated enum LiveStatus: String, Codable, Sendable {
    case scheduled = "SCHEDULED"
    case postponed = "POSTPONED"
    case cancelled = "CANCELLED"
    case soldOut = "SOLD_OUT"

    var banner: String? {
        switch self {
        case .scheduled: return nil
        case .postponed: return "本场演出已延期，请以官方公告为准"
        case .cancelled: return "本场演出已中止"
        case .soldOut: return "本场演出票已售罄"
        }
    }
}
