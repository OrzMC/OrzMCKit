import Foundation

// Linux/Windows 把 URLSession/URLRequest 放在 FoundationNetworking（决策 D8：跨平台）。
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 认证失败，携带规范错误码（`E_AUTH*`，见 `docs/spec/auth.md` §7）。
public struct AuthError: Error, Sendable, Equatable, CustomStringConvertible {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { message }
}

public struct AuthHTTPResponse: Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    public func json() -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [:] }
        return object
    }
}

/// HTTP 发送接缝（生产用 `URLSession`，测试可注入假实现）。
public protocol AuthTransport: Sendable {
    func send(_ request: AuthRequest) async throws -> AuthHTTPResponse
}

public struct URLSessionAuthTransport: AuthTransport {
    public init() {}

    public func send(_ request: AuthRequest) async throws -> AuthHTTPResponse {
        guard let url = URL(string: request.url) else {
            throw AuthError(code: "E_AUTH", message: "非法 URL: \(request.url)")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if let form = request.form {
            urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let encoded = form
                .map { "\(Self.escape($0.key))=\(Self.escape($0.value))" }
                .sorted()
                .joined(separator: "&")
            urlRequest.httpBody = encoded.data(using: .utf8)
        } else if let body = request.body {
            urlRequest.httpBody = body
            if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return AuthHTTPResponse(status: status, body: data)
    }

    static func escape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// 正版授权编排：缓存复用 → 刷新 → 设备码登录。
public struct Authenticator: Sendable {
    public typealias Clock = @Sendable () -> Double
    public typealias Sleep = @Sendable (Double) async -> Void

    let transport: any AuthTransport
    let store: AuthStore
    let clientId: String
    let clock: Clock
    let sleep: Sleep
    let onDeviceCode: (@Sendable (DeviceCode) -> Void)?

    public init(
        transport: any AuthTransport = URLSessionAuthTransport(),
        store: AuthStore,
        clientId: String,
        onDeviceCode: (@Sendable (DeviceCode) -> Void)? = nil,
        clock: @escaping Clock = { Date().timeIntervalSince1970 },
        sleep: @escaping Sleep = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.transport = transport
        self.store = store
        self.clientId = clientId
        self.onDeviceCode = onDeviceCode
        self.clock = clock
        self.sleep = sleep
    }

    /// 返回一个 MC 令牌有效的会话：缓存 → 刷新 → 设备码登录。
    public func ensure() async throws -> AuthSession {
        if let session = store.load() {
            if AuthMapping.tokenState(expiresAt: session.expiresAt, now: clock()).state == .valid {
                var cached = session
                cached.source = "cache"
                return cached
            }
            do {
                return try await refresh(session.msa)
            } catch {
                // refresh token 被拒 → 清掉重登，不吞错（最终 login 的错会抛出）。
                store.clear()
            }
        }
        return try await login()
    }

    /// 完整设备码流程（用户需在浏览器完成授权）。
    public func login() async throws -> AuthSession {
        let response = try await transport.send(AuthMapping.deviceCodeRequest(clientId: clientId))
        guard response.status == 200, let device = AuthMapping.deviceCodeResult(response.json()) else {
            throw AuthError(code: "E_AUTH", message: Self.errorText(response.json()))
        }
        onDeviceCode?(device)
        let msa = try await poll(device)
        return try await complete(msa, source: "device_code")
    }

    /// 用 MSA `refresh_token` 换新 MSA 令牌，再重走 Xbox 链路。
    public func refresh(_ msa: MsaTokens) async throws -> AuthSession {
        let response = try await transport.send(
            AuthMapping.tokenRefreshRequest(clientId: clientId, refreshToken: msa.refreshToken)
        )
        guard response.status == 200, let tokens = AuthMapping.tokenResult(response.json(), now: clock()) else {
            let action = AuthMapping.classifyTokenError(response.json()["error"] as? String)
            throw AuthError(code: action.code ?? "E_AUTH_EXPIRED", message: Self.errorText(response.json()))
        }
        return try await complete(tokens, source: "refresh")
    }

    private func poll(_ device: DeviceCode) async throws -> MsaTokens {
        let deadline = clock() + Double(device.expiresIn)
        var interval = max(1, device.interval)
        while true {
            let response = try await transport.send(
                AuthMapping.tokenPollRequest(clientId: clientId, deviceCode: device.deviceCode)
            )
            if response.status == 200, let tokens = AuthMapping.tokenResult(response.json(), now: clock()) {
                return tokens
            }
            let action = AuthMapping.classifyTokenError(response.json()["error"] as? String)
            if action.action == .slowDown {
                interval += 5
            } else if action.action == .fail {
                throw AuthError(code: action.code ?? "E_AUTH", message: Self.errorText(response.json()))
            }
            if clock() + Double(interval) > deadline {
                throw AuthError(code: "E_AUTH_EXPIRED", message: "设备码已过期，请重新运行以再次授权")
            }
            await sleep(Double(interval))
        }
    }

    private func complete(_ msa: MsaTokens, source: String) async throws -> AuthSession {
        let xblResponse = try await transport.send(AuthMapping.xboxRequest(msaAccessToken: msa.accessToken))
        guard xblResponse.status == 200, let xbl = AuthMapping.xboxResult(xblResponse.json()) else {
            throw AuthError(code: "E_AUTH", message: Self.errorText(xblResponse.json()))
        }

        let xstsResponse = try await transport.send(AuthMapping.xstsRequest(xblToken: xbl.token))
        guard xstsResponse.status == 200, let xsts = AuthMapping.xstsResult(xstsResponse.json()) else {
            let code = AuthMapping.classifyXstsError(status: xstsResponse.status, xerr: xstsResponse.json()["XErr"]) ?? "E_AUTH"
            throw AuthError(code: code, message: Self.errorText(xstsResponse.json()))
        }

        let loginResponse = try await transport.send(
            AuthMapping.minecraftLoginRequest(userHash: xsts.userHash, xstsToken: xsts.token)
        )
        guard loginResponse.status == 200, let token = AuthMapping.minecraftLoginResult(loginResponse.json()) else {
            throw AuthError(code: "E_AUTH", message: Self.errorText(loginResponse.json()))
        }

        let profileResponse = try await transport.send(AuthMapping.profileRequest(accessToken: token.accessToken))
        if profileResponse.status == 401 {
            throw AuthError(code: "E_AUTH_NO_GAME", message: "该账号没有 Minecraft Java 版")
        }
        guard profileResponse.status == 200, let profile = AuthMapping.profileResult(profileResponse.json()) else {
            throw AuthError(code: "E_AUTH", message: Self.errorText(profileResponse.json()))
        }

        let session = AuthSession(
            uuid: profile.uuid,
            name: profile.name,
            accessToken: token.accessToken,
            expiresAt: clock() + Double(token.expiresIn),
            msa: msa,
            source: source
        )
        try store.save(session, clientId: clientId)
        return session
    }

    static func errorText(_ json: [String: Any]) -> String {
        (json["error_description"] as? String)
            ?? (json["Message"] as? String)
            ?? (json["error"] as? String)
            ?? "认证失败"
    }
}

/// 便捷入口：确保一个有效的正版授权会话（缓存 → 刷新 → 设备码）。
public func authenticate(
    clientId: String,
    stateDir: String? = nil,
    onDeviceCode: (@Sendable (DeviceCode) -> Void)? = nil
) async throws -> AuthSession {
    let authenticator = Authenticator(store: AuthStore(stateDir: stateDir), clientId: clientId, onDeviceCode: onDeviceCode)
    return try await authenticator.ensure()
}
