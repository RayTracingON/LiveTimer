import SwiftUI
import SwiftData

/// 「发现」：缓存里的演出按日期分组，本地搜索，下拉刷新走同步。
struct LivesListView: View {
    @Environment(\.modelContext) private var context
    @Environment(LiveCatalogSync.self) private var sync
    @Query(sort: \CachedLive.startAt) private var lives: [CachedLive]
    @Binding var toast: ToastMessage?

    @State private var query = ""
    /// 调试用：`-debugOpenFirstLive YES` 启动即进入第一场演出的详情页（模拟器没有点击命令）。
    @State private var debugPath: [String] = []

    private var upcoming: [CachedLive] {
        let now = Date()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return lives.filter { live in
            guard live.effectiveEndAt >= now else { return false }
            guard !q.isEmpty else { return true }
            let hay = ([live.title, live.subtitle ?? "", live.venueName] + live.lineup.flatMap { [$0.name, $0.nameCn ?? "", $0.nameLatin ?? ""] })
                .joined(separator: " ").lowercased()
            return hay.contains(q)
        }
    }

    private var groups: [(day: Date, lives: [CachedLive])] {
        let cal = Calendar.jst
        let grouped = Dictionary(grouping: upcoming) { cal.startOfDay(for: $0.startAt) }
        return grouped.keys.sorted().map { (day: $0, lives: grouped[$0]!) }
    }

    var body: some View {
        NavigationStack(path: $debugPath) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                    if let error = sync.lastError, sync.isOffline {
                        Text("离线：\(error)")
                            .font(Theme.F.caption).foregroundStyle(Theme.C.warning)
                            .padding(.horizontal, Theme.M.screenPadding)
                    }
                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups, id: \.day) { group in
                            Section {
                                VStack(spacing: Theme.M.rowSpacing) {
                                    ForEach(group.lives) { live in
                                        NavigationLink(value: live.id) {
                                            LiveRowCard(live: live, isScheduled: ScheduleStore.existingItem(forLive: live.id, in: context) != nil)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, Theme.M.screenPadding)
                            } header: {
                                DaySectionHeader(day: group.day, count: group.lives.count)
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Theme.C.background)
            .refreshable { await sync.sync(context: context, force: true) }
            .searchable(text: $query, prompt: "艺人 / 演出 / 场馆")
            .navigationTitle("发现演出")
            .navigationDestination(for: String.self) { id in
                if let live = lives.first(where: { $0.id == id }) {
                    LiveDetailView(live: live, toast: $toast)
                }
            }
            .task(id: upcoming.first?.id) {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "debugOpenFirstLive"), debugPath.isEmpty,
                   let first = upcoming.first {
                    debugPath = [first.id]
                }
                #endif
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            EmptyStateView(icon: "magnifyingglass", title: "没有符合条件的演出", message: "换个关键词试试。")
        } else if sync.isSyncing {
            VStack(spacing: 12) { ProgressView(); Text("正在拉取演出…").font(Theme.F.body).foregroundStyle(Theme.C.textSecondary) }
                .frame(maxWidth: .infinity).padding(.vertical, 48)
        } else {
            EmptyStateView(icon: "music.note.list", title: "暂时没有演出", message: "下拉刷新，或稍后再来。",
                           actionTitle: "刷新", action: { Task { await sync.sync(context: context, force: true) } })
        }
    }
}

/// 信息流单元。视线按「开演时间 → 艺人 → 演出名 → 场馆 · 票价」往下落。
struct LiveRowCard: View {
    let live: CachedLive
    var isScheduled: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverThumbnail(url: live.coverURL, fallbackText: live.headlineText)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(Fmt.time.string(from: live.startAt)).font(Theme.F.timeLarge).foregroundStyle(Theme.C.textPrimary)
                    Text("開演").font(Theme.F.caption).foregroundStyle(Theme.C.textTertiary)
                    if let countdown = Fmt.countdown(to: live.startAt) {
                        TagLabel(text: countdown, color: Theme.C.accent, filled: true)
                    }
                    if live.status != .scheduled {
                        TagLabel(text: statusLabel, color: Theme.C.status(live.status), filled: true)
                    }
                }
                Text(live.headlineText).font(Theme.F.cardTitle).foregroundStyle(Theme.C.textPrimary).lineLimit(2)
                if !live.lineup.isEmpty {
                    Text(live.title).font(Theme.F.body).foregroundStyle(Theme.C.textSecondary).lineLimit(1)
                }
                HStack(spacing: 5) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 10))
                    Text(live.venueName).lineLimit(1)
                    Text("·").foregroundStyle(Theme.C.textTertiary)
                    Text(live.priceText).font(Theme.F.price)
                }
                .font(Theme.F.caption).foregroundStyle(Theme.C.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)

            if isScheduled {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.C.accentAlt)
                    .accessibilityLabel("已在日程中")
            }
        }
        .padding(Theme.M.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: Theme.M.cardRadius)
                .fill(Theme.C.surface)
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(topLeadingRadius: Theme.M.cardRadius, bottomLeadingRadius: Theme.M.cardRadius)
                        .fill(Theme.C.kind(.live)).frame(width: 3)
                }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: String {
        switch live.status {
        case .scheduled: return ""
        case .postponed: return "延期"
        case .cancelled: return "中止"
        case .soldOut: return "售罄"
        }
    }
}
