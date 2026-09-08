import Foundation

/// 网络层不抛裸 Error，统一成这一个枚举。
nonisolated enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case offline
    case network(String)
    case server(status: Int, code: String?, message: String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请求地址无效"
        case .offline: return "当前离线，显示的是缓存数据"
        case .network(let m): return "网络错误：\(m)"
        case .server(let status, let code, let message):
            return "服务器错误 \(status)" + (code.map { " (\($0))" } ?? "") + (message.map { "：\($0)" } ?? "")
        case .decoding(let m): return "数据解析失败：\(m)"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .network, .offline: return true
        case .server(let status, _, _): return status >= 500
        default: return false
        }
    }
}

/// 后端 §1.4 的统一错误信封。
nonisolated struct APIErrorEnvelope: Decodable, Sendable {
    nonisolated struct Body: Decodable, Sendable {
        let code: String
        let message: String
    }
    let error: Body
}
