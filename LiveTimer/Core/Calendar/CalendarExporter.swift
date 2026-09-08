import Foundation
import EventKit

/// 导出到 Apple 日历。只申请仅写入权限，所以是单向、一次性的动作：
/// 之后在本 App 修改不会同步，需要重新导出（v1 的明确取舍，见 iOS 文档 §6.1）。
enum CalendarExporter {

    enum ExportError: LocalizedError {
        case accessDenied
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied: return "没有日历写入权限，请在「设置」里允许后再试。"
            case .saveFailed(let message): return "保存到日历失败：\(message)"
            }
        }
    }

    /// 返回本次新导出的数量；已经导出过（有 ekEventIdentifier）的条目跳过。
    @MainActor
    static func export(_ items: [ScheduleItem]) async throws -> Int {
        let store = EKEventStore()
        guard try await store.requestWriteOnlyAccessToEvents() else { throw ExportError.accessDenied }

        var saved = 0
        for item in items where item.ekEventIdentifier == nil {
            let event = EKEvent(eventStore: store)
            event.title = item.title
            event.startDate = item.startAt
            event.endDate = item.effectiveEndAt
            event.isAllDay = item.isAllDayBand
            if let name = item.locationName {
                event.location = [name, item.locationAddress].compactMap { $0 }.joined(separator: "\n")
                if let lat = item.latitude, let lng = item.longitude {
                    let structured = EKStructuredLocation(title: name)
                    structured.geoLocation = CLLocation(latitude: lat, longitude: lng)
                    event.structuredLocation = structured
                }
            }
            event.notes = [item.subtitle, item.note, item.externalUrl.map { "购票：\($0)" }]
                .compactMap { $0 }.joined(separator: "\n")
            event.url = item.externalUrl.flatMap(URL.init(string:))
            event.addAlarm(EKAlarm(relativeOffset: -3600))
            event.calendar = store.defaultCalendarForNewEvents
            do {
                try store.save(event, span: .thisEvent, commit: false)
                item.ekEventIdentifier = event.eventIdentifier
                saved += 1
            } catch {
                throw ExportError.saveFailed(error.localizedDescription)
            }
        }
        do { try store.commit() } catch { throw ExportError.saveFailed(error.localizedDescription) }
        return saved
    }
}
