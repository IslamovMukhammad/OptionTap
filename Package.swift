// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OptionTap",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "OptionTap",
            path: "Sources/OptionTap"
        ),
        .testTarget(
            name: "OptionTapTests",
            dependencies: ["OptionTap"],
            path: "Tests/OptionTapTests"
        ),
    ]
)
