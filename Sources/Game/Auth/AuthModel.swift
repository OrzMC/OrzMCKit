import Foundation

/// 正版授权数据形状（纯数据，无 IO）。契约见父仓库 `docs/spec/auth.md`。

public struct DeviceCode: Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let expiresIn: Int
    public let interval: Int
    public let message: String?

    public init(
        deviceCode: String,
        userCode: String,
        verificationUri: String,
        expiresIn: Int,
        interval: Int = 5,
        message: String? = nil
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationUri = verificationUri
        self.expiresIn = expiresIn
        self.interval = interval
        self.message = message
    }
}

/// Xbox Live / XSTS 令牌（`userHash` 即 `DisplayClaims.xui[0].uhs`）。
public struct XboxToken: Sendable, Equatable {
    public let token: String
    public let userHash: String

    public init(token: String, userHash: String) {
        self.token = token
        self.userHash = userHash
    }
}

public struct MinecraftToken: Sendable, Equatable {
    public let accessToken: String
    public let expiresIn: Int

    public init(accessToken: String, expiresIn: Int) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
    }
}

/// Minecraft 档案（`uuid` 已规范化为带连字符形式）。
public struct MinecraftProfile: Sendable, Equatable {
    public let uuid: String
    public let name: String

    public init(uuid: String, name: String) {
        self.uuid = uuid
        self.name = name
    }
}

public enum TokenState: String, Sendable, Equatable {
    case valid
    case stale
    case expired
}

public struct TokenStatus: Sendable, Equatable {
    public let state: TokenState
    public let remainingSeconds: Int

    public init(state: TokenState, remainingSeconds: Int) {
        self.state = state
        self.remainingSeconds = remainingSeconds
    }
}

public enum TokenAction: String, Sendable, Equatable {
    case wait
    case slowDown
    case fail
}

public struct TokenErrorAction: Sendable, Equatable {
    public let action: TokenAction
    public let code: String?

    public init(action: TokenAction, code: String? = nil) {
        self.action = action
        self.code = code
    }
}

/// Microsoft 账号令牌（`refreshToken` 来自 `offline_access`）。
public struct MsaTokens: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Double
    public let tokenType: String
    public let scope: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Double, tokenType: String = "Bearer", scope: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
        self.scope = scope
    }
}

/// 一次可用的认证会话：启动客户端所需的 uuid / 用户名 / MC 令牌。
public struct AuthSession: Sendable, Equatable {
    public let uuid: String
    public let name: String
    public let accessToken: String
    public let expiresAt: Double
    public let msa: MsaTokens
    public var source: String

    public init(uuid: String, name: String, accessToken: String, expiresAt: Double, msa: MsaTokens, source: String = "cache") {
        self.uuid = uuid
        self.name = name
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.msa = msa
        self.source = source
    }
}
