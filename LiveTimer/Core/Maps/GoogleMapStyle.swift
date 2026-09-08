import Foundation
import GoogleMaps

/// 深色地图样式（Google 官方 Night mode 样式的精简版），和 App 的暗色主题统一。
enum GoogleMapStyle {
    static let dark: GMSMapStyle? = try? GMSMapStyle(jsonString: json)

    private static let json = """
    [
      {"elementType":"geometry","stylers":[{"color":"#1c1f2b"}]},
      {"elementType":"labels.text.fill","stylers":[{"color":"#8f93a3"}]},
      {"elementType":"labels.text.stroke","stylers":[{"color":"#1c1f2b"}]},
      {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#3a3d4d"}]},
      {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#c9ccd8"}]},
      {"featureType":"poi","stylers":[{"visibility":"off"}]},
      {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#22302a"}]},
      {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2e3142"}]},
      {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1c1f2b"}]},
      {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#454a63"}]},
      {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#2a2d3c"}]},
      {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3244"}]},
      {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#8f93a3"}]},
      {"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#4a6fb5"}]},
      {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},
      {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d4a66"}]}
    ]
    """
}
