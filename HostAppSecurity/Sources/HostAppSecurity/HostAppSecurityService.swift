import Foundation
import os

/// Recovery the host presents when a direct call must not proceed.
///
/// `reauthenticate` matches an app-unlock style session recovery.
/// `rebind` matches a device that has no authentication method set up.
public enum RecoveryPath: Equatable, Sendable {
    case reauthenticate
    case rebind
}

/// Local session snapshot used to decide whether a direct call may be signed.
///
/// Mirrors the SDK authentication state: `unsecured`, `locked`, and `unlocked`.
public enum HostAuthenticationState: Equatable, Sendable {
    case unsecured
    case locked
    case unlocked
}

public struct HostServiceResponse: Equatable, Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public enum HostSecurityError: Error, Equatable, Sendable {
    case sessionUnavailable(RecoveryPath)
    case signingFailed
    case verificationFailed
    case requestFailed

    /// Text safe to show in the host UI. Contains no request or signature material.
    public var safeMessage: String {
        switch self {
        case .sessionUnavailable(.reauthenticate):
            "Please sign in again to continue."
        case .sessionUnavailable(.rebind):
            "This device needs to be set up again before continuing."
        case .signingFailed, .verificationFailed:
            "We couldn’t verify this request. Please try again."
        case .requestFailed:
            "Something went wrong. Please try again."
        }
    }
}

public enum SecurityDiagnosticEvent: Equatable, Sendable {
    case requestBlocked(RecoveryPath)
    case signingFailed
    case verificationFailed(statusCode: Int)
    case requestFailed(statusCode: Int?)

    /// Fixed diagnostic line. Status codes only; no URLs, headers, or bodies.
    public var logLine: String {
        switch self {
        case .requestBlocked(.reauthenticate):
            "request_blocked recovery=reauthenticate"
        case .requestBlocked(.rebind):
            "request_blocked recovery=rebind"
        case .signingFailed:
            "signing_failed"
        case .verificationFailed(let statusCode):
            "verification_failed status=\(statusCode)"
        case .requestFailed(let statusCode):
            "request_failed status=\(statusCode.map(String.init) ?? "none")"
        }
    }
}

public protocol EngineRequestSigning: Sendable {
    /// Adds Engine signature headers to `request` using `basePath` as the unsigned prefix.
    func sign(_ request: inout URLRequest, basePath: URL)
}

public protocol EngineAuthenticationReading: Sendable {
    func authenticationState() -> HostAuthenticationState
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public protocol SecurityDiagnostics: Sendable {
    func log(_ event: SecurityDiagnosticEvent)
}

public protocol SecurityRecoveryHandling: Sendable {
    func recover(_ path: RecoveryPath) async
}

public protocol HostSecureTransporting: Sendable {
    func send(_ request: URLRequest) async throws(HostSecurityError) -> HostServiceResponse
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

public struct OSLogSecurityDiagnostics: SecurityDiagnostics {
    private let logger: Logger

    public init(subsystem: String = "host-app-security", category: String = "request-signing") {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func log(_ event: SecurityDiagnosticEvent) {
        let line = event.logLine
        logger.log("\(line, privacy: .public)")
    }
}

public struct ClosureRecoveryHandler: SecurityRecoveryHandling {
    private let handler: @Sendable (RecoveryPath) async -> Void

    public init(_ handler: @escaping @Sendable (RecoveryPath) async -> Void) {
        self.handler = handler
    }

    public func recover(_ path: RecoveryPath) async {
        await handler(path)
    }
}

/// Signs and sends host calls to non-Engine services on the I&O layer.
///
/// Feature code builds a `URLRequest` and calls `send`. Signing stays in this type,
/// which delegates the cryptographic headers to the Engine operator.
public struct HostAppSecurityService: HostSecureTransporting {
    private let basePath: URL
    private let signer: any EngineRequestSigning
    private let authentication: any EngineAuthenticationReading
    private let transport: any HTTPTransport
    private let diagnostics: any SecurityDiagnostics
    private let recovery: any SecurityRecoveryHandling

    public init(
        basePath: URL,
        signer: any EngineRequestSigning,
        authentication: any EngineAuthenticationReading,
        transport: any HTTPTransport = URLSessionTransport(),
        diagnostics: any SecurityDiagnostics = OSLogSecurityDiagnostics(),
        recovery: any SecurityRecoveryHandling
    ) {
        self.basePath = basePath
        self.signer = signer
        self.authentication = authentication
        self.transport = transport
        self.diagnostics = diagnostics
        self.recovery = recovery
    }

    public func send(_ request: URLRequest) async throws(HostSecurityError) -> HostServiceResponse {
        if let blocked = await blockedSession() {
            return try await failSession(blocked)
        }

        var signedRequest = request
        guard requestIsUnderBasePath(signedRequest) else {
            diagnostics.log(.signingFailed)
            throw HostSecurityError.signingFailed
        }

        signer.sign(&signedRequest, basePath: basePath)
        guard signedRequest.hasRequiredSignatureHeaders else {
            diagnostics.log(.signingFailed)
            throw HostSecurityError.signingFailed
        }

        if let blocked = await blockedSession() {
            return try await failSession(blocked)
        }

        let outcome: (Data, HTTPURLResponse)
        do {
            outcome = try await transport.send(signedRequest)
        } catch {
            diagnostics.log(.requestFailed(statusCode: nil))
            throw HostSecurityError.requestFailed
        }

        let statusCode = outcome.1.statusCode
        if statusCode == 401 || statusCode == 403 {
            diagnostics.log(.verificationFailed(statusCode: statusCode))
            await recovery.recover(.reauthenticate)
            throw HostSecurityError.verificationFailed
        }
        guard (200 ..< 300).contains(statusCode) else {
            diagnostics.log(.requestFailed(statusCode: statusCode))
            throw HostSecurityError.requestFailed
        }
        return HostServiceResponse(data: outcome.0, statusCode: statusCode)
    }

    private func blockedSession() async -> RecoveryPath? {
        switch authentication.authenticationState() {
        case .unlocked:
            nil
        case .locked:
            .reauthenticate
        case .unsecured:
            .rebind
        }
    }

    private func failSession(_ path: RecoveryPath) async throws(HostSecurityError) -> HostServiceResponse {
        diagnostics.log(.requestBlocked(path))
        await recovery.recover(path)
        throw HostSecurityError.sessionUnavailable(path)
    }

    private func requestIsUnderBasePath(_ request: URLRequest) -> Bool {
        guard let url = request.url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return false
        }
        let prefix = basePath.absoluteString.hasSuffix("/")
            ? String(basePath.absoluteString.dropLast())
            : basePath.absoluteString
        let absolute = url.absoluteString
        return absolute == prefix || absolute.hasPrefix(prefix + "/")
    }
}

private extension URLRequest {
    var hasRequiredSignatureHeaders: Bool {
        guard
            let authorization = value(forHTTPHeaderField: "Authorization"),
            authorization.contains("Signature"),
            let date = value(forHTTPHeaderField: "Date"),
            !date.isEmpty,
            let digest = value(forHTTPHeaderField: "Digest"),
            !digest.isEmpty
        else {
            return false
        }
        return true
    }
}
