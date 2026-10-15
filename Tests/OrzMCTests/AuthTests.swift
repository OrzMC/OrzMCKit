import Foundation
import Testing

@testable import Game

/// 正版授权（`docs/spec/auth.md`）：纯映射 + 令牌存储 + 设备码编排。
@Suite struct AuthTests {
    // MARK: 纯映射

    @Test func deviceCodeRequestUsesConsumersAndScope() {
        let request = AuthMapping.deviceCodeRequest(clientId: "cid")
        #expect(request.method == "POST")
        #expect(request.url == "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")
        #expect(request.form == ["client_id": "cid", "scope": "XboxLive.signin offline_access"])
    }

    @Test func xboxRequestPrefixesRpsTicket() throws {
        let request = AuthMapping.xboxRequest(msaAccessToken: "MSA")
        let body = try #require(request.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let properties = try #require(object["Properties"] as? [String: Any])
        #expect(properties["RpsTicket"] as? String == "d=MSA")
        #expect(object["RelyingParty"] as? String == "http://auth.xboxlive.com")
    }

    @Test func profileResultNormalizesUUID() throws {
        let profile = try #require(AuthMapping.profileResult(["id": "069a79f444e94726a5befca90e38aaf5", "name": "Notch"]))
        #expect(profile.uuid == "069a79f4-44e9-4726-a5be-fca90e38aaf5")
        #expect(profile.name == "Notch")
    }

    @Test func tokenStateBoundaries() {
        #expect(AuthMapping.tokenState(expiresAt: 1000, now: 900).state == .valid)
        #expect(AuthMapping.tokenState(expiresAt: 1000, now: 960).state == .stale)
        #expect(AuthMapping.tokenState(expiresAt: 1000, now: 1000).state == .expired)
    }

    @Test func classifyErrors() {
        #expect(AuthMapping.classifyTokenError("authorization_pending").action == .wait)
        #expect(AuthMapping.classifyTokenError("slow_down").action == .slowDown)
        #expect(AuthMapping.classifyTokenError("expired_token").code == "E_AUTH_EXPIRED")
        #expect(AuthMapping.classifyXstsError(status: 401, xerr: 2148916233) == "E_AUTH_XBOX")
        #expect(AuthMapping.classifyXstsError(status: 401, xerr: 12345) == "E_AUTH")
        #expect(AuthMapping.classifyXstsError(status: 200, xerr: nil) == nil)
    }

    // MARK: 令牌存储

    private func tempDir() -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("orzmc-auth-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir.path
    }

    private var sampleSession: AuthSession {
        AuthSession(
            uuid: "069a79f4-44e9-4726-a5be-fca90e38aaf5",
            name: "Notch",
            accessToken: "MC",
            expiresAt: 10_000,
            msa: MsaTokens(accessToken: "MSA", refreshToken: "REFRESH", expiresAt: 10_000)
        )
    }

    @Test func storeRoundtripIsPrivate() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = AuthStore(stateDir: dir)
        #expect(store.load() == nil)
        try store.save(sampleSession, clientId: "cid")
        let loaded = try #require(store.load())
        #expect(loaded.uuid == sampleSession.uuid)
        #expect(loaded.msa.refreshToken == "REFRESH")
        let attributes = try FileManager.default.attributesOfItem(atPath: store.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func storeIgnoresCorruptFile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = AuthStore(stateDir: dir)
        try Data("{ not json".utf8).write(to: URL(fileURLWithPath: store.path))
        #expect(store.load() == nil)
    }

    // MARK: 设备码编排（假 transport，离线）

    final class MockTransport: AuthTransport, @unchecked Sendable {
        private var queue: [AuthHTTPResponse]
        private(set) var requests: [AuthRequest] = []

        init(_ queue: [AuthHTTPResponse]) { self.queue = queue }

        func send(_ request: AuthRequest) async throws -> AuthHTTPResponse {
            requests.append(request)
            return queue.removeFirst()
        }
    }

    private func response(_ status: Int, _ json: [String: Any]) -> AuthHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        return AuthHTTPResponse(status: status, body: data)
    }

    @Test func ensureRunsDeviceCodeThenReusesCache() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let transport = MockTransport([
            response(200, ["device_code": "DEV", "user_code": "ABCD", "verification_uri": "https://x", "expires_in": 900, "interval": 5]),
            response(200, ["access_token": "MSA", "refresh_token": "REFRESH", "expires_in": 3600]),
            response(200, ["Token": "XBL", "DisplayClaims": ["xui": [["uhs": "UH"]]]]),
            response(200, ["Token": "XSTS", "DisplayClaims": ["xui": [["uhs": "UH"]]]]),
            response(200, ["access_token": "MC", "expires_in": 3600]),
            response(200, ["id": "069a79f444e94726a5befca90e38aaf5", "name": "Notch"]),
        ])
        let authenticator = Authenticator(
            transport: transport,
            store: AuthStore(stateDir: dir),
            clientId: "cid",
            clock: { 1000 },
            sleep: { _ in }
        )
        let session = try await authenticator.ensure()
        #expect(session.source == "device_code")
        #expect(session.name == "Notch")
        #expect(session.msa.refreshToken == "REFRESH")

        let before = transport.requests.count
        let cached = try await authenticator.ensure()
        #expect(cached.source == "cache")
        #expect(transport.requests.count == before)
    }

    @Test func xstsRejectionMapsToAuthXbox() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let transport = MockTransport([
            response(200, ["device_code": "DEV", "user_code": "ABCD", "verification_uri": "https://x", "expires_in": 900, "interval": 5]),
            response(200, ["access_token": "MSA", "refresh_token": "REFRESH", "expires_in": 3600]),
            response(200, ["Token": "XBL", "DisplayClaims": ["xui": [["uhs": "UH"]]]]),
            response(401, ["XErr": 2148916233, "Message": "no xbox"]),
        ])
        let authenticator = Authenticator(
            transport: transport,
            store: AuthStore(stateDir: dir),
            clientId: "cid",
            clock: { 1000 },
            sleep: { _ in }
        )
        await #expect(throws: AuthError.self) {
            _ = try await authenticator.ensure()
        }
    }
}
