// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "StatusGlance",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "StatusGlance",
            path: "Sources/StatusGlance"
        )
    ]
)
