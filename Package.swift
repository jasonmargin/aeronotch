// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AeroNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AeroNotch",
            path: "Sources/AeroNotch"
        )
    ]
)
