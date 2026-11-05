// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZeroTab",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "ZeroTab", targets: ["ZeroTab"])],
    targets: [
        .target(name: "ZeroTabCore"),
        .executableTarget(name: "ZeroTab", dependencies: ["ZeroTabCore"]),
        .testTarget(name: "ZeroTabCoreTests", dependencies: ["ZeroTabCore"]),
        .testTarget(name: "ZeroTabTests", dependencies: ["ZeroTab"])
    ],
    swiftLanguageModes: [.v5]
)
