# Host app security service

The host app is our app. Engine is the SDK already started at launch. This package is the one place our app uses when a screen we built needs to call a non-Engine service through the integration and orchestration (I&O) layer.

Engine journeys sign their own calls. A screen we built does not. I&O trusts a call when it carries the same device signature Engine already uses. This service checks the Engine session, asks Engine to sign, sends the request, and returns a safe error when that cannot happen.

Engine is not started again. The service uses the `Engine.shared` instance from launch.

## What the app does

Create the service once, after Engine startup has finished. Keep that object for the whole app.

```swift
let security = HostAppSecurityService.engineBacked(
    basePath: basePath,
    recovery: ClosureRecoveryHandler { path in
        await MainActor.run {
            switch path {
            case .reauthenticate:
                // Present the same app-unlock flow the app already uses.
                break
            case .rebind:
                // Present device setup.
                break
            }
        }
    }
)
```

`basePath` is the URL prefix Engine leaves out of the signature. Start from the `serverBasePath` already passed in `AppConfiguration.ServerContextSettings`. If I&O strips a prefix such as `/mobile-api` before it checks the path, include that prefix in `basePath`. Every direct call URL has to sit under it.

A feature builds a normal request and passes it to `send`. `security` is the service created above. `send` is the line that uses it.

```swift
var request = URLRequest(url: basePath.appending(path: "v1/rewards"))
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.httpBody = body

do {
    let response = try await security.send(request)
    // response.data is the service body. response.statusCode is the 2xx status.
} catch {
    let error = error as HostSecurityError
    show(error.safeMessage)
}
```

The feature does not add signature headers and does not call `signEngineURLRequest`.

## Files

| File | Role |
|---|---|
| `Sources/HostAppSecurity/HostAppSecurityService.swift` | Session check, signing gate, send, safe errors |
| `Sources/HostAppSecurity/EngineSecurityAdapter.swift` | Connects the service to `Engine.shared` when `EngineSDK` is linked |

The adapter file is compiled only in an app that already imports `EngineSDK`.

## What the service stores

`HostAppSecurityService` does not name Engine itself. Creation passes in five dependencies:

| Stored value | Job |
|---|---|
| `basePath` | Prefix excluded from the signature. Also the prefix a request URL must use. |
| `signer` | Adds the Engine signature headers. |
| `authentication` | Reads `unlocked`, `locked`, or `unsecured`. |
| `transport` | Performs the HTTP call. Default is `URLSession`. |
| `diagnostics` | Writes one safe log line. |
| `recovery` | Asks the app to present unlock or device setup. |

`engineBacked` fills these with:

- `EngineRequestSigner`, which calls `Engine.shared.operations.signEngineURLRequest(&request, basePath:)`
- `EngineAuthenticationReader`, which reads `Engine.shared.state.authenticationState`
- `URLSession.shared`
- `OSLogSecurityDiagnostics`
- the recovery closure the app passes in

An unknown future authentication state is treated as `locked`, so the call stops and recovery is re-authentication.

## What `send` does

`send` takes the feature's `URLRequest`. It returns `HostServiceResponse` (`data` and `statusCode`) or throws `HostSecurityError`.

1. **Read the session.** `unlocked` continues. `locked` logs `request_blocked recovery=reauthenticate`, runs the recovery handler, and throws `sessionUnavailable(.reauthenticate)`. `unsecured` does the same with `rebind`. Nothing is signed or sent.
2. **Copy the request.** Signing mutates the request. The feature's original value stays as the feature built it.
3. **Require the URL to be under `basePath`.** The scheme must be `http` or `https`. One trailing slash is removed from `basePath`. The request URL must equal that prefix or start with `prefix + "/"`. Otherwise the method logs `signing_failed` and throws `signingFailed`. The signer is not called.
4. **Sign.** `signer.sign` is the only signing call. Engine adds `Authorization` (a `Signature` value, RSA-SHA256), `Date`, and `Digest`.
5. **Require those headers.** `Authorization` must contain `Signature`. `Date` and `Digest` must be non-empty. If any of that is missing, the method logs `signing_failed` and throws `signingFailed`. The request is not sent.
6. **Read the session again.** If the app locked or became unsecured while signing, recovery runs and the signed request is dropped. The network call does not start.
7. **Send.** `URLSession.data(for:)` performs the call. A network failure logs `request_failed status=none` and throws `requestFailed`.
8. **Sort the status.** `401` and `403` log `verification_failed` with that status, run re-authentication, and throw `verificationFailed`. Any other non-2xx status logs `request_failed` with the status and throws `requestFailed`. A 2xx status returns the body and status code.

## Errors and logs

`safeMessage` is the text for the screen:

| Error | Message |
|---|---|
| `sessionUnavailable(.reauthenticate)` | Please sign in again to continue. |
| `sessionUnavailable(.rebind)` | This device needs to be set up again before continuing. |
| `signingFailed`, `verificationFailed` | We couldn't verify this request. Please try again. |
| `requestFailed` | Something went wrong. Please try again. |

The log line is a fixed phrase. A status code is included only for verification failure and for an HTTP failure that is not `401` or `403`. The URL, headers, and body are not logged.

## What this service does not do

- It does not start Engine.
- It does not launch an Engine journey. The app presents unlock or device setup from the recovery closure.
- It does not implement the signature. Engine's `signEngineURLRequest` does that.
- It does not read a separate "server token valid" or "device binding status" API. The documented session read is `Engine.shared.state.authenticationState`. A rejection by I&O arrives as `401` or `403`.
