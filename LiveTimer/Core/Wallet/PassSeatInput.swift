import Foundation

/// 用户填的座位信息。字段和后端 PassSeat 一一对应。
///
/// 日本的演出分两种入场方式，卡面显示规则完全不同：
/// livehouse 多是站席 + 整理番号（按号码顺序入场），hall / arena 才是ブロック・列・番号对号入座。
/// 两种都支持，UI 上二选一。
nonisolated struct PassSeatInput: Codable, Equatable, Sendable {
    var section = ""
    var row = ""
    var number = ""
    var entryOrder = ""
    var type = ""

    var isEmpty: Bool {
        [section, row, number, entryOrder, type].allSatisfy { $0.trimmed.isEmpty }
    }

    /// 去掉首尾空白后再送给后端，避免「 A 」这种值写进卡片。
    var normalized: PassSeatInput {
        PassSeatInput(section: section.trimmed, row: row.trimmed, number: number.trimmed,
                      entryOrder: entryOrder.trimmed, type: type.trimmed)
    }

    /// 和后端 PassSeat.displayText() 保持一致，让填写页的预览就是卡面上的样子。
    var displayText: String {
        let s = normalized
        if !s.entryOrder.isEmpty {
            return s.section.isEmpty ? "整理番号 \(s.entryOrder)" : "整理番号 \(s.section)-\(s.entryOrder)"
        }
        var parts: [String] = []
        if !s.section.isEmpty { parts.append(s.section) }
        if !s.row.isEmpty { parts.append("\(s.row)列") }
        if !s.number.isEmpty { parts.append("\(s.number)番") }
        return parts.isEmpty ? s.type : parts.joined(separator: " ")
    }

    var displayLabel: String { normalized.entryOrder.isEmpty ? "座席" : "整理番号" }
}

/// 必须标 nonisolated：工程默认把成员推断成 MainActor 隔离，而 PassSeatInput 本身是 nonisolated 的，
/// 直接用会报跨 actor 引用。这里只是纯字符串处理，不碰任何共享状态。
private nonisolated extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
