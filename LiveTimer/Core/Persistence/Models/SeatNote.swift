import Foundation
import SwiftData

/// 用户为某场演出填的座位，按 liveId 存一条。
///
/// 后端也会把座位存在卡片上，这里再存一份是为了：填写页能回填上次填的内容，
/// 以及卡片被用户从钱包里删掉后重新签发时不用再问一遍。
@Model
final class SeatNote {
    @Attribute(.unique) var liveId: String
    var section: String
    var row: String
    var number: String
    var entryOrder: String
    var type: String
    var updatedAt: Date

    init(liveId: String, seat: PassSeatInput) {
        self.liveId = liveId
        section = seat.section
        row = seat.row
        number = seat.number
        entryOrder = seat.entryOrder
        type = seat.type
        updatedAt = Date()
    }

    var seat: PassSeatInput {
        PassSeatInput(section: section, row: row, number: number, entryOrder: entryOrder, type: type)
    }

    func apply(_ seat: PassSeatInput) {
        section = seat.section
        row = seat.row
        number = seat.number
        entryOrder = seat.entryOrder
        type = seat.type
        updatedAt = Date()
    }

    static func find(liveId: String, in context: ModelContext) -> SeatNote? {
        try? context.fetch(FetchDescriptor<SeatNote>(predicate: #Predicate { $0.liveId == liveId })).first
    }

    /// 空座位不留空记录，直接删掉。
    static func save(_ seat: PassSeatInput, liveId: String, in context: ModelContext) {
        let existing = find(liveId: liveId, in: context)
        if seat.isEmpty {
            if let existing { context.delete(existing) }
        } else if let existing {
            existing.apply(seat)
        } else {
            context.insert(SeatNote(liveId: liveId, seat: seat))
        }
        try? context.save()
    }
}
