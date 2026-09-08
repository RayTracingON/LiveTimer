import Foundation
import SwiftData

nonisolated enum ScheduleItemKind: String, Codable, CaseIterable, Sendable {
    case live, hotel, pilgrimage, custom

    var label: String {
        switch self {
        case .live: return "演出"
        case .hotel: return "酒店"
        case .pilgrimage: return "巡礼"
        case .custom: return "自定义"
        }
    }

    var systemImage: String {
        switch self {
        case .live: return "music.mic"
        case .hotel: return "bed.double.fill"
        case .pilgrimage: return "camera.viewfinder"
        case .custom: return "pin.fill"
        }
    }
}

/// 核心表：Live / 酒店 / 巡礼点 / 自定义四类内容归一到一张表，靠 kind + sourceRef 区分。
/// 周日历渲染、冲突检测、日历导出、通知调度只针对这张表写一遍逻辑。
@Model
final class ScheduleItem {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var subtitle: String?
    var startAt: Date
    var endAt: Date?
    /// true = 渲染在顶部横条而非时间网格。酒店恒为 true，否则跨夜的住宿会把周视图整个占满。
    var isAllDayBand: Bool
    var note: String?

    // 地点
    var locationName: String?
    var locationAddress: String?
    var latitude: Double?
    var longitude: Double?

    // 溯源
    var sourceRef: String?
    var sourceSubjectId: Int?
    var externalUrl: String?
    /// 后端下发墓碑后置 true：条目保留，UI 提示「演出信息已失效」。
    var isSourceInvalid: Bool

    // 系统集成回写
    var ekEventIdentifier: String?
    var passSerialNumber: String?
    var notificationIds: [String]

    var createdAt: Date
    var updatedAt: Date

    init(kind: ScheduleItemKind, title: String, subtitle: String? = nil, startAt: Date, endAt: Date? = nil,
         isAllDayBand: Bool = false, note: String? = nil, locationName: String? = nil,
         locationAddress: String? = nil, latitude: Double? = nil, longitude: Double? = nil,
         sourceRef: String? = nil, sourceSubjectId: Int? = nil, externalUrl: String? = nil) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.title = title
        self.subtitle = subtitle
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDayBand = isAllDayBand
        self.note = note
        self.locationName = locationName
        self.locationAddress = locationAddress
        self.latitude = latitude
        self.longitude = longitude
        self.sourceRef = sourceRef
        self.sourceSubjectId = sourceSubjectId
        self.externalUrl = externalUrl
        self.isSourceInvalid = false
        self.notificationIds = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var kind: ScheduleItemKind {
        get { ScheduleItemKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    /// 未公布结束时间时按 2 小时估。冲突判定和日历导出共用这一处。
    static let assumedDuration: TimeInterval = 2 * 60 * 60

    var effectiveEndAt: Date {
        max(endAt ?? startAt.addingTimeInterval(Self.assumedDuration), startAt.addingTimeInterval(15 * 60))
    }

    var interval: DateInterval { DateInterval(start: startAt, end: effectiveEndAt) }
}
