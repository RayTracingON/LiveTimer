import UIKit
import CoreLocation

/// 导航统一拉起 Google Maps App（公共交通模式）；没装的话回退到网页版。
enum GoogleNavigation {
    static func open(latitude: Double, longitude: Double, name: String?) {
        let dest = "\(latitude),\(longitude)"
        if let appURL = URL(string: "comgooglemaps://?daddr=\(dest)&directionsmode=transit"),
           UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
            return
        }
        var comps = URLComponents(string: "https://www.google.com/maps/dir/")!
        comps.queryItems = [.init(name: "api", value: "1"), .init(name: "destination", value: dest),
                            .init(name: "travelmode", value: "transit")]
        if let url = comps.url { UIApplication.shared.open(url) }
    }

    static func openPlace(url: String?) {
        guard let url, let u = URL(string: url) else { return }
        UIApplication.shared.open(u)
    }
}
