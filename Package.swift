// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SerbiaID",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SerbiaID",
            path: "Sources/SerbiaID",
            resources: [.copy("Resources")]
        )
    ]
)
