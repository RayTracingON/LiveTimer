import SwiftUI

/// 列表视图：按日期分组。是周视图的无障碍降级方案，也用于「+N」展开。
struct DayListView: View {
    let items: [ScheduleItem]
    let anchorDay: Date?
    let onSelect: (ScheduleItem) -> Void

    private let calendar = Calendar.jst

    private var groups: [(day: Date, items: [ScheduleItem])] {
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.startAt) }
        return grouped.keys.sorted().map { (day: $0, items: grouped[$0]!.sorted { $0.startAt < $1.startAt }) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.day) { group in
                        Section {
                            VStack(spacing: Theme.M.rowSpacing) {
                                ForEach(group.items) { item in
                                    ScheduleItemRow(item: item)
                                        .onTapGesture { onSelect(item) }
                                }
                            }
                            .padding(.horizontal, Theme.M.screenPadding)
                        } header: {
                            DaySectionHeader(day: group.day, count: group.items.count)
                        }
                        .id(group.day)
                    }
                }
                .padding(.bottom, 24)
            }
            .onAppear {
                if let anchorDay, let target = groups.first(where: { calendar.isDate($0.day, inSameDayAs: anchorDay) }) {
                    proxy.scrollTo(target.day, anchor: .top)
                }
            }
        }
    }
}

struct DaySectionHeader: View {
    let day: Date
    let count: Int

    private var isToday: Bool { Calendar.jst.isDateInToday(day) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Fmt.dayLabel(for: day))
                .font(Theme.F.sectionTitle)
                .foregroundStyle(isToday ? Theme.C.accent : Theme.C.textPrimary)
            if let sub = Fmt.daySubLabel(for: day) {
                Text(sub).font(Theme.F.caption).foregroundStyle(Theme.C.textTertiary)
            }
            Spacer()
            Text("\(count) 项").font(Theme.F.caption).foregroundStyle(Theme.C.textTertiary)
        }
        .padding(.horizontal, Theme.M.screenPadding)
        .padding(.vertical, 8)
        .background(Theme.C.background)
    }
}

struct ScheduleItemRow: View {
    let item: ScheduleItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(item.isAllDayBand ? "全天" : Fmt.time.string(from: item.startAt))
                    .font(Theme.F.time).foregroundStyle(Theme.C.textPrimary)
                if let end = item.endAt, !item.isAllDayBand {
                    Text(Fmt.time.string(from: end)).font(Theme.F.tag).foregroundStyle(Theme.C.textTertiary)
                }
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TagLabel(text: item.kind.label, color: Theme.C.kind(item.kind), filled: true)
                    if item.isSourceInvalid {
                        TagLabel(text: "演出信息已失效", color: Theme.C.warning)
                    }
                }
                Text(item.title).font(Theme.F.cardTitle).foregroundStyle(Theme.C.textPrimary).lineLimit(2)
                if let sub = item.subtitle { Text(sub).font(Theme.F.body).foregroundStyle(Theme.C.textSecondary).lineLimit(1) }
                if let loc = item.locationName {
                    Label(loc, systemImage: "mappin.and.ellipse").font(Theme.F.caption).foregroundStyle(Theme.C.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.M.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: Theme.M.cardRadius)
                .fill(Theme.C.surface)
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(topLeadingRadius: Theme.M.cardRadius, bottomLeadingRadius: Theme.M.cardRadius)
                        .fill(Theme.C.kind(item.kind)).frame(width: 3)
                }
        }
        .contentShape(Rectangle())
    }
}
