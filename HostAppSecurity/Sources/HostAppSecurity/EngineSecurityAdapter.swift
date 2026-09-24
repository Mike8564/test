#if canImport(EngineSDK)
import EngineSDK
import Foundation

/// Forwards signing to `Engine.shared.operations.signEngineURLRequest`.
public struct EngineRequestSigner: EngineRequestSigning {
    public init() {}

    public func sign(_ request: inout URLRequest, basePath: URL) {
        Engine.shared.operations.signEngineURLRequest(&request, basePath: basePath)
    }
}

/// Reads `Engine.shared.state.authenticationState`.
public struct EngineAuthenticationReader: EngineAuthenticationReading {
    public init() {}

    public func authenticationState() -> HostAuthenticationState {
        switch Engine.shared.state.authenticationState {
        case .unsecured:
            .unsecured
        case .locked:
            .locked
        case .unlocked:
            .unlocked
        @unknown default:
            .locked
        }
    }
}

public extension HostAppSecurityService {
    /// Service wired to Engine signing and authentication state.
    ///
    /// `basePath` is the URL prefix excluded from the signature, matching the
    /// Engine operator. Feature code calls `send` and does not sign requests itself.
    static func engineBacked(
        basePath: URL,
        session: URLSession = .shared,
        recovery: any SecurityRecoveryHandling
    ) -> HostAppSecurityService {
        HostAppSecurityService(
            basePath: basePath,
            signer: EngineRequestSigner(),
            authentication: EngineAuthenticationReader(),
            transport: URLSessionTransport(session: session),
            diagnostics: OSLogSecurityDiagnostics(),
            recovery: recovery
        )
    }
}
#endif
