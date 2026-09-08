import SwiftUI
import SwiftData
import MapKit

/// 浮在地图底部的卡片外框。
struct MapCard<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(Theme.M.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.C.background.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: Theme.M.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: Theme.M.cardRadius).stroke(Theme.C.separator, lineWidth: 1) }
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.C.textTertiary)
                }
                .padding(8)
                .accessibilityLabel("关闭")
            }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .padding(.horizontal, Theme.M.screenPadding)
            .padding(.bottom, 8)
    }
}

// MARK: - 场馆

struct VenueCard: View {
    let venue: CachedVenue
    let selectedDate: Date
    @Binding var toast: ToastMessage?
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(LiveCatalogSync.self) private var sync
    @State private var lives: [CachedLive] = []
    @State private var loading = false

    var body: some View {
        MapCard(onClose: onClose) {
            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name).font(Theme.F.cardTitle).foregroundStyle(Theme.C.textPrimary).padding(.trailing, 28)
                if let station = venue.nearestStation {
                    Label(station, systemImage: "tram.fill").font(Theme.F.caption).foregroundStyle(Theme.C.accentAlt)
                }
            }
            if loading && lives.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if lives.isEmpty {
                Text("这段时间没有场次").font(Theme.F.caption).foregroundStyle(Theme.C.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(lives) { live in
                            NavigationLink { LiveDetailView(live: live, toast: $toast) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(Fmt.sectionDay.string(from: live.startAt)).font(Theme.F.caption).foregroundStyle(Theme.C.textTertiary)
                                    Text(live.headlineText).font(Theme.F.body).foregroundStyle(Theme.C.textPrimary).lineLimit(2).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    Text("\(Fmt.time.string(from: live.startAt)) 開演").font(Theme.F.time).foregroundStyle(Theme.C.accent)
                                }
                                .padding(10)
                                .frame(width: 180, height: 104, alignment: .topLeading)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.C.surfaceRaised))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task(id: venue.id) { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        lives = cached()
        let to = Calendar.jst.date(byAdding: .day, value: 60, to: selectedDate) ?? selectedDate
        if let page = try? await LiveTimerAPI.production.venueLives(venueId: venue.id, from: selectedDate, to: to) {
            for dto in page.items { sync.upsert(dto, context: context) }
            try? context.save()
            lives = cached()
        }
    }

    private func cached() -> [CachedLive] {
        let id = venue.id
        let from = Calendar.jst.startOfDay(for: selectedDate)
        let all = (try? context.fetch(FetchDescriptor<CachedLive>(predicate: #Predicate { $0.venueId == id }))) ?? []
        return all.filter { $0.startAt >= from }.sorted { $0.startAt < $1.startAt }
    }
}

// MARK: - 酒店

struct HotelCard: View {
    let place: HotelPlace
    @Binding var toast: ToastMessage?
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(RemoteConfig.self) private var config
    @Query private var items: [ScheduleItem]
    @State private var showDates = false

    var body: some View {
        MapCard(onClose: onClose) {
            HStack(spacing: 8) {
                TagLabel(text: "酒店", color: Theme.C.kind(.hotel), filled: true)
                Text(place.name).font(Theme.F.cardTitle).foregroundStyle(Theme.C.textPrimary).lineLimit(1).padding(.trailing, 28)
            }
            if let address = place.address {
                Text(address).font(Theme.F.caption).foregroundStyle(Theme.C.textSecondary).lineLimit(2)
            }
            HStack(spacing: 10) {
                if let rating = place.rating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill").font(Theme.F.caption).foregroundStyle(Theme.C.warning)
                }
                if let nearest = nearestLiveDistance {
                    Label(nearest, systemImage: "figure.walk").font(Theme.F.caption).foregroundStyle(Theme.C.accentAlt)
                }
            }
            HStack(spacing: 8) {
                Button { showDates = true } label: {
                    Label("加入日程", systemImage: "calendar.badge.plus")
                        .font(Theme.F.body).foregroundStyle(Theme.C.background)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.C.kind(.hotel)))
                }
                .buttonStyle(.plain)
                if place.googleMapsUrl != nil {
                    Button { GoogleNavigation.openPlace(url: place.googleMapsUrl) } label: {
                        Label("Google 地图", systemImage: "map")
                            .font(Theme.F.body).foregroundStyle(Theme.C.textPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.C.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(config.disclaimers["hotel"] ?? "本 App 不提供预订，房价与空房请以官网为准。位置信息来自 Google 地图。")
                .font(Theme.F.tag).foregroundStyle(Theme.C.textTertiary)
        }
        .sheet(isPresented: $showDates) { HotelDatesSheet(place: place, toast: $toast) }
    }

    /// 到日程中最近一场 Live 的直线距离（不调路径 API）。
    private var nearestLiveDistance: String? {
        let here = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let candidates = items.filter { $0.kind == .live && $0.startAt >= Date() }
            .compactMap { item -> (String, Double)? in
                guard let lat = item.latitude, let lng = item.longitude else { return nil }
                return (item.locationName ?? item.title, here.distance(from: CLLocation(latitude: lat, longitude: lng)))
            }
        guard let (name, meters) = candidates.min(by: { $0.1 < $1.1 }) else { return nil }
        return String(format: "距 %@ %.1f km · 步行约 %d 分", name, meters / 1000, Int(meters / 80))
    }
}

struct HotelDatesSheet: View {
    let place: HotelPlace
    @Binding var toast: ToastMessage?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var checkIn = Calendar.jst.startOfDay(for: Date())
    @State private var checkOut = Calendar.jst.startOfDay(for: Date()).addingTimeInterval(86400)

    var body: some View {
        NavigationStack {
            Form {
                Section(place.name) {
                    DatePicker("入住", selection: $checkIn, displayedComponents: .date)
                    DatePicker("退房", selection: $checkOut, in: checkIn.addingTimeInterval(86400)..., displayedComponents: .date)
                }
                Section { Text("只记录住宿安排，不涉及预订。").font(Theme.F.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("加入日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        ScheduleStore.addHotel(name: place.name, address: place.address, latitude: place.latitude,
                                               longitude: place.longitude, checkIn: checkIn, checkOut: checkOut,
                                               url: place.googleMapsUrl, phone: nil, in: context)
                        toast = ToastMessage(text: "已加入日程", detail: "\(Fmt.sectionDay.string(from: checkIn)) 入住", tint: Theme.C.kind(.hotel))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 巡礼地标

struct PilgrimagePointCard: View {
    let point: CachedPilgrimagePoint
    let work: SubscribedIP?
    @Binding var toast: ToastMessage?
    let onClose: () -> Void

    @State private var showDetail = false

    var body: some View {
        MapCard(onClose: onClose) {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: point.thumbnailURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Theme.C.surfaceRaised }
                }
                .frame(width: 96, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(point.nameCn ?? point.name).font(Theme.F.cardTitle).foregroundStyle(Theme.C.textPrimary).lineLimit(2).padding(.trailing, 28)
                    if point.nameCn != nil { Text(point.name).font(Theme.F.caption).foregroundStyle(Theme.C.textSecondary).lineLimit(1) }
                    if let work { Text(work.titleCn ?? work.titleOriginal).font(Theme.F.caption).foregroundStyle(Theme.C.kind(.pilgrimage)).lineLimit(1) }
                    if let ep = point.episodeText { Text(ep).font(Theme.F.tag).foregroundStyle(Theme.C.textTertiary) }
                }
            }
            AttributionRow(point: point)
            Button { showDetail = true } label: {
                Label("查看详情", systemImage: "camera.viewfinder")
                    .font(Theme.F.body).foregroundStyle(Theme.C.background)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.C.kind(.pilgrimage)))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showDetail) {
            NavigationStack { PilgrimagePointDetailView(point: point, work: work, toast: $toast) }
        }
    }
}

/// 来源署名。授权要求：每个展示地标截图的地方都要有，不得折叠或隐藏。
struct AttributionRow: View {
    let point: CachedPilgrimagePoint
    @State private var originURL: URL?

    var body: some View {
        HStack(spacing: 4) {
            Text("来源：\(point.origin ?? "anitabi")").font(Theme.F.caption).foregroundStyle(Theme.C.textSecondary)
            if let raw = point.originURL, let url = URL(string: raw) {
                Button { originURL = url } label: {
                    Label("查看原始来源", systemImage: "arrow.up.right.square").font(Theme.F.caption).foregroundStyle(Theme.C.accentAlt)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("数据：Anitabi CC BY-NC-SA").font(Theme.F.tag).foregroundStyle(Theme.C.textTertiary)
        }
        .sheet(item: $originURL) { SafariView(url: $0).ignoresSafeArea() }
    }
}
