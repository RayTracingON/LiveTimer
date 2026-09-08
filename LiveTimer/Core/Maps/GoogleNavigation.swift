import UIKit
import CoreLocation

/// 导航统一拉起 Google Maps App（公共交通模式）；没装的话回退到网页版。
enum GoogleNavigation {
    @MainActor
    static func open(latitude: Double, longitude: Double, name: String?) {
        let dest = "\(latitude),\(longitude)"
        let web = webDirections(to: dest)
        guard let appURL = URL(string: "comgooglemaps://?daddr=\(dest)&directionsmode=transit") else {
            if let web { UIApplication.shared.open(web) }
            return
        }
        // canOpenURL 在 iOS 27 起废弃：直接尝试打开，失败了再回退网页版
        UIApplication.shared.open(appURL) { opened in
            if !opened, let web { UIApplication.shared.open(web) }
        }
    }

    private static func webDirections(to dest: String) -> URL? {
        var comps = URLComponents(string: "https://www.google.com/maps/dir/")
        comps?.queryItems = [.init(name: "api", value: "1"), .init(name: "destination", value: dest),
                             .init(name: "travelmode", value: "transit")]
        return comps?.url
    }

    @MainActor
    static func openPlace(url: String?) {
        guard let url, let u = URL(string: url) else { return }
        UIApplication.shared.open(u)
    }
}
