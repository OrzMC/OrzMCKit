import Foundation

/// 纯数据请求描述；由 transport 翻译成实际 HTTP 调用。
public struct AuthRequest: Sendable, Equatable {
    public let method: String
    public let url: String
    public let headers: [String: String]
    public let form: [String: String]?
    public let body: Data?

    public init(method: String, url: String, headers: [String: String] = [:], form: [String: String]? = nil, body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.form = form
        self.body = body
    }
}

/// Microsoft / Xbox Live 设备码认证的**纯映射**（规范见 `docs/spec/auth.md`）。
/// 无 IO —— HTTP 发送与轮询在 `Authenticator`。
public enum AuthMapping {
    public static let authority = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
    public static let defaultScope = "XboxLive.signin offline_access"
    public static let xblURL = "https://user.auth.xboxlive.com/user/authenticate"
    public static let xstsURL = "https://xsts.auth.xboxlive.com/xsts/authorize"
    public static let minecraftLoginURL = "https://api.minecraftservices.com/authentication/login_with_xbox"
    public static let minecraftProfileURL = "https://api.minecraftservices.com/minecraft/profile"
    public static let xblRelyingParty = "http://auth.xboxlive.com"
    public static let xstsRelyingParty = "rp://api.minecraftservices.com/"
    public static let defaultSkewSeconds = 60

    static let knownXstsErrors: Set<Int> = [2148916233, 2148916235, 2148916238]

    static var jsonHeaders: [String: String] {
        ["Content-Type": "application/json", "Accept": "application/json"]
    }

    static func jsonBody(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        return nil
    }

    /// 32 位无连字符 UUID → 规范 8-4-4-4-12（非 32 位则原样返回）。
    public static func dashedUUID(_ hex32: String) -> String {
        let h = hex32.replacingOccurrences(of: "-", with: "").lowercased()
        guard h.count == 32 else { return hex32 }
        let chars = Array(h)
        func slice(_ start: Int, _ end: Int) -> String { String(chars[start..<end]) }
        return "\(slice(0, 8))-\(slice(8, 12))-\(slice(12, 16))-\(slice(16, 20))-\(slice(20, 32))"
    }

    static func xuiUhs(_ data: [String: Any]) -> String? {
        guard let claims = data["DisplayClaims"] as? [String: Any],
              let xui = claims["xui"] as? [[String: Any]],
              let first = xui.first else { return nil }
        return first["uhs"] as? String
    }

    // MARK: ① 设备码

    public static func deviceCodeRequest(clientId: String, scope: String = defaultScope) -> AuthRequest {
        AuthRequest(method: "POST", url: "\(authority)/devicecode", form: ["client_id": clientId, "scope": scope])
    }

    public static func deviceCodeResult(_ data: [String: Any]) -> DeviceCode? {
        guard let device = data["device_code"] as? String,
              let user = data["user_code"] as? String,
              let uri = data["verification_uri"] as? String,
              let expires = intValue(data["expires_in"]) else { return nil }
        return DeviceCode(
            deviceCode: device,
            userCode: user,
            verificationUri: uri,
            expiresIn: expires,
            interval: intValue(data["interval"]) ?? 5,
            message: data["message"] as? String
        )
    }

    // MARK: ② 令牌轮询 / 刷新

    public static func tokenPollRequest(clientId: String, deviceCode: String) -> AuthRequest {
        AuthRequest(
            method: "POST",
            url: "\(authority)/token",
            form: [
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": clientId,
                "device_code": deviceCode,
            ]
        )
    }

    public static func tokenRefreshRequest(clientId: String, refreshToken: String, scope: String = defaultScope) -> AuthRequest {
        AuthRequest(
            method: "POST",
            url: "\(authority)/token",
            form: [
                "grant_type": "refresh_token",
                "client_id": clientId,
                "refresh_token": refreshToken,
                "scope": scope,
            ]
        )
    }

