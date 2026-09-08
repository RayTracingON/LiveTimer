import Foundation

/// 通用 HTTP 层。超时 15s；5xx 和网络错误重试 2 次（指数退避），4xx 不重试。
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let userAgent: String

    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        self.session = session ?? URLSession(configuration: config)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601DateFormatter.internet.date(from: raw)
                ?? ISO8601DateFormatter.internetFractional.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "非 ISO8601 日期: \(raw)")
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.internet.string(from: date))
        }
        self.encoder = encoder

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        self.userAgent = "LiveTimer/\(version) iOS"
    }

    func get<T: Decodable & Sendable>(_ url: URL, headers: [String: String] = [:]) async throws -> T {
        let data = try await send(request(url: url, method: "GET", headers: headers))
        return try decode(T.self, from: data)
    }

    func post<B: Encodable & Sendable, T: Decodable & Sendable>(_ url: URL, body: B,
                                                                headers: [String: String] = [:]) async throws -> T {
        var req = request(url: url, method: "POST", headers: headers)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        let data = try await send(req)
        return try decode(T.self, from: data)
    }

    /// pkpass 等二进制。
    func postData<B: Encodable & Sendable>(_ url: URL, body: B) async throws -> Data {
        var req = request(url: url, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        return try await send(req)
    }

    // MARK: - internals

    private func request(url: URL, method: String, headers: [String: String] = [:]) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return req
    }

    private func send(_ request: URLRequest, attempt: Int = 0) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.network("无效响应") }
            guard (200..<300).contains(http.statusCode) else {
                let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data)
                let error = APIError.server(status: http.statusCode, code: envelope?.error.code,
                                            message: envelope?.error.message)
                if error.isRetryable, attempt < 2 {
                    try await backoff(attempt)
                    return try await send(request, attempt: attempt + 1)
                }
                throw error
            }
            return data
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            let mapped: APIError = error.code == .notConnectedToInternet ? .offline : .network(error.localizedDescription)
            if attempt < 2, error.code != .cancelled {
                try await backoff(attempt)
                return try await send(request, attempt: attempt + 1)
            }
            throw mapped
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private func backoff(_ attempt: Int) async throws {
        try await Task.sleep(for: .milliseconds(400 * Int(pow(2.0, Double(attempt)))))
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

nonisolated extension ISO8601DateFormatter {
    /// 后端保证输出不带小数秒的 ISO8601（+09:00），这是主路径。
    static let internet: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 兜底：万一哪个字段带了小数秒也能解。
    static let internetFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
