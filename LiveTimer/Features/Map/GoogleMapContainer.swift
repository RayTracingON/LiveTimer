import SwiftUI
import MapKit
import GoogleMaps
import GoogleMapsUtils

/// 三类可聚合条目。各图层用独立的 GMUClusterManager，不跨图层聚合。
/// 标 nonisolated：它们只持有普通值，而聚合渲染回调不保证在主 actor 上。
nonisolated final class VenueItem: NSObject, GMUClusterItem {
    let venue: CachedVenue
    let position: CLLocationCoordinate2D
    init(_ venue: CachedVenue) { self.venue = venue; position = venue.coordinate }
}

nonisolated final class HotelItem: NSObject, GMUClusterItem {
    let place: HotelPlace
    let position: CLLocationCoordinate2D
    init(_ place: HotelPlace) { self.place = place; position = place.coordinate }
}

nonisolated final class PointItem: NSObject, GMUClusterItem {
    let point: CachedPilgrimagePoint
    let position: CLLocationCoordinate2D
    init(_ point: CachedPilgrimagePoint) {
        self.point = point
        position = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }
}

/// 标注颜色。UIColor(SwiftUI.Color) 的初始化是 MainActor 隔离的，而聚合渲染回调不在主 actor 上，
/// 所以这里用与 Theme 一致的字面值直接构造，避免跨 actor 调用。
enum MarkerPalette {
    static let live = UIColor(red: 1.0, green: 45 / 255, blue: 111 / 255, alpha: 1)          // Theme.C.kind(.live)
    static let hotel = UIColor(red: 59 / 255, green: 158 / 255, blue: 1.0, alpha: 1)         // Theme.C.kind(.hotel)
    static let pilgrimage = UIColor(red: 0, green: 229 / 255, blue: 195 / 255, alpha: 1)     // Theme.C.kind(.pilgrimage)
}

enum MapSelection: Equatable {
    case venue(String)
    case hotel(String)
    case point(String)
    case work(Int)
}

/// Google Maps SDK 版本的地图容器。聚合用 google-maps-ios-utils。
struct GoogleMapContainer: UIViewRepresentable {
    let venues: [CachedVenue]
    let hotels: [HotelPlace]
    let points: [CachedPilgrimagePoint]
    let works: [SubscribedIP]
    let initialRegion: MKCoordinateRegion
    let onRegionChanged: (MKCoordinateRegion) -> Void
    let onSelect: (MapSelection?) -> Void

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(target: initialRegion.center, zoom: Self.zoom(for: initialRegion))
        let map = GMSMapView(options: options)
        map.mapStyle = GoogleMapStyle.dark
        map.settings.compassButton = false
        map.settings.rotateGestures = false
        map.settings.tiltGestures = false
        map.delegate = context.coordinator
        context.coordinator.attach(map)
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// 大致换算：0.35° 经度跨度在 ~400pt 宽的屏幕上约等于 zoom 10.6。
    static func zoom(for region: MKCoordinateRegion, widthPoints: Double = 400) -> Float {
        let z = log2(360.0 * widthPoints / 256.0 / max(region.span.longitudeDelta, 0.0005))
        return Float(min(max(z, 3), 19))
    }

    final class Coordinator: NSObject, GMSMapViewDelegate, GMUClusterRendererDelegate {
        var parent: GoogleMapContainer
        private weak var map: GMSMapView?
        private var venueManager: GMUClusterManager?
        private var hotelManager: GMUClusterManager?
        private var pointManager: GMUClusterManager?
        private var workMarkers: [Int: GMSMarker] = [:]
        private var venueIds: Set<String> = [], hotelIds: Set<String> = [], pointIds: Set<String> = [], workIds: Set<Int> = []

        init(parent: GoogleMapContainer) { self.parent = parent }

        func attach(_ map: GMSMapView) {
            self.map = map
            venueManager = makeManager(map, color: MarkerPalette.live)
            hotelManager = makeManager(map, color: MarkerPalette.hotel)
            pointManager = makeManager(map, color: MarkerPalette.pilgrimage)
            sync()
        }

        private func makeManager(_ map: GMSMapView, color: UIColor) -> GMUClusterManager {
            let generator = GMUDefaultClusterIconGenerator(buckets: [5, 10, 50, 200], backgroundColors: [color, color, color, color])
            let renderer = GMUDefaultClusterRenderer(mapView: map, clusterIconGenerator: generator)
            renderer.delegate = self
            renderer.minimumClusterSize = 3
            return GMUClusterManager(map: map, algorithm: GMUNonHierarchicalDistanceBasedAlgorithm(), renderer: renderer)
        }

