import SwiftUI

/// 列表里用的小标签。圆角和字距收在一处，避免各页面各写一套。
struct TagLabel: View {
    let text: String
    var color: Color = Theme.C.textSecondary
    var filled: Bool = false
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text).font(Theme.F.tag)
        }
        .foregroundStyle(filled ? Theme.C.background : color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(filled ? color : color.opacity(0.14))
        }
    }
}

/// 冲突标记。按需求不用弹窗打断，只靠列表内的颜色和文字传达。
struct ConflictBadge: View {
    let message: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10, weight: .bold))
            Text("时间冲突").font(Theme.F.tag)
            Text(message)
                .font(Theme.F.tag)
                .foregroundStyle(Theme.C.accent.opacity(0.75))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.C.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.C.accent.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 7).stroke(Theme.C.accent.opacity(0.35), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("时间冲突。\(message)")
    }
}

/// 封面。有宣传图就异步加载，没有就铺类型色渐变 + 首字占位。
struct CoverThumbnail: View {
    let url: URL?
    let fallbackText: String
    var size: CGFloat = Theme.M.thumbSize
    var color: Color = Theme.C.kind(.live)

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(LinearGradient(colors: [color.opacity(0.55), color.opacity(0.12)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var placeholder: some View {
        Text(String(fallbackText.prefix(1)))
            .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.C.textPrimary.opacity(0.85))
    }
}
