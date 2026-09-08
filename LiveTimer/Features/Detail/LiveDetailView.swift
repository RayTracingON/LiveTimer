import SwiftUI
import SwiftData
import MapKit

/// 演出详情。以远征为前提，按「什么时候 · 在哪 · 多少钱 · 怎么去」自上而下排。
struct LiveDetailView: View {
    let live: CachedLive
    @Binding var toast: ToastMessage?

    @Environment(\.modelContext) private var context
    @Environment(RemoteConfig.self) private var config
    @State private var presentedURL: URL?
    @State private var scheduled: ScheduleItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if let banner = live.status.banner { statusBanner(banner) }
                timeCard
                priceCard
                if !live.lineup.isEmpty { lineupSection }
                venueSection
                summarySection
            }
            .padding(.bottom, 140)
        }
        .background(Theme.C.background)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }.tint(Theme.C.textSecondary)
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .sheet(item: $presentedURL) { url in SafariView(url: url).ignoresSafeArea() }
        .onAppear { scheduled = ScheduleStore.existingItem(forLive: live.id, in: context) }
    }

    /// 公演情報。外部同步来的演出会把来源页地址单独占一行，
    /// 直接当正文显示就是一串裸链接，所以这里把链接行拆出来做成可点的入口。
    @ViewBuilder
    private var summarySection: some View {
        let lines = (live.summary ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let links = lines.compactMap { Self.webURL($0) }
        let text = lines.filter { Self.webURL($0) == nil }.joined(separator: "\n")
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading("公演情報")
                if !text.isEmpty {
                    Text(text).font(Theme.F.body).foregroundStyle(Theme.C.textSecondary)
                }
                ForEach(links, id: \.self) { url in
                    Button { presentedURL = url } label: {
                        Label(url.host() ?? "查看来源", systemImage: "safari")
                            .font(Theme.F.body)
                    }
                    .tint(Theme.C.accent)
                }
            }
            .padding(.horizontal, Theme.M.screenPadding)
        }
    }

    /// 只认 http/https，避免把正文里带冒号的日文标题误判成链接。
    private static func webURL(_ line: String) -> URL? {
        guard let url = URL(string: line), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil else { return nil }
        return url
    }

    // MARK: - sections

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = live.coverURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { gradient }
                    }
                } else {
                    gradient
                }
            }
            .frame(height: 300)
            .clipped()
            .overlay { LinearGradient(colors: [.clear, Theme.C.background], startPoint: .center, endPoint: .bottom) }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(live.tags.prefix(3), id: \.self) { TagLabel(text: $0, color: Theme.C.textSecondary) }
                }
                Text(live.headlineText).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.C.textPrimary)
                if !live.lineup.isEmpty || live.subtitle != nil {
                    Text([live.lineup.isEmpty ? nil : live.title, live.subtitle].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.F.body).foregroundStyle(Theme.C.textSecondary)
                }
            }
            .padding(Theme.M.screenPadding)
        }
    }

    private var gradient: some View {
        LinearGradient(colors: [Theme.C.kind(.live).opacity(0.65), Theme.C.background], startPoint: .top, endPoint: .bottom)
    }

    private func statusBanner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(Theme.F.cardTitle).foregroundStyle(Theme.C.background)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.C.status(live.status)))
            .padding(.horizontal, Theme.M.screenPadding)
    }

    /// 開場 / 開演 分两行是日本 live 的惯例，不要合并。
    private var timeCard: some View {
        VStack(spacing: 0) {
            Text(Fmt.fullDay.string(from: live.startAt)).font(Theme.F.caption).foregroundStyle(Theme.C.textTertiary)
                .padding(.bottom, 10)
            HStack(spacing: 0) {
                timeColumn(label: "開場", date: live.openAt, emphasized: false)
                Divider().frame(height: 40).overlay(Theme.C.separator)
                timeColumn(label: "開演", date: live.startAt, emphasized: true)
                Divider().frame(height: 40).overlay(Theme.C.separator)
                timeColumn(label: "終演", date: live.endAt, emphasized: false)
            }
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Theme.M.cardRadius).fill(Theme.C.surface))
        .padding(.horizontal, Theme.M.screenPadding)
    }

    private func timeColumn(label: String, date: Date?, emphasized: Bool) -> some View {
        VStack(spacing: 4) {
            Text(label).font(Theme.F.caption).foregroundStyle(Theme.C.textTertiary)
            Text(date.map { Fmt.time.string(from: $0) } ?? "未定")
                .font(emphasized ? Theme.F.timeLarge : Theme.F.time)
                .foregroundStyle(emphasized ? Theme.C.accent : (date == nil ? Theme.C.textTertiary : Theme.C.textPrimary))
        }
        .frame(maxWidth: .infinity)
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading("チケット")
            VStack(spacing: 6) {
                priceRow("前売", live.priceAdvance)
                priceRow("当日", live.priceDoor)
                if live.hasDrinkFee {
                    priceRow("ドリンク代（別途）", live.drinkFee)
                }
                if let vendor = live.ticketVendor {
                    HStack { Text("販売").font(Theme.F.caption).foregroundStyle(Theme.C.textTertiary); Spacer()
                        Text(vendor).font(Theme.F.caption).foregroundStyle(Theme.C.textSecondary) }
                }
            }
            .padding(Theme.M.cardPadding)
            .background(RoundedRectangle(cornerRadius: Theme.M.cardRadius).fill(Theme.C.surface))
        }
        .padding(.horizontal, Theme.M.screenPadding)
    }

    private func priceRow(_ label: String, _ value: Int?) -> some View {
        HStack {
            Text(label).font(Theme.F.body).foregroundStyle(Theme.C.textSecondary)
            Spacer()
            Text(value.map { "¥" + $0.formatted(.number.grouping(.automatic)) } ?? "—")
                .font(Theme.F.price).foregroundStyle(Theme.C.textPrimary)
        }
    }

    private var lineupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("出演")
            ForEach(live.lineup) { entry in
                HStack(spacing: 12) {
                    CoverThumbnail(url: entry.imageUrl.flatMap(URL.init(string:)), fallbackText: entry.name, size: 40,
                                   color: Theme.C.kind(.custom))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(entry.isHeadliner ? Theme.F.cardTitle : Theme.F.body)
                            .fontWeight(entry.isHeadliner ? .bold : .regular).foregroundStyle(Theme.C.textPrimary)
                        if let cn = entry.nameCn ?? entry.nameLatin {
                            Text(cn).font(Theme.F.caption).foregroundStyle(Theme.C.textTertiary)
                        }
                    }
                    Spacer()
                    if entry.isHeadliner { TagLabel(text: "HEADLINER", color: Theme.C.accent) }
                }
                .padding(Theme.M.cardPadding)
                .background(RoundedRectangle(cornerRadius: Theme.M.cardRadius).fill(Theme.C.surface))
            }
        }
        .padding(.horizontal, Theme.M.screenPadding)
    }

    private var venueSection: some View {
        let coordinate = CLLocationCoordinate2D(latitude: live.venueLatitude, longitude: live.venueLongitude)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeading("会場")
            VStack(alignment: .leading, spacing: 0) {
                GoogleMiniMap(latitude: coordinate.latitude, longitude: coordinate.longitude, title: live.venueName)
                    .frame(height: 140)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 6) {
                    Text(live.venueName).font(Theme.F.cardTitle).foregroundStyle(Theme.C.textPrimary)
                    Text(live.venueAddress).font(Theme.F.body).foregroundStyle(Theme.C.textSecondary)
                    if let station = live.nearestStation {
                        Label(station, systemImage: "tram.fill").font(Theme.F.caption).foregroundStyle(Theme.C.accentAlt)
                    }
                    Button { openInMaps(coordinate) } label: {
                        Label("在 Google 地图中查看路线", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(Theme.F.body).foregroundStyle(Theme.C.textPrimary)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.C.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(Theme.M.cardPadding)
            }
            .background(RoundedRectangle(cornerRadius: Theme.M.cardRadius).fill(Theme.C.surface))
            .clipShape(RoundedRectangle(cornerRadius: Theme.M.cardRadius))
        }
        .padding(.horizontal, Theme.M.screenPadding)
    }

    // MARK: - 底部操作区

    private var actionBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button { toggleSchedule() } label: {
                    Label(scheduled != nil ? "已加入日程" : "加入日程",
                          systemImage: scheduled != nil ? "checkmark.circle.fill" : "calendar.badge.plus")
                        .font(Theme.F.cardTitle)
                        .foregroundStyle(scheduled != nil ? Theme.C.accentAlt : Theme.C.background)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(scheduled != nil ? Theme.C.surfaceRaised : Theme.C.accentAlt))
                }
                .buttonStyle(.plain)

                if let url = live.ticketURL {
                    Button { presentedURL = url } label: {
                        Label("購入", systemImage: "ticket.fill")
                            .font(Theme.F.cardTitle).foregroundStyle(Theme.C.textPrimary)
                            .padding(.horizontal, 18).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.C.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
            WalletPassSection(live: live)
        }
        .padding(.horizontal, Theme.M.screenPadding)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - behaviour

    private func toggleSchedule() {
        if let scheduled {
            ScheduleStore.remove(scheduled, in: context)
            self.scheduled = nil
            toast = ToastMessage(text: "已从日程移除", icon: "minus.circle.fill", tint: Theme.C.textSecondary)
            return
        }
        let result = ScheduleStore.add(live: live, in: context)
        scheduled = result.item
        if let clash = result.conflicts.first {
            toast = ToastMessage(text: "已加入日程", detail: "但与「\(clash.title)」时间重叠",
                                 icon: "exclamationmark.triangle.fill", tint: Theme.C.warning)
        } else {
            toast = ToastMessage(text: "已加入日程", detail: Fmt.fullDay.string(from: live.startAt))
        }
    }

    private func openInMaps(_ coordinate: CLLocationCoordinate2D) {
        // 远征场景，默认公共交通；拉起 Google Maps。
        GoogleNavigation.open(latitude: coordinate.latitude, longitude: coordinate.longitude, name: live.venueName)
    }

    private var shareText: String {
        """
        \(live.headlineText) @ \(live.venueName)
        \(Fmt.fullDay.string(from: live.startAt)) 開場 \(live.openAt.map { Fmt.time.string(from: $0) } ?? "-") / 開演 \(Fmt.time.string(from: live.startAt))
        \(live.venueAddress)
        """
    }
}

struct SectionHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(Theme.F.caption).foregroundStyle(Theme.C.textTertiary) }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
