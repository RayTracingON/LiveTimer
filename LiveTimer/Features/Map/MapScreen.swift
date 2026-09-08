import SwiftUI
import SwiftData
import MapKit

/// 地图页：三个图层 + 点选后才浮出的小卡片。没有常驻的底部面板。
struct MapScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(LiveCatalogSync.self) private var sync
    @Environment(RemoteConfig.self) private var config
    @Environment(PilgrimageStore.self) private var pilgrimage
    @Binding var toast: ToastMessage?

    @AppStorage("map.layer.venues") private var showVenues = true
    @AppStorage("map.layer.hotels") private var showHotels = true
    @AppStorage("map.layer.pilgrimage") private var showPilgrimage = true

    @Query private var subscribedIPs: [SubscribedIP]
    @Query private var allPoints: [CachedPilgrimagePoint]

    @State private var region: MKCoordinateRegion = .tokyo
    @State private var visibleVenues: [CachedVenue] = []
    @State private var selection: MapSelection?
    @State private var selectedDate = Date()
    @State private var isLoading = false
    @State private var tooZoomedOut = false
    @State private var fetchTask: Task<Void, Never>?
    @State private var hotelSearch = HotelSearch()
    @State private var showIPManager = false

    private let api = LiveTimerAPI.production
    /// 巡礼点只在放得够近时渲染，否则只显示作品级聚合点。
    private let pointZoomThreshold = 0.25

    private var hotelsEnabled: Bool { config.hotelLayerEnabled }
    private var pilgrimageEnabled: Bool { config.pilgrimageLayerEnabled }

    private var visiblePoints: [CachedPilgrimagePoint] {
        guard pilgrimageEnabled, showPilgrimage, region.span.latitudeDelta < pointZoomThreshold else { return [] }
        let b = region.bbox
        let pad = region.span.latitudeDelta * 0.3
        return allPoints.filter {
            $0.latitude >= b.minLat - pad && $0.latitude <= b.maxLat + pad && $0.longitude >= b.minLng - pad && $0.longitude <= b.maxLng + pad
        }
    }

    private var visibleWorks: [SubscribedIP] {
        guard pilgrimageEnabled, showPilgrimage, region.span.latitudeDelta >= pointZoomThreshold else { return [] }
        return subscribedIPs
    }

    var body: some View {
        NavigationStack {
            GoogleMapContainer(
                venues: showVenues ? visibleVenues : [],
                hotels: hotelsEnabled && showHotels ? hotelSearch.places : [],
                points: visiblePoints,
                works: visibleWorks,
                initialRegion: region,
                onRegionChanged: { newRegion in
                    region = newRegion
                    scheduleFetch()
                    if hotelsEnabled && showHotels { hotelSearch.search(in: newRegion) }
                },
                onSelect: { selection = $0 }
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("地图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                        .tint(Theme.C.accent)
                        .onChange(of: selectedDate) { _, _ in scheduleFetch(immediate: true) }
                }
            }
            .overlay(alignment: .topLeading) { summaryPill.padding(10) }
            .overlay(alignment: .topTrailing) { layerToggles.padding(10) }
            .overlay(alignment: .bottom) { selectionCard }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selection)
            .sheet(isPresented: $showIPManager) { IPSubscriptionView() }
            .task {
                loadFromCache()
                scheduleFetch(immediate: true)
                if hotelsEnabled && showHotels { hotelSearch.search(in: region) }
            }
            .onChange(of: showHotels) { _, on in
                if on { hotelSearch.search(in: region) } else { hotelSearch.clear() }
            }
        }
    }

    // MARK: - overlays

    /// 「12 场馆 · 3 有公演」。只有场馆没有公演时不重复写 0。
    private var venueSummary: String {
        let withLives = visibleVenues.filter { $0.upcomingLiveCount > 0 }.count
        return withLives > 0 ? "\(visibleVenues.count) 场馆·\(withLives) 有公演" : "\(visibleVenues.count) 场馆"
    }

    private var summaryPill: some View {
        let parts: [String] = [
            tooZoomedOut ? "放大查看场馆" : (showVenues ? venueSummary : nil),
            hotelsEnabled && showHotels ? "\(hotelSearch.places.count) 酒店" : nil,
            pilgrimageEnabled && showPilgrimage ? (region.span.latitudeDelta < pointZoomThreshold ? "\(visiblePoints.count) 地标" : (subscribedIPs.isEmpty ? nil : "\(subscribedIPs.count) 作品")) : nil,
        ].compactMap { $0 }
        return HStack(spacing: 6) {
            if isLoading || hotelSearch.isSearching { ProgressView().controlSize(.mini) }
            if hotelSearch.lastError != nil, showHotels { Image(systemName: "exclamationmark.triangle").font(Theme.F.tag).foregroundStyle(Theme.C.warning) }
            Text(parts.joined(separator: " · ")).font(Theme.F.caption).foregroundStyle(Theme.C.textPrimary)
            if sync.isOffline { Text("离线").font(Theme.F.tag).foregroundStyle(Theme.C.warning) }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    private var layerToggles: some View {
        VStack(spacing: 8) {
            LayerToggle(icon: "music.mic", color: Theme.C.kind(.live), isOn: $showVenues, label: "演出场馆")
            if hotelsEnabled {
                LayerToggle(icon: "bed.double.fill", color: Theme.C.kind(.hotel), isOn: $showHotels, label: "酒店")
            }
            if pilgrimageEnabled {
                LayerToggle(icon: "camera.viewfinder", color: Theme.C.kind(.pilgrimage), isOn: $showPilgrimage, label: "巡礼地标")
                Button { showIPManager = true } label: {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.C.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .accessibilityLabel("管理作品")
            }
        }
    }

    @ViewBuilder
    private var selectionCard: some View {
        switch selection {
        case .venue(let id):
            if let venue = visibleVenues.first(where: { $0.id == id }) {
                VenueCard(venue: venue, selectedDate: selectedDate, toast: $toast, onClose: { selection = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        case .hotel(let id):
            if let place = hotelSearch.places.first(where: { $0.id == id }) {
                HotelCard(place: place, toast: $toast, onClose: { selection = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        case .point(let id):
            if let point = allPoints.first(where: { $0.id == id }) {
                PilgrimagePointCard(point: point, work: subscribedIPs.first { $0.bangumiSubjectId == point.subjectId },
                                    toast: $toast, onClose: { selection = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        default:
            EmptyView()
        }
    }

    // MARK: - data

    /// 地图区域变化后 debounce 500ms 再请求场馆。
    private func scheduleFetch(immediate: Bool = false) {
        fetchTask?.cancel()
        let bbox = region.bbox
        tooZoomedOut = bbox.isTooLargeForBackend
        if tooZoomedOut { visibleVenues = []; return }
        fetchTask = Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            await fetchVenues(bbox: bbox)
        }
    }

    private func fetchVenues(bbox: Bbox) async {
        isLoading = true
        defer { isLoading = false }
        let from = selectedDate
        let to = Calendar.jst.date(byAdding: .day, value: 30, to: from) ?? from
        do {
            // 拉全部场馆：只显示「有场次」的话，刚导入的场馆在地图上完全看不到。
            // 没有公演的用灰色图钉区分，见 LiveMapContainer 的 willRenderMarker。
            let page = try await api.venues(bbox: bbox, hasUpcomingLives: false, from: from, to: to, limit: 200)
            for dto in page.items { sync.upsert(dto, context: context) }
            try? context.save()
            let ids = Set(page.items.map(\.id))
            visibleVenues = (try? context.fetch(FetchDescriptor<CachedVenue>()))?.filter { ids.contains($0.id) } ?? []
        } catch {
            loadFromCache()
        }
    }

    private func loadFromCache() {
        let b = region.bbox
        let all = (try? context.fetch(FetchDescriptor<CachedVenue>())) ?? []
        visibleVenues = all.filter { $0.longitude >= b.minLng && $0.longitude <= b.maxLng && $0.latitude >= b.minLat && $0.latitude <= b.maxLat }
    }
}

struct LayerToggle: View {
    let icon: String
    let color: Color
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Theme.C.background : Theme.C.textSecondary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(isOn ? AnyShapeStyle(color) : AnyShapeStyle(.ultraThinMaterial)))
        }
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "开" : "关")
    }
}
