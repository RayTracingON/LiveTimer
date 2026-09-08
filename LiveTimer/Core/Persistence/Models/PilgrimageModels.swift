import Foundation
import SwiftData

/// 用户订阅的作品（P2 巡礼功能用，表结构先建好，避免以后迁移）。
@Model
final class SubscribedIP {
    @Attribute(.unique) var bangumiSubjectId: Int
    var titleOriginal: String
    var titleCn: String?
    var coverUrl: String?
    var themeColorHex: String?
    var defaultLatitude: Double
    var defaultLongitude: Double
    var pointCount: Int
    var subscribedAt: Date
    /// anitabi /lite 的 modified，作为缓存失效判据。
    var anitabiModified: Int?
    var pointsFetchedAt: Date?

    init(bangumiSubjectId: Int, titleOriginal: String, titleCn: String?, coverUrl: String?, themeColorHex: String?,
         defaultLatitude: Double, defaultLongitude: Double, pointCount: Int) {
        self.bangumiSubjectId = bangumiSubjectId
        self.titleOriginal = titleOriginal
        self.titleCn = titleCn
        self.coverUrl = coverUrl
        self.themeColorHex = themeColorHex
        self.defaultLatitude = defaultLatitude
        self.defaultLongitude = defaultLongitude
        self.pointCount = pointCount
        self.subscribedAt = Date()
    }
}

@Model
final class CachedPilgrimagePoint {
    @Attribute(.unique) var id: String
    var subjectId: Int
    var name: String
    var nameCn: String?
    /// 不含 plan 参数的 base，用时再拼 ?plan=h160 / h360。
    var imageUrl: String?
    /// 集数原文（"3" / "OP" / "劇場版"）。anitabi 这个字段不保证是数字，所以按文本存。
    var episodeLabel: String?
    var seconds: Int?
    var latitude: Double
    var longitude: Double
    /// 署名，必填展示（CC BY 要求）。
    var origin: String?
    /// 来源跳转，必填实现。
    var originURL: String?

    init(id: String, subjectId: Int, name: String, nameCn: String?, imageUrl: String?, episodeLabel: String?, seconds: Int?,
         latitude: Double, longitude: Double, origin: String?, originURL: String?) {
        self.id = id
        self.subjectId = subjectId
        self.name = name
        self.nameCn = nameCn
        self.imageUrl = imageUrl
        self.episodeLabel = episodeLabel
        self.seconds = seconds
        self.latitude = latitude
        self.longitude = longitude
        self.origin = origin
        self.originURL = originURL
    }

    var thumbnailURL: URL? { AnitabiAPI.thumbnail(imageUrl) }
    var largeImageURL: URL? { AnitabiAPI.large(imageUrl) }

    /// 「第 3 話 12:34」。集数不是纯数字时（OP、劇場版）直接用原文。
    var episodeText: String? {
        guard let episodeLabel else { return nil }
        let ep = Int(episodeLabel).map { "第 \($0) 話" } ?? episodeLabel
        guard let seconds else { return ep }
        return String(format: "%@ %02d:%02d", ep, seconds / 60, seconds % 60)
    }
}

@Model
final class WalletPassRecord {
    @Attribute(.unique) var serialNumber: String
    var liveId: String
    var addedAt: Date

    init(serialNumber: String, liveId: String) {
        self.serialNumber = serialNumber
        self.liveId = liveId
        self.addedAt = Date()
    }
}
