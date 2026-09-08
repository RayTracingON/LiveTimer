import Foundation
import Observation

/// 启动时拉 /api/v1/meta/config，结果存 UserDefaults 作为下次启动的兜底。
/// pilgrimageLayerEnabled == false 时：地图隐藏图层 C、IP 订阅入口隐藏，已有巡礼日程保留但不再拉新数据。
@MainActor
@Observable
final class RemoteConfig {
    var pilgrimageLayerEnabled: Bool = true
    var walletPassEnabled: Bool = true
    var hotelLayerEnabled: Bool = true
    var disclaimers: [String: String] = [:]
    var minimumAppVersion: String = "1.0.0"
    private(set) var lastFetchedAt: Date?

    private let defaults: UserDefaults
    private let api: LiveTimerAPI
    private static let key = "remoteConfig.v1"

    init(api: LiveTimerAPI = .production, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let cached = try? JSONDecoder().decode(Stored.self, from: data) {
            apply(cached)
        }
    }

    func refresh() async {
        do {
            let cfg = try await api.config()
            let stored = Stored(pilgrimage: cfg.features["pilgrimageLayer"] ?? true,
                                wallet: cfg.features["walletPass"] ?? true,
                                hotel: cfg.features["hotelLayer"] ?? true,
                                disclaimers: cfg.disclaimers,
                                minimumAppVersion: cfg.minimumAppVersion,
                                fetchedAt: Date())
            apply(stored)
            defaults.set(try? JSONEncoder().encode(stored), forKey: Self.key)
        } catch {
            // 拉不到就沿用上次的值；没有上次的值就全开，功能开关的默认语义是「可用」。
        }
    }

    private func apply(_ s: Stored) {
        pilgrimageLayerEnabled = s.pilgrimage
        walletPassEnabled = s.wallet
        hotelLayerEnabled = s.hotel
        disclaimers = s.disclaimers
        minimumAppVersion = s.minimumAppVersion
        lastFetchedAt = s.fetchedAt
    }

    private struct Stored: Codable {
        var pilgrimage: Bool
        var wallet: Bool
        var hotel: Bool
        var disclaimers: [String: String]
        var minimumAppVersion: String
        var fetchedAt: Date
    }
}
