import Foundation
import SwiftData
import CoreLocation

@Model
final class CachedVenue {
    @Attribute(.unique) var id: String
    var name: String
    var address: String
    var prefecture: String?
    var latitude: Double
    var longitude: Double
    var nearestStation: String?
    var upcomingLiveCount: Int
    var nextLiveAt: Date?
    var updatedAt: Date

    init(id: String, name: String, address: String, prefecture: String?, latitude: Double, longitude: Double,
         nearestStation: String?, upcomingLiveCount: Int, nextLiveAt: Date?, updatedAt: Date) {
        self.id = id
        self.name = name
        self.address = address
        self.prefecture = prefecture
        self.latitude = latitude
        self.longitude = longitude
        self.nearestStation = nearestStation
        self.upcomingLiveCount = upcomingLiveCount
        self.nextLiveAt = nextLiveAt
        self.updatedAt = updatedAt
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
