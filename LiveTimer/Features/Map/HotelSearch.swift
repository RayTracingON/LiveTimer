import Foundation
import MapKit
import Observation

/// 图层 B 的数据源：后端代理的 Google Places（Key 不进 App，结果在服务端缓存）。
/// 后端只返回希尔顿 / 万豪 / IHG / 凯悦四家集团的酒店。
/// 只有名称 / 地址 / 评分 / Google 地图链接，**没有价格和空房**，UI 上不留价格占位。
nonisolated struct HotelPlace: Identifiable, Sendable, Equatable, Decodable {
    let id: String
    let name: String
    let address: String?
    let lat: Double
    let lng: Double
    let rating: Double?
    let googleMapsUrl: String?
    /// 所属集团（hilton / marriott / ihg / hyatt）。后端只返回这四家。
    let brandId: String?
    let brandLabel: String?

    var latitude: Double { lat }
    var longitude: Double { lng }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    static func == (l: HotelPlace, r: HotelPlace) -> Bool { l.id == r.id }
}

nonisolated struct HotelPage: Decodable, Sendable {
    let items: [HotelPlace]
    let source: String?
    let cached: Bool?
}

@MainActor
@Observable
final class HotelSearch {
    private(set) var places: [HotelPlace] = []
    private(set) var isSearching = false
    private(set) var lastError: String?
    /// 只看某几个集团时填 id，逗号分隔；空 = 四家都看。
    var groups: String = ""

    private var lastRegion: MKCoordinateRegion?
    private var task: Task<Void, Never>?
    private let api = LiveTimerAPI.production

    /// 地图移动 800ms 防抖，小幅移动不重搜（Places 按请求计费）。
    func search(in region: MKCoordinateRegion) {
        if let last = lastRegion, !movedEnough(from: last, to: region) { return }
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await run(region)
        }
    }

    func clear() {
        task?.cancel()
        places = []
        lastRegion = nil
    }

    private func run(_ region: MKCoordinateRegion) async {
        let bbox = region.bbox
        guard !bbox.isTooLargeForBackend else { places = []; return }
        isSearching = true
        defer { isSearching = false }
        do {
            let page: HotelPage = try await api.hotels(bbox: bbox, groups: groups)
            guard !Task.isCancelled else { return }
            places = page.items
            lastRegion = region
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func movedEnough(from a: MKCoordinateRegion, to b: MKCoordinateRegion) -> Bool {
        let dLat = abs(a.center.latitude - b.center.latitude)
        let dLng = abs(a.center.longitude - b.center.longitude)
        let zoomChanged = abs(a.span.latitudeDelta - b.span.latitudeDelta) > a.span.latitudeDelta * 0.3
        return zoomChanged || dLat > a.span.latitudeDelta * 0.25 || dLng > a.span.longitudeDelta * 0.25
    }
}
