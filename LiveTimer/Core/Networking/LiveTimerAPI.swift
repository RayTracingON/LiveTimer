import Foundation
import CoreLocation

/// 自有后端。接口规格见《LiveTimer-Backend-API文档》。
nonisolated struct LiveTimerAPI: Sendable {
    static let production = LiveTimerAPI(
        baseURL: URL(string: "https://livetimer-gjcheughcncugpe8.newzealandnorth-01.azurewebsites.net")!)

    let baseURL: URL
    var client: APIClient = .shared

    // MARK: - DTO（和后端 JSON 一一对应；墓碑记录只有 id/updatedAt/deleted，所以大多数字段可选）

    nonisolated struct Page<T: Decodable & Sendable>: Decodable, Sendable {
        let items: [T]
        let total: Int
        let limit: Int
        let offset: Int
    }

    nonisolated struct VenueSummary: Decodable, Sendable {
        let id: String
        let name: String
        let address: String
        let lat: Double
        let lng: Double
        let nearestStation: String?
    }

    nonisolated struct ArtistSummary: Decodable, Sendable {
        let id: String
        let name: String
        let nameCn: String?
        let nameLatin: String?
        let type: String?
        let imageUrl: String?
    }

    nonisolated struct LineupItem: Decodable, Sendable {
        let artist: ArtistSummary
        let isHeadliner: Bool
        let billingOrder: Int
    }

    nonisolated struct Live: Decodable, Sendable {
        let id: String
        let title: String?
        let subtitle: String?
        let venueId: String?
        let venue: VenueSummary?
        let lineup: [LineupItem]?
        let openAt: Date?
        let startAt: Date?
        let endAt: Date?
        let priceAdvance: Int?
        let priceDoor: Int?
        let currency: String?
        let hasDrinkFee: Bool?
        let drinkFee: Int?
        let ticketUrl: String?
        let ticketVendor: String?
        let coverImageUrl: String?
        let description: String?
        let status: String?
        let tags: [String]?
        let updatedAt: Date
        let deleted: Bool?

        var isTombstone: Bool { deleted == true }
    }

    nonisolated struct Venue: Decodable, Sendable {
        let id: String
        let name: String?
        let address: String?
        let prefecture: String?
        let lat: Double?
        let lng: Double?
        let nearestStation: String?
        let upcomingLiveCount: Int?
        let nextLiveAt: Date?
        let updatedAt: Date
        let deleted: Bool?

        var isTombstone: Bool { deleted == true }
    }

    nonisolated struct Config: Decodable, Sendable {
        let minimumAppVersion: String
        let features: [String: Bool]
        let disclaimers: [String: String]
        let anitabi: Anitabi?

        nonisolated struct Anitabi: Decodable, Sendable {
            let apiBase: String
            let imageBase: String
        }
    }

    nonisolated struct IpCatalogEntry: Decodable, Sendable {
        let bangumiSubjectId: Int
        let titleOriginal: String?
        let titleCn: String?
        let coverUrl: String?
        let primaryCity: String?
        let prefecture: String?
        let themeColor: String?
        let defaultGeo: [Double]?
        let defaultZoom: Double?
        let pointCount: Int?
        let isActive: Bool?
        let sortOrder: Int?
        let updatedAt: Date
        let deleted: Bool?
    }

    // MARK: - 接口

    func config() async throws -> Config {
        try await client.get(url("/api/v1/meta/config"))
    }

    func lives(from: Date? = nil, to: Date? = nil, updatedSince: Date? = nil, bbox: Bbox? = nil,
               venueId: String? = nil, keyword: String? = nil, limit: Int = 200, offset: Int = 0)
        async throws -> Page<Live> {
        var q: [URLQueryItem] = [.init(name: "limit", value: String(limit)), .init(name: "offset", value: String(offset))]
        if let from { q.append(.init(name: "from", value: DateOnly.string(from))) }
        if let to { q.append(.init(name: "to", value: DateOnly.string(to))) }
        if let updatedSince { q.append(.init(name: "updatedSince", value: ISO8601DateFormatter.internet.string(from: updatedSince))) }
        if let bbox { q.append(.init(name: "bbox", value: bbox.queryValue)) }
        if let venueId { q.append(.init(name: "venueId", value: venueId)) }
        if let keyword, !keyword.isEmpty { q.append(.init(name: "keyword", value: keyword)) }
        return try await client.get(url("/api/v1/lives", q))
    }

    func live(id: String) async throws -> Live {
        try await client.get(url("/api/v1/lives/\(id)"))
    }

    func venues(bbox: Bbox? = nil, hasUpcomingLives: Bool = true, from: Date? = nil, to: Date? = nil,
                updatedSince: Date? = nil, limit: Int = 200, offset: Int = 0) async throws -> Page<Venue> {
        var q: [URLQueryItem] = [.init(name: "limit", value: String(limit)), .init(name: "offset", value: String(offset)),
                                 .init(name: "hasUpcomingLives", value: hasUpcomingLives ? "true" : "false")]
        if let bbox { q.append(.init(name: "bbox", value: bbox.queryValue)) }
        if let from { q.append(.init(name: "from", value: DateOnly.string(from))) }
        if let to { q.append(.init(name: "to", value: DateOnly.string(to))) }
        if let updatedSince { q.append(.init(name: "updatedSince", value: ISO8601DateFormatter.internet.string(from: updatedSince))) }
        return try await client.get(url("/api/v1/venues", q))
    }

    func venueLives(venueId: String, from: Date? = nil, to: Date? = nil) async throws -> Page<Live> {
        var q: [URLQueryItem] = [.init(name: "limit", value: "100")]
        if let from { q.append(.init(name: "from", value: DateOnly.string(from))) }
        if let to { q.append(.init(name: "to", value: DateOnly.string(to))) }
        return try await client.get(url("/api/v1/venues/\(venueId)/lives", q))
    }

    /// 图层 B：后端代理的 Google Places。
    func hotels(bbox: Bbox, keyword: String? = nil, limit: Int = 20) async throws -> HotelPage {
        var q: [URLQueryItem] = [.init(name: "bbox", value: bbox.queryValue), .init(name: "limit", value: String(limit))]
        if let keyword, !keyword.isEmpty { q.append(.init(name: "keyword", value: keyword)) }
        return try await client.get(url("/api/v1/hotels", q))
    }

    func ipCatalog() async throws -> [IpCatalogEntry] {
        try await client.get(url("/api/v1/ip-catalog"))
    }

    func passData(liveId: String) async throws -> Data {
        try await client.postData(url("/api/v1/passes"), body: ["liveId": liveId])
    }

    private func url(_ path: String, _ query: [URLQueryItem] = []) -> URL {
        var comps = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        return comps.url!
    }
}

/// 地图视野过滤：minLng,minLat,maxLng,maxLat。后端对面积有上限（4 平方度），超过会拒绝。
nonisolated struct Bbox: Sendable, Equatable {
    var minLng: Double, minLat: Double, maxLng: Double, maxLat: Double

    var queryValue: String {
        [minLng, minLat, maxLng, maxLat].map { String(format: "%.5f", $0) }.joined(separator: ",")
    }

    var areaDeg2: Double { (maxLng - minLng) * (maxLat - minLat) }
    static let backendMaxAreaDeg2 = 4.0
    var isTooLargeForBackend: Bool { areaDeg2 > Self.backendMaxAreaDeg2 }
}

/// 后端的 from/to 按 JST 日历日解释，这里也固定用东京时区拼日期。
nonisolated enum DateOnly {
    static let jst = TimeZone(identifier: "Asia/Tokyo")!

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = jst
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
}
