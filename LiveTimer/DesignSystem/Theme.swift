import SwiftUI

/// 带 livehouse 舞台感的暗色主题。
/// 为了长时间浏览列表不刺眼，背景不用纯黑而是略带蓝调；
/// 强调色只压在「今天」「时间冲突」这类有意义的位置上，不铺大面积。
enum Theme {

    // MARK: - 配色

    enum C {
        /// 全局背景。纯黑(#000)对比过强，稍微抬一点。
        static let background = Color(hex: 0x0E0E12)
        /// 卡片、列表单元的表面。
        static let surface = Color(hex: 0x17171F)
        /// 弹层、选中态等需要再抬一层的表面。
        static let surfaceRaised = Color(hex: 0x22222E)
        /// 分割线。
        static let separator = Color(hex: 0x2C2C3A)

        /// 主强调色。霓虹灯感的洋红。
        static let accent = Color(hex: 0xFF2D6F)
        /// 副强调色。用在「已加入日程」这类肯定状态上。
        static let accentAlt = Color(hex: 0x00E5C3)
        /// 时间冲突等警告。
        static let warning = Color(hex: 0xFFB020)
        /// 赶场紧张等提醒。
        static let caution = Color(hex: 0xFF7A45)

        static let textPrimary = Color(hex: 0xF2F2F7)
        static let textSecondary = Color(hex: 0x9A9AAB)
        static let textTertiary = Color(hex: 0x6B6B7B)

        /// 四类日程条目各有识别色（周日历色块、列表左侧细条都用它）。
        static func kind(_ kind: ScheduleItemKind) -> Color {
            switch kind {
            case .live: return Color(hex: 0xFF2D6F)
            case .hotel: return Color(hex: 0x3B9EFF)
            case .pilgrimage: return Color(hex: 0x00E5C3)
            case .custom: return Color(hex: 0x8B5CF6)
            }
        }

        /// 演出状态横幅色。
        static func status(_ status: LiveStatus) -> Color {
            switch status {
            case .scheduled: return accentAlt
            case .postponed: return warning
            case .cancelled: return accent
            case .soldOut: return caution
            }
        }
    }

    // MARK: - 字体

    /// 中日文混排交给系统字体处理(苹方 / Hiragino Sans)。
    /// 数字用等宽，保证开演时间和票价竖排时位数对齐。
    enum F {
        static let screenTitle = Font.system(size: 28, weight: .bold)
        static let sectionTitle = Font.system(size: 20, weight: .bold)
        static let cardTitle = Font.system(size: 16, weight: .semibold)
        static let body = Font.system(size: 14, weight: .regular)
        static let caption = Font.system(size: 12, weight: .medium)
        static let tag = Font.system(size: 11, weight: .semibold)

        static let timeLarge = Font.system(size: 22, weight: .bold, design: .rounded).monospacedDigit()
        static let time = Font.system(size: 14, weight: .semibold).monospacedDigit()
        static let price = Font.system(size: 13, weight: .medium).monospacedDigit()
    }

    // MARK: - 尺寸

    enum M {
        static let screenPadding: CGFloat = 16
        static let cardPadding: CGFloat = 12
        static let cardRadius: CGFloat = 14
        static let rowSpacing: CGFloat = 10
        static let thumbSize: CGFloat = 72
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
