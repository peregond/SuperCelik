// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SerbiaID",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CPCSC",
            path: "Sources/CPCSC",
            linkerSettings: [.linkedFramework("PCSC")]
        ),
        .executableTarget(
            name: "SerbiaID",
            dependencies: ["CPCSC"],
            path: "Sources/SerbiaID",
            resources: [.copy("Resources")]
        )
    ]
)
