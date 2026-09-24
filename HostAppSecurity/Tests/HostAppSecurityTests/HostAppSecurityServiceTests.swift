import Foundation
import os
import Testing
@testable import HostAppSecurity

private struct SignerState: Sendable {
    var count = 0
    var addsMaterial = true
}

private final class SpySigner: EngineRequestSigning, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: SignerState())

    var addsMaterial: Bool {
        get { state.withLock { $0.addsMaterial } }
        set { state.withLock { $0.addsMaterial = newValue } }
    }

    func sign(_ request: inout URLRequest, basePath: URL) {
        let shouldAdd = state.withLock { value in
            value.count += 1
            return value.addsMaterial
        }
        guard shouldAdd else { return }
        request.setValue(
            "Signature keyid=\"device\",algorithm=\"rsa-sha256\",headers=\"Date Digest (request-target)\",signature=\"signed\"",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("Thu, 01 Jan 2026 00:00:00 GMT", forHTTPHeaderField: "Date")
        request.setValue("X", forHTTPHeaderField: "Digest")
    }

    func signCount() -> Int {
        state.withLock { $0.count }
    }
}

private final class SpyAuthentication: EngineAuthenticationReading, Sendable {
    private let state: OSAllocatedUnfairLock<HostAuthenticationState>

    init(_ state: HostAuthenticationState) {
        self.state = OSAllocatedUnfairLock(initialState: state)
    }

    func authenticationState() -> HostAuthenticationState {
        state.withLock { $0 }
    }

    func set(_ state: HostAuthenticationState) {
        self.state.withLock { $0 = state }
    }
}

private struct TransportState: Sendable {
    var requests: [URLRequest] = []
    var statusCode = 200
    var body = Data("ok".utf8)
    var error: URLError?
}

private final class SpyTransport: HTTPTransport, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: TransportState())

    var statusCode: Int {
        get { state.withLock { $0.statusCode } }
        set { state.withLock { $0.statusCode = newValue } }
    }

    var body: Data {
        get { state.withLock { $0.body } }
        set { state.withLock { $0.body = newValue } }
    }

    var error: URLError? {
        get { state.withLock { $0.error } }
        set { state.withLock { $0.error = newValue } }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let snapshot = state.withLock { value in
            value.requests.append(request)
            return value
        }
        if let error = snapshot.error {
            throw error
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://io.example/service")!,
            statusCode: snapshot.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (snapshot.body, response)
    }

    func sentRequests() -> [URLRequest] {
        state.withLock { $0.requests }
    }
}

private final class SpyDiagnostics: SecurityDiagnostics, Sendable {
    private let events = OSAllocatedUnfairLock(initialState: [SecurityDiagnosticEvent]())

    func log(_ event: SecurityDiagnosticEvent) {
        events.withLock { $0.append(event) }
    }

    func recorded() -> [SecurityDiagnosticEvent] {
        events.withLock { $0 }
    }
}

private final class SpyRecovery: SecurityRecoveryHandling, Sendable {
    private let paths = OSAllocatedUnfairLock(initialState: [RecoveryPath]())

    func recover(_ path: RecoveryPath) async {
        paths.withLock { $0.append(path) }
    }

    func recorded() -> [RecoveryPath] {
        paths.withLock { $0 }
    }
}

private struct Fixture {
    let basePath = URL(string: "https://io.example/api")!
    let signer = SpySigner()
    let authentication: SpyAuthentication
    let transport = SpyTransport()
    let diagnostics = SpyDiagnostics()
    let recovery = SpyRecovery()
    let service: HostAppSecurityService

    init(state: HostAuthenticationState = .unlocked) {
        authentication = SpyAuthentication(state)
        service = HostAppSecurityService(
            basePath: basePath,
            signer: signer,
            authentication: authentication,
            transport: transport,
            diagnostics: diagnostics,
            recovery: recovery
        )
    }

    func request(path: String = "/v1/rewards", method: String = "POST") -> URLRequest {
        var request = URLRequest(url: URL(string: basePath.absoluteString + path)!)
        request.httpMethod = method
        request.httpBody = Data("{\"amount\":1}".utf8)
        return request
    }
}

@Suite("Host app security service")
struct HostAppSecurityServiceTests {
    @Test("AC1 and AC2 sign with Engine material and send those headers")
    func signsRequestBeforeSend() async throws {
        let fixture = Fixture()
        let response = try await fixture.service.send(fixture.request())

        #expect(response.statusCode == 200)
        #expect(response.data == Data("ok".utf8))
        #expect(fixture.signer.signCount() == 1)
        let sent = try #require(fixture.transport.sentRequests().first)
        let authorization = try #require(sent.value(forHTTPHeaderField: "Authorization"))
        #expect(authorization.contains("Signature"))
        #expect(sent.value(forHTTPHeaderField: "Date") != nil)
        #expect(sent.value(forHTTPHeaderField: "Digest") == "X")
        #expect(fixture.diagnostics.recorded().isEmpty)
    }

