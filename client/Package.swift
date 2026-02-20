// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClawClient",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ClawClient", targets: ["ClawClient"]),
        .executable(name: "ClawApp", targets: ["ClawApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "ClawClient",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "ClawApp",
            dependencies: [
                "ClawClient",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "App",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "ClawClientTests",
            dependencies: ["ClawClient"]
        ),
    ]
)
