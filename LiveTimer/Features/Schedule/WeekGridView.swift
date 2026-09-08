import SwiftUI

/// 一周的网格：固定的日期行 + 全天横条区 + 可滚动的时间网格。
struct WeekGridView: View {
    let weekStart: Date
    let items: [ScheduleItem]
    let onSelect: (ScheduleItem) -> Void
    let onLongPressEmpty: (Date) -> Void
    let onExpandDay: (Date) -> Void

    private let calendar = Calendar.jst
    private let hourHeight: CGFloat = 56
    private let gutter: CGFloat = 44

    private var days: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) } }

    private var allDayItems: [ScheduleItem] { items.filter(\.isAllDayBand) }

    var body: some View {
        VStack(spacing: 0) {
            dayHeader
            if !allDayItems.isEmpty {
                AllDayBand(days: days, items: allDayItems, gutter: gutter, onSelect: onSelect)
                Divider().overlay(Theme.C.separator)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    timeGrid
                        .frame(height: hourHeight * 24)
                        .padding(.bottom, 80)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { scrollToStart(proxy) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 日期行

    private var dayHeader: some View {
        HStack(spacing: 0) {
            // 不能用 Color.clear：它会纵向撑满，把整个 VStack 的高度分走一半。
            Spacer().frame(width: gutter)
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDateInToday(day)
                VStack(spacing: 2) {
                    Text(Fmt.weekdayShort.string(from: day))
                        .font(Theme.F.tag)
                        .foregroundStyle(isToday ? Theme.C.accent : Theme.C.textTertiary)
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(size: 16, weight: isToday ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(isToday ? Theme.C.background : Theme.C.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(isToday ? Theme.C.accent : .clear))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .background(Theme.C.background)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.C.separator) }
    }

    // MARK: - 时间网格

    private var timeGrid: some View {
        GeometryReader { geo in
            let columnWidth = (geo.size.width - gutter) / 7
            ZStack(alignment: .topLeading) {
                hourLines
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    dayColumn(day: day, x: gutter + CGFloat(index) * columnWidth, width: columnWidth)
                }
                if let y = nowLineY() {
                    nowLine(y: y)
                }
            }
        }
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%02d", hour))
                        .font(Theme.F.tag.monospacedDigit())
                        .foregroundStyle(Theme.C.textTertiary)
                        .frame(width: gutter - 8, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle().fill(Theme.C.separator).frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id("hour-\(hour)")
            }
        }
    }

    private func dayColumn(day: Date, x: CGFloat, width: CGFloat) -> some View {
        let dayItems = items.filter { !$0.isAllDayBand && calendar.isDate($0.startAt, inSameDayAs: day) }
        let placed = WeekLayout.layout(dayItems)
        let isToday = calendar.isDateInToday(day)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(isToday ? Theme.C.accent.opacity(0.06) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { }
                .onLongPressGesture(minimumDuration: 0.4) { }
                .overlay {
                    // 长按空白新建自定义事件：用带位置的手势拿到时间。
                    LongPressLocator { point in
                        let hour = Double(point.y / hourHeight)
                        let snapped = (hour * 2).rounded() / 2
                        let date = calendar.date(byAdding: .minute, value: Int(snapped * 60), to: calendar.startOfDay(for: day)) ?? day
                        onLongPressEmpty(date)
                    }
                }

            ForEach(placed) { p in
                let colWidth = (width - 4) / CGFloat(p.columnCount)
                let top = yOffset(for: p.item.startAt, on: day)
                let bottom = yOffset(for: p.item.effectiveEndAt, on: day)
                let height = max(bottom - top, 22)
                if p.collapsedCount > 0 {
                    Button { onExpandDay(day) } label: {
                        Text("+\(p.collapsedCount)")
                            .font(Theme.F.tag)
                            .foregroundStyle(Theme.C.textPrimary)
                            .frame(width: colWidth - 2, height: height)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.C.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 2 + CGFloat(p.column) * colWidth, y: top)
                } else {
                    EventBlock(item: p.item, hasConflict: p.hasLiveConflict, height: height, width: colWidth - 2)
                        .frame(width: colWidth - 2, height: height)
                        .offset(x: 2 + CGFloat(p.column) * colWidth, y: top)
                        .onTapGesture { onSelect(p.item) }
                        .contextMenu {
                            Button("查看详情") { onSelect(p.item) }
                        }
                }
            }
        }
        .frame(width: width, height: hourHeight * 24, alignment: .topLeading)
        .offset(x: x)
    }

    private func nowLine(y: CGFloat) -> some View {
        HStack(spacing: 0) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            Rectangle().fill(Color.red).frame(height: 1.5)
        }
        .offset(x: gutter - 4, y: y - 3)
        .allowsHitTesting(false)
    }

    // MARK: - geometry

    private func yOffset(for date: Date, on day: Date) -> CGFloat {
        let startOfDay = calendar.startOfDay(for: day)
        let seconds = date.timeIntervalSince(startOfDay)
        let clamped = min(max(seconds, 0), 24 * 3600)
        return CGFloat(clamped / 3600) * hourHeight
    }

    private func nowLineY() -> CGFloat? {
        guard days.contains(where: { calendar.isDateInToday($0) }) else { return nil }
        return yOffset(for: Date(), on: Date())
    }

    /// 首次进入滚到当日第一个事件；没有就滚到 09:00。
    private func scrollToStart(_ proxy: ScrollViewProxy) {
        let today = days.first { calendar.isDateInToday($0) } ?? weekStart
        let first = items.filter { !$0.isAllDayBand && calendar.isDate($0.startAt, inSameDayAs: today) }
            .min { $0.startAt < $1.startAt }
        let hour = first.map { max(calendar.component(.hour, from: $0.startAt) - 1, 0) } ?? 9
        proxy.scrollTo("hour-\(hour)", anchor: .top)
    }
}

/// 全天横条区：酒店等跨夜条目横着铺，避免把时间网格整个占满。
struct AllDayBand: View {
    let days: [Date]
    let items: [ScheduleItem]
    let gutter: CGFloat
    let onSelect: (ScheduleItem) -> Void

    private let calendar = Calendar.jst

    var body: some View {
        GeometryReader { geo in
            let columnWidth = (geo.size.width - gutter) / 7
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items) { item in
                    let (startCol, span) = columns(for: item)
                    Text(item.title)
                        .font(Theme.F.tag)
                        .foregroundStyle(Theme.C.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(width: columnWidth * CGFloat(span) - 2, height: 20, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.C.kind(item.kind).opacity(0.75)))
                        .offset(x: gutter + CGFloat(startCol) * columnWidth + 1)
                        .onTapGesture { onSelect(item) }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: CGFloat(items.count) * 23 + 8)
    }

    private func columns(for item: ScheduleItem) -> (Int, Int) {
        guard let weekStart = days.first, let weekEnd = days.last.flatMap({ calendar.date(byAdding: .day, value: 1, to: $0) }) else {
            return (0, 1)
        }
        let start = max(item.startAt, weekStart)
        let end = min(item.effectiveEndAt, weekEnd)
        let startCol = calendar.dateComponents([.day], from: calendar.startOfDay(for: weekStart), to: calendar.startOfDay(for: start)).day ?? 0
        let endCol = calendar.dateComponents([.day], from: calendar.startOfDay(for: weekStart), to: calendar.startOfDay(for: end.addingTimeInterval(-1))).day ?? startCol
        return (max(0, startCol), max(1, endCol - startCol + 1))
    }
}

/// 时间网格里的色块。内容按高度降级：>44pt 标题+时间+地点；22–44pt 只标题；更矮只显示色块。
struct EventBlock: View {
    let item: ScheduleItem
    let hasConflict: Bool
    let height: CGFloat
    var width: CGFloat = 60

    /// 分列后一格只有二三十点宽，这时只放标题，图标挪到右上角。
    private var narrow: Bool { width < 44 }

    var body: some View {
        let color = Theme.C.kind(item.kind)
        RoundedRectangle(cornerRadius: 5)
            .fill(color.opacity(item.isSourceInvalid ? 0.35 : 0.85))
            .overlay {
                if hasConflict {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.C.warning, lineWidth: 2.5)
                }
            }
            .overlay(alignment: .topLeading) {
                if height >= 22 {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 2) {
                            if hasConflict && !narrow {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.C.warning)
                            }
                            Text(item.title)
                                .font(narrow ? .system(size: 9, weight: .semibold) : Theme.F.tag)
                                .lineLimit(height >= 44 ? (narrow ? 3 : 2) : 1)
                        }
                        if height > 44 && !narrow {
                            Text(Fmt.time.string(from: item.startAt)).font(.system(size: 9, weight: .medium).monospacedDigit())
                            if let loc = item.locationName, height > 60 {
                                Text(loc).font(.system(size: 9)).lineLimit(1)
                            }
                        }
                    }
                    .foregroundStyle(Theme.C.textPrimary)
                    .padding(narrow ? 2 : 3)
                    .padding(.top, narrow && hasConflict ? 10 : 0)
                }
            }
            .overlay(alignment: .topTrailing) {
                if hasConflict && narrow {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.C.warning).padding(2)
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }
}

/// 拿到长按位置的最小 UIKit 桥。SwiftUI 的 onLongPressGesture 不给坐标。
struct LongPressLocator: UIViewRepresentable {
    let onLongPress: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let gesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        gesture.minimumPressDuration = 0.45
        view.addGestureRecognizer(gesture)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onLongPress = onLongPress
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLongPress: onLongPress) }

    final class Coordinator: NSObject {
        var onLongPress: (CGPoint) -> Void
        init(onLongPress: @escaping (CGPoint) -> Void) { self.onLongPress = onLongPress }

        @objc func handle(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let view = g.view else { return }
            onLongPress(g.location(in: view))
        }
    }
}
