import Foundation

extension Calendar {
    /// 全部业务时间按 JST 处理（后端规格 §1.2）。周日历分列、按日分组、日期行都用它，不随设备时区变。
    static let jst: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = DateOnly.jst
        c.locale = Locale(identifier: "zh_CN")
        c.firstWeekday = 2
        return c
    }()
}

enum Fmt {
    /// 「9月10日 周四」。用于分组标题。
    static let sectionDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = DateOnly.jst
        f.dateFormat = "M月d日 E"
        return f
    }()

    /// 「一」「二」…周日历日期行用。
    static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = DateOnly.jst
        f.dateFormat = "EEEEE"
        return f
    }()

    /// 「18:30」。
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = DateOnly.jst
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 「2026/09/10 周四」。详情页用的完整写法。
    static let fullDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = DateOnly.jst
        f.dateFormat = "yyyy/MM/dd E"
        return f
    }()

    /// 分组标题优先显示「今天 / 明天」，掌握本周安排的速度差很多。
    static func dayLabel(for day: Date, calendar: Calendar = .jst) -> String {
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInTomorrow(day) { return "明天" }
        return sectionDay.string(from: day)
    }

    static func daySubLabel(for day: Date, calendar: Calendar = .jst) -> String? {
        guard calendar.isDateInToday(day) || calendar.isDateInTomorrow(day) else { return nil }
        return sectionDay.string(from: day)
    }

    /// 距开演还有多久。也用来判断要不要打「即将开演」的标。
    static func countdown(to date: Date, from now: Date = Date()) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0, seconds < 6 * 60 * 60 else { return nil }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "距开演 \(hours)小时\(minutes)分" : "距开演 \(minutes)分钟"
    }
}
