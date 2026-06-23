// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SessionSweep",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SessionSweep",
            path: "Sources/SessionSweep"
        )
    ]
)
