// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HostAppSecurity",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(name: "HostAppSecurity", targets: ["HostAppSecurity"])
    ],
    targets: [
        .target(name: "HostAppSecurity"),
        .testTarget(
            name: "HostAppSecurityTests",
            dependencies: ["HostAppSecurity"]
        )
    ]
)
