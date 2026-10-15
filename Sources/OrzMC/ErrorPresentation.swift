import Foundation
import Game
import MojangAPI

/// 错误语义归一（B11）：把底层错误转成**用户可读**信息，不裸抛。
enum ErrorPresentation {
    static func message(for error: Error) -> String {
        // CLI 命令自身抛出的错误：已是用户可读信息。
        if let error = error as? CLIError {
            return error.message
        }
        if let error = error as? MojangAPIError {
            switch error {
            case .invalidURL: return "无效的地址"
            case .requestFailed(let status): return "网络请求失败（HTTP \(status)）"
            case .decodingFailed: return "响应解析失败"
            case .notFound: return "未找到指定的版本或资源"
            case .deprecatedEndpoint(let endpoint): return "接口已废弃：\(endpoint)"
            case .cacheMiss: return "缓存未命中且无法获取"
            case .missingSHA1: return "版本元数据缺少 SHA1"
            case .httpError(let status, _, let message): return "HTTP \(status)：\(message)"
            case .unknown(let message): return message
            }
        }
        if let error = error as? GameError {
            switch error {
            case .noGameVersions: return "无法获取版本清单(请检查网络连接)"
            case .worldNotFound(let path): return "未找到世界目录: \(path)"
            }
        }
        if let error = error as? AuthError {
            return error.message
        }
        return String(describing: error)
    }
}
