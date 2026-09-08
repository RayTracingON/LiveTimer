import Foundation

/// 周视图的重叠布局算法（iOS 文档 §5.1）。纯函数，方便单测。
enum WeekLayout {

    struct Placed: Identifiable {
        let id: UUID
        let item: ScheduleItem
        /// 在同一组内的列索引 / 列数。
        let column: Int
        let columnCount: Int
        /// 同组内是否和其它 Live 重叠（真冲突）。
        let hasLiveConflict: Bool
        /// 一组内超过 3 列时，第 3 列及之后折叠成「+N」；这里给出被折叠的数量（只在 column == 2 的元素上非 0）。
        let collapsedCount: Int
    }

    static let maxVisibleColumns = 3

    /// 输入某一天的非全天事件，输出每个事件的列位置。
    static func layout(_ items: [ScheduleItem]) -> [Placed] {
        let sorted = items.filter { !$0.isAllDayBand }.sorted {
            $0.startAt == $1.startAt ? $0.effectiveEndAt > $1.effectiveEndAt : $0.startAt < $1.startAt
        }
        var result: [Placed] = []
        var group: [ScheduleItem] = []
        var groupMaxEnd = Date.distantPast

        func flush() {
            guard !group.isEmpty else { return }
            result.append(contentsOf: placeGroup(group))
            group.removeAll()
            groupMaxEnd = .distantPast
        }

        for item in sorted {
            if !group.isEmpty, item.startAt >= groupMaxEnd { flush() }
            group.append(item)
            groupMaxEnd = max(groupMaxEnd, item.effectiveEndAt)
        }
        flush()
        return result
    }

    /// 组内贪心分列：每个事件放进第一个「最后一个事件已结束」的列。
    private static func placeGroup(_ group: [ScheduleItem]) -> [Placed] {
        var columnEnds: [Date] = []
        var assignment: [(ScheduleItem, Int)] = []
        for item in group {
            if let col = columnEnds.firstIndex(where: { $0 <= item.startAt }) {
                columnEnds[col] = item.effectiveEndAt
                assignment.append((item, col))
            } else {
                columnEnds.append(item.effectiveEndAt)
                assignment.append((item, columnEnds.count - 1))
            }
        }
        let total = columnEnds.count
        let visible = min(total, maxVisibleColumns)
        let overflow = assignment.filter { $0.1 >= maxVisibleColumns - 1 }.count
        let lives = group.filter { $0.kind == .live }

        return assignment.compactMap { item, col in
            if total > maxVisibleColumns, col >= maxVisibleColumns - 1 {
                // 只保留第 3 列的第一个作为「+N」占位，其余不渲染。
                guard assignment.first(where: { $0.1 >= maxVisibleColumns - 1 })?.0.id == item.id else { return nil }
                return Placed(id: item.id, item: item, column: maxVisibleColumns - 1, columnCount: visible,
                              hasLiveConflict: false, collapsedCount: overflow)
            }
            let conflict = item.kind == .live && lives.contains { $0.id != item.id && $0.interval.intersects(item.interval) }
            return Placed(id: item.id, item: item, column: col, columnCount: visible,
                          hasLiveConflict: conflict, collapsedCount: 0)
        }
    }
}
