// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Quota",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Quota", targets: ["ClaudeBar"])],
    targets: [
        .executableTarget(
            name: "ClaudeBar",
            path: "Sources/ClaudeBar"
        ),
        .testTarget(name: "ClaudeBarTests", dependencies: ["ClaudeBar"])
    ]
)
