import Foundation

/// anitabi 直连。三条硬性约束（来自 anitabi 官方文档，CC BY-NC-SA 4.0）：
/// 1. 绝不请求主域 https://anitabi.cn/ —— 只用 api.anitabi.cn 与 image.anitabi.cn。
/// 2. 图片只用 ?plan=h160（Pin / 列表）和 ?plan=h360（详情页），禁止使用去掉 plan 参数的原图。
/// 3. 每个地标展示处必须显示 origin 署名并实现 originURL 跳转（BY 条款）。
/// 另：NC 条款要求 App 保持免费、无内购、无广告；商业化前先用远程配置 features.pilgrimageLayer 关掉本图层。
actor AnitabiAPI {
    static let shared = AnitabiAPI()

    static let apiBase = URL(string: "https://api.anitabi.cn")!
    static let imageBase = "https://image.anitabi.cn"

    private let client = APIClient.shared
    /// 同一作品的 detail 拉取加 1 小时去重锁，避免反复进出地图触发重复请求。
    private var lastDetailFetch: [Int: Date] = [:]

    nonisolated struct Lite: Decodable, Sendable {
        let id: Int
        let title: String?
        let cn: String?
        let city: String?
        let cover: String?
        let color: String?
        let geo: [Double]?
        let zoom: Double?
        let modified: Int?
        let pointsLength: Int?
        let imagesLength: Int?
    }

    nonisolated struct Point: Decodable, Sendable {
        let id: String
        let name: String?
        let cn: String?
        let image: String?
        let ep: Int?
        let s: Int?
        let geo: [Double]?
        let origin: String?
        let originURL: String?
    }

    func lite(subjectId: Int) async throws -> Lite {
        try await client.get(Self.apiBase.appending(path: "/bangumi/\(subjectId)/lite"))
    }

    /// 全量地标。返回 nil 表示 1 小时内已经拉过、这次跳过。
    func pointsDetail(subjectId: Int, force: Bool = false) async throws -> [Point]? {
        if !force, let last = lastDetailFetch[subjectId], Date().timeIntervalSince(last) < 3600 { return nil }
        var comps = URLComponents(url: Self.apiBase.appending(path: "/bangumi/\(subjectId)/points/detail"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "haveImage", value: "true")]
        let points: [Point] = try await client.get(comps.url!)
        lastDetailFetch[subjectId] = Date()
        return points
    }

    // MARK: - 图片尺寸

    nonisolated static func imageBase(from url: String?) -> String? {
        guard let url, var comps = URLComponents(string: url) else { return nil }
        comps.query = nil
        return comps.string
    }

    nonisolated static func thumbnail(_ base: String?) -> URL? { base.flatMap { URL(string: $0 + "?plan=h160") } }
    nonisolated static func large(_ base: String?) -> URL? { base.flatMap { URL(string: $0 + "?plan=h360") } }
}
