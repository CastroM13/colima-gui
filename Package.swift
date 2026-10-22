// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ColimaManager",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ColimaManager", targets: ["ColimaManager"])
    ],
    targets: [
        .executableTarget(
            name: "ColimaManager",
            path: "Sources/ColimaManager"
        ),
        .testTarget(name: "ColimaManagerTests", dependencies: ["ColimaManager"])
    ]
)