    @Test("AC3 returns the non-Engine service body when the signed call succeeds")
    func returnsSuccessfulBody() async throws {
        let fixture = Fixture()
        fixture.transport.body = Data("{\"status\":\"accepted\"}".utf8)
        fixture.transport.statusCode = 201

        let response = try await fixture.service.send(fixture.request(path: "/v1/loyalty"))

        #expect(response.statusCode == 201)
        #expect(response.data == Data("{\"status\":\"accepted\"}".utf8))
    }

    @Test("AC4 missing signature material fails closed and logs only a code")
    func missingSignatureIsSafe() async {
        let fixture = Fixture()
        fixture.signer.addsMaterial = false

        await #expect(throws: HostSecurityError.signingFailed) {
            try await fixture.service.send(fixture.request())
        }
        #expect(fixture.transport.sentRequests().isEmpty)
        #expect(fixture.diagnostics.recorded() == [.signingFailed])
        #expect(HostSecurityError.signingFailed.safeMessage.contains("verify") )
        #expect(!fixture.diagnostics.recorded().map(\.logLine).joined().contains("Signature"))
    }

    @Test("AC4 verification failure logs the status and asks for re-authentication")
    func verificationFailureIsSafe() async {
        let fixture = Fixture()
        fixture.transport.statusCode = 401

        await #expect(throws: HostSecurityError.verificationFailed) {
            try await fixture.service.send(fixture.request())
        }
        #expect(fixture.diagnostics.recorded() == [.verificationFailed(statusCode: 401)])
        #expect(fixture.recovery.recorded() == [.reauthenticate])
        #expect(!HostSecurityError.verificationFailed.safeMessage.contains("401"))
    }

    @Test("AC4 transport failure has a safe error and no payload in the log")
    func transportFailureIsSafe() async {
        let fixture = Fixture()
        fixture.transport.error = URLError(.notConnectedToInternet)

        await #expect(throws: HostSecurityError.requestFailed) {
            try await fixture.service.send(fixture.request())
        }
        #expect(fixture.diagnostics.recorded() == [.requestFailed(statusCode: nil)])
        #expect(fixture.diagnostics.recorded().first?.logLine == "request_failed status=none")
    }

    @Test("AC5 locked session does not sign or send and starts re-authentication")
    func lockedSessionBlocksCall() async {
        let fixture = Fixture(state: .locked)

        await #expect(throws: HostSecurityError.sessionUnavailable(.reauthenticate)) {
            try await fixture.service.send(fixture.request())
        }
        #expect(fixture.signer.signCount() == 0)
        #expect(fixture.transport.sentRequests().isEmpty)
        #expect(fixture.recovery.recorded() == [.reauthenticate])
        #expect(fixture.diagnostics.recorded() == [.requestBlocked(.reauthenticate)])
    }

    @Test("AC5 unsecured device does not sign or send and starts re-binding")
    func unsecuredDeviceBlocksCall() async {
        let fixture = Fixture(state: .unsecured)

        await #expect(throws: HostSecurityError.sessionUnavailable(.rebind)) {
            try await fixture.service.send(fixture.request())
        }
        #expect(fixture.signer.signCount() == 0)
        #expect(fixture.transport.sentRequests().isEmpty)
        #expect(fixture.recovery.recorded() == [.rebind])
    }

    @Test("AC5 a lock after signing still prevents the send")
    func lockAfterSigningPreventsSend() async {
        let fixture = Fixture()
        let signer = LockingSigner(authentication: fixture.authentication)
        let service = HostAppSecurityService(
            basePath: fixture.basePath,
            signer: signer,
            authentication: fixture.authentication,
            transport: fixture.transport,
            diagnostics: fixture.diagnostics,
            recovery: fixture.recovery
        )

        await #expect(throws: HostSecurityError.sessionUnavailable(.reauthenticate)) {
            try await service.send(fixture.request())
        }
        #expect(fixture.transport.sentRequests().isEmpty)
        #expect(fixture.recovery.recorded() == [.reauthenticate])
    }

    @Test("AC6 one service signs every non-Engine call")
    func signingIsSharedAcrossServices() async throws {
        let fixture = Fixture()
        _ = try await fixture.service.send(fixture.request(path: "/v1/rewards"))
        _ = try await fixture.service.send(fixture.request(path: "/v1/loyalty", method: "GET"))

        #expect(fixture.signer.signCount() == 2)
        #expect(fixture.transport.sentRequests().count == 2)
        let paths = fixture.transport.sentRequests().compactMap { $0.url?.path }
        #expect(paths == ["/api/v1/rewards", "/api/v1/loyalty"])
    }
}

/// Signs, then locks the session, so the second gate must stop the send.
private final class LockingSigner: EngineRequestSigning, Sendable {
    let authentication: SpyAuthentication

    init(authentication: SpyAuthentication) {
        self.authentication = authentication
    }

    func sign(_ request: inout URLRequest, basePath: URL) {
        request.setValue("Signature keyid=\"device\"", forHTTPHeaderField: "Authorization")
        request.setValue("Thu, 01 Jan 2026 00:00:00 GMT", forHTTPHeaderField: "Date")
        request.setValue("X", forHTTPHeaderField: "Digest")
        authentication.set(.locked)
    }
}
