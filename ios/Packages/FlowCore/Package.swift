// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlowCore",
    platforms: [
        .iOS("18.0"),
        // macOS нужен только для того, чтобы гонять тесты командой `swift test`.
        .macOS("14.0"),
    ],
    products: [
        .library(name: "FlowCore", targets: ["FlowCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "FlowCore",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .testTarget(
            name: "FlowCoreTests",
            dependencies: ["FlowCore"]
        ),
    ]
)
