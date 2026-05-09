// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "YTDLFront",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "YTDLFront", targets: ["YTDLFront"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "YTDLFront",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/YTDLFront"
        )
    ]
)
