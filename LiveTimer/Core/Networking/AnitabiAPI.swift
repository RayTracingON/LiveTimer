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
        let id: Int?
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

        enum CodingKeys: String, CodingKey {
            case id, title, cn, city, cover, color, geo, zoom, modified, pointsLength, imagesLength
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.lenientInt(.id)
            title = c.lenientString(.title)
            cn = c.lenientString(.cn)
            city = c.lenientString(.city)
            cover = c.lenientString(.cover)
            color = c.lenientString(.color)
            geo = c.lenientDoubles(.geo)
            zoom = c.lenientDouble(.zoom)
            modified = c.lenientInt(.modified)
            pointsLength = c.lenientInt(.pointsLength)
            imagesLength = c.lenientInt(.imagesLength)
        }
    }

    nonisolated struct Point: Decodable, Sendable {
        let id: String
        let name: String?
        let cn: String?
        let image: String?
        /// 集数按原文保留。anitabi 这里的类型不固定：可能是数字 3，也可能是 "OP" / "劇場版" / "3"，
        /// 所以不再硬解成 Int，展示层自己决定要不要拼成「第 3 話」。
        let ep: String?
        let s: Int?
        let geo: [Double]?
        let origin: String?
        let originURL: String?

        enum CodingKeys: String, CodingKey {
            case id, name, cn, image, ep, s, geo, origin, originURL
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // id 是主键，缺了这个点就没法落库，只能整条丢掉。
            guard let id = c.lenientString(.id) else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "地标缺少 id")
            }
            self.id = id
            name = c.lenientString(.name)
            cn = c.lenientString(.cn)
            image = c.lenientString(.image)
            ep = c.lenientString(.ep)
            s = c.lenientInt(.s)
            geo = c.lenientDoubles(.geo)
            origin = c.lenientString(.origin)
            originURL = c.lenientString(.originURL)
        }
    }

    func lite(subjectId: Int) async throws -> Lite {
        try await client.get(Self.apiBase.appending(path: "/bangumi/\(subjectId)/lite"))
    }

    /// 全量地标。返回 nil 表示 1 小时内已经拉过、这次跳过。
    func pointsDetail(subjectId: Int, force: Bool = false) async throws -> [Point]? {
        if !force, let last = lastDetailFetch[subjectId], Date().timeIntervalSince(last) < 3600 { return nil }
        var comps = URLComponents(url: Self.apiBase.appending(path: "/bangumi/\(subjectId)/points/detail"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "haveImage", value: "true")]
        let list: LossyPoints = try await client.get(comps.url!)
        lastDetailFetch[subjectId] = Date()
        return list.points
    }

    /// 单个地标解析失败时只丢这一个点，不让几百个点的整批数据一起失败。
    nonisolated struct LossyPoints: Decodable, Sendable {
        let points: [Point]

        /// 包一层：init 永远不抛，unkeyed container 的游标才能稳定前进。
        private struct Element: Decodable {
            let point: Point?
            init(from decoder: any Decoder) throws { point = try? Point(from: decoder) }
        }

        init(from decoder: any Decoder) throws {
            let elements = try [Element](from: decoder)
            points = elements.compactMap(\.point)
        }
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

/// anitabi 是第三方开放数据，字段类型并不稳定（同一个 ep 有时是 3、有时是 "OP"）。
/// 这里统一用宽松读法：能转成目标类型就用，转不了就当没填，绝不因为一个字段炸掉整次请求。
/// 解码辅助。必须标 nonisolated：工程默认把成员推断成 MainActor 隔离，
/// 而 `init(from:)` 是非隔离的，调用时会报跨 actor 警告（Swift 6 严格并发下是错误）。
/// 这些方法只做纯粹的类型转换，不碰任何共享状态。
private nonisolated extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let v = try? decodeIfPresent(String.self, forKey: key) { return v.isEmpty ? nil : v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return String(v) }
        if let v = try? decodeIfPresent(Double.self, forKey: key), v.isFinite {
            return v == v.rounded() && v.magnitude < 1e15 ? String(Int(v)) : String(v)
        }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return v.asInt }
        if let v = try? decodeIfPresent(String.self, forKey: key) { return Int(v) ?? Double(v)?.asInt }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(String.self, forKey: key) { return Double(v) }
        return nil
    }

    /// geo 这类数组可能混着数字和字符串，逐项宽松解。
    func lenientDoubles(_ key: Key) -> [Double]? {
        guard let items = try? decodeIfPresent([LenientDouble].self, forKey: key) else { return nil }
        return items.compactMap(\.value)
    }
}

private nonisolated struct LenientDouble: Decodable {
    let value: Double?
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
}

private nonisolated extension Double {
    /// 只有有限且不溢出的浮点才转 Int，否则 Int(_:) 会直接崩。
    var asInt: Int? { isFinite && magnitude < 1e15 ? Int(self) : nil }
}