    public static func tokenResult(_ data: [String: Any], now: Double) -> MsaTokens? {
        guard let access = data["access_token"] as? String,
              let refresh = data["refresh_token"] as? String,
              let expires = intValue(data["expires_in"]) else { return nil }
        return MsaTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: now + Double(expires),
            tokenType: data["token_type"] as? String ?? "Bearer",
            scope: data["scope"] as? String
        )
    }

    // MARK: ③ Xbox Live（RPS）

    public static func xboxRequest(msaAccessToken: String) -> AuthRequest {
        AuthRequest(
            method: "POST",
            url: xblURL,
            headers: jsonHeaders,
            body: jsonBody([
                "Properties": [
                    "AuthMethod": "RPS",
                    "SiteName": "user.auth.xboxlive.com",
                    "RpsTicket": "d=" + msaAccessToken,
                ],
                "RelyingParty": xblRelyingParty,
                "TokenType": "JWT",
            ])
        )
    }

    public static func xboxResult(_ data: [String: Any]) -> XboxToken? {
        guard let token = data["Token"] as? String, let uhs = xuiUhs(data) else { return nil }
        return XboxToken(token: token, userHash: uhs)
    }

    // MARK: ④ XSTS

    public static func xstsRequest(xblToken: String, relyingParty: String = xstsRelyingParty) -> AuthRequest {
        AuthRequest(
            method: "POST",
            url: xstsURL,
            headers: jsonHeaders,
            body: jsonBody([
                "Properties": ["SandboxId": "RETAIL", "UserTokens": [xblToken]],
                "RelyingParty": relyingParty,
                "TokenType": "JWT",
            ])
        )
    }

    public static func xstsResult(_ data: [String: Any]) -> XboxToken? {
        guard let token = data["Token"] as? String, let uhs = xuiUhs(data) else { return nil }
        return XboxToken(token: token, userHash: uhs)
    }

    // MARK: ⑤ Minecraft 登录

    public static func minecraftLoginRequest(userHash: String, xstsToken: String) -> AuthRequest {
        AuthRequest(
            method: "POST",
            url: minecraftLoginURL,
            headers: jsonHeaders,
            body: jsonBody(["identityToken": "XBL3.0 x=\(userHash);\(xstsToken)"])
        )
    }

    public static func minecraftLoginResult(_ data: [String: Any]) -> MinecraftToken? {
        guard let access = data["access_token"] as? String, let expires = intValue(data["expires_in"]) else { return nil }
        return MinecraftToken(accessToken: access, expiresIn: expires)
    }

    // MARK: ⑥ 档案

    public static func profileRequest(accessToken: String) -> AuthRequest {
        AuthRequest(method: "GET", url: minecraftProfileURL, headers: ["Authorization": "Bearer " + accessToken])
    }

    public static func profileResult(_ data: [String: Any]) -> MinecraftProfile? {
        guard let id = data["id"] as? String, let name = data["name"] as? String else { return nil }
        return MinecraftProfile(uuid: dashedUUID(id), name: name)
    }

    // MARK: 令牌状态与错误分类

    public static func tokenState(expiresAt: Double, now: Double, skewSeconds: Int = defaultSkewSeconds) -> TokenStatus {
        let remaining = Int(expiresAt - now)
        let state: TokenState = remaining <= 0 ? .expired : (remaining <= skewSeconds ? .stale : .valid)
        return TokenStatus(state: state, remainingSeconds: remaining)
    }

    public static func classifyTokenError(_ error: String?) -> TokenErrorAction {
        switch error {
        case "authorization_pending": return TokenErrorAction(action: .wait)
        case "slow_down": return TokenErrorAction(action: .slowDown)
        case "expired_token": return TokenErrorAction(action: .fail, code: "E_AUTH_EXPIRED")
        case "access_denied", "authorization_declined": return TokenErrorAction(action: .fail, code: "E_AUTH_DENIED")
        default: return TokenErrorAction(action: .fail, code: "E_AUTH")
        }
    }

    /// XSTS 响应 → 规范错误码；200 表示成功（`nil`）。
    public static func classifyXstsError(status: Int, xerr: Any?) -> String? {
        if status == 200 { return nil }
        guard let value = intValue(xerr) else { return "E_AUTH" }
        return knownXstsErrors.contains(value) ? "E_AUTH_XBOX" : "E_AUTH"
    }
}