        /// 只有集合变了才重建该图层的聚合。
        func sync() {
            guard let map else { return }
            let newVenues = Set(parent.venues.map(\.id))
            if newVenues != venueIds, let m = venueManager {
                venueIds = newVenues
                m.clearItems(); m.add(parent.venues.map(VenueItem.init)); m.cluster()
            }
            let newHotels = Set(parent.hotels.map(\.id))
            if newHotels != hotelIds, let m = hotelManager {
                hotelIds = newHotels
                m.clearItems(); m.add(parent.hotels.map(HotelItem.init)); m.cluster()
            }
            let newPoints = Set(parent.points.map(\.id))
            if newPoints != pointIds, let m = pointManager {
                pointIds = newPoints
                m.clearItems(); m.add(parent.points.map(PointItem.init)); m.cluster()
            }
            let newWorks = Set(parent.works.map(\.bangumiSubjectId))
            if newWorks != workIds {
                workIds = newWorks
                workMarkers.values.forEach { $0.map = nil }
                workMarkers.removeAll()
                for ip in parent.works {
                    let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: ip.defaultLatitude, longitude: ip.defaultLongitude))
                    marker.title = ip.titleCn ?? ip.titleOriginal
                    marker.snippet = "\(ip.pointCount) 个地标"
                    marker.icon = GMSMarker.markerImage(with: MarkerPalette.pilgrimage)
                    marker.userData = ip.bangumiSubjectId
                    marker.map = map
                    workMarkers[ip.bangumiSubjectId] = marker
                }
            }
        }

        // MARK: GMUClusterRendererDelegate — 单个条目按图层上色

        func renderer(_ renderer: GMUClusterRenderer, willRenderMarker marker: GMSMarker) {
            switch marker.userData {
            case let item as VenueItem:
                marker.icon = GMSMarker.markerImage(with: MarkerPalette.live)
                marker.title = item.venue.name
                marker.snippet = item.venue.nextLiveAt.map { Fmt.sectionDay.string(from: $0) }
            case let item as HotelItem:
                marker.icon = GMSMarker.markerImage(with: MarkerPalette.hotel)
                marker.title = item.place.name
            case let item as PointItem:
                marker.icon = GMSMarker.markerImage(with: MarkerPalette.pilgrimage)
                marker.title = item.point.nameCn ?? item.point.name
            default:
                break
            }
        }

        // MARK: GMSMapViewDelegate

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            [venueManager, hotelManager, pointManager].forEach { $0?.cluster() }
            parent.onRegionChanged(Self.region(of: mapView))
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            switch marker.userData {
            case let item as VenueItem: parent.onSelect(.venue(item.venue.id))
            case let item as HotelItem: parent.onSelect(.hotel(item.place.id))
            case let item as PointItem: parent.onSelect(.point(item.point.id))
            case let subject as Int:
                parent.onSelect(.work(subject))
                mapView.animate(to: GMSCameraPosition(target: marker.position, zoom: max(mapView.camera.zoom, 12.5)))
            case is GMUCluster:
                mapView.animate(to: GMSCameraPosition(target: marker.position, zoom: mapView.camera.zoom + 1.5))
            default: return false
            }
            return true
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.onSelect(nil)
        }

        static func region(of map: GMSMapView) -> MKCoordinateRegion {
            let bounds = GMSCoordinateBounds(region: map.projection.visibleRegion())
            let ne = bounds.northEast, sw = bounds.southWest
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (ne.latitude + sw.latitude) / 2, longitude: (ne.longitude + sw.longitude) / 2),
                span: MKCoordinateSpan(latitudeDelta: abs(ne.latitude - sw.latitude), longitudeDelta: abs(ne.longitude - sw.longitude)))
        }
    }
}

/// 详情页里的小地图：单个标记，不可交互。
struct GoogleMiniMap: UIViewRepresentable {
    let latitude: Double
    let longitude: Double
    let title: String?
    var color: UIColor = MarkerPalette.live
    var zoom: Float = 15

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(latitude: latitude, longitude: longitude, zoom: zoom)
        let map = GMSMapView(options: options)
        map.mapStyle = GoogleMapStyle.dark
        map.settings.setAllGesturesEnabled(false)
        map.isUserInteractionEnabled = false
        let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        marker.title = title
        marker.icon = GMSMarker.markerImage(with: color)
        marker.map = map
        return map
    }

    func updateUIView(_ uiView: GMSMapView, context: Context) {}
}

extension MKCoordinateRegion {
    var bbox: Bbox {
        Bbox(minLng: center.longitude - span.longitudeDelta / 2, minLat: center.latitude - span.latitudeDelta / 2,
             maxLng: center.longitude + span.longitudeDelta / 2, maxLat: center.latitude + span.latitudeDelta / 2)
    }

    /// 首都圈。不用先要定位权限就能起来。
    static let tokyo = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.7200),
        span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35))
}
